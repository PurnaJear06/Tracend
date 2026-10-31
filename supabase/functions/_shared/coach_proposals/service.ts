// The entry point Coach chat calls (coach-chat/index.ts, through chat.ts): from the model's intent to a stored, pending
// proposal. It reads the athlete's state through three service-role RPCs, builds the proposal with
// rules (build.ts), and stores it with persist_coach_proposal_v1. It makes no model call and takes
// no budget. The model's reply may mention the proposal only when this returns `ok: true`.
import type { DeloadReason } from "../training/guidance/payload.ts";
import { buildCoachProposal } from "./build.ts";
import { parseCoachProposalIntent } from "./intent.ts";
import { buildTrainingPause, parsePauseInputs } from "./pause.ts";
import { refusals } from "./refusals.ts";
import { parseAthleteState } from "./state.ts";
import { buildSuggestedDeload } from "./training.ts";
import type { AthleteState, CoachProposal, CoachProposalIntent, RefusalCode } from "./types.ts";

/** A Supabase-style `rpc`, typed structurally so any service-role client fits. */
export type ProposalRpc = (
  name: string,
  params: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: { code?: string; message?: string } | null }>;

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
    code: RefusalCode | "unavailable" | "other_proposal_pending";
    /** Plain words for the athlete; Coach may quote them. */
    reason: string;
  }>;

const squash = (text: string) => text.replace(/\s+/g, " ").trim();

/**
 * A note is quoted to the athlete as "in your words", so it stays only when it really is a piece
 * of their message (case and spacing ignored), and then as they wrote it. A note the model wrote
 * itself is dropped.
 */
export function keepAthletesNote(
  intent: CoachProposalIntent,
  athleteMessage: string,
): CoachProposalIntent {
  if (intent.note === undefined) return intent;
  const message = squash(athleteMessage);
  const at = message.toLowerCase().indexOf(squash(intent.note).toLowerCase());
  if (at >= 0) return { ...intent, note: message.slice(at, at + squash(intent.note).length) };
  const { note: _dropped, ...rest } = intent;
  return rest as CoachProposalIntent;
}

/** Why the database refused to store a proposal (55000), by what it says. */
function storeRefusal(message: string): ProposeResult {
  if (message.includes("health professional")) return refusals.seeProfessional();
  if (message.includes("health check")) return refusals.screeningChanged();
  if (message.includes("logged data")) return refusals.evidenceChanged();
  if (message.includes("break")) return refusals.pauseNoLongerFits();
  return refusals.planChanged();
}

const unavailable: Extract<ProposeResult, { ok: false }> = {
  ok: false,
  code: "unavailable",
  reason: "I couldn't prepare that change just now. Try again in a moment.",
};

/** The athlete's state for the rules, read through the service-role RPCs; null when it is unreadable. */
async function readState(
  rpc: ProposalRpc,
  userId: string,
  athleteMessage: string,
): Promise<AthleteState | ProposeResult> {
  const user = { p_user_id: userId };
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
    athleteMessage,
  });
  return state ?? refusals.profileIncomplete();
}

/** Stores a built proposal as pending; the athlete's answer is the only thing that applies it. */
async function storeProposal(
  rpc: ProposalRpc,
  userId: string,
  proposal: CoachProposal,
  sourceMessageId: string | null,
  store: "persist_coach_proposal_v1" | "persist_suggested_deload_v1" = "persist_coach_proposal_v1",
): Promise<ProposeResult> {
  const stored = await rpc(store, {
    p_user_id: userId,
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
    p_source_message_id: sourceMessageId,
  });
  if (stored.error) {
    // The rules' deload store refuses, in the same transaction as the store, while another change is
    // waiting for the athlete's answer (it would have been expired by this one).
    if (stored.error.code === "TP001") {
      return {
        ok: false,
        code: "other_proposal_pending",
        reason: "Another change is waiting for your answer. Answer it first.",
      };
    }
    return stored.error.code === "55000" ? storeRefusal(stored.error.message ?? "") : unavailable;
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

const isState = (value: AthleteState | ProposeResult): value is AthleteState => !("ok" in value);

export async function proposeCoachChange(
  rpc: ProposalRpc,
  request: ProposeRequest,
): Promise<ProposeResult> {
  const parsed = parseCoachProposalIntent(request.intent);
  if (!parsed.ok) return refusals.invalidIntent();

  // A break computes no number, so it reads only the athlete's date and their breaks: an incomplete
  // profile never stops it.
  if (parsed.intent.kind === "training_pause") {
    const read = await rpc("get_training_pause_inputs_v1", { p_user_id: request.userId });
    const inputs = read.error ? null : parsePauseInputs(read.data);
    if (inputs === null) return unavailable;
    const intent = keepAthletesNote(parsed.intent, request.athleteMessage);
    if (intent.kind !== "training_pause") return refusals.invalidIntent();
    const built = buildTrainingPause(intent, inputs);
    if (!built.ok) return built;
    return await storeProposal(
      rpc,
      request.userId,
      built.proposal,
      request.sourceMessageId ?? null,
    );
  }

  const state = await readState(rpc, request.userId, request.athleteMessage);
  if (!isState(state)) return state;

  const built = buildCoachProposal(keepAthletesNote(parsed.intent, request.athleteMessage), state);
  if (!built.ok) return built;
  return await storeProposal(rpc, request.userId, built.proposal, request.sourceMessageId ?? null);
}

/**
 * Stores the pending deload the rules suggest (training-proposals). The week is built by the same
 * deterministic builder as a deload Coach proposes; only the reasons come from the rules. It stores
 * a proposal for the athlete to answer and changes nothing else. It uses the rules' own store
 * (persist_suggested_deload_v1), which refuses while another current change waits for an answer.
 */
export async function proposeSuggestedDeload(
  rpc: ProposalRpc,
  request: Readonly<{ userId: string; reasons: readonly DeloadReason[] }>,
): Promise<ProposeResult> {
  if (request.reasons.length === 0) return refusals.noChange("Nothing suggests a lighter week.");
  const state = await readState(rpc, request.userId, "");
  if (!isState(state)) return state;
  const built = buildSuggestedDeload(request.reasons, state);
  if (!built.ok) return built;
  return await storeProposal(
    rpc,
    request.userId,
    built.proposal,
    null,
    "persist_suggested_deload_v1",
  );
}
