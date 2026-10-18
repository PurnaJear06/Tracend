// The Coach chat request handler, offline: a fake authenticated client records every RPC, so the
// order of the steps (replay before budget), the 429 reason, the lost-turn answer and the
// red-flag shortcut (no consent check, no budget place) are checked on the real handler.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { captureLogs } from "../_shared/ai/fakes.ts";
import { handleCoachChat } from "./index.ts";
import type { CoachChatBudgetLedger } from "./budget_ledger.ts";
import type { requireAuth } from "../_shared/auth.ts";

const threadId = "11111111-1111-4111-8111-111111111111";
const key = "22222222-2222-4222-8222-222222222222";

type Call = readonly [string, Record<string, unknown>];

type Body = {
  schema_version?: string;
  error?: string;
  code?: string;
  reason?: string;
  replayed?: boolean;
  message?: {
    answer: string;
    model: string;
    model_provider: string;
    safety_state: string;
    proposal_id?: string;
  };
};

type Setup = Readonly<{
  prepared: unknown;
  /** The error `reserve_ai_budget` raises, or null to accept. */
  refuse?: string | null;
  savedQuestionAt?: string | null;
  /** The newest check-in row, or none. */
  checkIn?: { local_date: string; pain_severity: number } | null;
  /** The athlete's AI consent (default granted). */
  consent?: boolean;
  /** The thread's stored messages (coach_messages), filtered by the handler's own queries. */
  stored?: StoredRow[];
  /** What each attempt produced, by idempotency key (coach_chat_turn). */
  turns?: Record<string, unknown>;
  /** `prepare_coach_chat_v9` raises this message (for example "approved plan required"). */
  prepareFails?: string;
  /** The reply cannot be stored. */
  persistFails?: boolean;
  /** The first read of the saved question fails (as a database error does). */
  savedReadFailsOnce?: boolean;
  /** Route the turn through the AI gateway (as production does), recording library prefetches. */
  gateway?: boolean;
}>;

const gatewaySettings: Record<string, string> = {
  AI_COACH_CHAT_PROVIDER: "anthropic",
  AI_COACH_CHAT_MODEL: "claude-haiku-5-5",
  AI_COACH_CHAT_MAX_OUTPUT_TOKENS: "4096",
  AI_COACH_CHAT_TIMEOUT_MS: "30000",
  AI_COACH_CHAT_EVALUATED: "true",
  ANTHROPIC_API_KEY: "synthetic-test-key",
};

type StoredRow = {
  id: string;
  user_id: string;
  thread_id: string;
  role: string;
  idempotency_key: string | null;
  content: string;
  safety_state: string | null;
  created_at: string;
  proposal_id?: string | null;
};

async function run(question: string, setup: Setup) {
  const calls: Call[] = [];
  const updates: Record<string, unknown>[] = [];
  const markedIds: string[] = [];
  let savedReads = 0;
  // Every RPC and every library prefetch, in the order the handler made them.
  const events: string[] = [];
  const rpc = (name: string, args: Record<string, unknown>) => {
    calls.push([name, args]);
    events.push(name);
    switch (name) {
      case "has_ai_coaching_consent":
        return Promise.resolve({ data: setup.consent ?? true, error: null });
      case "get_ai_consent_v2":
        return Promise.resolve({
          data: { granted: true, provider: "anthropic", notice_version: "v1" },
          error: null,
        });
      case "reserve_ai_budget":
      case "reserve_ai_budget_v2":
        return Promise.resolve(
          setup.refuse
            ? { data: null, error: { message: setup.refuse } }
            : { data: "reservation-1", error: null },
        );
      case "prepare_coach_chat_v9":
        return Promise.resolve(
          setup.prepareFails
            ? { data: null, error: { message: setup.prepareFails, code: "P0001" } }
            : { data: setup.prepared, error: null },
        );
      case "persist_coach_chat_data_summary":
        return Promise.resolve(
          setup.persistFails ? { data: null, error: { code: "XX000" } } : {
            data: {
              assistant_message_id: "55555555-5555-4555-8555-555555555555",
              created_at: "2026-10-17T09:00:00Z",
            },
            error: null,
          },
        );
      case "coach_chat_turn":
        return Promise.resolve({
          data: setup.turns?.[String(args.request_idempotency_key)] ?? null,
          error: null,
        });
      case "persist_coach_chat_result":
        return Promise.resolve({
          data: { assistant_message_id: "33333333-3333-4333-8333-333333333333" },
          error: null,
        });
      default:
        return Promise.resolve({ data: null, error: null });
    }
  };
  // A small in-memory table that applies the handler's filters with SQL semantics: `neq` drops
  // NULL, `eq` matches exactly. The handler's own queries decide what it reads.
  const stored = (): StoredRow[] => [
    ...(setup.stored ?? []),
    ...(setup.savedQuestionAt
      ? [{
        id: "request-question",
        user_id: "user-1",
        thread_id: threadId,
        role: "user",
        idempotency_key: key,
        content: "the request",
        safety_state: null,
        created_at: setup.savedQuestionAt,
      }]
      : []),
  ];
  const table = (name: string, fixed: unknown) => {
    const filters: ((row: Record<string, unknown>) => boolean)[] = [];
    const rowsNow = () =>
      name === "coach_messages"
        ? stored().filter((row) => filters.every((test) => test(row as never)))
        : fixed;
    const chain: Record<string, unknown> = {
      select: () => chain,
      eq: (column: string, value: unknown) => {
        filters.push((row) => row[column] === value);
        return chain;
      },
      neq: (column: string, value: unknown) => {
        filters.push((row) =>
          row[column] !== null && row[column] !== undefined && row[column] !== value
        );
        return chain;
      },
      is: (column: string, value: null) => {
        filters.push((row) => (row[column] ?? null) === value);
        return chain;
      },
      in: (_column: string, ids: string[]) => {
        markedIds.push(...ids);
        return chain;
      },
      limit: () => chain,
      order: () => chain,
      update: (payload: Record<string, unknown>) => {
        updates.push(payload);
        return chain;
      },
      then: (resolve: (value: unknown) => unknown) => resolve({ data: rowsNow(), error: null }),
      maybeSingle: () => {
        if (name === "daily_check_ins") {
          return Promise.resolve({ data: setup.checkIn ?? null, error: null });
        }
        const rows = rowsNow() as unknown[];
        // Like PostgREST: a second matching row is an error, a failed read is an error.
        if (rows.length > 1 || (setup.savedReadFailsOnce && savedReads++ === 0)) {
          return Promise.resolve({ data: null, error: { code: "PGRST116" } });
        }
        return Promise.resolve({ data: rows[0] ?? null, error: null });
      },
    };
    return chain;
  };
  const authenticate = (() =>
    Promise.resolve({
      userId: "user-1",
      userEmail: undefined,
      serviceClient: { rpc, from: (name: string) => table(name, []) },
      userClient: { from: (name: string) => table(name, [{ id: "m1" }]) },
    })) as unknown as typeof requireAuth;
  const held: { current?: CoachChatBudgetLedger } = {};
  const prefetched: string[] = [];
  const prefetch = (text: string) => {
    prefetched.push(text);
    events.push("library_prefetch");
    return null;
  };
  const previousEnv = new Map(
    Object.keys(gatewaySettings).map((name) => [name, Deno.env.get(name)]),
  );
  if (setup.gateway) {
    for (const [name, value] of Object.entries(gatewaySettings)) Deno.env.set(name, value);
  }
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
        prefetch,
      );
    } finally {
      await held.current?.release();
      for (const [name, value] of previousEnv) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  });
  const response = logged.result;
  return {
    status: response.status,
    body: await response.json() as Body,
    prefetched,
    events,
    calls: calls.map(([name]) => name),
    lines: logged.lines,
    updates,
    markedIds,
  };
}

const answeredTurn = {
  state: "answered",
  model_provider: "anthropic",
  model: "claude-haiku-5-5",
  message: {
    id: "44444444-4444-4444-8444-444444444444",
    content: "Keep today's session as planned.",
    evidence: [],
    missing_data: [],
    safety_state: "allowed",
    created_at: "2026-10-17T09:00:00Z",
  },
};

Deno.test("a finished turn is replayed without budget or context work, even at the monthly limit", async () => {
  const result = await run("How did my week go?", {
    prepared: { replayed: false, context: { coaching_date: "2026-10-17" } },
    savedQuestionAt: new Date().toISOString(),
    turns: { [key]: answeredTurn },
    refuse: "monthly cost limit reached",
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.replayed, true);
  assertEquals(result.body.message!.answer, "Keep today's session as planned.");
  assert(!result.calls.includes("reserve_ai_budget"), result.calls.join());
  assert(!result.calls.includes("prepare_coach_chat_v9"), result.calls.join());
  assert(result.calls.includes("coach_chat_turn"));
});

Deno.test("a new turn at a limit gets 429 with the reason and never runs context preparation", async () => {
  for (
    const [message, reason] of [
      ["monthly cost limit reached", "monthly_cost_limit"],
      ["daily rate limit reached", "daily_rate_limit"],
      ["global monthly cost limit reached", "global_monthly_cost_limit"],
    ] as const
  ) {
    const result = await run("How did my week go?", {
      prepared: { replayed: false, context: { coaching_date: "2026-10-17" } },
      refuse: message,
    });
    assertEquals(result.status, 429);
    assertEquals(result.body.error, "ai_usage_limit");
    assertEquals(result.body.reason, reason);
    assert(result.calls.includes("reserve_ai_budget"));
    assert(!result.calls.includes("prepare_coach_chat_v9"), result.calls.join());
    assert(!result.calls.includes("record_coach_chat_question"), "the turn never started");
  }
});

Deno.test("an unexplained refusal is a 429 without a reason", async () => {
  const result = await run("How did my week go?", {
    prepared: { replayed: false, context: { coaching_date: "2026-10-17" } },
    refuse: "something else",
  });
  assertEquals(result.status, 429);
  assertEquals(result.body, { schema_version: "1.1", error: "ai_usage_limit" });
});

Deno.test("a turn still running answers 409; a lost one answers 503 turn_lost", async () => {
  const running = await run("How did my week go?", {
    prepared: { replayed: false, context: {} },
    turns: { [key]: { state: "in_progress" } },
    savedQuestionAt: new Date(Date.now() - 5_000).toISOString(),
  });
  assertEquals(running.status, 409);
  assertEquals(running.body.error, "chat_in_progress");
  for (let attempt = 0; attempt < 2; attempt++) {
    const lost = await run("How did my week go?", {
      prepared: { replayed: false, context: {} },
      turns: { [key]: { state: "in_progress" } },
      savedQuestionAt: new Date(Date.now() - 10 * 60_000).toISOString(),
    });
    assertEquals(lost.status, 503);
    assertEquals(lost.body.code, "turn_lost");
    assertEquals(lost.body.replayed, true);
    assert(!lost.calls.includes("reserve_ai_budget"));
    assert(!lost.calls.includes("prepare_coach_chat_v9"));
  }
});

Deno.test("a lost turn whose age cannot be read stays a 409", async () => {
  const result = await run("How did my week go?", {
    prepared: { replayed: false, context: {} },
    turns: { [key]: { state: "in_progress" } },
    savedQuestionAt: "not a date",
  });
  assertEquals(result.status, 409);
});

Deno.test("a red flag is answered with the referral: no consent check, no budget place, no log of the message", async () => {
  const result = await run("I fainted at the gym yesterday", {
    prepared: { replayed: false, context: { coaching_date: "2026-10-17" } },
    refuse: "monthly cost limit reached",
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.message!.model, "deterministic-safety-v1");
  assertEquals(result.body.message!.model_provider, "mock");
  assertEquals(result.body.message!.safety_state, "limited");
  assert(result.body.message!.answer.includes("emergency number"));
  assert(!result.calls.includes("has_ai_coaching_consent"), result.calls.join());
  assert(!result.calls.includes("reserve_ai_budget"), result.calls.join());
  const logs = result.lines.join("\n");
  assert(logs.includes("coach_chat_red_flag"));
  assert(logs.includes('"rule":"faint"'));
  assert(!logs.includes("gym"), "the message is never logged");
});

Deno.test("an ordinary question still checks consent and takes a budget place first", async () => {
  const result = await run("How did my week go?", {
    prepared: { replayed: false, context: { coaching_date: "2026-10-17" } },
    refuse: "daily rate limit reached",
  });
  assert(result.calls.includes("has_ai_coaching_consent"));
  assertEquals(result.status, 429);
});

Deno.test("pain of 7 or more on today's check-in gets the referral even with no consent and no budget", async () => {
  const today = new Date().toISOString().slice(0, 10);
  const result = await run("Can I train today?", {
    prepared: { replayed: false, context: { coaching_date: today } },
    checkIn: { local_date: today, pain_severity: 8 },
    consent: false,
    refuse: "monthly cost limit reached",
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.message!.model, "deterministic-safety-v1");
  assertEquals(result.body.message!.safety_state, "limited");
  assert(!result.calls.includes("has_ai_coaching_consent"), result.calls.join());
  assert(!result.calls.includes("reserve_ai_budget"), result.calls.join());
  assert(result.lines.join("\n").includes('"source":"check_in"'));
});

Deno.test("an old or mild check-in, or a question that is not about training, takes the normal gates", async () => {
  const today = new Date().toISOString().slice(0, 10);
  const cases: [string, Setup][] = [
    ["Can I train today?", {
      prepared: { replayed: false, context: { coaching_date: today } },
      checkIn: { local_date: today, pain_severity: 6 },
      consent: false,
    }],
    ["Can I train today?", {
      prepared: { replayed: false, context: { coaching_date: today } },
      checkIn: { local_date: "2020-01-01", pain_severity: 9 },
      consent: false,
    }],
    ["What should I eat tonight?", {
      prepared: { replayed: false, context: { coaching_date: today } },
      checkIn: { local_date: today, pain_severity: 9 },
      consent: false,
    }],
  ];
  for (const [question, setup] of cases) {
    const result = await run(question, setup);
    assertEquals(result.status, 403, question);
    assertEquals(result.body.error, "ai_consent_required");
  }
});

const stored = (
  id: string,
  extra: Partial<StoredRow> = {},
): StoredRow => ({
  id,
  user_id: "user-1",
  thread_id: threadId,
  role: "user",
  idempotency_key: `key-${id}`,
  content: "How is my week?",
  safety_state: null,
  created_at: new Date(Date.now() - 10 * 60_000).toISOString(),
  ...extra,
});

/** The updates that mark earlier attempts superseded (the turn trace writes others). */
const supersedeUpdates = (updates: readonly Record<string, unknown>[]) =>
  updates.filter((update) => "safety_state" in update);

Deno.test("a fresh-key retry supersedes failed and lost attempts, and only those", async () => {
  const result = await run("How is my week?", {
    prepared: {
      replayed: false,
      context: {
        coaching_date: "2026-10-17",
        recent_messages: [
          { role: "user", content: "How is my week?" },
          { role: "assistant", content: "Fine." },
          { role: "user", content: "How is my week?" },
        ],
      },
    },
    stored: [
      // Marked: a failed attempt (NULL state, as user messages are stored), an untrimmed copy,
      // and a lost one (still open, well past the function's time limit).
      stored("failed"),
      stored("untrimmed", { content: "  How is my week?\n" }),
      stored("lost"),
      // Left alone: answered, still running, another text, already superseded, another thread,
      // and another athlete (this request's own key is covered by the pure test).
      stored("answered"),
      stored("running", { created_at: new Date(Date.now() - 3_000).toISOString() }),
      stored("other-text", { content: "What should I eat?" }),
      stored("done", { safety_state: "unavailable" }),
      stored("elsewhere", { thread_id: "99999999-9999-4999-8999-999999999999" }),
      stored("stranger", { user_id: "user-2" }),
    ],
    turns: {
      "key-failed": { state: "failed" },
      "key-untrimmed": { state: "answered", message: { answer_source: "data_summary" } },
      "key-lost": { state: "in_progress" },
      "key-answered": { state: "answered", message: { answer_source: null } },
      "key-running": { state: "in_progress" },
    },
  });
  assertEquals(result.status, 200);
  assertEquals(result.markedIds.sort(), ["failed", "lost", "untrimmed"]);
  assertEquals(supersedeUpdates(result.updates), [{ safety_state: "unavailable" }]);
  // The fallback turn is traced: its message gets the fallback code.
  assert(result.updates.some((update) => "guard_faults" in update));
  assert(
    result.calls.indexOf("coach_chat_turn") < result.calls.indexOf("record_coach_chat_question"),
    result.calls.join(),
  );
  assert(result.lines.join("\n").includes('"marked":3'));
});

Deno.test("a question that was not asked before reads and writes nothing about attempts", async () => {
  const result = await run("How is my week?", {
    prepared: {
      replayed: false,
      context: {
        coaching_date: "2026-10-17",
        recent_messages: [
          { role: "user", content: "Something else" },
          { role: "assistant", content: "Fine." },
        ],
      },
    },
  });
  assertEquals(supersedeUpdates(result.updates), []);
  assert(!result.calls.includes("coach_chat_turn"));
});

Deno.test("a later, different question still gets memory without the superseded duplicate", async () => {
  // The duplicate is in the memory; this turn asks something else, so it is not a retry.
  const result = await run("What should I eat?", {
    prepared: {
      replayed: false,
      context: {
        coaching_date: "2026-10-17",
        recent_messages: [
          { role: "user", content: "How is my week?" },
          { role: "user", content: "How is my week?" },
          { role: "assistant", content: "Fine." },
        ],
      },
    },
  });
  assertEquals(result.status, 200);
  assertEquals(supersedeUpdates(result.updates), []);
  assert(!result.calls.includes("coach_chat_turn"));
});

Deno.test("a red flag gets its referral even when the context cannot be prepared", async () => {
  const result = await run("I fainted at the gym yesterday", {
    prepared: null,
    prepareFails: "approved plan required",
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.message!.safety_state, "limited");
  assert(result.body.message!.answer.includes("emergency number"));
  assertEquals(result.body.message!.model_provider, "deterministic");
  assert(result.calls.includes("record_coach_chat_question"));
  assert(result.calls.includes("persist_coach_chat_data_summary"));
  assert(!result.calls.includes("reserve_ai_budget"));
  assert(!result.calls.includes("persist_coach_chat_result"));
  assert(result.lines.join("\n").includes("coach_chat_referral_without_context"));
});

Deno.test("the referral is returned even when it cannot be stored, and the failure is logged", async () => {
  const result = await run("I want to die", {
    prepared: null,
    prepareFails: "approved plan required",
    persistFails: true,
  });
  assertEquals(result.status, 200);
  assert(result.body.message!.answer.includes("988"));
  assert(result.lines.join("\n").includes("referral_not_stored"));
});

Deno.test("an ordinary question still fails with 422 when the context cannot be prepared", async () => {
  const result = await run("How is my week?", {
    prepared: null,
    prepareFails: "approved plan required",
  });
  assertEquals(result.status, 422);
  assertEquals(result.body.reason, "approved_plan_required");
});

Deno.test("a reply carrying the same key does not hide the saved question: replay still works at the limit", async () => {
  const reply = stored("reply", {
    role: "assistant",
    idempotency_key: key,
    created_at: new Date().toISOString(),
  });
  const result = await run("How did my week go?", {
    prepared: { replayed: false, context: {} },
    savedQuestionAt: new Date().toISOString(),
    stored: [reply],
    turns: { [key]: answeredTurn },
    refuse: "monthly cost limit reached",
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.replayed, true);
  assert(!result.calls.includes("reserve_ai_budget"), result.calls.join());
});

Deno.test("a failed read of the saved question is unknown, not 'not saved': a lost turn is still found", async () => {
  const result = await run("How did my week go?", {
    // The early read fails; the budget place is taken; context preparation reports the replay.
    prepared: { replayed: true, turn: { state: "in_progress" } },
    savedQuestionAt: new Date(Date.now() - 10 * 60_000).toISOString(),
    savedReadFailsOnce: true,
  });
  assertEquals(result.status, 503);
  assertEquals(result.body.code, "turn_lost");
  assert(result.calls.includes("reserve_ai_budget"), "unknown does not skip the normal path");
  assert(result.calls.includes("prepare_coach_chat_v9"));
});

Deno.test("a referral without context keeps its own safety state", async () => {
  for (
    const [question, state] of [
      ["I want to die", "refused"],
      ["Please diagnose my knee pain", "refused"],
      ["I fainted at the gym", "limited"],
    ] as const
  ) {
    const result = await run(question, { prepared: null, prepareFails: "approved plan required" });
    assertEquals(result.status, 200, question);
    assertEquals(result.body.message!.safety_state, state, question);
  }
});

Deno.test("a replayed answer shows its card: the stored reply's proposal id rides on the message", async () => {
  const result = await run("How did my week go?", {
    prepared: { replayed: false, context: { coaching_date: "2026-10-17" } },
    savedQuestionAt: new Date().toISOString(),
    turns: { [key]: answeredTurn },
    stored: [{
      id: "44444444-4444-4444-8444-444444444444",
      user_id: "user-1",
      thread_id: threadId,
      role: "assistant",
      idempotency_key: key,
      content: "Keep today's session as planned.",
      safety_state: "allowed",
      created_at: "2026-10-17T09:00:00Z",
      proposal_id: "55555555-5555-4555-8555-555555555555",
    }],
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.replayed, true);
  assertEquals(result.body.message!.proposal_id, "55555555-5555-4555-8555-555555555555");
});

Deno.test("the library embedding starts only after the replay check and the budget, beside context preparation", async () => {
  const fresh = await run("How did my week go?", {
    prepared: { replayed: false, context: {} },
    prepareFails: "approved plan required",
    gateway: true,
  });
  assertEquals(fresh.prefetched, ["How did my week go?"]);
  const at = (event: string) => fresh.events.indexOf(event);
  assert(at("reserve_ai_budget_v2") >= 0, fresh.events.join());
  assert(at("library_prefetch") > at("reserve_ai_budget_v2"), fresh.events.join());
  assert(
    at("library_prefetch") < at("prepare_coach_chat_v9"),
    "it starts before the context is prepared, so the two overlap",
  );
});

Deno.test("a replay never starts the library embedding, even at the monthly limit", async () => {
  const result = await run("How did my week go?", {
    prepared: { replayed: false, context: {} },
    savedQuestionAt: new Date().toISOString(),
    turns: { [key]: answeredTurn },
    refuse: "monthly cost limit reached",
    gateway: true,
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.replayed, true);
  assertEquals(result.prefetched, []);
});

Deno.test("a request refused at the usage limit never starts the library embedding", async () => {
  const result = await run("How did my week go?", {
    prepared: { replayed: false, context: {} },
    refuse: "daily rate limit reached",
    gateway: true,
  });
  assertEquals(result.status, 429);
  assertEquals(result.body.error, "ai_usage_limit");
  assert(result.calls.includes("reserve_ai_budget_v2"), result.calls.join());
  assertEquals(result.prefetched, []);
});
