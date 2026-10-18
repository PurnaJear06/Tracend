// A reply that still fails only cuttable rules after its repair is cut, not replaced by the data
// summary (AI_SAFETY_SPEC §12, "Cutting a reply"): the sentences with a figure that is not in the
// athlete's data, a source Coach was not shown, or a repeat of the previous reply go; what is left
// must pass every check again and still be an answer. Rules that are about safety are never cut.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { captureLogs, claudeMessage, fakeFetch, jsonResponse, routeFor } from "../ai/fakes.ts";
import { ownerContext } from "../coach_safety/fixtures.ts";
import { type CoachContributions, noCoachContributions } from "../coach_context/host.ts";
import { generateCoachChatViaGateway } from "./coach_chat_provider_gateway.ts";
import { CoachChatUnavailableError } from "./coach_chat_provider.ts";

const route = () =>
  routeFor("coach_chat", {
    MODEL: "claude-haiku-5-5",
    MAX_OUTPUT_TOKENS: "4096",
    EVALUATED: "true",
  });

type Reply = Readonly<{
  answer: string;
  evidence?: readonly unknown[];
  suggested_follow_ups?: readonly string[];
  missing_data?: readonly string[];
}>;

const claude = (reply: Reply) =>
  jsonResponse(claudeMessage({
    content: [{
      type: "text",
      text: JSON.stringify({
        data_requests: [],
        proposal_intent: [],
        fact_suggestions: [],
        evidence: [],
        missing_data: [],
        safety_state: "allowed",
        suggested_follow_ups: [],
        reasoning_chain: [],
        ...reply,
      }),
    }],
  }));

async function run(
  answers: readonly Reply[],
  options: {
    question?: string;
    context?: Record<string, unknown>;
    contributions?: CoachContributions;
    refuseRepair?: boolean;
  } = {},
) {
  let index = 0;
  const fake = fakeFetch(() => claude(answers[Math.min(index++, answers.length - 1)]));
  const logged = await captureLogs(async () => {
    try {
      return await generateCoachChatViaGateway({
        question: options.question ?? "Plan my travel week.",
        context: options.context ?? ownerContext(),
        contextKind: "general",
        route: route(),
        consentVendor: "anthropic",
        contributions: options.contributions,
        ...(options.refuseRepair
          ? { budget: { reserveAttempt: () => Promise.resolve(false), inFlight: () => {} } }
          : {}),
      }, { fetch: fake.fetch });
    } catch (error) {
      return error as CoachChatUnavailableError;
    }
  });
  return { result: logged.result, sent: fake.sent.length };
}

const travelPlan = [
  "Here is a travel-week plan with minimal equipment:",
  "- Day 1: 30 min brisk walk, then 3 x 12 push-ups.",
  "- Day 2: Hotel gym, goblet squat 24 kg x 10 and row 30 kg x 10.",
  "- Day 3: 20 min easy jog and 10 min of mobility.",
  "- Day 4: Rest, with 10 min stretching.",
  "- Day 5: Dumbbell press 22 kg x 10, then a 30 min walk.",
  "Keep your protein steady and sleep well.",
].join("\n");

Deno.test("a plan the athlete asked for keeps its answer when only its loads are not in the data", async () => {
  const { result, sent } = await run([{ answer: travelPlan }]);
  if (result instanceof Error) throw result;
  assertEquals(sent, 2);
  assertEquals(result.attempts.map((attempt) => [attempt.outcome, attempt.rule]), [
    ["invalid", "numbers_not_grounded"],
    ["invalid", "numbers_not_grounded"],
  ]);
  assertEquals(result.cuts, ["numbers_stripped"]);
  const text = result.answer.answer;
  assertStringIncludes(text, "30 min brisk walk");
  assertStringIncludes(text, "Keep your protein steady");
  assert(!/\b(?:24|30|22) kg\b/.test(text), text);
  assertEquals(result.answer.missing_data, [
    "Left out lines with figures that are not in your data.",
  ]);
});

Deno.test("too little left after the cut keeps the data summary", async () => {
  const { result } = await run([{
    answer: "Day 2: squat 24 kg x 10. Day 3: row 30 kg x 10. Day 4: press 22 kg x 10.",
  }]);
  assert(result instanceof CoachChatUnavailableError);
  assertEquals(result.metadata.repairRule, "numbers_not_grounded");
});

Deno.test("a rule about safety is never cut away", async () => {
  for (
    const answer of [
      "Keep your protein steady and sleep well. Eat 1,200 kcal a day while you travel and walk 30 min after dinner.",
      "Keep your protein steady and sleep well. At this pace you will weigh 66.5 kg in 12 weeks, so keep going.",
      "Keep your protein steady and sleep well. I've updated your plan for the trip, 24 kg goblet squats.",
    ]
  ) {
    const { result } = await run([{ answer }]);
    assert(result instanceof CoachChatUnavailableError, answer);
  }
});

const previous = ownerContext({
  recent_messages: [
    { role: "user", content: "How is my protein?" },
    {
      role: "assistant",
      content:
        "You are logging protein on some days. Want me to suggest two easy ways to close the protein gap?",
    },
  ],
});

const repeating: Reply = {
  answer:
    "Your sleep looks steady this week and your recovery is in range, so keep the same routine. Want me to suggest two simple ways to close the protein gap?",
};

Deno.test("a repeated closing question is repaired once, then cut", async () => {
  const { result, sent } = await run([repeating], {
    question: "What about my sleep?",
    context: previous,
  });
  if (result instanceof Error) throw result;
  assertEquals(sent, 2);
  assertEquals(result.attempts.map((attempt) => attempt.rule), [
    "repeats_previous_turn",
    "repeats_previous_turn",
  ]);
  assertEquals(result.cuts, ["closing_question_stripped"]);
  assertEquals(
    result.answer.answer,
    "Your sleep looks steady this week and your recovery is in range, so keep the same routine.",
  );
  assertEquals(result.answer.missing_data, []);
});

Deno.test("a repair that fixes the repeat is used as it is", async () => {
  const { result } = await run([repeating, {
    answer: "Your sleep looks steady this week. How did you feel on waking today?",
  }], { question: "What about my sleep?", context: previous });
  if (result instanceof Error) throw result;
  assertEquals(result.cuts, undefined);
  assertEquals(result.answer.answer.endsWith("waking today?"), true);
});

Deno.test("with no time or budget for a repair the repeated closing question is cut", async () => {
  const { result, sent } = await run([repeating], {
    question: "What about my sleep?",
    context: previous,
    refuseRepair: true,
  });
  if (result instanceof Error) throw result;
  assertEquals(sent, 1);
  assertEquals(result.cuts, ["closing_question_stripped"]);
  assert(!result.answer.answer.includes("?"));
});

Deno.test("asking the same thing again gets the same answer again", async () => {
  const context = ownerContext({
    recent_messages: [
      { role: "user", content: "How can I close my protein gap?" },
      {
        role: "assistant",
        content: "Add a shake. Want me to suggest two easy ways to close the protein gap?",
      },
    ],
  });
  const { result, sent } = await run([{
    answer: "Add a shake. Want me to suggest two easy ways to close the protein gap?",
  }], { question: "How can I close my protein gap?", context });
  if (result instanceof Error) throw result;
  assertEquals(sent, 1);
});

const maughan = "maughan_2018_ioc_supplements";
const shownSources: CoachContributions = {
  ...noCoachContributions,
  texts: { library: `[source: ${maughan}] Creatine\nCreatine at 3 to 5 g a day is well studied.` },
  shown: {
    [maughan]: {
      label: "IOC consensus statement: dietary supplements and the high-performance athlete (2018)",
      text: `[source: ${maughan}] Creatine\nCreatine at 3 to 5 g a day is well studied.`,
    },
  },
};

Deno.test("a shown study named in the text is added to the evidence", async () => {
  const { result, sent } = await run([{
    answer: "Maughan 2018 found creatine at 3 to 5 g a day is well studied for strength work.",
  }], { contributions: shownSources, question: "Is creatine worth it?" });
  if (result instanceof Error) throw result;
  assertEquals(sent, 1);
  assertEquals(result.answer.evidence, [{
    code: maughan,
    label: "IOC consensus statement: dietary supplements and the high-performance athlete (2018)",
    source: "library",
  }]);
});

Deno.test("a study that was not shown is repaired, and cut when the repair repeats it", async () => {
  const unshown = {
    answer:
      "Creatine is one of the better studied supplements. Kreider 2017 found it helps strength work. Ask your doctor if you have kidney problems.",
  };
  const repaired = await run([unshown, {
    answer:
      "Creatine is one of the better studied supplements. Ask your doctor if you have kidney problems.",
  }], { contributions: shownSources, question: "Is creatine worth it?" });
  if (repaired.result instanceof Error) throw repaired.result;
  assertEquals(repaired.result.attempts.map((attempt) => attempt.rule), [
    "citation_not_retrieved",
    undefined,
  ]);
  const cut = await run([unshown], {
    contributions: shownSources,
    question: "Is creatine worth it?",
  });
  if (cut.result instanceof Error) throw cut.result;
  assertEquals(cut.result.cuts, ["study_stripped"]);
  assert(!cut.result.answer.answer.includes("Kreider"));
  assertStringIncludes(cut.result.answer.answer, "Ask your doctor");
});
