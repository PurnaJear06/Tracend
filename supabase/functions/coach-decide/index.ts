import { parseCoachDecision, type PolicyOutcome } from "../_shared/contracts/coach_decision_v1.ts";
import { parseCoachRequest } from "../_shared/contracts/coach_request_v1.ts";
import type { CoachModelGeneration } from "../_shared/providers/coach_model_provider.ts";
import { createCoachModelProvider } from "../_shared/providers/create_coach_model_provider.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";

const SAFE_REASON = /^[a-z][a-z0-9_]{0,60}$/;
const SAFE_EVIDENCE_CODE = /^[A-Z][A-Z_]{0,39}$/;

// Maps a generation/validation failure to a sanitized, persistable token.
// Only fixed snake_case tokens (contract + provider errors) pass through;
// anything else collapses to `provider_or_validation_failed`, so no model
// output or user content ever reaches telemetry.
function failureReason(
  error: unknown,
  generated: CoachModelGeneration | undefined,
  permitted: readonly string[],
): string {
  if (!(error instanceof Error)) return "provider_or_validation_failed";
  if (error.name === "AbortError") return "deepseek_timeout";
  if (error instanceof SyntaxError) return "deepseek_json_parse_failed";
  if (!SAFE_REASON.test(error.message)) return "provider_or_validation_failed";
  if (error.message === "unpermitted_decision_evidence" && generated) {
    const items = (generated.decision as { evidence?: unknown }).evidence;
    if (Array.isArray(items)) {
      for (const item of items) {
        const code = typeof item === "object" && item !== null
          ? (item as { code?: unknown }).code
          : undefined;
        if (
          typeof code === "string" && SAFE_EVIDENCE_CODE.test(code) &&
          !permitted.includes(code)
        ) {
          return `unpermitted_evidence_${code.toLowerCase()}`;
        }
      }
    }
  }
  return error.message;
}

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
  let generated: CoachModelGeneration | undefined;
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
    generated = await createCoachModelProvider().generateDecision({
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
    if (error || !persisted) {
      await auth.serviceClient.rpc("persist_failed_coaching_run_v2", {
        target_user_id: auth.userId,
        snapshot_id: prepared.feature_snapshot_id,
        policy_id: prepared.policy_evaluation_id,
        request_idempotency_key: input.idempotency_key,
        run_latency_ms: Math.round(performance.now() - started),
        error_code: "decision_rejected",
        run_provider: generated.provider,
        run_model: generated.model,
      });
      return reply(422, { error: "decision_rejected" });
    }
    return reply(200, {
      schema_version: "1.0",
      decision: { ...decision, id: persisted.decision_id, local_date: input.local_date },
      replayed: false,
    });
  } catch (error) {
    const reason = failureReason(
      error,
      generated,
      (prepared.permitted_evidence as string[] | undefined) ?? [],
    );
    console.error(`coach-decide failed: ${reason}`);
    await auth.serviceClient.rpc("persist_failed_coaching_run_v2", {
      target_user_id: auth.userId,
      snapshot_id: prepared.feature_snapshot_id,
      policy_id: prepared.policy_evaluation_id,
      request_idempotency_key: input.idempotency_key,
      run_latency_ms: Math.round(performance.now() - started),
      error_code: reason,
      run_provider: Deno.env.get("COACH_MODEL_PROVIDER") === "gemini"
        ? "gemini"
        : Deno.env.get("COACH_MODEL_PROVIDER") === "groq"
        ? "groq"
        : Deno.env.get("COACH_MODEL_PROVIDER") === "deepseek"
        ? "deepseek"
        : "mock",
      run_model: Deno.env.get("COACH_MODEL_PROVIDER") === "gemini"
        ? (Deno.env.get("GEMINI_MODEL") || "unconfigured")
        : Deno.env.get("COACH_MODEL_PROVIDER") === "groq"
        ? (Deno.env.get("GROQ_MODEL") || "unconfigured")
        : Deno.env.get("COACH_MODEL_PROVIDER") === "deepseek"
        ? (Deno.env.get("DEEPSEEK_MODEL") || "unconfigured")
        : "deterministic-mock-v1",
    });
    return reply(503, { error: "coaching_unavailable" });
  }
});
