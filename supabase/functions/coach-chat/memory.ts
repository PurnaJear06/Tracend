// Coach chat's use of Coach memory (A10 part 2): whether a conversation is remembered, the fact
// suggestions that follow a reply, and the notes written after it. Nothing here calls a model,
// writes a fact, or changes a reply; a fact is saved only when the athlete confirms a suggestion
// in the app (Architecture 2 and 3).
import type { CoachChatGeneration } from "../_shared/providers/coach_chat_provider.ts";
import type { CoachChatAnswerV2 } from "../_shared/contracts/coach_chat_v1.ts";
import type { MemoryContext } from "../_shared/coach_memory/store.ts";
import {
  mergeSuggestions,
  sanitizeModelSuggestions,
  suggestFromStatement,
  suggestionToWire,
} from "../_shared/coach_memory/suggestions.ts";
import type { TurnForNote } from "../_shared/coach_memory/notes.ts";
import { proposalKinds } from "../_shared/coach_proposals/types.ts";

/**
 * Whether the athlete lets Coach remember a conversation, from a read of its `remember` column
 * (`select remember from coach_threads where id and user_id`). A conversation that cannot be read
 * is treated as not remembered: memory writes nothing it is not sure it may.
 */
export async function threadIsRemembered(
  read: () => PromiseLike<{ data: unknown; error: unknown }>,
): Promise<boolean> {
  try {
    const { data, error } = await read();
    return !error && (data as { remember?: unknown } | null)?.remember === true;
  } catch {
    return false;
  }
}

export type TurnSuggestions = Readonly<{
  /** The suggestions in the shape the app reads (`fact_suggestions` in the response). */
  wire: readonly Record<string, unknown>[];
  /** How many of the model's suggestions the closed vocabulary refused, for the log. */
  dropped: number;
}>;

const none: TurnSuggestions = { wire: [], dropped: 0 };

/**
 * The fact suggestions for one answered turn: the athlete's own statements read by rules, then
 * whatever the model suggested that fits the closed vocabulary. None for a conversation that is
 * not remembered, a referral, or when the athlete's facts could not be read (a suggestion made
 * without them could repeat or contradict a saved fact).
 */
export function suggestionsForTurn(
  input: Readonly<{
    remembered: boolean;
    referral: boolean;
    question: string;
    memory: MemoryContext | null;
    modelSuggestions: unknown;
  }>,
): TurnSuggestions {
  if (!input.remembered || input.referral || input.memory === null) return none;
  const facts = input.memory.facts;
  const checked = sanitizeModelSuggestions(input.modelSuggestions, facts);
  const merged = mergeSuggestions(
    suggestFromStatement(input.question, facts),
    checked.suggestions,
  );
  return { wire: merged.map(suggestionToWire), dropped: checked.dropped };
}

/** What a stored reply tells the note builder. */
export function turnForNote(
  input: Readonly<{
    question: string;
    localDate: string;
    threadId: string;
    remembered: boolean;
    generation: CoachChatGeneration;
    answer: CoachChatAnswerV2;
    proposalIntent: unknown;
    proposed: boolean;
    userMessageId: unknown;
    assistantMessageId: unknown;
  }>,
): TurnForNote {
  const kind = (input.proposalIntent as { kind?: unknown } | undefined)?.kind;
  const messageIds = [input.userMessageId, input.assistantMessageId].filter(
    (id): id is string => typeof id === "string",
  );
  return {
    question: input.question,
    localDate: input.localDate,
    threadId: input.threadId,
    remember: input.remembered,
    outcome: input.generation.safety !== undefined || input.answer.safety_state === "refused"
      ? "referral"
      : "answered",
    evidenceCodes: input.answer.evidence.map((item) => item.code),
    lookups: (input.generation.lookups ?? []).map((item) => item.lookup),
    proposalKind: input.proposed && typeof kind === "string" &&
        (proposalKinds as readonly string[]).includes(kind)
      ? kind
      : null,
    messageIds,
  };
}

/** How long a reply waits for its notes before it goes out without knowing how they went. */
export const memoryWriteWaitMs = 2_000;

type EdgeRuntimeGlobal = { EdgeRuntime?: { waitUntil(work: Promise<unknown>): void } };

/**
 * Waits for work for at most `ms`. The work carries on after that: the Edge runtime is asked to
 * keep the function alive until it finishes.
 */
export async function waitBriefly<T>(work: Promise<T>, ms: number): Promise<T | "pending"> {
  (globalThis as EdgeRuntimeGlobal).EdgeRuntime?.waitUntil(work);
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      work,
      new Promise<"pending">((resolve) => {
        timer = setTimeout(() => resolve("pending"), ms);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
