import type { CoachContextContributor } from "./host.ts";
import { goalPhaseContributor } from "./contributors/goal_phase.ts";
import { screeningContributor } from "./contributors/screening.ts";

// The contributors Coach chat renders, in their fixed order (Contract 7). A9 (screening) and B7
// (goal phase) are registered; E3 (research library), C3 (heart-rate profile) and B3
// (progression) add theirs. Order is part of the prompt: a stable contributor placed before
// another keeps the cached prefix of the ones before it, so the screening, which changes only
// when the athlete answers the health check again, comes first.
export const coachContextContributors: readonly CoachContextContributor[] = Object.freeze([
  screeningContributor,
  goalPhaseContributor,
]);
