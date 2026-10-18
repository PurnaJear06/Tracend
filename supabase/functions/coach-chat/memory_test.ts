// Coach memory through the real Coach chat handler, offline (A10 part 2): the suggestions that
// follow a reply, the notes written after it, and the rule that a conversation the athlete asked
// not to have remembered gets neither. The model's answer comes from a fake Anthropic fetch and
// every RPC the handler calls is recorded.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { captureLogs, claudeMessage, jsonResponse } from "../_shared/ai/fakes.ts";
import type { requireAuth } from "../_shared/auth.ts";
import { evalProfiles } from "../_evals/fixtures.ts";
import { factWire, makeFact } from "../_shared/coach_memory/memory_fixtures.ts";
import type { CoachFact } from "../_shared/coach_memory/facts.ts";
import { handleCoachChat } from "./index.ts";
import { runInBackground, threadIsRemembered, turnForNote } from "./memory.ts";
import type { CoachChatBudgetLedger } from "./budget_ledger.ts";

const threadId = "11111111-1111-4111-8111-111111111111";
const key = "22222222-2222-4222-8222-222222222222";
const userMessageId = "33333333-3333-4333-8333-333333333330";
const assistantId = "33333333-3333-4333-8333-333333333333";

const settings: Record<string, string> = {
  AI_COACH_CHAT_PROVIDER: "anthropic",
  AI_COACH_CHAT_MODEL: "claude-haiku-5-5",
  AI_COACH_CHAT_MAX_OUTPUT_TOKENS: "4096",
  AI_COACH_CHAT_TIMEOUT_MS: "30000",
  AI_COACH_CHAT_EVALUATED: "true",
  ANTHROPIC_API_KEY: "synthetic-test-key",
};

type Call = Readonly<{ name: string; args: Record<string, unknown> }>;

const reply = {
  answer: "Noted, I'll keep that in mind when I suggest meals.",
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
};

type Options = Readonly<{
  remember?: boolean;
  /** Facts the athlete has confirmed; null makes the memory unreadable. */
  facts?: readonly CoachFact[] | null;
  modelAnswer?: Record<string, unknown>;
  /** The note write does not finish until the test lets it (the reply must not wait for it). */
  holdNotes?: boolean;
  /** The note write fails with an error. */
  notesThrow?: boolean;
}>;

async function turn(question: string, options: Options = {}) {
  const calls: Call[] = [];
  const background: Promise<unknown>[] = [];
  let release: () => void = () => {};
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  const runtime = globalThis as { EdgeRuntime?: unknown };
  const previousRuntime = runtime.EdgeRuntime;
  runtime.EdgeRuntime = { waitUntil: (work: Promise<unknown>) => background.push(work) };
  const context = structuredClone(evalProfiles().find((p) => p.id === "rich")!.context);
  const rpc = (name: string, args: Record<string, unknown>) => {
    calls.push({ name, args });
    const ok = (value: unknown) => Promise.resolve({ data: value, error: null });
    switch (name) {
      case "get_ai_consent_v2":
        return ok({ granted: true, provider: "anthropic", notice_version: "v1" });
      case "reserve_ai_budget_v2":
        return ok("reservation-1");
      case "prepare_coach_chat_v9":
        return ok({
          replayed: false,
          context,
          feature_snapshot_id: "55555555-5555-4555-8555-555555555555",
          policy_evaluation_id: "66666666-6666-4666-8666-666666666666",
        });
      case "persist_coach_chat_result":
        return ok({
          user_message_id: userMessageId,
          assistant_message_id: assistantId,
          created_at: "2026-10-18T09:00:00Z",
        });
      case "get_coach_memory_context_v1":
        return options.facts === null
          ? Promise.resolve({ data: null, error: { message: "down" } })
          : ok({
            schema_version: "1.0",
            local_date: "2026-10-18",
            facts: (options.facts ?? []).map(factWire),
            notes: [],
          });
      case "persist_coach_note_v1":
        if (options.notesThrow) return Promise.reject(new Error("down"));
        if (options.holdNotes) {
          return gate.then(() => ({
            data: { schema_version: "1.0", stored: true, note_id: "note-1" },
            error: null,
          }));
        }
        return ok({ schema_version: "1.0", stored: true, note_id: "note-1" });
      case "get_unnoted_coach_proposals_v1":
        return ok({ schema_version: "1.0", proposals: [] });
      case "get_coach_follow_through_inputs_v1":
        return ok({ schema_version: "1.0", checks: [] });
      default:
        return ok(null);
    }
  };
  const thread = (): Record<string, unknown> => {
    const chain: Record<string, unknown> = {};
    for (const method of ["select", "eq", "neq", "is", "in", "limit", "order", "update"]) {
      chain[method] = () => chain;
    }
    chain.maybeSingle = () => Promise.resolve({ data: null, error: null });
    chain.then = (resolve: (value: unknown) => unknown) => resolve({ data: [], error: null });
    return chain;
  };
  const from = (table: string) => {
    const chain = thread();
    if (table === "coach_threads") {
      chain.maybeSingle = () =>
        Promise.resolve({ data: { remember: options.remember ?? true }, error: null });
    }
    return chain;
  };
  const authenticate = (() =>
    Promise.resolve({
      userId: "user-1",
      userEmail: undefined,
      serviceClient: { rpc, from },
      userClient: { from },
    })) as unknown as typeof requireAuth;

  const previousEnv = new Map(Object.keys(settings).map((name) => [name, Deno.env.get(name)]));
  for (const [name, value] of Object.entries(settings)) Deno.env.set(name, value);
  const realFetch = globalThis.fetch;
  let modelRequest = "";
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    if (String(input).includes("anthropic")) {
      modelRequest = String(init?.body ?? "");
      return Promise.resolve(jsonResponse(claudeMessage({
        content: [{ type: "text", text: JSON.stringify(options.modelAnswer ?? reply) }],
      })));
    }
    return Promise.reject(new Error(`unexpected request to ${String(input)}`));
  }) as typeof fetch;
  const held: { current?: CoachChatBudgetLedger } = {};
  try {
    const logged = await captureLogs(async () => {
      try {
        return await handleCoachChat(
          new Request("https://example.test/coach-chat", {
            method: "POST",
            headers: { Authorization: "Bearer synthetic" },
            body: JSON.stringify({
              schema_version: "1.1",
              thread_id: threadId,
              question,
              timezone: "UTC",
              idempotency_key: key,
            }),
          }),
          held,
          authenticate,
        );
      } finally {
        await held.current?.release();
      }
    });
    const response = logged.result;
    const beforeRelease = background.length;
    release();
    await Promise.all(background);
    const body = await response.json() as {
      message: Record<string, unknown>;
      fact_suggestions?: Record<string, unknown>[];
      preference_prompt?: unknown;
    };
    return {
      status: response.status,
      body,
      calls,
      names: calls.map((call) => call.name),
      modelRequest,
      stored: calls.find((call) => call.name === "persist_coach_chat_result")?.args,
      notes: calls.filter((call) => call.name === "persist_coach_note_v1"),
      background: beforeRelease,
    };
  } finally {
    runtime.EdgeRuntime = previousRuntime;
    globalThis.fetch = realFetch;
    for (const [name, value] of previousEnv) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

Deno.test("a statement the athlete makes becomes a suggestion, never a stored fact", async () => {
  const result = await turn("I hate mushrooms, so please keep them out of my meals");
  assertEquals(result.status, 200);
  assertEquals(result.body.fact_suggestions?.map((s) => [s.action, s.kind, s.subject]), [
    ["add", "food_dislike", "mushrooms"],
  ]);
  assertEquals(result.body.fact_suggestions?.[0].fact_id, null);
  // Only the athlete's confirm in the app saves a fact: the server never calls a fact writer.
  assert(!result.names.some((name) => name.includes("coach_fact")));
  assertEquals("preference_prompt" in result.body, false);
});

Deno.test("a statement that contradicts a confirmed fact is an update suggestion that names it", async () => {
  const saved = makeFact("food_like", "pizza", "Likes pizza");
  const result = await turn("I can't stand pizza any more", { facts: [saved] });
  const [suggestion] = result.body.fact_suggestions!;
  assertEquals(
    [suggestion.action, suggestion.kind, suggestion.fact_id, suggestion.previous],
    ["update", "food_dislike", saved.id, "Likes pizza"],
  );
});

Deno.test("a fact already saved is not suggested again", async () => {
  const result = await turn("I hate mushrooms", {
    facts: [makeFact("food_dislike", "mushrooms", "Dislikes mushrooms")],
  });
  assertEquals(result.body.fact_suggestions, undefined);
});

Deno.test("the model's own suggestions are checked, merged and kept out of the stored answer", async () => {
  const saved = makeFact("injury_limitation", "left knee", "Left knee hurts on squats");
  const result = await turn("my knee has been fine for weeks and I got a bench", {
    facts: [saved],
    modelAnswer: {
      ...reply,
      fact_suggestions: [
        {
          action: "resolve",
          kind: "injury_limitation",
          subject: "left knee",
          statement: "x",
          fact_id: saved.id,
        },
        {
          action: "update",
          kind: "equipment",
          subject: "bench",
          statement: "Has a bench",
          fact_id: "99999999-9999-4999-8999-999999999999",
        },
      ],
    },
  });
  const suggestions = result.body.fact_suggestions!;
  // The model's update names a fact the athlete never saved, so it is dropped.
  assertEquals(suggestions.map((s) => [s.action, s.origin]), [
    ["resolve", "athlete_statement"],
    ["add", "athlete_statement"],
  ]);
  assertEquals("fact_suggestions" in (result.stored!.answer_payload as object), false);
  assertEquals("fact_suggestions" in result.body.message, false);
  assert(result.modelRequest.includes("fact_suggestions"));
});

Deno.test("a model suggestion that fits the vocabulary is offered", async () => {
  const result = await turn("What should I eat after training?", {
    modelAnswer: {
      ...reply,
      fact_suggestions: [{
        action: "add",
        kind: "equipment",
        subject: "kettlebells",
        statement: "Has kettlebells at home",
      }],
    },
  });
  assertEquals(result.body.fact_suggestions?.map((s) => [s.kind, s.origin]), [
    ["equipment", "coach"],
  ]);
});

Deno.test("a conversation that is not remembered gets no suggestions, no notes and no memory reads", async () => {
  const result = await turn("I hate mushrooms and I will train 4 days this week", {
    remember: false,
    modelAnswer: {
      ...reply,
      fact_suggestions: [{ action: "add", kind: "equipment", subject: "x", statement: "Has x" }],
    },
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.fact_suggestions, undefined);
  for (
    const name of [
      "persist_coach_note_v1",
      "get_coach_memory_context_v1",
      "get_unnoted_coach_proposals_v1",
      "get_coach_follow_through_inputs_v1",
    ]
  ) assert(!result.names.includes(name), name);
  // The model is not even offered the field.
  assertEquals(result.modelRequest.includes("fact_suggestions"), false);
});

Deno.test("a remembered conversation gets a note built from the message and the turn, linked to its messages", async () => {
  const result = await turn("OK, I will train 4 days this week. My sleep has been poor.");
  assertEquals(result.notes.length, 1);
  const note = result.notes[0].args;
  assertEquals(note.p_user_id, "user-1");
  assertEquals(note.p_thread_id, threadId);
  assertEquals(note.p_entry_kind, "conversation");
  assertEquals(note.p_message_ids, [userMessageId, assistantId]);
  assertEquals(note.p_concerns, ["poor_sleep"]);
  assertEquals(
    (note.p_commitments as { kind: string; target: number }[]).map((c) => [c.kind, c.target]),
    [["train_days", 4]],
  );
  // The note holds the athlete's words and rules' labels, not the Coach's reply.
  assert(!String(note.p_summary).includes("keep that in mind"));
});

Deno.test("a referral writes no note and offers no suggestion", async () => {
  const result = await turn("I fainted during my last set and I hate mushrooms");
  assertEquals(result.body.fact_suggestions, undefined);
  assert(!result.names.includes("persist_coach_note_v1"));
});

Deno.test("when the facts cannot be read nothing is suggested, but the reply and the note still go out", async () => {
  const result = await turn("I hate mushrooms and my sleep is bad", { facts: null });
  assertEquals(result.status, 200);
  assertEquals(result.body.fact_suggestions, undefined);
  assertEquals(result.notes.length, 1);
});

Deno.test("a conversation that cannot be read is treated as not remembered", async () => {
  const read = (data: unknown, error: unknown = null) => () => Promise.resolve({ data, error });
  assertEquals(await threadIsRemembered(read({ remember: true })), true);
  assertEquals(await threadIsRemembered(read({ remember: false })), false);
  assertEquals(await threadIsRemembered(read(null)), false);
  assertEquals(await threadIsRemembered(read({ remember: true }, { code: "x" })), false);
  assertEquals(await threadIsRemembered(() => Promise.reject(new Error("down"))), false);
});

Deno.test("the note builder is told the evidence, the lookups and the proposal of the turn", () => {
  const generation = {
    lookups: [{ lookup: "meals", rows: 3 }],
  } as unknown as Parameters<typeof turnForNote>[0]["generation"];
  const answer = {
    answer: "x",
    evidence: [{ code: "NUTRITION_WEEK", label: "l", source: "feature_snapshot" }],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: [],
  } as Parameters<typeof turnForNote>[0]["answer"];
  const base = {
    question: "q",
    localDate: "2026-10-18",
    threadId: "t",
    remembered: true,
    generation,
    answer,
    proposalIntent: { kind: "training_schedule" },
    proposed: true,
    userMessageId: "u",
    assistantMessageId: "a",
  };
  const note = turnForNote(base);
  assertEquals(note.evidenceCodes, ["NUTRITION_WEEK"]);
  assertEquals(note.lookups, ["meals"]);
  assertEquals(note.proposalKind, "training_schedule");
  assertEquals(note.messageIds, ["u", "a"]);
  assertEquals(note.outcome, "answered");
  assertEquals(turnForNote({ ...base, proposed: false }).proposalKind, null);
  assertEquals(turnForNote({ ...base, proposalIntent: { kind: "made_up" } }).proposalKind, null);
  assertEquals(turnForNote({ ...base, userMessageId: undefined }).messageIds, ["a"]);
  assertEquals(
    turnForNote({ ...base, answer: { ...answer, safety_state: "refused" } }).outcome,
    "referral",
  );
  assertEquals(
    turnForNote({
      ...base,
      generation: { ...generation, safety: { category: "c" } } as never,
    }).outcome,
    "referral",
  );
});

Deno.test("the notes are written after the reply has gone out, kept alive by the runtime", async () => {
  const result = await turn("I will train 4 days this week", { holdNotes: true });
  // The reply is returned while the note write is still waiting; the runtime holds it open.
  assertEquals(result.status, 200);
  assertEquals(result.background, 1);
  assertEquals(result.notes.length, 1);
});

Deno.test("a failing note write cannot fail a stored reply", async () => {
  const result = await turn("I will train 4 days this week", { notesThrow: true });
  assertEquals(result.status, 200);
  assertEquals(result.body.message.safety_state, "allowed");
});

Deno.test("background work reports its outcome and survives a failing report", async () => {
  const seen: unknown[] = [];
  const waited: Promise<unknown>[] = [];
  const runtime = { waitUntil: (work: Promise<unknown>) => waited.push(work) };
  await runInBackground(() => Promise.resolve(7), (outcome) => seen.push(outcome), runtime);
  await runInBackground(
    () => Promise.reject(new Error("x")),
    (outcome) => seen.push(outcome),
    runtime,
  );
  await runInBackground(() => Promise.resolve(1), () => {
    throw new Error("log failed");
  }, runtime);
  assertEquals(seen, [{ ok: true, value: 7 }, { ok: false }]);
  assertEquals(waited.length, 3);
  await runInBackground(() => Promise.resolve(1), () => {}, undefined);
});

Deno.test("a due fact the athlete speaks of gets a still-true card, and only the scheduler's facts are marked", async () => {
  const due = makeFact("injury_limitation", "left knee", "Left knee hurts on deep squats", {
    reconfirmOn: "2020-01-01",
  });
  const result = await turn("my left knee hurts again today", { facts: [due] });
  const [suggestion] = result.body.fact_suggestions!;
  assertEquals([suggestion.action, suggestion.fact_id], ["reconfirm", due.id]);
  const fresh = makeFact("injury_limitation", "left knee", "Left knee hurts on deep squats", {
    reconfirmOn: "2026-12-01",
  });
  const quiet = await turn("my left knee hurts again today", { facts: [fresh] });
  assertEquals(quiet.body.fact_suggestions, undefined);
});
