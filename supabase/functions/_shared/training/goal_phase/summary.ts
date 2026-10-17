// The goal phase summary: where the athlete stands since the goal began, from their own body
// readings. Missing data lowers confidence and is reported, never invented. The goal's saved
// `current_weight_kg` is the weight at the time the goal was written; it is never a start weight.
import { bmiOf, hasGoalTarget } from "./bmi.ts";
import { dayIndex, median, round } from "./math.ts";
import { goalPhaseThresholds as limits } from "./thresholds.ts";
import type {
  ContinuousLoss,
  ExcludedReading,
  GoalPhaseInputs,
  GoalPhaseSummary,
  PhaseConfidence,
  RecordedHistory,
  WeightReading,
} from "./types.ts";

type Point = Readonly<{ day: number; date: string; kg: number }>;

/** Days a start or current weight is smoothed over, and the most readings it takes. */
const smoothingDays = 7;
const smoothingReadings = 3;
const recentWindowDays = 28;
const recentMinimumReadings = 3;
const recentMinimumSpanDays = 14;
const minimumRateWeeks = 2;

/** Valid readings in date order, one per date (the last one given for a date wins). */
function normalise(readings: readonly WeightReading[]): Point[] {
  const byDay = new Map<number, Point>();
  for (const reading of readings) {
    const day = dayIndex(reading.date);
    if (day === null || !Number.isFinite(reading.kg) || reading.kg <= 0) continue;
    byDay.set(day, { day, date: reading.date, kg: reading.kg });
  }
  return [...byDay.values()].sort((a, b) => a.day - b.day);
}

/** Whether `kg` is further from `neighbour` than any real change over the days between them. */
function beyondReach(kg: number, neighbour: Point, day: number): boolean {
  const weeks = Math.abs(neighbour.day - day) / 7;
  const allowed = neighbour.kg *
    (limits.implausibleBaseFraction.value + limits.implausibleWeeklyFraction.value * weeks);
  return Math.abs(kg - neighbour.kg) > allowed;
}

/**
 * Readings that cannot be real against their neighbours: further from both the reading before
 * and the reading after than body weight can move in that time (an end reading is judged against
 * its one neighbour). With fewer than three readings nothing can be judged.
 */
export function findImplausibleReadings(readings: readonly WeightReading[]): ExcludedReading[] {
  const points = normalise(readings);
  if (points.length < 3) return [];
  const excluded: Point[] = [];
  // Interior readings first, against the reading on each side.
  const interior = points.filter((point, index) =>
    index > 0 && index < points.length - 1 &&
    beyondReach(point.kg, points[index - 1], point.day) &&
    beyondReach(point.kg, points[index + 1], point.day)
  );
  excluded.push(...interior);
  // Then the two ends, against their nearest reading that is still believed.
  const kept = points.filter((point) => !interior.includes(point));
  const ends: [Point, Point | undefined][] = [
    [kept[0], kept[1]],
    [kept[kept.length - 1], kept[kept.length - 2]],
  ];
  for (const [end, neighbour] of ends) {
    if (neighbour && kept.length >= 3 && beyondReach(end.kg, neighbour, end.day)) {
      excluded.push(end);
    }
  }
  return excluded.sort((a, b) => a.day - b.day).map((point) => ({
    date: point.date,
    kg: point.kg,
    reason: "implausible_jump" as const,
  }));
}

/** Median of up to three readings within a week of `anchor`, looking forward or back. */
function smoothed(points: readonly Point[], fromStart: boolean): number {
  const anchor = fromStart ? points[0] : points[points.length - 1];
  const near = points.filter((p) =>
    fromStart ? p.day - anchor.day < smoothingDays : anchor.day - p.day < smoothingDays
  );
  const chosen = fromStart ? near.slice(0, smoothingReadings) : near.slice(-smoothingReadings);
  return median(chosen.map((p) => p.kg));
}

/** Least-squares slope in kg a week, or null with too few readings or too short a span. */
function recentSlope(points: readonly Point[]): number | null {
  if (points.length === 0) return null;
  const last = points[points.length - 1].day;
  const inside = points.filter((p) => last - p.day < recentWindowDays);
  if (inside.length < recentMinimumReadings) return null;
  if (inside[inside.length - 1].day - inside[0].day < recentMinimumSpanDays) return null;
  const meanX = inside.reduce((sum, p) => sum + p.day, 0) / inside.length;
  const meanY = inside.reduce((sum, p) => sum + p.kg, 0) / inside.length;
  let covariance = 0;
  let variance = 0;
  for (const p of inside) {
    covariance += (p.day - meanX) * (p.kg - meanY);
    variance += (p.day - meanX) ** 2;
  }
  return round((covariance / variance) * 7, 2);
}

/**
 * The recorded history, when the first reading is at least a week before the phase's first
 * reading (so it says something the phase does not). The start is smoothed like the phase start.
 */
function recordedHistory(
  clean: readonly Point[],
  last: Point,
  firstDay: number,
  current: number,
): RecordedHistory | null {
  const lead = firstDay - clean[0].day;
  if (lead < limits.historyMinimumLeadDays.value) return null;
  const startWeightKg = round(smoothed(clean, true), 1);
  const changeKg = round(current - startWeightKg, 1);
  return {
    startDate: clean[0].date,
    startWeightKg,
    changeKg,
    changePct: round((changeKg / startWeightKg) * 100, 1),
    weeks: round((last.day - clean[0].day) / 7, 1),
    readingsUsed: clean.length,
  };
}

/**
 * The run of falling weight that ends now. Walking back from the current weight, every higher
 * smoothed reading moves the start back to it; the walk stops at a reading lower than the high
 * so far by more than the tolerance (the weight was rising before that, a gain phase or a
 * rebound), so the run starts at the high point. It is returned only when it differs from the goal
 * phase: an earlier start must sit at least the tolerance above the phase start (a flat stretch
 * before the goal is not a loss), and a later start (weight rose, then fell) is kept as is.
 */
function continuousLoss(
  clean: readonly Point[],
  firstIndex: number,
  last: Point,
  current: number,
  phaseStart: number,
): ContinuousLoss | null {
  const tolerance = limits.continuousRunTolerancePct.value / 100;
  let high = current;
  let startIndex = clean.length - 1;
  for (let index = clean.length - 2; index >= 0; index--) {
    const kg = smoothed(clean.slice(index), true);
    if (kg > high) {
      high = kg;
      startIndex = index;
    } else if (kg < high * (1 - tolerance)) break;
  }
  if (startIndex === firstIndex) return null;
  if (startIndex < firstIndex && high < phaseStart * (1 + tolerance)) return null;
  const weeks = (last.day - clean[startIndex].day) / 7;
  const changeKg = round(current - high, 1);
  if (weeks < minimumRateWeeks || changeKg >= 0) return null;
  const startWeightKg = round(high, 1);
  return {
    startDate: clean[startIndex].date,
    startWeightKg,
    changeKg,
    changePct: round((changeKg / startWeightKg) * 100, 1),
    weeks: round(weeks, 1),
    weeklyRateKg: round(changeKg / weeks, 2),
    beganBeforeGoalPhase: startIndex < firstIndex,
  };
}

const emptySummary = (input: GoalPhaseInputs): Omit<
  GoalPhaseSummary,
  "hasGoal" | "confidence" | "notes" | "excluded" | "readingsUsed" | "history" | "continuousLoss"
> => ({
  goalType: input.goalType,
  phaseStart: null,
  phaseStartSource: null,
  firstReadingDate: null,
  startWeightKg: null,
  currentWeightKg: null,
  currentDate: null,
  changeKg: null,
  changePct: null,
  weeks: null,
  weeklyRateKg: null,
  weeklyRatePct: null,
  recentRateKgPerWeek: null,
  bmi: null,
  heightCm: input.heightCm,
  hasTarget: hasGoalTarget(input.target),
  target: input.target,
});

export function summarizeGoalPhase(input: GoalPhaseInputs): GoalPhaseSummary {
  const hasGoal = input.goalType !== null;
  const notes: string[] = [];
  const excluded = findImplausibleReadings(input.readings);
  const skipped = new Set(excluded.map((e) => e.date));
  const clean = normalise(input.readings).filter((p) => !skipped.has(p.date));
  const base = emptySummary(input);
  if (!hasGoal) notes.push("no active goal");

  const activation = input.activatedOn === null ? null : dayIndex(input.activatedOn);
  if (hasGoal && activation === null) {
    notes.push("goal activation date unknown; the phase starts at the first reading");
  }
  const phase = activation === null ? clean : clean.filter((p) => p.day >= activation);
  if (clean.length > 0 && phase.length === 0) {
    notes.push("no weight reading on or after the goal began");
  }
  if (clean.length === 0) notes.push("no weight readings");

  const stale = phase.length > 0 &&
    (dayIndex(input.today) ?? 0) - phase[phase.length - 1].day > limits.staleReadingDays.value;
  if (stale) notes.push(`latest reading is older than ${limits.staleReadingDays.value} days`);
  if (phase.length === 1) notes.push("one reading since the goal began; no change can be shown");

  if (phase.length === 0) {
    return {
      ...base,
      hasGoal,
      phaseStart: activation === null ? null : input.activatedOn,
      phaseStartSource: activation === null ? null : "goal_activation",
      readingsUsed: 0,
      history: null,
      continuousLoss: null,
      excluded,
      confidence: "low",
      notes,
    };
  }

  const first = phase[0];
  const last = phase[phase.length - 1];
  const current = round(smoothed(phase, false), 1);
  const bmi = input.heightCm === null ? null : bmiOf(current, input.heightCm);
  const common = {
    ...base,
    hasGoal,
    phaseStart: activation === null ? first.date : input.activatedOn,
    phaseStartSource: activation === null ? "first_reading" as const : "goal_activation" as const,
    firstReadingDate: first.date,
    currentWeightKg: current,
    currentDate: last.date,
    bmi,
    readingsUsed: phase.length,
    history: null,
    continuousLoss: null,
    excluded,
  };
  if (input.heightCm === null) notes.push("height unknown; BMI not calculated");

  const weeks = (last.day - first.day) / 7;
  if (phase.length < 2 || weeks < minimumRateWeeks) {
    if (phase.length >= 2) notes.push(`less than ${minimumRateWeeks} weeks of readings; no rate`);
    // The recorded history does not depend on the phase having a rate.
    const phaseStart = round(smoothed(phase, true), 1);
    return {
      ...common,
      startWeightKg: phaseStart,
      history: recordedHistory(clean, last, first.day, current),
      continuousLoss: continuousLoss(
        clean,
        clean.length - phase.length,
        last,
        current,
        phaseStart,
      ),
      confidence: "low",
      notes,
    };
  }

  const start = round(smoothed(phase, true), 1);
  const changeKg = round(current - start, 1);
  const weeklyRateKg = round((current - start) / weeks, 2);
  const slope = recentSlope(phase);
  const firstIndex = clean.length - phase.length;
  let confidence: PhaseConfidence = "medium";
  if (phase.length >= 8 && weeks >= 4 && activation !== null && !stale) confidence = "high";
  if (stale || phase.length < 3) confidence = "low";
  if (activation === null && confidence === "high") confidence = "medium";
  if (slope === null) notes.push("not enough recent readings for a recent rate");
  return {
    ...common,
    startWeightKg: start,
    history: recordedHistory(clean, last, first.day, current),
    continuousLoss: continuousLoss(clean, firstIndex, last, current, start),
    changeKg,
    changePct: round((changeKg / start) * 100, 1),
    weeks: round(weeks, 1),
    weeklyRateKg,
    weeklyRatePct: round((weeklyRateKg / start) * 100, 2),
    recentRateKgPerWeek: slope,
    confidence,
    notes,
  };
}
