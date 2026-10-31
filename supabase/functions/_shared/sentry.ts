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
  /** A database or provider error code, such as 42501 or a provider's own short code. */
  errorCode?: string;
  /** The HTTP status a provider or network call answered with. */
  httpStatus?: number;
  latencyMs?: number;
  /** How many items the failure concerns (chunks given up on, keys refused). */
  count?: number;
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

/**
 * Sentry fails closed. An event carries finite codes and numbers, never free text: an exception
 * message can hold a provider's response body, the model's reply, a JSON parse error quoting it, or
 * the athlete's own words, and none of that may leave the Edge Function. So the exception value is
 * the call site's failure code (or the error's class name when it gave none), every tag and extra
 * field is a short code, and the stack keeps function, file and line only.
 */
const codePattern = /^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,79}$/;
const namePattern = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;
const maxFrames = 30;

/** The value when it is a short code (letters, digits, `_ . : / -`, no spaces), else the fallback. */
function safeCode(value: unknown, fallback: string): string {
  return typeof value === "string" && codePattern.test(value) ? value : fallback;
}

function optionalCode(value: string | undefined): string | undefined {
  return value === undefined ? undefined : safeCode(value, "invalid");
}

function safeNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

/** Runs a reader of an arbitrary error (a getter can throw); a failure reads as nothing. */
function attempt<T>(read: () => T, fallback: T): T {
  try {
    return read();
  } catch {
    return fallback;
  }
}

/** The error's class name, or a fixed name for anything that is not an Error. */
function errorClass(error: unknown): string {
  return attempt(
    () => error instanceof Error && namePattern.test(error.name) ? error.name : "NonError",
    "NonError",
  );
}

/** The HTTP status an error carries as a number, if any. */
function errorStatus(error: unknown): number | undefined {
  return attempt(() => {
    if (typeof error !== "object" || error === null) return undefined;
    const status = (error as { status?: unknown }).status ??
      (error as { httpStatus?: unknown }).httpStatus;
    return typeof status === "number" && Number.isInteger(status) && status >= 100 &&
        status <= 599
      ? status
      : undefined;
  }, undefined);
}

/**
 * What a provider call that failed can say: its short error code and HTTP status, read from the
 * error's `code` or, when that is not a code, its message, but only when the text is a code (no
 * spaces) such as `meal_vision_request_failed:503:overloaded`. A message with words in it, a
 * response body or model text says nothing here.
 */
export function providerFailure(
  error: unknown,
): { errorCode?: string; httpStatus?: number } {
  return attempt(() => {
    if (typeof error !== "object" || error === null) return {};
    const candidates = [
      (error as { code?: unknown }).code,
      (error as { message?: unknown }).message,
    ];
    const errorCode = candidates.find((value): value is string =>
      typeof value === "string" && codePattern.test(value)
    );
    if (errorCode === undefined) return {};
    const status = /^[A-Za-z0-9_]+:([1-5]\d\d)(?::|$)/.exec(errorCode)?.[1];
    return status === undefined ? { errorCode } : { errorCode, httpStatus: Number(status) };
  }, {});
}

const framePattern = /^\s*at\s+(?:(.+?)\s+\()?(.+?):(\d+):(\d+)\)?\s*$/;
/** A function name from V8: no spaces except a leading `async ` or `new `. */
const functionPattern = /^(?:(?:async|new) )?[A-Za-z0-9_$.<>[\]]{1,100}$/;
/**
 * Frames come from code the runtime loaded, so the file is a URL (a local path may hold spaces);
 * any other frame is dropped.
 */
const filenamePattern = /^(?:file|ext|https?|node|jsr|npm):.{1,300}$/;

interface SentryFrame {
  function?: string;
  filename: string;
  lineno: number;
}

/**
 * The text of `error.stack` after the header (`Name: message`, which may span several lines and
 * may itself look like frames), or null when the header cannot be located.
 */
function stackAfterHeader(error: Error): string | null {
  const stack = error.stack;
  if (typeof stack !== "string") return null;
  const message = error.message;
  if (message === "") {
    const newline = stack.indexOf("\n");
    return newline === -1 ? "" : stack.slice(newline + 1);
  }
  const at = stack.indexOf(message);
  return at === -1 ? null : stack.slice(at + message.length);
}

/**
 * The frames of a stack, oldest first as Sentry expects: function name, file and line only. The
 * header (the message, however many lines it has), source text and any line that is not a frame
 * in a loaded file are dropped.
 */
function stackFrames(error: unknown): SentryFrame[] {
  return attempt(() => {
    if (!(error instanceof Error)) return [];
    const section = stackAfterHeader(error);
    if (section === null) return [];
    const frames: SentryFrame[] = [];
    for (const line of section.split("\n")) {
      const match = framePattern.exec(line);
      if (!match) continue;
      const filename = match[2].replace(/[?#].*$/, "");
      if (!filenamePattern.test(filename)) continue;
      frames.push({
        ...(match[1] !== undefined && functionPattern.test(match[1]) ? { function: match[1] } : {}),
        filename,
        lineno: Number(match[3]),
      });
      if (frames.length === maxFrames) break;
    }
    return frames.reverse();
  }, []);
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

/** Every exception report names its failure with a code: the code is all the event says. */
export function captureException(
  error: unknown,
  context: SentryContext & { failureCode: string },
): void {
  try {
    if (!Deno.env.get("SENTRY_DSN")) return;
    send(buildSentryEvent(error, context));
  } catch {
    // Silent: reporting a failure must never become one.
  }
}

/** A message event that is not an error, such as a turn that succeeded but ran slowly. */
export function captureMessage(
  message: string,
  level: "warning" | "info",
  context?: SentryContext,
): void {
  try {
    if (!Deno.env.get("SENTRY_DSN")) return;
    send(buildSentryMessageEvent(message, level, context));
  } catch {
    // Silent: reporting a failure must never become one.
  }
}

const tagValue = (value: string | number | boolean | undefined): string => {
  if (value === undefined) return "unknown";
  if (typeof value === "string") return safeCode(value, "invalid");
  return typeof value === "number" && !Number.isFinite(value) ? "invalid" : String(value);
};

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
        attempt: safeCode(item.attempt, "invalid"),
        outcome: safeCode(item.outcome, "invalid"),
        latency_ms: safeNumber(item.latencyMs),
        retry: item.retry === true,
        prompt_chars: safeNumber(item.promptChars),
        schema_bytes: safeNumber(item.schemaBytes),
        schema_sha: optionalCode(item.schemaSha),
        remembered: item.remembered === true ? true : item.remembered === false ? false : undefined,
        route_timeout_ms: safeNumber(item.routeTimeoutMs),
        max_output_tokens: safeNumber(item.maxOutputTokens),
        prompt_tokens: safeNumber(item.promptTokens),
        completion_tokens: safeNumber(item.completionTokens),
        cache_read_tokens: safeNumber(item.cacheReadTokens),
        cache_write_tokens: safeNumber(item.cacheWriteTokens),
      })),
    },
  };
}

function eventFields(context: SentryContext | undefined, error?: unknown) {
  const attempts = attemptFields(context?.attempts);
  const status = safeNumber(context?.httpStatus) ?? errorStatus(error);
  const latency = safeNumber(context?.latencyMs);
  return {
    tags: {
      function: safeCode(context?.functionName, "unknown"),
      environment: safeCode(Deno.env.get("TRACEND_ENV"), "unknown"),
      runtime: safeCode(context?.runtime, "edge"),
      provider: safeCode(context?.provider, "unknown"),
      model: safeCode(context?.model, "unknown"),
      context_kind: safeCode(context?.contextKind, "unknown"),
      failure_code: safeCode(context?.failureCode, "unknown"),
      error_code: safeCode(context?.errorCode, "none"),
      attempt: safeCode(context?.attempt, "unknown"),
      finish_reason: safeCode(context?.finishReason, "unknown"),
      initial_validation_rule: safeCode(context?.initialValidationRule, "none"),
      repair_validation_rule: safeCode(context?.repairValidationRule, "none"),
      answer_source: context?.answerSource ?? "none",
      ...attempts.tags,
      ...(status === undefined ? {} : { http_status: String(status) }),
      ...(latency === undefined ? {} : { latency_ms: String(latency) }),
    },
    user: context?.userId ? { id: String(context.userId) } : undefined,
    extra: {
      correlationId: optionalCode(context?.correlationId),
      coachingDate: optionalCode(context?.coachingDate),
      mealId: optionalCode(context?.mealId),
      count: safeNumber(context?.count),
      ...attempts.extra,
    },
  };
}

/**
 * The event for a caught error. Nothing of `error.message`, its cause, its response body or its
 * stack text is sent: the value is the failure code, the type is the error's class name.
 */
export function buildSentryEvent(
  error: unknown,
  context?: SentryContext,
): Record<string, unknown> {
  const fields = eventFields(context, error);
  const type = errorClass(error);
  const frames = stackFrames(error);
  return {
    event_id: crypto.randomUUID(),
    timestamp: Math.floor(Date.now() / 1000),
    level: "error",
    platform: "javascript",
    exception: {
      values: [
        {
          type,
          value: safeCode(context?.failureCode, type),
          ...(frames.length > 0 ? { stacktrace: { frames } } : {}),
        },
      ],
    },
    tags: fields.tags,
    user: fields.user,
    extra: fields.extra,
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
    message: safeCode(message, "invalid_message"),
    tags: fields.tags,
    user: fields.user,
    extra: fields.extra,
  };
}
