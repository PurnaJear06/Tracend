// Exercise catalog v2: catalog v1 plus the coaching data later chunks need
// (secondary muscles, joint stress, regressions, progressions, substitutes and
// a load step). Catalog v1 and its exports are unchanged, so today's plans and
// prompts are byte-identical (catalog_plans_test.ts); B2 moves the planner onto
// this list. The database catalog mirrors these fields
// (20261015170021_exercise_catalog_v2.sql); catalog_v2_test.ts keeps the two
// equal and checks that every link points at a real exercise.
import { type CatalogExercise, exerciseCatalogV1, type Muscle } from "./catalog.ts";
import type { JointStress } from "../training/standard/joint_stress.ts";
import { loadingEquipmentOrder, loadStepKgByEquipment } from "../training/standard/progression.ts";

export type JointStressProfile = Readonly<{
  knee: JointStress;
  back: JointStress;
  shoulder: JointStress;
}>;

export type CatalogExerciseDetails = Readonly<{
  /** Muscles trained indirectly; never one of the primary muscles. */
  secondaryMuscles: readonly Muscle[];
  /** Rated with the method in `_shared/training/standard/joint_stress.ts`. */
  jointStress: JointStressProfile;
  /** Easier forms of the same movement pattern, any equipment. */
  regressions: readonly string[];
  /** Harder forms of the same movement pattern, any equipment. */
  progressions: readonly string[];
  /** Alternatives of similar difficulty: the same pattern or the same target muscle. */
  substitutes: readonly string[];
  /**
   * Smallest load increase in kg (per dumbbell or kettlebell), from the
   * standard's equipment steps; null when the exercise progresses by reps, a
   * harder form or a stronger band.
   */
  loadStepKg: number | null;
}>;

export type CatalogExerciseV2 = CatalogExercise & CatalogExerciseDetails;

type Links = Readonly<{
  regressions?: readonly string[];
  progressions?: readonly string[];
  substitutes?: readonly string[];
}>;

type Entry = Omit<CatalogExerciseDetails, "loadStepKg">;

const low = "low", moderate = "moderate", high = "high";

const d = (
  secondaryMuscles: readonly Muscle[],
  [knee, back, shoulder]: readonly [JointStress, JointStress, JointStress],
  links: Links = {},
): Entry => ({
  secondaryMuscles,
  jointStress: { knee, back, shoulder },
  regressions: links.regressions ?? [],
  progressions: links.progressions ?? [],
  substitutes: links.substitutes ?? [],
});

const details: Readonly<Record<string, Entry>> = {
  // Squat
  "bodyweight-squat": d(["core"], [moderate, low, low], {
    progressions: ["goblet-squat", "kettlebell-goblet-squat"],
    substitutes: ["split-squat"],
  }),
  "goblet-squat": d(["core"], [moderate, low, low], {
    regressions: ["bodyweight-squat"],
    progressions: ["barbell-back-squat", "barbell-front-squat"],
    substitutes: ["kettlebell-goblet-squat", "leg-press"],
  }),
  "kettlebell-goblet-squat": d(["core"], [moderate, low, low], {
    regressions: ["bodyweight-squat"],
    progressions: ["barbell-back-squat"],
    substitutes: ["goblet-squat", "leg-press"],
  }),
  "barbell-back-squat": d(["core"], [high, high, moderate], {
    regressions: ["goblet-squat", "kettlebell-goblet-squat"],
    substitutes: ["barbell-front-squat", "leg-press"],
  }),
  "barbell-front-squat": d(["core"], [high, moderate, moderate], {
    regressions: ["goblet-squat"],
    substitutes: ["barbell-back-squat", "leg-press"],
  }),
  "leg-press": d([], [high, moderate, low], {
    substitutes: [
      "goblet-squat",
      "kettlebell-goblet-squat",
      "barbell-back-squat",
      "barbell-front-squat",
    ],
  }),
  // Lunge
  "split-squat": d(["hamstrings"], [moderate, low, low], {
    progressions: ["reverse-lunge"],
    substitutes: ["bodyweight-squat"],
  }),
  "reverse-lunge": d(["hamstrings"], [moderate, low, low], {
    regressions: ["split-squat"],
    progressions: ["dumbbell-reverse-lunge"],
  }),
  "dumbbell-reverse-lunge": d(["hamstrings"], [moderate, low, low], {
    regressions: ["reverse-lunge"],
    progressions: ["barbell-reverse-lunge"],
    substitutes: ["dumbbell-step-up"],
  }),
  "dumbbell-step-up": d(["hamstrings"], [moderate, low, low], {
    substitutes: ["dumbbell-reverse-lunge"],
  }),
  "barbell-reverse-lunge": d(["hamstrings"], [moderate, moderate, moderate], {
    regressions: ["dumbbell-reverse-lunge"],
  }),
  // Hinge
  "single-leg-hip-hinge": d(["core"], [low, low, low], {
    progressions: ["dumbbell-romanian-deadlift"],
    substitutes: ["glute-bridge"],
  }),
  "dumbbell-romanian-deadlift": d(["back"], [low, moderate, low], {
    regressions: ["single-leg-hip-hinge"],
    progressions: ["barbell-romanian-deadlift"],
    substitutes: ["cable-pull-through"],
  }),
  "barbell-romanian-deadlift": d(["back"], [low, high, low], {
    regressions: ["dumbbell-romanian-deadlift"],
    substitutes: ["barbell-deadlift"],
  }),
  "barbell-deadlift": d(["quads", "core"], [moderate, high, low], {
    substitutes: ["barbell-romanian-deadlift"],
  }),
  "glute-bridge": d([], [low, low, low], {
    progressions: ["dumbbell-hip-thrust"],
    substitutes: ["single-leg-hip-hinge"],
  }),
  "dumbbell-hip-thrust": d([], [low, low, low], {
    regressions: ["glute-bridge"],
    progressions: ["barbell-hip-thrust"],
    substitutes: ["cable-pull-through"],
  }),
  "barbell-hip-thrust": d([], [low, low, low], {
    regressions: ["dumbbell-hip-thrust"],
    substitutes: ["cable-pull-through"],
  }),
  "cable-pull-through": d([], [low, low, low], {
    substitutes: [
      "dumbbell-romanian-deadlift",
      "dumbbell-hip-thrust",
      "barbell-hip-thrust",
      "kettlebell-swing",
    ],
  }),
  "kettlebell-swing": d(["back", "core"], [low, moderate, low], {
    substitutes: ["cable-pull-through"],
  }),
  // Horizontal push
  "hands-elevated-push-up": d(["shoulders", "core"], [low, low, low], {
    progressions: ["push-up"],
  }),
  "push-up": d(["shoulders", "core"], [low, low, moderate], {
    regressions: ["hands-elevated-push-up"],
    substitutes: ["dumbbell-floor-press", "machine-chest-press"],
  }),
  "dumbbell-floor-press": d(["shoulders"], [low, low, low], {
    progressions: ["dumbbell-bench-press"],
    substitutes: ["push-up"],
  }),
  "dumbbell-bench-press": d(["shoulders"], [low, low, moderate], {
    regressions: ["dumbbell-floor-press"],
    substitutes: ["barbell-bench-press", "machine-chest-press", "incline-dumbbell-press"],
  }),
  "incline-dumbbell-press": d(["triceps"], [low, low, moderate], {
    substitutes: ["dumbbell-bench-press"],
  }),
  "barbell-bench-press": d(["shoulders"], [low, low, high], {
    substitutes: ["dumbbell-bench-press", "machine-chest-press"],
  }),
  "machine-chest-press": d(["shoulders"], [low, low, low], {
    substitutes: ["push-up", "dumbbell-bench-press", "barbell-bench-press"],
  }),
  // Vertical push
  "pike-push-up": d([], [low, low, high], {
    substitutes: ["dumbbell-shoulder-press"],
  }),
  "dumbbell-shoulder-press": d([], [low, low, moderate], {
    substitutes: [
      "kettlebell-press",
      "machine-shoulder-press",
      "barbell-overhead-press",
      "pike-push-up",
    ],
  }),
  "barbell-overhead-press": d(["core"], [low, moderate, high], {
    substitutes: ["dumbbell-shoulder-press", "machine-shoulder-press"],
  }),
  "machine-shoulder-press": d([], [low, low, moderate], {
    substitutes: ["dumbbell-shoulder-press", "barbell-overhead-press", "kettlebell-press"],
  }),
  "kettlebell-press": d(["core"], [low, low, moderate], {
    substitutes: ["dumbbell-shoulder-press", "machine-shoulder-press"],
  }),
  // Horizontal pull
  "towel-doorway-row": d(["shoulders"], [low, low, low], {
    substitutes: ["band-row"],
  }),
  "one-arm-dumbbell-row": d(["shoulders"], [low, low, low], {
    substitutes: ["chest-supported-dumbbell-row", "kettlebell-row", "seated-cable-row"],
  }),
  "chest-supported-dumbbell-row": d(["shoulders"], [low, low, low], {
    substitutes: ["one-arm-dumbbell-row", "machine-row", "barbell-row"],
  }),
  "barbell-row": d(["shoulders"], [low, high, low], {
    substitutes: ["chest-supported-dumbbell-row", "machine-row", "seated-cable-row"],
  }),
  "seated-cable-row": d(["shoulders"], [low, low, low], {
    substitutes: ["one-arm-dumbbell-row", "barbell-row", "machine-row", "band-row"],
  }),
  "machine-row": d(["shoulders"], [low, low, low], {
    substitutes: ["chest-supported-dumbbell-row", "barbell-row", "seated-cable-row"],
  }),
  "kettlebell-row": d(["shoulders"], [low, low, low], {
    substitutes: ["one-arm-dumbbell-row"],
  }),
  "band-row": d(["shoulders"], [low, low, low], {
    substitutes: ["towel-doorway-row", "seated-cable-row"],
  }),
  // Vertical pull
  "assisted-pull-up": d([], [low, low, moderate], {
    progressions: ["pull-up", "chin-up"],
    substitutes: ["lat-pulldown"],
  }),
  "pull-up": d([], [low, low, moderate], {
    regressions: ["assisted-pull-up"],
    substitutes: ["chin-up", "lat-pulldown"],
  }),
  "chin-up": d([], [low, low, moderate], {
    regressions: ["assisted-pull-up"],
    substitutes: ["pull-up", "lat-pulldown"],
  }),
  "lat-pulldown": d([], [low, low, moderate], {
    substitutes: ["pull-up", "chin-up", "assisted-pull-up", "band-lat-pulldown"],
  }),
  "band-lat-pulldown": d([], [low, low, low], {
    substitutes: ["lat-pulldown"],
  }),
  "dumbbell-pullover": d(["triceps"], [low, low, high]),
  // Core
  "dead-bug": d([], [low, low, low], {
    substitutes: ["bird-dog", "band-pallof-press"],
  }),
  "bird-dog": d(["glutes"], [low, low, low], {
    substitutes: ["dead-bug"],
  }),
  "band-pallof-press": d([], [low, low, low], {
    substitutes: ["dead-bug"],
  }),
  "hanging-knee-raise": d([], [low, low, moderate], {
    substitutes: ["cable-crunch"],
  }),
  "cable-crunch": d([], [low, moderate, low], {
    substitutes: ["hanging-knee-raise"],
  }),
  // Calves
  "standing-calf-raise": d([], [low, low, low], {
    progressions: ["dumbbell-calf-raise"],
    substitutes: ["seated-calf-raise"],
  }),
  "dumbbell-calf-raise": d([], [low, low, low], {
    regressions: ["standing-calf-raise"],
    substitutes: ["seated-calf-raise"],
  }),
  "seated-calf-raise": d([], [low, low, low], {
    substitutes: ["standing-calf-raise", "dumbbell-calf-raise"],
  }),
  // Biceps
  "dumbbell-curl": d([], [low, low, low], {
    substitutes: ["barbell-curl", "cable-curl", "band-curl"],
  }),
  "barbell-curl": d([], [low, low, low], {
    substitutes: ["dumbbell-curl", "cable-curl"],
  }),
  "cable-curl": d([], [low, low, low], {
    substitutes: ["dumbbell-curl", "barbell-curl", "band-curl"],
  }),
  "band-curl": d([], [low, low, low], {
    substitutes: ["dumbbell-curl", "cable-curl"],
  }),
  // Triceps
  "bench-dip": d(["chest", "shoulders"], [low, low, high], {
    substitutes: ["cable-triceps-pressdown", "band-triceps-pushdown"],
  }),
  "dumbbell-overhead-triceps-extension": d([], [low, low, moderate], {
    substitutes: ["cable-triceps-pressdown"],
  }),
  "cable-triceps-pressdown": d([], [low, low, low], {
    substitutes: ["bench-dip", "dumbbell-overhead-triceps-extension", "band-triceps-pushdown"],
  }),
  "band-triceps-pushdown": d([], [low, low, low], {
    substitutes: ["bench-dip", "cable-triceps-pressdown"],
  }),
  // Lateral raise
  "dumbbell-lateral-raise": d([], [low, low, moderate], {
    substitutes: ["cable-lateral-raise"],
  }),
  "cable-lateral-raise": d([], [low, low, moderate], {
    substitutes: ["dumbbell-lateral-raise"],
  }),
  // Rear delts
  "dumbbell-rear-delt-fly": d(["back"], [low, low, low], {
    substitutes: ["face-pull", "band-pull-apart"],
  }),
  "face-pull": d(["back"], [low, low, low], {
    substitutes: ["dumbbell-rear-delt-fly", "band-pull-apart"],
  }),
  "band-pull-apart": d(["back"], [low, low, low], {
    substitutes: ["dumbbell-rear-delt-fly", "face-pull"],
  }),
  // Chest fly
  "dumbbell-chest-fly": d(["shoulders"], [low, low, high], {
    substitutes: ["cable-chest-fly", "pec-deck"],
  }),
  "cable-chest-fly": d(["shoulders"], [low, low, moderate], {
    substitutes: ["dumbbell-chest-fly", "pec-deck"],
  }),
  "pec-deck": d(["shoulders"], [low, low, moderate], {
    substitutes: ["dumbbell-chest-fly", "cable-chest-fly"],
  }),
  // Leg isolation
  "leg-extension": d([], [moderate, low, low]),
  "lying-leg-curl": d(["calves"], [low, low, low]),
};

/** The load step of an exercise's loading implement, or null. */
export function loadStepKgFor(exercise: CatalogExercise): number | null {
  const implement = loadingEquipmentOrder.value.find((item) => exercise.equipment.includes(item));
  return implement ? loadStepKgByEquipment.value[implement] : null;
}

const freezeEntry = (exercise: CatalogExercise): CatalogExerciseV2 => {
  const entry = details[exercise.slug];
  if (!entry) throw new Error(`catalog v2 has no details for ${exercise.slug}`);
  return Object.freeze({
    ...exercise,
    secondaryMuscles: Object.freeze([...entry.secondaryMuscles]),
    jointStress: Object.freeze({ ...entry.jointStress }),
    regressions: Object.freeze([...entry.regressions]),
    progressions: Object.freeze([...entry.progressions]),
    substitutes: Object.freeze([...entry.substitutes]),
    loadStepKg: loadStepKgFor(exercise),
  });
};

/** Every catalog v1 exercise, in the same order, with its v2 details. */
export const exerciseCatalogV2: readonly CatalogExerciseV2[] = Object.freeze(
  exerciseCatalogV1.map(freezeEntry),
);

export const catalogV2BySlug: ReadonlyMap<string, CatalogExerciseV2> = new Map(
  exerciseCatalogV2.map((exercise) => [exercise.slug, exercise]),
);

/** Slugs with v2 details, so a test can prove none is left without an exercise. */
export const catalogV2DetailSlugs: readonly string[] = Object.freeze(Object.keys(details));
