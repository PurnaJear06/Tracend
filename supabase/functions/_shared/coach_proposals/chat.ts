// Coach chat's use of the proposal engine (A8). After a model answer has passed every reply guard,
// a `proposal_intent` the model returned goes to the engine. The engine stores a proposal, or
// refuses with plain words that are appended to the reply. A referral, a red-flag turn, a data
// summary and any answer that is not an ordinary allowed one never reach the engine, so a turn
// that is about a symptom or a safety limit cannot start a change.
import { coachChatAnswerLimits } from "../contracts/coach_chat_v1.ts";
import type { CoachChatAnswerV2 } from "../contracts/coach_chat_v1.ts";
import type { CoachChatGeneration } from "../providers/coach_chat_provider.ts";
import { type ProposalRpc, proposeCoachChange } from "./service.ts";

export type ChatProposalOutcome =
  /** Nothing to do: no intent, or a turn that may not propose. */
  | Readonly<{ kind: "none"; answer: CoachChatAnswerV2 }>
  | Readonly<{ kind: "proposed"; answer: CoachChatAnswerV2; proposalId: string }>
  /** Refused or unavailable: the plain reason is appended to the reply. */
  | Readonly<{ kind: "refused"; answer: CoachChatAnswerV2; code: string }>;

/** True when this generation may start a proposal. */
export function mayPropose(generation: CoachChatGeneration): boolean {
  return generation.proposalIntent !== undefined && generation.safety === undefined &&
    generation.answer.safety_state === "allowed";
}

export async function proposeFromChat(
  rpc: ProposalRpc,
  userId: string,
  athleteMessage: string,
  generation: CoachChatGeneration,
): Promise<ChatProposalOutcome> {
  if (!mayPropose(generation)) return { kind: "none", answer: generation.answer };
  const result = await proposeCoachChange(rpc, {
    userId,
    intent: generation.proposalIntent,
    athleteMessage,
  });
  if (result.ok) {
    return { kind: "proposed", answer: generation.answer, proposalId: result.proposalId };
  }
  const answer = generation.answer;
  const joined = `${answer.answer.trimEnd()}\n\n${result.reason}`;
  return {
    kind: "refused",
    code: result.code,
    answer: {
      ...answer,
      answer: joined.length <= coachChatAnswerLimits.answerMaxLength
        ? joined
        : `${
          answer.answer.slice(0, coachChatAnswerLimits.answerMaxLength - result.reason.length - 2)
        }\n\n${result.reason}`,
    },
  };
}
