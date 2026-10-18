import {
  type CoachChatAnswerV2,
  type CoachChatRequestV1,
  type CoachChatValidationRule,
  parseCoachChatRequest,
} from "../_shared/contracts/coach_chat_v1.ts";
import { createLogger, extractCorrelationId } from "../_shared/logger.ts";
import {
  buildCoachChatDataSummary,
  coachChatDataSummaryModel,
} from "../_shared/coach_chat_fallback.ts";
import {
  classifyQuestion,
  coachChatFailureUsage,
  coachChatTiming,
  CoachChatUnavailableError,
  deterministicSafetyGeneration,
  generateCoachChat,
  legacyCoachChatVendor,
} from "../_shared/providers/coach_chat_provider.ts";
import {
  type AttemptStore,
  coachChatTurnStaleAfterMs,
  earlierAttempts,
  questionAgeMs,
  type StoredQuestion,
  supersededSafetyState,
  supersedeFailedAttempts,
  withoutSupersededMemory,
  withoutSupersededQuestions,
} from "./superseded.ts";
import { referralFor } from "../_shared/coach_safety/referrals.ts";
import { selectCoachChatRoute } from "../_shared/providers/coach_chat_provider_route.ts";
import {
  localDateIn,
  type RedFlagHit,
  screenCheckInRow,
  screenMessage,
  screenTurn,
  trainingQuestion,
} from "../_shared/coach_safety/red_flags.ts";
import { previousQuestionsOf } from "../_shared/library/query.ts";
import { prefetchLibraryEmbedding } from "../_shared/library/live.ts";
import { libraryContributorId } from "../_shared/library/retrieval.ts";
import { loadMemoryContext, recordMemoryAfterTurn } from "../_shared/coach_memory/store.ts";
import {
  noSuggestions,
  runInBackground,
  suggestionsForTurn,
  threadIsRemembered,
  turnForNote,
  type TurnSuggestions,
} from "./memory.ts";
import {
  chooseCoachChatRoute,
  coachChatReservationUsd,
  generateCoachChatViaGateway,
} from "../_shared/providers/coach_chat_provider_gateway.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { captureException } from "../_shared/sentry.ts";
import { attemptLogFields, reportSlowTurn, sentryAttemptsOf } from "./attempt_telemetry.ts";
import {
  aiCoachingConsent,
  type AiConsentWithProvider,
  aiConsentWithProvider,
  type AiVendor,
  coachChatConsentRefusal,
} from "../_shared/ai_consent.ts";
import { CoachChatBudgetLedger, keepAfterFailure } from "./budget_ledger.ts";
import { route } from "../_shared/ai/routes.ts";
import type { AiFeature, AiRoute } from "../_shared/ai/types.ts";
import {
  noCoachContributions,
  renderCoachContext,
  validateCoachContextContributors,
} from "../_shared/coach_context/host.ts";
import {
  coachContextContributors,
  coachContextContributorsFor,
} from "../_shared/coach_context/registry.ts";
import { coachServiceRpc } from "../_shared/coach_context/service_source.ts";
import { createLookupRunner } from "../_shared/coach_lookups/runner.ts";
import { proposeFromChat } from "../_shared/coach_proposals/chat.ts";
import { guardFaultsOf, lookupTrace, recordTurnTrace } from "./turn_trace.ts";

export const coachChatResponseSchemaVersion = "1.1";
// Request 1.1 (current app) gets response 1.2: answer_source on every message
// and a labeled data-summary reply instead of a 503. Request 1.0 (older
// installed builds) keeps response 1.1 unchanged.
export const coachChatDataSummaryResponseSchemaVersion = "1.2";

export function supportsDataSummary(
  request: Pick<CoachChatRequestV1, "schema_version">,
): boolean {
  return request.schema_version === "1.1";
}

function versionedResponse(payload: Record<string, unknown>): Record<string, unknown> {
  return { schema_version: coachChatResponseSchemaVersion, ...payload };
}

export function coachChatFailureResponse(
  error: CoachChatUnavailableError,
): Record<string, unknown> {
  return versionedResponse({
    error: "chat_unavailable",
    code: error.failureReason,
    retry_after_seconds: error.retryAfterSeconds,
  });
}

// Context preparation raises fixed messages. Each maps to a finite code, so a
// blocked turn names its cause in Sentry and in the beta app without free text.
const coachChatPreparationFailures: Readonly<Record<string, string>> = {
  "thread not found": "thread_not_found",
  "invalid chat request": "invalid_chat_request",
  "account not found": "account_not_found",
  "approved plan required": "approved_plan_required",
  "invalid timezone": "invalid_timezone",
  "daily rate limit reached": "daily_rate_limit",
  "monthly cost limit reached": "monthly_cost_limit",
  "chat context too large": "chat_context_too_large",
};

/**
 * With a gateway route, what coach-chat answers instead of calling the model, or null to go on.
 * The athlete's current Coach notice must be granted and name the route's vendor; a notice for
 * another vendor (or none) takes the consent-needed path and nothing is sent.
 */
export function coachChatGatewayConsentRefusal(
  consent: AiConsentWithProvider,
  coachRoute: AiRoute,
): { status: 403 | 503; error: string } | null {
  const refusal = coachChatConsentRefusal(consent.consent);
  if (refusal) return refusal;
  return consent.provider === coachRoute.vendor
    ? null
    : { status: 403, error: "ai_consent_required" };
}

/**
 * Without a gateway route, today's provider receives the data, so the athlete's current Coach
 * notice must name that vendor. A notice that predates vendor names (provider null) is the one
 * published for today's provider and keeps working; a notice naming another vendor (for example
 * Anthropic after cutover) never covers a fallback or rollback to DeepSeek, Groq or Gemini.
 */
export function coachChatLegacyConsentRefusal(
  consent: AiConsentWithProvider,
  legacyVendor: AiVendor,
): { status: 403 | 503; error: string } | null {
  const refusal = coachChatConsentRefusal(consent.consent);
  if (refusal) return refusal;
  return consent.provider === null || consent.provider === legacyVendor
    ? null
    : { status: 403, error: "ai_consent_required" };
}

/**
 * The gateway route of a Coach chat feature ("coach_chat", or "coach_chat_strong" for the second
 * route), or null for today's path: no route, a route whose eval has not passed, a route whose
 * first attempt cannot be reserved, or a contributor registry that breaks its contract (checked
 * before any budget place is taken). Each reason except "no route" is logged, as is a route
 * timeout cut to the total deadline.
 */
function usableCoachRoute(
  log: ReturnType<typeof createLogger>,
  feature: Extract<AiFeature, "coach_chat" | "coach_chat_strong"> = "coach_chat",
): AiRoute | null {
  const found = route(feature);
  if (!found) return null;
  try {
    validateCoachContextContributors(coachContextContributors);
  } catch (error) {
    log.error("coach_context_registry_invalid", {
      message: error instanceof Error ? error.message : "unknown",
    });
    captureException(error, { functionName: "coach-chat", runtime: "edge" });
    return null;
  }
  const choice = chooseCoachChatRoute(found, coachContextContributors);
  if (choice.route === null) {
    log.warn("coach_chat_route_not_used", {
      feature,
      reason: choice.legacyReason,
      model: found.model,
    });
    return null;
  }
  if (choice.timeoutClamped) {
    log.warn("coach_chat_route_timeout_clamped", {
      feature,
      route_timeout_ms: choice.route.timeoutMs,
      limit_ms: coachChatTiming.totalDeadlineMs,
    });
  }
  return choice.route;
}

export function coachChatPreparationFailureCode(
  error: { code?: string; message?: string } | null,
): string {
  if (!error) return "missing_prepared_context";
  const known = coachChatPreparationFailures[error.message ?? ""];
  if (known) return known;
  return /^[0-9A-Z]{5}$/.test(error.code ?? "") ? `sqlstate_${error.code}` : "unknown";
}

export function coachChatFailureRules(error: CoachChatUnavailableError): CoachChatValidationRule[] {
  return [error.metadata.initialRule, error.metadata.repairRule].filter(
    (rule): rule is CoachChatValidationRule => rule !== undefined,
  );
}

export function coachChatDataSummaryResponse(
  summary: CoachChatAnswerV2,
  error: CoachChatUnavailableError,
  stored: { assistant_message_id?: string; created_at?: string } | null,
  budgetWarning: unknown,
): Record<string, unknown> {
  return {
    schema_version: coachChatDataSummaryResponseSchemaVersion,
    message: {
      id: stored?.assistant_message_id ?? crypto.randomUUID(),
      role: "assistant",
      created_at: stored?.created_at ?? new Date().toISOString(),
      model_provider: "deterministic",
      model: coachChatDataSummaryModel,
      answer_source: "data_summary",
      diagnostic: {
        failure_code: error.failureReason,
        initial_rule: error.metadata.initialRule ?? null,
        repair_rule: error.metadata.repairRule ?? null,
      },
      ...summary,
    },
    budget_warning: budgetWarning,
    replayed: false,
  };
}

export type CoachChatTurn = Readonly<{
  state?: string;
  failure_code?: string | null;
  model_provider?: string | null;
  model?: string | null;
  message?: Readonly<Record<string, unknown>> | null;
}>;

// A request retried with the same idempotency key gets what its first attempt
// produced and never runs the model again. The question is saved when a turn
// starts, so a saved question alone is not a completed reply: the turn is
// answered, failed, or still in progress.
//
// A turn still in progress after `coachChatTurnStaleAfterMs` (`ageMs`, the age of its saved
// question) is lost: it answers 503 `turn_lost` once and for every retry of that key, so the app
// stops waiting and sends the message again under a new key. Without an age, or while the turn is
// young, it answers 409 as before.
export function coachChatReplayResponse(
  turn: CoachChatTurn | null | undefined,
  dataSummarySupported: boolean,
  ageMs: number | null = null,
): { status: number; body: Record<string, unknown> } {
  const message = turn?.message;
  const isDataSummary = message?.answer_source === "data_summary";
  if (turn?.state === "answered" && message && (dataSummarySupported || !isDataSummary)) {
    return {
      status: 200,
      body: {
        schema_version: dataSummarySupported
          ? coachChatDataSummaryResponseSchemaVersion
          : coachChatResponseSchemaVersion,
        message: {
          id: message.id,
          role: "assistant",
          created_at: message.created_at,
          model_provider: isDataSummary ? "deterministic" : turn.model_provider,
          model: isDataSummary ? coachChatDataSummaryModel : turn.model,
          ...(dataSummarySupported
            ? { answer_source: isDataSummary ? "data_summary" : "model" }
            : {}),
          answer: message.content,
          evidence: message.evidence ?? [],
          missing_data: message.missing_data ?? [],
          safety_state: message.safety_state,
          suggested_follow_ups: [],
          // The proposal the first attempt introduced, when the turn row carries it.
          ...(typeof message.proposal_id === "string" ? { proposal_id: message.proposal_id } : {}),
        },
        replayed: true,
      },
    };
  }
  if (turn?.state === "answered" || turn?.state === "failed") {
    return {
      status: 503,
      body: versionedResponse({
        error: "chat_unavailable",
        code: turn.failure_code ?? "provider_response_invalid",
        retry_after_seconds: null,
        replayed: true,
      }),
    };
  }
  if (ageMs !== null && ageMs > coachChatTurnStaleAfterMs) {
    return {
      status: 503,
      body: versionedResponse({
        error: "chat_unavailable",
        code: "turn_lost",
        retry_after_seconds: null,
        replayed: true,
      }),
    };
  }
  return {
    status: 409,
    body: versionedResponse({
      error: "chat_in_progress",
      code: "request_in_progress",
      replayed: true,
    }),
  };
}

/**
 * With a question about training, today's check-in read straight from the table (a cheap read,
 * no budget): pain of 7 or more answers with the referral before the consent and budget gates.
 * A failed read lets the turn go on: the providers screen again with the prepared context.
 */
async function screenTodaysCheckIn(
  client: Awaited<ReturnType<typeof requireAuth>>["serviceClient"],
  userId: string,
  question: string,
  timezone: string,
  log: ReturnType<typeof createLogger>,
): Promise<RedFlagHit | null> {
  if (!trainingQuestion(question)) return null;
  try {
    const { data, error } = await client.from("daily_check_ins")
      .select("local_date,pain_severity").eq("user_id", userId).is("superseded_at", null)
      .order("local_date", { ascending: false }).limit(1).maybeSingle();
    if (error) {
      log.warn("coach_chat_check_in_unread", { error_code: error.code ?? "unknown" });
      return null;
    }
    return screenCheckInRow(
      data as { local_date?: unknown; pain_severity?: unknown } | null,
      localDateIn(timezone),
      question,
    );
  } catch {
    log.warn("coach_chat_check_in_unread", { error_code: "exception" });
    return null;
  }
}

/**
 * The fixed referral for a red flag when the context could not be prepared. It is stored through
 * the lightest path there is (the question, then the reply as a labelled deterministic reply: no
 * snapshot, policy or model run is needed) and returned whether or not storing worked; a storing
 * failure is logged. Stored this way it is a labelled deterministic reply with the referral's own safety state.
 */
async function referralWithoutContext(
  client: Awaited<ReturnType<typeof requireAuth>>["serviceClient"],
  userId: string,
  input: CoachChatRequestV1,
  hit: RedFlagHit,
  log: ReturnType<typeof createLogger>,
): Promise<Response> {
  log.warn("coach_chat_red_flag", { category: hit.category, rule: hit.rule, source: hit.source });
  // The same state as the normal path: `refused` for self-harm and unsupported requests.
  const referral = referralFor(hit);
  let stored: { assistant_message_id?: string; created_at?: string } | null = null;
  try {
    const { error: recordError } = await client.rpc("record_coach_chat_question", {
      target_user_id: userId,
      target_thread_id: input.thread_id,
      question: input.question,
      request_idempotency_key: input.idempotency_key,
    });
    if (recordError) log.error("referral_question_not_recorded", { error_code: recordError.code });
    const { data, error } = await client.rpc("persist_coach_chat_data_summary", {
      target_user_id: userId,
      target_thread_id: input.thread_id,
      request_idempotency_key: input.idempotency_key,
      summary_payload: referral,
    });
    if (error) log.error("referral_not_stored", { error_code: error.code ?? "unknown" });
    else stored = data;
  } catch {
    log.error("referral_not_stored", { error_code: "exception" });
  }
  const message = {
    id: stored?.assistant_message_id ?? crypto.randomUUID(),
    role: "assistant",
    created_at: stored?.created_at ?? new Date().toISOString(),
    model_provider: "deterministic",
    model: coachChatDataSummaryModel,
    ...(supportsDataSummary(input) ? { answer_source: "data_summary" } : {}),
    ...referral,
  };
  return reply(200, {
    schema_version: supportsDataSummary(input)
      ? coachChatDataSummaryResponseSchemaVersion
      : coachChatResponseSchemaVersion,
    message,
    budget_warning: null,
    replayed: false,
  });
}

/** The database side of superseding a failed attempt (see superseded.ts), on the service client. */
function attemptStore(
  client: Awaited<ReturnType<typeof requireAuth>>["serviceClient"],
  userId: string,
  threadId: string,
  question: string,
  currentKey: string,
): AttemptStore {
  return {
    async copies() {
      // The state and the text are compared in code (superseded.ts): in SQL, `<>` drops the NULL
      // `safety_state` that user messages normally have, and a row may be stored untrimmed.
      const { data, error } = await client.from("coach_messages")
        .select("id,idempotency_key,content,safety_state,created_at")
        .eq("user_id", userId).eq("thread_id", threadId).eq("role", "user")
        .order("created_at", { ascending: false }).limit(40);
      if (error) throw new Error("copies unreadable");
      return earlierAttempts((data ?? []) as StoredQuestion[], question, currentKey).slice(0, 5);
    },
    async turn(key) {
      const { data, error } = await client.rpc("coach_chat_turn", {
        target_user_id: userId,
        request_idempotency_key: key,
      });
      return error ? null : data as never;
    },
    async mark(ids) {
      const { error } = await client.from("coach_messages")
        .update({ safety_state: supersededSafetyState }).eq("user_id", userId).in("id", [...ids]);
      if (error) throw new Error("mark failed");
    },
  };
}

// Every budget reservation a request takes is released when it ends, however
// it ends; a reservation kept open (`AiBudget.keep`) stays counted.
Deno.serve(async (request) => {
  const budget: { current?: CoachChatBudgetLedger } = {};
  try {
    return await handleCoachChat(request, budget);
  } finally {
    await budget.current?.release();
  }
});

export async function handleCoachChat(
  request: Request,
  held: { current?: CoachChatBudgetLedger },
  authenticate: typeof requireAuth = requireAuth,
  prefetchLibrary: typeof prefetchLibraryEmbedding = prefetchLibraryEmbedding,
): Promise<Response> {
  const correlationId = extractCorrelationId(request);
  const log = createLogger(correlationId);
  const started = performance.now();
  const startedAtMs = Date.now();
  if (request.method !== "POST") {
    return reply(405, versionedResponse({ error: "method_not_allowed" }));
  }
  let auth;
  try {
    auth = await authenticate(request);
  } catch (e) {
    if (e instanceof AuthError) {
      return reply(e.status, versionedResponse({ error: e.message }));
    }
    throw e;
  }
  let input;
  try {
    input = parseCoachChatRequest(await request.json());
  } catch {
    log.warn("invalid_chat_request");
    return reply(422, versionedResponse({ error: "invalid_chat_request" }));
  }
  // A message that reports a red-flag symptom, or a question about training on a day of check-in
  // pain of 7 or more, is answered by the fixed referral: nothing is sent to an AI provider, so
  // no consent is needed and no budget place is taken (an athlete without consent or budget still
  // gets the referral). The message is not logged, only the rule that fired.
  const redFlag: RedFlagHit | null = screenMessage(input.question) ??
    await screenTodaysCheckIn(auth.serviceClient, auth.userId, input.question, input.timezone, log);
  // With AI_COACH_CHAT_* settings (and EVALUATED=true) the turn goes through the AI gateway;
  // without them, or when the route cannot be used, it keeps today's provider path, request for
  // request. A question that needs analysis (progress, weight, nutrition numbers, the plan) uses
  // the second route (AI_COACH_CHAT_STRONG_*) when it is set and the athlete's notice names its
  // vendor.
  const defaultRoute = redFlag ? null : usableCoachRoute(log);
  let coachRoute = defaultRoute;
  // Nothing reaches the AI provider without the athlete's current consent,
  // whichever app build is calling. Through the gateway the consented notice
  // must also name the route's vendor.
  const rpc = (name: string, params: Record<string, unknown>) =>
    auth.serviceClient.rpc(name, params);
  let consent: "granted" | "not_granted" | "unavailable" = "granted";
  let refusal: { status: 403 | 503; error: string } | null = null;
  let consentVendor: AiConsentWithProvider["provider"] = null;
  if (defaultRoute) {
    const withProvider = await aiConsentWithProvider(rpc, auth.userId, "coach_chat");
    consent = withProvider.consent;
    consentVendor = withProvider.provider;
    const selection = selectCoachChatRoute(
      input.question,
      defaultRoute,
      () => usableCoachRoute(log, "coach_chat_strong"),
      withProvider.provider,
    );
    coachRoute = selection.route;
    if ("strongSkipped" in selection) {
      log.warn("coach_chat_strong_route_not_used", { reason: selection.strongSkipped });
    }
    refusal = coachChatGatewayConsentRefusal(withProvider, selection.route);
  } else if (!redFlag) {
    const legacyVendor = legacyCoachChatVendor(Deno.env);
    if (legacyVendor) {
      const withProvider = await aiConsentWithProvider(rpc, auth.userId, "coach_chat");
      consent = withProvider.consent;
      refusal = coachChatLegacyConsentRefusal(withProvider, legacyVendor);
    } else {
      consent = await aiCoachingConsent(rpc, auth.userId, "coach_chat");
      refusal = coachChatConsentRefusal(consent);
    }
  }
  if (refusal) {
    if (consent === "unavailable") {
      log.error("ai_consent_check_failed");
      captureException(new Error("ai_consent_check_failed"), {
        userId: auth.userId,
        functionName: "coach-chat",
        correlationId,
      });
    }
    return reply(refusal.status, versionedResponse({ error: refusal.error }));
  }
  const budget = new CoachChatBudgetLedger(
    (fn, args) => auth.serviceClient.rpc(fn, args),
    auth.userId,
  );
  held.current = budget;
  const contextKind = classifyQuestion(input.question);

  // A retry of a turn that already started is answered from what that turn produced. The lookup
  // is two cheap reads (the saved question, then `coach_chat_turn`) and comes before the budget
  // and before the heavy context step, so a finished turn is returned even at a spending limit
  // and an athlete at the limit cannot trigger context preparation with every new key.
  const replayResponse = async (
    turn: CoachChatTurn | null | undefined,
    createdAt: unknown,
  ): Promise<Response> => {
    const stillOpen = !turn || turn.state === "in_progress";
    const replay = coachChatReplayResponse(
      turn,
      supportsDataSummary(input),
      stillOpen ? questionAgeMs(createdAt) : null,
    );
    if (replay.status === 200) {
      // Kept from the earlier replay response, which listed the thread.
      const { data } = await auth.userClient.from("coach_messages").select().eq(
        "thread_id",
        input.thread_id,
      ).order("created_at");
      replay.body.messages = data ?? [];
      // The stored reply knows its proposal even when the turn row does not: the replayed answer
      // shows its card.
      const replayed = replay.body.message as Record<string, unknown> | undefined;
      const stored = (data ?? []).find((row: Record<string, unknown>) => row.id === replayed?.id);
      if (replayed && typeof stored?.proposal_id === "string") {
        replayed.proposal_id = stored.proposal_id;
      }
    }
    log.info("coach_chat_replayed", { status: replay.status });
    return reply(replay.status, replay.body);
  };
  // The athlete's saved question for this key (a user message: a reply may carry the same key). A
  // failed read is "unknown", never "not saved".
  const savedQuestionCreatedAt = async (): Promise<
    { saved: boolean | "unknown"; createdAt: unknown }
  > => {
    const { data, error } = await auth.serviceClient.from("coach_messages").select("created_at")
      .eq("user_id", auth.userId).eq("role", "user").eq("idempotency_key", input.idempotency_key)
      .maybeSingle();
    if (error) return { saved: "unknown", createdAt: undefined };
    return {
      saved: data !== null && data !== undefined,
      createdAt: (data as { created_at?: unknown } | null)?.created_at,
    };
  };
  const earlier = await savedQuestionCreatedAt();
  if (earlier.saved === true) {
    const { data: turn, error: turnError } = await auth.serviceClient.rpc("coach_chat_turn", {
      target_user_id: auth.userId,
      request_idempotency_key: input.idempotency_key,
    });
    if (!turnError) return await replayResponse(turn as CoachChatTurn, earlier.createdAt);
  }

  // The gateway path reserves per attempt: this is the first attempt's worst case, and a repair
  // reserves its own before it is sent. A referral calls no model and reserves nothing.
  const reserved = redFlag
    ? true
    : coachRoute
    ? await budget.reserveInitial(coachChatReservationUsd(coachRoute, coachContextContributors)!)
    : await budget.reserveLegacy();
  if (!reserved) {
    return reply(
      429,
      versionedResponse({
        error: "ai_usage_limit",
        ...(budget.refusal ? { reason: budget.refusal } : {}),
      }),
    );
  }

  // The library (gateway route only) embeds the question now: after the replay is resolved and the
  // budget is reserved, so a replay or a request at a limit never costs a library-embed call, and
  // while the context is prepared; the contributor waits for it within its own deadline. A
  // follow-up is embedded later, with the earlier question the prepared context supplies.
  const libraryEmbedding = coachRoute && !redFlag ? prefetchLibrary(input.question) : null;
  const { data: prepared, error: prepareError } = await auth.serviceClient.rpc(
    "prepare_coach_chat_v9",
    {
      target_user_id: auth.userId,
      target_thread_id: input.thread_id,
      question: input.question,
      coaching_timezone: input.timezone,
      request_idempotency_key: input.idempotency_key,
      context_kind: contextKind,
    },
  );
  // A referral needs no context and no model: when preparation fails (an athlete with no plan
  // before the no-plan chat mode is deployed, a database error) the athlete still gets it.
  if ((prepareError || !prepared) && redFlag) {
    log.warn("coach_chat_referral_without_context", {
      reason: coachChatPreparationFailureCode(prepareError),
    });
    return await referralWithoutContext(auth.serviceClient, auth.userId, input, redFlag, log);
  }
  if (prepareError || !prepared) {
    const reason = coachChatPreparationFailureCode(prepareError);
    log.error("prepare_coach_chat_v9 failed", {
      error_code: prepareError?.code ?? "missing_prepared_context",
      reason,
    });
    captureException(new Error(`coach_chat_context_unavailable: ${reason}`), {
      userId: auth.userId,
      functionName: "coach-chat",
      correlationId,
      runtime: "edge",
      contextKind,
      failureCode: reason,
    });
    return reply(
      422,
      versionedResponse({
        error: "chat_unavailable",
        code: "context_preparation_failed",
        reason,
      }),
    );
  }
  // Another request saved the question between the lookup above and now.
  if (prepared.replayed) {
    return await replayResponse(prepared.turn, (await savedQuestionCreatedAt()).createdAt);
  }

  // A fresh-key retry of a message whose earlier attempt failed: the failed attempt's question is
  // marked superseded and left out of the model's memory, so the thread holds the question once.
  const { context, dropped: repeatedQuestions } = withoutSupersededQuestions(
    withoutSupersededMemory(prepared.context as Record<string, unknown>),
    input.question,
  );
  if (repeatedQuestions > 0) {
    try {
      const marked = await supersedeFailedAttempts(
        attemptStore(
          auth.serviceClient,
          auth.userId,
          input.thread_id,
          input.question,
          input.idempotency_key,
        ),
      );
      log.info("coach_chat_attempts_superseded", { marked });
    } catch {
      log.warn("coach_chat_supersede_failed");
    }
  }
  const coachingDate = (context.coaching_date as string) ??
    new Date().toISOString().slice(0, 10);

  // Saved after the context is built (so it is not echoed as history) and
  // before the model runs (so a failed answer cannot erase it).
  const { error: recordError } = await auth.serviceClient.rpc("record_coach_chat_question", {
    target_user_id: auth.userId,
    target_thread_id: input.thread_id,
    question: input.question,
    request_idempotency_key: input.idempotency_key,
  });
  if (recordError) {
    log.error("record_coach_chat_question failed", { error_code: recordError.code ?? "unknown" });
    captureException(new Error("coach_chat_question_not_recorded"), {
      userId: auth.userId,
      functionName: "coach-chat",
      correlationId,
      runtime: "edge",
      failureCode: recordError.code ?? "unknown",
    });
  }

  // Whether the athlete lets Coach remember this conversation (A10 part 2). A conversation that is
  // not remembered gets no suggested facts and no notes. The athlete's memory is read alongside
  // the contributors so the reply never waits for it.
  const memoryRpc = (name: string, params: Record<string, unknown>) =>
    auth.serviceClient.rpc(name, params);
  const remembered = await threadIsRemembered(() =>
    auth.serviceClient.from("coach_threads").select("remember")
      .eq("id", input.thread_id).eq("user_id", auth.userId).maybeSingle()
  );
  const memoryRead = remembered && !redFlag
    ? loadMemoryContext(memoryRpc, auth.userId)
    : Promise.resolve(null);

  const chatStart = performance.now();
  try {
    // Both paths render the contributors (the goal phase review is not tied to the gateway). A
    // referral shows the model nothing, so it renders none.
    // The library is searched for every turn that reaches a model: a red-flag turn (a symptom, or
    // a training question on a pain day) is answered by the fixed referral and retrieves nothing.
    const contributions = redFlag || screenTurn(input.question, context)
      ? noCoachContributions
      : await renderCoachContext(
        coachContextContributorsFor(coachRoute !== null),
        {
          userId: auth.userId,
          question: input.question,
          localDate: coachingDate,
          previousQuestions: previousQuestionsOf(context, input.question),
          ...(libraryEmbedding ? { queryEmbedding: libraryEmbedding } : {}),
        },
      );
    if (contributions.outcomes.length) {
      log.info("coach_context_contributors", { contributors: contributions.outcomes });
    }
    // Source ids, counts, timings and the nearest distance: never the question or a chunk.
    const libraryTrace = contributions.traces?.[libraryContributorId];
    if (libraryTrace) log.info("library_retrieval", { ...libraryTrace });
    const generation = redFlag
      ? deterministicSafetyGeneration(redFlag)
      : coachRoute
      ? await generateCoachChatViaGateway({
        question: input.question,
        context,
        contextKind,
        route: coachRoute,
        consentVendor,
        contributions,
        budget: budget.attemptBudget,
        lookups: createLookupRunner((name, params) => coachServiceRpc(name, params), auth.userId),
        proposals: true,
        factSuggestions: remembered,
        requestStartedAt: startedAtMs,
      })
      : await generateCoachChat(
        input.question,
        context,
        contextKind,
        undefined,
        undefined,
        contributions,
      );
    if (generation.safety) {
      // The rule that fired, never the message.
      log.warn("coach_chat_red_flag", {
        category: generation.safety.category,
        rule: generation.safety.rule,
        source: generation.safety.source,
      });
    }
    // A proposal the model asked for (A8): only after every reply guard has passed, never from a
    // referral, and the engine decides. A refusal is appended to the reply in plain words.
    const proposed = await proposeFromChat(
      (name, params) => auth.serviceClient.rpc(name, params),
      auth.userId,
      input.question,
      generation,
    );
    const finalAnswer = proposed.answer;
    if (proposed.kind !== "none") {
      log.info("coach_chat_proposal", {
        outcome: proposed.kind,
        code: proposed.kind === "refused" ? proposed.code : "none",
      });
    }
    log.info("persist_coach_chat_result", {
      snapshot_id: (prepared.feature_snapshot_id as string) ?? "null",
      policy_id: (prepared.policy_evaluation_id as string) ?? "null",
      provider: generation.provider,
      inputUnits: String(generation.inputUnits),
      outputUnits: String(generation.outputUnits),
    });
    const { data: persisted, error } = await auth.serviceClient.rpc("persist_coach_chat_result", {
      target_user_id: auth.userId,
      target_thread_id: input.thread_id,
      question: input.question,
      request_idempotency_key: input.idempotency_key,
      snapshot_id: prepared.feature_snapshot_id,
      policy_id: prepared.policy_evaluation_id,
      answer_payload: finalAnswer,
      run_latency_ms: Math.round(performance.now() - chatStart),
      run_provider: generation.provider,
      run_model: generation.model,
      run_input_units: generation.inputUnits,
      run_output_units: generation.outputUnits,
      run_estimated_cost_usd: generation.estimatedCostUsd,
    });
    if (error || !persisted) {
      log.error("persist_coach_chat_result failed", {
        errorCode: error?.code ?? "none",
        provider: generation.provider,
        hasAnswer: typeof generation.answer?.answer === "string",
        answerLen: typeof generation.answer?.answer === "string"
          ? String(generation.answer.answer).length
          : "n/a",
        safetyState: generation.answer?.safety_state ?? "n/a",
        inputUnits: String(generation.inputUnits),
        outputUnits: String(generation.outputUnits),
      });
      // The answer was paid for even though it was not stored.
      const { error: usageError } = await auth.serviceClient.rpc(
        "persist_failed_coach_chat_run_v2",
        {
          target_user_id: auth.userId,
          snapshot_id: prepared.feature_snapshot_id,
          policy_id: prepared.policy_evaluation_id,
          request_idempotency_key: input.idempotency_key,
          run_latency_ms: Math.min(Math.round(performance.now() - chatStart), 120_000),
          error_code: "persistence_rejected",
          run_provider: generation.provider,
          run_model: generation.model,
          failure_rules: [],
          run_input_units: generation.inputUnits,
          run_output_units: generation.outputUnits,
          run_estimated_cost_usd: generation.estimatedCostUsd,
        },
      );
      if (usageError) budget.keepAll();
      return reply(
        422,
        versionedResponse({
          error: "chat_rejected",
          code: "persistence_rejected",
        }),
      );
    }

    if (proposed.kind === "proposed") {
      // The reply is stored; point it at its proposal so the thread shows the card, live and on
      // reload. A failure leaves a stored proposal with no card; it expires unanswered.
      const { error: linkError } = await auth.serviceClient.rpc("link_coach_proposal_v1", {
        p_user_id: auth.userId,
        p_message_id: persisted.assistant_message_id,
        p_proposal_id: proposed.proposalId,
      });
      if (linkError) {
        log.warn("coach_chat_proposal_link_failed", { code: linkError.code ?? "none" });
      }
    }

    const traced = await recordTurnTrace(
      auth.serviceClient,
      auth.userId,
      persisted.assistant_message_id,
      {
        guardFaults: guardFaultsOf(generation.attempts),
        lookups: lookupTrace(generation.lookups),
        libraryVersion: typeof libraryTrace?.library_version === "string"
          ? libraryTrace.library_version
          : null,
      },
    );
    if (!traced) log.warn("coach_chat_trace_not_stored");

    // After the reply is stored: what the athlete may be asked to confirm, and the notes. Nothing
    // here can fail a stored reply: the suggestions are optional, and the notes are written in the
    // background after the reply has gone out.
    let suggestions: TurnSuggestions = noSuggestions;
    try {
      suggestions = suggestionsForTurn({
        remembered,
        referral: generation.safety !== undefined || finalAnswer.safety_state === "refused",
        question: input.question,
        today: coachingDate,
        memory: await memoryRead,
        modelSuggestions: generation.factSuggestions,
      });
      if (suggestions.dropped > 0) {
        log.info("coach_chat_fact_suggestions_dropped", { count: suggestions.dropped });
      }
      const turn = turnForNote({
        question: input.question,
        localDate: coachingDate,
        threadId: input.thread_id,
        remembered,
        generation,
        answer: finalAnswer,
        proposalIntent: generation.proposalIntent,
        proposed: proposed.kind === "proposed",
        userMessageId: persisted.user_message_id,
        assistantMessageId: persisted.assistant_message_id,
      });
      void runInBackground(
        () => recordMemoryAfterTurn(memoryRpc, { userId: auth.userId, turn }),
        (outcome) =>
          log.info("coach_chat_memory", outcome.ok ? { ...outcome.value } : { failed: true }),
      );
    } catch {
      log.warn("coach_chat_memory_skipped", {});
    }

    const responsePayload: Record<string, unknown> = {
      schema_version: supportsDataSummary(input)
        ? coachChatDataSummaryResponseSchemaVersion
        : coachChatResponseSchemaVersion,
      message: {
        id: persisted.assistant_message_id,
        role: "assistant",
        created_at: persisted.created_at ?? new Date().toISOString(),
        model_provider: generation.provider,
        model: generation.model,
        ...(supportsDataSummary(input) ? { answer_source: "model" } : {}),
        ...finalAnswer,
        ...(proposed.kind === "proposed" ? { proposal_id: proposed.proposalId } : {}),
      },
      budget_warning: prepared.budget_warning,
      replayed: false,
    };
    if (suggestions.wire.length) responsePayload.fact_suggestions = suggestions.wire;
    const turnMs = Math.round(performance.now() - started);
    reportSlowTurn(turnMs, {
      userId: auth.userId,
      functionName: "coach-chat",
      correlationId,
      runtime: "edge",
      provider: generation.provider,
      model: generation.model,
      contextKind,
      coachingDate,
      attempts: sentryAttemptsOf(generation.attempts),
    });
    log.info("coach_chat_complete", {
      latency_ms: turnMs,
      provider: generation.provider,
      model: generation.model,
      context_kind: contextKind,
      ai_path: generation.safety ? "safety" : coachRoute ? "gateway" : "legacy",
      route_feature: coachRoute?.feature ?? "none",
      lookups: lookupTrace(generation.lookups),
      replayed: false,
      attempts: generation.attempts.map(attemptLogFields),
    });
    return reply(200, responsePayload);
  } catch (error) {
    const unavailable = error instanceof CoachChatUnavailableError
      ? error
      : new CoachChatUnavailableError(
        "mock",
        "unknown",
        "provider_response_invalid",
        null,
        {},
        { cause: error },
      );
    const servesDataSummary = supportsDataSummary(input);
    captureException(unavailable, {
      userId: auth.userId,
      functionName: "coach-chat",
      correlationId,
      runtime: "edge",
      provider: unavailable.provider,
      model: unavailable.model,
      contextKind,
      failureCode: unavailable.failureReason,
      attempt: unavailable.metadata.attempt,
      finishReason: unavailable.metadata.finishReason,
      initialValidationRule: unavailable.metadata.initialRule,
      repairValidationRule: unavailable.metadata.repairRule,
      answerSource: servesDataSummary ? "data_summary" : "none",
      coachingDate,
      attempts: sentryAttemptsOf(unavailable.metadata.attempts ?? []),
    });
    log.error("coach_chat_failure", {
      failure_code: unavailable.failureReason,
      provider: unavailable.provider,
      model: unavailable.model,
      context_kind: contextKind,
      ai_path: coachRoute ? "gateway" : "legacy",
      attempt: unavailable.metadata.attempt ?? "unknown",
      finish_reason: unavailable.metadata.finishReason ?? "unknown",
      initial_rule: unavailable.metadata.initialRule ?? "none",
      repair_rule: unavailable.metadata.repairRule ?? "none",
      repair_skipped: unavailable.metadata.repairSkipped ?? "none",
      route_feature: coachRoute?.feature ?? "none",
      attempts: (unavailable.metadata.attempts ?? []).map(attemptLogFields),
      latency_ms: Math.round(performance.now() - started),
    });
    // supabase-js reports RPC failures in `error` rather than throwing, so the
    // result is checked; an unrecorded failure is itself reported.
    const failureUsage = coachChatFailureUsage(unavailable);
    const { error: failedRunError } = await auth.serviceClient.rpc(
      "persist_failed_coach_chat_run_v2",
      {
        target_user_id: auth.userId,
        snapshot_id: prepared.feature_snapshot_id,
        policy_id: prepared.policy_evaluation_id,
        request_idempotency_key: input.idempotency_key,
        run_latency_ms: Math.min(Math.round(performance.now() - chatStart), 120_000),
        error_code: unavailable.failureReason,
        run_provider: unavailable.provider,
        run_model: unavailable.model,
        failure_rules: coachChatFailureRules(unavailable),
        run_input_units: failureUsage.inputUnits,
        run_output_units: failureUsage.outputUnits,
        run_estimated_cost_usd: failureUsage.estimatedCostUsd,
      },
    );
    // Today's path: a timeout, or a failure that is not the provider's own answer, may have
    // been billed with no usage reported, so the reservation stays open and keeps counting at
    // its ceiling. The gateway path keeps only the attempt the provider reported in flight
    // (a sent request that timed out with no usage); a deadline that passed before a request,
    // a refused repair place and a failure whose cost is recorded are all settled. A failure
    // that could not be recorded keeps every place.
    keepAfterFailure(budget, error, coachRoute !== null);
    if (failedRunError) {
      budget.keepAll();
      log.error("persist_failed_coach_chat_run failed", {
        error_code: failedRunError.code ?? "unknown",
      });
      captureException(new Error("coach_chat_failure_not_recorded"), {
        userId: auth.userId,
        functionName: "coach-chat",
        correlationId,
        runtime: "edge",
        failureCode: failedRunError.code ?? "unknown",
      });
    }

    if (!servesDataSummary) return reply(503, coachChatFailureResponse(unavailable));

    const summary = buildCoachChatDataSummary(context, input.question);
    const { data: stored, error: storeError } = await auth.serviceClient.rpc(
      "persist_coach_chat_data_summary",
      {
        target_user_id: auth.userId,
        target_thread_id: input.thread_id,
        request_idempotency_key: input.idempotency_key,
        summary_payload: summary,
      },
    );
    if (storeError) {
      log.error("persist_coach_chat_data_summary failed", {
        error_code: storeError.code ?? "unknown",
      });
      captureException(new Error("coach_chat_data_summary_not_stored"), {
        userId: auth.userId,
        functionName: "coach-chat",
        correlationId,
        runtime: "edge",
        failureCode: storeError.code ?? "unknown",
      });
    }
    const traced = await recordTurnTrace(
      auth.serviceClient,
      auth.userId,
      storeError ? undefined : stored?.assistant_message_id,
      {
        guardFaults: guardFaultsOf(unavailable.metadata.attempts ?? [], unavailable.failureReason),
        lookups: lookupTrace(unavailable.metadata.lookups),
      },
    );
    log.info("coach_chat_data_summary_served", {
      failure_code: unavailable.failureReason,
      stored: !storeError,
      trace_stored: traced,
    });
    return reply(
      200,
      coachChatDataSummaryResponse(
        summary,
        unavailable,
        storeError ? null : stored,
        prepared.budget_warning,
      ),
    );
  }
}
