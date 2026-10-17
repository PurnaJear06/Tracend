import { assert, assertEquals } from "jsr:@std/assert@1";
import { librarySources } from "../../library/index.ts";
import questionFile from "./library_questions.json" with { type: "json" };
import { type LibraryQuestion, scoreQuestion, summarise } from "./library_eval_metrics.ts";

const questions = questionFile.questions as LibraryQuestion[];

Deno.test("the question set is a few dozen realistic questions with known expected sources", () => {
  assert(questions.length >= 38 && questions.length <= 80, `${questions.length} questions`);
  assertEquals(new Set(questions.map((question) => question.id)).size, questions.length);
  const keys = new Set(librarySources.map((source) => source.slug));
  for (const question of questions) {
    assert(question.text.trim().endsWith("?"), `${question.id} is not a question`);
    assert(question.expected.length >= 1 && question.expected.length <= 3, question.id);
    for (const key of question.expected) assert(keys.has(key), `${question.id}: unknown ${key}`);
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

Deno.test("the summary averages recall and counts full and partial hits", () => {
  const question = { id: "q", text: "?", expected: ["a", "b"] };
  const scores = [
    scoreQuestion(question, ["a", "b"]),
    scoreQuestion(question, ["a"]),
    scoreQuestion(question, ["z"]),
  ];
  assertEquals(summarise(scores), {
    questions: 3,
    meanRecall: 0.5,
    fullRecall: 1 / 3,
    anyRecall: 2 / 3,
  });
});
