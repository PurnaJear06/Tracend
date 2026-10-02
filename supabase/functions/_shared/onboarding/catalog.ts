// Exercise catalog v1, the only exercises an onboarding plan may use
// (AI_SAFETY_SPEC §11: "only supplied catalog identifiers"). The database
// table public.exercise_catalog is seeded from this list
// (20261002091000_exercise_catalog.sql); catalog_test.ts keeps the two equal.

export const equipmentItems = [
  "dumbbells",
  "barbell",
  "bench",
  "cables",
  "machines",
  "pull_up_bar",
  "kettlebells",
  "bands",
] as const;
export type EquipmentItem = typeof equipmentItems[number];

export const movementPatterns = [
  "squat",
  "lunge",
  "hinge",
  "horizontal_push",
  "vertical_push",
  "horizontal_pull",
  "vertical_pull",
  "core",
  "calves",
  "biceps",
  "triceps",
  "lateral_raise",
  "rear_delts",
  "chest_fly",
  "quads_isolation",
  "hamstring_curl",
] as const;
export type MovementPattern = typeof movementPatterns[number];

export const muscles = [
  "quads",
  "glutes",
  "hamstrings",
  "chest",
  "back",
  "shoulders",
  "biceps",
  "triceps",
  "core",
  "calves",
] as const;
export type Muscle = typeof muscles[number];

export type CatalogExercise = Readonly<{
  slug: string;
  name: string;
  pattern: MovementPattern;
  /** The first muscle is the target; weekly volume is counted against it. */
  muscles: readonly Muscle[];
  /** Everything required; an empty list means bodyweight only. */
  equipment: readonly EquipmentItem[];
  level: "beginner" | "intermediate";
  compound: boolean;
}>;

const x = (
  slug: string,
  name: string,
  pattern: MovementPattern,
  muscleList: Muscle[],
  equipment: EquipmentItem[],
  level: "beginner" | "intermediate",
  compound: boolean,
): CatalogExercise => ({ slug, name, pattern, muscles: muscleList, equipment, level, compound });

export const catalogVersion = "catalog-v1";

export const exerciseCatalogV1: readonly CatalogExercise[] = Object.freeze([
  // Bodyweight
  x("bodyweight-squat", "Bodyweight squat", "squat", ["quads", "glutes"], [], "beginner", true),
  x("split-squat", "Split squat", "lunge", ["quads", "glutes"], [], "beginner", true),
  x("reverse-lunge", "Reverse lunge", "lunge", ["quads", "glutes"], [], "beginner", true),
  x("glute-bridge", "Glute bridge", "hinge", ["glutes", "hamstrings"], [], "beginner", true),
  x(
    "single-leg-hip-hinge",
    "Single-leg hip hinge",
    "hinge",
    ["hamstrings", "glutes"],
    [],
    "beginner",
    true,
  ),
  x("push-up", "Push-up", "horizontal_push", ["chest", "triceps"], [], "beginner", true),
  x(
    "hands-elevated-push-up",
    "Hands-elevated push-up",
    "horizontal_push",
    ["chest", "triceps"],
    [],
    "beginner",
    true,
  ),
  x(
    "pike-push-up",
    "Pike push-up",
    "vertical_push",
    ["shoulders", "triceps"],
    [],
    "intermediate",
    true,
  ),
  x(
    "towel-doorway-row",
    "Towel doorway row",
    "horizontal_pull",
    ["back", "biceps"],
    [],
    "beginner",
    true,
  ),
  x("dead-bug", "Dead bug", "core", ["core"], [], "beginner", false),
  x("bird-dog", "Bird dog", "core", ["core"], [], "beginner", false),
  x("standing-calf-raise", "Standing calf raise", "calves", ["calves"], [], "beginner", false),
  x("bench-dip", "Bench dip", "triceps", ["triceps"], ["bench"], "beginner", false),
  // Pull-up bar
  x(
    "pull-up",
    "Pull-up",
    "vertical_pull",
    ["back", "biceps"],
    ["pull_up_bar"],
    "intermediate",
    true,
  ),
  x(
    "chin-up",
    "Chin-up",
    "vertical_pull",
    ["back", "biceps"],
    ["pull_up_bar"],
    "intermediate",
    true,
  ),
  x(
    "hanging-knee-raise",
    "Hanging knee raise",
    "core",
    ["core"],
    ["pull_up_bar"],
    "beginner",
    false,
  ),
  // Dumbbells
  x("goblet-squat", "Goblet squat", "squat", ["quads", "glutes"], ["dumbbells"], "beginner", true),
  x(
    "dumbbell-romanian-deadlift",
    "Dumbbell Romanian deadlift",
    "hinge",
    ["hamstrings", "glutes"],
    ["dumbbells"],
    "beginner",
    true,
  ),
  x(
    "dumbbell-reverse-lunge",
    "Dumbbell reverse lunge",
    "lunge",
    ["quads", "glutes"],
    ["dumbbells"],
    "beginner",
    true,
  ),
  x(
    "dumbbell-step-up",
    "Dumbbell step-up",
    "lunge",
    ["quads", "glutes"],
    ["dumbbells", "bench"],
    "beginner",
    true,
  ),
  x(
    "dumbbell-floor-press",
    "Dumbbell floor press",
    "horizontal_push",
    ["chest", "triceps"],
    ["dumbbells"],
    "beginner",
    true,
  ),
  x(
    "dumbbell-bench-press",
    "Dumbbell bench press",
    "horizontal_push",
    ["chest", "triceps"],
    ["dumbbells", "bench"],
    "beginner",
    true,
  ),
  x(
    "incline-dumbbell-press",
    "Incline dumbbell press",
    "horizontal_push",
    ["chest", "shoulders"],
    ["dumbbells", "bench"],
    "beginner",
    true,
  ),
  x(
    "one-arm-dumbbell-row",
    "One-arm dumbbell row",
    "horizontal_pull",
    ["back", "biceps"],
    ["dumbbells"],
    "beginner",
    true,
  ),
  x(
    "chest-supported-dumbbell-row",
    "Chest-supported dumbbell row",
    "horizontal_pull",
    ["back", "biceps"],
    ["dumbbells", "bench"],
    "beginner",
    true,
  ),
  x(
    "dumbbell-shoulder-press",
    "Dumbbell shoulder press",
    "vertical_push",
    ["shoulders", "triceps"],
    ["dumbbells"],
    "beginner",
    true,
  ),
  x(
    "dumbbell-lateral-raise",
    "Dumbbell lateral raise",
    "lateral_raise",
    ["shoulders"],
    ["dumbbells"],
    "beginner",
    false,
  ),
  x(
    "dumbbell-rear-delt-fly",
    "Dumbbell rear delt fly",
    "rear_delts",
    ["shoulders"],
    ["dumbbells"],
    "beginner",
    false,
  ),
  x("dumbbell-curl", "Dumbbell curl", "biceps", ["biceps"], ["dumbbells"], "beginner", false),
  x(
    "dumbbell-overhead-triceps-extension",
    "Dumbbell overhead triceps extension",
    "triceps",
    ["triceps"],
    ["dumbbells"],
    "beginner",
    false,
  ),
  x(
    "dumbbell-pullover",
    "Dumbbell pullover",
    "vertical_pull",
    ["back", "chest"],
    ["dumbbells", "bench"],
    "intermediate",
    false,
  ),
  x(
    "dumbbell-hip-thrust",
    "Dumbbell hip thrust",
    "hinge",
    ["glutes", "hamstrings"],
    ["dumbbells", "bench"],
    "beginner",
    true,
  ),
  x(
    "dumbbell-calf-raise",
    "Dumbbell calf raise",
    "calves",
    ["calves"],
    ["dumbbells"],
    "beginner",
    false,
  ),
  x(
    "dumbbell-chest-fly",
    "Dumbbell chest fly",
    "chest_fly",
    ["chest"],
    ["dumbbells", "bench"],
    "beginner",
    false,
  ),
  // Barbell with a rack
  x(
    "barbell-back-squat",
    "Barbell back squat",
    "squat",
    ["quads", "glutes"],
    ["barbell"],
    "beginner",
    true,
  ),
  x(
    "barbell-front-squat",
    "Barbell front squat",
    "squat",
    ["quads", "glutes"],
    ["barbell"],
    "intermediate",
    true,
  ),
  x(
    "barbell-romanian-deadlift",
    "Barbell Romanian deadlift",
    "hinge",
    ["hamstrings", "glutes"],
    ["barbell"],
    "beginner",
    true,
  ),
  x(
    "barbell-deadlift",
    "Barbell deadlift",
    "hinge",
    ["back", "hamstrings", "glutes"],
    ["barbell"],
    "intermediate",
    true,
  ),
  x(
    "barbell-bench-press",
    "Barbell bench press",
    "horizontal_push",
    ["chest", "triceps"],
    ["barbell", "bench"],
    "beginner",
    true,
  ),
  x(
    "barbell-overhead-press",
    "Barbell overhead press",
    "vertical_push",
    ["shoulders", "triceps"],
    ["barbell"],
    "beginner",
    true,
  ),
  x(
    "barbell-row",
    "Barbell row",
    "horizontal_pull",
    ["back", "biceps"],
    ["barbell"],
    "beginner",
    true,
  ),
  x(
    "barbell-hip-thrust",
    "Barbell hip thrust",
    "hinge",
    ["glutes", "hamstrings"],
    ["barbell", "bench"],
    "beginner",
    true,
  ),
  x(
    "barbell-reverse-lunge",
    "Barbell reverse lunge",
    "lunge",
    ["quads", "glutes"],
    ["barbell"],
    "intermediate",
    true,
  ),
  x("barbell-curl", "Barbell curl", "biceps", ["biceps"], ["barbell"], "beginner", false),
  // Cables
  x(
    "lat-pulldown",
    "Lat pulldown",
    "vertical_pull",
    ["back", "biceps"],
    ["cables"],
    "beginner",
    true,
  ),
  x(
    "seated-cable-row",
    "Seated cable row",
    "horizontal_pull",
    ["back", "biceps"],
    ["cables"],
    "beginner",
    true,
  ),
  x("cable-chest-fly", "Cable chest fly", "chest_fly", ["chest"], ["cables"], "beginner", false),
  x(
    "cable-lateral-raise",
    "Cable lateral raise",
    "lateral_raise",
    ["shoulders"],
    ["cables"],
    "beginner",
    false,
  ),
  x("face-pull", "Face pull", "rear_delts", ["shoulders"], ["cables"], "beginner", false),
  x(
    "cable-triceps-pressdown",
    "Cable triceps pressdown",
    "triceps",
    ["triceps"],
    ["cables"],
    "beginner",
    false,
  ),
  x("cable-curl", "Cable curl", "biceps", ["biceps"], ["cables"], "beginner", false),
  x("cable-crunch", "Cable crunch", "core", ["core"], ["cables"], "beginner", false),
  x(
    "cable-pull-through",
    "Cable pull-through",
    "hinge",
    ["glutes", "hamstrings"],
    ["cables"],
    "beginner",
    true,
  ),
  // Machines
  x("leg-press", "Leg press", "squat", ["quads", "glutes"], ["machines"], "beginner", true),
  x(
    "leg-extension",
    "Leg extension",
    "quads_isolation",
    ["quads"],
    ["machines"],
    "beginner",
    false,
  ),
  x(
    "lying-leg-curl",
    "Lying leg curl",
    "hamstring_curl",
    ["hamstrings"],
    ["machines"],
    "beginner",
    false,
  ),
  x(
    "machine-chest-press",
    "Machine chest press",
    "horizontal_push",
    ["chest", "triceps"],
    ["machines"],
    "beginner",
    true,
  ),
  x(
    "machine-shoulder-press",
    "Machine shoulder press",
    "vertical_push",
    ["shoulders", "triceps"],
    ["machines"],
    "beginner",
    true,
  ),
  x(
    "machine-row",
    "Chest-supported machine row",
    "horizontal_pull",
    ["back", "biceps"],
    ["machines"],
    "beginner",
    true,
  ),
  x(
    "assisted-pull-up",
    "Assisted pull-up",
    "vertical_pull",
    ["back", "biceps"],
    ["machines"],
    "beginner",
    true,
  ),
  x("pec-deck", "Pec deck", "chest_fly", ["chest"], ["machines"], "beginner", false),
  x(
    "seated-calf-raise",
    "Seated calf raise",
    "calves",
    ["calves"],
    ["machines"],
    "beginner",
    false,
  ),
  // Kettlebells
  x(
    "kettlebell-swing",
    "Kettlebell swing",
    "hinge",
    ["glutes", "hamstrings"],
    ["kettlebells"],
    "intermediate",
    true,
  ),
  x(
    "kettlebell-goblet-squat",
    "Kettlebell goblet squat",
    "squat",
    ["quads", "glutes"],
    ["kettlebells"],
    "beginner",
    true,
  ),
  x(
    "kettlebell-press",
    "Kettlebell press",
    "vertical_push",
    ["shoulders", "triceps"],
    ["kettlebells"],
    "beginner",
    true,
  ),
  x(
    "kettlebell-row",
    "Kettlebell row",
    "horizontal_pull",
    ["back", "biceps"],
    ["kettlebells"],
    "beginner",
    true,
  ),
  // Resistance bands
  x("band-row", "Band row", "horizontal_pull", ["back", "biceps"], ["bands"], "beginner", true),
  x(
    "band-lat-pulldown",
    "Band lat pulldown",
    "vertical_pull",
    ["back", "biceps"],
    ["bands"],
    "beginner",
    true,
  ),
  x(
    "band-pull-apart",
    "Band pull-apart",
    "rear_delts",
    ["shoulders"],
    ["bands"],
    "beginner",
    false,
  ),
  x("band-pallof-press", "Band Pallof press", "core", ["core"], ["bands"], "beginner", false),
  x("band-curl", "Band curl", "biceps", ["biceps"], ["bands"], "beginner", false),
  x(
    "band-triceps-pushdown",
    "Band triceps pushdown",
    "triceps",
    ["triceps"],
    ["bands"],
    "beginner",
    false,
  ),
]);

export const catalogBySlug: ReadonlyMap<string, CatalogExercise> = new Map(
  exerciseCatalogV1.map((exercise) => [exercise.slug, exercise]),
);

/**
 * The movement patterns an athlete can ask a plan to leave out (onboarding
 * "movements to avoid"). Every exercise with that pattern is excluded.
 */
export const avoidablePatterns = [
  "squat",
  "lunge",
  "hinge",
  "horizontal_push",
  "vertical_push",
  "horizontal_pull",
  "vertical_pull",
] as const satisfies readonly MovementPattern[];
export type AvoidablePattern = typeof avoidablePatterns[number];

export const avoidablePatternLabels: Readonly<Record<AvoidablePattern, string>> = Object.freeze({
  squat: "squats",
  lunge: "lunges and step-ups",
  hinge: "deadlifts and hip hinges",
  horizontal_push: "bench pressing and push-ups",
  vertical_push: "overhead pressing",
  horizontal_pull: "rows",
  vertical_pull: "pull-ups and pulldowns",
});

/**
 * Exercises this athlete can do with their equipment and experience, leaving
 * out the movement patterns they asked to avoid.
 */
export function allowedExercises(
  catalog: readonly CatalogExercise[],
  equipment: readonly EquipmentItem[],
  experience: "beginner" | "intermediate",
  avoid: readonly MovementPattern[] = [],
): CatalogExercise[] {
  const owned = new Set(equipment);
  return catalog.filter((exercise) =>
    exercise.equipment.every((item) => owned.has(item)) &&
    (experience === "intermediate" || exercise.level === "beginner") &&
    !avoid.includes(exercise.pattern)
  );
}
