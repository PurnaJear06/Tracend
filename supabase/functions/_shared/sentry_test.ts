import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { buildSentryEvent, buildSentryMessageEvent } from "./sentry.ts";

Deno.test("Edge Sentry event keeps diagnostic tags and excludes sensitive context", () => {
  const error = new Error("coach_chat_unavailable: provider_response_invalid");
  error.stack = "s".repeat(5_000);
  const event = buildSentryEvent(error, {
    userId: "owner-id",
    functionName: "coach-chat",
    correlationId: "correlation-id",
    runtime: "edge",
    provider: "deepseek",
    model: "deepseek-v4-flash",
    contextKind: "recovery",
    failureCode: "provider_response_invalid",
    attempt: "repair",
    finishReason: "stop",
    initialValidationRule: "evidence_code_not_permitted",
    repairValidationRule: "reasoning_value_too_long",
    answerSource: "data_summary",
    coachingDate: "2026-09-11",
    ...({
      question: "private question",
      healthContext: "private health context",
      providerResponse: "private model output",
      httpBody: "private HTTP body",
    } as Record<string, unknown>),
  });

  const tags = event.tags as Record<string, unknown>;
  assertEquals(tags.runtime, "edge");
  assertEquals(tags.provider, "deepseek");
  assertEquals(tags.context_kind, "recovery");
  assertEquals(tags.failure_code, "provider_response_invalid");
  assertEquals(tags.attempt, "repair");
  assertEquals(tags.finish_reason, "stop");
  assertEquals(tags.initial_validation_rule, "evidence_code_not_permitted");
  assertEquals(tags.repair_validation_rule, "reasoning_value_too_long");
  assertEquals(tags.answer_source, "data_summary");

  const exception = (event.exception as { values: Record<string, unknown>[] }).values[0];
  assertEquals(exception.type, "Error");
  assertEquals(exception.value, "provider_response_invalid");
  const serialized = JSON.stringify(event);
  assert(!serialized.includes("private question"));
  assert(!serialized.includes("private health context"));
  assert(!serialized.includes("private model output"));
  assert(!serialized.includes("private HTTP body"));
});

const secret = "SECRET-athlete-text-and-provider-body";

function serialized(error: unknown, context = {}): string {
  return JSON.stringify(
    buildSentryEvent(error, { failureCode: "provider_request_failed", ...context }),
  );
}

class ProviderHttpError extends Error {
  constructor(readonly status: number, readonly body: string) {
    super(`provider answered ${status}: ${body}`);
    this.name = "ProviderHttpError";
    this.cause = new Error(body);
  }
}

Deno.test("a provider error with a response body sends the code, class and status only", () => {
  const error = new ProviderHttpError(502, secret);
  const event = buildSentryEvent(error, {
    functionName: "coach-chat",
    failureCode: "provider_request_failed",
    provider: "deepseek",
    latencyMs: 812,
  });
  assert(!JSON.stringify(event).includes(secret));
  const exception = (event.exception as { values: Record<string, unknown>[] }).values[0];
  assertEquals(exception.type, "ProviderHttpError");
  assertEquals(exception.value, "provider_request_failed");
  const tags = event.tags as Record<string, string>;
  assertEquals(tags.http_status, "502");
  assertEquals(tags.latency_ms, "812");
  assertEquals(tags.provider, "deepseek");
});

Deno.test("a JSON parse error quoting the model text sends none of it", () => {
  let error: unknown;
  try {
    JSON.parse(`{"reply": "${secret}" oops`);
  } catch (caught) {
    error = caught;
  }
  assert(error instanceof SyntaxError);
  assert(String(error.message).includes("oops") || String(error.message).length > 0);
  const text = serialized(error);
  assert(!text.includes(secret));
  assert(!text.includes("oops"));
  assertEquals(
    (JSON.parse(text).exception.values[0] as Record<string, string>).type,
    "SyntaxError",
  );
});

Deno.test("a plain Error carrying user text sends none of it", () => {
  const text = serialized(new Error(`the athlete wrote: ${secret}`));
  assert(!text.includes(secret));
  assert(!text.includes("athlete wrote"));
});

Deno.test("without a code the value is the error class name, never the message", () => {
  const event = buildSentryEvent(new TypeError(secret), {});
  const exception = (event.exception as { values: Record<string, unknown>[] }).values[0];
  assertEquals(exception.type, "TypeError");
  assertEquals(exception.value, "TypeError");
  assert(!JSON.stringify(event).includes(secret));
});

Deno.test("a thrown string, object or null sends only a fixed class name", () => {
  for (const thrown of [secret, { message: secret, body: secret }, null, undefined]) {
    const event = buildSentryEvent(thrown, { failureCode: "x y" });
    assert(!JSON.stringify(event).includes(secret));
    const exception = (event.exception as { values: Record<string, unknown>[] }).values[0];
    assertEquals(exception.type, "NonError");
    assertEquals(exception.value, "NonError");
  }
});

Deno.test("free text in a context field is replaced, codes pass", () => {
  const spaced = "the athlete wrote this sentence";
  const event = buildSentryEvent(new Error("x"), {
    failureCode: spaced,
    errorCode: "42501",
    provider: spaced,
    model: "qwen/qwen3.6-27b",
    correlationId: spaced,
    functionName: "coach-chat",
    attempts: [{ attempt: spaced, outcome: "ok", latencyMs: 5, schemaSha: spaced }],
  });
  const text = JSON.stringify(event);
  assert(!text.includes("athlete wrote"));
  const tags = event.tags as Record<string, string>;
  assertEquals(tags.error_code, "42501");
  assertEquals(tags.model, "qwen/qwen3.6-27b");
  assertEquals(tags.provider, "unknown");
  assertEquals(tags.function, "coach-chat");
});

Deno.test("the stack keeps function, file and line, and drops the message and the source", () => {
  const error = new Error(secret);
  error.stack = [
    `Error: ${secret}`,
    "    at parseReply (file:///src/functions/coach-chat/index.ts:42:13)",
    `    at async Object.handle (file:///src/functions/_shared/x.ts?token=${secret}:7:3)`,
    `    at file:///src/main.ts:1:1`,
    `    at broken (file:///src/y.ts:9:9 ${secret}`,
    `    const leaked = "${secret}";`,
  ].join("\n");
  const event = buildSentryEvent(error, { failureCode: "provider_request_failed" });
  assert(!JSON.stringify(event).includes(secret));
  const frames =
    (event.exception as { values: { stacktrace: { frames: Record<string, unknown>[] } }[] })
      .values[0].stacktrace.frames;
  assertEquals(frames, [
    { filename: "file:///src/main.ts", lineno: 1 },
    { function: "async Object.handle", filename: "file:///src/functions/_shared/x.ts", lineno: 7 },
    { function: "parseReply", filename: "file:///src/functions/coach-chat/index.ts", lineno: 42 },
  ]);
  assertEquals((event.extra as Record<string, unknown>).stack, undefined);
});

Deno.test("a long stack keeps a bounded number of frames", () => {
  const error = new Error("x");
  error.stack = Array.from({ length: 200 }, (_, i) => `    at f${i} (file:///a.ts:${i + 1}:1)`)
    .join("\n");
  const frames = (buildSentryEvent(error, { failureCode: "c" }).exception as {
    values: { stacktrace: { frames: unknown[] } }[];
  }).values[0].stacktrace.frames;
  assertEquals(frames.length, 30);
});

Deno.test("a message event carries a code, never free text", () => {
  const code = buildSentryMessageEvent("coach_chat_slow_turn", "warning", {
    functionName: "coach-chat",
  });
  assertEquals(code.message, "coach_chat_slow_turn");
  const text = buildSentryMessageEvent(`reply: ${secret}`, "warning", {});
  assertEquals(text.message, "invalid_message");
  assert(!JSON.stringify(text).includes(secret));
});
