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
  CoachChatUnavailableError,
  generateCoachChat,
} from "../_shared/providers/coach_chat_provider.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { captureException } from "../_shared/sentry.ts";

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

export function detectPreferenceStatement(question: string): string | null {
  const q = question.toLowerCase();
  const patterns: [RegExp, string][] = [
    [
      /i (?:don't|do not|hate|dislike|can't|cannot stand|never) (?:eat|drink|have|like) (.{2,80}?)($|[.,!?;])/i,
      "food",
    ],
    [
      /i (?:prefer|love|really like) (.{2,80}?) (?:over|instead of|to) (.{2,40}?)($|[.,!?;])/i,
      "food",
    ],
    [/i (?:prefer|love|really like) (.{2,80}?) (?:as|for) (?:a|my) (.{2,40}?)($|[.,!?;])/i, "food"],
    [/i (?:only|always) (?:eat|cook|make) (.{2,80}?)(?:$|[.,!?;])/i, "food"],
    [/i (?:hate|dislike|don't like) (?:doing|training) (.{2,80}?)(?:$|[.,!?;])/i, "training"],
    [/i (?:prefer|love) (?:training|doing) (.{2,80}?)(?:$|[.,!?;])/i, "training"],
  ];
  for (const [pattern, category] of patterns) {
    const match = q.match(pattern);
    if (match) {
      const value = category === "food"
        ? match[1]?.trim() ?? match[3]?.trim() ?? match[4]?.trim()
        : match[1]?.trim();
      if (value && value.length >= 2 && value.length <= 120) {
        return JSON.stringify({ category, key: value, value, provenance: "chat_statement" });
      }
    }
  }
  return null;
}

export function buildSessionSummary(
  context: Record<string, unknown>,
  _coachingDate: string,
  question?: string,
  answerText?: string,
): string {
  const activePlan = context.active_plan as Record<string, unknown> | undefined;
  const activeGoal = context.active_goal as Record<string, unknown> | undefined;
  const weightSeries = Array.isArray(context.weight_series_8w) ? context.weight_series_8w : [];
  const weight = (weightSeries[0] as Record<string, unknown> | undefined)?.weight_kg ??
    (context.latest_measurement as Record<string, unknown> | undefined)?.weight_kg ??
    (context.latest_weight as Record<string, unknown> | undefined)?.weight_kg;
  const trainingLog = Array.isArray(context.training_log_28d) ? context.training_log_28d : null;
  const sessions = trainingLog ??
    (Array.isArray(context.recent_execution) ? context.recent_execution : []);
  const completed = trainingLog
    ? trainingLog.length
    : sessions.filter((s: Record<string, unknown>) => (s.completion_rate as number) > 0).length;
  const healthDays = Array.isArray(context.health_daily_28d)
    ? context.health_daily_28d
    : Array.isArray(context.brief_health)
    ? context.brief_health
    : [];
  const lastHealth = healthDays[0] as Record<string, unknown> | undefined;
  const sleep = lastHealth?.sleep_minutes;
  const rhr = lastHealth?.resting_heart_rate_bpm;
  const goalLabel = (activeGoal?.goal_type ?? activeGoal?.type) as string ?? "training";
  const phase = activePlan?.title as string ?? "active plan";
  const meals = Array.isArray(context.confirmed_nutrition_history)
    ? context.confirmed_nutrition_history
    : [];
  const mealDays = meals.length;

  const parts: string[] = [];
  parts.push(`${goalLabel} phase: ${phase}.`);
  if (weight != null) parts.push(`Weight ${weight}kg.`);
  if (trainingLog && completed > 0) parts.push(`${completed} workouts in 28 days.`);
  else if (completed > 0) parts.push(`${completed}/${sessions.length} workouts done.`);
  if (sleep != null) parts.push(`Sleep ${sleep}min.`);
  if (rhr != null) parts.push(`RHR ${rhr}.`);
  if (mealDays > 0) parts.push(`Nutrition ${mealDays} days.`);

  if (question) {
    const topic = question.length > 100 ? question.slice(0, 97) + "..." : question;
    parts.push(`Asked about: "${topic}".`);
  }
  if (answerText) {
    const excerpt = answerText.length > 150 ? answerText.slice(0, 147) + "..." : answerText;
    parts.push(`Coach: ${excerpt}`);
  }

  return parts.join(" ").slice(0, 400);
}

Deno.serve(async (request) => {
  const correlationId = extractCorrelationId(request);
  const log = createLogger(correlationId);
  const started = performance.now();
  if (request.method !== "POST") {
    return reply(405, versionedResponse({ error: "method_not_allowed" }));
  }
  let auth;
  try {
    auth = await requireAuth(request);
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
  const { error: budgetError } = await auth.serviceClient.rpc("assert_owner_ai_budget", {
    target_user_id: auth.userId,
  });
  if (budgetError) {
    return reply(429, versionedResponse({ error: "ai_usage_limit" }));
  }
  const contextKind = classifyQuestion(input.question);
  const { data: prepared, error: prepareError } = await auth.serviceClient.rpc(
    "prepare_coach_chat_v8",
    {
      target_user_id: auth.userId,
      target_thread_id: input.thread_id,
      question: input.question,
      coaching_timezone: input.timezone,
      request_idempotency_key: input.idempotency_key,
      context_kind: contextKind,
    },
  );
  if (prepareError || !prepared) {
    log.error("prepare_coach_chat_v8 failed", {
      error_code: prepareError?.code ?? "missing_prepared_context",
    });
    return reply(
      422,
      versionedResponse({
        error: "chat_unavailable",
        code: "context_preparation_failed",
      }),
    );
  }
  if (prepared.replayed) {
    const { data } = await auth.userClient.from("coach_messages").select().eq(
      "thread_id",
      input.thread_id,
    ).order("created_at");
    return reply(
      200,
      versionedResponse({
        messages: data ?? [],
        replayed: true,
      }),
    );
  }

  const context = prepared.context as Record<string, unknown>;
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
  }

  const { data: ftsMessages, error: ftsError } = await auth.serviceClient.rpc(
    "search_coach_messages",
    {
      target_user_id: auth.userId,
      query_text: input.question,
      max_results: 8,
    },
  );
  if (!ftsError && ftsMessages) {
    // Trim full message content — the model only needs a relevance signal,
    // not the entire conversation history.
    context.fts_messages = (Array.isArray(ftsMessages) ? ftsMessages : [ftsMessages]).map(
      (msg: Record<string, unknown>) => ({
        ...msg,
        content: typeof msg.content === "string" ? msg.content.slice(0, 150) : msg.content,
      }),
    );
  }

  const preferenceSignal = detectPreferenceStatement(input.question);

  const chatStart = performance.now();
  try {
    const generation = await generateCoachChat(
      input.question,
      context,
      contextKind,
    );
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
      answer_payload: generation.answer,
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
      return reply(
        422,
        versionedResponse({
          error: "chat_rejected",
          code: "persistence_rejected",
        }),
      );
    }

    const summaryText = buildSessionSummary(
      context,
      coachingDate,
      input.question,
      generation.answer?.answer as string | undefined,
    );
    const sessionSnapshotIds: string[] = [];
    if (prepared.coach_context_snapshot_id) {
      sessionSnapshotIds.push(prepared.coach_context_snapshot_id as string);
    }
    await auth.serviceClient.rpc("persist_coach_session_summary", {
      target_user_id: auth.userId,
      coaching_date: coachingDate,
      summary_text: summaryText,
      thread_id_param: input.thread_id,
      key_snapshot_ids: sessionSnapshotIds,
    });

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
        ...generation.answer,
      },
      budget_warning: prepared.budget_warning,
      replayed: false,
    };
    if (preferenceSignal) {
      responsePayload.preference_prompt = JSON.parse(preferenceSignal);
    }
    log.info("coach_chat_complete", {
      latency_ms: Math.round(performance.now() - started),
      provider: generation.provider,
      model: generation.model,
      context_kind: contextKind,
      replayed: false,
      attempts: generation.attempts.map((attempt) => ({
        attempt: attempt.attempt,
        outcome: attempt.outcome,
        rule: attempt.rule ?? "none",
        path: attempt.path ?? "none",
        limit: attempt.limit ?? null,
        actual: attempt.actual ?? null,
        latency_ms: attempt.latencyMs,
        finish_reason: attempt.finishReason ?? "unknown",
        completion_tokens: attempt.completionTokens,
      })),
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
    });
    log.error("coach_chat_failure", {
      failure_code: unavailable.failureReason,
      provider: unavailable.provider,
      model: unavailable.model,
      context_kind: contextKind,
      attempt: unavailable.metadata.attempt ?? "unknown",
      finish_reason: unavailable.metadata.finishReason ?? "unknown",
      initial_rule: unavailable.metadata.initialRule ?? "none",
      repair_rule: unavailable.metadata.repairRule ?? "none",
      attempts: (unavailable.metadata.attempts ?? []).map((attempt) => ({
        attempt: attempt.attempt,
        outcome: attempt.outcome,
        rule: attempt.rule ?? "none",
        path: attempt.path ?? "none",
        limit: attempt.limit ?? null,
        actual: attempt.actual ?? null,
        latency_ms: attempt.latencyMs,
        finish_reason: attempt.finishReason ?? "unknown",
        completion_tokens: attempt.completionTokens,
      })),
      latency_ms: Math.round(performance.now() - started),
    });
    // supabase-js reports RPC failures in `error` rather than throwing, so the
    // result is checked; an unrecorded failure is itself reported.
    const { error: failedRunError } = await auth.serviceClient.rpc(
      "persist_failed_coach_chat_run",
      {
        target_user_id: auth.userId,
        snapshot_id: prepared.feature_snapshot_id,
        policy_id: prepared.policy_evaluation_id,
        request_idempotency_key: input.idempotency_key,
        run_latency_ms: Math.round(performance.now() - chatStart),
        error_code: unavailable.failureReason,
        run_provider: unavailable.provider,
        run_model: unavailable.model,
        failure_rules: coachChatFailureRules(unavailable),
      },
    );
    if (failedRunError) {
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

    const summary = buildCoachChatDataSummary(context);
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
    }
    log.info("coach_chat_data_summary_served", {
      failure_code: unavailable.failureReason,
      stored: !storeError,
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
});
