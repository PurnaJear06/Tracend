import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { parseCoachDecision, type PolicyOutcome } from "../_shared/contracts/coach_decision_v1.ts";
import { parseCoachRequest } from "../_shared/contracts/coach_request_v1.ts";
import { createCoachModelProvider } from "../_shared/providers/create_coach_model_provider.ts";

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
    input = parseCoachRequest(await request.json());
  } catch {
    return reply(422, { error: "invalid_coach_request" });
  }
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: prepared, error: prepareError } = await service.rpc(
    "prepare_daily_coaching",
    {
      target_user_id: userData.user.id,
      coaching_date: input.local_date,
      coaching_timezone: input.timezone,
      request_idempotency_key: input.idempotency_key,
    },
  );
  if (prepareError || !prepared) return reply(422, { error: "coaching_unavailable" });
  if (prepared.replayed && prepared.model_run_id) {
    const { data } = await userClient.from("coach_decisions").select()
      .eq("model_run_id", prepared.model_run_id).maybeSingle();
    return data
      ? reply(200, { schema_version: "1.0", decision: data, replayed: true })
      : reply(409, { error: "decision_pending" });
  }

  const started = performance.now();
  try {
    const outcome = prepared.policy_outcome as PolicyOutcome;
    const evidence = prepared.permitted_evidence as string[];
    const { data: snapshot, error: snapshotError } = await service.from("feature_snapshots")
      .select("features")
      .eq("id", prepared.feature_snapshot_id)
      .eq("user_id", userData.user.id)
      .single();
    if (snapshotError || !snapshot || typeof snapshot.features !== "object") {
      throw new Error("feature_context_unavailable");
    }
    const generated = await createCoachModelProvider().generateDecision({
      decisionKind: "daily",
      featureSnapshotId: prepared.feature_snapshot_id,
      policyEvaluationId: prepared.policy_evaluation_id,
      policyOutcome: outcome,
      permittedEvidence: evidence,
      featureContext: snapshot.features as Record<string, unknown>,
      missingData: prepared.missing_data ?? [],
    });
    const decision = parseCoachDecision(generated.decision, evidence, outcome);
    const persistedPayload = { ...decision, local_date: input.local_date };
    const { data: persisted, error } = await service.rpc(
      "persist_daily_coaching_result_v2",
      {
        target_user_id: userData.user.id,
        snapshot_id: prepared.feature_snapshot_id,
        policy_id: prepared.policy_evaluation_id,
        request_idempotency_key: input.idempotency_key,
        decision_payload: persistedPayload,
        run_latency_ms: Math.round(performance.now() - started),
        run_provider: generated.provider,
        run_model: generated.model,
        run_input_units: generated.inputUnits,
        run_output_units: generated.outputUnits,
        run_estimated_cost_usd: generated.estimatedCostUsd,
      },
    );
    if (error || !persisted) return reply(422, { error: "decision_rejected" });
    return reply(200, {
      schema_version: "1.0",
      decision: { ...decision, id: persisted.decision_id, local_date: input.local_date },
      replayed: false,
    });
  } catch {
    await service.rpc("persist_failed_coaching_run_v2", {
      target_user_id: userData.user.id,
      snapshot_id: prepared.feature_snapshot_id,
      policy_id: prepared.policy_evaluation_id,
      request_idempotency_key: input.idempotency_key,
      run_latency_ms: Math.round(performance.now() - started),
      error_code: "provider_or_validation_failed",
      run_provider: Deno.env.get("COACH_MODEL_PROVIDER") === "gemini" ? "gemini" : "mock",
      run_model: Deno.env.get("COACH_MODEL_PROVIDER") === "gemini"
        ? (Deno.env.get("GEMINI_MODEL") || "unconfigured")
        : "deterministic-mock-v1",
    });
    return reply(503, { error: "coaching_unavailable" });
  }
});
