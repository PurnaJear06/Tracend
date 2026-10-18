import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  buildAdviceNote,
  buildConversationNote,
  evaluateFollowThrough,
  parseFollowThroughChecks,
  parseNotes,
  parseResolvedProposals,
  type ResolvedProposal,
  type TurnForNote,
} from "./notes.ts";
import { maxNoteCommitments, maxNoteConcerns, maxNoteTopics } from "./vocabulary.ts";

const turn = (overrides: Partial<TurnForNote> = {}): TurnForNote => ({
  question: "How should I train my chest this week?",
  localDate: "2026-10-18",
  threadId: "t1",
  remember: true,
  outcome: "answered",
  evidenceCodes: [],
  lookups: [],
  proposalKind: null,
  messageIds: ["m1", "m2"],
  ...overrides,
});

const note = (overrides: Partial<TurnForNote> = {}) => buildConversationNote(turn(overrides));

Deno.test("an answered turn becomes a small structured note linked to its messages", () => {
  const draft = note()!;
  assertEquals(draft.entryKind, "conversation");
  assertEquals(draft.threadId, "t1");
  assertEquals(draft.noteDate, "2026-10-18");
  assertEquals(draft.topics, ["training"]);
  assertEquals(draft.messageIds, ["m1", "m2"]);
  assertEquals(draft.proposalId, null);
  assertEquals(draft.advice, []);
  assertEquals(draft.summary, "Asked about training.");
});

Deno.test("nothing is noted when the chat is not remembered, a referral, or a data summary", () => {
  assertEquals(note({ remember: false }), null);
  assertEquals(note({ outcome: "referral" }), null);
  assertEquals(note({ outcome: "data_summary" }), null);
});

Deno.test("a turn that touches nothing worth noting writes no note", () => {
  assertEquals(note({ question: "hi" }), null);
  assertEquals(note({ question: "thanks, that makes sense" }), null);
  assertEquals(note({ question: "" }), null);
});

Deno.test("topics come from the athlete's words, in the fixed order", () => {
  assertEquals(note({ question: "Is my protein enough for my squat and my sleep?" })!.topics, [
    "training",
    "nutrition",
    "sleep",
  ]);
  assertEquals(note({ question: "should I take creatine?" })!.topics, ["supplements"]);
  assertEquals(note({ question: "my weight on the scale went up" })!.topics, ["weight"]);
  assertEquals(note({ question: "I have a trip next week" })!.topics, ["schedule"]);
  assertEquals(note({ question: "I only have dumbbells" })!.topics, ["equipment"]);
});

Deno.test("topics also come from the lookups the turn ran, the evidence it cited and the proposal", () => {
  assertEquals(note({ question: "how did I do?", lookups: ["meals", "body"] })!.topics, [
    "nutrition",
    "weight",
  ]);
  assertEquals(note({ question: "how did I do?", lookups: ["exercise_history"] })!.topics, [
    "training",
  ]);
  assertEquals(
    note({ question: "how did I do?", evidenceCodes: ["SLEEP_LAST_NIGHT", "RECOVERY_SCORE"] })!
      .topics,
    ["recovery", "sleep"],
  );
  assertEquals(note({ question: "ok do it", proposalKind: "training_schedule" })!.topics, [
    "plan",
    "schedule",
  ]);
  assertEquals(note({ question: "how did I do?", lookups: ["past_messages"] }), null);
});

Deno.test("topics and concerns are capped", () => {
  const all = note({
    question:
      "my sleep, protein, squat, weight, goal, plan, trip and creatine are a worry, I am tired, sore, stressed and in pain",
  })!;
  assertEquals(all.topics.length, maxNoteTopics);
  assertEquals(all.concerns.length, maxNoteConcerns);
});

Deno.test("concerns are read from a closed list", () => {
  const cases: Record<string, string> = {
    "my knee hurts when I squat": "pain",
    "I am so tired lately": "fatigue",
    "my legs are sore": "soreness",
    "I can't sleep": "poor_sleep",
    "my bench has plateaued": "plateau",
    "I'm starving all the time": "hunger",
    "I have no motivation": "low_motivation",
    "I have no time this week": "time_pressure",
    "work is stressing me, I feel stressed": "stress",
  };
  for (const [question, concern] of Object.entries(cases)) {
    assertEquals(note({ question })!.concerns.includes(concern as never), true, question);
  }
  assertEquals(note({ question: "how should I train my chest?" })!.concerns, []);
});

Deno.test("a commitment is the athlete's own words, and a training-days one can be checked", () => {
  const draft = note({ question: "OK, I will train 4 days this week." })!;
  assertEquals(draft.commitments, [{
    text: "train 4 days this week",
    kind: "train_days",
    target: 4,
  }]);
  assertStringIncludes(draft.summary, "Said they would: “train 4 days this week”.");
  const other = note({ question: "I'm going to cut out soda" })!;
  assertEquals(other.commitments, [{ text: "cut out soda", kind: "other" }]);
  assertEquals(
    note({ question: "I'll go to the gym three times a week" })!.commitments[0].target,
    3,
  );
  assertEquals(note({ question: "I will eat 2 days a week out" })!.commitments[0].kind, "other");
});

Deno.test("commitments are limited in number and length and carry no angle brackets", () => {
  const many = note({
    question: "I will try a. I will try b. I will try c. I will try d. I will try e.",
  })!;
  assertEquals(many.commitments.length, maxNoteCommitments);
  const long = note({ question: `I will ${"x".repeat(150)} <b>now</b>` })!;
  assertEquals(long.commitments[0].text.length <= 100, true);
  assertEquals(long.commitments[0].text.includes("<"), false);
});

Deno.test("the summary is built from the fields, not from the reply, and stays short", () => {
  const draft = note({
    question: "I am tired and my sleep is bad, so I will rest tomorrow",
    lookups: ["recovery"],
  })!;
  assertEquals(draft.summary.includes("Coach"), false);
  assertEquals(draft.summary.length <= 400, true);
  assertStringIncludes(draft.summary, "Asked about recovery and sleep.");
  assertStringIncludes(draft.summary, "Mentioned tiredness and poor sleep.");
});

const accepted: ResolvedProposal = {
  id: "p1",
  kind: "training_schedule",
  title: "Train 4 days a week",
  outcome: "accepted",
  answeredOn: "2026-10-12",
  daysPerWeek: 4,
  sourceMessageId: "m9",
};

Deno.test("an approved schedule becomes an advice note that can be checked against sessions", () => {
  const draft = buildAdviceNote(accepted);
  assertEquals(draft.entryKind, "advice");
  assertEquals(draft.threadId, null);
  assertEquals(draft.proposalId, "p1");
  assertEquals(draft.noteDate, "2026-10-12");
  assertEquals(draft.messageIds, ["m9"]);
  assertEquals(draft.advice, [{
    code: "training_schedule",
    summary: "Train 4 days a week",
    outcome: "accepted",
    kind: "train_days",
    target: 4,
  }]);
  assertEquals(
    draft.summary,
    "Coach proposed “Train 4 days a week”; you approved it on 2026-10-12.",
  );
  assertEquals(draft.topics, ["plan", "schedule"]);
});

Deno.test("each way a proposal ends is worded, and only an approved schedule is checkable", () => {
  const words: Record<string, string> = {
    accepted: "you approved it",
    declined: "you said not now",
    changed: "you asked for changes",
    expired: "it expired unanswered",
    undone: "you approved it, then undid it",
  };
  for (const [outcome, phrase] of Object.entries(words)) {
    const draft = buildAdviceNote({ ...accepted, outcome: outcome as never });
    assertStringIncludes(draft.summary, phrase);
    assertEquals(draft.advice[0].outcome, outcome);
    assertEquals(draft.advice[0].kind === "train_days", outcome === "accepted");
  }
  const nutrition = buildAdviceNote({
    ...accepted,
    kind: "nutrition_targets",
    title: "Lower calories",
    daysPerWeek: null,
    sourceMessageId: null,
  });
  assertEquals(nutrition.advice[0].kind, undefined);
  assertEquals(nutrition.messageIds, []);
  assertEquals(nutrition.topics, ["nutrition", "plan"]);
  assertEquals(buildAdviceNote({ ...accepted, daysPerWeek: 9 }).advice[0].kind, undefined);
});

Deno.test("follow-through: all the sessions, at least half, or less", () => {
  const check = (done: number, target = 4) =>
    evaluateFollowThrough(
      {
        noteId: "n",
        target,
        windowFrom: "2026-10-13",
        windowTo: "2026-10-19",
        sessionsCompleted: done,
      },
      "2026-10-20",
    );
  assertEquals(check(4).status, "followed");
  assertEquals(check(5).status, "followed");
  assertEquals(check(3).status, "partly");
  assertEquals(check(2).status, "partly");
  assertEquals(check(1).status, "not_followed");
  assertEquals(check(0).status, "not_followed");
  assertEquals(check(1, 2).status, "partly");
  assertEquals(check(1, 3).status, "not_followed");
  assertEquals(check(2, 3).status, "partly");
  assertEquals(check(1).detail, "1 of 4 sessions from 2026-10-13 to 2026-10-19");
  assertEquals(check(1).checkedOn, "2026-10-20");
});

Deno.test("the readers of the database answers leave out malformed rows", () => {
  assertEquals(
    parseResolvedProposals({
      proposals: [
        {
          id: "p1",
          kind: "training_schedule",
          title: "T",
          outcome: "accepted",
          answered_on: "2026-10-12",
          days_per_week: 4,
          source_message_id: "m",
        },
        { id: "p2", kind: "x", title: "T", outcome: "weird", answered_on: "2026-10-12" },
        { id: "p3", kind: "x", title: "T", outcome: "declined", answered_on: "soon" },
        null,
      ],
    }).map((proposal) => proposal.id),
    ["p1"],
  );
  assertEquals(parseResolvedProposals(null), []);
  assertEquals(
    parseFollowThroughChecks({
      checks: [
        {
          note_id: "n1",
          kind: "train_days",
          target: 4,
          window_from: "2026-10-13",
          window_to: "2026-10-19",
          sessions_completed: 2,
        },
        { note_id: "n2", kind: "train_days", target: 9, window_from: "a", window_to: "b" },
        { note_id: "n3", kind: "other", target: 3 },
      ],
    }).map((check) => check.noteId),
    ["n1"],
  );
  assertEquals(parseFollowThroughChecks(undefined), []);
  const notes = parseNotes([
    {
      id: "n1",
      entry_kind: "advice",
      note_date: "2026-10-12",
      summary: "S",
      topics: ["plan", 3],
      concerns: [],
      follow_through: { status: "partly", checked_on: "2026-10-20", detail: "2 of 4" },
    },
    { id: "n2", entry_kind: "other", note_date: "2026-10-12", summary: "S" },
    { id: "n3", entry_kind: "conversation", note_date: "2026-10-13", summary: "S" },
  ]);
  assertEquals(notes.map((n) => n.id), ["n1", "n3"]);
  assertEquals(notes[0].topics, ["plan"]);
  assertEquals(notes[0].followThrough?.status, "partly");
  assertEquals(notes[1].followThrough, null);
});
