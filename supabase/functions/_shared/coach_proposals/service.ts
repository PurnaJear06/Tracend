// The entry point Coach chat calls (part 2 wires it): from the model's intent to a stored, pending
// proposal. It reads the athlete's state through three service-role RPCs, builds the proposal with
// rules (build.ts), and stores it with persist_coach_proposal_v1. It makes no model call and takes
// no budget. The model's reply may mention the proposal only when this returns `ok: true`.
import { buildCoachProposal } from "./build.ts";
import { parseCoachProposalIntent } from "./intent.ts";
import { refusals } from "./refusals.ts";
import { parseAthleteState } from "./state.ts";
import type { CoachProposal, RefusalCode } from "./types.ts";

/** A Supabase-style `rpc`, typed structurally so any service-role client fits. */
export type ProposalRpc = (
  name: string,
  params: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: { code?: string } | null }>;

export type ProposeRequest = Readonly<{
  userId: string;
  /** The model's intent object, as parsed from its reply. */
  intent: unknown;
  /** The athlete's message in this turn: a figure in the intent must appear in it. */
  athleteMessage: string;
  /** The assistant message the proposal belongs to, when it is already stored. */
  sourceMessageId?: string | null;
}>;

export type ProposeResult =
  | Readonly<{
    ok: true;
    proposalId: string;
    expiresAt: string;
    kind: CoachProposal["kind"];
    title: string;
    endsOn: string | null;
  }>
  | Readonly<{
    ok: false;
    code: RefusalCode | "unavailable";
    /** Plain words for the athlete; Coach may quote them. */
    reason: string;
  }>;

const unavailable: ProposeResult = {
  ok: false,
  code: "unavailable",
  reason: "I couldn't prepare that change just now. Try again in a moment.",
};

export async function proposeCoachChange(
  rpc: ProposalRpc,
  request: ProposeRequest,
): Promise<ProposeResult> {
  const parsed = parseCoachProposalIntent(request.intent);
  if (!parsed.ok) return refusals.invalidIntent(parsed.problem);

  const user = { p_user_id: request.userId };
  const [inputs, goalPhase, progression] = await Promise.all([
    rpc("get_coach_proposal_inputs_v1", user),
    rpc("get_goal_phase_inputs_v1", user),
    rpc("get_progression_summary_v1", user),
  ]);
  if (inputs.error || goalPhase.error) return unavailable;
  // A missing progression summary only removes next-session load advice; it never blocks a change.
  const state = parseAthleteState({
    inputs: inputs.data,
    goalPhase: goalPhase.data,
    progression: progression.error ? null : progression.data,
    athleteMessage: request.athleteMessage,
  });
  if (!state) return refusals.profileIncomplete();

  const built = buildCoachProposal(parsed.intent, state);
  if (!built.ok) return built;
  const proposal = built.proposal;

  const stored = await rpc("persist_coach_proposal_v1", {
    p_user_id: request.userId,
    p_kind: proposal.kind,
    p_title: proposal.title,
    p_rationale: proposal.rationale,
    p_benefit: proposal.benefit,
    p_downside: proposal.downside,
    p_confidence: proposal.confidence,
    p_evidence: proposal.evidence,
    p_before: proposal.before,
    p_after: proposal.after,
    p_payload: proposal.payload,
    p_basis: proposal.basis,
    p_ends_on: proposal.endsOn,
    p_expires_in_hours: proposal.expiresInHours,
    p_source_message_id: request.sourceMessageId ?? null,
  });
  if (stored.error) {
    return stored.error.code === "55000" ? refusals.planChanged() : unavailable;
  }
  const row = stored.data as { proposal_id?: unknown; expires_at?: unknown } | null;
  if (typeof row?.proposal_id !== "string" || typeof row.expires_at !== "string") {
    return unavailable;
  }
  return {
    ok: true,
    proposalId: row.proposal_id,
    expiresAt: row.expires_at,
    kind: proposal.kind,
    title: proposal.title,
    endsOn: proposal.endsOn,
  };
}
