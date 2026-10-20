// Coach chat lookups (A10), offline: the model's data requests, the server's validation and rounds,
// the budget, the guards on the final answer, and the owner's two cases.
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
import { createTrainingPlanContributor } from "../coach_context/contributors/training_plan.ts";
import { ownersCaseDate, ownersPlanPayload } from "../coach_context/contributors/plan_fixtures.ts";
import { exerciseHistoryPayload } from "../coach_lookups/lookup_fixtures.ts";
import { createLookupRunner, type LookupRpc } from "../coach_lookups/runner.ts";
import {
  coachChatGatewaySchema,
  generateCoachChatViaGateway,
} from "./coach_chat_provider_gateway.ts";
import { classifyQuestion, CoachChatUnavailableError } from "./coach_chat_provider.ts";
import type { CoachChatGeneration } from "./coach_chat_provider.ts";

const rich = () => structuredClone(evalProfiles().find((p) => p.id === "rich")!.context);
const haiku = () =>
  routeFor("coach_chat", { MODEL: "claude-haiku-5-5", MAX_OUTPUT_TOKENS: "4096" });

const final = (text: string, overrides: Record<string, unknown> = {}) =>
  JSON.stringify({
    data_requests: [],
    proposal_intent: [],
    fact_suggestions: [],
    answer: text,
    evidence: [],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: [],
    reasoning_chain: [],
    ...overrides,
  });

// A request with no filter text carries "": the schema has no optional field.
const asking = (
  requests: unknown,
  interim = "I am checking your records and have not seen them yet.",
) =>
  final(interim, {
    data_requests: Array.isArray(requests)
      ? requests.map((request) => ({ filter: "", ...request }))
      : requests,
  });

/** A response for the fake: the provider answers with a server error. */
const provider500 = "provider-500";

const benchRequest = {
  lookup: "exercise_history",
  from: "2026-08-01",
  to: "2026-09-27",
  filter: "bench",
};

const claude = (text: string) =>
  jsonResponse(claudeMessage({ content: [{ type: "text", text }] }, {
    input_tokens: 40,
    output_tokens: 120,
  }));

type Body = { system: { text: string }[]; messages: { content: { text: string }[] }[] };
const promptOf = (sent: Sent) =>
  (sent.body as unknown as Body).messages[0].content.map((part) => part.text).join("\n");
const systemOf = (sent: Sent) => (sent.body as unknown as Body).system[0].text;

function lookupRig(payload: unknown = exerciseHistoryPayload) {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  const rpc: LookupRpc = (name, params) => {
    calls.push({ name, params });
    return Promise.resolve({ data: payload, error: null });
  };
  return { calls, runner: createLookupRunner(rpc, "user-1") };
}

async function run(
  responses: readonly string[],
  options: {
    question?: string;
    context?: Record<string, unknown>;
    runner?: ReturnType<typeof lookupRig>["runner"];
    budget?: Parameters<typeof generateCoachChatViaGateway>[0]["budget"];
    contributions?: Awaited<ReturnType<typeof renderCoachContext>>;
    timing?: Parameters<typeof generateCoachChatViaGateway>[2];
    /** Answer every call after the given responses with a provider error. */
    failAfter?: boolean;
  } = {},
) {
  let index = 0;
  const fake = fakeFetch(() => {
    const at = index++;
    if (at >= responses.length && options.failAfter) return new Response("down", { status: 500 });
    const response = responses[Math.min(at, responses.length - 1)];
    return response === provider500 ? new Response("down", { status: 500 }) : claude(response);
  });
  const question = options.question ?? "How did my bench go since August?";
  const logged = await captureLogs(async () => {
    try {
      return await generateCoachChatViaGateway(
        {
          question,
          context: options.context ?? rich(),
          contextKind: classifyQuestion(question),
          route: haiku(),
          consentVendor: "anthropic",
          lookups: options.runner,
          budget: options.budget,
          contributions: options.contributions,
        },
        { fetch: fake.fetch },
        options.timing,
      );
    } catch (error) {
      return error as CoachChatUnavailableError;
    }
  });
  return {
    result: logged.result as CoachChatGeneration | CoachChatUnavailableError,
    sent: fake.sent,
  };
}

const generation = (result: CoachChatGeneration | CoachChatUnavailableError) => {
  if (result instanceof Error) throw result;
  return result;
};

Deno.test("owner's case: 'how did my bench go since August?' looks up the exercise and cites the dated rows", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([benchRequest]),
    final(
      "Since August your heaviest bench set went from 80 kg x 5 on 2026-08-04 to 85 kg x 5 on 2026-09-10.",
    ),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(sent.length, 2);
  // The athlete is bound by the server: the model named only a lookup, a range and a filter.
  assertEquals(rig.calls, [{
    name: "coach_lookup_exercise_history_v1",
    params: { p_user_id: "user-1", p_from: "2026-08-01", p_to: "2026-09-27", p_filter: "bench" },
  }]);
  assertStringIncludes(done.answer.answer, "2026-09-10");
  assertEquals(done.lookups, [{ lookup: "exercise_history", rows: 2, round: 1 }]);
  // The first call was offered the lookups; the second carries the rows after the question.
  assertStringIncludes(systemOf(sent[0]), "Looking up the athlete's records");
  assert(!promptOf(sent[0]).includes("<looked_up_data>"));
  const second = promptOf(sent[1]);
  assertStringIncludes(second, "<looked_up_data>");
  assertStringIncludes(second, "2026-08-04 Barbell bench press: heaviest set 80 kg x 5");
  assert(second.indexOf("User's message:") < second.indexOf("<looked_up_data>"));
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome]), [
    ["initial", "lookup"],
    ["lookup", "valid"],
  ]);
});

Deno.test("owner's case: train today, then 10-15 days at home: the baseline and the home options answer, and the model made no lookup", async () => {
  const rig = lookupRig();
  const contributions = await renderCoachContext([
    createTrainingPlanContributor(() => Promise.resolve(ownersPlanPayload())),
  ], { userId: "user-1", question: "x", localDate: ownersCaseDate });
  const context = { ...rich(), coaching_date: ownersCaseDate };
  const { result, sent } = await run([
    final(
      "Today is **Push day**:\n- Barbell bench press, 3 x 6-8, 62.5 kg\n- Incline dumbbell press, 3 x 8-10, 24 kg\n- Cable lateral raise, 3 x 12-15\n- Cable triceps pressdown, 3 x 10-12\n\nAt home: push-ups and a dumbbell floor press for chest.",
    ),
  ], {
    question:
      "I'm training in five minutes. What should I do today, and for 10 to 15 days at home?",
    runner: rig.runner,
    context,
    contributions,
  });
  const done = generation(result);
  assertEquals(sent.length, 1);
  assertEquals(rig.calls.length, 0);
  assertEquals(done.lookups, undefined);
  const prompt = promptOf(sent[0]);
  assertStringIncludes(prompt, '<reference_data source="training_plan">');
  assertStringIncludes(prompt, "Barbell bench press: 3 x 6-8, rest 120 s, RPE 8, plan load 60 kg");
  assertStringIncludes(prompt, "Home: bodyweight");
  const system = systemOf(sent[0]);
  assertStringIncludes(system, "investigate before you answer");
  assert(!system.includes("Do not look up what the context already holds"));
});

Deno.test("a lookup the catalogue does not know never reaches the server: the output schema refuses it and the repair answers", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([{ lookup: "everything", from: "2026-08-01", to: "2026-09-27" }]),
    final("I have not checked your history, so I cannot say how the bench went."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(rig.calls.length, 0);
  assertEquals(sent.length, 2);
  // The route's output schema lists the lookup names, so the gateway refuses this answer itself.
  assertEquals(done.attempts[0].outcome, "invalid");
  assertEquals(done.attempts[0].rule, "json_syntax");
});

Deno.test("an oversized range passes the schema and is refused by the server's check before anything is read: the model gets one corrected round", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([{ ...benchRequest, from: "2025-01-01" }]),
    final("I could not check that far back."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(rig.calls.length, 0);
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome, attempt.rule]), [
    ["initial", "invalid", "lookup_request_invalid"],
    ["lookup", "valid", undefined],
  ]);
  // The second call is told why and may ask again; it is not a repair that must answer.
  assertStringIncludes(promptOf(sent[1]), "Your data_requests were refused");
  assertStringIncludes(promptOf(sent[1]), "a range is at most 400 days");
  assert(!promptOf(sent[1]).includes("No more lookups are available"));
  assert(!promptOf(sent[1]).includes("Repair instruction"));
});

Deno.test("a corrected list runs as the first round, and the turn answers from its rows", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([{ ...benchRequest, from: "2025-01-01" }]),
    asking([benchRequest]),
    final("From the rows, your bench went from 80 kg to 85 kg."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(sent.length, 3);
  assertEquals(rig.calls.length, 1);
  assertEquals(done.lookups, [{ lookup: "exercise_history", rows: 2, round: 1 }]);
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome]), [
    ["initial", "invalid"],
    ["lookup", "lookup"],
    ["lookup", "valid"],
  ]);
  // The correction used no round: both lookup rounds are still available after it.
  assertStringIncludes(promptOf(sent[2]), "<looked_up_data>");
  assert(!promptOf(sent[2]).includes("No more lookups are available"));
});

Deno.test("a malformed request (a date that is not a date, a missing filter) is corrected the same way", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([{ ...benchRequest, from: "last August" }]),
    asking([benchRequest]),
    final("From the rows, your bench went from 80 kg to 85 kg."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(rig.calls.length, 1);
  assertStringIncludes(promptOf(sent[1]), "from and to must be dates as YYYY-MM-DD");
  assertEquals(done.attempts.map((attempt) => attempt.rule), [
    "lookup_request_invalid",
    undefined,
    undefined,
  ]);
  const missing = await run([
    asking([{ ...benchRequest, filter: "" }]),
    final("I will answer without it."),
  ], { runner: rig.runner });
  assertStringIncludes(promptOf(missing.sent[1]), "a filter is required");
});

Deno.test("only one correction a turn: a second refusal goes to the repair, which must answer", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([{ ...benchRequest, from: "2025-01-01" }]),
    asking([{ ...benchRequest, from: "2025-01-01" }]),
    final("I could not check that far back."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(rig.calls.length, 0);
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome, attempt.rule]), [
    ["initial", "invalid", "lookup_request_invalid"],
    ["lookup", "invalid", "lookup_request_invalid"],
    ["repair", "valid", undefined],
  ]);
  assertStringIncludes(promptOf(sent[2]), "no more lookups are available this turn");
  assertStringIncludes(promptOf(sent[2]), "Answer now from what you have");
});

Deno.test("a refusal in the second round is corrected once, and a refusal after that is not", async () => {
  const rig = lookupRig();
  const oversized = asking([{ ...benchRequest, from: "2025-01-01" }]);
  const { result, sent } = await run([
    oversized,
    asking([benchRequest]),
    oversized,
    final("From the rows I have, your bench went from 80 kg to 85 kg."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(sent.length, 4);
  assertEquals(rig.calls.length, 1);
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome]), [
    ["initial", "invalid"],
    ["lookup", "lookup"],
    ["lookup", "invalid"],
    ["repair", "valid"],
  ]);
});

Deno.test("a correction that cannot be sent (no budget place) leaves the refusal to the repair", async () => {
  const rig = lookupRig();
  const reserved: string[] = [];
  const { result, sent } = await run([
    asking([{ ...benchRequest, from: "2025-01-01" }]),
    final("I could not check that far back."),
  ], {
    runner: rig.runner,
    budget: {
      reserveAttempt: (_usd, kind) => {
        reserved.push(kind);
        return Promise.resolve(kind === "repair");
      },
      inFlight: () => {},
    },
  });
  const done = generation(result);
  assertEquals(reserved, ["lookup", "repair"]);
  assertEquals(sent.length, 2);
  assertStringIncludes(promptOf(sent[1]), "no more lookups are available this turn");
  assertEquals(done.attempts.map((attempt) => attempt.attempt), ["initial", "repair"]);
});

Deno.test("a correction call that fails outright leaves the refusal to the repair", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([{ ...benchRequest, from: "2025-01-01" }]),
    provider500,
    final("I could not check that far back."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(sent.length, 3);
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome]), [
    ["initial", "invalid"],
    ["lookup", "http_error"],
    ["repair", "valid"],
  ]);
});

Deno.test("no correction when too little of the turn's deadline is left: the repair path stands", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([{ ...benchRequest, from: "2025-01-01" }]),
    final("I could not check that far back."),
  ], {
    runner: rig.runner,
    timing: { totalDeadlineMs: 12_000, initialAttemptMs: 28_000, repairAttemptMs: 10_000 },
  });
  const done = generation(result);
  assertEquals(sent.length, 2);
  assertEquals(done.attempts.map((attempt) => attempt.attempt), ["initial", "repair"]);
});

Deno.test("two lookup rounds are allowed; a third request is refused and the repair must answer", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([
    asking([benchRequest]),
    asking([{ lookup: "body", from: "2026-08-01", to: "2026-09-27" }]),
    asking([{ lookup: "recovery", from: "2026-09-01", to: "2026-09-27" }]),
    final("From the rows I have, your bench went from 80 kg to 85 kg."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(sent.length, 4);
  assertEquals(rig.calls.length, 2);
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome, attempt.rule]), [
    ["initial", "lookup", undefined],
    ["lookup", "lookup", undefined],
    ["lookup", "invalid", "lookup_rounds_exceeded"],
    ["repair", "valid", undefined],
  ]);
  // After the second round the model is told no more lookups exist, and so is the repair.
  assertStringIncludes(promptOf(sent[2]), "No more lookups are available this turn.");
  assertStringIncludes(promptOf(sent[3]), "No more lookups are available this turn.");
  assertStringIncludes(promptOf(sent[3]), "<looked_up_data>");
});

Deno.test("a model that keeps asking after the repair ends in the data summary path", async () => {
  const rig = lookupRig();
  const { result } = await run([
    asking([benchRequest]),
    asking([benchRequest]),
    asking([benchRequest]),
    asking([benchRequest]),
  ], { runner: rig.runner });
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.metadata.initialRule, "lookup_rounds_exceeded");
  assertEquals(result.metadata.repairRule, "lookup_rounds_exceeded");
  assertEquals(result.metadata.lookups?.length, 2);
});

Deno.test("each extra call has its own budget place; with none, the interim sentence is the answer", async () => {
  const rig = lookupRig();
  const reserved: string[] = [];
  const { result, sent } = await run([asking([benchRequest])], {
    runner: rig.runner,
    budget: {
      reserveAttempt: (_usd, kind) => {
        reserved.push(kind);
        return Promise.resolve(false);
      },
      inFlight: () => {},
    },
  });
  const done = generation(result);
  assertEquals(reserved, ["lookup"]);
  assertEquals(sent.length, 1);
  assertEquals(done.answer.answer, "I am checking your records and have not seen them yet.");
  assertEquals(done.lookups, [{ lookup: "exercise_history", rows: 2, round: 1 }]);
});

Deno.test("budget gone and no usable interim sentence: the turn falls back, as a failed repair does", async () => {
  const rig = lookupRig();
  const { result } = await run([
    asking([benchRequest], "Your bench went up 987 kg since August."),
  ], {
    runner: rig.runner,
    budget: { reserveAttempt: () => Promise.resolve(false), inFlight: () => {} },
  });
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.metadata.repairSkipped, "reservation_refused");
});

Deno.test("a repair after a lookup reserves its own place, as a lookup round does", async () => {
  const rig = lookupRig();
  const reserved: string[] = [];
  const { result } = await run([
    asking([benchRequest]),
    final("Your bench went from 80 kg to 92 kg."),
    final("Your bench went from 80 kg to 85 kg."),
  ], {
    runner: rig.runner,
    budget: {
      reserveAttempt: (_usd, kind) => {
        reserved.push(kind);
        return Promise.resolve(true);
      },
      inFlight: () => {},
    },
  });
  generation(result);
  assertEquals(reserved, ["lookup", "repair"]);
});

Deno.test("a red flag is answered before any model call or lookup", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([asking([benchRequest])], {
    question: "I fainted at the gym yesterday, how did my bench go since August?",
    runner: rig.runner,
  });
  const done = generation(result);
  assertEquals(sent.length, 0);
  assertEquals(rig.calls.length, 0);
  assert(done.safety !== undefined);
});

Deno.test("a figure the final answer states that is neither in the rows nor in the context fails the numbers check", async () => {
  const rig = lookupRig();
  const { result } = await run([
    asking([benchRequest]),
    final("Your bench went from 80 kg to 92 kg."),
    final("Your bench went from 80 kg to 85 kg."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome, attempt.rule]), [
    ["initial", "lookup", undefined],
    ["lookup", "invalid", "numbers_not_grounded"],
    ["repair", "valid", undefined],
  ]);
  assertStringIncludes(done.answer.answer, "85 kg");
});

Deno.test("figures in the looked-up rows ground the answer", async () => {
  const rig = lookupRig();
  const { result } = await run([
    asking([benchRequest]),
    final("Your estimated one-rep max rose from 93.3 kg to 99.2 kg."),
  ], { runner: rig.runner });
  assertEquals(generation(result).attempts.at(-1)?.outcome, "valid");
});

Deno.test("without a runner the model is not offered lookups", async () => {
  const { result, sent } = await run([final("Keep the planned session.")]);
  generation(result);
  assert(!systemOf(sent[0]).includes("Looking up the athlete's records"));
});

Deno.test("the schema with lookups is one the gateway checks and Claude accepts", () => {
  const schema = coachChatGatewaySchema();
  assert(isSupportedSchema(schema));
  assert(anthropicSchema(schema) !== null);
});

Deno.test("an empty data_requests list is a final answer", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([final("Keep the planned session.", { data_requests: [] })], {
    runner: rig.runner,
  });
  generation(result);
  assertEquals(sent.length, 1);
  assertEquals(rig.calls.length, 0);
});

Deno.test("the model's own filter text grounds nothing: a figure it put in the filter is not the athlete's", async () => {
  const rig = lookupRig();
  const { result } = await run(
    [
      asking([{ ...benchRequest, filter: "bench 140 kg" }]),
      final("Your bench reached 140 kg."),
      final("Your bench reached 85 kg."),
    ],
    { runner: rig.runner },
  );
  const done = generation(result);
  assertEquals(rig.calls[0].params.p_filter, "bench 140 kg");
  assertEquals(done.attempts.map((attempt) => [attempt.attempt, attempt.outcome, attempt.rule]), [
    ["initial", "lookup", undefined],
    ["lookup", "invalid", "numbers_not_grounded"],
    ["repair", "valid", undefined],
  ]);
});

Deno.test("the period looked at is grounded, so the answer can name it", async () => {
  const rig = lookupRig();
  const { result } = await run(
    [
      asking([benchRequest]),
      final("From 2026-08-01 to 2026-09-27 your heaviest bench set went from 80 kg to 85 kg."),
    ],
    { runner: rig.runner },
  );
  assertEquals(generation(result).attempts.at(-1)?.outcome, "valid");
});

Deno.test("the interim sentence is checked only against what the model had seen when it wrote it", async () => {
  const rig = lookupRig();
  // 99.2 appears only in the looked-up rows, which the model had not seen yet.
  const { result } = await run(
    [
      asking([benchRequest], "Your estimated one-rep max is 99.2 kg, I am checking the rest."),
    ],
    {
      runner: rig.runner,
      budget: { reserveAttempt: () => Promise.resolve(false), inFlight: () => {} },
    },
  );
  assert(result instanceof CoachChatUnavailableError);
});

Deno.test("a lookup call that fails after the rows were fetched ends with the interim sentence and says what was not checked", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([asking([benchRequest])], {
    runner: rig.runner,
    failAfter: true,
  });
  const done = generation(result);
  assert(sent.length >= 2);
  assertEquals(done.answer.answer, "I am checking your records and have not seen them yet.");
  assertEquals(done.answer.missing_data, [
    "Could not check: exercise_history 2026-08-01 to 2026-09-27",
  ]);
  assertEquals(done.lookups, [{ lookup: "exercise_history", rows: 2, round: 1 }]);
});

Deno.test("a failed lookup call with no usable interim sentence falls back as before", async () => {
  const rig = lookupRig();
  const { result } = await run([asking([benchRequest], "Up 987 kg.")], {
    failAfter: true,
    runner: rig.runner,
  });
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.failureReason, "provider_http_error");
});

Deno.test("a lookup round does not start when too little of the turn's deadline is left", async () => {
  const rig = lookupRig();
  const { result, sent } = await run([asking([benchRequest])], {
    runner: rig.runner,
    timing: { totalDeadlineMs: 2_000, initialAttemptMs: 28_000, repairAttemptMs: 10_000 },
  });
  const done = generation(result);
  assertEquals(sent.length, 1);
  assertEquals(rig.calls.length, 0);
  assertEquals(done.answer.answer, "I am checking your records and have not seen them yet.");
  assertEquals(done.answer.missing_data.length, 1);
});

Deno.test("each lookup is counted with the round it ran in, so the trace can show how wide the first round was", async () => {
  const rig = lookupRig();
  const { result } = await run([
    asking([
      benchRequest,
      { lookup: "body", from: "2026-08-01", to: "2026-09-27" },
      { lookup: "recovery", from: "2026-09-01", to: "2026-09-27" },
    ]),
    asking([{ lookup: "check_ins", from: "2026-09-01", to: "2026-09-27" }]),
    final("From the rows I have, your bench went from 80 kg to 85 kg."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(rig.calls.length, 4);
  assertEquals(done.lookups?.map((count) => [count.lookup, count.round]), [
    ["exercise_history", 1],
    ["body", 1],
    ["recovery", 1],
    ["check_ins", 2],
  ]);
});

Deno.test("up to eight lookups are accepted in one round", async () => {
  const rig = lookupRig();
  const names = [
    "body",
    "recovery",
    "check_ins",
    "goals",
    "weekly_reviews",
    "workouts",
    "meals",
    "health_history",
  ];
  const { result, sent } = await run([
    asking(names.map((lookup) => ({ lookup, from: "2026-09-01", to: "2026-09-27" }))),
    final("From the rows I have, nothing stands out."),
  ], { runner: rig.runner });
  const done = generation(result);
  assertEquals(rig.calls.length, 8);
  assertEquals(done.lookups?.length, 8);
  assertStringIncludes(systemOf(sent[0]), "a round holds at most 8 requests");
  const nine = asking([...names, "past_messages"].map((lookup) => ({
    lookup,
    from: "2026-09-01",
    to: "2026-09-27",
    filter: lookup === "past_messages" ? "knee" : "",
  })));
  const refused = await run([nine, final("I will answer without it.")], { runner: rig.runner });
  assertStringIncludes(promptOf(refused.sent[1]), "at most 8 requests");
});
