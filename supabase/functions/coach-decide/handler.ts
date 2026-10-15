import { parseCoachDecision, type PolicyOutcome } from "../_shared/contracts/coach_decision_v1.ts";
import { parseCoachRequest } from "../_shared/contracts/coach_request_v1.ts";
import type { CoachModelGeneration } from "../_shared/providers/coach_model_provider.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { AiBudget } from "../_shared/ai_budget.ts";
import {
  dailyDecisionConsent,
  type DailyDecisionDeps,
  type DailyDecisionPath,
  dailyDecisionPath,
  dailyDecisionProviderFor,
  failedRunProvenance,
  failureSpend,
  groundingFault,
  reserveDailyDecision,
} from "../_shared/providers/daily_decision_provider.ts";

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

export type Auth = Awaited<ReturnType<typeof requireAuth>>;

export type CoachDecideDeps = Readonly<{
  requireAuth: (request: Request) => Promise<Auth>;
  /** The decision path; production reads it from the environment per request. */
  path?: () => DailyDecisionPath;
  provider?: DailyDecisionDeps;
}>;

// A budget reservation taken for the live model is released when the request
// ends, however it ends, unless the failure path kept it open.
export function coachDecideHandler(deps: CoachDecideDeps) {
  return async (request: Request): Promise<Response> => {
    const budget: { current?: AiBudget } = {};
    try {
      return await handleCoachDecide(request, budget, deps);
    } finally {
      await budget.current?.release();
    }
  };
}

async function handleCoachDecide(
  request: Request,
  held: { current?: AiBudget },
  deps: CoachDecideDeps,
): Promise<Response> {
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  let auth;
  try {
    auth = await deps.requireAuth(request);
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
  // Checked before anything else: without the athlete's consent to the notice
  // current for daily coaching (or when the check fails), the day's decision
  // comes from the deterministic provider and no data reaches the AI provider.
  // With an AI_DAILY_DECISION_* route the notice must also name the route's
  // vendor; without one, today's provider settings apply unchanged.
  const path = deps.path ? deps.path() : dailyDecisionPath();
  const consent = await dailyDecisionConsent(
    path,
    (name, params) => auth.serviceClient.rpc(name, params),
    auth.userId,
  );
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

  // The live model also needs a place in the AI budget. Without one the day's
  // decision comes from the deterministic provider, as without consent.
  const budget = new AiBudget((fn, args) => auth.serviceClient.rpc(fn, args), auth.userId);
  held.current = budget;
  const useModel = consent === "granted" && await reserveDailyDecision(path, budget);

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
    const decisionRequest = {
      decisionKind: "daily" as const,
      featureSnapshotId: prepared.feature_snapshot_id,
      policyEvaluationId: prepared.policy_evaluation_id,
      policyOutcome: outcome,
      permittedEvidence: evidence,
      featureContext: snapshot.features as Record<string, unknown>,
      missingData: prepared.missing_data ?? [],
    };
    generated = await dailyDecisionProviderFor(
      path,
      useModel ? consent : "not_granted",
      deps.provider,
    ).generateDecision(decisionRequest);
    const decision = parseCoachDecision(generated.decision, evidence, outcome);
    // A gateway model's text is also checked against the request's data (numbers, names, gaps).
    // Today's path is unchanged and has the same gap (A5 handoff).
    if (path.kind === "gateway" && useModel) {
      const fault = groundingFault(decision, decisionRequest);
      if (fault) throw new Error(fault);
    }
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
      // A failed run is stored without its cost, so a live call's reservation
      // stays open and keeps counting at its ceiling.
      if (useModel) budget.keep();
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
    // Nothing billed: the place is released when the request ends. Otherwise it
    // stays open at its ceiling (today's path always; see failureSpend).
    if (useModel && failureSpend(path, error, generated) !== "none") budget.keep();
    const provenance = failedRunProvenance(path, useModel);
    await auth.serviceClient.rpc("persist_failed_coaching_run_v2", {
      target_user_id: auth.userId,
      snapshot_id: prepared.feature_snapshot_id,
      policy_id: prepared.policy_evaluation_id,
      request_idempotency_key: input.idempotency_key,
      run_latency_ms: Math.round(performance.now() - started),
      error_code: reason,
      run_provider: provenance.provider,
      run_model: provenance.model,
    });
    return reply(503, { error: "coaching_unavailable" });
  }
}
