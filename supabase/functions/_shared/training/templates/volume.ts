// Weekly volume per muscle, counted the way the coaching standard counts it, and the weekly
// target the rules plan builds toward. The standard's numbers live in `../standard/volume.ts`;
// the targets here only combine them (Tracend's reading, recorded in ALGORITHMS §9).
import type { CatalogExercise, Muscle } from "../../onboarding/catalog.ts";
import { catalogV2BySlug } from "../../onboarding/catalog_v2.ts";
import type { PlanWorkout } from "../../onboarding/plan_contract.ts";
import {
  indirectSetFraction,
  sessionsPerMusclePerWeek,
  strengthSetsPerExercise,
  weeklySetsPerMuscle,
} from "../standard/volume.ts";
import type { Emphasis, Experience } from "../standard/prescription.ts";
import { sourced } from "../standard/sources.ts";

/**
 * How much one working set of an exercise counts toward each muscle: 1 for the target and the
 * exercise's other primary muscles (the catalog's `muscles`), `indirectSetFraction` (0.5) for its
 * secondary muscles (catalog v2). The secondary muscles are read from catalog v2 by slug, like
 * the exercise role, because the database catalog is not read for them yet.
 */
export function setWeights(exercise: CatalogExercise): ReadonlyMap<Muscle, number> {
  const weights = new Map<Muscle, number>();
  for (const muscle of catalogV2BySlug.get(exercise.slug)?.secondaryMuscles ?? []) {
    weights.set(muscle, indirectSetFraction.value);
  }
  for (const muscle of exercise.muscles) weights.set(muscle, 1);
  return weights;
}

/** Weekly working sets per muscle, direct and indirect, with indirect sets counted fractionally. */
export function fractionalWeeklySets(
  workouts: readonly Pick<PlanWorkout, "exercises">[],
  catalog: readonly CatalogExercise[],
): Map<Muscle, number> {
  const bySlug = new Map(catalog.map((exercise) => [exercise.slug, exercise]));
  const totals = new Map<Muscle, number>();
  for (const workout of workouts) {
    for (const planned of workout.exercises) {
      const exercise = bySlug.get(planned.slug);
      if (!exercise) continue;
      for (const [muscle, weight] of setWeights(exercise)) {
        totals.set(muscle, (totals.get(muscle) ?? 0) + planned.sets * weight);
      }
    }
  }
  return totals;
}

/**
 * Muscles whose weekly target is the minimum and whose indirect sets are not held to the weekly
 * maximum: the trunk gets a great deal of indirect work from every squat, hinge and press, so it
 * is not built up with sets of its own, and rotating trunk exercises must never be dropped
 * because the lifts already brace it.
 */
export const supportingMuscles: readonly Muscle[] = ["core"];

export const strengthWeeklyTarget = sourced(
  sessionsPerMusclePerWeek.value * strengthSetsPerExercise.value[1],
  ["acsm_2011", "acsm_2026", "tracend_in_house"],
  "Two sessions a week (the standard's frequency) of the top of 2-3 sets an exercise (the " +
    "standard's strength sets) is 6 weekly sets a muscle, above the 4-set minimum and below " +
    "the 10-set growth level. Tracend's arithmetic on the standard's two values.",
);

export const stretchTarget = sourced(
  0.5,
  ["acsm_2026", "schoenfeld_2017", "baz_valle_2022", "tracend_in_house"],
  "Schoenfeld 2017 finds a graded dose-response (more weekly sets, more growth) and Baz-Valle " +
    "2022 sets 12-20 sets as the standard for trained lifters, so once every muscle has the " +
    "10-set growth level (12 for an advanced lifter, the bottom of Baz-Valle's range), spare " +
    "session room goes toward the maximum: halfway between the two (11 sets for a beginner, " +
    "15 for an intermediate, 16 for an advanced lifter). The halfway point is Tracend's choice.",
);

/**
 * The weekly sets (indirect sets counted 0.5) the rules plan builds toward for each muscle. A
 * target, never a promise: session length and set budget come first, and the policy's weekly
 * maximum stays the ceiling. Strength emphasis aims at `strengthWeeklyTarget`; the other emphasis
 * first at the standard's growth level and, with `stretch`, at the `stretchTarget` point between
 * that level and the experience's maximum. No target passes the experience's maximum.
 */
export function weeklyTargets(
  emphasis: Emphasis,
  experience: Experience,
  muscles: readonly Muscle[],
  stretch = false,
): Readonly<Record<string, number>> {
  const ceiling = weeklySetsPerMuscle.maximum[experience].value;
  const growth = experience === "advanced"
    ? weeklySetsPerMuscle.advancedGrowth.value
    : weeklySetsPerMuscle.growth.value;
  const level = emphasis === "strength"
    ? strengthWeeklyTarget.value
    : stretch
    ? Math.round(growth + (ceiling - growth) * stretchTarget.value)
    : growth;
  return Object.fromEntries(muscles.map((muscle) => [
    muscle,
    Math.min(
      ceiling,
      supportingMuscles.includes(muscle) ? weeklySetsPerMuscle.minimum.value : level,
    ),
  ]));
}
