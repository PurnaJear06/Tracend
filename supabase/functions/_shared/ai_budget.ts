export type AiBudgetPurpose =
  | "coach_chat"
  | "daily_coaching"
  | "meal_vision"
  | "progress_vision"
  | "onboarding_plan"
  | "onboarding_questions";

/// The gateway's feature names (Contract 1) that `reserve_ai_budget_v2` also
/// accepts. It stores them under today's purposes: daily_decision as
/// daily_coaching, physique_vision as progress_vision, library_context as
/// coach_chat.
export type AiBudgetFeature = "daily_decision" | "physique_vision" | "library_context";

export type AiBudgetRpc = (
  fn: string,
  args: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: unknown }>;

// One request's hold on the AI budget. `reserve` takes a place before a model
// call (`reserve_ai_budget` counts open places alongside recorded usage, so
// parallel calls cannot all pass the limit). `release` gives the places back
// once the call's usage is recorded or no call was made. `keep` leaves them
// open when a call may have been billed with no usage known: they keep
// counting at their ceiling instead of undercounting.
export class AiBudget {
  readonly #rpc: AiBudgetRpc;
  readonly #userId: string;
  #open: string[] = [];

  constructor(rpc: AiBudgetRpc, userId: string) {
    this.#rpc = rpc;
    this.#userId = userId;
  }

  // Without a ceiling the place holds the purpose's fixed ceiling
  // (`reserve_ai_budget`). With one, it holds the route's per-call ceiling
  // (`reserve_ai_budget_v2`: above 0 and at most USD 0.50, or refused).
  reserve(purpose: AiBudgetPurpose): Promise<boolean>;
  reserve(purpose: AiBudgetPurpose | AiBudgetFeature, ceilingUsd: number): Promise<boolean>;
  async reserve(
    purpose: AiBudgetPurpose | AiBudgetFeature,
    ceilingUsd?: number,
  ): Promise<boolean> {
    const { data, error } = ceilingUsd === undefined
      ? await this.#rpc("reserve_ai_budget", {
        target_user_id: this.#userId,
        run_purpose: purpose,
      })
      : await this.#rpc("reserve_ai_budget_v2", {
        target_user_id: this.#userId,
        run_purpose: purpose,
        ceiling_usd: ceilingUsd,
      });
    if (error || typeof data !== "string") return false;
    this.#open.push(data);
    return true;
  }

  keep(): void {
    this.#open = [];
  }

  // Never throws: a reservation left open only counts conservatively.
  async release(): Promise<void> {
    const open = this.#open;
    this.#open = [];
    for (const reservation of open) {
      try {
        await this.#rpc("settle_ai_budget", { reservation_id: reservation });
      } catch {
        // Left open; it keeps counting at its ceiling.
      }
    }
  }
}
