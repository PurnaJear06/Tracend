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
} from "../_shared/onboarding/generate.ts";
import type { OnboardingProposalPayload } from "../_shared/onboarding/plan_contract.ts";
import { onboardingPolicyVersion } from "../_shared/onboarding/policy.ts";
import { sha256 } from "../_shared/onboarding/snapshot.ts";
import type { OnboardingModelResolution } from "../_shared/providers/onboarding_plan_provider.ts";

// POST onboarding-plan: start (or return) the athlete's onboarding plan
// generation and answer at once with its id. The plan is built in the
// background; the app polls get_my_onboarding_generation. A repeated request
// with the same answers returns the same generation.

/** Longer than the 75 s model deadline plus storing, shorter than Edge limits. */
export const generationLeaseSeconds = 140;

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
  consent(): Promise<AiCoachingConsent>;
  budgetAvailable(): Promise<boolean>;
  recordUsage(usage: GenerationUsage): Promise<void>;
  /** "superseded" when a newer generation replaced this one meanwhile. */
  persist(
    generationId: string,
    snapshotHash: string,
    snapshot: Record<string, unknown>,
    proposal: OnboardingProposalPayload,
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
  const snapshot = {
    schema_version: "2.0",
    policy_version: onboardingPolicyVersion,
    catalog_version: catalogVersion,
    answers: answersSnapshot(parsed.answers),
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
  deps.background(runGeneration(deps, claim.generation_id, snapshotHash, snapshot, parsed.answers));
  return reply(202, body);
}

async function runGeneration(
  deps: HandlerDeps,
  generationId: string,
  snapshotHash: string,
  snapshot: Record<string, unknown>,
  answers: OnboardingAnswers,
): Promise<void> {
  const { store, observer } = deps;
  try {
    const catalog = await store.loadCatalog();
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
    };
    // A model was asked and its plan was not used: worth a look.
    if (result.usage && result.fallbackReason) {
      observer.warn("onboarding_plan_model_fallback", fields);
    } else {
      observer.info("onboarding_plan_generated", fields);
    }
    const stored = await store.persist(generationId, snapshotHash, snapshot, result.proposal);
    if (stored === "superseded") {
      observer.info("onboarding_plan_superseded", { generationId });
    }
  } catch (error) {
    observer.error("onboarding_plan_generation_failed", error, { generationId });
    try {
      await store.fail(generationId, "generation_failed");
    } catch (failError) {
      // The lease expires on its own; the app then reads the generation as failed.
      observer.error("onboarding_plan_failure_not_recorded", failError, { generationId });
    }
  }
}
