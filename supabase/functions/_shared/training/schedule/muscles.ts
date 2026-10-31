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

/**
 * The muscle groups a session is compared by. The catalog lists one `shoulders` group, but rear-delt
 * work (face pulls, rear-delt flies) and pressing or lateral work do not tax the same fibres, so a
 * push day and a pull day with face pulls are not a back-to-back shoulder day. The split comes from
 * the catalog's own movement pattern: an exercise whose pattern is `rear_delts` trains the rear
 * delts, any other exercise that lists `shoulders` trains the front and side delts.
 */
export const frontSideDelts = "front and side delts";
export const rearDelts = "rear delts";
export type TrainedMuscle = Exclude<Muscle, "shoulders"> | typeof frontSideDelts | typeof rearDelts;

const groupOf = (muscle: Muscle, pattern: string): TrainedMuscle =>
  muscle !== "shoulders" ? muscle : pattern === "rear_delts" ? rearDelts : frontSideDelts;

/** The muscles a session trains and how many of its exercises have no muscle data. */
export function sessionMuscles(
  exercises: readonly DayExercise[],
): Readonly<{ muscles: readonly TrainedMuscle[]; unknown: number }> {
  const sets = new Map<TrainedMuscle, number>();
  let unknown = 0;
  for (const exercise of exercises) {
    const known = exercise.slug === null ? undefined : catalogV2BySlug.get(exercise.slug);
    if (!known) {
      unknown += 1;
      continue;
    }
    for (const muscle of known.muscles) {
      const group = groupOf(muscle, known.pattern);
      sets.set(group, (sets.get(group) ?? 0) + exercise.sets);
    }
  }
  const muscles = [...sets].filter(([, count]) => count >= setsThatTrainAMuscle)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([muscle]) => muscle);
  return { muscles, unknown };
}
