import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  type AttemptStore,
  supersedeFailedAttempts,
  unansweredCopies,
  withoutSupersededQuestions,
} from "./superseded.ts";

const user = (content: string) => ({ role: "user", content });
const assistant = (content: string) => ({ role: "assistant", content });

Deno.test("an unanswered copy of the question is found, an answered one is not", () => {
  const recent = [
    user("How is my week?"),
    assistant("Fine."),
    user("How is my week?"),
    user("Other question"),
    assistant("Answer."),
    user("How is my week?"),
  ];
  assertEquals(unansweredCopies(recent, "How is my week?"), [2, 5]);
  assertEquals(unansweredCopies(recent, "  How is my week?  "), [2, 5]);
  assertEquals(unansweredCopies(recent, "Other question"), []);
  assertEquals(unansweredCopies([], "x"), []);
  assertEquals(unansweredCopies(undefined, "x"), []);
  assertEquals(unansweredCopies([user("x"), "junk", null], "x"), [0]);
});

Deno.test("the context keeps the history and loses only the failed copies", () => {
  const context = {
    coaching_date: "2026-10-17",
    recent_messages: [user("Hi"), assistant("Hello"), user("Plan?"), user("Plan?")],
  };
  const { context: cleaned, dropped } = withoutSupersededQuestions(context, "Plan?");
  assertEquals(dropped, 2);
  assertEquals(cleaned.recent_messages, [user("Hi"), assistant("Hello")]);
  assertEquals(cleaned.coaching_date, "2026-10-17");
  assertEquals(context.recent_messages.length, 4, "the original is not changed");
  const same = withoutSupersededQuestions(context, "Something new");
  assertEquals(same.dropped, 0);
  assertEquals(same.context, context);
});

function store(
  turns: Record<string, unknown>,
  copies = [{ id: "m1", key: "k1" }, { id: "m2", key: "k2" }, { id: "m3", key: "k3" }],
) {
  const marked: string[][] = [];
  const asked: string[] = [];
  const value: AttemptStore = {
    copies: () => Promise.resolve(copies),
    turn: (key) => {
      asked.push(key);
      return Promise.resolve((turns[key] ?? null) as never);
    },
    mark: (ids) => {
      marked.push([...ids]);
      return Promise.resolve();
    },
  };
  return { value, marked, asked };
}

Deno.test("failed, lost and data-summary attempts are marked; a model answer is not", async () => {
  const { value, marked } = store({
    k1: { state: "failed" },
    k2: { state: "in_progress" },
    k3: { state: "answered", message: { answer_source: "data_summary" } },
  });
  assertEquals(await supersedeFailedAttempts(value), 3);
  assertEquals(marked, [["m1", "m2", "m3"]]);
  const answered = store({
    k1: { state: "answered", message: { answer_source: null } },
    k2: { state: "answered", message: { answer_source: "model" } },
    k3: { state: "failed" },
  });
  assertEquals(await supersedeFailedAttempts(answered.value), 1);
  assertEquals(answered.marked, [["m3"]]);
});

Deno.test("an attempt whose state cannot be read is left alone, and nothing is written for none", async () => {
  const unreadable = store({ k1: null, k2: { state: "failed" } }, [
    { id: "m1", key: "k1" },
    { id: "m2", key: "k2" },
  ]);
  assertEquals(await supersedeFailedAttempts(unreadable.value), 1);
  assertEquals(unreadable.marked, [["m2"]]);
  const none = store({}, []);
  assertEquals(await supersedeFailedAttempts(none.value), 0);
  assertEquals(none.marked, []);
});
