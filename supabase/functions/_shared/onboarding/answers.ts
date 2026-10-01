import { type EquipmentItem, equipmentItems } from "./catalog.ts";

// The reviewed onboarding answers an onboarding plan is built from, parsed
// from onboarding_drafts.payload. Old drafts (before 2026-10) lack the body,
// schedule and equipment fields; they get a list of what is missing, never
// invented values.

export const goals = ["fat_loss", "muscle_gain", "recomposition", "strength", "aesthetic"] as const;
export type Goal = typeof goals[number];
export const sexes = ["male", "female", "unspecified"] as const;
export type Sex = typeof sexes[number];
export const dailyActivities = [
  "mostly_sitting",
  "some_standing",
  "mostly_standing",
  "physical_labour",
] as const;
export type DailyActivity = typeof dailyActivities[number];

export const answerLimits = Object.freeze({
  minAge: 18,
  maxAge: 100,
  minHeightCm: 120,
  maxHeightCm: 230,
  minWeightKg: 35,
  maxWeightKg: 250,
  maxTrainingDays: 6,
  minSessionMinutes: 30,
  maxSessionMinutes: 120,
  maxNoteLength: 500,
});

export type OnboardingAnswers = Readonly<{
  path: "beginner" | "experienced";
  experience: "beginner" | "intermediate";
  goal: Goal;
  sex: Sex;
  birthYear: number;
  age: number;
  heightCm: number;
  weightKg: number;
  targetWeightKg: number | null;
  dailyActivity: DailyActivity;
  /** ISO weekdays, 1 = Monday, ascending and unique. */
  trainingWeekdays: readonly number[];
  sessionMinutes: number;
  equipment: readonly EquipmentItem[];
  equipmentNote: string;
  nutritionContext: string;
  limitations: string;
  currentPlan: string;
  revisionNote: string;
}>;

export type AnswersResult =
  | { ok: true; answers: OnboardingAnswers }
  | { ok: false; missing: string[] };

const text = (value: unknown): string =>
  typeof value === "string" ? value.trim().slice(0, answerLimits.maxNoteLength) : "";

const integer = (value: unknown): number | null =>
  typeof value === "number" && Number.isFinite(value) ? Math.round(value) : null;

const within = (value: number | null, min: number, max: number): value is number =>
  value !== null && value >= min && value <= max;

export function parseOnboardingAnswers(
  path: unknown,
  payload: Record<string, unknown>,
  currentYear: number,
): AnswersResult {
  const missing: string[] = [];
  if (path !== "beginner" && path !== "experienced") missing.push("path");
  const goal = goals.find((item) => item === payload.goal);
  if (!goal) missing.push("goal");
  const sex = sexes.find((item) => item === payload.sex);
  if (!sex) missing.push("sex");
  const birthYear = integer(payload.birth_year);
  const age = birthYear === null ? null : currentYear - birthYear;
  if (!within(age, answerLimits.minAge, answerLimits.maxAge)) missing.push("birth_year");
  const heightCm = integer(payload.height_cm);
  if (!within(heightCm, answerLimits.minHeightCm, answerLimits.maxHeightCm)) {
    missing.push("height_cm");
  }
  const weightKg = typeof payload.weight_kg === "number" ? payload.weight_kg : null;
  if (!within(weightKg, answerLimits.minWeightKg, answerLimits.maxWeightKg)) {
    missing.push("weight_kg");
  }
  const target = typeof payload.target_weight_kg === "number" ? payload.target_weight_kg : null;
  const targetWeightKg = within(target, answerLimits.minWeightKg, answerLimits.maxWeightKg)
    ? Math.round(target * 10) / 10
    : null;
  const dailyActivity = dailyActivities.find((item) => item === payload.daily_activity);
  if (!dailyActivity) missing.push("daily_activity");
  const weekdays = Array.isArray(payload.training_weekdays)
    ? [
      ...new Set(
        payload.training_weekdays.filter((day): day is number =>
          Number.isInteger(day) && day >= 1 && day <= 7
        ),
      ),
    ].sort((a, b) => a - b)
    : [];
  if (weekdays.length < 1 || weekdays.length > answerLimits.maxTrainingDays) {
    missing.push("training_weekdays");
  }
  const sessionMinutes = integer(payload.session_minutes);
  if (
    !within(sessionMinutes, answerLimits.minSessionMinutes, answerLimits.maxSessionMinutes)
  ) {
    missing.push("session_minutes");
  }
  const equipment = Array.isArray(payload.equipment_items)
    ? equipmentItems.filter((item) => (payload.equipment_items as unknown[]).includes(item))
    : null;
  if (equipment === null) missing.push("equipment_items");
  const currentPlan = text(payload.current_plan);
  if (path === "experienced" && !currentPlan) missing.push("current_plan");

  if (missing.length) return { ok: false, missing };
  return {
    ok: true,
    answers: {
      path: path as "beginner" | "experienced",
      experience: path === "experienced" ? "intermediate" : "beginner",
      goal: goal!,
      sex: sex!,
      birthYear: birthYear!,
      age: age!,
      heightCm: heightCm!,
      weightKg: Math.round(weightKg! * 10) / 10,
      targetWeightKg,
      dailyActivity: dailyActivity!,
      trainingWeekdays: weekdays,
      sessionMinutes: sessionMinutes!,
      equipment: equipment!,
      equipmentNote: text(payload.equipment),
      nutritionContext: text(payload.nutrition_context),
      limitations: text(payload.constraints),
      currentPlan,
      revisionNote: text(payload.revision_note),
    },
  };
}

/** The answers as stored in the onboarding feature snapshot and read by approval. */
export function answersSnapshot(answers: OnboardingAnswers): Record<string, unknown> {
  return {
    path: answers.path,
    experience: answers.experience,
    goal: answers.goal,
    sex: answers.sex,
    birth_year: answers.birthYear,
    height_cm: answers.heightCm,
    weight_kg: answers.weightKg,
    target_weight_kg: answers.targetWeightKg,
    daily_activity: answers.dailyActivity,
    training_weekdays: answers.trainingWeekdays,
    session_minutes: answers.sessionMinutes,
    equipment_items: answers.equipment,
    equipment_note: answers.equipmentNote,
    nutrition_context: answers.nutritionContext,
    limitations: answers.limitations,
    current_plan: answers.currentPlan,
    revision_note: answers.revisionNote,
  };
}
