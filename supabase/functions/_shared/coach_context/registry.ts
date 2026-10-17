import type { CoachContextContributor } from "./host.ts";
import { goalPhaseContributor } from "./contributors/goal_phase.ts";

// The contributors Coach chat renders, in their fixed order (Contract 7). B7 (goal phase) is
// registered; E3 (research library), C3 (heart-rate profile) and B3 (progression) add theirs. Order is part of the prompt:
// a stable contributor placed before another keeps the cached prefix of the ones before it.
export const coachContextContributors: readonly CoachContextContributor[] = Object.freeze([
  goalPhaseContributor,
]);
