// Pieces every proposal builder shares: the onboarding answers rebuilt from the athlete's state,
// the card's wording for a reason, snapshots of a plan for the before and after columns, and date
// arithmetic on ISO dates.
import type { OnboardingAnswers } from "../onboarding/answers.ts";
import { shiftDate } from "../onboarding/health_summary.ts";
import { estimateWorkoutMinutes } from "../onboarding/policy.ts";
import type {
  AthleteState,
  DisplaySession,
  ProposalBasis,
  ProposalReason,
  StatePlan,
  StatePlanWorkout,
  TrainingPayloadWorkout,
} from "./types.ts";

/** The onboarding answers the rules read, rebuilt from the athlete's stored profile and weight. */
export function answersFromState(
  state: AthleteState,
  weightKg: number,
  overrides: Partial<OnboardingAnswers> = {},
): OnboardingAnswers {
  const { profile, goal } = state;
  return {
    path: "experienced",
    experience: profile.experience,
    goal: goal?.goalType ?? "recomposition",
    sex: profile.sex,
    birthYear: profile.birthYear,
    age: profile.age,
    heightCm: profile.heightCm,
    weightKg,
    targetWeightKg: goal?.target.weightKg ?? null,
    dailyActivity: profile.dailyActivity,
    trainingWeekdays: profile.trainingWeekdays,
    sessionMinutes: profile.sessionMinutes,
    equipment: profile.equipment,
    equipmentNote: "",
    nutritionContext: "",
    limitations: "",
    avoidPatterns: profile.avoidPatterns,
    currentPlan: "",
    trainingYears: null,
    trainingHistory: "",
    currentLifts: [],
    priorityMuscles: profile.priorityMuscles,
    strongMuscles: profile.strongMuscles,
    followUps: [],
    revisionNote: "",
    ...overrides,
  };
}

/** The athlete's latest usable weight, or null when there is none within two weeks. */
export function currentWeightKg(state: AthleteState): number | null {
  const summary = state.goalPhase;
  if (summary.currentWeightKg === null || summary.latestReadingStale) return null;
  return summary.currentWeightKg;
}

const reasonSentences: Readonly<Record<ProposalReason, string>> = {
  travel: "You're away from your usual setup.",
  time: "Your week is tighter than usual.",
  fatigue: "You've been feeling worn down.",
  missed_sessions: "You've missed sessions lately.",
  illness_recovery: "You're coming back from being unwell.",
  plateau: "Progress has stalled.",
  preference: "It's what you'd rather do right now.",
  equipment_change: "Your equipment has changed.",
  diet_fatigue: "Dieting has been wearing on you.",
  injury_caution: "You want to be careful with an area that bothers you.",
  athlete_request: "You asked for this change.",
};

/** The reason in the card's words, plus the athlete's own note when it has no figures in it. */
export function reasonText(reason: ProposalReason, note?: string): string {
  return note ? `${reasonSentences[reason]} In your words: "${note}"` : reasonSentences[reason];
}

/** Hours an unanswered proposal stays open, by kind. */
export const proposalExpiryHours = Object.freeze({
  default: 72,
  next_session: 24,
});

export function isoWeekday(date: string): number {
  const day = new Date(`${date}T00:00:00Z`).getUTCDay();
  return day === 0 ? 7 : day;
}

/** Whole days from `from` to `to` (negative when `to` is earlier). */
export function daysBetween(from: string, to: string): number {
  return Math.round(
    (new Date(`${to}T00:00:00Z`).getTime() - new Date(`${from}T00:00:00Z`).getTime()) / 86_400_000,
  );
}

export const addDays = (date: string, days: number) => shiftDate(date, -days);

const weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] as const;
export const weekdayName = (weekday: number | null) =>
  weekday === null ? "" : weekdayNames[weekday - 1];

const monthNames = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
] as const;
/** "25 Oct" for 2026-10-25. */
export function shortDate(date: string): string {
  const [, month, day] = date.split("-").map(Number);
  return `${day} ${monthNames[month - 1]}`;
}

export function sessionSummary(
  workouts: readonly Pick<
    StatePlanWorkout,
    "name" | "weekday" | "estimatedMinutes" | "exercises"
  >[],
): DisplaySession[] {
  return workouts.map((workout) => ({
    weekday: workout.weekday,
    name: workout.name,
    exercises: workout.exercises.length,
    minutes: workout.estimatedMinutes,
  }));
}

export function payloadSessionSummary(
  workouts: readonly TrainingPayloadWorkout[],
): DisplaySession[] {
  return workouts.map((workout) => ({
    weekday: workout.preferred_weekday,
    name: workout.name,
    exercises: workout.exercises.length,
    minutes: workout.estimated_minutes,
  }));
}

/** A stored plan as the payload shape approval writes. */
export function planAsPayload(plan: StatePlan): TrainingPayloadWorkout[] {
  return plan.workouts.map((workout, index) => ({
    workout_order: index + 1,
    name: workout.name,
    objective: workout.objective,
    preferred_weekday: workout.weekday,
    estimated_minutes: workout.estimatedMinutes,
    warm_up_guidance: workout.warmUp,
    cool_down_guidance: workout.coolDown,
    exercises: workout.exercises.map((exercise, order) => ({
      exercise_order: order + 1,
      slug: exercise.slug,
      name: exercise.name,
      sets: exercise.sets,
      rep_min: exercise.repMin,
      rep_max: exercise.repMax,
      target_rpe: exercise.targetRpe,
      rest_seconds: exercise.restSeconds,
      notes: exercise.notes,
      ...(exercise.targetLoadKg === null ? {} : { start_load_kg: exercise.targetLoadKg }),
    })),
  }));
}

/** A workout's length after its exercises changed: the same estimate onboarding uses. */
export function minutesFor(exercises: readonly { sets: number; rest_seconds: number }[]): number {
  return estimateWorkoutMinutes(exercises);
}

export function basisOf(
  state: AthleteState,
  gates: ProposalBasis["gates"] = [],
): ProposalBasis {
  return {
    training_version_id: state.plan?.versionId ?? null,
    nutrition_version_id: state.nutrition?.versionId ?? null,
    goal_id: state.goal?.id ?? null,
    screening: state.screening,
    gates,
  };
}

/** Plain text of a figure from the athlete's message with thousands separators removed. */
export function messageHasFigure(message: string | undefined, figure: number): boolean {
  if (message === undefined) return false;
  const stripped = message.replace(/(\d),(\d{3})/g, "$1$2");
  const found = stripped.match(/\d+(?:\.\d+)?/g) ?? [];
  return found.some((item) => Number(item) === figure);
}
