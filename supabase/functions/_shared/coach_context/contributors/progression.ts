// Contract 7 contributor: where the athlete's lifts are heading. It reads the next-session targets
// that the database computes from the sets the athlete logged (get_progression_summary_v1, service
// role) and renders them for Coach as reference data. Coach explains these numbers; it never sets
// or changes them, and heart rate plays no part in them (decision D9). Not registered in
// registry.ts yet: the lead registers it in round 3.
import {
  describeTarget,
  parseProgressionSummary,
  type ProgressionTarget,
} from "../../training/progression/targets.ts";
import type { CoachContextContributor } from "../host.ts";

/** Reads the progression summary payload for a user (the service-role RPC). */
export type ProgressionSource = (userId: string) => Promise<unknown>;

/** The RPC call the source makes, typed structurally so any Supabase client fits. */
export type ProgressionRpc = (
  name: "get_progression_summary_v1",
  params: { p_user_id: string },
) => PromiseLike<{ data: unknown; error: unknown }>;

export function progressionSourceFromRpc(rpc: ProgressionRpc): ProgressionSource {
  return async (userId) => {
    const { data, error } = await rpc("get_progression_summary_v1", { p_user_id: userId });
    if (error) throw new Error("progression summary unavailable");
    return data;
  };
}

export const progressionContributorBudgetChars = 2_400;

const mostTargets = 12;

const header = "Next-session targets Tracend computed from the sets the athlete logged " +
  "(weight, reps, reps in reserve; never heart rate). Explain them; do not change them:";

/** The text for these targets, or null without any. Exposed for tests. */
export function renderProgressionTargets(targets: readonly ProgressionTarget[]): string | null {
  if (targets.length === 0) return null;
  const shown = targets.slice(0, mostTargets);
  const omitted = targets.length - shown.length;
  const lines = shown.map((item) => `- ${describeTarget(item)}`);
  if (omitted > 0) lines.push(`- ${omitted} more exercises have targets.`);
  return `${header}\n${lines.join("\n")}`;
}

export function createProgressionContributor(source: ProgressionSource): CoachContextContributor {
  return {
    id: "progression",
    slot: "volatile",
    budgetChars: progressionContributorBudgetChars,
    async render(input) {
      return renderProgressionTargets(parseProgressionSummary(await source(input.userId)));
    },
  };
}
