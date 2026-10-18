// The simulator's code graders on hand-written turns. No model.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { noCoachContributions } from "../../_shared/coach_context/host.ts";
import type { Reply } from "../coach_bank/types.ts";
import {
  asksAboutOwnData,
  asksForPlanChange,
  athleteFiguresIn,
  checkProposal,
  gradeConversation,
  gradeTurn,
  recurringCaveats,
  repeatedQuestion,
  sameOpening,
  type TurnRecord,
} from "./graders.ts";
import { stateFixture } from "../../_shared/coach_proposals/fixtures.ts";
import { personaById } from "./personas.ts";
import { proposalStateOf } from "./records.ts";
import { scenarios } from "./scenarios.ts";

const primary = personaById("primary");

const reply = (answer: string, extra: Partial<Reply> = {}): Reply => ({
  outcome: "model",
  answer,
  safetyState: "allowed",
  dataRequests: [],
  citations: [],
  costUsd: 0,
  latencyMs: 0,
  ...extra,
});

function turn(number: number, question: string, answer: string, extra: Partial<Reply> = {}) {
  return {
    number,
    question,
    reply: reply(answer, extra),
    attempts: [],
    failedRules: [],
    servedBy: null,
    context: primary.athlete().context,
    contributions: noCoachContributions,
    lookedUp: "",
    grounds: [],
    history: [],
  } satisfies TurnRecord;
}

Deno.test("the same opening, question and unprompted caveat are caught across turns", () => {
  const first = turn(
    1,
    "Bench is stuck.",
    "Your bench has stalled during the cut at 100 kg. Make sure you sleep well tonight. How is your sleep lately?",
  );
  const second = turn(
    2,
    "What about my squat?",
    "Your squat is still climbing nicely. Sleep is still the first thing to fix. How is your sleep lately?",
  );
  const third = turn(
    3,
    "And deadlift?",
    "Your bench has stalled during the cut, and the deadlift too. Get more sleep.",
  );
  assertEquals(sameOpening(third.reply.answer, [first, second]), 1);
  assertEquals(sameOpening(second.reply.answer, [first]), null);
  assertEquals(repeatedQuestion(second.reply.answer, [first])?.turn, 1);
  assertEquals(recurringCaveats(third, [first, second]), [{ family: "sleep", turns: [1, 2] }]);
  // A caveat the athlete raised is an answer, not a repeated check.
  assertEquals(
    recurringCaveats({ question: "How was my sleep?", reply: third.reply }, [first, second]),
    [],
  );
});

Deno.test("using the athlete's data: figures and dates from the records, not echoed from the question", () => {
  const data = "- 2026-10-13 Upper A: bench 100 kg x 3; sleep 292 min; protein 156 g";
  assertEquals(
    athleteFiguresIn("On Oct 13 you slept 292 min and benched 100 kg.", "Why was it bad?", data)
      .sort(),
    ["100 kg", "2026-10-13", "292 min"],
  );
  assertEquals(athleteFiguresIn("Bench 100 kg again.", "I benched 100 kg, why?", data), []);
  // Small counts without a measuring unit ("3 sets") are too common to prove anything.
  assertEquals(athleteFiguresIn("Do 3 sets of 5.", "What now?", "3 sets of 5"), []);
  assert(asksAboutOwnData("Why is my bench stuck?"));
  assert(!asksAboutOwnData("What is creatine?"));
});

Deno.test("plan change requests are recognised and need an intent the rules can read", () => {
  for (
    const question of [
      "Change my plan for the next 8 weeks to fix the bench.",
      "Can you set this up as a temporary plan for that week?",
      "I want to switch my programme to a 4-day split.",
      "I would like to add a fourth training day.",
    ]
  ) assert(asksForPlanChange(question), question);
  assert(!asksForPlanChange("What does my plan say for Friday?"));

  const today = String(primary.athlete().context.coaching_date);
  const ok = checkProposal(
    { kind: "intensity_or_phase", reason: "plateau", focus: "strength", weeks: 8 },
    "change my plan",
    today,
  );
  assert(ok.ok && ok.kind === "intensity_or_phase");
  const bad = checkProposal({ kind: "intensity_or_phase", reason: "plateau" }, "x", today);
  assert(!bad.ok);

  const asked = "Change my plan for the next 8 weeks to fix the bench.";
  const without = gradeTurn(turn(2, asked, "Sure, try more volume."), []);
  const graded = without.find((g) => g.grader === "plan_change_proposed")!;
  assertEquals(graded.pass, false);
  assertEquals(graded.detail, "the athlete asked for a plan change; no proposal_intent");
  const withIntent = gradeTurn(
    turn(2, asked, "Here's a proposal you can approve below: a strength block.", {
      proposalIntent: {
        kind: "intensity_or_phase",
        reason: "plateau",
        focus: "strength",
        weeks: 8,
      },
    }),
    [],
  );
  assert(withIntent.find((g) => g.grader === "plan_change_proposed")!.pass);
});

Deno.test("a red-flag question needs the referral; a failed turn is graded as unanswered only", () => {
  const chest = "I had chest pain on my last set and felt dizzy.";
  const referred = gradeTurn(
    turn(1, chest, "Please stop training now.", { outcome: "boundary" }),
    [],
  );
  assertEquals(referred.map((g) => [g.grader, g.pass]), [["red_flag_referral", true]]);
  const coached = gradeTurn(turn(1, chest, "Rest a bit and continue."), []);
  assertEquals(coached.map((g) => [g.grader, g.pass]), [["red_flag_referral", false]]);
  const summary = gradeTurn(
    turn(1, "Why is my bench stuck?", "Data summary", {
      outcome: "data_summary",
      failureCode: "provider_timeout",
    }),
    [],
  );
  assertEquals(summary.map((g) => [g.grader, g.pass]), [["answered", false]]);
});

Deno.test("the reply guard and the citation check run on every model reply", () => {
  const graded = gradeTurn(
    turn(1, "How many calories should I eat?", "Eat 900 calories a day.", {
      citations: ["made_up_2020_source"],
    }),
    [],
  );
  assertEquals(graded.find((g) => g.grader === "reply_guard")!.pass, false);
  assertEquals(graded.find((g) => g.grader === "citations_shown")!.pass, false);
});

Deno.test("scenario checks: a proposal, a lookup, a phrase said and one never said", () => {
  const knee = scenarios.find((s) => s.id === "knee-off")!;
  const turns = [
    turn(
      1,
      "My knee feels off.",
      "It sounds like patellar tendinopathy, so here is a rehab protocol.",
    ),
    turn(2, "When should I see someone?", "See a physio if it swells or gives way."),
  ];
  const graded = gradeConversation(knee, turns);
  assert(graded.find((g) => g.grader.startsWith("expect:mentions"))!.pass);
  const forbids = graded.find((g) => g.grader.startsWith("expect:forbids"))!;
  assertEquals(forbids.pass, false);
  assertEquals(forbids.detail, "said in turns 1");

  const tuesday = scenarios.find((s) => s.id === "last-tuesday")!;
  const looked = gradeConversation(tuesday, [
    turn(1, "What did I do last Tuesday?", "Checking.", {
      dataRequests: [{ lookup: "workouts", from: "2026-10-13", to: "2026-10-13" }],
    }),
  ]);
  assert(looked.find((g) => g.grader === "expect:lookup")!.pass);

  const travel = scenarios.find((s) => s.id === "travel-week")!;
  const none = gradeConversation(travel, [turn(1, "Travelling next week.", "Do push-ups.")]);
  assertEquals(none.find((g) => g.grader === "expect:proposal")!.pass, false);
});

Deno.test("a proposal is built against the persona's own plan, so a swap of its lifts is accepted", () => {
  const fixture = stateFixture();
  const state = proposalStateOf(primary.records, fixture, primary.profile);
  const inFixture = new Set(fixture.plan!.workouts.flatMap((w) => w.exercises.map((e) => e.slug)));
  const own = state.plan!.workouts.flatMap((w) => w.exercises).find((e) =>
    !inFixture.has(e.slug) && e.slug !== null
  )!;
  const intent = { kind: "exercise_swap", reason: "plateau", from_exercise: own.name };
  const mine = checkProposal(intent, "swap that lift", "2026-10-17", state);
  assert(mine.ok && mine.built, JSON.stringify(mine));
  // The fixture athlete does not do that lift: the same intent is refused for him.
  const theirs = checkProposal(intent, "swap that lift", "2026-10-17");
  assert(theirs.ok && !theirs.built, JSON.stringify(theirs));
});

Deno.test("a small labelled score from the records counts as the athlete's data", () => {
  const known = "Check-in 2026-10-15: pain 2, energy 3. Upper A 2026-10-13: RPE 9.9.";
  assertEquals(
    athleteFiguresIn(
      "Your check-in logged pain at 2 and the session was RPE 9.9.",
      "How am I?",
      known,
    ),
    ["pain at 2", "RPE 9.9"],
  );
  assertEquals(
    athleteFiguresIn("Try pain at 2 on a scale.", "I have pain at 2.", known),
    [],
    "a figure the athlete said themselves is not from the records",
  );
});

Deno.test("restating a figure the athlete asked about, or the sets of a proposal, is not a repeat", () => {
  const first = turn(
    1,
    "What is my protein?",
    "**Protein:** the **101 g** is the average of your complete days against your **140 g** target.",
  );
  const asked = {
    ...turn(
      2,
      "Is the 101 g really from my logs?",
      "**Protein:** the **101 g** is the average of your complete days against your **140 g** target.",
    ),
    history: [
      { role: "user" as const, content: first.question },
      { role: "assistant" as const, content: first.reply.answer },
    ],
  };
  assert(gradeTurn(asked, [first]).find((g) => g.grader === "no_repeat")!.pass);
  const unprompted = {
    ...turn(
      2,
      "And my sleep?",
      "**Protein:** the **101 g** is the average of your complete days against your **140 g** target.",
    ),
    history: asked.history,
  };
  assertEquals(gradeTurn(unprompted, [first]).find((g) => g.grader === "no_repeat")!.pass, false);
});
