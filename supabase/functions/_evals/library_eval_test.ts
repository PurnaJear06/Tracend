import { assert, assertAlmostEquals, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { librarySources } from "../../library/index.ts";
import questionFile from "./library_questions.json" with { type: "json" };
import {
  type LibraryQuestion,
  questionKind,
  renderTable,
  scoreQuestion,
  summarise,
  summariseKind,
  topSources,
} from "./library_eval_metrics.ts";

const questions = questionFile.questions as LibraryQuestion[];
const ofKind = (kind: string) => questions.filter((question) => questionKind(question) === kind);

Deno.test("the question set holds the original questions, multi-source questions and no-answer questions", () => {
  assertEquals(ofKind("single").length, 42);
  assert(ofKind("multi_source").length >= 15, `${ofKind("multi_source").length} multi-source`);
  assert(ofKind("no_answer").length >= 10, `${ofKind("no_answer").length} no-answer`);
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
      case "no_answer":
        assertEquals(question.expected, [], question.id);
        break;
    }
  }
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

Deno.test("the table has a row per mode and kind, and lists no-answer questions without scoring them", () => {
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
  assertStringIncludes(table, "(not scored)");
  assert(!table.includes("vector_only  multi_source"), "an empty kind has no row");
  assertEquals(topSources(["a", "a", "b", "c", "d"]), ["a", "b", "c"]);
});
