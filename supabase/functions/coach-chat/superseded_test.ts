import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  type AttemptStore,
  coachChatTurnStaleAfterMs,
  earlierAttempts,
  supersedeFailedAttempts,
  unansweredCopies,
  withoutSupersededMemory,
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

const old = new Date(Date.now() - 10 * 60_000).toISOString();

function store(
  turns: Record<string, unknown>,
  copies: { id: string; key: string; createdAt: string | null }[] = [
    { id: "m1", key: "k1", createdAt: old },
    { id: "m2", key: "k2", createdAt: old },
    { id: "m3", key: "k3", createdAt: old },
  ],
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
    { id: "m1", key: "k1", createdAt: old },
    { id: "m2", key: "k2", createdAt: old },
  ]);
  assertEquals(await supersedeFailedAttempts(unreadable.value), 1);
  assertEquals(unreadable.marked, [["m2"]]);
  const none = store({}, []);
  assertEquals(await supersedeFailedAttempts(none.value), 0);
  assertEquals(none.marked, []);
});

Deno.test("earlier attempts are chosen in code: NULL state, untrimmed text, other keys", () => {
  const row = (id: string, extra: Record<string, unknown> = {}) => ({
    id,
    idempotency_key: `key-${id}`,
    content: "How is my week?",
    safety_state: null,
    created_at: "2026-10-17T09:00:00Z",
    ...extra,
  });
  const rows = [
    row("null-state"),
    row("allowed", { safety_state: "allowed" }),
    row("untrimmed", { content: "\n  How is my week?  " }),
    row("superseded", { safety_state: "unavailable" }),
    row("other-text", { content: "How is my day?" }),
    row("own-key", { idempotency_key: "current" }),
    row("no-key", { idempotency_key: null }),
    row("no-id", { id: 7 }),
    row("no-content", { content: null }),
    row("no-date", { created_at: undefined }),
  ];
  const found = earlierAttempts(rows, "  How is my week? ", "current");
  assertEquals(found.map((attempt) => attempt.id), [
    "null-state",
    "allowed",
    "untrimmed",
    "no-date",
  ]);
  assertEquals(found[0], {
    id: "null-state",
    key: "key-null-state",
    createdAt: "2026-10-17T09:00:00Z",
  });
  assertEquals(found[3].createdAt, null);
});

Deno.test("a turn still running is never superseded; a lost one is, by the same age rule as turn_lost", async () => {
  const now = Date.parse("2026-10-17T10:00:00Z");
  const at = (msAgo: number) => new Date(now - msAgo).toISOString();
  const copies = [
    { id: "double-tap", key: "a", createdAt: at(2_000) },
    { id: "at-limit", key: "b", createdAt: at(coachChatTurnStaleAfterMs) },
    { id: "lost", key: "c", createdAt: at(coachChatTurnStaleAfterMs + 1) },
    { id: "no-age", key: "d", createdAt: null },
  ];
  const open = { state: "in_progress" };
  const live = store({ a: open, b: open, c: open, d: open }, copies);
  assertEquals(await supersedeFailedAttempts(live.value, now), 1);
  assertEquals(live.marked, [["lost"]]);
  // A failed attempt is replaced at any age.
  const failed = store({ a: { state: "failed" } }, [copies[0]]);
  assertEquals(await supersedeFailedAttempts(failed.value, now), 1);
});

Deno.test("memory on every turn drops superseded questions: by state when carried, else by repetition", () => {
  const context = {
    recent_messages: [
      user("Plan?"),
      user("Plan?"),
      assistant("Here is the plan."),
      { role: "user", content: "Marked", safety_state: "unavailable" },
      { role: "user", content: "Fine", safety_state: null },
      assistant("Ok."),
      user("Ask twice"),
      assistant("Answer"),
      user("Ask twice"),
      assistant("Answer again"),
    ],
    recent_other_conversations: [user("Old"), user("  Old "), assistant("Reply")],
    other: "kept",
  };
  const cleaned = withoutSupersededMemory(context);
  assertEquals(cleaned.recent_messages, [
    user("Plan?"),
    assistant("Here is the plan."),
    { role: "user", content: "Fine", safety_state: null },
    assistant("Ok."),
    user("Ask twice"),
    assistant("Answer"),
    user("Ask twice"),
    assistant("Answer again"),
  ]);
  assertEquals(cleaned.recent_other_conversations, [user("  Old "), assistant("Reply")]);
  assertEquals(cleaned.other, "kept");
  assertEquals(context.recent_messages.length, 10, "the original is not changed");
  const clean = { recent_messages: [user("a"), assistant("b")] };
  assertEquals(withoutSupersededMemory(clean), clean);
  assertEquals(withoutSupersededMemory({}), {});
});
