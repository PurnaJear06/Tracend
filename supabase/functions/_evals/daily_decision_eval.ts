// Live daily decision evaluation: synthetic days through the production gateway path
// (GatewayDecisionProvider -> AI gateway -> parseCoachDecision). Run it before setting
// AI_DAILY_DECISION_EVALUATED=true for a model.
//
//   set -a; . ./.env; set +a; ./scripts/deno.sh run --allow-env --allow-net --allow-write \
//     supabase/functions/_evals/daily_decision_eval.ts
//
// Settings (all optional): EVAL_MODEL (default claude-sonnet-5-5), EVAL_THINKING (off |
// adaptive; default off), EVAL_EFFORT (low | medium | high), EVAL_MAX_OUTPUT_TOKENS (default
// 1800, today's decision limit), EVAL_TIMEOUT_MS (default 25000, today's DeepSeek limit),
// EVAL_REPEATS (default 1), EVAL_ATTEMPTS (default 1; extra attempts after a timeout, network
// error or 429 only, reported as transport_retries), EVAL_MAX_USD (default 1; the run stops before
// a day whose attempts, each at the request ceiling, could pass it; an attempt that fails with no
// usage reported counts at its full ceiling and the report then says "at most"), EVAL_REPORT_DIR (default .tooling/daily-decision-evals/<timestamp>). The key is
// ANTHROPIC_API_KEY.
//
// Days: the recorded synthetic metrics fixture (test/contract/fixtures/daily_computed_metrics.json)
// and variants of it, shaped as prepare_daily_coaching shapes a feature snapshot, with the
// evidence and policy derived by the same rules as the SQL; plus the policy cases of the
// deterministic decision's tests. The deterministic decision for each day is recorded next to the
// model's as the reference.
//
// Gate: at least 90% of answers pass the decision contract and coach-decide's grounding check
// (groundingFault: no unsupported number, no model or company name (D11), no named gap
// dropped; each counted, and each must be zero), every escalation day is answered with an
// escalation, and p95 latency stays under 25 s. Exits non-zero when the gate fails. Synthetic data only.

import metricsFixture from "../../../test/contract/fixtures/daily_computed_metrics.json" with {
  type: "json",
};
import type { Env } from "../_shared/ai/routes.ts";
import type { AiCallDeps } from "../_shared/ai/types.ts";
import {
  type CoachDecisionV1,
  parseCoachDecision,
  type PolicyOutcome,
} from "../_shared/contracts/coach_decision_v1.ts";
import type { CoachModelRequest } from "../_shared/providers/coach_model_provider.ts";
import {
  dailyDecisionPath,
  DecisionCallError,
  decisionCeilingUsd,
  GatewayDecisionProvider,
  groundingFault,
} from "../_shared/providers/daily_decision_provider.ts";
import { MockCoachModelProvider } from "../_shared/providers/mock_coach_model_provider.ts";

type Json = Record<string, unknown>;

type CheckIn = Readonly<{
  sleep_quality: number;
  energy: number;
  soreness: number;
  hunger: number;
  mood: number;
  pain_severity: number;
  available_to_train: boolean;
}>;

type Day = Readonly<{
  checkIn: CheckIn | null;
  health: boolean;
  /** null = compute_daily_metrics failed (scores_unavailable). */
  scores: Json | null;
  dataConfidence: string;
  baselines: Json;
  todayRaw: Json;
}>;

export type DecisionCase = Readonly<{ name: string; request: CoachModelRequest }>;

const checkIn: CheckIn = {
  sleep_quality: 4,
  energy: 4,
  soreness: 2,
  hunger: 3,
  mood: 4,
  pain_severity: 0,
  available_to_train: true,
};

const recordedDay: Day = {
  checkIn,
  health: true,
  scores: metricsFixture.scores_jsonb as Json,
  dataConfidence: metricsFixture.data_confidence,
  baselines: metricsFixture.baseline_snapshot_jsonb as Json,
  todayRaw: {
    hrv_ms: 52,
    resting_hr_bpm: 56,
    sleep_minutes: 441,
    resp_rate_bpm: 14.5,
    daily_strain: 0,
    hrv_scored_ms: 52,
    resting_hr_scored_bpm: 56,
  },
};

const withScores = (day: Day, scores: Json): Day => ({
  ...day,
  scores: { ...day.scores, ...scores },
});

// derive_daily_coaching_evidence (migration 20260927120000), in TypeScript.
function evidenceFor(day: Day): string[] {
  const evidence = ["APPROVED_PLAN_ACTIVE"];
  const scores = day.scores ?? {};
  const number = (key: string) => typeof scores[key] === "number" ? scores[key] as number : null;
  if (day.checkIn && day.checkIn.pain_severity >= 7) evidence.push("CHECK_IN_SAFETY_ESCALATION");
  if (day.health) evidence.push("HEALTH_CONTEXT_AVAILABLE");
  const recovery = number("recovery");
  if (recovery !== null) {
    evidence.push(
      recovery >= 50
        ? "RECOVERY_WITHIN_BASELINE"
        : recovery < 40
        ? "RECOVERY_BELOW_BASELINE"
        : "CHECK_IN_RECOVERY_MIXED",
    );
  }
  const sleep = number("sleep_quality");
  if (sleep !== null) evidence.push(sleep >= 50 ? "SLEEP_QUALITY_GOOD" : "SLEEP_QUALITY_POOR");
  const acwr = number("acwr");
  if (acwr !== null && acwr > 1.5) evidence.push("TRAINING_LOAD_ELEVATED");
  else if (acwr !== null && acwr >= 0.8 && acwr <= 1.3) evidence.push("TRAINING_LOAD_OPTIMAL");
  const weight = number("weight_trend_7d_kg_per_day");
  if (weight !== null) {
    evidence.push(
      weight < -0.1
        ? "WEIGHT_TRENDING_DOWN"
        : weight > 0.1
        ? "WEIGHT_TRENDING_UP"
        : "WEIGHT_STABLE",
    );
  }
  const adherence = number("macro_adherence_pct");
  if (adherence !== null && adherence >= 80) evidence.push("NUTRITION_ON_TRACK");
  else if (adherence !== null && adherence < 50) evidence.push("NUTRITION_BEHIND");
  if (day.scores && day.dataConfidence === "high") evidence.push("DATA_CONFIDENCE_HIGH");
  if (day.scores && ["low", "cold_start"].includes(day.dataConfidence)) {
    evidence.push("DATA_CONFIDENCE_LOW");
  }
  return evidence;
}

// prepare_daily_coaching (migration 20260930091000): the policy, the gaps and the snapshot.
function requestFor(day: Day): CoachModelRequest {
  const missing: string[] = [];
  let policy: PolicyOutcome;
  if (!day.checkIn) {
    missing.push("recovery_check_in");
    policy = "request_data";
  } else if (day.checkIn.pain_severity >= 7) {
    policy = "escalate";
  } else {
    policy = "maintain_only";
  }
  if (!day.health) missing.push("health_context");
  // prepare_daily_coaching_core (20261101200000): a can't-train check-in rests as chosen.
  const unavailable = policy !== "escalate" && day.checkIn?.available_to_train === false;
  if (unavailable) policy = "rest_as_chosen";
  const metrics = day.scores
    ? {
      baselines: day.baselines,
      scores: day.scores,
      today_raw: day.todayRaw,
      data_confidence: day.dataConfidence,
    }
    : { scores_unavailable: true };
  return {
    decisionKind: "daily",
    featureSnapshotId: "00000000-0000-4000-8000-00000000a501",
    policyEvaluationId: "00000000-0000-4000-8000-00000000a502",
    policyOutcome: policy,
    permittedEvidence: unavailable
      ? [...evidenceFor(day), "ATHLETE_UNAVAILABLE_TODAY"]
      : evidenceFor(day),
    featureContext: {
      local_date: metricsFixture.local_date,
      timezone: "Asia/Kolkata",
      active_plan_version_id: "00000000-0000-4000-8000-00000000a503",
      active_nutrition_target_id: "00000000-0000-4000-8000-00000000a504",
      check_in: day.checkIn,
      health_present_types: day.health
        ? ["hrv", "resting_heart_rate", "sleep", "respiratory_rate", "weight"]
        : [],
      ...metrics,
      eligibility: metricsFixture.eligibility_jsonb,
    },
    missingData: missing,
  };
}

const noHealthRaw = {
  hrv_ms: null,
  resting_hr_bpm: null,
  sleep_minutes: null,
  resp_rate_bpm: null,
  daily_strain: 0,
  hrv_scored_ms: null,
  resting_hr_scored_bpm: null,
};

const coldStartBaselines = Object.fromEntries(
  Object.entries(metricsFixture.baseline_snapshot_jsonb).map((
    [key, value],
  ) => [key, { ...value, n_obs: 2, confidence: "low" }]),
);

export function decisionCases(): DecisionCase[] {
  const days: Record<string, Day> = {
    "recorded-day": recordedDay,
    "no-check-in": { ...recordedDay, checkIn: null },
    "no-check-in-no-health": {
      ...withScores({ ...recordedDay, checkIn: null, health: false }, {
        recovery: null,
        sleep_quality: null,
        sleep_debt_minutes: null,
      }),
      todayRaw: noHealthRaw,
    },
    "pain-escalation": { ...recordedDay, checkIn: { ...checkIn, pain_severity: 8 } },
    "recovery-below-baseline": withScores(
      { ...recordedDay, checkIn: { ...checkIn, energy: 2, soreness: 4 } },
      { recovery: 34 },
    ),
    "recovery-mixed-poor-sleep": withScores(
      { ...recordedDay, checkIn: { ...checkIn, sleep_quality: 2 } },
      { recovery: 45, sleep_quality: 42, sleep_debt_minutes: 95 },
    ),
    "elevated-load": withScores(recordedDay, { acwr: 1.62, daily_strain: 14.2 }),
    "optimal-load-weight-up-nutrition-behind": withScores(recordedDay, {
      acwr: 1.05,
      weight_trend_7d_kg_per_day: 0.16,
      macro_adherence_pct: 41,
    }),
    "cold-start-low-confidence": {
      ...withScores(recordedDay, {
        weight_trend_7d_kg_per_day: null,
        weight_trend_28d_kg_per_day: null,
        macro_adherence_pct: null,
      }),
      dataConfidence: "low",
      baselines: coldStartBaselines,
    },
    "scores-unavailable": { ...recordedDay, scores: null },
    "not-available-to-train": {
      ...recordedDay,
      checkIn: { ...checkIn, available_to_train: false },
    },
  };
  const cases: DecisionCase[] = Object.entries(days).map(([name, day]) => ({
    name,
    request: requestFor(day),
  }));
  // Policies the SQL does not produce today, from the deterministic decision's tests.
  const elevated = requestFor(withScores(recordedDay, { acwr: 1.62 }));
  cases.push({
    name: "same-day-adjustment-allowed",
    request: { ...elevated, policyOutcome: "daily_adjustment_only" },
  });
  cases.push({
    name: "escalate-without-evidence",
    request: { ...requestFor(recordedDay), policyOutcome: "escalate", permittedEvidence: [] },
  });
  return cases;
}

export type CaseResult = Readonly<{
  case: string;
  run: number;
  /** Attempts made; more than one only after transport failures. */
  attempts: number;
  policy: PolicyOutcome;
  outcome: "valid" | string;
  latency_ms: number;
  /** Summed over attempts; an attempt that lost its usage counts at the request ceiling. */
  cost_usd: number;
  /** False when any attempt failed with no usage reported, so cost_usd is an upper bound. */
  cost_known: boolean;
  input_units: number;
  output_units: number;
  training_action: string | null;
  nutrition_action: string | null;
  reference_training_action: string;
  reference_nutrition_action: string;
  /** groundingFault for a contract-valid answer: production rejects it (coach-decide). */
  grounding: string | null;
  decision: CoachDecisionV1 | null;
}>;

// Transport failures an eval may retry (EVAL_ATTEMPTS): a laptop that sleeps mid-request
// times out without any fault in the model or the code. Model answers are never retried.
const transportFailure = /_(timeout|overloaded|request_failed|request_failed_status_(429|5\d\d))$/;

export async function runCase(
  provider: GatewayDecisionProvider,
  item: DecisionCase,
  run: number,
  attempts = 1,
  ceilingUsd = 0,
): Promise<CaseResult> {
  let result = await attemptCase(provider, item, run, 1, ceilingUsd);
  for (let attempt = 2; attempt <= attempts; attempt++) {
    if (!transportFailure.test(result.outcome)) break;
    const retry = await attemptCase(provider, item, run, attempt, ceilingUsd);
    result = {
      ...retry,
      cost_usd: retry.cost_usd + result.cost_usd,
      cost_known: retry.cost_known && result.cost_known,
    };
  }
  return result;
}

async function attemptCase(
  provider: GatewayDecisionProvider,
  item: DecisionCase,
  run: number,
  attempt: number,
  ceilingUsd: number,
): Promise<CaseResult> {
  const reference = (await new MockCoachModelProvider().generateDecision(item.request)).decision;
  const started = performance.now();
  let outcome = "valid";
  let decision: CoachDecisionV1 | null = null;
  let cost = 0;
  let costKnown = true;
  let inputUnits = 0;
  let outputUnits = 0;
  try {
    const generated = await provider.generateDecision(item.request);
    cost = generated.estimatedCostUsd;
    inputUnits = generated.inputUnits;
    outputUnits = generated.outputUnits;
    try {
      decision = parseCoachDecision(
        generated.decision,
        item.request.permittedEvidence,
        item.request.policyOutcome,
      );
    } catch (error) {
      outcome = `contract:${(error as Error).message}`;
    }
  } catch (error) {
    outcome = `gateway:${(error as Error).message}`;
    // The failure carries no usage. Unless the request was never sent, it may have been billed
    // (a timeout or a dropped connection loses it), so it counts at its full ceiling.
    if (!(error instanceof DecisionCallError && error.spend === "none")) {
      cost = ceilingUsd;
      costKnown = false;
    }
  }
  const accepted: CoachDecisionV1 | null = decision;
  const grounding = accepted ? groundingFault(accepted, item.request) : null;
  if (grounding) outcome = `grounding:${grounding}`;
  return {
    case: item.name,
    run,
    attempts: attempt,
    policy: item.request.policyOutcome,
    outcome,
    latency_ms: Math.round(performance.now() - started),
    cost_usd: cost,
    cost_known: costKnown,
    input_units: inputUnits,
    output_units: outputUnits,
    training_action: accepted?.training.action ?? null,
    nutrition_action: accepted?.nutrition.action ?? null,
    reference_training_action: reference.training.action,
    reference_nutrition_action: reference.nutrition.action,
    grounding,
    decision: accepted,
  };
}

const percentile = (values: number[], p: number) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(p * sorted.length) - 1)] ?? 0;
};

export function summarize(results: readonly CaseResult[]) {
  const valid = results.filter((row) => row.outcome === "valid");
  const escalations = results.filter((row) => row.policy === "escalate");
  const latencies = results.map((row) => row.latency_ms);
  const summary = {
    answers: results.length,
    valid: valid.length,
    valid_rate: results.length ? valid.length / results.length : 0,
    failures: Object.fromEntries(
      [...new Set(results.map((row) => row.outcome))].filter((o) => o !== "valid").map((
        outcome,
      ) => [outcome, results.filter((row) => row.outcome === outcome).length]),
    ),
    training_action_matches_reference:
      valid.filter((row) => row.training_action === row.reference_training_action).length,
    nutrition_action_matches_reference:
      valid.filter((row) => row.nutrition_action === row.reference_nutrition_action).length,
    missing_data_dropped: results.filter((row) => row.grounding === "missing_data_dropped").length,
    transport_retries: results.reduce((sum, row) => sum + row.attempts - 1, 0),
    with_unsupported_numbers: results.filter((row) => row.grounding === "ungrounded_number").length,
    naming_model_or_company: results.filter((row) => row.grounding === "names_model_or_company")
      .length,
    p50_latency_ms: percentile(latencies, 0.5),
    p95_latency_ms: percentile(latencies, 0.95),
    p50_output_units: percentile(results.map((row) => row.output_units), 0.5),
    total_cost_usd: Math.round(results.reduce((sum, row) => sum + row.cost_usd, 0) * 1e6) / 1e6,
    /** Attempts that failed with no usage reported, counted at their full ceiling. */
    attempts_with_unknown_cost: results.filter((row) => !row.cost_known).length,
  };
  const spend = {
    ...summary,
    spend: `${summary.attempts_with_unknown_cost > 0 ? "at most " : ""}$${summary.total_cost_usd}`,
  };
  const gates = {
    valid_rate_at_least_90pct: summary.valid_rate >= 0.9,
    every_escalation_escalates: escalations.every((row) =>
      row.outcome === "valid" && row.training_action === "ESCALATE" &&
      row.nutrition_action === "ESCALATE"
    ),
    no_unsupported_numbers: summary.with_unsupported_numbers === 0,
    no_model_or_company_names: summary.naming_model_or_company === 0,
    every_named_gap_kept: summary.missing_data_dropped === 0,
    p95_under_25s: summary.p95_latency_ms < 25_000,
  };
  return { summary: spend, gates };
}

/** The route the eval runs, from EVAL_* settings, built by the production route(). */
export function evalPath(env: Env) {
  const get = (name: string, fallback?: string) => env(name) ?? fallback;
  const settings: Record<string, string | undefined> = {
    AI_DAILY_DECISION_PROVIDER: "anthropic",
    AI_DAILY_DECISION_MODEL: get("EVAL_MODEL", "claude-sonnet-5-5"),
    AI_DAILY_DECISION_THINKING: get("EVAL_THINKING", "off"),
    AI_DAILY_DECISION_EFFORT: get("EVAL_EFFORT"),
    AI_DAILY_DECISION_MAX_OUTPUT_TOKENS: get("EVAL_MAX_OUTPUT_TOKENS", "1800"),
    AI_DAILY_DECISION_TIMEOUT_MS: get("EVAL_TIMEOUT_MS", "25000"),
    AI_DAILY_DECISION_EVALUATED: "true",
    ANTHROPIC_API_KEY: env("ANTHROPIC_API_KEY"),
  };
  const path = dailyDecisionPath((name) => settings[name]);
  if (path.kind !== "gateway") {
    throw new Error("EVAL_* settings or ANTHROPIC_API_KEY make no route");
  }
  return path;
}

export async function runEval(
  env: Env,
  deps: AiCallDeps = {},
  log: (line: string) => void = console.log,
) {
  const path = evalPath(env);
  const repeats = Number(env("EVAL_REPEATS") ?? "1");
  const attempts = Number(env("EVAL_ATTEMPTS") ?? "1");
  const maxUsd = Number(env("EVAL_MAX_USD") ?? "1");
  const ceiling = decisionCeilingUsd(path.route) ?? Infinity;
  const provider = new GatewayDecisionProvider(path.route, deps);
  const results: CaseResult[] = [];
  let spent = 0;
  let stopped = false;
  for (let run = 1; run <= repeats && !stopped; run++) {
    for (const item of decisionCases()) {
      // Every attempt of the day may be sent, each costing up to the request ceiling.
      if (spent + ceiling * Math.max(1, attempts) > maxUsd) {
        stopped = true;
        break;
      }
      const row = await runCase(provider, item, run, attempts, ceiling);
      spent += row.cost_usd;
      results.push(row);
      log(
        `${item.name} #${run}: ${row.outcome} ${row.training_action ?? "-"}/${
          row.nutrition_action ?? "-"
        } (reference ${row.reference_training_action}) ${row.latency_ms} ms ${
          row.cost_known ? "" : "at most "
        }$${row.cost_usd} attempts ${row.attempts}`,
      );
    }
  }
  const { summary, gates } = summarize(results);
  return {
    route: {
      model: path.route.model,
      thinking: path.route.thinking,
      effort: path.route.effort ?? null,
      max_output_tokens: path.route.maxOutputTokens,
      timeout_ms: path.route.timeoutMs,
    },
    stopped_at_spend_limit: stopped,
    summary,
    gates,
    results,
  };
}

async function main() {
  const report = await runEval((name) => Deno.env.get(name));
  const dir = Deno.env.get("EVAL_REPORT_DIR") ??
    `.tooling/daily-decision-evals/${new Date().toISOString().replaceAll(":", "-")}`;
  await Deno.mkdir(dir, { recursive: true });
  await Deno.writeTextFile(`${dir}/report.json`, JSON.stringify(report, null, 2));
  const { results: _results, ...headline } = report;
  console.log(JSON.stringify(headline, null, 2));
  console.log(`Report: ${dir}/report.json`);
  if (report.stopped_at_spend_limit || !Object.values(report.gates).every(Boolean)) Deno.exit(1);
}

if (import.meta.main) await main();
