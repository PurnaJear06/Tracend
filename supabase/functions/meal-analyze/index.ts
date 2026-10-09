import { createLogger, extractCorrelationId } from "../_shared/logger.ts";
import { analyzeMealImage } from "../_shared/providers/gemini_meal_vision_provider.ts";
import { analyzeGroqMealImage } from "../_shared/providers/groq_meal_vision_provider.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { captureException } from "../_shared/sentry.ts";
import { isUserStorageKey } from "../_shared/storage_keys.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  const correlationId = extractCorrelationId(request);
  const log = createLogger(correlationId);
  const started = performance.now();
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  let auth;
  try {
    auth = await requireAuth(request);
  } catch (e) {
    if (e instanceof AuthError) return reply(e.status, { error: e.message });
    throw e;
  }
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    log.warn("invalid_meal_request");
    return reply(422, { error: "invalid_meal_request" });
  }
  if (
    body.schema_version !== "1.0" || typeof body.meal_id !== "string" || !uuid.test(body.meal_id)
  ) {
    return reply(422, { error: "invalid_meal_request" });
  }
  const { error: budgetError } = await auth.serviceClient.rpc("assert_owner_ai_budget", {
    target_user_id: auth.userId,
  });
  if (budgetError) return reply(429, { error: "ai_usage_limit" });
  const { data: meal, error: mealError } = await auth.serviceClient.from("meals")
    .select("id,status,source,media_objects!inner(object_key,content_type,byte_size)")
    .eq("id", body.meal_id).eq("user_id", auth.userId).single();
  if (mealError || !meal || meal.status !== "draft" || meal.source !== "photo_analysis") {
    return reply(404, { error: "meal_not_found" });
  }
  const media = meal.media_objects as unknown as Record<string, unknown>;
  if (!isUserStorageKey(auth.userId, media.object_key)) {
    log.warn("unsafe_meal_object_key");
    return reply(404, { error: "meal_not_found" });
  }
  const { data: image, error: downloadError } = await auth.serviceClient.storage.from("meal-images")
    .download(media.object_key);
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
    const visionLatency = Math.round(performance.now() - started);
    const recordUsage = () =>
      auth.serviceClient.rpc("record_ai_usage_event", {
        target_user_id: auth.userId,
        run_purpose: "meal_vision",
        run_provider: provider,
        run_model: result.model,
        run_input_units: result.inputUnits,
        run_output_units: result.outputUnits,
        run_estimated_cost_usd: result.estimatedCostUsd,
        run_latency_ms: visionLatency,
      });
    if (result.candidates.length === 0) {
      // The model looked and found no food. That is an answer, not an outage;
      // the call still counts toward the budget.
      await recordUsage();
      // Nothing to review, so the draft goes, the way the app deletes a meal
      // (which also schedules the photo for deletion). A failed removal
      // leaves a draft with no candidates; the answer still stands.
      const { error: discardError } = await auth.userClient.rpc("delete_my_meal", {
        target_meal_id: body.meal_id,
      });
      if (discardError) log.warn("meal_no_food_draft_not_removed");
      log.info("meal_analysis_no_food", {
        latency_ms: visionLatency,
        provider,
        model: result.model,
      });
      return reply(422, { error: "meal_no_food_found" });
    }
    const persistenceCandidates = result.candidates.map((
      { assumptions: _assumptions, question: _question, ...candidate },
    ) => candidate);
    const { error } = await auth.serviceClient.rpc("persist_meal_photo_candidates", {
      target_user_id: auth.userId,
      target_meal_id: body.meal_id,
      candidates: persistenceCandidates,
      run_provider: provider,
      run_model: result.model,
    });
    if (error) return reply(422, { error: "meal_analysis_rejected" });
    await recordUsage();
    log.info("meal_analysis_complete", {
      latency_ms: visionLatency,
      provider,
      model: result.model,
    });
    return reply(200, {
      schema_version: "1.0",
      meal_id: body.meal_id,
      candidates: result.candidates,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.startsWith("meal_vision_request_failed:429:")) {
      // Groq's free tier allows about one photo a minute. Busy, not broken.
      log.warn("meal_analysis_busy", { detail: message });
      return reply(429, { error: "meal_vision_busy" });
    }
    captureException(err, {
      userId: auth.userId,
      functionName: "meal-analyze",
      correlationId,
      mealId: body.meal_id,
    });
    log.error("meal_analysis_unavailable", {
      detail: message,
      latency_ms: Math.round(performance.now() - started),
    });
    return reply(503, { error: "meal_analysis_unavailable" });
  }
});
