// Contract 7 contributor: where the athlete stands in the current goal phase. It reads the weight
// readings and the active goal (get_goal_phase_inputs_v1, service role), computes the phase
// summary and review with deterministic code, and renders them for Coach as reference data. Coach
// explains the outcome; it never sets it, and it never sets the athlete's target.
import {
  parseGoalPhaseInputs,
  renderGoalPhase,
  reviewGoalPhase,
  summarizeGoalPhase,
} from "../../training/goal_phase/index.ts";
import type { CoachContextContributor } from "../host.ts";
import { coachServiceRpc } from "../service_source.ts";

/** Reads the goal phase inputs payload for a user (the service-role RPC). */
export type GoalPhaseSource = (userId: string) => Promise<unknown>;

/** The RPC call the source makes, typed structurally so any Supabase client fits. */
export type GoalPhaseRpc = (
  name: "get_goal_phase_inputs_v1",
  params: { p_user_id: string },
) => PromiseLike<{ data: unknown; error: unknown }>;

export function goalPhaseSourceFromRpc(rpc: GoalPhaseRpc): GoalPhaseSource {
  return async (userId) => {
    const { data, error } = await rpc("get_goal_phase_inputs_v1", { p_user_id: userId });
    if (error) throw new Error("goal phase inputs unavailable");
    return data;
  };
}

/** The source for Edge Functions: the shared service-role caller (coach_context/service_source.ts). */
export function serviceRoleGoalPhaseSource(): GoalPhaseSource {
  return goalPhaseSourceFromRpc((name, params) => coachServiceRpc(name, params));
}

export const goalPhaseContributorBudgetChars = 2_200;

/** The text for one payload, or null without an active goal. Exposed for tests. */
export function renderGoalPhasePayload(payload: unknown, localDate: string): string | null {
  const inputs = parseGoalPhaseInputs(payload, localDate);
  const summary = summarizeGoalPhase(inputs);
  return renderGoalPhase(summary, reviewGoalPhase(summary));
}

export function createGoalPhaseContributor(source: GoalPhaseSource): CoachContextContributor {
  return {
    id: "goal_phase",
    slot: "volatile",
    budgetChars: goalPhaseContributorBudgetChars,
    async render(input) {
      return renderGoalPhasePayload(await source(input.userId), input.localDate);
    },
  };
}

export const goalPhaseContributor: CoachContextContributor = createGoalPhaseContributor(
  serviceRoleGoalPhaseSource(),
);
