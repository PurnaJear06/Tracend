import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import type { CoachChatAttemptTelemetry } from "../_shared/providers/coach_chat_provider.ts";
import {
  buildSentryEvent,
  buildSentryMessageEvent,
  type SentryContext,
} from "../_shared/sentry.ts";
import {
  attemptLogFields,
  reportSlowTurn,
  sentryAttemptsOf,
  slowTurnMs,
} from "./attempt_telemetry.ts";

const attempts: CoachChatAttemptTelemetry[] = [
  {
    attempt: "initial",
    outcome: "timeout",
    latencyMs: 29_500,
    completionTokens: 0,
    finishReason: "timeout",
    promptChars: 61_000,
    schemaBytes: 2_818,
    schemaSha: "274ee4fafead",
    remembered: true,
    routeTimeoutMs: 30_000,
    maxOutputTokens: 4_096,
  },
  {
    attempt: "initial",
    outcome: "valid",
    retry: true,
    latencyMs: 4_200,
    completionTokens: 410,
    promptTokens: 18_000,
    cacheReadTokens: 15_000,
    cacheWriteTokens: 3_000,
    finishReason: "end",
    promptChars: 61_000,
    schemaBytes: 2_818,
    schemaSha: "274ee4fafead",
    remembered: true,
    routeTimeoutMs: 30_000,
    maxOutputTokens: 4_096,
  },
];

Deno.test("the log line carries the numbers that find a slow call", () => {
  const [first, second] = attempts.map(attemptLogFields);
  assertEquals(first.latency_ms, 29_500);
  assertEquals(first.schema_sha, "274ee4fafead");
  assertEquals(first.schema_bytes, 2_818);
  assertEquals(first.prompt_chars, 61_000);
  assertEquals(first.remembered, true);
  assertEquals(first.route_timeout_ms, 30_000);
  assertEquals(first.max_output_tokens, 4_096);
  assertEquals(first.cache_read_tokens, null);
  assertEquals(first.retry, false);
  assertEquals(second.cache_read_tokens, 15_000);
  assertEquals(second.cache_write_tokens, 3_000);
  assertEquals(second.retry, true);
});

Deno.test("a legacy attempt, which has none of those fields, still logs", () => {
  const fields = attemptLogFields({
    attempt: "initial",
    outcome: "valid",
    latencyMs: 900,
    completionTokens: 80,
  });
  assertEquals(fields.schema_sha, null);
  assertEquals(fields.latency_ms, 900);
});

Deno.test("a failure event is tagged with the last attempt and lists every attempt, with no content", () => {
  const context: SentryContext = {
    functionName: "coach-chat",
    failureCode: "provider_timeout",
    attempts: sentryAttemptsOf(attempts),
    ...({ question: "private question", prompt: "private prompt" } as Record<string, unknown>),
  };
  const event = buildSentryEvent(new Error("coach_chat_unavailable: provider_timeout"), context);
  const tags = event.tags as Record<string, string>;
  assertEquals(tags.latency_ms, "4200");
  assertEquals(tags.prompt_chars, "61000");
  assertEquals(tags.schema_bytes, "2818");
  assertEquals(tags.schema_sha, "274ee4fafead");
  assertEquals(tags.remembered, "true");
  assertEquals(tags.route_timeout_ms, "30000");
  assertEquals(tags.max_output_tokens, "4096");
  assertEquals(tags.cache_read_tokens, "15000");
  assertEquals(tags.cache_write_tokens, "3000");
  assertEquals(tags.attempt_count, "2");
  const listed = (event.extra as { attempts: Record<string, unknown>[] }).attempts;
  assertEquals(listed.length, 2);
  assertEquals(listed[0].outcome, "timeout");
  assertEquals(listed[1].retry, true);
  const text = JSON.stringify(event);
  assert(!text.includes("private question") && !text.includes("private prompt"));
});

Deno.test("an event without attempts has no attempt tags", () => {
  const event = buildSentryEvent(new Error("x"), { functionName: "coach-chat" });
  assertEquals("latency_ms" in (event.tags as object), false);
  assertEquals("attempts" in (event.extra as object), false);
});

Deno.test("only the allowlisted fields of an attempt reach Sentry", () => {
  const sneaky = {
    ...attempts[1],
    text: "the reply",
    prompt: "the prompt",
  } as CoachChatAttemptTelemetry;
  const [sent] = sentryAttemptsOf([sneaky]);
  assertEquals("text" in sent || "prompt" in sent, false);
  const event = buildSentryMessageEvent("coach_chat_slow_turn", "warning", { attempts: [sent] });
  assert(!JSON.stringify(event).includes("the reply"));
  assert(!JSON.stringify(event).includes("the prompt"));
});

Deno.test("a message event is a warning, not an exception", () => {
  const event = buildSentryMessageEvent("coach_chat_slow_turn", "warning", {
    functionName: "coach-chat",
    attempts: sentryAttemptsOf(attempts),
  });
  assertEquals(event.level, "warning");
  assertEquals(event.message, "coach_chat_slow_turn");
  assertEquals("exception" in event, false);
  assertEquals((event.tags as Record<string, string>).schema_sha, "274ee4fafead");
});

Deno.test("a turn slower than 15 s is reported once; one at the limit or faster is not", () => {
  assertEquals(slowTurnMs, 15_000);
  const reported: [string, string][] = [];
  const capture = ((message: string, level: string) => {
    reported.push([message, level]);
  }) as Parameters<typeof reportSlowTurn>[2];
  const context = { functionName: "coach-chat", attempts: sentryAttemptsOf(attempts) };
  assertEquals(reportSlowTurn(14_999, context, capture), false);
  assertEquals(reportSlowTurn(15_000, context, capture), false);
  assertEquals(reported, []);
  assertEquals(reportSlowTurn(15_001, context, capture), true);
  assertEquals(reported, [["coach_chat_slow_turn", "warning"]]);
});
