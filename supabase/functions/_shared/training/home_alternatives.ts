// Home alternatives for a planned exercise (A10): catalog exercises that train the same movement
// with no equipment, or with kit that fits a small home setup. Coach builds an away-from-the-gym
// routine from these and from the plan's weekly volume, so it names catalog exercises and never
// invents one. The plan itself is not changed; a plan change is a proposal the athlete approves.
import {
  allowedExercises,
  type AvoidablePattern,
  type EquipmentItem,
  type MovementPattern,
} from "../onboarding/catalog.ts";
import {
  type CatalogExerciseV2,
  catalogV2BySlug,
  exerciseCatalogV2,
} from "../onboarding/catalog_v2.ts";

/** Kit a small home setup can hold. A bench, bar, cables and machines are gym kit. */
export const minimalHomeKit: readonly EquipmentItem[] = Object.freeze([
  "dumbbells",
  "kettlebells",
  "bands",
  "pull_up_bar",
]);

const mostPerKind = 2;

export type HomeAlternatives = Readonly<{
  /** The exercise already needs no gym kit: "bodyweight" or "minimal"; null for gym kit. */
  already: "bodyweight" | "minimal" | null;
  bodyweight: readonly string[];
  minimal: readonly string[];
}>;

const none: HomeAlternatives = Object.freeze({ already: null, bodyweight: [], minimal: [] });

/** Linked exercises first (substitutes, regressions, progressions), then the same pattern and muscle. */
function candidates(exercise: CatalogExerciseV2, pool: readonly CatalogExerciseV2[]) {
  const linked = [...exercise.substitutes, ...exercise.regressions, ...exercise.progressions]
    .flatMap((slug) => {
      const found = pool.find((item) => item.slug === slug);
      return found ? [found] : [];
    });
  const related = pool.filter((item) =>
    item.pattern === exercise.pattern && item.muscles[0] === exercise.muscles[0]
  ).sort((a, b) =>
    Number(b.compound) - Number(a.compound) ||
    Number(a.level === "intermediate") - Number(b.level === "intermediate") ||
    a.slug.localeCompare(b.slug)
  );
  return [...new Set([...linked, ...related])].filter((item) => item.slug !== exercise.slug);
}

/**
 * Bodyweight and minimal-kit catalog alternatives for a planned exercise, at most two of each,
 * leaving out movement patterns the athlete asked to avoid. An exercise outside the catalog (an
 * imported plan, a custom exercise) has none.
 */
export function homeAlternativesFor(
  slug: string | null,
  avoid: readonly AvoidablePattern[] = [],
): HomeAlternatives {
  const exercise = slug === null ? undefined : catalogV2BySlug.get(slug);
  if (!exercise) return none;
  const avoided: readonly MovementPattern[] = avoid;
  const bodyweightPool = allowedExercises(
    exerciseCatalogV2,
    [],
    "intermediate",
    avoided,
  ) as CatalogExerciseV2[];
  const minimalPool = (allowedExercises(
    exerciseCatalogV2,
    minimalHomeKit,
    "intermediate",
    avoided,
  ) as CatalogExerciseV2[]).filter((item) => item.equipment.length > 0);
  const names = (pool: CatalogExerciseV2[]) =>
    candidates(exercise, pool).slice(0, mostPerKind).map((item) => item.name);
  const already = exercise.equipment.length === 0
    ? "bodyweight"
    : exercise.equipment.every((item) => minimalHomeKit.includes(item))
    ? "minimal"
    : null;
  return { already, bodyweight: names(bodyweightPool), minimal: names(minimalPool) };
}
