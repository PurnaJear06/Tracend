export type AiBudgetPurpose =
  | "coach_chat"
  | "daily_coaching"
  | "meal_vision"
  | "progress_vision"
  | "onboarding_plan"
  | "onboarding_questions";

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

  async reserve(purpose: AiBudgetPurpose): Promise<boolean> {
    const { data, error } = await this.#rpc("reserve_ai_budget", {
      target_user_id: this.#userId,
      run_purpose: purpose,
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
