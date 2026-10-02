import { roundTo, weightTrendKgPerWeek } from "../coach_calculations.ts";

// The athlete's last 28 complete days of Apple Health, summarised by
// deterministic code for the onboarding plan (ALGORITHMS §9). A metric is
// included only with enough days behind it; resting heart rate, HRV and
// breathing rate are left out, because without a personal baseline they cannot
// guide a starting plan. Values are rounded and keys fixed, so the same data
// always gives the same snapshot hash.

export const healthWindowDays = 28;
/** Days with a value before steps or active energy are averaged. */
export const healthMinimumDays = 7;
/** Nights with sleep before sleep is averaged. */
export const healthMinimumNights = 7;

export type HealthDay = Readonly<{
  local_date: string;
  steps: number | null;
  active_energy_kcal: number | null;
  sleep_minutes: number | null;
  weight_kg: number | null;
}>;

export type HealthWorkout = Readonly<{
  local_date: string;
  activity_type: string;
  duration_seconds: number;
}>;

export type HealthSummary = Readonly<{
  window_days: number;
  /** Days in the window with any Apple Health value. */
  days_with_data: number;
  steps_per_day?: number;
  steps_days?: number;
  active_energy_kcal_per_day?: number;
  sleep_minutes_per_night?: number;
  sleep_nights?: number;
  /** Present only when at least one workout was found: none found proves nothing. */
  workouts_per_week?: number;
  /** Strength workouts a week; present (possibly 0) whenever workouts are. */
  strength_workouts_per_week?: number;
  workout_minutes_per_week?: number;
  workout_types?: readonly string[];
  weight_latest_kg?: number;
  weight_latest_date?: string;
  weight_trend_kg_per_week?: number;
}>;

const isoDate = /^\d{4}-\d{2}-\d{2}$/;

/** The date `days` before an ISO date, as an ISO date. */
export function shiftDate(date: string, days: number): string {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day - days)).toISOString().slice(0, 10);
}

/** Today's date where the athlete lives; an unknown time zone reads as UTC. */
export function localDate(now: Date, timezone: string): string {
  const format = (zone: string) =>
    new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(now);
  try {
    return format(timezone);
  } catch {
    return format("UTC");
  }
}

/** The first and last date of the window ending the day before `today`. */
export function healthWindow(today: string): Readonly<{ from: string; through: string }> {
  return { from: shiftDate(today, healthWindowDays), through: shiftDate(today, 1) };
}

const value = (input: number | null) =>
  typeof input === "number" && Number.isFinite(input) && input > 0 ? input : null;

/** HealthKit workout types that count as strength training. */
export const strengthActivityTypes: readonly string[] = [
  "TRADITIONAL_STRENGTH_TRAINING",
  "FUNCTIONAL_STRENGTH_TRAINING",
];

export const isStrengthWorkout = (activityType: string) =>
  strengthActivityTypes.includes(activityType.trim().toUpperCase());

const readable = (activityType: string) => activityType.toLowerCase().replaceAll("_", " ").trim();

/**
 * The summary for the 28 dates before `today` (the athlete's local date).
 * Today's partial row is left out when it exists; yesterday's row is never
 * dropped. Null when the window has no Apple Health value at all.
 */
export function summarizeHealth(
  days: readonly HealthDay[],
  workouts: readonly HealthWorkout[],
  today: string,
): HealthSummary | null {
  const { from, through } = healthWindow(today);
  const inside = (date: string) => isoDate.test(date) && date >= from && date <= through;
  const window = days.filter((day) => inside(day.local_date));
  const withData = window.filter((day) =>
    [day.steps, day.active_energy_kcal, day.sleep_minutes, day.weight_kg].some((v) =>
      value(v) !== null
    )
  );
  const found = workouts.filter((workout) =>
    inside(workout.local_date) && workout.duration_seconds > 0 &&
    workout.activity_type.trim() !== ""
  );
  if (withData.length === 0 && found.length === 0) return null;

  const mean = (values: number[]) => values.reduce((sum, v) => sum + v, 0) / values.length;
  const present = (pick: (day: HealthDay) => number | null) =>
    window.map((day) => value(pick(day))).filter((v): v is number => v !== null);
  const steps = present((day) => day.steps);
  const energy = present((day) => day.active_energy_kcal);
  const sleep = present((day) => day.sleep_minutes);
  const weights = window
    .flatMap((day) => {
      const kg = value(day.weight_kg);
      return kg === null ? [] : [{ date: day.local_date, kg }];
    })
    .sort((a, b) => a.date.localeCompare(b.date));
  const latestWeight = weights.at(-1);
  const trend = weightTrendKgPerWeek(weights, through);

  const weeks = healthWindowDays / 7;
  const typeCounts = new Map<string, number>();
  for (const workout of found) {
    const type = readable(workout.activity_type);
    typeCounts.set(type, (typeCounts.get(type) ?? 0) + 1);
  }
  const workoutTypes = [...typeCounts]
    .sort(([leftType, left], [rightType, right]) =>
      right - left || leftType.localeCompare(rightType)
    )
    .slice(0, 3)
    .map(([type]) => type);

  return {
    window_days: healthWindowDays,
    days_with_data: new Set([
      ...withData.map((day) => day.local_date),
      ...found.map((workout) => workout.local_date),
    ]).size,
    ...(steps.length >= healthMinimumDays
      ? { steps_per_day: Math.round(mean(steps)), steps_days: steps.length }
      : {}),
    ...(energy.length >= healthMinimumDays
      ? { active_energy_kcal_per_day: Math.round(mean(energy)) }
      : {}),
    ...(sleep.length >= healthMinimumNights
      ? { sleep_minutes_per_night: Math.round(mean(sleep)), sleep_nights: sleep.length }
      : {}),
    ...(found.length
      ? {
        workouts_per_week: roundTo(found.length / weeks, 1),
        strength_workouts_per_week: roundTo(
          found.filter((workout) => isStrengthWorkout(workout.activity_type)).length / weeks,
          1,
        ),
        workout_minutes_per_week: Math.round(
          found.reduce((sum, workout) => sum + workout.duration_seconds, 0) / 60 / weeks,
        ),
        workout_types: workoutTypes,
      }
      : {}),
    ...(latestWeight
      ? { weight_latest_kg: roundTo(latestWeight.kg, 1), weight_latest_date: latestWeight.date }
      : {}),
    ...(trend === null ? {} : { weight_trend_kg_per_week: trend }),
  };
}

export type ActivityLevel = "mostly_sitting" | "some_standing" | "mostly_standing";

/**
 * The daily-activity answer average steps point to (ALGORITHMS §9). Steps never
 * suggest physical labour. The app's About you step uses the same thresholds
 * (lib/features/onboarding/health_activity.dart).
 */
export function activityFromSteps(stepsPerDay: number): ActivityLevel {
  if (stepsPerDay < 5000) return "mostly_sitting";
  if (stepsPerDay < 7500) return "some_standing";
  return "mostly_standing";
}

/** Sleep below this average starts the first block lighter. */
export const shortSleepMinutes = 360;

/** Recorded sleep proves sleep access, so short sleep is a measured fact. */
export const startsLighter = (health: HealthSummary | null) =>
  health?.sleep_minutes_per_night !== undefined &&
  health.sleep_minutes_per_night < shortSleepMinutes;
