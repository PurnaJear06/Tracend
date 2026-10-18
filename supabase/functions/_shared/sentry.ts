/**
 * One model attempt of a Coach chat turn, for finding a slow or failing call. Numbers, names and a
 * schema hash only: nothing here can hold the athlete's text, a prompt or a reply.
 */
export interface SentryAttempt {
  attempt: string;
  outcome: string;
  latencyMs: number;
  retry?: boolean;
  promptChars?: number;
  schemaBytes?: number;
  schemaSha?: string;
  remembered?: boolean;
  routeTimeoutMs?: number;
  maxOutputTokens?: number;
  promptTokens?: number;
  completionTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
}

export interface SentryContext {
  userId?: string;
  functionName?: string;
  correlationId?: string;
  runtime?: string;
  provider?: string;
  model?: string;
  contextKind?: string;
  failureCode?: string;
  attempt?: string;
  finishReason?: string | null;
  initialValidationRule?: string;
  repairValidationRule?: string;
  answerSource?: "data_summary" | "none";
  coachingDate?: string;
  mealId?: string;
  /** Coach chat: the model attempts of the turn, in order. */
  attempts?: readonly SentryAttempt[];
}

interface ParsedDsn {
  publicKey: string;
  url: string;
  projectId: string;
}

function parseDsn(dsn: string): ParsedDsn | null {
  const match = dsn.match(/^https?:\/\/([^@]+)@([^/]+)\/(\d+)$/);
  if (!match) return null;
  return {
    publicKey: match[1],
    url: `https://${match[2]}`,
    projectId: match[3],
  };
}

function send(event: Record<string, unknown>): void {
  const dsn = Deno.env.get("SENTRY_DSN") ?? "";
  if (!dsn) return;

  const parsed = parseDsn(dsn);
  if (!parsed) return;

  fetch(`${parsed.url}/api/${parsed.projectId}/store/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Sentry-Auth":
        `Sentry sentry_version=7, sentry_client=tracend-edge/1.0.0, sentry_timestamp=${
          Math.floor(Date.now() / 1000)
        }, sentry_key=${parsed.publicKey}`,
    },
    body: JSON.stringify(event),
  }).catch(() => {
    // Silent — Sentry failures must never affect the caller.
  });
}

export function captureException(
  error: unknown,
  context?: SentryContext,
): void {
  if (!Deno.env.get("SENTRY_DSN")) return;
  send(buildSentryEvent(error, context));
}

/** A message event that is not an error, such as a turn that succeeded but ran slowly. */
export function captureMessage(
  message: string,
  level: "warning" | "info",
  context?: SentryContext,
): void {
  if (!Deno.env.get("SENTRY_DSN")) return;
  send(buildSentryMessageEvent(message, level, context));
}

const tagValue = (value: string | number | boolean | undefined): string =>
  value === undefined ? "unknown" : String(value);

/**
 * Tags that make the turn searchable and the attempt list for the detail. The tags describe the
 * last attempt, which is the one that ended the turn.
 */
function attemptFields(
  attempts: readonly SentryAttempt[] | undefined,
): { tags: Record<string, string>; extra: Record<string, unknown> } {
  const last = attempts?.at(-1);
  if (!attempts || !last) return { tags: {}, extra: {} };
  return {
    tags: {
      latency_ms: tagValue(last.latencyMs),
      prompt_chars: tagValue(last.promptChars),
      schema_bytes: tagValue(last.schemaBytes),
      schema_sha: tagValue(last.schemaSha),
      remembered: tagValue(last.remembered),
      route_timeout_ms: tagValue(last.routeTimeoutMs),
      max_output_tokens: tagValue(last.maxOutputTokens),
      cache_read_tokens: tagValue(last.cacheReadTokens),
      cache_write_tokens: tagValue(last.cacheWriteTokens),
      attempt_count: String(attempts.length),
    },
    extra: {
      attempts: attempts.map((item) => ({
        attempt: item.attempt,
        outcome: item.outcome,
        latency_ms: item.latencyMs,
        retry: item.retry === true,
        prompt_chars: item.promptChars,
        schema_bytes: item.schemaBytes,
        schema_sha: item.schemaSha,
        remembered: item.remembered,
        route_timeout_ms: item.routeTimeoutMs,
        max_output_tokens: item.maxOutputTokens,
        prompt_tokens: item.promptTokens,
        completion_tokens: item.completionTokens,
        cache_read_tokens: item.cacheReadTokens,
        cache_write_tokens: item.cacheWriteTokens,
      })),
    },
  };
}

function eventFields(context: SentryContext | undefined) {
  const attempts = attemptFields(context?.attempts);
  return {
    tags: {
      function: context?.functionName ?? "unknown",
      environment: Deno.env.get("TRACEND_ENV") ?? "unknown",
      runtime: context?.runtime ?? "edge",
      provider: context?.provider ?? "unknown",
      model: context?.model ?? "unknown",
      context_kind: context?.contextKind ?? "unknown",
      failure_code: context?.failureCode ?? "unknown",
      attempt: context?.attempt ?? "unknown",
      finish_reason: context?.finishReason ?? "unknown",
      initial_validation_rule: context?.initialValidationRule ?? "none",
      repair_validation_rule: context?.repairValidationRule ?? "none",
      answer_source: context?.answerSource ?? "none",
      ...attempts.tags,
    },
    user: context?.userId ? { id: String(context.userId) } : undefined,
    extra: {
      correlationId: context?.correlationId,
      coachingDate: context?.coachingDate,
      mealId: context?.mealId,
      ...attempts.extra,
    },
  };
}

export function buildSentryEvent(
  error: unknown,
  context?: SentryContext,
): Record<string, unknown> {
  const stack = error instanceof Error && typeof error.stack === "string"
    ? error.stack.slice(0, 4_000)
    : undefined;
  const fields = eventFields(context);

  return {
    event_id: crypto.randomUUID(),
    timestamp: Math.floor(Date.now() / 1000),
    level: "error",
    platform: "javascript",
    exception: {
      values: [
        {
          type: error instanceof Error ? error.name : typeof error,
          value: error instanceof Error ? error.message : String(error),
        },
      ],
    },
    tags: fields.tags,
    user: fields.user,
    extra: { ...fields.extra, stack },
  };
}

export function buildSentryMessageEvent(
  message: string,
  level: "warning" | "info",
  context?: SentryContext,
): Record<string, unknown> {
  const fields = eventFields(context);
  return {
    event_id: crypto.randomUUID(),
    timestamp: Math.floor(Date.now() / 1000),
    level,
    platform: "javascript",
    message,
    tags: fields.tags,
    user: fields.user,
    extra: fields.extra,
  };
}
