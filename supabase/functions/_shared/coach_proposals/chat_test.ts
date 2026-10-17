import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import type { CoachChatAnswerV2 } from "../contracts/coach_chat_v1.ts";
import type { CoachChatGeneration } from "../providers/coach_chat_provider.ts";
import { nothingProposedText, proposeFromChat, withoutProposalPromise } from "./chat.ts";
import { proposalRpcPayloads } from "./fixtures.ts";
import type { ProposalRpc } from "./service.ts";

const answer = (text: string, state = "allowed"): CoachChatAnswerV2 => ({
  answer: text,
  evidence: [],
  missing_data: [],
  safety_state: state as CoachChatAnswerV2["safety_state"],
  suggested_follow_ups: [],
});

const generation = (
  text: string,
  extra: Partial<CoachChatGeneration> = {},
): CoachChatGeneration => ({
  answer: answer(text),
  provider: "anthropic",
  model: "claude-haiku-5-5",
  inputUnits: 0,
  outputUnits: 0,
  estimatedCostUsd: 0,
  attempts: [],
  ...extra,
});

function rpcFor(): { rpc: ProposalRpc; calls: string[] } {
  const data = proposalRpcPayloads();
  const calls: string[] = [];
  const rpc: ProposalRpc = (name) => {
    calls.push(name);
    const table: Record<string, unknown> = {
      get_coach_proposal_inputs_v1: data.inputs,
      get_goal_phase_inputs_v1: data.goalPhase,
      get_progression_summary_v1: data.progression,
      persist_coach_proposal_v1: { proposal_id: "p-1", expires_at: "2026-10-21T09:00:00Z" },
    };
    return Promise.resolve({ data: table[name], error: null });
  };
  return { rpc, calls };
}

const lead =
  "Here's a proposal you can approve below: a lighter week. Tracend works out the sessions.";

Deno.test("the sentences that promise a proposal go, the rest of the reply stays", () => {
  assertEquals(
    withoutProposalPromise(`${lead} Which days suit you?`),
    "Which days suit you?",
  );
  assertEquals(
    withoutProposalPromise("Keep it easy today.\n- Walk\n- Stretch\nSleep well."),
    "Keep it easy today.\n- Walk\n- Stretch\nSleep well.",
  );
  assertEquals(withoutProposalPromise(lead), "");
});

Deno.test("a stored proposal keeps the reply; a refusal replaces the promise with the reason", async () => {
  const { rpc } = rpcFor();
  const kept = await proposeFromChat(
    rpc,
    "u",
    "lower it a little",
    generation(`${lead} Which days?`, {
      proposalIntent: { kind: "nutrition_targets", reason: "plateau", direction: "lower" },
    }),
  );
  assertEquals(kept.kind, "proposed");
  assertStringIncludes(kept.answer.answer, "Here's a proposal you can approve below");

  const refused = await proposeFromChat(
    rpc,
    "u",
    "Lower my calories to 1,200",
    generation(`${lead} Which days?`, {
      proposalIntent: {
        kind: "nutrition_targets",
        reason: "athlete_request",
        direction: "lower",
        requested_calories: 1200,
      },
    }),
  );
  assertEquals(refused.kind, "refused");
  assertEquals(refused.answer.answer.includes("proposal"), false);
  assertStringIncludes(refused.answer.answer, "Which days?");
  assertStringIncludes(refused.answer.answer, "calorie floor");

  const invalid = await proposeFromChat(
    rpc,
    "u",
    "x",
    generation(lead, {
      proposalIntent: { kind: "nope" },
    }),
  );
  assertEquals(invalid.kind, "refused");
  assertStringIncludes(invalid.answer.answer, "couldn't turn that into a change");
  assertEquals(invalid.answer.answer.includes("proposal"), false);
});

Deno.test("no intent, a referral or a limited answer never stores a proposal or promises one", async () => {
  const { rpc, calls } = rpcFor();
  const none = await proposeFromChat(rpc, "u", "x", generation(lead));
  assertEquals(none.kind, "none");
  assertEquals(none.answer.answer, nothingProposedText);
  const limited = await proposeFromChat(rpc, "u", "x", {
    ...generation("Please see a doctor. A proposal waits below."),
    answer: answer("Please see a doctor. A proposal waits below.", "limited"),
    proposalIntent: { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
  });
  assertEquals(limited.kind, "none");
  assertEquals(limited.answer.answer, "Please see a doctor.");
  const referral = generation("Please see a doctor or call emergency services.", {
    safety: { category: "chest", rule: "chest", source: "message" } as never,
    proposalIntent: { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
  });
  assertEquals((await proposeFromChat(rpc, "u", "x", referral)).answer, referral.answer);
  assert(calls.length === 0, "nothing was read or stored");
});
