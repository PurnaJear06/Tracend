import { parseCoachDecision, type PolicyOutcome } from "../_shared/contracts/coach_decision_v1.ts";
import { parseCoachRequest } from "../_shared/contracts/coach_request_v1.ts";
import { createCoachModelProvider } from "../_shared/providers/create_coach_model_provider.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  let auth;
  try {
    auth = await requireAuth(request);
  } catch (e) {
    if (e instanceof AuthError) return reply(e.status, { error: e.message });
    throw e;
  }

  let input;
  try {
    input = parseCoachRequest(await request.json());
  } catch {
    return reply(422, { error: "invalid_coach_request" });
  }
  const { data: prepared, error: prepareError } = await auth.serviceClient.rpc(
    "prepare_daily_coaching",
    {
      target_user_id: auth.userId,
      coaching_date: input.local_date,
      coaching_timezone: input.timezone,
      request_idempotency_key: input.idempotency_key,
    },
  );
  if (prepareError || !prepared) return reply(422, { error: "coaching_unavailable" });
  if (prepared.replayed && prepared.model_run_id) {
    const { data } = await auth.userClient.from("coach_decisions").select()
      .eq("model_run_id", prepared.model_run_id).maybeSingle();
    return data
      ? reply(200, { schema_version: "1.0", decision: data, replayed: true })
      : reply(409, { error: "decision_pending" });
  }

  const started = performance.now();
  try {
    const outcome = prepared.policy_outcome as PolicyOutcome;
    const evidence = prepared.permitted_evidence as string[];
    const { data: snapshot, error: snapshotError } = await auth.serviceClient.from(
      "feature_snapshots",
    )
      .select("features")
      .eq("id", prepared.feature_snapshot_id)
      .eq("user_id", auth.userId)
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
    const { data: persisted, error } = await auth.serviceClient.rpc(
      "persist_daily_coaching_result_v2",
      {
        target_user_id: auth.userId,
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
    await auth.serviceClient.rpc("persist_failed_coaching_run_v2", {
      target_user_id: auth.userId,
      snapshot_id: prepared.feature_snapshot_id,
      policy_id: prepared.policy_evaluation_id,
      request_idempotency_key: input.idempotency_key,
      run_latency_ms: Math.round(performance.now() - started),
      error_code: "provider_or_validation_failed",
      run_provider: Deno.env.get("COACH_MODEL_PROVIDER") === "gemini"
        ? "gemini"
        : Deno.env.get("COACH_MODEL_PROVIDER") === "groq"
        ? "groq"
        : "mock",
      run_model: Deno.env.get("COACH_MODEL_PROVIDER") === "gemini"
        ? (Deno.env.get("GEMINI_MODEL") || "unconfigured")
        : Deno.env.get("COACH_MODEL_PROVIDER") === "groq"
        ? (Deno.env.get("GROQ_MODEL") || "unconfigured")
        : "deterministic-mock-v1",
    });
    return reply(503, { error: "coaching_unavailable" });
  }
});
