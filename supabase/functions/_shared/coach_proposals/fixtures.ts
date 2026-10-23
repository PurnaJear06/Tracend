// Athlete states for the proposal tests: a 32-year-old man with a gym plan built by the rules, a
// month of weigh-ins, an active fat-loss goal and complete logging.
import { exerciseCatalogV1 } from "../onboarding/catalog.ts";
import { policiesFor, validRulesPlan } from "../onboarding/generate.ts";
import { buildOnboardingProposal } from "../onboarding/plan_contract.ts";
import { answersFor, equipmentSets } from "../onboarding/test_helpers.ts";
import { summarizeGoalPhase } from "../training/goal_phase/summary.ts";
import { noGoalTarget } from "../training/goal_phase/types.ts";
import { addDays } from "./common.ts";
import type { AthleteState, StateNutrition, StatePlan, TrainingPayloadWorkout } from "./types.ts";

export const today = "2026-10-18";

export const baseAnswers = answersFor({
  goal: "fat_loss",
  experience: "intermediate",
  path: "experienced",
  weightKg: 80,
  trainingWeekdays: [1, 3, 5],
  sessionMinutes: 60,
  equipment: equipmentSets.gym,
});

/** A stable planned exercise id for the fixture plan: workout index, then exercise position. */
export const plannedExerciseIdFor = (workout: number, exercise: number) =>
  `00000000-0000-4000-8000-${String(workout).padStart(6, "0")}${String(exercise).padStart(6, "0")}`;

export function planFor(
  weekdays: readonly number[],
  overrides: Partial<StatePlan> = {},
): StatePlan {
  const answers = { ...baseAnswers, trainingWeekdays: weekdays };
  const policies = policiesFor(answers, exerciseCatalogV1);
  const built = validRulesPlan(policies);
  const training = buildOnboardingProposal(built, policies, {
    origin: "rules",
    provider: null,
    model: null,
    fallbackReason: null,
  }).training;
  const workouts = (training.weekly_structure as TrainingPayloadWorkout[]).map((
    workout,
    index,
  ) => ({
    name: workout.name,
    objective: workout.objective,
    weekday: workout.preferred_weekday,
    estimatedMinutes: workout.estimated_minutes,
    warmUp: workout.warm_up_guidance,
    coolDown: workout.cool_down_guidance,
    exercises: workout.exercises.map((exercise, order) => ({
      plannedExerciseId: plannedExerciseIdFor(index, order),
      slug: exercise.slug,
      name: exercise.name,
      sets: exercise.sets,
      repMin: exercise.rep_min,
      repMax: exercise.rep_max,
      targetRpe: exercise.target_rpe,
      restSeconds: exercise.rest_seconds,
      notes: exercise.notes,
      targetLoadKg: exercise.start_load_kg ?? null,
    })),
  }));
  return {
    versionId: "11111111-1111-4111-8111-111111111111",
    planId: "22222222-2222-4222-8222-222222222222",
    versionNumber: 1,
    title: training.title as string,
    blockWeeks: training.block_weeks as number,
    workouts,
    blockEndsOn: null,
    blockKind: null,
    ...overrides,
  };
}

/** Thirty daily readings drifting down about 0.05 kg a day to 80 kg on the last day. */
export function weightReadings(days = 30, endKg = 80) {
  return Array.from({ length: days }, (_, index) => ({
    date: addDays(today, index - days + 1),
    kg: Math.round((endKg + (days - 1 - index) * 0.05) * 10) / 10,
  }));
}

export const nutritionFixture: StateNutrition = {
  versionId: "33333333-3333-4333-8333-333333333333",
  calories: 2300,
  proteinG: 170,
  carbohydrateG: 240,
  fatG: 75,
};

export function stateFixture(overrides: Partial<AthleteState> = {}): AthleteState {
  const goalPhase = summarizeGoalPhase({
    today,
    goalType: "fat_loss",
    activatedOn: addDays(today, -40),
    heightCm: 176,
    target: noGoalTarget,
    readings: weightReadings(),
  });
  return {
    today,
    profile: {
      sex: "male",
      age: 32,
      birthYear: 1994,
      heightCm: 176,
      experience: "intermediate",
      dailyActivity: "mostly_sitting",
      equipment: equipmentSets.gym,
      avoidPatterns: [],
      trainingWeekdays: [1, 3, 5],
      sessionMinutes: 60,
      priorityMuscles: [],
      strongMuscles: [],
    },
    screening: "cleared",
    plan: planFor([1, 3, 5]),
    nutrition: nutritionFixture,
    goal: {
      id: "44444444-4444-4444-8444-444444444444",
      goalType: "fat_loss",
      activatedOn: addDays(today, -40),
      target: noGoalTarget,
      phase: null,
      phaseEndsOn: null,
    },
    goalPhase,
    eligibility: {
      trainingEligible: true,
      trainingDetail: "3 comparable sessions in last 14 days",
      nutritionEligible: true,
      nutritionDetail: "24 weight days, 88% adherence, trend r2=0.61",
    },
    progression: [],
    todayWorkoutDone: false,
    ...overrides,
  };
}

/** The database payloads for the fixture athlete, as the three service-role RPCs return them. */
export function proposalRpcPayloads() {
  const state = stateFixture();
  const plan = state.plan!;
  return {
    inputs: {
      schema_version: "1.1",
      local_date: today,
      screening: "cleared",
      profile: {
        sex: "male",
        birth_year: 1994,
        height_cm: 176,
        experience: "intermediate",
        daily_activity: "mostly_sitting",
        equipment: state.profile.equipment,
        avoid_patterns: [],
        training_days: [1, 3, 5],
        session_minutes: 60,
        priority_muscles: null,
        strong_muscles: null,
      },
      plan: {
        version_id: plan.versionId,
        plan_id: plan.planId,
        version_number: 1,
        title: plan.title,
        block_weeks: plan.blockWeeks,
        ends_on: null,
        block_kind: null,
        workouts: plan.workouts.map((workout) => ({
          name: workout.name,
          objective: workout.objective,
          weekday: workout.weekday,
          estimated_minutes: workout.estimatedMinutes,
          warm_up: workout.warmUp,
          cool_down: workout.coolDown,
          exercises: workout.exercises.map((exercise) => ({
            planned_exercise_id: exercise.plannedExerciseId,
            slug: exercise.slug,
            name: exercise.name,
            sets: exercise.sets,
            rep_min: exercise.repMin,
            rep_max: exercise.repMax,
            target_rpe: exercise.targetRpe,
            rest_seconds: exercise.restSeconds,
            notes: exercise.notes,
            target_load_kg: exercise.targetLoadKg,
          })),
        })),
      },
      nutrition: {
        version_id: state.nutrition!.versionId,
        calories: 2300,
        protein_g: 170,
        carbohydrate_g: 240,
        fat_g: 75,
      },
      goal: {
        id: state.goal!.id,
        goal_type: "fat_loss",
        details: { description: "Lean out" },
        activated_on: addDays(today, -40),
      },
      eligibility: {
        training_eligible: true,
        training_detail: "3 comparable sessions in last 14 days",
        nutrition_eligible: true,
        nutrition_detail: "24 weight days, 88% adherence, trend r2=0.61",
      },
      today_workout_done: false,
    },
    goalPhase: {
      schema_version: "1.0",
      height_cm: 176,
      goal: {
        goal_type: "fat_loss",
        activated_on: addDays(today, -40),
        target: {
          weight_kg: null,
          body_fat_pct_min: null,
          body_fat_pct_max: null,
          physique: null,
          physique_note: null,
          date: null,
        },
      },
      readings: weightReadings(),
    },
    progression: { schema_version: "1.0", targets: [] },
  };
}
