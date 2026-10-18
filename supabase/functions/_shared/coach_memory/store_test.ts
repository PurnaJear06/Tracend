import { assertEquals } from "jsr:@std/assert@1.0.14";
import type { ServiceRpc } from "../coach_context/service_source.ts";
import { factWire, makeFact } from "./memory_fixtures.ts";
import type { TurnForNote } from "./notes.ts";
import {
  loadMemoryContext,
  parseMemoryContext,
  persistNote,
  recordMemoryAfterTurn,
} from "./store.ts";

type Call = { name: string; params: Record<string, unknown> };

function fakeRpc(
  answers: Record<string, (params: Record<string, unknown>) => unknown>,
): { rpc: ServiceRpc; calls: Call[] } {
  const calls: Call[] = [];
  const rpc: ServiceRpc = (name, params) => {
    calls.push({ name, params });
    const answer = answers[name];
    if (!answer) return Promise.resolve({ data: null, error: { message: "unknown" } });
    try {
      const data = answer(params);
      return Promise.resolve({ data, error: null });
    } catch (error) {
      return Promise.resolve({ data: null, error });
    }
  };
  return { rpc, calls };
}

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

const idle = {
  persist_coach_note_v1: () => ({ schema_version: "1.0", stored: true, note_id: "n1" }),
  get_unnoted_coach_proposals_v1: () => ({ schema_version: "1.0", proposals: [] }),
  get_coach_follow_through_inputs_v1: () => ({ schema_version: "1.0", checks: [] }),
  record_coach_note_follow_through_v1: () => ({ schema_version: "1.0", recorded: true }),
};

Deno.test("memory context is read from the service RPC and parsed", async () => {
  const fact = makeFact("allergy", "peanuts", "Allergy: peanuts");
  const { rpc, calls } = fakeRpc({
    get_coach_memory_context_v1: () => ({
      schema_version: "1.0",
      local_date: "2026-10-18",
      facts: [factWire(fact)],
      notes: [{ id: "n1", entry_kind: "conversation", note_date: "2026-10-17", summary: "S" }],
    }),
  });
  const context = await loadMemoryContext(rpc, "u1");
  assertEquals(calls[0], { name: "get_coach_memory_context_v1", params: { p_user_id: "u1" } });
  assertEquals(context?.localDate, "2026-10-18");
  assertEquals(context?.facts, [fact]);
  assertEquals(context?.notes.length, 1);
});

Deno.test("a memory that cannot be read is left out instead of failing the turn", async () => {
  assertEquals(await loadMemoryContext(fakeRpc({}).rpc, "u1"), null);
  const throwing: ServiceRpc = () => Promise.reject(new Error("down"));
  assertEquals(await loadMemoryContext(throwing, "u1"), null);
  assertEquals(parseMemoryContext({ schema_version: "2.0", local_date: "2026-10-18" }), null);
  assertEquals(parseMemoryContext({ schema_version: "1.0", local_date: "soon" }), null);
  assertEquals(parseMemoryContext(null), null);
});

Deno.test("a note is stored through the RPC with the athlete's id bound by the caller", async () => {
  const { rpc, calls } = fakeRpc(idle);
  const outcome = await recordMemoryAfterTurn(rpc, { userId: "u1", turn: turn() });
  assertEquals(outcome, { conversation: "stored", advice: 0, checked: 0, failed: 0 });
  const stored = calls.find((call) => call.name === "persist_coach_note_v1")!;
  assertEquals(stored.params.p_user_id, "u1");
  assertEquals(stored.params.p_thread_id, "t1");
  assertEquals(stored.params.p_entry_kind, "conversation");
  assertEquals(stored.params.p_message_ids, ["m1", "m2"]);
  assertEquals(stored.params.p_topics, ["training"]);
  assertEquals(stored.params.p_proposal_id, null);
});

Deno.test("a chat that is not remembered, a referral and a data summary write nothing and read nothing", async () => {
  for (
    const skipped of [
      turn({ remember: false }),
      turn({ outcome: "referral" }),
      turn({ outcome: "data_summary" }),
    ]
  ) {
    const { rpc, calls } = fakeRpc(idle);
    const outcome = await recordMemoryAfterTurn(rpc, { userId: "u1", turn: skipped });
    assertEquals(outcome, { conversation: "none", advice: 0, checked: 0, failed: 0 });
    assertEquals(calls, []);
  }
});

Deno.test("a turn with nothing to note still settles answered proposals and follow-through", async () => {
  const { rpc, calls } = fakeRpc({
    ...idle,
    get_unnoted_coach_proposals_v1: () => ({
      schema_version: "1.0",
      proposals: [{
        id: "p1",
        kind: "training_schedule",
        title: "Train 4 days a week",
        outcome: "accepted",
        answered_on: "2026-10-05",
        days_per_week: 4,
        source_message_id: "m9",
      }],
    }),
    get_coach_follow_through_inputs_v1: () => ({
      schema_version: "1.0",
      checks: [{
        note_id: "n7",
        kind: "train_days",
        target: 4,
        window_from: "2026-10-06",
        window_to: "2026-10-12",
        sessions_completed: 2,
      }],
    }),
  });
  const outcome = await recordMemoryAfterTurn(rpc, {
    userId: "u1",
    turn: turn({ question: "ok thanks" }),
  });
  assertEquals(outcome, { conversation: "none", advice: 1, checked: 1, failed: 0 });
  const advice = calls.find((call) => call.name === "persist_coach_note_v1")!;
  assertEquals(advice.params.p_entry_kind, "advice");
  assertEquals(advice.params.p_thread_id, null);
  assertEquals(advice.params.p_proposal_id, "p1");
  const through = calls.find((call) => call.name === "record_coach_note_follow_through_v1")!;
  assertEquals(through.params, {
    p_user_id: "u1",
    p_note_id: "n7",
    p_status: "partly",
    p_checked_on: "2026-10-18",
    p_detail: "2 of 4 sessions from 2026-10-06 to 2026-10-12",
  });
});

Deno.test("the database's refusal is reported, never thrown", async () => {
  const refused = fakeRpc({
    ...idle,
    persist_coach_note_v1: () => ({
      schema_version: "1.0",
      stored: false,
      reason: "not_remembered",
    }),
  });
  assertEquals(
    (await recordMemoryAfterTurn(refused.rpc, { userId: "u1", turn: turn() })).conversation,
    "not_remembered",
  );
  const repeat = fakeRpc({
    ...idle,
    persist_coach_note_v1: () => ({
      schema_version: "1.0",
      stored: false,
      reason: "already_noted",
    }),
  });
  assertEquals(
    (await recordMemoryAfterTurn(repeat.rpc, { userId: "u1", turn: turn() })).conversation,
    "already_noted",
  );
});

Deno.test("every failing call is counted and none stops the others", async () => {
  const broken = fakeRpc({});
  const outcome = await recordMemoryAfterTurn(broken.rpc, { userId: "u1", turn: turn() });
  assertEquals(outcome, { conversation: "failed", advice: 0, checked: 0, failed: 3 });
  const throwing: ServiceRpc = () => Promise.reject(new Error("down"));
  const thrown = await recordMemoryAfterTurn(throwing, { userId: "u1", turn: turn() });
  assertEquals(thrown, { conversation: "failed", advice: 0, checked: 0, failed: 3 });
  const recordFails = fakeRpc({
    ...idle,
    get_coach_follow_through_inputs_v1: () => ({
      schema_version: "1.0",
      checks: [{
        note_id: "n7",
        kind: "train_days",
        target: 2,
        window_from: "2026-10-06",
        window_to: "2026-10-12",
        sessions_completed: 2,
      }],
    }),
    record_coach_note_follow_through_v1: () => {
      throw new Error("no");
    },
  });
  assertEquals(
    await recordMemoryAfterTurn(recordFails.rpc, { userId: "u1", turn: turn() }),
    { conversation: "stored", advice: 0, checked: 0, failed: 1 },
  );
});

Deno.test("persistNote sends exactly the draft's fields", async () => {
  const { rpc, calls } = fakeRpc(idle);
  await persistNote(rpc, "u1", {
    entryKind: "advice",
    threadId: null,
    noteDate: "2026-10-12",
    summary: "S",
    topics: ["plan"],
    concerns: [],
    advice: [{ code: "x", summary: "y", outcome: "declined" }],
    commitments: [],
    messageIds: [],
    proposalId: "p1",
  });
  assertEquals(Object.keys(calls[0].params).sort(), [
    "p_advice",
    "p_commitments",
    "p_concerns",
    "p_entry_kind",
    "p_message_ids",
    "p_note_date",
    "p_proposal_id",
    "p_summary",
    "p_thread_id",
    "p_topics",
    "p_user_id",
  ]);
});
