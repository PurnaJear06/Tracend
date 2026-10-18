// What one Coach turn reports about its model attempts, in the log and in Sentry: how long each
// took, how big the request and its schema were, and which cache tokens were read or written. All
// of it is a number, a name or a schema hash; none of it can carry the athlete's text, a prompt or
// a reply. A slow call is found by these fields (the incident of 2026-10-18 was a schema Claude
// compiled on every turn: 0 tokens, 31.7 s, and no way to see it).
import type { CoachChatAttemptTelemetry } from "../_shared/providers/coach_chat_provider.ts";
import { captureMessage, type SentryAttempt, type SentryContext } from "../_shared/sentry.ts";

/** A turn that answers but takes longer than this is reported to Sentry as a warning. */
export const slowTurnMs = 15_000;

/** The log line's view of an attempt. */
export function attemptLogFields(attempt: CoachChatAttemptTelemetry): Record<string, unknown> {
  return {
    attempt: attempt.attempt,
    outcome: attempt.outcome,
    retry: attempt.retry === true,
    rule: attempt.rule ?? "none",
    also_rules: attempt.alsoRules ?? [],
    path: attempt.path ?? "none",
    limit: attempt.limit ?? null,
    actual: attempt.actual ?? null,
    latency_ms: attempt.latencyMs,
    finish_reason: attempt.finishReason ?? "unknown",
    completion_tokens: attempt.completionTokens,
    prompt_chars: attempt.promptChars ?? null,
    schema_bytes: attempt.schemaBytes ?? null,
    schema_sha: attempt.schemaSha ?? null,
    remembered: attempt.remembered ?? null,
    route_timeout_ms: attempt.routeTimeoutMs ?? null,
    max_output_tokens: attempt.maxOutputTokens ?? null,
    cache_read_tokens: attempt.cacheReadTokens ?? null,
    cache_write_tokens: attempt.cacheWriteTokens ?? null,
  };
}

/** The Sentry view of the turn's attempts (an allowlist: nothing else is copied). */
export function sentryAttemptsOf(
  attempts: readonly CoachChatAttemptTelemetry[],
): SentryAttempt[] {
  return attempts.map((attempt) => ({
    attempt: attempt.attempt,
    outcome: attempt.outcome,
    latencyMs: attempt.latencyMs,
    ...(attempt.retry ? { retry: true } : {}),
    promptChars: attempt.promptChars,
    schemaBytes: attempt.schemaBytes,
    schemaSha: attempt.schemaSha,
    remembered: attempt.remembered,
    routeTimeoutMs: attempt.routeTimeoutMs,
    maxOutputTokens: attempt.maxOutputTokens,
    promptTokens: attempt.promptTokens,
    completionTokens: attempt.completionTokens,
    cacheReadTokens: attempt.cacheReadTokens,
    cacheWriteTokens: attempt.cacheWriteTokens,
  }));
}

/**
 * Reports a turn that answered but took longer than `slowTurnMs` to Sentry as a warning, with its
 * attempts. A turn within the limit reports nothing. Returns whether it reported.
 */
export function reportSlowTurn(
  turnMs: number,
  context: SentryContext,
  capture: typeof captureMessage = captureMessage,
): boolean {
  if (turnMs <= slowTurnMs) return false;
  capture("coach_chat_slow_turn", "warning", context);
  return true;
}
