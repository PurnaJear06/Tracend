import { assert, assertAlmostEquals, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { librarySources } from "../../library/index.ts";
import { isFollowUp, libraryRetrievalQuery } from "../_shared/library/query.ts";
import questionFile from "./library_questions.json" with { type: "json" };
import {
  floorGrid,
  keysPassing,
  type LibraryQuestion,
  percentile,
  questionKind,
  renderSweep,
  renderTable,
  scoreQuestion,
  summarise,
  summariseKind,
  summariseNoAnswer,
  sweepFloors,
  topSources,
} from "./library_eval_metrics.ts";

const questions = questionFile.questions as LibraryQuestion[];
const ofKind = (kind: string) => questions.filter((question) => questionKind(question) === kind);

Deno.test("the question set holds the single-topic questions, multi-source questions and no-answer questions", () => {
  assert(ofKind("single").length >= 42, `${ofKind("single").length} single-topic`);
  assert(ofKind("multi_source").length >= 15, `${ofKind("multi_source").length} multi-source`);
  assert(ofKind("no_answer").length >= 10, `${ofKind("no_answer").length} no-answer`);
  assert(ofKind("follow_up").length >= 6, `${ofKind("follow_up").length} follow-up`);
  assertEquals(new Set(questions.map((question) => question.id)).size, questions.length);
  assertEquals(
    new Set(questions.map((question) => question.text)).size,
    questions.length,
    "a question is asked twice",
  );
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
  const multi = { id: "m", text: "?", kind: "multi_source" as const, expected: ["a", "b"] };
  const none = { id: "n", text: "?", kind: "no_answer" as const, expected: [] };
  const scores = [
    scoreQuestion(single, ["a"]),
    scoreQuestion(multi, ["b", "a"]),
    scoreQuestion(none, ["a"]),
  ];
  const table = renderTable({ hybrid: scores, vector_only: scores.slice(0, 1) });
  assertStringIncludes(table, "recall@8");
  assertStringIncludes(table, "MRR");
  assertStringIncludes(table, "hybrid       all scored");
  assertStringIncludes(table, "hybrid       multi_source");
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
  assertEquals(
    keysPassing(hits[0], { maxTopDistance: 0.13, maxVectorDistance: 0.18, strongTextRank: 0.1 }),
    ["a", "b", "z"],
  );
  const grid = floorGrid([0.13, 0.17], [0.15, 0.18], [Number.POSITIVE_INFINITY, 0.1]);
  assertEquals(grid.length, 6, "a row limit nearer than the top limit is skipped");
  assert(grid.every((floor) => floor.maxVectorDistance >= floor.maxTopDistance));
  const points = sweepFloors([single, none], hits, grid);
  const at = (top: number, row: number, rank: number) =>
    points.find((point) =>
      point.floor.maxTopDistance === top && point.floor.maxVectorDistance === row &&
      point.floor.strongTextRank === rank
    )!;
  const tight = at(0.13, 0.15, Number.POSITIVE_INFINITY);
  assertEquals([tight.meanRecall, tight.noAnswerPrecision, tight.emptyAnswerable], [0.5, 1, 0]);
  const loose = at(0.13, 0.18, Number.POSITIVE_INFINITY);
  assertEquals([loose.meanRecall, loose.mrr, loose.noAnswerPrecision], [1, 1, 1]);
  assertEquals(at(0.17, 0.18, Number.POSITIVE_INFINITY).noAnswerPrecision, 0);
  const table = renderSweep(points);
  assertStringIncludes(table, "top distance  row distance");
  assertStringIncludes(table, "none");
  assertEquals(percentile([3, 1, 2, 4], 0.5), 2);
  assertEquals(percentile([3, 1, 2, 4], 1), 4);
  assert(Number.isNaN(percentile([], 0.5)));
});
