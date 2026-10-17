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

/** A sentence that tells the athlete a proposal, or its checking, is on the way. */
const promisesProposal =
  /\bproposals?\b|\bapprove\b[^.!?]*\bbelow\b|\bTracend (?:checks|works out)\b/i;

/** What the reply says when taking the promise out leaves nothing. */
export const nothingProposedText = "No change has been put forward.";

/**
 * The reply with every sentence that promises a proposal removed. Used whenever no proposal was
 * stored, so the reply never points at a card that is not there.
 */
export function withoutProposalPromise(text: string): string {
  const pieces = text.split(/((?<=[.!?])\s+)/);
  let kept = "";
  for (let index = 0; index < pieces.length; index += 2) {
    if (promisesProposal.test(pieces[index])) continue;
    kept += pieces[index] + (pieces[index + 1] ?? "");
  }
  return kept.trim();
}

const withText = (answer: CoachChatAnswerV2, text: string): CoachChatAnswerV2 => ({
  ...answer,
  answer: text.slice(0, coachChatAnswerLimits.answerMaxLength),
});

export async function proposeFromChat(
  rpc: ProposalRpc,
  userId: string,
  athleteMessage: string,
  generation: CoachChatGeneration,
): Promise<ChatProposalOutcome> {
  // A referral says nothing about proposals; everything else that stores none must not promise one.
  if (generation.safety !== undefined) return { kind: "none", answer: generation.answer };
  const answer = generation.answer;
  const stripped = withoutProposalPromise(answer.answer);
  if (!mayPropose(generation)) {
    return {
      kind: "none",
      answer: stripped === answer.answer
        ? answer
        : withText(answer, stripped || nothingProposedText),
    };
  }
  const result = await proposeCoachChange(rpc, {
    userId,
    intent: generation.proposalIntent,
    athleteMessage,
  });
  if (result.ok) return { kind: "proposed", answer, proposalId: result.proposalId };
  // The model's lead-in promised a card; the reason stands in its place.
  const lead = stripped.slice(
    0,
    Math.max(0, coachChatAnswerLimits.answerMaxLength - result.reason.length - 2),
  );
  return {
    kind: "refused",
    code: result.code,
    answer: withText(answer, lead ? `${lead}\n\n${result.reason}` : result.reason),
  };
}
