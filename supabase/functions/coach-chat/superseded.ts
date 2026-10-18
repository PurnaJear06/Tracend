// A fresh-key retry of a failed message. The server saves a question when its turn starts, so a
// turn that failed (or was lost) leaves its question in the thread; when the app sends the same
// text again under a new key, the thread and the model context would hold the question twice.
// The failed attempt's question is dropped from the model's context and marked superseded
// (`safety_state` = "unavailable" on that user row, the existing column that says a message got
// no valid reply), and the retry stands in for it. An attempt that was answered by the model
// stays: the athlete really asked twice.

export const supersededSafetyState = "unavailable";

// A turn that has neither an answer nor a failure was started by a request that is still running
// or was lost (the function was cut off). A running request ends at the Edge Function's wall-clock
// limit at the latest, so a turn still open longer than that after its question was saved is lost.
// Supabase documents the limit as 150 seconds on the free plan and 400 seconds on paid plans
// (https://supabase.com/docs/guides/functions/limits, "Maximum duration (wall-clock limit)"), and
// the gateway's route timeouts are capped at 150 seconds for the same reason (ai/routes.ts);
// supabase/config.toml sets no per-function timeout. The longest limit is used, so a turn that is
// still running is never taken for lost, plus a margin for clock differences and for the work
// around the request. The replay answer (`turn_lost`) and superseding a failed attempt both use
// this rule.
export const edgeFunctionWallClockMs = 400_000;
export const coachChatTurnStaleAfterMs = edgeFunctionWallClockMs + 30_000;

/** How long ago a saved question was created, or null when it cannot be told. */
export function questionAgeMs(createdAt: unknown, now: number = Date.now()): number | null {
  const created = typeof createdAt === "string" ? Date.parse(createdAt) : NaN;
  return Number.isNaN(created) ? null : now - created;
}

type Message = Readonly<{ role?: unknown; content?: unknown; answer_source?: unknown }>;

/**
 * Indexes of user messages in `recent` that repeat `question` and got no reply: the next message
 * is not an assistant message. The app's labelled data summary (`answer_source: "data_summary"`)
 * is in the context's memory, marked, but it is not Coach's reply, so a question that fell back to
 * one still reads as unanswered here.
 */
export function unansweredCopies(recent: unknown, question: string): number[] {
  if (!Array.isArray(recent)) return [];
  const wanted = question.trim();
  const found: number[] = [];
  recent.forEach((item, index) => {
    const message = (item && typeof item === "object" ? item : {}) as Message;
    if (message.role !== "user" || typeof message.content !== "string") return;
    if (message.content.trim() !== wanted) return;
    const next = recent[index + 1] as Message | undefined;
    if (next?.role !== "assistant" || next.answer_source === "data_summary") found.push(index);
  });
  return found;
}

/** The context's memory without the unanswered copies of the question being asked again. */
export function withoutSupersededQuestions(
  context: Record<string, unknown>,
  question: string,
): { context: Record<string, unknown>; dropped: number } {
  const copies = unansweredCopies(context.recent_messages, question);
  if (copies.length === 0) return { context, dropped: 0 };
  const recent = (context.recent_messages as unknown[]).filter((_, index) =>
    !copies.includes(index)
  );
  return { context: { ...context, recent_messages: recent }, dropped: copies.length };
}

/** A stored user message of the thread, as the retry reads it. */
export type StoredQuestion = Readonly<{
  id?: unknown;
  idempotency_key?: unknown;
  content?: unknown;
  safety_state?: unknown;
  created_at?: unknown;
}>;

export type EarlierAttempt = Readonly<{ id: string; key: string; createdAt: string | null }>;

/**
 * The earlier attempts at this question among a thread's stored user messages: the same text once
 * trimmed (a row may be stored untrimmed), under another key, not already superseded. The state
 * is read in code, not in a query: in SQL `safety_state <> 'unavailable'` drops the rows where it
 * is NULL, which is how user messages are normally stored.
 */
export function earlierAttempts(
  rows: readonly StoredQuestion[],
  question: string,
  currentKey: string,
): EarlierAttempt[] {
  const wanted = question.trim();
  const found: EarlierAttempt[] = [];
  for (const row of rows) {
    if (typeof row.id !== "string" || typeof row.idempotency_key !== "string") continue;
    if (row.idempotency_key === currentKey) continue;
    if (typeof row.content !== "string" || row.content.trim() !== wanted) continue;
    if (row.safety_state === supersededSafetyState) continue;
    found.push({
      id: row.id,
      key: row.idempotency_key,
      createdAt: typeof row.created_at === "string" ? row.created_at : null,
    });
  }
  return found;
}

/**
 * The model's memory without superseded questions, on every turn (frozen v8 builds the memory
 * from the thread, so a failed attempt's question keeps coming back on later turns). A message
 * that carries `safety_state: "unavailable"` is dropped, if the context carries it. The context's
 * memory entries are only role and content, so otherwise a user message that is immediately
 * followed by an identical user message is dropped: the first of the two never got a reply.
 */
export function withoutSupersededMemory(context: Record<string, unknown>): Record<string, unknown> {
  let cleaned = context;
  for (const key of ["recent_messages", "recent_other_conversations"]) {
    const list = context[key];
    if (!Array.isArray(list)) continue;
    const kept = list.filter((item, index) => {
      const message = (item && typeof item === "object" ? item : {}) as Message & {
        safety_state?: unknown;
      };
      if (message.safety_state === supersededSafetyState) return false;
      const next = list[index + 1] as Message | undefined;
      return !(message.role === "user" && next?.role === "user" &&
        typeof message.content === "string" && typeof next.content === "string" &&
        message.content.trim() === next.content.trim());
    });
    if (kept.length !== list.length) cleaned = { ...cleaned, [key]: kept };
  }
  return cleaned;
}

/** What the retry needs from the database; the handler builds it from the service client. */
export type AttemptStore = Readonly<{
  /** The earlier attempts at this question (see `earlierAttempts`). */
  copies(): Promise<readonly EarlierAttempt[]>;
  /** What the first attempt under `key` produced (coach_chat_turn). */
  turn(key: string): Promise<
    Readonly<{ state?: string; message?: Readonly<{ answer_source?: unknown }> | null }> | null
  >;
  mark(ids: readonly string[]): Promise<void>;
}>;

/**
 * Marks the failed or lost earlier attempts of this question as superseded; returns how many.
 * Only the user's question is marked. An attempt's reply exists only when its state is "answered":
 * a labelled data summary, which is stored with `safety_state` "unavailable" already, or a model
 * answer, which is never superseded. A turn with no reply (failed, lost) has nothing to mark. So
 * `unavailable` cannot tell an orphaned summary from a live one by itself; hiding the summary of
 * a superseded attempt is the reader's rule (hide a data summary that follows a hidden question).
 * An attempt the model answered, one still running, or one whose state or age cannot be read, is
 * left alone.
 */
export async function supersedeFailedAttempts(
  store: AttemptStore,
  now: number = Date.now(),
): Promise<number> {
  const marked: string[] = [];
  for (const copy of await store.copies()) {
    const turn = await store.turn(copy.key);
    if (!turn) continue;
    if (turn.state === "answered") {
      if (turn.message?.answer_source === "data_summary") marked.push(copy.id);
      continue;
    }
    // Still open: a live request (a double tap, a client timeout) keeps its question; only a lost
    // turn, older than the function's time limit plus a margin, is replaced.
    if (turn.state === "in_progress") {
      const age = questionAgeMs(copy.createdAt, now);
      if (age === null || age <= coachChatTurnStaleAfterMs) continue;
    }
    marked.push(copy.id);
  }
  if (marked.length > 0) await store.mark(marked);
  return marked.length;
}
