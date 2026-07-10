import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { parseCoachChatRequest } from "../_shared/contracts/coach_chat_v1.ts";
import { generateCoachChat } from "../_shared/providers/coach_chat_provider.ts";

const headers = { "Content-Type": "application/json" };
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers });

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
  let input;
  try {
    input = parseCoachChatRequest(await request.json());
  } catch {
    return reply(422, { error: "invalid_chat_request" });
  }
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: prepared, error: prepareError } = await service.rpc("prepare_coach_chat", {
    target_user_id: userData.user.id,
    target_thread_id: input.thread_id,
    question: input.question,
    coaching_timezone: input.timezone,
    request_idempotency_key: input.idempotency_key,
  });
  if (prepareError || !prepared) return reply(422, { error: "chat_unavailable" });
  if (prepared.replayed) {
    const { data } = await userClient.from("coach_messages").select().eq(
      "thread_id",
      input.thread_id,
    ).order("created_at");
    return reply(200, { schema_version: "1.0", messages: data ?? [], replayed: true });
  }
  const started = performance.now();
  try {
    const generation = await generateCoachChat(
      input.question,
      prepared.context as Record<string, unknown>,
    );
    const { data: persisted, error } = await service.rpc("persist_coach_chat_result", {
      target_user_id: userData.user.id,
      target_thread_id: input.thread_id,
      question: input.question,
      request_idempotency_key: input.idempotency_key,
      snapshot_id: prepared.feature_snapshot_id,
      policy_id: prepared.policy_evaluation_id,
      answer_payload: generation.answer,
      run_latency_ms: Math.round(performance.now() - started),
      run_provider: generation.provider,
      run_model: generation.model,
      run_input_units: generation.inputUnits,
      run_output_units: generation.outputUnits,
      run_estimated_cost_usd: generation.estimatedCostUsd,
    });
    if (error || !persisted) return reply(422, { error: "chat_rejected" });
    return reply(200, {
      schema_version: "1.0",
      message: { id: persisted.assistant_message_id, role: "assistant", ...generation.answer },
      budget_warning: prepared.budget_warning,
      replayed: false,
    });
  } catch {
    return reply(503, { error: "chat_unavailable" });
  }
});
