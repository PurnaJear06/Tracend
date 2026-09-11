import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { buildSentryEvent } from "./sentry.ts";

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

  const extra = event.extra as Record<string, unknown>;
  assertEquals(String(extra.stack).length, 4_000);
  const serialized = JSON.stringify(event);
  assert(!serialized.includes("private question"));
  assert(!serialized.includes("private health context"));
  assert(!serialized.includes("private model output"));
  assert(!serialized.includes("private HTTP body"));
});
