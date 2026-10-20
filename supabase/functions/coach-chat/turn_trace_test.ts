import { assertEquals } from "jsr:@std/assert@1.0.14";
import type { CoachChatAttemptTelemetry } from "../_shared/providers/coach_chat_provider.ts";
import {
  guardFaultsOf,
  lookupTrace,
  mostTraceEntries,
  recordTurnTrace,
  type TraceClient,
} from "./turn_trace.ts";

const attempt = (
  kind: CoachChatAttemptTelemetry["attempt"],
  outcome: CoachChatAttemptTelemetry["outcome"],
  extra: Partial<CoachChatAttemptTelemetry> = {},
): CoachChatAttemptTelemetry => ({
  attempt: kind,
  outcome,
  latencyMs: 10,
  completionTokens: 5,
  ...extra,
});

Deno.test("a clean turn leaves no trace", () => {
  assertEquals(guardFaultsOf([attempt("initial", "valid")]), []);
  assertEquals(guardFaultsOf([attempt("initial", "lookup"), attempt("lookup", "valid")]), []);
  assertEquals(lookupTrace(undefined), []);
});

Deno.test("a repaired turn records each rule and how many attempts broke it", () => {
  assertEquals(
    guardFaultsOf([
      attempt("initial", "invalid", {
        rule: "numbers_not_grounded",
        alsoRules: ["claimed_action"],
        path: "answer",
      }),
      attempt("repair", "valid"),
    ]),
    ["rule:numbers_not_grounded:1", "rule:claimed_action:1"],
  );
});

Deno.test("a fallback records the rules of both attempts, how an attempt failed and the failure code", () => {
  assertEquals(
    guardFaultsOf([
      attempt("initial", "invalid", { rule: "numbers_not_grounded" }),
      attempt("repair", "invalid", { rule: "numbers_not_grounded" }),
    ], "provider_response_invalid"),
    ["rule:numbers_not_grounded:2", "fallback:provider_response_invalid"],
  );
  assertEquals(
    guardFaultsOf([attempt("initial", "timeout")], "provider_timeout"),
    ["outcome:initial_timeout", "fallback:provider_timeout"],
  );
});

Deno.test("entries are names and counts only, in the column's format, and bounded", () => {
  const many = Array.from(
    { length: 30 },
    (_, i) =>
      attempt("initial", "invalid", {
        rule: `rule_${String.fromCharCode(97 + (i % 26))}` as never,
      }),
  );
  const entries = guardFaultsOf(many, "provider_response_invalid");
  assertEquals(entries.length <= mostTraceEntries, true);
  for (const entry of entries) assertEquals(/^[a-z0-9_:]+$/.test(entry), true, entry);
});

Deno.test("lookups are logged per round: r1_workouts:4, r2_recovery:28, summed within a round", () => {
  assertEquals(
    lookupTrace([
      { lookup: "exercise_history", rows: 14, round: 1 },
      { lookup: "body", rows: 3, round: 1 },
      { lookup: "exercise_history", rows: 2, round: 1 },
      { lookup: "exercise_history", rows: 5, round: 2 },
      { lookup: "recovery", rows: 28, round: 2 },
    ]),
    ["r1_exercise_history:16", "r1_body:3", "r2_exercise_history:5", "r2_recovery:28"],
  );
  // A count with no round (a caller that does not run rounds) reads as the first.
  assertEquals(lookupTrace([{ lookup: "workouts", rows: 4 }]), ["r1_workouts:4"]);
  assertEquals(lookupTrace(undefined), []);
  assertEquals(lookupTrace([]), []);
});

Deno.test("a trace entry is names and counts in the column's format, and the column's limits hold", () => {
  const all = [
    "workouts",
    "exercise_history",
    "meals",
    "body",
    "check_ins",
    "recovery",
    "plan_history",
    "goals",
    "weekly_reviews",
    "health_history",
    "past_messages",
  ];
  // Eight lookups in round one and eight in round two: the column keeps its 12 entries.
  const entries = lookupTrace(
    [
      ...all.slice(0, 8).map((lookup) => ({ lookup, rows: 60, round: 1 })),
      ...all.slice(0, 8).map((
        lookup,
      ) => ({ lookup, rows: 60, round: 2 })),
    ],
  );
  assertEquals(entries.length, mostTraceEntries);
  assertEquals(entries[0], "r1_workouts:60");
  const column = entries.join(" ");
  assertEquals(/^[a-z0-9_: ]*$/.test(column), true);
  assertEquals(column.length <= 600, true);
});

function client(result: { error: unknown } | "throw") {
  const writes: { values: unknown; id?: string; userId?: string }[] = [];
  const traceClient: TraceClient = {
    from: () => ({
      update: (values) => ({
        eq: (_column, id) => ({
          eq: (_other, userId) => {
            writes.push({ values, id, userId });
            if (result === "throw") throw new Error("down");
            return Promise.resolve(result);
          },
        }),
      }),
    }),
  };
  return { traceClient, writes };
}

Deno.test("the trace is written on the assistant message for that athlete only", async () => {
  const { traceClient, writes } = client({ error: null });
  assertEquals(
    await recordTurnTrace(traceClient, "user-1", "message-1", {
      guardFaults: ["rule:claimed_action:1"],
      lookups: ["body:3"],
    }),
    true,
  );
  assertEquals(writes, [{
    values: { guard_faults: ["rule:claimed_action:1"], lookups: ["body:3"] },
    id: "message-1",
    userId: "user-1",
  }]);
});

Deno.test("the library version the turn searched is stored with the answer", async () => {
  const { traceClient, writes } = client({ error: null });
  assertEquals(
    await recordTurnTrace(traceClient, "user-1", "message-1", {
      guardFaults: [],
      lookups: [],
      libraryVersion: "0123456789abcdef",
    }),
    true,
  );
  assertEquals(
    await recordTurnTrace(traceClient, "user-1", "message-2", {
      guardFaults: [],
      lookups: [],
      libraryVersion: "not a version",
    }),
    true,
  );
  assertEquals(writes, [{
    values: { library_version: "0123456789abcdef" },
    id: "message-1",
    userId: "user-1",
  }]);
});

Deno.test("a clean turn or a missing message writes nothing; a failed write never throws", async () => {
  const { traceClient, writes } = client({ error: { code: "x" } });
  assertEquals(
    await recordTurnTrace(traceClient, "u", "m", { guardFaults: [], lookups: [] }),
    true,
  );
  assertEquals(
    await recordTurnTrace(traceClient, "u", undefined, { guardFaults: ["a"], lookups: [] }),
    true,
  );
  assertEquals(writes.length, 0);
  assertEquals(
    await recordTurnTrace(traceClient, "u", "m", { guardFaults: ["a"], lookups: [] }),
    false,
  );
  const thrower = client("throw");
  assertEquals(
    await recordTurnTrace(thrower.traceClient, "u", "m", { guardFaults: ["a"], lookups: [] }),
    false,
  );
});
