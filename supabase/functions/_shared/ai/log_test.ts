import { assertEquals } from "jsr:@std/assert@1";
import { captureLogs } from "./fakes.ts";
import { aiCallFields, logAiCall } from "./log.ts";

const record = {
  feature: "meal_vision" as const,
  provider: "anthropic" as const,
  vendor: "anthropic" as const,
  model: "claude-haiku-5-5",
  outcome: "ok" as const,
  usage: {
    inputTokens: 1340,
    outputTokens: 210,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    costUsd: 0.000239,
  },
  latencyMs: 812.6,
  httpStatus: 200,
  stop: "end" as const,
};

Deno.test("ai_call fields are the fixed set, with usage spelled out", () => {
  assertEquals(aiCallFields(record), {
    feature: "meal_vision",
    provider: "anthropic",
    vendor: "anthropic",
    model: "claude-haiku-5-5",
    outcome: "ok",
    input_tokens: 1340,
    output_tokens: 210,
    cache_read_tokens: 0,
    cache_write_tokens: 0,
    cost_usd: 0.000239,
    latency_ms: 813,
    http_status: 200,
    stop: "end",
  });
});

Deno.test("a failure without usage logs nulls; model ids are clipped to id characters", () => {
  const fields = aiCallFields({
    ...record,
    model: 'claude-haiku-5-5" <script>',
    outcome: "timeout",
    usage: null,
    httpStatus: null,
    stop: null,
  });
  assertEquals(fields.model, "claude-haiku-5-5script");
  assertEquals(fields.input_tokens, null);
  assertEquals(fields.cost_usd, null);
});

Deno.test("success logs at info, failure at warn, one line each", async () => {
  const ok = await captureLogs(() => Promise.resolve(logAiCall(record)));
  const failed = await captureLogs(() =>
    Promise.resolve(logAiCall({ ...record, outcome: "rate_limited", usage: null, stop: null }))
  );
  assertEquals(ok.lines.length, 1);
  assertEquals(failed.lines.length, 1);
  assertEquals(JSON.parse(ok.lines[0]).level, "info");
  assertEquals(JSON.parse(failed.lines[0]).level, "warn");
  assertEquals(JSON.parse(failed.lines[0]).msg, "ai_call");
});
