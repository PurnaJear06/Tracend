import { reply } from "../_shared/auth.ts";
import type { AiCoachingConsent, AiConsentWithProvider, AiVendor } from "../_shared/ai_consent.ts";
import type { AiRoute } from "../_shared/ai/types.ts";
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
import {
  type OnboardingProposalPayload,
  PlanBlockedByScreeningError,
} from "../_shared/onboarding/plan_contract.ts";
import type { ScreeningOutcome } from "../_shared/training/screening/outcome.ts";
import { onboardingPolicyVersion } from "../_shared/onboarding/policy.ts";
import { onboardingLibraryQueries } from "../_shared/library/plan_explanation.ts";
import type { PlanLibrary } from "../_shared/library/plan_library.ts";
import {
  type HealthDay,
  type HealthSummary,
  healthWindow,
  type HealthWorkout,
  localDate,
  summarizeHealth,
} from "../_shared/onboarding/health_summary.ts";
import {
  type HealthHistory,
  type HealthMonth,
  historyWindow,
  summarizeHealthHistory,
} from "../_shared/onboarding/health_history.ts";
import {
  followUpGateReason,
  type FollowUpQuestion,
  type FollowUpResult,
  generateFollowUpQuestions,
} from "../_shared/onboarding/questions.ts";
import { sha256 } from "../_shared/onboarding/snapshot.ts";
import type {
  OnboardingGatewayFeature,
  OnboardingModelResolution,
} from "../_shared/providers/onboarding_plan_provider.ts";
import {
  type GatewayDeps,
  type GatewayPlanResult,
  type GatewayQuestionsResult,
  type GatewaySpend,
  generatePlanViaGateway,
  generateQuestionsViaGateway,
  type PreparedPlan,
  preparePlan,
  prepareQuestions,
  type QuestionsPreparation,
} from "./gateway.ts";

// POST onboarding-plan: start (or return) the athlete's onboarding plan
// generation and answer at once with its id. The plan is built in the
// background; the app polls get_my_onboarding_generation. A repeated request
// with the same answers returns the same generation. Answers no valid plan can
// meet are refused at once (422 onboarding_plan_infeasible, with the answers
// to change), so retrying them never starts a generation or calls a model.
//
// An athlete whose stored screening outcome is see_professional gets 422
// onboarding_screening_see_professional (both modes): no plan, no questions, no model call and no
// budget. moderate_until_cleared builds a plan capped at moderate effort. An athlete with no
// stored screening (it was skipped, or the account predates it) gets 422
// onboarding_answers_incomplete with missing ["screening"], which every app build opens at the
// health check: a missing screening is never read as cleared.
//
// POST onboarding-plan {"mode":"questions"}: the coach's follow-up questions
// for the current answers, answered synchronously. One request claims the
// answers' hash before asking the model; an overlapping one waits for its
// outcome. The model's outcome is stored under the hash, so a retry returns the
// same questions without a model call, and an edited answer gets new ones. No
// consent, no budget or no model ask nothing and store nothing, so they never
// outlast their cause. Follow-up answers count toward the plan only while they
// carry that hash.

/**
 * Longer than the model deadline (75 s, or 125 s with thinking) plus storing,
 * shorter than the 150 s Edge background limit.
 */
export const generationLeaseSeconds = 140;

/** Longer than the question deadline (40 s) plus storing. */
export const questionsLeaseSeconds = 60;

/** How long an overlapping question request waits, polling once a second. */
export const questionsWaitMs = 45_000;
export const questionsPollMs = 1_000;

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
  /**
   * The athlete's stored pre-exercise screening outcome (Contract 8): the newest
   * onboarding_screenings row, or null when there is none (never screened).
   */
  screening(): Promise<ScreeningOutcome | null>;
  /** Apple Health daily summaries and workouts with local dates in [from, through]. */
  loadHealth(
    from: string,
    through: string,
  ): Promise<{ days: HealthDay[]; workouts: HealthWorkout[] }>;
  /** Apple Health monthly totals for months starting in [from, through]. */
  loadHealthHistory(from: string, through: string): Promise<HealthMonth[]>;
  /**
   * Started: this request asks the model. Otherwise the stored outcome, or
   * none while another request holds the claim.
   */
  claimQuestions(questionsHash: string): Promise<QuestionsClaim>;
  /** Stores the questions; when another request stored first, returns those. */
  saveQuestions(questionsHash: string, questions: StoredQuestions): Promise<StoredQuestions>;
  /** Drops this request's claim after a failed call, so a retry asks again. */
  releaseQuestions(questionsHash: string): Promise<void>;
  recordQuestionUsage(usage: GenerationUsage): Promise<void>;
  /**
   * Settings path: whether the athlete's current onboarding notice is granted and names `vendor`,
   * the provider the settings send the data to (see `legacyNoticeConsent`).
   */
  consent(feature: OnboardingGatewayFeature, vendor: AiVendor): Promise<AiCoachingConsent>;
  budgetAvailable(): Promise<boolean>;
  /** The notice current for the feature, and the vendor it names (gateway path). */
  gatewayConsent(feature: OnboardingGatewayFeature): Promise<AiConsentWithProvider>;
  /**
   * Takes a place in the budget at the route's worst-case cost (gateway path); false when the
   * limit stops it.
   */
  reserveGatewayBudget(feature: OnboardingGatewayFeature, ceilingUsd: number): Promise<boolean>;
  /** Gives the place back: no call was made, it cost nothing, or its usage is recorded. */
  releaseBudget(): Promise<void>;
  /** Leaves the budget place open: a call may have been billed with no usage reported. */
  keepBudget?(): void;
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

export type StoredQuestions = Readonly<{
  questions: readonly FollowUpQuestion[];
  skipped_reason: string | null;
  metadata: GenerationMetadata | null;
}>;

export type QuestionsClaim = Readonly<{ started: boolean; stored?: StoredQuestions }>;

export type HandlerDeps = Readonly<{
  /** "questions" for the follow-up questions, otherwise the plan. */
  mode: "plan" | "questions";
  store: OnboardingStore;
  resolution: () => OnboardingModelResolution;
  currentYear: number;
  now: () => Date;
  /** Keeps the background work alive after the response (EdgeRuntime.waitUntil). */
  background: (work: Promise<void>) => void;
  observer: Observer;
  /**
   * The AI gateway routes (Contract 1), read per request: a usable, evaluated route sends that
   * feature through the gateway; null (no route, not evaluated, or unusable) keeps the settings
   * path in `resolution`.
   */
  routes?: Readonly<{ plan: () => AiRoute | null; questions: () => AiRoute | null }>;
  /**
   * The research library searched for this athlete with the given queries (chunk E5): the excerpts
   * the gateway plan prompt shows, which the plan may cite. Never throws. Absent (no library
   * wiring) leaves the plan built without excerpts, as before.
   */
  library?: (queries: readonly string[]) => Promise<PlanLibrary>;
  /** The gateway's fetch and clock (tests pass fakes). */
  gateway?: GatewayDeps;
  generate?: typeof generateOnboardingProposal;
  askQuestions?: typeof generateFollowUpQuestions;
  /** Waits between polls of a claim another request holds. */
  sleep?: (ms: number) => Promise<void>;
}>;

/**
 * The hash follow-up questions are stored under: the answers without the
 * follow-ups themselves or a revision note, with the Apple Health data. Any
 * other edit changes it, so stale follow-up answers are never used.
 */
export function followUpsHash(
  answers: OnboardingAnswers,
  health: HealthSummary | null,
  history: HealthHistory | null,
): Promise<string> {
  const { follow_ups: _followUps, revision_note: _revision, ...asked } = answersSnapshot(
    answers,
  );
  return sha256({ policy_version: onboardingPolicyVersion, answers: asked, health, history });
}

export async function handleOnboardingPlan(deps: HandlerDeps): Promise<Response> {
  const draft = await deps.store.loadDraft();
  if (!draft) return reply(422, { error: "onboarding_draft_incomplete" });
  const asked: AnswersResult = parseOnboardingAnswers(
    draft.path,
    draft.payload,
    deps.currentYear,
  );
  if (!asked.ok) {
    return reply(422, { error: "onboarding_answers_incomplete", missing: asked.missing });
  }
  const screening = await deps.store.screening();
  if (screening === null) {
    return reply(422, { error: "onboarding_answers_incomplete", missing: ["screening"] });
  }
  const catalog = await deps.store.loadCatalog();
  const { health, history } = await loadHealthContext(deps);
  try {
    validRulesPlan(policiesFor(asked.answers, catalog, health, history, screening));
  } catch (error) {
    if (error instanceof PlanBlockedByScreeningError) {
      return reply(422, { error: "onboarding_screening_see_professional" });
    }
    if (!(error instanceof OnboardingPlanInfeasibleError)) throw error;
    return reply(422, {
      error: "onboarding_plan_infeasible",
      rule: error.rule,
      change: answersToChange(error.rule, asked.answers),
    });
  }
  const questionsHash = await followUpsHash(asked.answers, health, history);
  if (deps.mode === "questions") {
    return await handleQuestions(deps, asked.answers, health, history, questionsHash);
  }
  // Follow-up answers count only when they were given for these answers.
  const parsed = parseOnboardingAnswers(
    draft.path,
    draft.payload,
    deps.currentYear,
    questionsHash,
  ) as Extract<AnswersResult, { ok: true }>;
  const snapshot = {
    schema_version: "2.0",
    policy_version: onboardingPolicyVersion,
    catalog_version: catalogVersion,
    answers: answersSnapshot(parsed.answers),
    // Part of the hash: connecting Apple Health builds a new plan, the same
    // data reuses the existing one.
    health,
    health_history: history,
    // Part of the hash when it limits the plan, so a changed outcome builds a new plan; a cleared
    // athlete's snapshot (and every older one) is unchanged.
    ...(screening === "cleared" ? {} : { screening }),
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
      history,
      screening,
    ),
  );
  return reply(202, body);
}

/**
 * The settings path sends the athlete's data to its own provider (DeepSeek, Groq or Gemini), so
 * a granted notice covers it only when the notice names that vendor. A notice with no vendor
 * (provider null) predates vendor names: it is the notice published for the settings path, so it
 * keeps covering it. A notice that names another vendor (Anthropic after cutover) does not, and
 * a fallback or rollback to the settings path then sends nothing.
 */
export function legacyNoticeConsent(
  answer: AiConsentWithProvider,
  vendor: AiVendor,
): AiCoachingConsent {
  if (answer.consent !== "granted") return answer.consent;
  return answer.provider === null || answer.provider === vendor ? "granted" : "not_granted";
}

/** The athlete's current notice names the vendor the route sends to. */
const namesVendor = (answer: AiConsentWithProvider, route: AiRoute) =>
  answer.consent === "granted" && answer.provider === route.vendor;

async function handleQuestions(
  deps: HandlerDeps,
  answers: OnboardingAnswers,
  health: HealthSummary | null,
  history: HealthHistory | null,
  questionsHash: string,
): Promise<Response> {
  const { store, observer } = deps;
  const respond = (stored: StoredQuestions) =>
    reply(200, {
      schema_version: "1.0",
      questions_hash: questionsHash,
      questions: stored.questions,
      ...(stored.skipped_reason ? { skipped_reason: stored.skipped_reason } : {}),
    });
  // The gateway answers when its route is usable and evaluated; otherwise the settings path does.
  const gatewayRoute = deps.routes?.questions() ?? null;
  let gateway:
    | { route: AiRoute; prepared: Extract<QuestionsPreparation, { kind: "ready" }> }
    | null = null;
  if (gatewayRoute) {
    const prepared = prepareQuestions(gatewayRoute, answers, health, history);
    if (prepared.kind === "ready") gateway = { route: gatewayRoute, prepared };
    else observer.warn("onboarding_questions_route_unusable", { fallbackReason: prepared.reason });
  }
  const resolution = deps.resolution();
  let consentGranted = false;
  let budgetAvailable = false;
  let closed: string | null;
  if (gateway) {
    // A notice that does not name the route's vendor is no consent: nothing is sent.
    consentGranted = namesVendor(await store.gatewayConsent("onboarding_questions"), gateway.route);
    if (consentGranted) {
      budgetAvailable = await store.reserveGatewayBudget(
        "onboarding_questions",
        gateway.prepared.ceilingUsd,
      );
    }
    closed = !consentGranted
      ? "ai_consent_not_granted"
      : !budgetAvailable
      ? "ai_usage_limit"
      : null;
  } else {
    if (resolution.kind === "model") {
      consentGranted =
        (await store.consent("onboarding_questions", resolution.config.provider)) === "granted";
      if (consentGranted) budgetAvailable = await store.budgetAvailable();
    }
    closed = followUpGateReason(resolution, { consentGranted, budgetAvailable });
  }
  if (closed !== null) return respond({ questions: [], skipped_reason: closed, metadata: null });
  try {
    return await askOrReuse(
      deps,
      resolution,
      answers,
      health,
      history,
      questionsHash,
      gateway,
      respond,
    );
  } finally {
    // The place is given back whatever happened; a call of unknown cost kept it before this.
    if (gateway) await store.releaseBudget();
  }
}

async function askOrReuse(
  deps: HandlerDeps,
  resolution: OnboardingModelResolution,
  answers: OnboardingAnswers,
  health: HealthSummary | null,
  history: HealthHistory | null,
  questionsHash: string,
  gateway: { route: AiRoute; prepared: Extract<QuestionsPreparation, { kind: "ready" }> } | null,
  respond: (stored: StoredQuestions) => Response,
): Promise<Response> {
  const { store, observer } = deps;
  const gate = { consentGranted: true, budgetAvailable: true };
  const sleep = deps.sleep ?? ((ms: number) => new Promise((done) => setTimeout(done, ms)));
  let claim = await store.claimQuestions(questionsHash);
  for (
    let waited = 0;
    !claim.started && !claim.stored && waited < questionsWaitMs;
    waited += questionsPollMs
  ) {
    await sleep(questionsPollMs);
    claim = await store.claimQuestions(questionsHash);
  }
  if (claim.stored) return respond(claim.stored);
  if (!claim.started) {
    return respond({ questions: [], skipped_reason: "questions_in_progress", metadata: null });
  }
  const release = async () => {
    try {
      await store.releaseQuestions(questionsHash);
    } catch (error) {
      // The claim then lapses with its lease.
      observer.error("onboarding_questions_claim_not_released", error, {});
    }
  };
  let result: FollowUpResult;
  let spend: GatewaySpend | null = null;
  try {
    if (gateway) {
      const answered: GatewayQuestionsResult = await generateQuestionsViaGateway(
        gateway.route,
        gateway.prepared,
        gatewayDeps(deps),
      );
      spend = answered.spend;
      result = answered;
    } else {
      result = await (deps.askQuestions ?? generateFollowUpQuestions)(
        answers,
        resolution,
        gate,
        health,
        history,
      );
    }
  } catch (error) {
    await release();
    throw error;
  }
  // A call that may have been billed with no usage known keeps its place at the ceiling.
  if (gateway ? spend === "unknown" : result.skippedReason === "provider_timeout") {
    store.keepBudget?.();
  }
  if (result.usage) {
    try {
      await store.recordQuestionUsage(result.usage);
    } catch (error) {
      observer.error("onboarding_questions_usage_not_recorded", error, {});
    }
  }
  const metadata = result.usage
    ? {
      thinking: result.usage.thinking,
      latency_ms: result.usage.latencyMs,
      attempts: 1,
      input_units: result.usage.inputUnits,
      output_units: result.usage.outputUnits,
      reasoning_units: result.usage.reasoningUnits,
      finish_reason: result.usage.finishReason,
    }
    : null;
  const outcome: StoredQuestions = {
    questions: result.questions,
    skipped_reason: result.skippedReason,
    metadata,
  };
  observer.info("onboarding_questions_generated", {
    questions: result.questions.length,
    skippedReason: result.skippedReason,
    metadata,
  });
  // A failed call is not stored, so a retry may ask again; the model's answer
  // is final for these answers.
  if (result.skippedReason?.startsWith("provider_")) {
    await release();
    return respond(outcome);
  }
  return respond(await store.saveQuestions(questionsHash, outcome));
}

const gatewayDeps = (deps: HandlerDeps): GatewayDeps => ({
  ...deps.gateway,
  info: (event, fields) => deps.observer.info(event, fields),
});

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
 * The 28 complete days before the athlete's local today, and their usual
 * completed months, summarised; each null without Apple Health data
 * (ALGORITHMS §9).
 */
async function loadHealthContext(
  deps: HandlerDeps,
): Promise<{ health: HealthSummary | null; history: HealthHistory | null }> {
  const today = localDate(deps.now(), await deps.store.timezone());
  const recent = healthWindow(today);
  const months = historyWindow(today);
  const [{ days, workouts }, rows] = await Promise.all([
    deps.store.loadHealth(recent.from, recent.through),
    deps.store.loadHealthHistory(months.from, months.through),
  ]);
  return {
    health: summarizeHealth(days, workouts, today),
    history: summarizeHealthHistory(rows, today),
  };
}

async function runGeneration(
  deps: HandlerDeps,
  generationId: string,
  snapshotHash: string,
  snapshot: Record<string, unknown>,
  answers: OnboardingAnswers,
  catalog: CatalogExercise[],
  health: HealthSummary | null,
  history: HealthHistory | null,
  screening: ScreeningOutcome,
): Promise<void> {
  const { store, observer } = deps;
  let viaGateway = false;
  try {
    // The gateway answers when its route is usable and evaluated; otherwise the settings path does.
    const gatewayRoute = deps.routes?.plan() ?? null;
    let prepared: PreparedPlan | null = null;
    if (gatewayRoute) {
      // The library is searched for this athlete before the prompt is built: its excerpts are part
      // of the prompt and of its cost ceiling. Only the gateway path shows excerpts; the rules plan
      // and the settings path are built without them.
      const library = deps.library
        ? await deps.library(onboardingLibraryQueries({
          goal: answers.goal,
          experience: answers.experience,
          trainingDays: answers.trainingWeekdays.length,
          sessionMinutes: answers.sessionMinutes,
          focusMuscles: answers.priorityMuscles,
        }))
        : null;
      if (library) observer.info("onboarding_library", { generationId, ...library.trace });
      const preparation = preparePlan(
        gatewayRoute,
        answers,
        catalog,
        health,
        history,
        screening,
        library,
      );
      if (preparation.kind === "ready") prepared = preparation.prepared;
      else observer.warn("onboarding_plan_route_unusable", { fallbackReason: preparation.reason });
    }
    let result: GenerationResult;
    // A model was asked: its plan not being used is worth a look.
    let asked: boolean;
    let provider: string | null;
    if (gatewayRoute && prepared) {
      viaGateway = true;
      const answered = await generateViaGateway(
        deps,
        gatewayRoute,
        prepared,
        answers,
        catalog,
        health,
        history,
        screening,
      );
      result = answered.result;
      asked = answered.asked;
      provider = asked ? gatewayRoute.vendor : null;
    } else {
      const resolution = deps.resolution();
      let consentGranted = false;
      let budgetAvailable = false;
      if (resolution.kind === "model") {
        consentGranted =
          (await store.consent("onboarding_plan", resolution.config.provider)) === "granted";
        if (consentGranted) budgetAvailable = await store.budgetAvailable();
      }
      result = await (deps.generate ?? generateOnboardingProposal)(
        answers,
        catalog,
        resolution,
        { consentGranted, budgetAvailable },
        fetch,
        undefined,
        health,
        history,
        screening,
      );
      // A call that failed with no HTTP answer (a timeout or a dropped
      // connection) may still have been billed with no usage reported.
      if (
        result.fallbackReason === "provider_timeout" ||
        result.attempts.some((attempt) =>
          attempt.outcome === "call_failed" && attempt.httpStatus === null
        )
      ) {
        store.keepBudget?.();
      }
      asked = result.usage !== null;
      provider = result.usage?.provider ?? null;
    }
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
      provider,
      model: result.usage?.model ?? null,
      fallbackReason: result.fallbackReason,
      attempts: result.attempts,
      metadata: generationMetadata(result),
    };
    if (asked && result.fallbackReason) {
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
  } finally {
    // The place is given back once the usage is recorded or when nothing was spent; a call of
    // unknown cost kept it before this.
    if (viaGateway) await store.releaseBudget();
  }
}

/**
 * The plan through the gateway. A notice that does not name the route's vendor, or a budget that
 * will not take the worst case, sends nothing and builds the rules plan.
 */
async function generateViaGateway(
  deps: HandlerDeps,
  gatewayRoute: AiRoute,
  prepared: PreparedPlan,
  answers: OnboardingAnswers,
  catalog: CatalogExercise[],
  health: HealthSummary | null,
  history: HealthHistory | null,
  screening: ScreeningOutcome,
): Promise<{ result: GenerationResult; asked: boolean }> {
  const { store } = deps;
  const rulesPlan = async (reason: string) => ({
    result: await generateOnboardingProposal(
      answers,
      catalog,
      { kind: "rules", reason },
      { consentGranted: false, budgetAvailable: false },
      fetch,
      undefined,
      health,
      history,
      screening,
    ),
    asked: false,
  });
  if (!namesVendor(await store.gatewayConsent("onboarding_plan"), gatewayRoute)) {
    return await rulesPlan("ai_consent_not_granted");
  }
  if (!(await store.reserveGatewayBudget("onboarding_plan", prepared.ceilingUsd))) {
    return await rulesPlan("ai_usage_limit");
  }
  const answered: GatewayPlanResult = await generatePlanViaGateway(
    gatewayRoute,
    prepared,
    gatewayDeps(deps),
  );
  if (answered.spend === "unknown") store.keepBudget?.();
  return { result: answered, asked: answered.asked };
}
