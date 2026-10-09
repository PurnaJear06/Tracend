import { reply } from "../_shared/auth.ts";
import {
  type MealCandidate,
  MealVisionBilledError,
  type MealVisionUsage,
} from "../_shared/providers/gemini_meal_vision_provider.ts";
import { isUserStorageKey } from "../_shared/storage_keys.ts";

// POST meal-analyze {"schema_version":"1.0","meal_id":…}: sends the photo of
// one of the athlete's meal drafts to the meal vision provider and stores the
// candidates for review. The call's usage is recorded whenever the provider
// answered, before anything else can fail, so every billed call counts.

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type MealVisionResult = MealVisionUsage & Readonly<{ candidates: MealCandidate[] }>;

export type MealDraft = Readonly<{ objectKey: unknown; contentType: string }>;

/** What is stored for review: the candidate without the model's notes. */
export type StoredMealCandidate = Omit<MealCandidate, "assumptions" | "question">;

export interface MealAnalyzeStore {
  /** Takes a place in the AI budget; false when a limit is reached. */
  reserveBudget(): Promise<boolean>;
  /** Leaves the place open: the call may have been billed with no usage known. */
  keepBudget(): void;
  /** The athlete's own photo draft, or null. */
  loadDraft(mealId: string): Promise<MealDraft | null>;
  download(objectKey: string): Promise<Uint8Array | null>;
  recordUsage(usage: MealVisionUsage, latencyMs: number): Promise<void>;
  persistCandidates(
    mealId: string,
    candidates: readonly StoredMealCandidate[],
    model: string,
  ): Promise<boolean>;
  discardDraft(mealId: string): Promise<boolean>;
}

export type MealAnalyzeLog = Readonly<{
  info(event: string, fields?: Record<string, unknown>): void;
  warn(event: string, fields?: Record<string, unknown>): void;
  error(event: string, fields?: Record<string, unknown>): void;
}>;

export type MealAnalyzeDependencies = Readonly<{
  userId: string;
  provider: "groq" | "gemini";
  analyze: (bytes: Uint8Array, contentType: string) => Promise<MealVisionResult>;
  store: MealAnalyzeStore;
  log: MealAnalyzeLog;
  report: (error: unknown, mealId: string) => void;
  now?: () => number;
}>;

// Errors raised before the provider was reached, or a refusal it answered
// without billing.
const unbilled =
  /^(meal_vision_disabled|meal_vision_configuration_invalid|meal_image_invalid|meal_vision_request_failed)/;

export async function handleMealAnalyze(
  body: unknown,
  dependencies: MealAnalyzeDependencies,
): Promise<Response> {
  const { store, log } = dependencies;
  const now = dependencies.now ?? (() => performance.now());
  const started = now();
  const request = body as Record<string, unknown> | null;
  if (
    request === null || typeof request !== "object" || request.schema_version !== "1.0" ||
    typeof request.meal_id !== "string" || !uuid.test(request.meal_id)
  ) {
    return reply(422, { error: "invalid_meal_request" });
  }
  const mealId = request.meal_id;
  if (!await store.reserveBudget()) return reply(429, { error: "ai_usage_limit" });
  const draft = await store.loadDraft(mealId);
  if (!draft) return reply(404, { error: "meal_not_found" });
  if (!isUserStorageKey(dependencies.userId, draft.objectKey)) {
    log.warn("unsafe_meal_object_key");
    return reply(404, { error: "meal_not_found" });
  }
  const image = await store.download(draft.objectKey);
  if (!image) return reply(503, { error: "meal_image_unavailable" });
  let result: MealVisionResult;
  try {
    result = await dependencies.analyze(image, draft.contentType);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (error instanceof MealVisionBilledError) {
      await store.recordUsage(error.usage, Math.round(now() - started));
    } else if (!unbilled.test(message)) {
      store.keepBudget();
    }
    if (message.startsWith("meal_vision_request_failed:429:")) {
      // Groq's free tier allows about one photo a minute. Busy, not broken.
      log.warn("meal_analysis_busy", { detail: message });
      return reply(429, { error: "meal_vision_busy" });
    }
    dependencies.report(error, mealId);
    log.error("meal_analysis_unavailable", {
      detail: message,
      latency_ms: Math.round(now() - started),
    });
    return reply(503, { error: "meal_analysis_unavailable" });
  }
  const latencyMs = Math.round(now() - started);
  await store.recordUsage(result, latencyMs);
  if (result.candidates.length === 0) {
    // The model looked and found no food. That is an answer, not an outage.
    // Nothing to review, so the draft goes, the way the app deletes a meal
    // (which also schedules the photo for deletion). A failed removal leaves a
    // draft with no candidates; the answer still stands.
    if (!await store.discardDraft(mealId)) log.warn("meal_no_food_draft_not_removed");
    log.info("meal_analysis_no_food", {
      latency_ms: latencyMs,
      provider: dependencies.provider,
      model: result.model,
    });
    return reply(422, { error: "meal_no_food_found" });
  }
  const persistenceCandidates = result.candidates.map((
    { assumptions: _assumptions, question: _question, ...candidate },
  ) => candidate);
  if (!await store.persistCandidates(mealId, persistenceCandidates, result.model)) {
    return reply(422, { error: "meal_analysis_rejected" });
  }
  log.info("meal_analysis_complete", {
    latency_ms: latencyMs,
    provider: dependencies.provider,
    model: result.model,
  });
  return reply(200, { schema_version: "1.0", meal_id: mealId, candidates: result.candidates });
}
