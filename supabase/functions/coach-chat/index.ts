import { parseCoachChatRequest } from "../_shared/contracts/coach_chat_v1.ts";
import { createLogger, extractCorrelationId } from "../_shared/logger.ts";
import {
  classifyQuestion,
  CoachChatUnavailableError,
  generateCoachChat,
} from "../_shared/providers/coach_chat_provider.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { captureException } from "../_shared/sentry.ts";

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
): string {
  const activePlan = context.active_plan as Record<string, unknown> | undefined;
  const activeGoal = context.active_goal as Record<string, unknown> | undefined;
  const weight = (context.latest_measurement as Record<string, unknown> | undefined)
    ?.weight_kg ?? (context.latest_weight as Record<string, unknown> | undefined)?.weight_kg;
  const sessions = Array.isArray(context.recent_execution) ? context.recent_execution : [];
  const completed = sessions.filter(
    (s: Record<string, unknown>) => (s.completion_rate as number) > 0,
  ).length;
  const healthDays = Array.isArray(context.brief_health) ? context.brief_health : [];
  const lastHealth = healthDays[0] as Record<string, unknown> | undefined;
  const sleep = lastHealth?.sleep_minutes;
  const rhr = lastHealth?.resting_heart_rate_bpm;
  const goalLabel = activeGoal?.type as string ?? "training";
  const phase = activePlan?.title as string ?? "active plan";
  const meals = Array.isArray(context.confirmed_nutrition_history)
    ? context.confirmed_nutrition_history
    : [];
  const mealDays = meals.length;
  const weightStr = weight != null ? `Weight ${weight}kg. ` : "";
  const sessionsStr = completed > 0 ? `${completed}/${sessions.length} workouts done, ` : "";
  const sleepStr = sleep != null ? `Sleep ${sleep}min` : "";
  const rhrStr = rhr != null ? `, RHR ${rhr}` : "";
  const mealStr = mealDays > 0 ? ` Nutrition ${mealDays} days.` : "";
  return `${goalLabel} phase: ${phase}. ${weightStr}${sessionsStr}${sleepStr}${rhrStr}.${mealStr}`
    .slice(0, 400);
}

Deno.serve(async (request) => {
  const correlationId = extractCorrelationId(request);
  const log = createLogger(correlationId);
  const started = performance.now();
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
    input = parseCoachChatRequest(await request.json());
  } catch {
    log.warn("invalid_chat_request");
    return reply(422, { error: "invalid_chat_request" });
  }
  const { error: budgetError } = await auth.serviceClient.rpc("assert_owner_ai_budget", {
    target_user_id: auth.userId,
  });
  if (budgetError) return reply(429, { error: "ai_usage_limit" });
  const contextKind = classifyQuestion(input.question);
  const { data: prepared, error: prepareError } = await auth.serviceClient.rpc(
    "prepare_coach_chat_v5",
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
    log.error("prepare_coach_chat_v5 failed", {
      detail: prepareError?.message ?? "unknown",
    });
    return reply(422, {
      error: "chat_unavailable",
      detail: prepareError?.message ?? "context_preparation_failed",
    });
  }
  if (prepared.replayed) {
    const { data } = await auth.userClient.from("coach_messages").select().eq(
      "thread_id",
      input.thread_id,
    ).order("created_at");
    return reply(200, { schema_version: "1.0", messages: data ?? [], replayed: true });
  }

  const context = prepared.context as Record<string, unknown>;
  const coachingDate = (context.coaching_date as string) ??
    new Date().toISOString().slice(0, 10);

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
    );
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
    if (error || !persisted) return reply(422, { error: "chat_rejected" });

    const summaryText = buildSessionSummary(context, coachingDate);
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
      schema_version: "1.0",
      message: {
        id: persisted.assistant_message_id,
        role: "assistant",
        created_at: persisted.created_at ?? new Date().toISOString(),
        model_provider: generation.provider,
        model: generation.model,
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
      replayed: false,
    });
    return reply(200, responsePayload);
  } catch (error) {
    const diagnosticMessage = error instanceof Error
      ? `${error.name}: ${error.message}`
      : `${error}`;
    const unavailable = error instanceof CoachChatUnavailableError
      ? error
      : new CoachChatUnavailableError("mock", "unknown");
    captureException(error, {
      userId: auth.userId,
      functionName: "coach-chat",
      correlationId,
      contextKind,
      coachingDate,
    });
    log.error("coach_chat_failure", {
      detail: diagnosticMessage,
      provider: unavailable.provider,
      model: unavailable.model,
      latency_ms: Math.round(performance.now() - started),
    });
    try {
      await auth.serviceClient.rpc("persist_failed_coach_chat_run", {
        target_user_id: auth.userId,
        snapshot_id: prepared.feature_snapshot_id,
        policy_id: prepared.policy_evaluation_id,
        request_idempotency_key: input.idempotency_key,
        run_latency_ms: Math.round(performance.now() - chatStart),
        error_code: "provider_or_validation_failed",
        run_provider: unavailable.provider,
        run_model: unavailable.model,
      });
    } catch (persistError) {
      log.error("persist_failed_coach_chat_run failed", {
        detail: persistError instanceof Error ? persistError.message : String(persistError),
      });
    }
    return reply(503, {
      error: "chat_unavailable",
      detail: diagnosticMessage,
      provider: unavailable.provider,
      model: unavailable.model,
      retry_after_seconds: unavailable.retryAfterSeconds,
    });
  }
});
