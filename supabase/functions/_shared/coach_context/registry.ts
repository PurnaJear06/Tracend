import type { CoachContextContributor } from "./host.ts";
import { goalPhaseContributor } from "./contributors/goal_phase.ts";
import { screeningContributor } from "./contributors/screening.ts";
import { trainingPlanContributor } from "./contributors/training_plan.ts";
import { nutritionStateContributor } from "./contributors/nutrition_state.ts";
import { proposalsContributor } from "./contributors/proposals.ts";
import {
  coverageBriefContributor,
  coverageBriefContributorId,
} from "./contributors/coverage_brief.ts";
import { readinessContributor } from "./contributors/readiness.ts";
import { watchOutsContributor } from "./contributors/watch_outs.ts";
import { heartRateContributor } from "./contributors/heart_rate.ts";
import { confirmedFactsContributor } from "./contributors/confirmed_facts.ts";
import { coachNotesContributor } from "./contributors/coach_notes.ts";
import { coachingPrinciplesContributor } from "../library/principles.ts";
import { libraryContributor } from "../library/live.ts";
import { libraryContributorId } from "../library/retrieval.ts";

// The contributors Coach chat renders, in their fixed order (Contract 7). The coaching principles
// digest (E2), the screening (A9), the goal phase (B7), the plan (A10: today's or the next session
// with targets and home alternatives), the week's nutrition (A10), the proposals and phases (A8) and the index of what Coach can
// look up and how fresh each kind is (the Coverage Brief) are registered, with today's readiness card
// (B4/B5: band, adjustment, safety route and joint areas, read-only, right after the plan), the watch-outs (the facts
// computed across several kinds of record), the heart-rate profile (C3), the athlete's confirmed facts
// (A10 part 2, stable: they change only when the athlete changes them), the Coach's own notes
// (A10 part 2, untrusted and capped) and the library (E3: the chunks found for this turn's
// question). Precedence when they disagree: Tracend's calculations, then the confirmed facts,
// then the athlete's recent statements, then the Coach's notes, then the library. Everything else the athlete's records hold comes from lookups
// on demand (coach_lookups/). Order is part of the prompt: a stable contributor placed before
// another keeps the cached prefix of the ones before it, so the fixed digest comes first, then the
// screening, which changes only when the athlete answers the health check again. The library is
// last: what changes every turn comes after what is steadier, just before the question.
export const coachContextContributors: readonly CoachContextContributor[] = Object.freeze([
  coachingPrinciplesContributor,
  screeningContributor,
  confirmedFactsContributor,
  goalPhaseContributor,
  trainingPlanContributor,
  readinessContributor,
  nutritionStateContributor,
  proposalsContributor,
  heartRateContributor,
  coachNotesContributor,
  watchOutsContributor,
  coverageBriefContributor,
  libraryContributor,
]);

// Contributors that exist only on the gateway route. The Coverage Brief invites the model to ask
// for lookups and the library asks it to cite sources; today's DeepSeek path (the rollback route,
// still reachable while its settings are kept) has no `data_requests` and no library evidence, so it
// renders without them. The watch-outs state facts and need neither, so the rollback path keeps
// them: it is where the back-to-back muscles fact would otherwise be lost.
const gatewayOnly: readonly string[] = [coverageBriefContributorId, libraryContributorId];

/** The contributors for a turn: all of them on the gateway route, the rest on the legacy path. */
export function coachContextContributorsFor(
  gatewayRoute: boolean,
): readonly CoachContextContributor[] {
  return gatewayRoute
    ? coachContextContributors
    : coachContextContributors.filter((contributor) => !gatewayOnly.includes(contributor.id));
}
