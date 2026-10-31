// The direct run's clients with fake fetches: the Coach on the production Claude route through the
// gateway, metered; the athlete and judges on the Messages API. No model.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  claudeMessage,
  envOf,
  fakeFetch,
  jsonResponse,
  settings,
  syntheticKey,
} from "../../_shared/ai/fakes.ts";
import type { TokenCounts } from "../../_shared/ai/models.ts";
import { anthropicChat, anthropicGatewayFromEnv } from "./anthropic_client.ts";
import type { WireError } from "./diagnostics.ts";
import { preflightDirect } from "./preflight.ts";

const answerJson = JSON.stringify({
  data_requests: [],
  proposal_intent: [],
  fact_suggestions: [],
  answer: "Keep it easy today.",
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
  reasoning_chain: [],
});

const productionEnv = envOf(settings("coach_chat", {
  MODEL: "claude-haiku-5-5",
  MAX_OUTPUT_TOKENS: "4096",
  TIMEOUT_MS: "30000",
  EVALUATED: "true",
}));

Deno.test("the direct Coach is the production Claude route through the gateway, metered", async () => {
  const fake = fakeFetch(() =>
    jsonResponse(
      claudeMessage(
        { model: "claude-haiku-5-5", content: [{ type: "text", text: answerJson }] },
        { input_tokens: 9000, output_tokens: 300, cache_read_input_tokens: 4000 },
      ),
    )
  );
  const direct = anthropicGatewayFromEnv(productionEnv, fake.fetch);
  assert(!("error" in direct));
  assertEquals(direct.coachModel, "claude-haiku-5-5");
  assert(direct.production);
  const usage: TokenCounts[] = [];
  const answers: string[] = [];
  const generation = await direct.generateWith(
    (t) => usage.push(t),
    undefined,
    (text) => answers.push(text),
  )({
    question: "How is my progress on the cut?",
    context: { coaching_date: "2026-10-14", permitted_evidence: [] },
    contextKind: "general",
    contributions: null,
  });
  assertEquals(generation.answer.answer, "Keep it easy today.");
  assertEquals(fake.sent.length, 1);
  const sent = fake.sent[0];
  assertEquals(sent.url, "https://api.anthropic.com/v1/messages");
  assertEquals(sent.headers["x-api-key"], syntheticKey);
  assertEquals(sent.body.model, "claude-haiku-5-5");
  assertEquals(sent.body.max_tokens, 4096);
  // Production's Claude request: the answer schema as structured output, thinking off.
  assertEquals(
    (sent.body.output_config as { format: { type: string } }).format.type,
    "json_schema",
  );
  assertEquals(sent.body.thinking, { type: "disabled" });
  assertEquals(usage, [{
    inputTokens: 9000,
    outputTokens: 300,
    cacheReadTokens: 4000,
    cacheWriteTokens: 0,
  }]);
  assertEquals(answers, [answerJson]);
});

Deno.test("a failed Coach call is recorded with its status and a redacted body", async () => {
  const fake = fakeFetch(() =>
    jsonResponse({ type: "error", error: { message: `bad key ${syntheticKey}` } }, 401)
  );
  const direct = anthropicGatewayFromEnv(productionEnv, fake.fetch);
  assert(!("error" in direct));
  const errors: WireError[] = [];
  await direct.generateWith(() => {}, (error) => errors.push(error))({
    question: "How is my progress on the cut?",
    context: { coaching_date: "2026-10-14", permitted_evidence: [] },
    contextKind: "general",
    contributions: null,
  }).catch(() => null);
  assert(errors.length >= 1);
  assertEquals(errors[0].kind, "http");
  assertEquals(errors[0].status, 401);
  assert(!errors[0].body.includes(syntheticKey));
});

Deno.test("without a Claude Coach route the direct run does not start", () => {
  const none = anthropicGatewayFromEnv(envOf({}));
  assert("error" in none);
  const other = anthropicGatewayFromEnv(envOf(settings("coach_chat", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_COACH_CHAT: syntheticKey,
  })));
  assert("error" in other && other.error.includes("Claude"));
});

Deno.test("the athlete and judge calls use the Messages API with thinking off and no sampling", async () => {
  const fake = fakeFetch(() =>
    jsonResponse(claudeMessage({ content: [{ type: "text", text: '{"ok": true}' }] }))
  );
  const chat = anthropicChat(syntheticKey, { fetcher: fake.fetch });
  const result = await chat({
    model: "claude-sonnet-5-5",
    system: "Judge.",
    user: "Score it.",
    maxTokens: 3000,
    json: true,
    source: "judge",
  });
  assert(result.ok);
  assertEquals(result.text, '{"ok": true}');
  // Sonnet 5.5 at list price: 1,000 in at USD 2/M and 200 out at USD 10/M.
  assertEquals(result.costUsd, 0.004);
  const body = fake.sent[0].body;
  assertEquals(body.system, "Judge.");
  assertEquals(body.messages, [{ role: "user", content: "Score it." }]);
  assertEquals(body.thinking, { type: "between_tools" });
  assertEquals(body.temperature, undefined);
  assertEquals(body.response_format, undefined);
});

Deno.test("a cut-off or empty answer is a failure; a server error is asked again", async () => {
  const truncated = anthropicChat(syntheticKey, {
    fetcher: fakeFetch(() => jsonResponse(claudeMessage({ stop_reason: "max_tokens" }))).fetch,
  });
  const cut = await truncated({
    model: "claude-haiku-5-5",
    system: "s",
    user: "u",
    maxTokens: 200,
    json: false,
    source: "athlete",
  });
  assert(!cut.ok && cut.kind === "truncated");

  let calls = 0;
  const flaky = anthropicChat(syntheticKey, {
    retryDelayMs: 1,
    fetcher: fakeFetch(() => {
      calls++;
      return calls === 1
        ? jsonResponse({ type: "error", error: { type: "overloaded_error" } }, 529)
        : jsonResponse(claudeMessage());
    }).fetch,
  });
  const second = await flaky({
    model: "claude-haiku-5-5",
    system: "s",
    user: "u",
    maxTokens: 200,
    json: false,
    source: "athlete",
  });
  assert(second.ok);
  assertEquals(calls, 2);
});

Deno.test("the direct preflight passes on a JSON reply and names the Messages API", async () => {
  const chat = anthropicChat(syntheticKey, {
    fetcher: fakeFetch(() =>
      jsonResponse(claudeMessage({ content: [{ type: "text", text: '{"ok": true}' }] }))
    ).fetch,
  });
  const check = await preflightDirect(chat, "coach", "claude-haiku-5-5", [syntheticKey]);
  assertEquals(check.working?.model, "claude-haiku-5-5");
  assert(check.working?.mode.messages);
  const refused = anthropicChat(syntheticKey, {
    fetcher: fakeFetch(() => jsonResponse({ error: "not found" }, 404)).fetch,
  });
  const failed = await preflightDirect(refused, "judge", "claude-sonnet-5-5", [syntheticKey]);
  assertEquals(failed.working, null);
  assertEquals(failed.attempts[0].status, 404);
});
