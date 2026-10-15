import { AiBudget, type AiBudgetRpc } from "../_shared/ai_budget.ts";
import type { CoachChatAttemptBudget } from "../_shared/providers/coach_chat_provider_gateway.ts";
import {
  type CoachChatAttempt,
  CoachChatUnavailableError,
} from "../_shared/providers/coach_chat_provider.ts";

/**
 * The budget places one Coach chat request holds. The legacy path holds one (the purpose's fixed
 * ceiling). The gateway path holds one per attempt, each at that attempt's worst case, so no
 * request is sent without a place that covers it. Each place is its own `AiBudget`, so one can
 * stay open (`keepAttempt`) while the others are given back.
 *
 * Nothing is given back while a turn runs: the first attempt's place keeps counting while a
 * repair is reserved (its real cost is recorded only when the turn ends), which can only
 * over-count. `release` settles every place that was not kept.
 */
export class CoachChatBudgetLedger {
  readonly #rpc: AiBudgetRpc;
  readonly #userId: string;
  readonly #places: { attempt: CoachChatAttempt; budget: AiBudget }[] = [];

  constructor(rpc: AiBudgetRpc, userId: string) {
    this.#rpc = rpc;
    this.#userId = userId;
  }

  /** Today's single place at the purpose's fixed ceiling. */
  reserveLegacy(): Promise<boolean> {
    return this.#take("initial", (budget) => budget.reserve("coach_chat"));
  }

  /** The first attempt's place at its worst case. */
  reserveInitial(ceilingUsd: number): Promise<boolean> {
    return this.#take("initial", (budget) => budget.reserve("coach_chat", ceilingUsd));
  }

  /** The repair's place, taken before the repair is sent. */
  reserveRepair(ceilingUsd: number): Promise<boolean> {
    return this.#take("repair", (budget) => budget.reserve("coach_chat", ceilingUsd));
  }

  /** The gateway path's view of the ledger. */
  get attemptBudget(): CoachChatAttemptBudget {
    return {
      reserveRepair: (usd) => this.reserveRepair(usd),
      inFlight: (attempt) => this.keepAttempt(attempt),
    };
  }

  async #take(
    attempt: CoachChatAttempt,
    reserve: (budget: AiBudget) => Promise<boolean>,
  ): Promise<boolean> {
    const budget = new AiBudget(this.#rpc, this.#userId);
    if (!await reserve(budget)) return false;
    this.#places.push({ attempt, budget });
    return true;
  }

  /** A request of this attempt may have been billed with no usage known: its place stays open. */
  keepAttempt(attempt: CoachChatAttempt): void {
    for (const place of this.#places) if (place.attempt === attempt) place.budget.keep();
  }

  /** Every place stays open, as when the turn's cost could not be recorded. */
  keepAll(): void {
    for (const place of this.#places) place.budget.keep();
  }

  /** Gives back every place that was not kept. Never throws. */
  async release(): Promise<void> {
    for (const place of this.#places) await place.budget.release();
  }
}

/**
 * Which places a failed turn keeps open. The legacy path keeps its single place for a timeout
 * or a failure that was not the provider's own answer, as before. The gateway path keeps only
 * what the provider reported in flight (`inFlight`): a failure before anything was sent, or one
 * whose cost is recorded, is settled. A failure that was not a provider outcome keeps all.
 */
export function keepAfterFailure(
  ledger: CoachChatBudgetLedger,
  error: unknown,
  gateway: boolean,
): void {
  if (!(error instanceof CoachChatUnavailableError)) {
    ledger.keepAll();
  } else if (!gateway && error.failureReason === "provider_timeout") {
    ledger.keepAll();
  }
}
