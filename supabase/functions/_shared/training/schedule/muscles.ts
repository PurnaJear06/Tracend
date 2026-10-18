// Which muscles a session trains, from the sets of its exercises and the catalog's muscle data.
// One mapping for everything that needs it: the week-ahead schedule, the schedule lookup and, later,
// other deterministic facts about the athlete's training. Deterministic: the model never decides it.
import type { Muscle } from "../../onboarding/catalog.ts";
import { catalogV2BySlug } from "../../onboarding/catalog_v2.ts";
import { sessionsPerMusclePerWeek, weeklySetsPerMuscle } from "../standard/volume.ts";

/**
 * Direct sets that make a session train a muscle: the standard's weekly minimum (4 sets) over its
 * minimum of 2 sessions a week, so 2. A single accessory set does not count.
 */
export const setsThatTrainAMuscle = weeklySetsPerMuscle.minimum.value /
  sessionsPerMusclePerWeek.value;

export type DayExercise = Readonly<{ slug: string | null; sets: number }>;

/** The muscles a session trains and how many of its exercises have no muscle data. */
export function sessionMuscles(
  exercises: readonly DayExercise[],
): Readonly<{ muscles: readonly Muscle[]; unknown: number }> {
  const sets = new Map<Muscle, number>();
  let unknown = 0;
  for (const exercise of exercises) {
    const known = exercise.slug === null ? undefined : catalogV2BySlug.get(exercise.slug);
    if (!known) {
      unknown += 1;
      continue;
    }
    for (const muscle of known.muscles) sets.set(muscle, (sets.get(muscle) ?? 0) + exercise.sets);
  }
  const muscles = [...sets].filter(([, count]) => count >= setsThatTrainAMuscle)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([muscle]) => muscle);
  return { muscles, unknown };
}
