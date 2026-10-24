import { assert, assertAlmostEquals, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { librarySources } from "../../library/index.ts";
import { isFollowUp, libraryRetrievalQuery } from "../_shared/library/query.ts";
import { isPlanExplanationQuestion, type PlanFacts } from "../_shared/library/plan_explanation.ts";
import holdoutFile from "./library_questions_holdout.json" with { type: "json" };
import planFile from "./library_questions_plan.json" with { type: "json" };
import questionFile from "./library_questions.json" with { type: "json" };
import {
  floorGrid,
  keysPassing,
  keywordGrid,
  keywordKeysPassing,
  type LibraryQuestion,
  percentile,
  questionKind,
  renderKeywordSweep,
  renderSweep,
  renderTable,
  scoreQuestion,
  summarise,
  summariseKind,
  summariseNoAnswer,
  sweepFloors,
  sweepKeywordFloors,
  topSources,
} from "./library_eval_metrics.ts";

const calibration = questionFile.questions as LibraryQuestion[];
const holdout = holdoutFile.questions as LibraryQuestion[];
// Every check on a question applies to both files: the hold-out set is only useful if it is as
// well formed as the one the thresholds are chosen on.
const questions = [...calibration, ...holdout];
const ofKind = (kind: string, set: readonly LibraryQuestion[] = questions) =>
  set.filter((question) => questionKind(question) === kind);

Deno.test("the question sets cover the whole library with every kind of question", () => {
  assert(ofKind("single").length >= 100, `${ofKind("single").length} single-topic`);
  assert(ofKind("multi_source").length >= 25, `${ofKind("multi_source").length} multi-source`);
  assert(ofKind("no_answer").length >= 30, `${ofKind("no_answer").length} no-answer`);
  assert(ofKind("follow_up").length >= 12, `${ofKind("follow_up").length} follow-up`);
  assert(
    questions.filter((question) => question.style === "colloquial").length >= 25,
    "colloquial questions",
  );
  assert(questions.length >= 240, `${questions.length} questions`);
  assertEquals(new Set(questions.map((question) => question.id)).size, questions.length);
  assertEquals(
    new Set(questions.map((question) => question.text)).size,
    questions.length,
    "a question is asked twice",
  );
  // Every source is asked about in the calibration set, so the floor is chosen with all of them.
  const asked = new Set(calibration.flatMap((question) => question.expected));
  const unasked = librarySources.map((source) => source.slug).filter((key) => !asked.has(key));
  assertEquals(unasked, [], "sources no calibration question expects");
});

Deno.test("the hold-out set is about a fifth of the questions and has every kind", () => {
  const share = holdout.length / questions.length;
  assert(share >= 0.15 && share <= 0.25, `hold-out share ${share.toFixed(2)}`);
  for (const kind of ["single", "multi_source", "follow_up", "no_answer"]) {
    assert(ofKind(kind, holdout).length >= 3, `hold-out ${kind}`);
  }
  assert(ofKind("no_answer", holdout).length >= 5);
});

Deno.test("every question is a question with known expected sources", () => {
  const keys = new Set(librarySources.map((source) => source.slug));
  for (const question of questions) {
    assert(question.text.trim().endsWith("?"), `${question.id} is not a question`);
    for (const key of question.expected) assert(keys.has(key), `${question.id}: unknown ${key}`);
    switch (questionKind(question)) {
      case "single":
        assert(question.expected.length >= 1 && question.expected.length <= 3, question.id);
        break;
      case "multi_source":
        assert(question.expected.length >= 2 && question.expected.length <= 3, question.id);
        assert(new Set(question.expected).size === question.expected.length, question.id);
        break;
      case "follow_up":
        assert(question.expected.length >= 1 && question.expected.length <= 3, question.id);
        assert((question.previous ?? []).length >= 1, `${question.id} has no earlier question`);
        break;
      case "no_answer":
        assertEquals(question.expected, [], question.id);
        break;
    }
  }
});

Deno.test("a follow-up has no topic of its own, so Coach's query borrows the earlier question's", () => {
  for (const question of ofKind("follow_up")) {
    assert(isFollowUp(question.text), `${question.id} would be searched alone`);
    const query = libraryRetrievalQuery(question.text, question.previous ?? []);
    assert(query.rewritten, question.id);
    assert(query.text.length > question.text.length, question.id);
  }
  for (const question of questions.filter((item) => questionKind(item) !== "follow_up")) {
    assertEquals(question.previous, undefined, question.id);
    assert(
      !isFollowUp(question.text),
      `${question.id} reads like a follow-up; Coach would add a topic to it`,
    );
  }
});

Deno.test("a question that names a region is asked from a region the library knows", () => {
  const known = new Set(librarySources.flatMap((source) => source.region));
  for (const question of questions.filter((item) => item.region !== undefined)) {
    assert(question.region!.includes("global"), question.id);
    for (const code of question.region!) assert(known.has(code), `${question.id}: ${code}`);
  }
  const india = questions.filter((item) =>
    item.expected.includes("icmr_nin_2024_dietary_guidelines")
  );
  assert(india.length >= 2);
  for (const question of india) assert(question.region?.includes("IN"), question.id);
});

Deno.test("questions carry no athlete data", () => {
  for (const question of questions) {
    assert(!/\d{4}-\d{2}-\d{2}|@|\b\d{2,3}\s?(kg|lb|lbs)\b/i.test(question.text), question.id);
  }
});

Deno.test("recall counts the expected sources found, ignoring duplicates and extras", () => {
  const question = { id: "q", text: "?", expected: ["a", "b"] };
  assertEquals(scoreQuestion(question, ["a", "a", "z"]).recall, 0.5);
  assertEquals(scoreQuestion(question, ["b", "a"]).missing, []);
  assertEquals(scoreQuestion(question, []).recall, 0);
});

Deno.test("the reciprocal rank is the first expected source's place in the ranked results", () => {
  const question = { id: "q", text: "?", expected: ["a", "b"] };
  assertEquals(scoreQuestion(question, ["a", "z"]).reciprocalRank, 1);
  assertEquals(scoreQuestion(question, ["z", "y", "b", "a"]).reciprocalRank, 1 / 3);
  assertEquals(scoreQuestion(question, ["z", "y"]).reciprocalRank, 0);
  assertEquals(scoreQuestion(question, []).reciprocalRank, 0);
});

Deno.test("the summary averages recall and MRR over answerable questions only", () => {
  const question = { id: "q", text: "?", expected: ["a", "b"] };
  const noAnswer = { id: "n", text: "?", kind: "no_answer" as const, expected: [] };
  const scores = [
    scoreQuestion(question, ["a", "b"]),
    scoreQuestion(question, ["z", "a"]),
    scoreQuestion(question, ["z"]),
    scoreQuestion(noAnswer, ["a"]),
  ];
  const summary = summarise(scores);
  assertEquals(summary.questions, 3);
  assertAlmostEquals(summary.meanRecall, 0.5);
  assertAlmostEquals(summary.fullRecall, 1 / 3);
  assertAlmostEquals(summary.anyRecall, 2 / 3);
  assertAlmostEquals(summary.mrr, (1 + 0.5 + 0) / 3);
  assertEquals(summariseKind(scores, "no_answer").questions, 0);
  assertEquals(
    summarise([]),
    { questions: 0, meanRecall: 0, fullRecall: 0, anyRecall: 0, mrr: 0 },
  );
});

Deno.test("the table has a row per mode and kind, and gives no-answer precision", () => {
  const single = { id: "s", text: "?", expected: ["a"] };
  const slang = { id: "c", text: "?", style: "colloquial" as const, expected: ["a"] };
  const multi = { id: "m", text: "?", kind: "multi_source" as const, expected: ["a", "b"] };
  const none = { id: "n", text: "?", kind: "no_answer" as const, expected: [] };
  const scores = [
    scoreQuestion(single, ["a"]),
    scoreQuestion(slang, []),
    scoreQuestion(multi, ["b", "a"]),
    scoreQuestion(none, ["a"]),
  ];
  const table = renderTable({ hybrid: scores, vector_only: scores.slice(0, 1) });
  assertStringIncludes(table, "recall@8");
  assertStringIncludes(table, "MRR");
  assertStringIncludes(table, "hybrid       all scored");
  assertStringIncludes(table, "hybrid       multi_source");
  assertStringIncludes(table, "hybrid       colloquial");
  assertStringIncludes(table, "hybrid       no_answer");
  assertStringIncludes(table, "shown nothing   0% (0 of 1)");
  assert(!table.includes("vector_only  multi_source"), "an empty kind has no row");
  assertEquals(topSources(["a", "a", "b", "c", "d"]), ["a", "b", "c"]);
});

Deno.test("no-answer precision is the share of questions outside the library shown nothing", () => {
  const none = { id: "n", text: "?", kind: "no_answer" as const, expected: [] };
  const single = { id: "s", text: "?", expected: ["a"] };
  const scores = [
    scoreQuestion(none, []),
    scoreQuestion(none, ["a"]),
    scoreQuestion(none, []),
    scoreQuestion(single, []),
  ];
  assertEquals(summariseNoAnswer(scores), { questions: 3, declined: 2, precision: 2 / 3 });
  assertEquals(summariseNoAnswer([scoreQuestion(single, ["a"])]), {
    questions: 0,
    declined: 0,
    precision: 1,
  });
});

Deno.test("the floor sweep scores every floor of the grid on the same hits", () => {
  const single = { id: "s", text: "?", expected: ["a", "b"] };
  const none = { id: "n", text: "?", kind: "no_answer" as const, expected: [] };
  const hits = [
    [
      { sourceKey: "a", vectorDistance: 0.12, textRank: 0 },
      { sourceKey: "b", vectorDistance: 0.17, textRank: 0 },
      { sourceKey: "z", vectorDistance: 0.3, textRank: 0.2 },
    ],
    [{ sourceKey: "z", vectorDistance: 0.16, textRank: 0.01 }],
  ];
  assertEquals(keysPassing(hits[0], { maxTopDistance: 0.13, maxVectorDistance: 0.18 }), ["a", "b"]);
  const grid = floorGrid([0.13, 0.17], [0.15, 0.18]);
  assertEquals(grid.length, 3, "a row limit nearer than the top limit is skipped");
  assert(grid.every((floor) => floor.maxVectorDistance >= floor.maxTopDistance));
  const points = sweepFloors([single, none], hits, grid);
  const at = (top: number, row: number) =>
    points.find((point) =>
      point.floor.maxTopDistance === top && point.floor.maxVectorDistance === row
    )!;
  const tight = at(0.13, 0.15);
  assertEquals([tight.meanRecall, tight.noAnswerPrecision, tight.emptyAnswerable], [0.5, 1, 0]);
  const loose = at(0.13, 0.18);
  assertEquals([loose.meanRecall, loose.mrr, loose.noAnswerPrecision], [1, 1, 1]);
  assertEquals(at(0.17, 0.18).noAnswerPrecision, 0);
  const table = renderSweep(points);
  assertStringIncludes(table, "top distance  row distance");
  assertEquals(percentile([3, 1, 2, 4], 0.5), 2);
  assertEquals(percentile([3, 1, 2, 4], 1), 4);
  assert(Number.isNaN(percentile([], 0.5)));
});

Deno.test("the word-search sweep scores each keyword floor on the same hits and their text", () => {
  const single = { id: "s", text: "?", expected: ["a"] };
  const none = { id: "n", text: "?", kind: "no_answer" as const, expected: [] };
  const hits = [
    [
      { sourceKey: "a", vectorDistance: null, textRank: 0.008, text: "Creatine and kidneys." },
      { sourceKey: "z", vectorDistance: null, textRank: 0.001, text: "Other." },
    ],
    [{ sourceKey: "z", vectorDistance: null, textRank: 0.009, text: "Safe harbour." }],
  ];
  const queries = ["creatine kidneys", "creatine kidneys"];
  const grid = keywordGrid([0.005, 0.01], [0, 0.5], [0.002]);
  assertEquals(grid.length, 4);
  const points = sweepKeywordFloors([single, none], hits, queries, grid);
  const at = (rank: number, coverage: number) =>
    points.find((point) =>
      point.floor.minTopRank === rank && point.floor.minTopCoverage === coverage
    )!;
  // Rank alone lets the unrelated strong hit through; coverage stops it.
  const rankOnly = at(0.005, 0);
  assertEquals([rankOnly.meanRecall, rankOnly.noAnswerPrecision], [1, 0]);
  const covered = at(0.005, 0.5);
  assertEquals([covered.meanRecall, covered.noAnswerPrecision, covered.emptyAnswerable], [1, 1, 0]);
  const strict = at(0.01, 0.5);
  assertEquals([strict.meanRecall, strict.noAnswerPrecision, strict.emptyAnswerable], [0, 1, 1]);
  assertEquals(
    keywordKeysPassing(hits[0], queries[0], {
      minTopRank: 0.005,
      minTopCoverage: 0.5,
      minRowRank: 0,
    }),
    ["a", "z"],
  );
  assertStringIncludes(renderKeywordSweep(points), "top rank  top coverage  row rank");
});

Deno.test("the plan-explanation questions are plan questions with plan facts and known sources", () => {
  const planQuestions = planFile.questions as unknown as (LibraryQuestion & { plan: PlanFacts })[];
  const keys = new Set(librarySources.map((source) => source.slug));
  const others = new Set(questions.map((question) => question.text));
  assert(planQuestions.length >= 10, `${planQuestions.length} plan questions`);
  assertEquals(new Set(planQuestions.map((question) => question.id)).size, planQuestions.length);
  for (const question of planQuestions) {
    assert(question.text.trim().endsWith("?"), `${question.id} is not a question`);
    assert(isPlanExplanationQuestion(question.text), `${question.id} is not a plan question`);
    assert(!others.has(question.text), `${question.id} repeats a calibration question`);
    assert(question.expected.length >= 1 && question.expected.length <= 3, question.id);
    for (const key of question.expected) assert(keys.has(key), `${question.id}: unknown ${key}`);
    // The plan topics are added to the question, and nothing is borrowed from an earlier one.
    const query = libraryRetrievalQuery(question.text, ["How much protein?"], question.plan);
    assertEquals(query.planExplanation, true, question.id);
    assert(query.text.startsWith(question.text), question.id);
    assert(!query.text.includes("protein?"), question.id);
  }
  // The facts cover each goal the plan can have, so each nutrition topic is searched.
  const goals = new Set(planQuestions.map((question) => question.plan.goal));
  for (const goal of ["fat_loss", "muscle_gain", "recomposition", "strength"]) {
    assert(goals.has(goal), goal);
  }
});
