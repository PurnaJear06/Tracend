import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  buildSentryEvent,
  buildSentryMessageEvent,
  captureException,
  captureMessage,
  providerFailure,
} from "./sentry.ts";

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
  error.stack = "Error: x\n" +
    Array.from({ length: 200 }, (_, i) => `    at f${i} (file:///a.ts:${i + 1}:1)`).join("\n");
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

type Frame = { function?: string; filename: string; lineno: number };
const framesOf = (event: Record<string, unknown>): Frame[] =>
  (event.exception as { values: { stacktrace?: { frames: Frame[] } }[] }).values[0].stacktrace
    ?.frames ?? [];

Deno.test("lines of a multi-line message that look like frames are never read as frames", () => {
  const error = new Error(
    "x:\n    at my knee hurts when I squat (heavy:12:3)\n    at user@example.com:5:6",
  );
  const event = buildSentryEvent(error, { failureCode: "provider_request_failed" });
  const text = JSON.stringify(event);
  assert(!text.includes("knee"));
  assert(!text.includes("example.com"));
  assert(!text.includes("squat"));
  const frames = framesOf(event);
  assert(frames.length > 0);
  assert(frames.every((frame) => /^(file|ext):/.test(frame.filename)));
  assert(frames.some((frame) => frame.filename.endsWith("sentry_test.ts")));
});

Deno.test("a message carrying a fake stack with an email as the filename sends nothing of it", () => {
  const message =
    "boom\n    at fake (user@example.com:5:6)\n    at lift (https://knee.example/heavy:1:2)";
  const error = new Error(message);
  error.stack = `Error: ${message}\n    at real (file:///src/real.ts:3:4)`;
  const event = buildSentryEvent(error, { failureCode: "provider_request_failed" });
  const text = JSON.stringify(event);
  assert(!text.includes("example.com"));
  assert(!text.includes("knee"));
  assertEquals(framesOf(event), [{ function: "real", filename: "file:///src/real.ts", lineno: 3 }]);
});

Deno.test("a stack whose header cannot be found sends no frames", () => {
  const error = new Error("one");
  error.stack = "Error: changed\n    at real (file:///src/real.ts:3:4)";
  assertEquals(framesOf(buildSentryEvent(error, { failureCode: "c" })), []);
});

Deno.test("frames keep only function names without spaces, and only loaded files", () => {
  const error = new Error("m");
  error.stack = [
    "Error: m",
    "    at async Object.handle [as run] (file:///src/a.ts:1:1)",
    "    at new Widget (ext:deno_web/b.ts:2:2)",
    "    at my knee hurts (file:///src/c.ts:3:3)",
    "    at /home/user/d.ts:4:4",
    "    at e (heavy:5:5)",
    "    at async f (https://deno.land/x/g.ts:6:6)",
  ].join("\n");
  assertEquals(framesOf(buildSentryEvent(error, { failureCode: "c" })), [
    { function: "async f", filename: "https://deno.land/x/g.ts", lineno: 6 },
    { filename: "file:///src/c.ts", lineno: 3 },
    { function: "new Widget", filename: "ext:deno_web/b.ts", lineno: 2 },
    { filename: "file:///src/a.ts", lineno: 1 },
  ]);
});

Deno.test("a provider failure keeps its status and code, never words", () => {
  assertEquals(
    providerFailure(new Error("meal_vision_request_failed:503:overloaded")),
    { errorCode: "meal_vision_request_failed:503:overloaded", httpStatus: 503 },
  );
  assertEquals(
    providerFailure(new Error("meal_vision_request_failed:429:rate_limit_exceeded")),
    { errorCode: "meal_vision_request_failed:429:rate_limit_exceeded", httpStatus: 429 },
  );
  assertEquals(providerFailure(new Error("meal_vision_request_failed")), {
    errorCode: "meal_vision_request_failed",
  });
  assertEquals(
    providerFailure(Object.assign(new Error("words in it"), { code: "physique_busy" })),
    {
      errorCode: "physique_busy",
    },
  );
  assertEquals(providerFailure(new Error(`the athlete wrote ${secret} here`)), {});
  assertEquals(providerFailure("meal_vision_request_failed:503:x"), {});
  assertEquals(providerFailure(null), {});
  const event = buildSentryEvent(new Error("x"), {
    failureCode: "meal_analysis_unavailable",
    ...providerFailure(new Error("meal_vision_request_failed:503:overloaded")),
  });
  const tags = event.tags as Record<string, string>;
  assertEquals(tags.error_code, "meal_vision_request_failed:503:overloaded");
  assertEquals(tags.http_status, "503");
});

function withDsn(run: (sent: string[]) => void) {
  const sent: string[] = [];
  const realFetch = globalThis.fetch;
  Deno.env.set("SENTRY_DSN", "https://publickey@sentry.example.com/12345");
  globalThis.fetch = ((_url: unknown, init?: { body?: string }) => {
    sent.push(String(init?.body));
    return Promise.resolve(new Response("{}"));
  }) as typeof fetch;
  try {
    run(sent);
  } finally {
    globalThis.fetch = realFetch;
    Deno.env.delete("SENTRY_DSN");
  }
}

Deno.test("reporting never throws, even when the error's getters do", () => {
  const hostile = new Error("x");
  for (const key of ["status", "httpStatus", "name", "message", "stack", "code"]) {
    Object.defineProperty(hostile, key, {
      get() {
        throw new Error("getter failed");
      },
    });
  }
  withDsn((sent) => {
    captureException(hostile, { failureCode: "provider_request_failed" });
    captureMessage("coach_chat_slow_turn", "warning", { functionName: "coach-chat" });
    assertEquals(sent.length, 2);
    assertEquals(
      (JSON.parse(sent[0]).exception.values[0] as Record<string, string>).value,
      "provider_request_failed",
    );
  });
  const throwingContext = {
    get failureCode(): string {
      throw new Error("context failed");
    },
  } as unknown as { failureCode: string };
  withDsn((sent) => {
    captureException(new Error("x"), throwingContext);
    assertEquals(sent.length, 0);
  });
});

Deno.test("an error whose status getter throws is still reported", () => {
  const error = Object.defineProperty(new Error("x"), "status", {
    get() {
      throw new Error("no status");
    },
  });
  withDsn((sent) => {
    captureException(error, { failureCode: "provider_request_failed" });
    assertEquals(sent.length, 1);
    assertEquals(JSON.parse(sent[0]).tags.http_status, undefined);
  });
});
