// The simulator loop end to end with a stubbed router: the athlete, the Coach (through the real
// gateway path, lookups and guards) and the judges all answer from fakes. No network.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { CoachChatUnavailableError } from "../../_shared/providers/coach_chat_provider.ts";
import type { CoachChatGeneration } from "../../_shared/providers/coach_chat_provider.ts";
import type { Generate, GenerateInput } from "../live_model.ts";
import { routerGatewayFromEnv } from "../live_model.ts";
import { renderReport } from "./report.ts";
import { type RouterChat, routerChat } from "./router_client.ts";
import { selectConversations } from "./scenarios.ts";
import { brokenRouteTurns, simulate, type SimulationOptions } from "./simulate.ts";
import { harnessFailures } from "./verdict.ts";
import type { WireError } from "./diagnostics.ts";

const routerModels = [
  "anthropic/claude-haiku-5.5",
  "deepseek-v4-flash",
  "anthropic/claude-sonnet-5.5",
];

const completion = (content: string, model: string) =>
  new Response(
    JSON.stringify({
      model,
      choices: [{ message: { role: "assistant", content }, finish_reason: "stop" }],
      usage: { prompt_tokens: 1000, completion_tokens: 100 },
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );

// The production answer schema (coachChatGatewaySchema): every key is present, empty is [] or "".
const coachAnswer = (answer: string, extra: Record<string, unknown> = {}) =>
  JSON.stringify({
    data_requests: [],
    proposal_intent: [],
    fact_suggestions: [],
    answer,
    evidence: [],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: [],
    reasoning_chain: [],
    ...extra,
  });

type Sent = { url: string; body: Record<string, unknown> };

/** A router that plays the Coach, the athlete and the judges, and records what it was sent. */
function fakeRouter() {
  const sent: Sent[] = [];
  const fetcher = (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.endsWith("/models")) {
      return Promise.resolve(
        new Response(JSON.stringify({ data: routerModels.map((id) => ({ id })) }), { status: 200 }),
      );
    }
    const body = JSON.parse(String(init?.body));
    sent.push({ url, body });
    const messages = body.messages as { role: string; content: string }[];
    const system = messages[0].content;
    const user = messages[messages.length - 1].content;
    const model = String(body.model);
    if (system.includes("role-play")) {
      const number = Number(user.match(/This is your message (\d+)/)?.[1]);
      const message = user.includes("why the bench is stuck")
        ? number === 2
          ? "Ok, change my plan for the next 8 weeks to fix the bench."
          : "And what exactly changes in the sets?"
        : "Was my sleep bad that night?";
      return Promise.resolve(completion(JSON.stringify({ message, done: false }), model));
    }
    if (system.includes("twenty years")) {
      return Promise.resolve(completion(
        "```json\n" + JSON.stringify({
          scores: { specific: 4, correct: 4, not_generic: 2, pushback: 5, coach_like: 3 },
          problem: "Repeats the same opening.",
          better_answer: "Drop to triples at 92.5 kg for three weeks.",
        }) + "\n```",
        model,
      ));
    }
    if (system.includes("faithful")) {
      return Promise.resolve(completion(JSON.stringify({ claims: [] }), model));
    }
    // The Coach: the production gateway request in JSON mode.
    if (user.includes("<looked_up_data>")) {
      return Promise.resolve(completion(
        coachAnswer(
          "On 2026-10-13 your bench top set was 100 kg x 3 at 0 reps in reserve and you slept 292 min the night before, so the session was a fatigue day, not lost strength. Keep Tuesday's plan as it is next week.",
        ),
        model,
      ));
    }
    const question = user.slice(user.lastIndexOf("User's message:\n") + 16).split("\n")[0];
    if (/tuesday/i.test(question)) {
      return Promise.resolve(completion(
        coachAnswer("Let me check Tuesday's session.", {
          data_requests: [{
            lookup: "workouts",
            from: "2026-10-13",
            to: "2026-10-13",
            filter: "",
          }],
        }),
        model,
      ));
    }
    if (/change my plan/i.test(question)) {
      return Promise.resolve(completion(
        coachAnswer(
          "Here's a proposal you can approve below: a strength block with lower reps on the bench for eight weeks. Tracend sets the loads from your logs.",
          {
            proposal_intent: [{
              kind: "intensity_or_phase",
              reason: "plateau",
              note: "",
              params: [{ name: "focus", value: "strength" }, { name: "weeks", value: "8" }],
            }],
          },
        ),
        model,
      ));
    }
    return Promise.resolve(completion(
      coachAnswer(
        "Your bench has stalled while you cut. Sleep well and log your meals so we can see recovery.",
      ),
      model,
    ));
  };
  return { fetcher: fetcher as typeof fetch, sent };
}

const env = (values: Record<string, string>) => (name: string) => values[name];

async function setup(filter: string, maxTurns = 3, maxUsd = 5) {
  const router = fakeRouter();
  const routed = await routerGatewayFromEnv(
    env({ EVAL_BASE_URL: "https://router.example/v1", EVAL_API_KEY: "synthetic-test-key" }),
    router.fetcher,
  );
  if ("error" in routed) throw new Error(routed.error);
  const options: SimulationOptions = {
    coach: routed.generateWith,
    coachModel: routed.coachModel,
    athleteModel: "deepseek-v4-flash",
    judgeModel: "anthropic/claude-sonnet-5.5",
    chat: routerChat(routed.baseUrl, routed.apiKey, { fetcher: router.fetcher, retryDelayMs: 0 }),
    conversations: selectConversations(filter),
    maxTurns,
    maxUsd,
  };
  return { router, routed, options };
}

Deno.test("the router gateway route plays the production Coach model when the router lists it", async () => {
  const { routed } = await setup("primary/last-tuesday");
  assertEquals(routed.coachModel, "anthropic/claude-haiku-5.5");
  assert(routed.production);
  assertStringIncludes(routed.choice, "lists the production model");
});

Deno.test("a conversation: the athlete writes, the Coach looks up through the production runner, history carries over", async () => {
  const { router, options } = await setup("primary/last-tuesday");
  const result = await simulate(options);
  const [run] = result.conversations;
  assertEquals(run.ended, "planned");
  assertEquals(run.turns.length, 3);
  const [first, second] = run.turns;
  assertEquals(first.question, "What did I do last Tuesday, and why was it so bad?");
  assertEquals(first.reply.outcome, "model");
  assertEquals(first.reply.dataRequests.map((r) => r.lookup), ["workouts"]);
  // The production runner rendered the persona's records.
  assertStringIncludes(first.lookedUp, "2026-10-13 Upper A");
  assertStringIncludes(first.lookedUp, "100 kg x 3 (0 reps in reserve)");
  assert(first.grades.find((g) => g.grader === "reply_guard")!.pass, JSON.stringify(first.grades));
  assert(first.grades.find((g) => g.grader === "uses_data")!.pass);
  // Turn 2 is the athlete model's message, and coach-chat's thread holds turn 1.
  assertEquals(second.question, "Was my sleep bad that night?");
  assertEquals(second.history.map((t) => t.role), ["user", "assistant"]);
  const coachCalls = router.sent.filter((s) =>
    (s.body.messages as { content: string }[])[0].content.includes(
      "Return only valid JSON matching this schema",
    )
  );
  assert(coachCalls.length >= 3);
  // Every Coach call names the played model and none carries DeepSeek's thinking or a temperature.
  for (const call of coachCalls) {
    assertEquals(call.body.model, "anthropic/claude-haiku-5.5");
    assertEquals(call.body.thinking, undefined);
    assertEquals(call.body.temperature, undefined);
  }
  // The expert judge ran on another model and its verdict was read from a fenced block.
  assertEquals(first.expert?.scores.not_generic, 2);
  assert(router.sent.some((s) => s.body.model === "anthropic/claude-sonnet-5.5"));
  assert(result.spend.coach > 0 && result.spend.athlete > 0 && result.spend.judges > 0);
});

Deno.test("a plan change asked for becomes a proposal; repetition and scenario checks are graded", async () => {
  const { options } = await setup("primary/bench-plateau", 3);
  const [run] = (await simulate(options)).conversations;
  const asked = run.turns[1];
  assertEquals(asked.question, "Ok, change my plan for the next 8 weeks to fix the bench.");
  const proposed = asked.grades.find((g) => g.grader === "plan_change_proposed")!;
  assert(proposed.pass, proposed.detail);
  assertStringIncludes(proposed.detail!, "intensity_or_phase");
  // Turns 1 and 3 give the same reply: the opening and the caveat repeat.
  const third = run.turns[2];
  assertEquals(third.grades.find((g) => g.grader === "same_opening")!.pass, false);
  assertEquals(third.grades.find((g) => g.grader === "no_repeat")!.pass, false);
  const scenario = run.grades.find((g) => g.grader === "expect:proposal")!;
  assert(scenario.pass, scenario.detail);
  assertEquals(run.grades.find((g) => g.grader === "expect:lookup")!.pass, false);
});

Deno.test("the report names the models, ranks the problems and holds every transcript", async () => {
  const { options, routed } = await setup("primary/bench-plateau,primary/last-tuesday", 3);
  const result = await simulate(options);
  const text = renderReport(result.conversations, result.spend, result.stoppedForBudget, {
    coachModel: routed.coachModel,
    coachChoice: routed.choice,
    productionModel: "claude-haiku-5-5",
    production: routed.production,
    athleteModel: options.athleteModel,
    judgeModel: options.judgeModel,
    judgeNote: "",
    endpoint: "router.example",
    maxUsd: 5,
    maxTurns: 3,
    estimateUsd: 0.1,
    assumedPrices: [],
    preflight: [],
    errors: [],
    judgeOutputTokens: [800, 1_900],
    judgeMaxTokens: 3_000,
    sizing: "Sized to the cap so that every conversation runs: 3 athlete messages.",
    harnessFailures: [],
  });
  assertStringIncludes(text, "Coach played by `anthropic/claude-haiku-5.5`");
  assertStringIncludes(text, "used the production model");
  assertStringIncludes(text, "## Problems, ranked");
  assertStringIncludes(text, "Judge output per call (thinking included), limit 3000");
  assertStringIncludes(text, "Sized to the cap so that every conversation runs");
  assertStringIncludes(text, "primary/bench-plateau, turn 3: same_opening");
  assertStringIncludes(text, "### primary/last-tuesday");
  assertStringIncludes(text, "A 20-year coach would say: Drop to triples");
});

const generation = (answer: string): CoachChatGeneration => ({
  answer: {
    answer,
    evidence: [],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: [],
  },
  provider: "router",
  model: "stub",
  inputUnits: 0,
  outputUnits: 0,
  estimatedCostUsd: 0,
  attempts: [],
});

const stubChat: RouterChat = (request) =>
  Promise.resolve({
    ok: true,
    text: JSON.stringify({ message: "And then?", done: false }),
    model: request.model,
    tokens: { inputTokens: 10, outputTokens: 10, cacheReadTokens: 0, cacheWriteTokens: 0 },
    costUsd: 0.0001,
    finishReason: "stop",
  });

function stubOptions(
  coach: Generate,
  overrides: Partial<SimulationOptions> = {},
): SimulationOptions {
  return {
    coach: () => coach,
    coachModel: "stub-coach",
    athleteModel: "stub-athlete",
    judgeModel: null,
    chat: stubChat,
    conversations: selectConversations("primary/pushback"),
    maxTurns: 3,
    maxUsd: 5,
    ...overrides,
  };
}

Deno.test("a labelled data summary is shown to the athlete but left out of the thread, as coach-chat stores it", async () => {
  const seen: GenerateInput[] = [];
  let call = 0;
  const coach: Generate = (input) => {
    seen.push(input);
    call++;
    return call === 1
      ? Promise.reject(new CoachChatUnavailableError("router", "stub", "provider_timeout"))
      : Promise.resolve(generation("Hold the deload until Friday."));
  };
  const [run] = (await simulate(stubOptions(coach))).conversations;
  assertEquals(run.turns[0].reply.outcome, "data_summary");
  assertEquals(run.turns[0].grades.find((g) => g.grader === "answered")!.pass, false);
  assertEquals(
    (seen[1].context.recent_messages as { role: string }[]).map((m) => m.role),
    ["user"],
  );
  assertEquals(
    (seen[2].context.recent_messages as { role: string }[]).map((m) => m.role),
    ["user", "user", "assistant"],
  );
});

Deno.test("the budget cap stops new turns; a thrown error is a harness error", async () => {
  const coach: Generate = () => Promise.resolve(generation("Deload next week."));
  const capped = await simulate(stubOptions(coach, { maxUsd: 0 }));
  assert(capped.stoppedForBudget);
  assertEquals(capped.conversations[0].ended, "budget");
  assertEquals(capped.conversations[0].turns.length, 0);

  const broken = await simulate(stubOptions(coach, {
    chat: () => Promise.reject(new Error("router client bug")),
  }));
  assertEquals(broken.conversations[0].ended, "harness_error");
  assertStringIncludes(broken.conversations[0].error!, "router client bug");
  assertEquals(broken.conversations[0].turns.length, 1);
});

Deno.test("the athlete model failing ends the conversation and says why", async () => {
  const coach: Generate = () => Promise.resolve(generation("Deload next week."));
  const failing: RouterChat = () =>
    Promise.resolve({
      ok: false,
      reason: "http 503",
      costUsd: 0,
      kind: "http",
      status: 503,
      body: "upstream down",
    });
  const [run] = (await simulate(stubOptions(coach, { chat: failing }))).conversations;
  assertEquals(run.ended, "athlete_failed");
  assertStringIncludes(run.error!, "http 503");
});

Deno.test("a Coach route that only fails is logged with its status and stops the run instead of spending it", async () => {
  const options = stubOptions(
    () => Promise.reject(new CoachChatUnavailableError("router", "stub", "provider_http_error")),
    {
      conversations: selectConversations("primary/pushback"),
      maxTurns: 10,
    },
  );
  const failing = {
    ...options,
    coach: (_usage: unknown, onError: (e: WireError) => void) => {
      const generate: Generate = () => {
        onError({ status: 400, kind: "http", body: '{"error":{"type":"validation_error"}}' });
        return Promise.reject(
          new CoachChatUnavailableError("router", "stub", "provider_http_error"),
        );
      };
      return generate;
    },
  };
  const result = await simulate(failing);
  const [run] = result.conversations;
  assertEquals(run.ended, "harness_error");
  assertEquals(run.turns.length, brokenRouteTurns);
  assertStringIncludes(run.error!, "HTTP 400");
  assertEquals(result.errors.length, brokenRouteTurns);
  assertEquals(
    [result.errors[0].source, result.errors[0].status, result.errors[0].turn],
    ["coach", 400, 1],
  );
});

Deno.test("a router out of credit stops every conversation at once and the run says so", async () => {
  const noCredit = {
    status: 402,
    kind: "http" as const,
    body:
      '{"error":{"type":"payment_required","message":"Insufficient credits: your balance is 221"}}',
  };
  let coachCalls = 0;
  const options = stubOptions(() => Promise.resolve(generation("never read")), {
    conversations: selectConversations("pushback"),
    maxTurns: 3,
  });
  const result = await simulate({
    ...options,
    coach: (_usage, onError) => () => {
      coachCalls++;
      onError(noCredit);
      return Promise.reject(new CoachChatUnavailableError("router", "stub", "provider_http_error"));
    },
  });
  assert(result.conversations.length >= 3);
  // Each conversation makes its first Coach call at most; none goes on to a second turn.
  assert(coachCalls <= result.conversations.length, `${coachCalls} Coach calls`);
  assert(result.conversations.every((run) => run.turns.length <= 1));
  assert(result.conversations.some((run) => run.ended === "credits"));
  const reasons = harnessFailures(result.conversations, false, result.errors);
  assertStringIncludes(reasons.join("\n"), "ran out of credit");
  assertStringIncludes(reasons.join("\n"), "Top up the router balance");
});
