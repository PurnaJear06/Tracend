import {
  type AvoidablePattern,
  avoidablePatterns,
  type EquipmentItem,
  equipmentItems,
  type Muscle,
  muscles,
} from "./catalog.ts";

// The reviewed onboarding answers an onboarding plan is built from, parsed
// from onboarding_drafts.payload. Old drafts (before 2026-10) lack the body,
// schedule and equipment fields, and a draft with a written limitation but no
// movements-to-avoid answer is incomplete; they get a list of what is missing,
// never invented values.

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

export const trainingYears = ["under_1", "1_2", "3_5", "over_5"] as const;
export type TrainingYears = typeof trainingYears[number];

/**
 * The lifts an athlete can report a recent top set for. Barbell only: the load
 * is the whole bar, so it means the same thing in every gym (ALGORITHMS §9).
 * Dumbbells, cables, machines and pull-ups wait until their load basis is
 * represented.
 */
export const reportableLifts = [
  "barbell-bench-press",
  "barbell-back-squat",
  "barbell-deadlift",
  "barbell-overhead-press",
  "barbell-row",
] as const;
export type ReportableLift = typeof reportableLifts[number];

export type ReportedLift = Readonly<{
  slug: ReportableLift;
  loadKg: number;
  reps: number;
  /** Reps the athlete could still have done; 0 means the set was to failure. */
  repsLeft: number;
}>;

/** The topics a follow-up question may ask about (AI_SAFETY_SPEC §10). */
export const followUpCategories = [
  "split_history",
  "recovery_between_sessions",
  "stalled_lift",
  "exercise_preference",
  "schedule_flexibility",
  "nutrition_routine",
] as const;
export type FollowUpCategory = typeof followUpCategories[number];

export type FollowUp = Readonly<{ category: FollowUpCategory; question: string; answer: string }>;

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
  maxLiftLoadKg: 2000,
  maxLiftReps: 15,
  maxRepsLeft: 4,
  maxPriorityMuscles: 2,
  maxStrongMuscles: 3,
  maxFollowUps: 3,
  maxFollowUpQuestionLength: 160,
  maxFollowUpAnswerLength: 300,
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
  /** Movement patterns the plan must leave out; every path enforces them. */
  avoidPatterns: readonly AvoidablePattern[];
  currentPlan: string;
  /** Null on drafts from before the question existed. */
  trainingYears: TrainingYears | null;
  /** What has worked and what has stalled, in the athlete's words. */
  trainingHistory: string;
  currentLifts: readonly ReportedLift[];
  /** At most two muscles the plan gives a weekly set minimum. */
  priorityMuscles: readonly Muscle[];
  strongMuscles: readonly Muscle[];
  /** Answers to the coach's follow-up questions for exactly these answers. */
  followUps: readonly FollowUp[];
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

const muscleList = (value: unknown, max: number): Muscle[] =>
  Array.isArray(value) ? muscles.filter((muscle) => value.includes(muscle)).slice(0, max) : [];

/** Valid reported lifts, one per lift, in catalog order; anything else is dropped. */
function liftList(value: unknown): ReportedLift[] {
  if (!Array.isArray(value)) return [];
  const lifts: ReportedLift[] = [];
  for (const slug of reportableLifts) {
    const entry = value.find((item) =>
      item && typeof item === "object" && (item as Record<string, unknown>).slug === slug
    ) as Record<string, unknown> | undefined;
    if (!entry) continue;
    const load = typeof entry.load_kg === "number" ? entry.load_kg : null;
    const reps = integer(entry.reps);
    const repsLeft = integer(entry.reps_left);
    if (
      within(load, 1, answerLimits.maxLiftLoadKg) && within(reps, 1, answerLimits.maxLiftReps) &&
      within(repsLeft, 0, answerLimits.maxRepsLeft)
    ) {
      lifts.push({ slug, loadKg: Math.round(load * 2) / 2, reps, repsLeft });
    }
  }
  return lifts;
}

/**
 * The follow-up answers, used only when they were asked for these answers:
 * the app stores the questions' hash with them, and an edited earlier answer
 * changes the hash, so stale follow-ups are never read.
 */
function followUpList(value: unknown): FollowUp[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item): FollowUp[] => {
    if (!item || typeof item !== "object") return [];
    const entry = item as Record<string, unknown>;
    const category = followUpCategories.find((name) => name === entry.category);
    const question = typeof entry.question === "string"
      ? entry.question.trim().slice(0, answerLimits.maxFollowUpQuestionLength)
      : "";
    const answer = typeof entry.answer === "string"
      ? entry.answer.trim().slice(0, answerLimits.maxFollowUpAnswerLength)
      : "";
    return category && question && answer ? [{ category, question, answer }] : [];
  }).slice(0, answerLimits.maxFollowUps);
}

export function parseOnboardingAnswers(
  path: unknown,
  payload: Record<string, unknown>,
  currentYear: number,
  /** The hash follow-ups must carry to count; null reads none. */
  followUpsHash: string | null = null,
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
  const limitations = text(payload.constraints);
  // A written limitation needs the structured answer too: the rules plan cannot
  // read the note, so it must not guess which movements to leave out.
  const avoidPatterns = Array.isArray(payload.avoid_patterns)
    ? avoidablePatterns.filter((item) => (payload.avoid_patterns as unknown[]).includes(item))
    : null;
  if (avoidPatterns === null && limitations) missing.push("avoid_patterns");

  const years = trainingYears.find((item) => item === payload.training_years) ?? null;

  if (missing.length) return { ok: false, missing };
  const experienced = path === "experienced";
  return {
    ok: true,
    answers: {
      path: path as "beginner" | "experienced",
      // Under a year of training keeps the beginner limits; older experienced
      // drafts without the answer stay intermediate, as they were built.
      experience: experienced && years !== "under_1" ? "intermediate" : "beginner",
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
      limitations,
      avoidPatterns: avoidPatterns ?? [],
      currentPlan,
      trainingYears: experienced ? years : null,
      trainingHistory: experienced ? text(payload.training_history) : "",
      currentLifts: experienced ? liftList(payload.current_lifts) : [],
      priorityMuscles: muscleList(payload.priority_muscles, answerLimits.maxPriorityMuscles),
      strongMuscles: muscleList(payload.strong_muscles, answerLimits.maxStrongMuscles),
      followUps: followUpsHash !== null && payload.follow_ups_hash === followUpsHash
        ? followUpList(payload.follow_ups)
        : [],
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
    avoid_patterns: answers.avoidPatterns,
    current_plan: answers.currentPlan,
    training_years: answers.trainingYears,
    training_history: answers.trainingHistory,
    current_lifts: answers.currentLifts.map((lift) => ({
      slug: lift.slug,
      load_kg: lift.loadKg,
      reps: lift.reps,
      reps_left: lift.repsLeft,
    })),
    priority_muscles: answers.priorityMuscles,
    strong_muscles: answers.strongMuscles,
    follow_ups: answers.followUps,
    revision_note: answers.revisionNote,
  };
}
