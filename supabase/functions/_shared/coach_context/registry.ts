import type { CoachContextContributor } from "./host.ts";
import { goalPhaseContributor } from "./contributors/goal_phase.ts";
import { screeningContributor } from "./contributors/screening.ts";
import { trainingPlanContributor } from "./contributors/training_plan.ts";
import { nutritionStateContributor } from "./contributors/nutrition_state.ts";
import { proposalsContributor } from "./contributors/proposals.ts";
import { dataIndexContributor, dataIndexContributorId } from "./contributors/data_index.ts";
import { coachingPrinciplesContributor } from "../library/principles.ts";

// The contributors Coach chat renders, in their fixed order (Contract 7). The coaching principles
// digest (E2), the screening (A9), the goal phase (B7), the plan (A10: today's or the next session
// with targets and home alternatives), the week's nutrition (A10), the proposals and phases (A8) and the index of what Coach can
// look up (A10) are registered; E3 (retrieval) and C3 (heart-rate profile) add theirs. Everything
// else the athlete's records hold comes from lookups on demand (coach_lookups/). Order is part of
// the prompt: a stable contributor placed before another keeps the cached prefix of the ones
// before it, so the fixed digest comes first, then the screening, which changes only when the
// athlete answers the health check again.
export const coachContextContributors: readonly CoachContextContributor[] = Object.freeze([
  coachingPrinciplesContributor,
  screeningContributor,
  goalPhaseContributor,
  trainingPlanContributor,
  nutritionStateContributor,
  proposalsContributor,
  dataIndexContributor,
]);

/**
 * The contributors for a turn. The data index invites the model to ask for lookups, which exist
 * only on the gateway route; today's DeepSeek path has no `data_requests`, so it renders without
 * the index.
 */
export function coachContextContributorsFor(
  gatewayRoute: boolean,
): readonly CoachContextContributor[] {
  return gatewayRoute
    ? coachContextContributors
    : coachContextContributors.filter((contributor) => contributor.id !== dataIndexContributorId);
}
