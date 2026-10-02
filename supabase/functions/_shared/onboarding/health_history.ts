import { roundTo } from "../coach_calculations.ts";
import type { HealthSummary } from "./health_summary.ts";

// The athlete's usual self from Apple Health: monthly totals for the last 11
// completed calendar months, sent by the app (save_health_history), compared
// with the last 28 days (health_summary.ts). The month in progress is never
// used, and a metric needs enough covered months behind it, so one unusual
// month never stands in for the athlete's normal (ALGORITHMS §9).

export const historyMonths = 11;
/** Nights of sleep a month needs before its average counts. */
export const historyMinimumSleepNights = 20;
/** Weigh-in days a month needs before its average counts. */
export const historyMinimumWeightDays = 4;
/** Counted months a usual value needs. */
export const historyMinimumMonths = 3;

export type HealthMonth = Readonly<{
  /** The first day of the month, YYYY-MM-01. */
  month: string;
  workouts: number;
  strength_workouts: number;
  workout_minutes: number;
  sleep_nights: number;
  sleep_minutes_avg: number | null;
  weight_days: number;
  weight_kg_avg: number | null;
  /** Days in the month with any Apple Health value. */
  data_days: number;
}>;

export type HealthHistory = Readonly<{
  months: number;
  first_month: string;
  last_month: string;
  /** Median strength workouts a week, from the first month with a workout. */
  usual_strength_per_week?: number;
  strength_months?: number;
  usual_sleep_minutes?: number;
  sleep_months?: number;
  /** Change between the first and last covered month's average weight. */
  weight_change_kg?: number;
  weight_months?: number;
}>;

const monthPattern = /^\d{4}-\d{2}-01$/;

/** The first day of the month `count` months before the month of `date`. */
export function monthStart(date: string, count = 0): string {
  const [year, month] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1 - count, 1)).toISOString().slice(0, 10);
}

export function daysInMonth(month: string): number {
  const [year, number] = month.split("-").map(Number);
  return new Date(Date.UTC(year, number, 0)).getUTCDate();
}

/** The completed months the history covers: [from, through], month starts. */
export function historyWindow(today: string): Readonly<{ from: string; through: string }> {
  return { from: monthStart(today, historyMonths), through: monthStart(today, 1) };
}

const median = (values: number[]) => {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};

/**
 * The usual values from the completed months before `today` (the athlete's
 * local date). Null when no month in the window has data. HealthKit cannot
 * tell denied access from no data, so workout months count only from the
 * first month a workout was found: a year with none is "none found", never
 * "inactive", and a month with none after that is a real break.
 */
export function summarizeHealthHistory(
  rows: readonly HealthMonth[],
  today: string,
): HealthHistory | null {
  const { from, through } = historyWindow(today);
  const months = [...new Map(
    rows
      .filter((row) => monthPattern.test(row.month) && row.month >= from && row.month <= through)
      .map((row) => [row.month, row]),
  ).values()]
    .filter((row) => row.data_days > 0 || row.workouts > 0)
    .sort((a, b) => a.month.localeCompare(b.month));
  if (!months.length) return null;

  const firstWorkout = months.find((row) => row.workouts > 0)?.month;
  const strength = firstWorkout
    ? months
      .filter((row) => row.month >= firstWorkout)
      .map((row) => row.strength_workouts / (daysInMonth(row.month) / 7))
    : [];
  const sleep = months.filter((row) =>
    row.sleep_minutes_avg !== null && row.sleep_nights >= historyMinimumSleepNights
  );
  const weight = months.filter((row) =>
    row.weight_kg_avg !== null && row.weight_days >= historyMinimumWeightDays
  );

  return {
    months: months.length,
    first_month: months[0].month,
    last_month: months.at(-1)!.month,
    ...(strength.length >= historyMinimumMonths
      ? { usual_strength_per_week: roundTo(median(strength), 1), strength_months: strength.length }
      : {}),
    ...(sleep.length >= historyMinimumMonths
      ? {
        usual_sleep_minutes: Math.round(
          sleep.reduce((sum, row) => sum + row.sleep_minutes_avg!, 0) / sleep.length,
        ),
        sleep_months: sleep.length,
      }
      : {}),
    ...(weight.length >= historyMinimumMonths
      ? {
        weight_change_kg: roundTo(weight.at(-1)!.weight_kg_avg! - weight[0].weight_kg_avg!, 1),
        weight_months: weight.length,
      }
      : {}),
  };
}

/** Usual strength sessions a week below which nothing counts as a break. */
export const breakMinimumUsualPerWeek = 2;
/** Recent training below this share of usual reads as a break. */
export const breakShareOfUsual = 0.5;

/**
 * Lifting much less than usual: the athlete is coming back from a break, so
 * the first block eases back in. The history proves workouts are readable, so
 * no strength workout in the last 28 days counts as none.
 */
export function returningFromBreak(
  history: HealthHistory | null,
  recent: HealthSummary | null,
): boolean {
  const usual = history?.usual_strength_per_week;
  if (usual === undefined || usual < breakMinimumUsualPerWeek) return false;
  const lately = recent?.strength_workouts_per_week ?? 0;
  return lately < usual * breakShareOfUsual;
}
