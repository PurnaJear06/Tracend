// Training content for a proposal comes from the same rules plan onboarding falls back to
// (onboarding/rules_plan.ts, templates from B2, the coaching standard from B1), validated against
// the same policy. A proposal therefore never carries a session the standard would refuse.
import { exerciseCatalogV1 } from "../onboarding/catalog.ts";
import type { OnboardingAnswers } from "../onboarding/answers.ts";
import {
  OnboardingPlanInfeasibleError,
  policiesFor,
  validRulesPlan,
} from "../onboarding/generate.ts";
import { buildOnboardingProposal } from "../onboarding/plan_contract.ts";
import { capsEffortToModerate } from "../training/screening/outcome.ts";
import { isoWeekday } from "./common.ts";
import { answersFromState } from "./common.ts";
import { refusals } from "./refusals.ts";
import type { AthleteState, BuildResult, StatePlan, TrainingPayloadWorkout } from "./types.ts";

/**
 * Weight does not enter the training policy and the nutrition half of the policies built here is
 * never read, so a plan is built even for an athlete without a recent weighing. The value only
 * fills the answers' required field.
 */
const trainingOnlyWeightKg = 75;

export type RulesTraining = Readonly<{
  title: string;
  blockWeeks: number;
  workouts: readonly TrainingPayloadWorkout[];
}>;

/** The rules plan for the athlete's state with some answers changed; a refusal when none fits. */
export function rulesTraining(
  state: AthleteState,
  overrides: Partial<OnboardingAnswers>,
  carryLoadsFrom: StatePlan | null,
): RulesTraining | Extract<BuildResult, { ok: false }> {
  const weight = state.goalPhase.currentWeightKg ?? trainingOnlyWeightKg;
  const answers = answersFromState(state, weight, overrides);
  // A never-answered health check holds effort like moderate_until_cleared. see_professional is
  // refused before any plan is built, so it never reaches the rules plan.
  const screening = capsEffortToModerate(state.screening)
    ? "moderate_until_cleared"
    : state.screening === "see_professional"
    ? "see_professional"
    : "cleared";
  const policies = policiesFor(answers, exerciseCatalogV1, null, null, screening);
  let built;
  try {
    built = validRulesPlan(policies);
  } catch (error) {
    if (error instanceof OnboardingPlanInfeasibleError) {
      return refusals.infeasible(infeasibleText[error.rule] ?? "the limits leave no valid week");
    }
    throw error;
  }
  const training = buildOnboardingProposal(built, policies, {
    origin: "rules",
    provider: null,
    model: null,
    fallbackReason: null,
  }).training;
  const carried = loadsToCarry(carryLoadsFrom);
  const workouts = (training.weekly_structure as TrainingPayloadWorkout[]).map((workout) => ({
    ...workout,
    exercises: workout.exercises.map((exercise) => {
      const load = carried(exercise);
      const { start_load_kg: _dropped, ...rest } = exercise;
      return load === undefined ? rest : { ...rest, start_load_kg: load };
    }),
  }));
  return {
    title: training.title as string,
    blockWeeks: training.block_weeks as number,
    workouts,
  };
}

/**
 * The load a rebuilt exercise starts from, taken from the plan it replaces. A lift the old plan
 * has in one rep range carries by slug. A lift it has in more than one range (an advanced plan's
 * heavy and light days) carries only to a new exercise with the same slug and the same range, and
 * to nothing else: a light day never starts from the heavy day's load or the reverse.
 */
function loadsToCarry(
  from: StatePlan | null,
): (exercise: { slug: string | null; rep_min: number; rep_max: number }) => number | undefined {
  const ranges = new Map<string, Set<string>>();
  const byRange = new Map<string, number>();
  const bySlug = new Map<string, number>();
  const rangeKey = (slug: string, repMin: number, repMax: number) => `${slug}|${repMin}|${repMax}`;
  for (const workout of from?.workouts ?? []) {
    for (const exercise of workout.exercises) {
      if (exercise.slug === null) continue;
      const key = rangeKey(exercise.slug, exercise.repMin, exercise.repMax);
      ranges.set(exercise.slug, (ranges.get(exercise.slug) ?? new Set()).add(key));
      if (exercise.targetLoadKg === null) continue;
      byRange.set(key, exercise.targetLoadKg);
      bySlug.set(exercise.slug, exercise.targetLoadKg);
    }
  }
  return (exercise) => {
    if (exercise.slug === null) return undefined;
    return (ranges.get(exercise.slug)?.size ?? 0) > 1
      ? byRange.get(rangeKey(exercise.slug, exercise.rep_min, exercise.rep_max))
      : bySlug.get(exercise.slug);
  };
}

const infeasibleText: Readonly<Record<string, string>> = {
  pattern_coverage_missing:
    "that equipment and the movements you avoid leave a gap in the week (no push, pull, squat " +
    "or hinge). Add dumbbells or bands, or ask for a different setup.",
  priority_volume_missing: "your focus muscles can't get their weekly sets with that setup.",
  session_too_long: "the sessions would run longer than the time you have.",
  workout_count_mismatch: "no week of that length fits those days.",
};

/** True for the refusal branch of a rules result. */
export const isRefusal = (
  value: RulesTraining | Extract<BuildResult, { ok: false }>,
): value is Extract<BuildResult, { ok: false }> => "ok" in value;

/**
 * Training weekdays for a new count, spread over the week. Days the athlete already trains on
 * stay when the count allows; added days go where they sit furthest from the others.
 */
export function spreadWeekdays(current: readonly number[], count: number): number[] {
  const circular = (a: number, b: number) => Math.min((a - b + 7) % 7, (b - a + 7) % 7);
  let chosen = [...current].sort((a, b) => a - b);
  while (chosen.length > count) {
    // Drop the day that sits closest to a neighbour.
    let drop = 0;
    let closest = Infinity;
    chosen.forEach((day, index) => {
      const others = chosen.filter((_, other) => other !== index);
      const gap = Math.min(...others.map((other) => circular(day, other)));
      if (gap < closest) {
        closest = gap;
        drop = index;
      }
    });
    chosen = chosen.filter((_, index) => index !== drop);
  }
  while (chosen.length < count) {
    let best = 1;
    let bestGap = -1;
    for (let day = 1; day <= 7; day++) {
      if (chosen.includes(day)) continue;
      const gap = chosen.length === 0
        ? 7
        : Math.min(...chosen.map((other) => circular(day, other)));
      if (gap > bestGap) {
        bestGap = gap;
        best = day;
      }
    }
    chosen = [...chosen, best].sort((a, b) => a - b);
  }
  return chosen;
}

/** The next date after `from` (exclusive) that falls on a weekday in the list. */
export function nextDateOnWeekdays(from: string, weekdays: readonly number[]): string | null {
  for (let offset = 1; offset <= 7; offset++) {
    const date = new Date(`${from}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() + offset);
    const iso = date.toISOString().slice(0, 10);
    if (weekdays.includes(isoWeekday(iso))) return iso;
  }
  return null;
}
