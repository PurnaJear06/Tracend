import { screenMessage } from "../coach_safety/red_flags.ts";

// The text Coach chat searches the library with (chunk E3). It is the athlete's question, except
// that a follow-up ("And on rest days?", "Is that enough?") has no topic of its own, so the
// topic of their last real question is added. This is deterministic on purpose: no model call
// decides what the library is searched for, and the same turn always searches the same text.

// Words that carry no topic. Postgres drops its own English stop words from the full-text query as
// well; this list is for deciding whether a question has a topic of its own.
const stopWords: ReadonlySet<string> = new Set(
  ("a an the and or but if so then than that this these those it its it's is are was were be been " +
    "am do does did done have has had i me my we our you your he she they them their there here " +
    "what which who whom whose when where why how can could should would will shall may might must " +
    "of to in on at by for with about as from into over under up down out off not no yes ok okay " +
    "just also too very really much many more most less some any all each every other another " +
    "get got go going want need please tell " +
    // Vague words that name no topic: "How often?" and "Is that enough?" depend on an earlier question.
    "often long enough better worse best good bad safe fine true sure anything something " +
    "everything thing things time times way ways work works help helps matter matters mean means")
    .split(
      " ",
    ),
);

// Words that point back at the earlier question. A lead ("And ...", "What about ...") or a
// demonstrative ("that", "this") does so even in a question of a few words. A bare pronoun ("it",
// "them") usually refers to something inside the same question ("how do I use it"), so it counts
// only when almost nothing else is said.
const pointsBackStrongly = new RegExp(
  String
    .raw`^\s*(?:and|but|so|also|then|what about|how about|what if|what else)\b|` +
    String.raw`\b(?:that|this|those|these|there|same|instead|else|again)\b`,
  "i",
);
const pointsBackWeakly = /\b(?:it|them|they)\b/i;

/** The words of a text that carry a topic: letters and digits, two or more, no stop words. */
export function topicTerms(text: string): string[] {
  return (text.toLowerCase().match(/[a-z0-9]+/g) ?? []).filter((word) =>
    word.length >= 2 && !stopWords.has(word)
  );
}

/**
 * Whether the question depends on an earlier one: it has no topic word at all, or only a few and
 * points back ("that", "it", "what about", "and ...").
 */
export function isFollowUp(question: string): boolean {
  const terms = topicTerms(question);
  return terms.length === 0 ||
    (terms.length <= 4 && pointsBackStrongly.test(question)) ||
    (terms.length <= 2 && pointsBackWeakly.test(question));
}

export type RetrievalQuery = Readonly<{
  /** The text to embed and to search. */
  text: string;
  /** True when the previous question's topic was added. */
  rewritten: boolean;
}>;

/** Longest question and earlier question the query keeps, so the whole stays well under 1,000. */
export const maxQuestionChars = 400;
export const maxTopicChars = 300;

/**
 * The query for a question. `previousQuestions` are the athlete's own earlier questions, newest
 * first. A follow-up borrows the topic of the newest earlier question that has one of its own (a
 * chain of follow-ups goes back to the question that started it); with nothing to borrow, the
 * question is searched as it stands.
 */
export function libraryRetrievalQuery(
  question: string,
  previousQuestions: readonly string[],
): RetrievalQuery {
  const own = question.trim().slice(0, maxQuestionChars);
  if (!isFollowUp(question)) return { text: own, rewritten: false };
  // A question that reported a symptom is answered by the fixed referral and never lends its words
  // to the next search.
  const earlier = previousQuestions.map((text) => text.trim()).filter((text) =>
    text !== "" && screenMessage(text) === null
  );
  const anchor = earlier.find((text) => !isFollowUp(text)) ?? earlier[0];
  if (anchor === undefined) return { text: own, rewritten: false };
  return { text: `${own} ${anchor.slice(0, maxTopicChars)}`, rewritten: true };
}

/**
 * The athlete's earlier questions in this conversation, newest first, from the prepared context
 * (its messages run oldest first). The current question is left out when the context already
 * holds a copy of it (a retry).
 */
export function previousQuestionsOf(
  context: Record<string, unknown>,
  question: string,
  limit = 3,
): string[] {
  const messages = Array.isArray(context.recent_messages) ? context.recent_messages : [];
  const asked: string[] = [];
  for (const message of messages) {
    const entry = message as { role?: unknown; content?: unknown } | null;
    if (entry?.role === "user" && typeof entry.content === "string") asked.push(entry.content);
  }
  return asked.reverse().filter((text) => text.trim() !== question.trim()).slice(0, limit);
}
