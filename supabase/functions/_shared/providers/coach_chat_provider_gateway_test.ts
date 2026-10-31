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
import { type CoachContributions, renderCoachContext } from "../coach_context/host.ts";
import { createLibraryContributor, libraryNoMatchText } from "../library/retrieval.ts";
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

// A model answer in the gateway's shape: every key present, nothing written as an empty list or "".
const answer = (overrides: Record<string, unknown> = {}) =>
  JSON.stringify({
    data_requests: [],
    proposal_intent: [],
    fact_suggestions: [],
    answer: "Your recovery is **38/100**, so keep today's session light.",
    evidence: [{ code: "RECOVERY_BELOW_BASELINE", label: "Recovery 38", source: "coach_context" }],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: ["What should I change today?"],
    reasoning_chain: [{ step: "Recovery", value: "38/100", evidence_id: "" }],
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
    contributions?: CoachContributions;
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
        ...(options.contributions ? { contributions: options.contributions } : {}),
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
  // The same sections; the check-ins heading says how many rows the gateway shows (the newest 3,
  // with the lookup for the rest), so it is compared by its name.
  for (const line of markdown.split("\n").filter((line) => line.startsWith("## "))) {
    assertStringIncludes(text, line.startsWith("## Check-ins (") ? "## Check-ins (" : line);
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
  const schema = coachChatGatewaySchema();
  assert(isSupportedSchema(schema));
  assert(anthropicSchema(schema) !== null);
});

Deno.test('the answer keeps today\'s shape: a reasoning step with no evidence is null, not ""', async () => {
  const { result } = await run(() =>
    claudeAnswer(answer({
      reasoning_chain: [
        { step: "goal", value: "Cut", evidence_id: "" },
        { step: "recovery", value: "38/100", evidence_id: "RECOVERY_BELOW_BASELINE" },
      ],
    }))
  );
  if (result instanceof Error) throw result;
  assertEquals(result.answer.reasoning_chain, [
    { step: "goal", value: "Cut", evidence_id: null },
    { step: "recovery", value: "38/100", evidence_id: "RECOVERY_BELOW_BASELINE" },
  ]);
  assertEquals(Object.keys(result.answer).sort(), [
    "answer",
    "evidence",
    "missing_data",
    "reasoning_chain",
    "safety_state",
    "suggested_follow_ups",
  ]);
});

Deno.test("an evidence code that is not permitted is a plain string to the schema and a repair to the parser", async () => {
  const unpermitted = answer({
    evidence: [{ code: "MADE_UP_CODE", label: "x", source: "coach_context" }],
  });
  const { result, sent } = await run((_, index) =>
    claudeAnswer(index === 0 ? unpermitted : answer())
  );
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 2);
  assertEquals(result.attempts.map((a) => [a.attempt, a.outcome, a.rule]), [
    ["initial", "invalid", "evidence_code_not_permitted"],
    ["repair", "valid", undefined],
  ]);
  const repair = body(sent[1]).messages[0].content.at(-1)!.text;
  assertStringIncludes(repair, "rule=evidence_code_not_permitted");
  assertStringIncludes(repair, "RECOVERY_BELOW_BASELINE");
  // The same for a reasoning step's evidence id.
  const step = answer({
    reasoning_chain: [{ step: "a", value: "b", evidence_id: "MADE_UP_CODE" }],
  });
  const second = await run((_, index) => claudeAnswer(index === 0 ? step : answer()));
  if (second.result instanceof Error) throw second.result;
  assertEquals(second.result.attempts[0].rule, "reasoning_evidence_not_permitted");
});

Deno.test("the rules tell the model how an empty value is written, with or without the optional blocks", () => {
  for (const on of [true, false]) {
    const rules = buildCoachChatGatewayPrompt(
      "q",
      rich(),
      "general",
      undefined,
      undefined,
      on ? { sections: [], closed: false } : undefined,
      on,
      on,
    ).system.map((part) => part.type === "text" ? part.text : "").join("");
    assertStringIncludes(rules, "# The shape of your JSON");
    assertStringIncludes(rules, "There is no null and no missing key");
    assertStringIncludes(rules, 'evidence_id ""');
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
  assertEquals(result.model, "deterministic-safety-v1");
  assertEquals(result.answer.safety_state, "limited");
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
  // (128,000 + 25,500) / 1.5 = 102,333 prompt tokens written plus 4,096 output tokens, once.
  // Haiku's price card changes at 100,000 prompt tokens, so its ceiling steps up here (it is
  // above that line with the contributors anyway: the registry's worst case is about 0.096).
  assertEquals(haikuCeiling, 0.07419875);
  assertEquals(sonnetCeiling, 0.296795);
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

// ---- the turn's deadline counts from the start of the request ---------------------------------

const hang = (sent: Sent) =>
  new Promise<Response>((_, reject) => {
    sent.signal?.addEventListener("abort", () => reject(new DOMException("", "AbortError")));
  });

/** One gateway turn whose requests answer with `respond`; reports what was sent and how long it took. */
async function timedTurn(
  respond: (sent: Sent, index: number) => Response | Promise<Response>,
  options: {
    timeoutMs: number;
    timing: Parameters<typeof generateCoachChatViaGateway>[2];
    startedAgoMs?: number;
    budget?: Parameters<typeof generateCoachChatViaGateway>[0]["budget"];
  },
) {
  let index = 0;
  const fake = fakeFetch((sent) => respond(sent, index++));
  const question = "How did my training go this week?";
  const started = performance.now();
  const logged = await captureLogs(() =>
    generateCoachChatViaGateway(
      {
        question,
        context: rich(),
        contextKind: classifyQuestion(question),
        route: routeFor("coach_chat", {
          MODEL: "claude-haiku-5-5",
          MAX_OUTPUT_TOKENS: "4096",
          TIMEOUT_MS: String(options.timeoutMs),
        }),
        consentVendor: "anthropic",
        budget: options.budget,
        requestStartedAt: Date.now() - (options.startedAgoMs ?? 0),
      },
      { fetch: fake.fetch },
      options.timing,
    ).catch((error) => error)
  );
  return {
    result: logged.result as Awaited<ReturnType<typeof generateCoachChatViaGateway>> | Error,
    sent: fake.sent,
    elapsed: performance.now() - started,
  };
}

Deno.test("slow work before the gateway shortens the model's time: the request deadline counts from the request's start", async () => {
  const timing = {
    totalDeadlineMs: 60_000,
    requestDeadlineMs: 2_000,
    initialAttemptMs: 28_000,
    repairAttemptMs: 600,
  };
  // The route would wait 5 s; 1.2 s of the request's 2 s are gone, so the call ends at about 0.8 s.
  const slow = await timedTurn(hang, { timeoutMs: 5_000, timing, startedAgoMs: 1_200 });
  assert(slow.result instanceof CoachChatUnavailableError);
  assertEquals(slow.result.failureReason, "provider_timeout");
  assert(slow.elapsed >= 600 && slow.elapsed < 1_500, `waited ${slow.elapsed} ms`);
  // Without slow work the same turn waits the request deadline, not the route's 5 s.
  const fast = await timedTurn(hang, { timeoutMs: 5_000, timing });
  assert(fast.elapsed >= 1_800 && fast.elapsed < 3_000, `waited ${fast.elapsed} ms`);
  // Without a request deadline in the timing, the gateway's own total applies, as before.
  const unbounded = await timedTurn(hang, {
    timeoutMs: 1_000,
    timing: { ...timing, requestDeadlineMs: undefined },
    startedAgoMs: 60_000,
  });
  assert(unbounded.elapsed >= 900 && unbounded.elapsed < 2_000, `waited ${unbounded.elapsed} ms`);
  assertEquals(coachChatTiming.requestDeadlineMs, 38_000);
});

Deno.test("a slow start to the request leaves no retry that could not finish, and does not cut the first call short for one", async () => {
  // Retry needs 500 ms; the first attempt keeps at least twice that before it leaves any room.
  const timing = {
    totalDeadlineMs: 60_000,
    requestDeadlineMs: 2_400,
    initialAttemptMs: 28_000,
    repairAttemptMs: 600,
    initialRetryMinMs: 500,
  };
  const ledger = () => {
    const reserved: string[] = [];
    return {
      reserved,
      budget: {
        reserveAttempt: (_: number, kind: string) => {
          reserved.push(kind);
          return Promise.resolve(true);
        },
        inFlight: () => {},
      },
    };
  };
  // Fresh request: 2.4 s left, the retry is possible, so it is sent and has its own place.
  const fresh = ledger();
  const first = await timedTurn(hang, { timeoutMs: 1_000, timing, budget: fresh.budget });
  assertEquals(first.sent.length, 2);
  assertEquals(fresh.reserved, ["initial"]);
  // 1 s already used: the first call takes its full 1 s, then 0.4 s is left, under the retry's 0.5 s.
  const late = ledger();
  const second = await timedTurn(hang, {
    timeoutMs: 1_000,
    timing,
    startedAgoMs: 1_000,
    budget: late.budget,
  });
  assert(second.result instanceof CoachChatUnavailableError);
  assertEquals(second.sent.length, 1);
  assertEquals(late.reserved, []);
  assert(second.elapsed >= 900 && second.elapsed < 1_400, `waited ${second.elapsed} ms`);
});

Deno.test("a repair that would get less than half its time is not sent and holds no place", async () => {
  const reserved: string[] = [];
  const budget = {
    reserveAttempt: (_: number, kind: string) => {
      reserved.push(kind);
      return Promise.resolve(true);
    },
    inFlight: () => {},
  };
  const bad = () => claudeAnswer("not json", { output_tokens: 20 });
  // The first answer arrives with 0.4 s left; a repair needs 0.5 s (half of repairAttemptMs).
  const timing = {
    totalDeadlineMs: 60_000,
    requestDeadlineMs: 2_000,
    initialAttemptMs: 28_000,
    repairAttemptMs: 1_000,
  };
  const { result, sent } = await timedTurn(bad, {
    timeoutMs: 5_000,
    timing,
    startedAgoMs: 1_600,
    budget,
  });
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(sent.length, 1);
  assertEquals(reserved, []);
  assertEquals(result.metadata.repairSkipped, "not_enough_time");
  assertEquals(result.failureReason, "provider_response_invalid");
});

Deno.test("the clock is read again after the reservation: a place that took too long sends nothing", async () => {
  const reserved: string[] = [];
  const budget = {
    reserveAttempt: async (_: number, kind: string) => {
      reserved.push(kind);
      await new Promise((resolve) => setTimeout(resolve, 700));
      return true;
    },
    inFlight: () => {},
  };
  const bad = () => claudeAnswer("not json", { output_tokens: 20 });
  // 1 s is left for the repair, which needs 0.5 s; the reservation uses 0.7 s of it.
  const timing = {
    totalDeadlineMs: 60_000,
    requestDeadlineMs: 1_100,
    initialAttemptMs: 28_000,
    repairAttemptMs: 1_000,
  };
  const { result, sent } = await timedTurn(bad, { timeoutMs: 5_000, timing, budget });
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(reserved, ["repair"]);
  assertEquals(sent.length, 1);
  assertEquals(result.metadata.repairSkipped, "not_enough_time");
});

Deno.test('the gateway\'s athlete file asks for "" where the legacy file says null', () => {
  const gateway = buildCoachChatGatewayPrompt("q", rich(), "general").messages[0].content
    .map((part) => part.type === "text" ? part.text : "").join("\n");
  const system = buildCoachChatGatewayPrompt("q", rich(), "general").system
    .map((part) => part.type === "text" ? part.text : "").join("");
  assertStringIncludes(
    gateway,
    'A reasoning evidence_id must be one listed code or "" when it cites none.',
  );
  assertStringIncludes(system, 'evidence_id must be one permitted code or "" when it cites none');
  assert(!gateway.includes("code or null") && !system.includes("code or null"));
  assertStringIncludes(formatContextAsMarkdown(rich(), 90_000), "listed code or null.");
});

Deno.test("a repair reserves its own worst case before it is sent; a refused place sends nothing", async () => {
  const reserved: number[] = [];
  const budget = (accept: boolean) => ({
    reserveAttempt: (usd: number) => {
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

// ---- proposals (A8) ---------------------------------------------------------------------------

// What the model writes (a list of one item, its fields as name/value pairs) and what the proposal
// engine's parser reads.
const modelIntent = [{
  kind: "nutrition_targets",
  reason: "plateau",
  note: "",
  params: [{ name: "direction", value: "lower" }],
}];
const intent = {
  kind: "nutrition_targets",
  reason: "plateau",
  direction: "lower",
};

Deno.test("proposals are offered only when asked for, in the rules; the schema always has the key", () => {
  const schema = coachChatGatewaySchema();
  assert("proposal_intent" in schema.properties);
  assert(schema.required.includes("proposal_intent"), "the key is required: empty means none");
  const prompt = (proposals: boolean) =>
    buildCoachChatGatewayPrompt(
      "Take a diet break",
      rich(),
      "general",
      undefined,
      undefined,
      undefined,
      proposals,
    ).system.map((part) => part.type === "text" ? part.text : "").join("");
  assertStringIncludes(prompt(true), "# Proposing a change");
  assertStringIncludes(prompt(true), "proposal you can approve");
  assert(!prompt(false).includes("# Proposing a change"));
  // A deload is one week whatever length is asked for (A8 builder, standard/deload.ts); the tool text says so.
  assertStringIncludes(prompt(true), "A deload is always one week");
  assert(
    !prompt(true).includes("weeks (1 to 8) and exactly one of level"),
    "no longer implies any length",
  );
});

// Coach simulation 2026-10-31: "change my plan so the bench moves" became a training_schedule with
// the plan's own week (no_change). The rules now say which kind changes what the plan trains.
Deno.test("the proposal rules say which kind changes what the plan trains", () => {
  const rules = buildCoachChatGatewayPrompt(
    "Change my plan so the bench moves",
    rich(),
    "general",
    undefined,
    undefined,
    undefined,
    true,
  ).system.map((part) => part.type === "text" ? part.text : "").join("");
  assertStringIncludes(rules, "the plan's own week is refused");
  assertStringIncludes(rules, "Use focus for a stalled lift, more strength or size.");
});

Deno.test("the model's intent is handed on in the engine's shape and is not part of the stored answer", async () => {
  const fake = fakeFetch(() => claudeAnswer(answer({ proposal_intent: modelIntent })));
  const generation = await generateCoachChatViaGateway({
    question: "Lower my calories a little",
    context: rich(),
    contextKind: "general",
    route: haiku(),
    consentVendor: "anthropic",
    proposals: true,
  }, { fetch: fake.fetch });
  assertEquals(generation.proposalIntent, intent);
  assertEquals("proposal_intent" in generation.answer, false);
});

Deno.test("without proposals an intent is dropped, and the answer needs no repair", async () => {
  const { result, sent } = await run(() => claudeAnswer(answer({ proposal_intent: modelIntent })));
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 1);
  assertEquals(result.proposalIntent, undefined);
  assertEquals("proposal_intent" in result.answer, false);
});

Deno.test("an empty proposal_intent list is no intent; a malformed one reaches the parser as invalid", async () => {
  const generate = async (proposalIntent: unknown) => {
    const fake = fakeFetch(() => claudeAnswer(answer({ proposal_intent: proposalIntent })));
    return await generateCoachChatViaGateway({
      question: "Lower my calories a little",
      context: rich(),
      contextKind: "general",
      route: haiku(),
      consentVendor: "anthropic",
      proposals: true,
    }, { fetch: fake.fetch });
  };
  assertEquals((await generate([])).proposalIntent, undefined);
  // Two items are not "one change at a time": null is refused by the parser, never guessed at.
  assertEquals((await generate([...modelIntent, ...modelIntent])).proposalIntent, null);
});

Deno.test("an intent survives a lookup round and is dropped from an interim answer", async () => {
  const lookups = () =>
    Promise.resolve({ text: "Lookup: weights\n2026-10-01 80 kg", grounds: ["80 kg"], counts: [] });
  const asked = {
    ...JSON.parse(answer({ proposal_intent: modelIntent, answer: "Checking your weights." })),
    data_requests: [{ lookup: "body", from: "2026-10-01", to: "2026-10-10", filter: "" }],
  };
  const fake = fakeFetch((_) =>
    claudeAnswer(
      JSON.stringify(
        fake.sent.length === 1 ? asked : JSON.parse(answer({ proposal_intent: modelIntent })),
      ),
    )
  );
  const generation = await generateCoachChatViaGateway({
    question: "How has my weight moved, and lower my calories",
    context: rich(),
    contextKind: "general",
    route: haiku(),
    consentVendor: "anthropic",
    proposals: true,
    lookups: lookups as never,
  }, { fetch: fake.fetch });
  assertEquals(fake.sent.length, 2);
  assertEquals(generation.proposalIntent, intent);
});

// ---- the library (E3) ---------------------------------------------------------------------

const volumeChunk = {
  sourceId: "schoenfeld_2017_weekly_volume",
  title: "Weekly volume",
  year: 2017 as number | null,
  header: "Source: Schoenfeld et al. 2017, Weekly volume. Section: Results.",
  body:
    "Ten or more sets per muscle per week gave more growth than fewer. Adults should aim for 150 minutes of moderate activity a week.",
};

async function withLibrary(question: string, rows = [volumeChunk]) {
  return await renderCoachContext([
    createLibraryContributor({
      embed: () => () => Promise.resolve([0.1, 0.2]),
      search: () => Promise.resolve(rows),
    }),
  ], { userId: "athlete-1", question, localDate: "2026-10-18" });
}

const libraryEvidence = (code: string) => ({
  code,
  label: "Schoenfeld et al. 2017, weekly volume",
  source: "library",
});

Deno.test("library prompt: the excerpts follow the cached block and the rules say how to cite", async () => {
  const contributions = await withLibrary("How many sets per week?");
  const prompt = buildCoachChatGatewayPrompt(
    "How many sets per week?",
    rich(),
    "general",
    contributions,
  );
  const [cached, turn, question] = prompt.messages[0].content.map((part) =>
    part.type === "text" ? part.text : ""
  );
  assert(!cached.includes('source="library"'), "retrieved text never joins the cached prefix");
  assertStringIncludes(turn, '<reference_data source="library">');
  assertStringIncludes(turn, "[source: schoenfeld_2017_weekly_volume]");
  assertEquals(question, "User's message:\nHow many sets per week?");
  const rules = prompt.system[0].type === "text" ? prompt.system[0].text : "";
  assertStringIncludes(rules, "# Using the research library");
  assertStringIncludes(rules, 'source "library"');
});

Deno.test("the gateway schema takes any evidence code as a string; the parser checks it", () => {
  const schema = coachChatGatewaySchema();
  const item = schema.properties.evidence.items as unknown as {
    properties: { code: { type: string; enum?: string[] }; source: { enum: string[] } };
  };
  assertEquals(item.properties.code, { type: "string" });
  assertEquals(item.properties.source.enum, [
    "feature_snapshot",
    "policy_evaluation",
    "coach_context",
    "library",
  ]);
});

Deno.test("a reply that cites a source it was shown is accepted with its evidence", async () => {
  const contributions = await withLibrary("How many sets per week?");
  const good = answer({
    answer: "Ten or more weekly sets per muscle is where the research points.",
    evidence: [libraryEvidence("schoenfeld_2017_weekly_volume")],
  });
  const { result, sent } = await run(() => claudeAnswer(good), {
    question: "How many sets per week?",
    contributions,
  });
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 1);
  // The label is the retrieved source's title and year, whatever the model wrote.
  assertEquals(result.answer.evidence, [{
    ...libraryEvidence("schoenfeld_2017_weekly_volume"),
    label: "Weekly volume (2017)",
  }]);
});

Deno.test("a citation of a source that was not shown is repaired, then answered without it", async () => {
  const contributions = await withLibrary("How many sets per week?");
  const invented = answer({
    answer: "Ten or more weekly sets per muscle is where the research points.",
    evidence: [libraryEvidence("made_up_2019_claim")],
  });
  const repaired = answer({
    answer: "Ten or more weekly sets per muscle is where the research points.",
    evidence: [libraryEvidence("schoenfeld_2017_weekly_volume")],
  });
  const { result, sent } = await run(
    (_, index) => claudeAnswer(index === 0 ? invented : repaired),
    {
      question: "How many sets per week?",
      contributions,
    },
  );
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 2);
  assertEquals(result.attempts.map((a) => [a.attempt, a.outcome, a.rule]), [
    ["initial", "invalid", "citation_not_retrieved"],
    ["repair", "valid", undefined],
  ]);
  const repairText = body(sent[1]).messages[0].content.at(-1)!.text;
  assertStringIncludes(repairText, "rule=citation_not_retrieved");
  assertStringIncludes(repairText, "was not shown in the library reference data");
});

Deno.test("two bad citations in a row end in the data summary path", async () => {
  const contributions = await withLibrary("How many sets per week?");
  const invented = answer({ evidence: [libraryEvidence("made_up_2019_claim")] });
  const { result } = await run(() => claudeAnswer(invented), {
    question: "How many sets per week?",
    contributions,
  });
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.metadata.initialRule, "citation_not_retrieved");
  assertEquals(result.metadata.repairRule, "citation_not_retrieved");
});

Deno.test("when retrieval found nothing no library citation is accepted", async () => {
  const none = await withLibrary("How many sets per week?", []);
  assertStringIncludes(none.volatile, libraryNoMatchText);
  assertEquals(none.shown, {});
  const citing = answer({ evidence: [libraryEvidence("schoenfeld_2017_weekly_volume")] });
  const { result, sent } = await run((_, index) => claudeAnswer(index === 0 ? citing : answer()), {
    question: "How many sets per week?",
    contributions: none,
  });
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 2);
  assertEquals(result.answer.evidence[0].code, "RECOVERY_BELOW_BASELINE");
});

Deno.test("a source id printed in the reply text must have been shown", async () => {
  const contributions = await withLibrary("How many sets per week?");
  const printed = answer({
    answer: "Ten or more weekly sets help [made_up_2019_claim].",
    evidence: [],
  });
  const { result, sent } = await run((_, index) => claudeAnswer(index === 0 ? printed : answer()), {
    question: "How many sets per week?",
    contributions,
  });
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 2);
  assertEquals(result.attempts[0].rule, "citation_not_retrieved");
});

Deno.test("a figure only an excerpt holds is accepted when the reply cites that source, and only then", async () => {
  const question = "How much activity do adults need?";
  const contributions = await withLibrary(question);
  const sentence = "Guidance for adults is about 150 minutes of moderate activity a week.";
  const cited = answer({
    answer: sentence,
    evidence: [libraryEvidence("schoenfeld_2017_weekly_volume")],
  });
  const withCitation = await run(() => claudeAnswer(cited), { question, contributions });
  if (withCitation.result instanceof Error) throw withCitation.result;
  assertEquals(withCitation.sent.length, 1);
  // The excerpt was shown, but the reply does not cite it: the figure is not grounded.
  const uncited = answer({ answer: sentence });
  const shownNotCited = await run(() => claudeAnswer(uncited), { question, contributions });
  assert(shownNotCited.result instanceof CoachChatUnavailableError);
  assertEquals(shownNotCited.result.metadata.initialRule, "numbers_not_grounded");
  // No excerpt at all.
  const without = await run(() => claudeAnswer(uncited), { question });
  assert(without.result instanceof CoachChatUnavailableError);
  assertEquals(without.result.metadata.initialRule, "numbers_not_grounded");
});

Deno.test("a library figure stated as the athlete's own target is refused even when cited", async () => {
  const question = "How much activity do I need?";
  const contributions = await withLibrary(question);
  const target = answer({
    answer: "Your activity target is 150 minutes of moderate activity a week.",
    evidence: [libraryEvidence("schoenfeld_2017_weekly_volume")],
  });
  const guidance = answer({
    answer: "Guidance for adults is about 150 minutes of moderate activity a week.",
    evidence: [libraryEvidence("schoenfeld_2017_weekly_volume")],
  });
  const { result, sent } = await run(
    (_, index) => claudeAnswer(index === 0 ? target : guidance),
    { question, contributions },
  );
  if (result instanceof Error) throw result;
  assertEquals(result.attempts.map((a) => [a.outcome, a.rule]), [
    ["invalid", "numbers_not_grounded"],
    ["valid", undefined],
  ]);
  assertEquals(sent.length, 2);
});

// ---- fact suggestions (A10 part 2) -----------------------------------------------------------

const suggestion = {
  action: "add",
  kind: "equipment",
  subject: "kettlebells",
  statement: "Has kettlebells at home",
  fact_id: "",
};

Deno.test("fact suggestions are offered only when asked for, in the rules; the schema always has the key", () => {
  const schema = coachChatGatewaySchema();
  assert("fact_suggestions" in schema.properties);
  assert(schema.required.includes("fact_suggestions"), "the key is required: empty means none");
  const prompt = (on: boolean) =>
    buildCoachChatGatewayPrompt(
      "I bought a kettlebell",
      rich(),
      "general",
      undefined,
      undefined,
      undefined,
      true,
      on,
    ).system.map((part) => part.type === "text" ? part.text : "").join("");
  assertStringIncludes(prompt(true), "# Suggesting something to remember");
  assertStringIncludes(prompt(true), "You cannot save anything about the athlete");
  assert(!prompt(false).includes("# Suggesting something to remember"));
});

Deno.test("the model's suggestions are handed on as written and are not part of the stored answer", async () => {
  const fake = fakeFetch(() => claudeAnswer(answer({ fact_suggestions: [suggestion] })));
  const generation = await generateCoachChatViaGateway({
    question: "I bought a kettlebell",
    context: rich(),
    contextKind: "general",
    route: haiku(),
    consentVendor: "anthropic",
    factSuggestions: true,
  }, { fetch: fake.fetch });
  assertEquals(generation.factSuggestions, [suggestion]);
  assertEquals("fact_suggestions" in generation.answer, false);
  assertEquals(generation.proposalIntent, undefined);
});

Deno.test("a conversation that is not remembered drops the suggestions without a repair", async () => {
  const { result, sent } = await run(() =>
    claudeAnswer(answer({ fact_suggestions: [suggestion] }))
  );
  if (result instanceof Error) throw result;
  assertEquals(sent.length, 1);
  assertEquals(result.factSuggestions, undefined);
  assertEquals("fact_suggestions" in result.answer, false);
});

Deno.test("an empty fact_suggestions list is no suggestion", async () => {
  const fake = fakeFetch(() => claudeAnswer(answer()));
  const generation = await generateCoachChatViaGateway({
    question: "I bought a kettlebell",
    context: rich(),
    contextKind: "general",
    route: haiku(),
    consentVendor: "anthropic",
    factSuggestions: true,
  }, { fetch: fake.fetch });
  assertEquals(generation.factSuggestions, undefined);
});

Deno.test("a proposal intent and fact suggestions travel together, each handed on separately", async () => {
  const fake = fakeFetch(() =>
    claudeAnswer(answer({ proposal_intent: modelIntent, fact_suggestions: [suggestion] }))
  );
  const generation = await generateCoachChatViaGateway({
    question: "Lower my calories, I bought a kettlebell",
    context: rich(),
    contextKind: "general",
    route: haiku(),
    consentVendor: "anthropic",
    proposals: true,
    factSuggestions: true,
  }, { fetch: fake.fetch });
  assertEquals(generation.proposalIntent, intent);
  assertEquals(generation.factSuggestions, [suggestion]);
});
