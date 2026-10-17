// A fresh-key retry of a failed message. The server saves a question when its turn starts, so a
// turn that failed (or was lost) leaves its question in the thread; when the app sends the same
// text again under a new key, the thread and the model context would hold the question twice.
// The failed attempt's question is dropped from the model's context and marked superseded
// (`safety_state` = "unavailable" on that user row, the existing column that says a message got
// no valid reply), and the retry stands in for it. An attempt that was answered by the model
// stays: the athlete really asked twice.

export const supersededSafetyState = "unavailable";

type Message = Readonly<{ role?: unknown; content?: unknown }>;

/**
 * Indexes of user messages in `recent` that repeat `question` and got no reply: the next message
 * is not an assistant message. A labelled data summary is never in the context's memory, so a
 * question that fell back to one reads as unanswered here.
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
    if (next?.role !== "assistant") found.push(index);
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

/** What the retry needs from the database; the handler builds it from the service client. */
export type AttemptStore = Readonly<{
  /** The athlete's earlier user messages in this thread with the same text, other keys, not yet superseded. */
  copies(): Promise<readonly Readonly<{ id: string; key: string }>[]>;
  /** What the first attempt under `key` produced (coach_chat_turn). */
  turn(key: string): Promise<
    Readonly<{ state?: string; message?: Readonly<{ answer_source?: unknown }> | null }> | null
  >;
  mark(ids: readonly string[]): Promise<void>;
}>;

/**
 * Marks the failed or lost earlier attempts of this question as superseded; returns how many.
 * An attempt the model answered, or one whose state cannot be read, is left alone.
 */
export async function supersedeFailedAttempts(store: AttemptStore): Promise<number> {
  const marked: string[] = [];
  for (const copy of await store.copies()) {
    const turn = await store.turn(copy.key);
    if (!turn) continue;
    const answeredByModel = turn.state === "answered" &&
      turn.message?.answer_source !== "data_summary";
    if (!answeredByModel) marked.push(copy.id);
  }
  if (marked.length > 0) await store.mark(marked);
  return marked.length;
}
