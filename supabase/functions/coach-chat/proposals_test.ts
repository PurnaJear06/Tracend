// Coach proposals through the real Coach chat handler, offline (A8). The model's answer comes from
// a fake Anthropic fetch, the database from an in-memory fake that answers the proposal RPCs with
// the athlete fixture, and every RPC the handler calls is recorded. Each owner case runs from the
// chat answer to the stored proposal and the link that puts its card under the reply.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { captureLogs, claudeMessage, jsonResponse } from "../_shared/ai/fakes.ts";
import type { requireAuth } from "../_shared/auth.ts";
import { evalProfiles } from "../_evals/fixtures.ts";
import { proposalRpcPayloads } from "../_shared/coach_proposals/fixtures.ts";
import { handleCoachChat } from "./index.ts";
import type { CoachChatBudgetLedger } from "./budget_ledger.ts";

const threadId = "11111111-1111-4111-8111-111111111111";
const key = "22222222-2222-4222-8222-222222222222";
const assistantId = "33333333-3333-4333-8333-333333333333";
const proposalId = "44444444-4444-4444-8444-444444444444";

const settings: Record<string, string> = {
  AI_COACH_CHAT_PROVIDER: "anthropic",
  AI_COACH_CHAT_MODEL: "claude-haiku-5-5",
  AI_COACH_CHAT_MAX_OUTPUT_TOKENS: "4096",
  AI_COACH_CHAT_TIMEOUT_MS: "30000",
  AI_COACH_CHAT_EVALUATED: "true",
  ANTHROPIC_API_KEY: "synthetic-test-key",
};

type Call = Readonly<{ name: string; args: Record<string, unknown> }>;

/**
 * The intent as the model writes it: a list of one item whose fields are name/value pairs, every
 * value as text. The tests below state each intent as the engine reads it; this is the only
 * place that turns it into the model's shape.
 */
function asModelIntent(intent: Record<string, unknown>) {
  const { kind, reason, note, ...fields } = intent;
  return [{
    kind,
    reason,
    note: note ?? "",
    params: Object.entries(fields).map(([name, value]) => ({
      name,
      value: Array.isArray(value) ? value.join(",") : String(value),
    })),
  }];
}

/** A model answer in the gateway's shape: every key present, "nothing" written as [] . */
function asModelAnswer(answer: Record<string, unknown>) {
  const intent = answer.proposal_intent;
  return {
    data_requests: [],
    fact_suggestions: [],
    reasoning_chain: [],
    ...answer,
    proposal_intent: intent && !Array.isArray(intent)
      ? asModelIntent(intent as Record<string, unknown>)
      : intent ?? [],
  };
}

const answerText = (overrides: Record<string, unknown> = {}) =>
  JSON.stringify({
    answer: "Here's a proposal you can approve below. Tracend checks it against your limits first.",
    evidence: [],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: [],
    ...overrides,
  });

async function turn(question: string, modelAnswer: Record<string, unknown>) {
  const calls: Call[] = [];
  const data = proposalRpcPayloads();
  const context = structuredClone(evalProfiles().find((p) => p.id === "rich")!.context);
  const rpc = (name: string, args: Record<string, unknown>) => {
    calls.push({ name, args });
    const reply = (value: unknown) => Promise.resolve({ data: value, error: null });
    switch (name) {
      case "get_ai_consent_v2":
        return reply({ granted: true, provider: "anthropic", notice_version: "v1" });
      case "reserve_ai_budget_v2":
        return reply("reservation-1");
      case "prepare_coach_chat_v9":
        return reply({
          replayed: false,
          context,
          feature_snapshot_id: "55555555-5555-4555-8555-555555555555",
          policy_evaluation_id: "66666666-6666-4666-8666-666666666666",
        });
      case "persist_coach_chat_result":
        return reply({ assistant_message_id: assistantId, created_at: "2026-10-18T09:00:00Z" });
      case "get_coach_proposal_inputs_v1":
        return reply(data.inputs);
      case "get_goal_phase_inputs_v1":
        return reply(data.goalPhase);
      case "get_progression_summary_v1":
        return reply(data.progression);
      case "persist_coach_proposal_v1":
        return reply({
          schema_version: "1.0",
          proposal_id: proposalId,
          expires_at: "2026-10-21T09:00:00Z",
        });
      default:
        return reply(null);
    }
  };
  const chain: Record<string, unknown> = {};
  for (const method of ["select", "eq", "neq", "is", "in", "limit", "order", "update"]) {
    chain[method] = () => chain;
  }
  chain.maybeSingle = () => Promise.resolve({ data: null, error: null });
  chain.then = (resolve: (value: unknown) => unknown) => resolve({ data: [], error: null });
  const authenticate = (() =>
    Promise.resolve({
      userId: "user-1",
      userEmail: undefined,
      serviceClient: { rpc, from: () => chain },
      userClient: { from: () => chain },
    })) as unknown as typeof requireAuth;

  const previousEnv = new Map(Object.keys(settings).map((name) => [name, Deno.env.get(name)]));
  for (const [name, value] of Object.entries(settings)) Deno.env.set(name, value);
  const realFetch = globalThis.fetch;
  let modelCalls = 0;
  globalThis.fetch = ((input: string | URL | Request) => {
    if (String(input).includes("anthropic")) {
      modelCalls++;
      return Promise.resolve(jsonResponse(claudeMessage({
        content: [{ type: "text", text: JSON.stringify(asModelAnswer(modelAnswer)) }],
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
    return {
      status: response.status,
      body: await response.json() as {
        message: { answer: string; proposal_id?: string; safety_state: string };
      },
      calls,
      modelCalls,
      persisted: calls.find((call) => call.name === "persist_coach_proposal_v1")?.args,
      stored: calls.find((call) => call.name === "persist_coach_chat_result")?.args,
      linked: calls.find((call) => call.name === "link_coach_proposal_v1")?.args,
    };
  } finally {
    globalThis.fetch = realFetch;
    for (const [name, value] of previousEnv) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

type Payload = {
  training?: { mode: string; ends_on?: string; weekly_structure: unknown[] };
  nutrition?: { calories: number };
  goal?: { phase: string; phase_ends_on: string | null; goal_type: string };
};

/** What the card needs, as the proposal row stores it. */
function assertCardFields(persisted: Record<string, unknown>) {
  assert(String(persisted.p_title).length > 0);
  assert(String(persisted.p_rationale).length > 0);
  assert(String(persisted.p_downside).length > 0);
  assert(Number(persisted.p_expires_in_hours) > 0);
  const before = persisted.p_before as { rows: unknown[] };
  const after = persisted.p_after as { rows: unknown[] };
  assert(before.rows.length > 0 && after.rows.length > 0);
  assertEquals((persisted.p_evidence as unknown[]).length > 0, true);
}

function assertProposedAndLinked(result: Awaited<ReturnType<typeof turn>>, kind: string) {
  assertEquals(result.status, 200);
  assertEquals(result.persisted?.p_kind, kind);
  assertEquals(result.persisted?.p_user_id, "user-1");
  assertCardFields(result.persisted!);
  // The reply is stored first, then pointed at its proposal; the live response carries the id.
  assertEquals(result.linked, {
    p_user_id: "user-1",
    p_message_id: assistantId,
    p_proposal_id: proposalId,
  });
  assertEquals(result.body.message.proposal_id, proposalId);
  const names = result.calls.map((call) => call.name);
  assert(names.indexOf("persist_coach_chat_result") < names.indexOf("link_coach_proposal_v1"));
  // The intent is not part of the stored answer.
  assert(!("proposal_intent" in (result.stored!.answer_payload as object)));
}

Deno.test("home for 10 to 15 days with no gym becomes a bodyweight block that ends on the date", async () => {
  const result = await turn("I'll be home for 10-15 days with no gym", {
    proposal_intent: {
      kind: "temporary_block",
      reason: "travel",
      setting: "bodyweight",
      start_date: "2026-10-18",
      end_date: "2026-11-01",
    },
    ...JSON.parse(answerText()),
  });
  assertProposedAndLinked(result, "temporary_block");
  assertEquals(result.persisted?.p_ends_on, "2026-11-01");
  const payload = result.persisted?.p_payload as Payload;
  assertEquals(payload.training?.mode, "block");
  assertEquals(payload.training?.ends_on, "2026-11-01");
  assertEquals(payload.training?.weekly_structure.length, 3);
});

Deno.test("4 days a week for the next 2 months becomes a new schedule", async () => {
  const result = await turn("Let's change my plan for the next 2 months to 4 days a week", {
    proposal_intent: {
      kind: "training_schedule",
      reason: "athlete_request",
      days_per_week: 4,
      weeks: 8,
    },
    ...JSON.parse(answerText()),
  });
  assertProposedAndLinked(result, "training_schedule");
  const payload = result.persisted?.p_payload as Payload;
  assertEquals(payload.training?.mode, "new_version");
  assertEquals(payload.training?.weekly_structure.length, 4);
});

Deno.test("a diet break is maintenance calories for two weeks on the fat-loss goal", async () => {
  const result = await turn("Take a diet break", {
    proposal_intent: { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
    ...JSON.parse(answerText()),
  });
  assertProposedAndLinked(result, "goal_or_phase");
  const payload = result.persisted?.p_payload as Payload;
  assertEquals(payload.goal?.phase, "diet_break");
  assertEquals(payload.goal?.goal_type, "fat_loss");
  assertEquals(payload.goal?.phase_ends_on, "2026-10-31");
  assert((payload.nutrition?.calories ?? 0) > 1500);
});

Deno.test("a lighter session tomorrow becomes a next-session block that ends that day", async () => {
  const result = await turn("Tomorrow I'm tired, go lighter", {
    proposal_intent: {
      kind: "next_session_adjustment",
      reason: "fatigue",
      direction: "lighter",
      session: "next",
    },
    ...JSON.parse(answerText()),
  });
  assertProposedAndLinked(result, "next_session_adjustment");
  assertEquals(result.persisted?.p_ends_on, "2026-10-19");
  assertEquals(result.persisted?.p_expires_in_hours, 24);
});

Deno.test("lowering calories to 1,200 is refused: the reason is appended and nothing is stored", async () => {
  const result = await turn("Lower my calories to 1,200", {
    proposal_intent: {
      kind: "nutrition_targets",
      reason: "athlete_request",
      direction: "lower",
      requested_calories: 1200,
    },
    ...JSON.parse(answerText()),
  });
  assertEquals(result.status, 200);
  assertEquals(result.persisted, undefined);
  assertEquals(result.linked, undefined);
  assertEquals(result.body.message.proposal_id, undefined);
  assertStringIncludes(result.body.message.answer, "below your calorie floor");
  // The lead-in that promised a card is gone: the reply never points at one that is not there.
  assertEquals(result.body.message.answer.includes("proposal"), false);
  // The appended reason is what was stored, so the thread reloads with it.
  assertStringIncludes(
    String(
      result.stored?.answer_payload && (result.stored.answer_payload as { answer: string }).answer,
    ),
    "below your calorie floor",
  );
});

Deno.test("a red-flag turn calls no model and starts no proposal", async () => {
  const result = await turn("I fainted at the gym, so lower my calories to 1,800", {
    proposal_intent: { kind: "nutrition_targets", reason: "athlete_request", direction: "lower" },
    ...JSON.parse(answerText()),
  });
  assertEquals(result.status, 200);
  assertEquals(result.modelCalls, 0);
  assertEquals(result.body.message.safety_state, "limited");
  assertEquals(result.persisted, undefined);
  assert(!result.calls.some((call) => call.name.startsWith("get_coach_proposal_inputs")));
});

Deno.test("a limited or refused model answer never starts a proposal", async () => {
  for (const safety of ["limited", "refused"]) {
    const result = await turn("Take a diet break", {
      proposal_intent: { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
      ...JSON.parse(answerText({ safety_state: safety })),
    });
    assertEquals(result.persisted, undefined, safety);
    assertEquals(result.body.message.proposal_id, undefined, safety);
  }
});

Deno.test("an invalid intent is dropped: the reply is kept and nothing is stored", async () => {
  const result = await turn("Take a diet break", {
    proposal_intent: {
      kind: "nutrition_targets",
      reason: "athlete_request",
      direction: "lower",
      requested_calories: 99999,
    },
    ...JSON.parse(answerText()),
  });
  assertEquals(result.status, 200);
  assertEquals(result.persisted, undefined);
  assertEquals(result.body.message.proposal_id, undefined);
  assertStringIncludes(result.body.message.answer, "couldn't turn that into a change");
  assertEquals(result.body.message.answer.includes("proposal you can approve"), false);
  assertEquals(result.body.message.answer.includes("requested_calories"), false);
});

Deno.test("an answer that claims the change was made is repaired, never stored as is", async () => {
  const result = await turn("Take a diet break", {
    proposal_intent: { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
    ...JSON.parse(answerText({ answer: "I've updated your calories to maintenance." })),
  });
  // The fake model repeats the same claim on the repair, so the turn ends without a model answer.
  assertEquals(result.persisted, undefined);
  assert(!String(JSON.stringify(result.stored ?? {})).includes("I've updated"));
});

Deno.test("a reply that promises a proposal but sends no intent loses the promise", async () => {
  const result = await turn("Take a diet break", { ...JSON.parse(answerText()) });
  assertEquals(result.persisted, undefined);
  assertEquals(result.body.message.proposal_id, undefined);
  assertEquals(result.body.message.answer, "No change has been put forward.");
});
