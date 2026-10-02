import { type HealthSummary, startsLighter } from "./health_summary.ts";
import type { DailyActivity, Goal, OnboardingAnswers, Sex } from "./answers.ts";
import type { MovementPattern } from "./catalog.ts";

// onboarding-policy-v1: the safe ranges an onboarding plan must stay inside.
// Deterministic code computes them; the model chooses within them and its plan
// is rejected outside them. Sources are in docs/ALGORITHMS.md ("Onboarding
// plan policy").

export const onboardingPolicyVersion = "onboarding-policy-v1";

/** Mifflin-St Jeor resting energy, kcal/day. */
export function mifflinStJeor(
  sex: "male" | "female",
  weightKg: number,
  heightCm: number,
  age: number,
): number {
  return 10 * weightKg + 6.25 * heightCm - 5 * age + (sex === "male" ? 5 : -161);
}

export const dailyActivityFactors: Readonly<Record<DailyActivity, number>> = Object.freeze({
  mostly_sitting: 1.2,
  some_standing: 1.375,
  mostly_standing: 1.55,
  physical_labour: 1.725,
});

/**
 * Average daily energy of the planned resistance training, kcal/day. Net
 * MET 4 (Compendium resistance training ~5 METs, minus the resting 1 MET that
 * the base factor already counts): kcal/min = 4 × 3.5 × kg / 200.
 */
export function trainingEnergyPerDay(
  weightKg: number,
  sessionMinutes: number,
  sessionsPerWeek: number,
): number {
  return (4 * 3.5 * weightKg / 200) * sessionMinutes * sessionsPerWeek / 7;
}

export const goalCalorieAdjustments: Readonly<Record<Goal, readonly [number, number]>> = Object
  .freeze({
    fat_loss: [-0.25, -0.10],
    muscle_gain: [0.05, 0.15],
    recomposition: [-0.10, 0],
    strength: [0, 0.10],
    aesthetic: [-0.05, 0.05],
  });

/**
 * The absolute nutrition bounds a 2.0 proposal may carry. They equal the
 * database check (private.is_valid_initial_proposal_v2), so a plan that passes
 * validation is always storable; policy_test.ts keeps the two equal.
 */
export const nutritionBounds = Object.freeze({
  calories: [1000, 6000] as const,
  proteinG: [30, 400] as const,
  carbohydrateG: [20, 1000] as const,
  fatG: [20, 300] as const,
});

const sexFloorKcal: Readonly<Record<Sex, number>> = Object.freeze({
  female: 1200,
  male: 1500,
  unspecified: 1500,
});

export type NutritionPolicy = Readonly<{
  /** BMR by equation; one value per applicable sex equation. */
  bmrKcal: readonly [number, number];
  tdeeKcal: readonly [number, number];
  activityFactor: number;
  floorKcal: number;
  /** The highest calorie target Tracend sets (nutritionBounds). */
  ceilingKcal: number;
  calories: readonly [number, number];
  floorApplied: boolean;
  /** The goal range was above the ceiling and was capped to it. */
  ceilingApplied: boolean;
  protein: readonly [number, number];
  /** Minimum fat in grams at a given calorie target. */
  fatMinG: (calories: number) => number;
  fatMaxG: (calories: number) => number;
  /** Carbohydrate below this (g) is flagged, not rejected. */
  carbohydrateFlagBelowG: number;
  macroTolerance: number;
}>;

const round10 = (value: number) => Math.round(value / 10) * 10;

export function nutritionPolicy(answers: OnboardingAnswers): NutritionPolicy {
  const { weightKg, heightCm, age, sex, goal } = answers;
  const equations: ("male" | "female")[] = sex === "unspecified" ? ["female", "male"] : [sex];
  const bmr = equations.map((eq) => mifflinStJeor(eq, weightKg, heightCm, age));
  const bmrLow = Math.min(...bmr);
  const bmrHigh = Math.max(...bmr);
  const factor = dailyActivityFactors[answers.dailyActivity];
  const training = trainingEnergyPerDay(
    weightKg,
    answers.sessionMinutes,
    answers.trainingWeekdays.length,
  );
  const tdeeLow = bmrLow * factor + training;
  const tdeeHigh = bmrHigh * factor + training;
  const [adjustLow, adjustHigh] = goalCalorieAdjustments[goal];
  const floor = Math.max(sexFloorKcal[sex], Math.round(bmrLow));
  // From BMI 30, protein and the fat minimum follow the weight at BMI 25, so
  // they track lean mass instead of total weight.
  const bmi = weightKg / ((heightCm / 100) ** 2);
  const referenceWeight = bmi >= 30 ? 25 * (heightCm / 100) ** 2 : weightKg;
  let low = round10(tdeeLow * (1 + adjustLow));
  let high = round10(tdeeHigh * (1 + adjustHigh));
  const floorApplied = low < floor;
  low = Math.max(low, floor);
  high = Math.max(high, low);
  // Very large estimates (a heavy athlete with a physical job training long
  // sessions) are capped, never passed on as a target nothing can store.
  const ceiling = nutritionBounds.calories[1];
  const ceilingApplied = high > ceiling;
  high = Math.min(high, ceiling);
  low = Math.min(low, high);
  const deficit = adjustHigh < 0 || goal === "recomposition";
  const [proteinMin, proteinMax] = nutritionBounds.proteinG;
  const proteinLow = Math.max(proteinMin, Math.round(1.6 * referenceWeight));
  const proteinHigh = Math.min(proteinMax, Math.round((deficit ? 2.6 : 2.2) * referenceWeight));
  return {
    bmrKcal: [Math.round(bmrLow), Math.round(bmrHigh)],
    tdeeKcal: [Math.round(tdeeLow), Math.round(tdeeHigh)],
    activityFactor: factor,
    floorKcal: floor,
    ceilingKcal: ceiling,
    calories: [low, high],
    floorApplied,
    ceilingApplied,
    protein: [proteinLow, proteinHigh],
    fatMinG: (calories) =>
      Math.max(
        nutritionBounds.fatG[0],
        Math.ceil(Math.max(0.2 * calories / 9, 0.5 * referenceWeight)),
      ),
    fatMaxG: (calories) => Math.min(nutritionBounds.fatG[1], Math.floor(0.35 * calories / 9)),
    carbohydrateFlagBelowG: Math.round(2 * weightKg),
    macroTolerance: 0.05,
  };
}

export type Split = "full_body" | "upper_lower" | "upper_lower_push_pull_legs" | "push_pull_legs";

export function splitForDays(days: number): Split {
  if (days <= 3) return "full_body";
  if (days === 4) return "upper_lower";
  if (days === 5) return "upper_lower_push_pull_legs";
  return "push_pull_legs";
}

export type TrainingPolicy = Readonly<{
  split: Split;
  blockWeeks: readonly [number, number];
  setBudgetPerSession: number;
  maxExercisesPerSession: number;
  maxWeeklySetsPerMuscle: number;
  setsPerExercise: readonly [number, number];
  reps: readonly [number, number];
  rpe: readonly [number, number];
  restSeconds: readonly [number, number];
  /** Minutes a session may run over the athlete's chosen length. */
  sessionOverrunMinutes: number;
  /**
   * Each week must include one movement from every group. A pattern the
   * athlete avoids is not required, and a group they avoid entirely is dropped.
   */
  requiredPatternGroups: readonly (readonly MovementPattern[])[];
  avoidPatterns: readonly MovementPattern[];
  /**
   * Apple Health shows short sleep, so the first block keeps effort half an
   * RPE point lower. Only this policy changes effort or volume limits.
   */
  startLighter: boolean;
}>;

const patternGroups: readonly (readonly MovementPattern[])[] = [
  ["squat", "lunge"],
  ["hinge"],
  ["horizontal_push", "vertical_push"],
  ["horizontal_pull", "vertical_pull"],
];

export function trainingPolicy(
  answers: OnboardingAnswers,
  health: HealthSummary | null = null,
): TrainingPolicy {
  const minutes = answers.sessionMinutes;
  const strength = answers.goal === "strength";
  const beginner = answers.experience === "beginner";
  const avoid: readonly MovementPattern[] = answers.avoidPatterns;
  const lighter = startsLighter(health);
  const rpeHigh = (beginner ? 8.5 : 9) - (lighter ? 0.5 : 0);
  return {
    split: splitForDays(answers.trainingWeekdays.length),
    blockWeeks: [4, 8],
    setBudgetPerSession: Math.min(30, Math.floor(minutes / 3)),
    maxExercisesPerSession: Math.min(8, 2 + Math.floor(minutes / 15)),
    maxWeeklySetsPerMuscle: beginner ? 12 : 20,
    setsPerExercise: [1, 5],
    reps: [strength ? 3 : 6, 20],
    rpe: [7, rpeHigh],
    restSeconds: [60, strength ? 240 : 180],
    sessionOverrunMinutes: Math.max(5, Math.round(minutes * 0.15)),
    requiredPatternGroups: patternGroups
      .map((group) => group.filter((pattern) => !avoid.includes(pattern)))
      .filter((group) => group.length > 0),
    avoidPatterns: avoid,
    startLighter: lighter,
  };
}

/**
 * Minutes a workout takes: 8 minutes of warm-up, then 45 seconds of work plus
 * the prescribed rest for every set. Deterministic code sets every workout's
 * estimated_minutes with this, whatever the model said.
 */
export function estimateWorkoutMinutes(
  exercises: readonly Readonly<{ sets: number; rest_seconds: number }>[],
): number {
  const work = exercises.reduce(
    (total, exercise) => total + exercise.sets * (0.75 + exercise.rest_seconds / 60),
    0,
  );
  return Math.min(180, Math.max(15, Math.round(8 + work)));
}

/** The highest confidence a plan may claim, given what the answers leave out. */
export function confidenceCap(
  answers: OnboardingAnswers,
  nutrition: NutritionPolicy,
): "low" | "medium" {
  if (nutrition.floorApplied || nutrition.ceilingApplied) return "low";
  if (answers.sex === "unspecified") return "low";
  // Targets are first estimates until weigh-ins confirm them (2-3 weeks).
  return "medium";
}
