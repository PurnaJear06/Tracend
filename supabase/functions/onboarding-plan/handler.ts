import { reply } from "../_shared/auth.ts";
import type { AiCoachingConsent } from "../_shared/ai_consent.ts";
import {
  type AnswersResult,
  answersSnapshot,
  type OnboardingAnswers,
  parseOnboardingAnswers,
} from "../_shared/onboarding/answers.ts";
import { type CatalogExercise, catalogVersion } from "../_shared/onboarding/catalog.ts";
import {
  generateOnboardingProposal,
  type GenerationResult,
  type GenerationUsage,
  OnboardingPlanInfeasibleError,
  policiesFor,
  validRulesPlan,
} from "../_shared/onboarding/generate.ts";
import type { OnboardingProposalPayload } from "../_shared/onboarding/plan_contract.ts";
import { onboardingPolicyVersion } from "../_shared/onboarding/policy.ts";
import {
  type HealthDay,
  type HealthSummary,
  healthWindow,
  type HealthWorkout,
  localDate,
  summarizeHealth,
} from "../_shared/onboarding/health_summary.ts";
import { sha256 } from "../_shared/onboarding/snapshot.ts";
import type { OnboardingModelResolution } from "../_shared/providers/onboarding_plan_provider.ts";

// POST onboarding-plan: start (or return) the athlete's onboarding plan
// generation and answer at once with its id. The plan is built in the
// background; the app polls get_my_onboarding_generation. A repeated request
// with the same answers returns the same generation. Answers no valid plan can
// meet are refused at once (422 onboarding_plan_infeasible, with the answers
// to change), so retrying them never starts a generation or calls a model.

/**
 * Longer than the model deadline (75 s, or 125 s with thinking) plus storing,
 * shorter than the 150 s Edge background limit.
 */
export const generationLeaseSeconds = 140;

/**
 * How the model call went, stored in the onboarding.plan.generated audit event
 * so production plans can be checked (persist_onboarding_proposal_v3).
 */
export type GenerationMetadata = Readonly<{
  thinking: boolean;
  latency_ms: number;
  attempts: number;
  input_units: number;
  output_units: number;
  reasoning_units: number;
  finish_reason: string | null;
}>;

export function generationMetadata(result: GenerationResult): GenerationMetadata | null {
  if (!result.usage) return null;
  return {
    thinking: result.usage.thinking,
    latency_ms: result.usage.latencyMs,
    attempts: result.attempts.length,
    input_units: result.usage.inputUnits,
    output_units: result.usage.outputUnits,
    reasoning_units: result.usage.reasoningUnits,
    finish_reason: result.usage.finishReason,
  };
}

export type GenerationClaim = Readonly<{
  generation_id: string;
  status: "running" | "succeeded";
  started: boolean;
  proposal_id?: string;
}>;

export interface OnboardingStore {
  loadDraft(): Promise<{ path: unknown; payload: Record<string, unknown> } | null>;
  claim(snapshotHash: string): Promise<GenerationClaim>;
  loadCatalog(): Promise<CatalogExercise[]>;
  /** The athlete's IANA time zone (user_accounts.timezone). */
  timezone(): Promise<string>;
  /** Apple Health daily summaries and workouts with local dates in [from, through]. */
  loadHealth(
    from: string,
    through: string,
  ): Promise<{ days: HealthDay[]; workouts: HealthWorkout[] }>;
  consent(): Promise<AiCoachingConsent>;
  budgetAvailable(): Promise<boolean>;
  recordUsage(usage: GenerationUsage): Promise<void>;
  /** "superseded" when a newer generation replaced this one meanwhile. */
  persist(
    generationId: string,
    snapshotHash: string,
    snapshot: Record<string, unknown>,
    proposal: OnboardingProposalPayload,
    metadata: GenerationMetadata | null,
  ): Promise<"stored" | "superseded">;
  fail(generationId: string, code: string): Promise<void>;
}

export type Observer = Readonly<{
  info(event: string, fields: Record<string, unknown>): void;
  warn(event: string, fields: Record<string, unknown>): void;
  error(event: string, error: unknown, fields: Record<string, unknown>): void;
}>;

export type HandlerDeps = Readonly<{
  store: OnboardingStore;
  resolution: () => OnboardingModelResolution;
  currentYear: number;
  now: () => Date;
  /** Keeps the background work alive after the response (EdgeRuntime.waitUntil). */
  background: (work: Promise<void>) => void;
  observer: Observer;
  generate?: typeof generateOnboardingProposal;
}>;

export async function handleOnboardingPlan(deps: HandlerDeps): Promise<Response> {
  const draft = await deps.store.loadDraft();
  if (!draft) return reply(422, { error: "onboarding_draft_incomplete" });
  const parsed: AnswersResult = parseOnboardingAnswers(
    draft.path,
    draft.payload,
    deps.currentYear,
  );
  if (!parsed.ok) {
    return reply(422, { error: "onboarding_answers_incomplete", missing: parsed.missing });
  }
  const catalog = await deps.store.loadCatalog();
  const health = await loadHealthSummary(deps);
  try {
    validRulesPlan(policiesFor(parsed.answers, catalog, health));
  } catch (error) {
    if (!(error instanceof OnboardingPlanInfeasibleError)) throw error;
    return reply(422, {
      error: "onboarding_plan_infeasible",
      rule: error.rule,
      change: answersToChange(error.rule, parsed.answers),
    });
  }
  const snapshot = {
    schema_version: "2.0",
    policy_version: onboardingPolicyVersion,
    catalog_version: catalogVersion,
    answers: answersSnapshot(parsed.answers),
    // Part of the hash: connecting Apple Health builds a new plan, the same
    // data reuses the existing one.
    health,
  };
  const snapshotHash = await sha256(snapshot);
  const claim = await deps.store.claim(snapshotHash);
  const body = {
    schema_version: "1.0",
    generation_id: claim.generation_id,
    status: claim.status,
    ...(claim.proposal_id ? { proposal_id: claim.proposal_id } : {}),
  };
  if (!claim.started) return reply(claim.status === "succeeded" ? 200 : 202, body);
  deps.background(
    runGeneration(
      deps,
      claim.generation_id,
      snapshotHash,
      snapshot,
      parsed.answers,
      catalog,
      health,
    ),
  );
  return reply(202, body);
}

/** The answers that decide whether a broken rule can be met. */
export function answersToChange(rule: string, answers: OnboardingAnswers): string[] {
  if (rule === "session_too_long" || rule === "session_set_budget_exceeded") {
    return ["session_minutes"];
  }
  if (
    rule.startsWith("calories") || rule.startsWith("protein") || rule.startsWith("fat") ||
    rule.startsWith("carbohydrate") || rule === "macro_sum_mismatch"
  ) {
    return ["weight_kg", "daily_activity"];
  }
  return answers.avoidPatterns.length ? ["avoid_patterns", "equipment_items"] : ["equipment_items"];
}

/**
 * The 28 complete days before the athlete's local today, summarised; null
 * without Apple Health data (ALGORITHMS §9).
 */
async function loadHealthSummary(deps: HandlerDeps): Promise<HealthSummary | null> {
  const today = localDate(deps.now(), await deps.store.timezone());
  const { from, through } = healthWindow(today);
  const { days, workouts } = await deps.store.loadHealth(from, through);
  return summarizeHealth(days, workouts, today);
}

async function runGeneration(
  deps: HandlerDeps,
  generationId: string,
  snapshotHash: string,
  snapshot: Record<string, unknown>,
  answers: OnboardingAnswers,
  catalog: CatalogExercise[],
  health: HealthSummary | null,
): Promise<void> {
  const { store, observer } = deps;
  try {
    const resolution = deps.resolution();
    let consentGranted = false;
    let budgetAvailable = false;
    if (resolution.kind === "model") {
      consentGranted = (await store.consent()) === "granted";
      if (consentGranted) budgetAvailable = await store.budgetAvailable();
    }
    const result: GenerationResult = await (deps.generate ?? generateOnboardingProposal)(
      answers,
      catalog,
      resolution,
      { consentGranted, budgetAvailable },
      fetch,
      undefined,
      health,
    );
    if (result.usage) {
      try {
        await store.recordUsage(result.usage);
      } catch (error) {
        observer.error("onboarding_plan_usage_not_recorded", error, { generationId });
      }
    }
    const fields = {
      generationId,
      origin: result.proposal.training.origin,
      provider: result.usage?.provider ?? null,
      model: result.usage?.model ?? null,
      fallbackReason: result.fallbackReason,
      attempts: result.attempts,
      metadata: generationMetadata(result),
    };
    // A model was asked and its plan was not used: worth a look.
    if (result.usage && result.fallbackReason) {
      observer.warn("onboarding_plan_model_fallback", fields);
    } else {
      observer.info("onboarding_plan_generated", fields);
    }
    const stored = await store.persist(
      generationId,
      snapshotHash,
      snapshot,
      result.proposal,
      generationMetadata(result),
    );
    if (stored === "superseded") {
      observer.info("onboarding_plan_superseded", { generationId });
    }
  } catch (error) {
    observer.error("onboarding_plan_generation_failed", error, { generationId });
    try {
      await store.fail(
        generationId,
        error instanceof OnboardingPlanInfeasibleError ? "plan_infeasible" : "generation_failed",
      );
    } catch (failError) {
      // The lease expires on its own; the app then reads the generation as failed.
      observer.error("onboarding_plan_failure_not_recorded", failError, { generationId });
    }
  }
}
