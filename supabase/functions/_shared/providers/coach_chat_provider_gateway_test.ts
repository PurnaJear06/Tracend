// Coach chat through the AI gateway, offline: every provider answer comes from a fake fetch.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  captureLogs,
  claudeMessage,
  fakeFetch,
  jsonResponse,
  routeFor,
  type Sent,
} from "../ai/fakes.ts";
import { isSupportedSchema } from "../ai/json_schema.ts";
import { anthropicSchema } from "../ai/adapters/anthropic.ts";
import { evalProfiles } from "../../_evals/fixtures.ts";
import { renderCoachContext } from "../coach_context/host.ts";
import {
  buildCoachChatGatewayPrompt,
  chooseCoachChatRoute,
  coachChatGatewaySchema,
  coachChatReservationCapUsd,
  coachChatReservationUsd,
  generateCoachChatViaGateway,
} from "./coach_chat_provider_gateway.ts";
import {
  classifyQuestion,
  coachChatFailureUsage,
  coachChatTiming,
  CoachChatUnavailableError,
  formatContextAsMarkdown,
} from "./coach_chat_provider.ts";
import type { AiRoute } from "../ai/types.ts";

const rich = () => structuredClone(evalProfiles().find((p) => p.id === "rich")!.context);
const haiku = () =>
  routeFor("coach_chat", { MODEL: "claude-haiku-5-5", MAX_OUTPUT_TOKENS: "4096" });
const sonnet = () =>
  routeFor("coach_chat", { MODEL: "claude-sonnet-5-5", MAX_OUTPUT_TOKENS: "4096" });

const answer = (overrides: Record<string, unknown> = {}) =>
  JSON.stringify({
    answer: "Your recovery is **38/100**, so keep today's session light.",
    evidence: [{ code: "RECOVERY_BELOW_BASELINE", label: "Recovery 38", source: "coach_context" }],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: ["What should I change today?"],
    reasoning_chain: [{ step: "Recovery", value: "38/100", evidence_id: null }],
    ...overrides,
  });

const claudeAnswer = (text: string, usage: Record<string, unknown> = {}, extra = {}) =>
  jsonResponse(claudeMessage({ content: [{ type: "text", text }], ...extra }, usage));

type Body = {
  system: { text: string; cache_control?: unknown }[];
  messages: { role: string; content: { text: string; cache_control?: unknown }[] }[];
  [key: string]: unknown;
};
const body = (sent: Sent) => sent.body as unknown as Body;

async function run(
  respond: (sent: Sent, index: number) => Response,
  options: {
    question?: string;
    context?: Record<string, unknown>;
    route?: AiRoute;
    consentVendor?: "anthropic" | "deepseek" | null;
  } = {},
) {
  let index = 0;
  const fake = fakeFetch((sent) => respond(sent, index++));
  const question = options.question ?? "How did my training go this week?";
  const route = options.route ?? haiku();
  const logged = await captureLogs(async () => {
    try {
      return await generateCoachChatViaGateway({
        question,
        context: options.context ?? rich(),
        contextKind: classifyQuestion(question),
        route,
        consentVendor: options.consentVendor === undefined ? "anthropic" : options.consentVendor,
      }, { fetch: fake.fetch });
    } catch (error) {
      return error as CoachChatUnavailableError;
    }
  });
  return { result: logged.result, lines: logged.lines, sent: fake.sent };
}

Deno.test("gateway prompt: rules first, then the cached athlete file, the question last", () => {
  const prompt = buildCoachChatGatewayPrompt(
    "How did my training go this week?",
    rich(),
    "explain_evidence",
  );
  assertEquals(prompt.system.length, 1);
  assertStringIncludes(prompt.system[0].type === "text" ? prompt.system[0].text : "", "Tracend");
  const parts = prompt.messages[0].content.map((part) => part.type === "text" ? part : null);
  assertEquals(parts.map((part) => part?.cache ?? false), [true, false, false]);
  assertStringIncludes(parts[0]!.text, "<coaching_context>");
  assertStringIncludes(parts[0]!.text, "## Context Date");
  assertStringIncludes(parts[1]!.text, "<coaching_context_recent>");
  assertEquals(parts[2]!.text, "User's message:\nHow did my training go this week?");
});

Deno.test("gateway prompt: questions share the rules and athlete file byte for byte", () => {
  const context = rich();
  const first = buildCoachChatGatewayPrompt("How did I sleep?", context, "recovery");
  const later = buildCoachChatGatewayPrompt(
    "Should I train legs today or rest?",
    {
      ...context,
      recent_messages: [
        { role: "user", content: "How did I sleep?" },
        { role: "assistant", content: "About 6 hours, below your 7-hour average." },
      ],
    },
    "daily_action",
  );
  assertEquals(later.system, first.system);
  assertEquals(later.messages[0].content[0], first.messages[0].content[0]);
  // The new conversation turn sits after the cache breakpoint, before the question.
  const turn = later.messages[0].content[1];
  assertEquals(turn.type === "text" && turn.cache, undefined);
  assertStringIncludes(turn.type === "text" ? turn.text : "", "About 6 hours");
  assertEquals(later.messages[0].content.length, 3);
});

Deno.test("gateway prompt carries the same athlete file as today's path", () => {
  const context = {
    ...rich(),
    recent_messages: [{ role: "user", content: "Earlier question" }],
  };
  const prompt = buildCoachChatGatewayPrompt("Plan for today?", context, "daily_action");
  const text = prompt.messages[0].content.map((part) => part.type === "text" ? part.text : "")
    .join("\n");
  const markdown = formatContextAsMarkdown(context, 90_000);
  for (const line of markdown.split("\n").filter((line) => line.startsWith("## "))) {
    assertStringIncludes(text, line);
  }
});

Deno.test("gateway prompt: stable contributors join the cached block, volatile ones follow it", async () => {
  const contributions = await renderCoachContext([
    { id: "library", slot: "stable", budgetChars: 200, render: () => Promise.resolve("Paper A.") },
    { id: "note", slot: "volatile", budgetChars: 200, render: () => Promise.resolve("Today.") },
  ], { userId: "u", question: "q", localDate: "2026-09-27" });
  const prompt = buildCoachChatGatewayPrompt("q", rich(), "general", contributions);
  const [cached, turn, question] = prompt.messages[0].content.map((part) =>
    part.type === "text" ? part.text : ""
  );
  assert(cached.indexOf("</coaching_context>") < cached.indexOf('source="library"'));
  assertStringIncludes(turn, 'source="note"');
  assertEquals(question, "User's message:\nq");
});

Deno.test("the gateway schema is one the gateway checks and Claude accepts", () => {
  for (const permitted of [["APPROVED_PLAN_ACTIVE"], []]) {
    const schema = coachChatGatewaySchema(permitted);
    assert(isSupportedSchema(schema));
    assert(anthropicSchema(schema) !== null);
  }
});

Deno.test("Haiku route: one cache-friendly request, priced usage, the answering model stored", async () => {
  const { result, sent, lines } = await run(() =>
    claudeAnswer(answer(), {
      input_tokens: 40,
      output_tokens: 300,
      cache_read_input_tokens: 9_000,
      cache_creation_input_tokens: 0,
    }, { model: "claude-haiku-5-5" })
  );
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 1);
  const sentBody = body(sent[0]);
  assertEquals(sent[0].url, "https://api.anthropic.com/v1/messages");
  assertEquals(sentBody.thinking, { type: "disabled" });
  assertEquals(sentBody.temperature, undefined);
  assertEquals((sentBody.output_config as { format: { type: string } }).format.type, "json_schema");
  assertEquals(sentBody.system[0].cache_control, undefined);
  assertEquals(sentBody.messages[0].content[0].cache_control, { type: "ephemeral" });
  assertStringIncludes(sentBody.messages[0].content.at(-1)!.text, "How did my training go");
  assertEquals(result.provider, "anthropic");
  assertEquals(result.model, "claude-haiku-5-5");
  assertEquals(result.inputUnits, 9_040);
  assertEquals(result.outputUnits, 300);
  // Haiku 5.5: 40 × 0.10 + 300 × 0.50 + 9,000 × 0.01 = 244 µUSD.
  assertEquals(result.estimatedCostUsd, 0.000244);
  assertEquals(result.attempts[0].cacheReadTokens, 9_000);
  assertEquals(result.answer.evidence[0].code, "RECOVERY_BELOW_BASELINE");
  const aiCall = lines.map((line) => JSON.parse(line)).find((entry) => entry.msg === "ai_call");
  assertEquals(aiCall.feature, "coach_chat");
  assertEquals(aiCall.cache_read_tokens, 9_000);
  assert(!lines.join("\n").includes("38/100"), "the answer text is never logged");
});

Deno.test("Sonnet route turns thinking off with between_tools", async () => {
  const { result, sent } = await run(() => claudeAnswer(answer()), { route: sonnet() });
  if (result instanceof Error) throw result;
  assertEquals(body(sent[0]).thinking, { type: "between_tools" });
});

Deno.test("an answer over a limit is repaired with the rule, the candidate and the same prefix", async () => {
  const bad = answer({
    suggested_follow_ups: ["One", "Two", "Three", "Four", "Five", "Six", "Seven-MARKER"],
  });
  const { result, sent } = await run((_, index) =>
    index === 0
      ? claudeAnswer(bad, {
        input_tokens: 100,
        output_tokens: 200,
        cache_creation_input_tokens: 9_000,
      })
      : claudeAnswer(answer(), {
        input_tokens: 400,
        output_tokens: 250,
        cache_read_input_tokens: 9_000,
      })
  );
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 2);
  const [first, repair] = sent.map(body);
  assertEquals(repair.system, first.system);
  assertEquals(repair.messages[0].content[0], first.messages[0].content[0]);
  const repairText = repair.messages[0].content.at(-1)!.text;
  assertStringIncludes(repairText, "rule=follow_ups_too_many");
  assertStringIncludes(repairText, "<invalid_candidate>");
  assertStringIncludes(repairText, "Seven-MARKER");
  assertEquals(result.attempts.map((a) => [a.attempt, a.outcome]), [
    ["initial", "invalid"],
    ["repair", "valid"],
  ]);
  // 100 × 0.10 + 200 × 0.50 + 9,000 × 0.125, then 400 × 0.10 + 250 × 0.50 + 9,000 × 0.01.
  assertEquals(result.estimatedCostUsd, 0.00149);
});

Deno.test("a citation outside the permitted codes fails the schema and is repaired", async () => {
  const made = answer({ evidence: [{ code: "MADE_UP", label: "x", source: "coach_context" }] });
  const { result, sent } = await run((_, index) => claudeAnswer(index === 0 ? made : answer()));
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 2);
  assertEquals(result.attempts.map((a) => a.outcome), ["invalid", "valid"]);
});

Deno.test("an answer that is not JSON is repaired without a candidate; failing twice is invalid", async () => {
  const { result, sent } = await run(() => claudeAnswer("not json", { output_tokens: 20 }));
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(sent.length, 2);
  assert(!body(sent[1]).messages[0].content.at(-1)!.text.includes("<invalid_candidate>"));
  assertEquals(result.failureReason, "provider_response_invalid");
  assertEquals(result.metadata.initialRule, "json_syntax");
  assertEquals(result.metadata.repairRule, "json_syntax");
  assertEquals(result.provider, "anthropic");
  // Both billed answers count toward the budget: 2 × (1,000 × 0.10 + 20 × 0.50) µUSD.
  assertEquals(coachChatFailureUsage(result).estimatedCostUsd, 0.00022);
  assertEquals(coachChatFailureUsage(result).outputUnits, 40);
});

Deno.test("an answer cut off at the output limit is reported as truncated", async () => {
  const { result } = await run(() =>
    claudeAnswer('{"answer": "cut', { output_tokens: 4096 }, { stop_reason: "max_tokens" })
  );
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.failureReason, "provider_response_truncated");
  assertEquals(result.metadata.attempts?.map((a) => a.outcome), ["truncated", "truncated"]);
});

Deno.test("provider failures map to Coach chat's existing codes and are not repaired", async () => {
  const cases: [() => Response, string, number | null][] = [
    [() => jsonResponse({}, 429, { "retry-after": "17" }), "provider_rate_limited", 17],
    [() => jsonResponse({}, 429), "provider_rate_limited", 60],
    [() => jsonResponse({}, 529), "provider_http_error", null],
    [() => jsonResponse({}, 500), "provider_http_error", null],
    [
      () => claudeAnswer("", { output_tokens: 5 }, { stop_reason: "refusal" }),
      "provider_response_invalid",
      null,
    ],
  ];
  for (const [respond, code, retryAfter] of cases) {
    const { result, sent } = await run(respond);
    assert(result instanceof CoachChatUnavailableError, code);
    assertEquals(sent.length, 1, code);
    assertEquals(result.failureReason, code);
    assertEquals(result.retryAfterSeconds, retryAfter, code);
  }
});

Deno.test("a refused answer still counts its tokens", async () => {
  const { result } = await run(() =>
    claudeAnswer("", { input_tokens: 2_000, output_tokens: 10 }, { stop_reason: "refusal" })
  );
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.metadata.attempts?.[0].outcome, "refused");
  assertEquals(coachChatFailureUsage(result).estimatedCostUsd, 0.000205);
});

Deno.test("a timeout ends the turn as provider_timeout", async () => {
  const fake = fakeFetch((sent) =>
    new Promise<Response>((_, reject) => {
      sent.signal?.addEventListener("abort", () => reject(new DOMException("", "AbortError")));
    })
  );
  const { result } = await captureLogs(() =>
    generateCoachChatViaGateway(
      {
        question: "How did my training go this week?",
        context: rich(),
        contextKind: "explain_evidence",
        route: haiku(),
        consentVendor: "anthropic",
      },
      { fetch: fake.fetch },
      { totalDeadlineMs: 30, initialAttemptMs: 30, repairAttemptMs: 30 },
    )
      .catch((error) => error)
  );
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.failureReason, "provider_timeout");
});

Deno.test("a consent for another vendor sends nothing", async () => {
  for (const consentVendor of ["deepseek", null] as const) {
    const { result, sent } = await run(() => claudeAnswer(answer()), { consentVendor });
    assert(result instanceof CoachChatUnavailableError);
    assertEquals(sent.length, 0);
    assertEquals(result.failureReason, "provider_http_error");
    assertEquals(coachChatFailureUsage(result).estimatedCostUsd, 0);
  }
});

Deno.test("the safety boundary answers before any request", async () => {
  const { result, sent } = await run(() => claudeAnswer(answer()), {
    question: "I have chest pain during squats",
  });
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 0);
  assertEquals(result.provider, "mock");
  assertEquals(result.answer.safety_state, "refused");
});

Deno.test("a DeepSeek route through the gateway restates the schema for JSON mode", async () => {
  const route = routeFor("coach_chat", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_COACH_CHAT: "synthetic-key",
  });
  const { result, sent } = await run(
    () =>
      jsonResponse({
        model: "deepseek-flash",
        choices: [{ message: { content: answer() }, finish_reason: "stop" }],
        usage: { prompt_tokens: 9_000, completion_tokens: 300, prompt_cache_hit_tokens: 8_000 },
      }),
    { route, consentVendor: "deepseek" },
  );
  if (result instanceof Error) throw result;
  assertEquals(sent[0].url, "https://api.deepseek.com/v1/chat/completions");
  assertEquals(result.provider, "deepseek");
  assertEquals(result.attempts[0].cacheReadTokens, 8_000);
  const system = (sent[0].body.messages as { content: string }[])[0].content;
  assertStringIncludes(system, "Return only valid JSON matching this schema");
});

Deno.test("the first attempt's reservation is its own worst case, never clamped", () => {
  const haikuCeiling = coachChatReservationUsd(haiku(), [])!;
  const sonnetCeiling = coachChatReservationUsd(sonnet(), [])!;
  // (128,000 + 16,000) / 1.5 = 96,000 prompt tokens written plus 4,096 output tokens, once.
  assertEquals(haikuCeiling, 0.014048);
  assertEquals(sonnetCeiling, 0.28096);
  assert(sonnetCeiling <= coachChatReservationCapUsd);
});

Deno.test("a route whose one attempt cannot be reserved takes today's path", () => {
  const large = routeFor("coach_chat", {
    MODEL: "claude-sonnet-5-5",
    MAX_OUTPUT_TOKENS: "32000",
    EVALUATED: "true",
  });
  assert(coachChatReservationUsd(large, [])! > coachChatReservationCapUsd);
  const choice = chooseCoachChatRoute(large, []);
  assertEquals(choice.route, null);
  assert("legacyReason" in choice && choice.legacyReason === "unreservable");
});

Deno.test("EVALUATED=false behaves like no route; true, a complete route", () => {
  assertEquals(chooseCoachChatRoute(null, []), { route: null, legacyReason: "no_route" });
  for (const value of [undefined, "false"]) {
    const found = routeFor("coach_chat", value === undefined ? {} : { EVALUATED: value });
    assertEquals(chooseCoachChatRoute(found, []), { route: null, legacyReason: "not_evaluated" });
  }
  const evaluated = routeFor("coach_chat", { EVALUATED: "true" });
  assertEquals(chooseCoachChatRoute(evaluated, []), { route: evaluated, timeoutClamped: false });
});

Deno.test("a route timeout over the total deadline is clamped and reported, not ignored", () => {
  const slow = routeFor("coach_chat", { EVALUATED: "true", TIMEOUT_MS: "150000" });
  const choice = chooseCoachChatRoute(slow, []);
  assert("timeoutClamped" in choice && choice.timeoutClamped);
  assertEquals(coachChatTiming.totalDeadlineMs, 40_000);
  const ok = routeFor("coach_chat", { EVALUATED: "true", TIMEOUT_MS: "40000" });
  assertEquals(chooseCoachChatRoute(ok, []), { route: ok, timeoutClamped: false });
});

Deno.test("an attempt waits for the route's timeout, not a shorter fixed one", async () => {
  const route = routeFor("coach_chat", { TIMEOUT_MS: "1000" });
  const started = performance.now();
  const fake = fakeFetch((sent) =>
    new Promise<Response>((_, reject) => {
      sent.signal?.addEventListener("abort", () => reject(new DOMException("", "AbortError")));
    })
  );
  const { result } = await captureLogs(() =>
    generateCoachChatViaGateway(
      {
        question: "How did my training go this week?",
        context: rich(),
        contextKind: "explain_evidence",
        route,
        consentVendor: "anthropic",
      },
      { fetch: fake.fetch },
      { totalDeadlineMs: 30_000, initialAttemptMs: 100, repairAttemptMs: 100 },
    ).catch((error) => error)
  );
  const elapsed = performance.now() - started;
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.failureReason, "provider_timeout");
  assert(elapsed >= 900 && elapsed < 5_000, `waited ${elapsed} ms`);
});

Deno.test("a repair reserves its own worst case before it is sent; a refused place sends nothing", async () => {
  const reserved: number[] = [];
  const budget = (accept: boolean) => ({
    reserveRepair: (usd: number) => {
      reserved.push(usd);
      return Promise.resolve(accept);
    },
    inFlight: () => {},
  });
  const bad = () => claudeAnswer("not json", { output_tokens: 20 });
  const route = haiku();
  const question = "How did my training go this week?";
  const attempt = (accept: boolean) => {
    const fake = fakeFetch(bad);
    return captureLogs(() =>
      generateCoachChatViaGateway({
        question,
        context: rich(),
        contextKind: classifyQuestion(question),
        route,
        consentVendor: "anthropic",
        budget: budget(accept),
      }, { fetch: fake.fetch }).catch((error) => error)
    ).then((logged) => ({ result: logged.result, sent: fake.sent }));
  };

  const accepted = await attempt(true);
  assertEquals(accepted.sent.length, 2);
  assertEquals(reserved.length, 1);
  assert(reserved[0] > 0 && reserved[0] <= coachChatReservationCapUsd);

  const refused = await attempt(false);
  assertEquals(refused.sent.length, 1);
  assert(refused.result instanceof CoachChatUnavailableError);
  assertEquals(refused.result.failureReason, "provider_response_invalid");
  assertEquals(refused.result.metadata.repairSkipped, "reservation_refused");
  // The first attempt was billed and is still recorded.
  assertEquals(coachChatFailureUsage(refused.result).estimatedCostUsd, 0.00011);
  assertEquals(reserved.length, 2);
});

Deno.test("a legacy failure is still priced from its own attempts", () => {
  const legacy = new CoachChatUnavailableError("deepseek", "deepseek-flash", "provider_timeout");
  assertEquals(coachChatFailureUsage(legacy).estimatedCostUsd, 0);
});
