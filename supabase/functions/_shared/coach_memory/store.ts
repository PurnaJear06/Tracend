// The database side of Coach memory, as service-role RPC calls: what the Coach contributors read,
// the notes written after a reply, and the follow-through checks. Everything here fails soft. A
// memory that cannot be read leaves that section out of the turn; a note that cannot be written is
// skipped; neither ever stops or changes a reply. Nothing in this file calls a model, and nothing
// it logs holds an athlete's words.
import type { ServiceRpc } from "../coach_context/service_source.ts";
import { type CoachFact, parseFacts } from "./facts.ts";
import {
  buildAdviceNote,
  buildConversationNote,
  type CoachNote,
  type CoachNoteDraft,
  evaluateFollowThrough,
  parseFollowThroughChecks,
  parseNotes,
  parseResolvedProposals,
  type TurnForNote,
} from "./notes.ts";

export type MemoryContext = Readonly<{
  localDate: string;
  facts: readonly CoachFact[];
  notes: readonly CoachNote[];
}>;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};

export function parseMemoryContext(payload: unknown): MemoryContext | null {
  const body = rec(payload);
  const localDate = typeof body.local_date === "string" ? body.local_date.slice(0, 10) : "";
  if (typeof body.schema_version !== "string" || !body.schema_version.startsWith("1.")) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(localDate)) return null;
  return { localDate, facts: parseFacts(body.facts), notes: parseNotes(body.notes) };
}

/** The athlete's active facts and unexpired notes, or null when they cannot be read. */
export async function loadMemoryContext(
  rpc: ServiceRpc,
  userId: string,
): Promise<MemoryContext | null> {
  try {
    const { data, error } = await rpc("get_coach_memory_context_v1", { p_user_id: userId });
    return error ? null : parseMemoryContext(data);
  } catch {
    return null;
  }
}

export type NoteWrite = "stored" | "not_remembered" | "already_noted" | "failed";

/** Stores one note. The database refuses a conversation that is not remembered. */
export async function persistNote(
  rpc: ServiceRpc,
  userId: string,
  draft: CoachNoteDraft,
): Promise<NoteWrite> {
  try {
    const { data, error } = await rpc("persist_coach_note_v1", {
      p_user_id: userId,
      p_thread_id: draft.threadId,
      p_entry_kind: draft.entryKind,
      p_note_date: draft.noteDate,
      p_summary: draft.summary,
      p_topics: draft.topics,
      p_concerns: draft.concerns,
      p_advice: draft.advice,
      p_commitments: draft.commitments,
      p_message_ids: draft.messageIds,
      p_proposal_id: draft.proposalId,
    });
    if (error) return "failed";
    const result = rec(data);
    if (result.stored === true) return "stored";
    return result.reason === "not_remembered" ? "not_remembered" : "already_noted";
  } catch {
    return "failed";
  }
}

export type MemoryWriteReport = Readonly<{
  /** The note for the turn itself. */
  conversation: NoteWrite | "none";
  /** Notes written for proposals the athlete has answered since the last turn. */
  advice: number;
  /** Follow-through checks recorded on earlier notes. */
  checked: number;
  /** Writes that failed, for the turn's log. */
  failed: number;
}>;

const skipped: MemoryWriteReport = { conversation: "none", advice: 0, checked: 0, failed: 0 };

/**
 * Everything memory writes after a reply, in one place:
 *   1. the turn's own note, built from the athlete's message and the turn's structured fields;
 *   2. an "advice and follow-through" note for each proposal answered since the last turn;
 *   3. follow-through on earlier notes whose week has passed.
 * A conversation the athlete asked not to have remembered, a referral and a data summary write
 * nothing at all. No call here can throw; the reply never waits on a failure.
 */
export async function recordMemoryAfterTurn(
  rpc: ServiceRpc,
  input: Readonly<{ userId: string; turn: TurnForNote }>,
): Promise<MemoryWriteReport> {
  const { userId, turn } = input;
  if (!turn.remember || turn.outcome !== "answered") return skipped;
  let failed = 0;

  const draft = buildConversationNote(turn);
  const conversation = draft ? await persistNote(rpc, userId, draft) : "none";
  if (conversation === "failed") failed++;

  let advice = 0;
  try {
    const { data, error } = await rpc("get_unnoted_coach_proposals_v1", {
      p_user_id: userId,
      p_limit: 5,
    });
    if (error) failed++;
    else {
      for (const proposal of parseResolvedProposals(data)) {
        const written = await persistNote(rpc, userId, buildAdviceNote(proposal));
        if (written === "stored") advice++;
        else if (written === "failed") failed++;
      }
    }
  } catch {
    failed++;
  }

  let checked = 0;
  try {
    const { data, error } = await rpc("get_coach_follow_through_inputs_v1", {
      p_user_id: userId,
      p_today: turn.localDate,
    });
    if (error) failed++;
    else {
      for (const check of parseFollowThroughChecks(data)) {
        const result = evaluateFollowThrough(check, turn.localDate);
        const recorded = await rpc("record_coach_note_follow_through_v1", {
          p_user_id: userId,
          p_note_id: check.noteId,
          p_status: result.status,
          p_checked_on: result.checkedOn,
          p_detail: result.detail,
        });
        if (recorded.error) failed++;
        else checked++;
      }
    }
  } catch {
    failed++;
  }
  return { conversation, advice, checked, failed };
}
