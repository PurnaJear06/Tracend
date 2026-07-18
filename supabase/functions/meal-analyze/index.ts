import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { analyzeMealImage } from "../_shared/providers/gemini_meal_vision_provider.ts";
import { analyzeGroqMealImage } from "../_shared/providers/groq_meal_vision_provider.ts";

const headers = { "Content-Type": "application/json" };
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  if (!url || !key || !serviceKey || !authorization) {
    return reply(401, { error: "authentication_required" });
  }
  const userClient = createClient(url, key, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return reply(401, { error: "invalid_session" });
  let body: Record<string, unknown>;
  const started = performance.now();
  try {
    body = await request.json();
  } catch {
    return reply(422, { error: "invalid_meal_request" });
  }
  if (
    body.schema_version !== "1.0" || typeof body.meal_id !== "string" || !uuid.test(body.meal_id)
  ) {
    return reply(422, { error: "invalid_meal_request" });
  }
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });
  // Budget check temporarily disabled — remove after testing.
  // const { error: budgetError } = await service.rpc("assert_owner_ai_budget", {
  //   target_user_id: userData.user.id,
  // });
  // if (budgetError) return reply(429, { error: "ai_usage_limit" });
  const { data: meal, error: mealError } = await service.from("meals")
    .select("id,status,source,media_objects!inner(object_key,content_type,byte_size)")
    .eq("id", body.meal_id).eq("user_id", userData.user.id).single();
  if (mealError || !meal || meal.status !== "draft" || meal.source !== "photo_analysis") {
    return reply(404, { error: "meal_not_found" });
  }
  const media = meal.media_objects as unknown as Record<string, unknown>;
  const { data: image, error: downloadError } = await service.storage.from("meal-images").download(
    media.object_key as string,
  );
  if (downloadError || !image) return reply(503, { error: "meal_image_unavailable" });
  try {
    const provider = Deno.env.get("MEAL_VISION_PROVIDER") === "groq" ? "groq" : "gemini";
    const result = provider === "groq"
      ? await analyzeGroqMealImage(
        new Uint8Array(await image.arrayBuffer()),
        media.content_type as string,
      )
      : await analyzeMealImage(
        new Uint8Array(await image.arrayBuffer()),
        media.content_type as string,
      );
    const persistenceCandidates = result.candidates.map((
      { assumptions: _assumptions, question: _question, ...candidate },
    ) => candidate);
    const { error } = await service.rpc("persist_meal_photo_candidates", {
      target_user_id: userData.user.id,
      target_meal_id: body.meal_id,
      candidates: persistenceCandidates,
      run_provider: provider,
      run_model: result.model,
    });
    if (error) return reply(422, { error: "meal_analysis_rejected" });
    await service.rpc("record_ai_usage_event", {
      target_user_id: userData.user.id,
      run_purpose: "meal_vision",
      run_provider: provider,
      run_model: result.model,
      run_input_units: result.inputUnits,
      run_output_units: result.outputUnits,
      run_estimated_cost_usd: result.estimatedCostUsd,
      run_latency_ms: Math.round(performance.now() - started),
    });
    return reply(200, {
      schema_version: "1.0",
      meal_id: body.meal_id,
      candidates: result.candidates,
    });
  } catch {
    return reply(503, { error: "meal_analysis_unavailable" });
  }
});
