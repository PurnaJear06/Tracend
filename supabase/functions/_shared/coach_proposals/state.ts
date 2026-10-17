// Reads the database payloads into the athlete state the builder uses. A payload that is missing a
// field the rules need yields no state at all: a change is never sized from a guess.
import {
  dailyActivities,
  type DailyActivity,
  type Goal,
  goals,
  type Sex,
  sexes,
} from "../onboarding/answers.ts";
import {
  type AvoidablePattern,
  avoidablePatterns,
  type EquipmentItem,
  equipmentItems,
  type Muscle,
  muscles,
} from "../onboarding/catalog.ts";
import { parseGoalPhaseInputs, summarizeGoalPhase } from "../training/goal_phase/index.ts";
import { screeningOutcomes } from "../training/screening/outcome.ts";
import { parseProgressionSummary } from "../training/progression/targets.ts";
import {
  type AthleteState,
  type BlockKind,
  type GoalPhase,
  goalPhases,
  type StateGoal,
  type StateNutrition,
  type StatePlan,
} from "./types.ts";

type Json = Record<string, unknown>;

const record = (value: unknown): Json | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value as Json : null;
const num = (value: unknown): number | null =>
  typeof value === "number" && Number.isFinite(value) ? value : null;
const whole = (value: unknown): number | null => {
  const n = num(value);
  return n !== null && Number.isInteger(n) ? n : null;
};
const str = (value: unknown): string | null => typeof value === "string" ? value : null;
const list = (value: unknown): unknown[] => Array.isArray(value) ? value : [];
const oneOf = <T extends string>(options: readonly T[], value: unknown): T | null =>
  options.find((option) => option === value) ?? null;
const many = <T extends string>(options: readonly T[], value: unknown): T[] =>
  options.filter((option) => list(value).includes(option));

const blockKinds: readonly BlockKind[] = ["temporary_block", "intensity", "focus", "next_session"];

function parsePlan(raw: unknown): StatePlan | null | undefined {
  if (raw === null || raw === undefined) return null;
  const plan = record(raw);
  if (!plan) return undefined;
  const workouts = list(plan.workouts).map((item) => {
    const workout = record(item);
    if (!workout) return null;
    const exercises = list(workout.exercises).map((entry) => {
      const exercise = record(entry);
      if (!exercise) return null;
      const sets = whole(exercise.sets);
      const repMin = whole(exercise.rep_min);
      const repMax = whole(exercise.rep_max);
      const rest = whole(exercise.rest_seconds);
      const name = str(exercise.name);
      if (sets === null || repMin === null || repMax === null || rest === null || !name) {
        return null;
      }
      return {
        slug: str(exercise.slug),
        name,
        sets,
        repMin,
        repMax,
        targetRpe: num(exercise.target_rpe),
        restSeconds: rest,
        notes: str(exercise.notes) ?? "",
        targetLoadKg: num(exercise.target_load_kg),
      };
    });
    const name = str(workout.name);
    const minutes = whole(workout.estimated_minutes);
    if (!name || minutes === null || exercises.length === 0 || exercises.includes(null)) {
      return null;
    }
    return {
      name,
      objective: str(workout.objective) ?? "",
      weekday: whole(workout.weekday),
      estimatedMinutes: minutes,
      warmUp: str(workout.warm_up) ?? "",
      coolDown: str(workout.cool_down) ?? "",
      exercises: exercises as NonNullable<typeof exercises[number]>[],
    };
  });
  const versionId = str(plan.version_id);
  const planId = str(plan.plan_id);
  const title = str(plan.title);
  const versionNumber = whole(plan.version_number);
  const blockWeeks = whole(plan.block_weeks);
  if (
    !versionId || !planId || !title || versionNumber === null || blockWeeks === null ||
    workouts.length === 0 || workouts.includes(null)
  ) return undefined;
  return {
    versionId,
    planId,
    versionNumber,
    title,
    blockWeeks,
    workouts: workouts as NonNullable<typeof workouts[number]>[],
    blockEndsOn: str(plan.ends_on),
    blockKind: oneOf(blockKinds, plan.block_kind),
  };
}

export type StateSources = Readonly<{
  /** get_coach_proposal_inputs_v1 */
  inputs: unknown;
  /** get_goal_phase_inputs_v1 */
  goalPhase: unknown;
  /** get_progression_summary_v1 */
  progression: unknown;
  athleteMessage?: string;
}>;

/** The athlete state, or null when the payloads leave out something the rules need. */
export function parseAthleteState(sources: StateSources): AthleteState | null {
  const root = record(sources.inputs);
  const profile = record(root?.profile);
  if (!root || !profile) return null;
  const today = str(root.local_date);
  const sex = oneOf<Sex>(sexes, profile.sex);
  const birthYear = whole(profile.birth_year);
  const heightCm = num(profile.height_cm);
  const experience = oneOf(["beginner", "intermediate", "advanced"] as const, profile.experience);
  const activity = oneOf<DailyActivity>(dailyActivities, profile.daily_activity);
  const days = list(profile.training_days).map(whole);
  const sessionMinutes = whole(profile.session_minutes);
  const screening = oneOf(screeningOutcomes, root.screening);
  if (
    !today || !sex || birthYear === null || heightCm === null || !experience || !activity ||
    days.length === 0 || days.includes(null) || sessionMinutes === null || !screening
  ) return null;
  const plan = parsePlan(root.plan);
  if (plan === undefined) return null;

  const nutritionRow = record(root.nutrition);
  const nutrition: StateNutrition | null = nutritionRow
    ? {
      versionId: str(nutritionRow.version_id) ?? "",
      calories: num(nutritionRow.calories) ?? NaN,
      proteinG: num(nutritionRow.protein_g) ?? NaN,
      carbohydrateG: num(nutritionRow.carbohydrate_g) ?? NaN,
      fatG: num(nutritionRow.fat_g) ?? NaN,
    }
    : null;
  if (
    nutrition &&
    (!nutrition.versionId ||
      [nutrition.calories, nutrition.proteinG, nutrition.carbohydrateG, nutrition.fatG].some(
        Number.isNaN,
      ))
  ) return null;

  const phaseInputs = parseGoalPhaseInputs(sources.goalPhase, today);
  const goalPhase = summarizeGoalPhase(phaseInputs);
  const goalRow = record(root.goal);
  let goal: StateGoal | null = null;
  if (goalRow) {
    const id = str(goalRow.id);
    const goalType = oneOf<Goal>(goals, goalRow.goal_type);
    if (!id || !goalType) return null;
    const details = record(goalRow.details) ?? {};
    goal = {
      id,
      goalType,
      activatedOn: str(goalRow.activated_on),
      target: phaseInputs.target,
      phase: oneOf<GoalPhase>(goalPhases, details.phase),
      phaseEndsOn: str(details.phase_ends_on),
    };
  }

  const eligibility = record(root.eligibility);
  if (!eligibility) return null;
  const age = Number(today.slice(0, 4)) - birthYear;
  return {
    today,
    profile: {
      sex,
      age,
      birthYear,
      heightCm,
      // The rules treat everyone above a beginner as intermediate (onboarding answers).
      experience: experience === "beginner" ? "beginner" : "intermediate",
      dailyActivity: activity,
      equipment: many<EquipmentItem>(equipmentItems, profile.equipment),
      avoidPatterns: many<AvoidablePattern>(avoidablePatterns, profile.avoid_patterns),
      trainingWeekdays: (days as number[]).sort((a, b) => a - b),
      sessionMinutes,
      priorityMuscles: many<Muscle>(muscles, profile.priority_muscles),
      strongMuscles: many<Muscle>(muscles, profile.strong_muscles),
    },
    screening,
    plan,
    nutrition,
    goal,
    goalPhase,
    eligibility: {
      trainingEligible: eligibility.training_eligible === true,
      trainingDetail: str(eligibility.training_detail) ?? "",
      nutritionEligible: eligibility.nutrition_eligible === true,
      nutritionDetail: str(eligibility.nutrition_detail) ?? "",
    },
    progression: parseProgressionSummary(sources.progression),
    todayWorkoutDone: root.today_workout_done === true,
    ...(sources.athleteMessage === undefined ? {} : { athleteMessage: sources.athleteMessage }),
  };
}
