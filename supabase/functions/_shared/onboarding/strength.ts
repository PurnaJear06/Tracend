import type { ReportableLift, ReportedLift } from "./answers.ts";

// Strength from the athlete's reported barbell top sets (ALGORITHMS §9).
// Deterministic code estimates a one-rep max for each lift and the starting
// load for an exercise that is that lift; the model never writes a load.

/** Barbell plates step the load by 2.5 kg; an empty bar is 20 kg. */
export const barbellIncrementKg = 2.5;
export const emptyBarKg = 20;
/** The first week starts this much under the estimate. */
export const firstWeekReduction = 0.05;

/**
 * Epley with reps in reserve: a set of `reps` that stopped `repsLeft` short of
 * failure counts as `reps + repsLeft` reps to failure. Rounded to 0.5 kg.
 */
export function estimatedOneRepMax(loadKg: number, reps: number, repsLeft: number): number {
  return Math.round(loadKg * (1 + (reps + repsLeft) / 30) * 2) / 2;
}

export type LiftEstimate = Readonly<{ slug: ReportableLift; e1rm_kg: number }>;

/** One estimate per reported lift, in the order reported. */
export function liftEstimates(lifts: readonly ReportedLift[]): LiftEstimate[] {
  return lifts.map((lift) => ({
    slug: lift.slug,
    e1rm_kg: estimatedOneRepMax(lift.loadKg, lift.reps, lift.repsLeft),
  }));
}

/**
 * The load for sets up to `repMax` reps at `targetRpe`: the estimate divided
 * back by Epley at the reps the set leaves in reserve (10 - RPE), 5% lighter
 * for the first week, rounded down to a plate step. Null below an empty bar,
 * where a load would mean nothing.
 */
export function startingLoadKg(e1rmKg: number, repMax: number, targetRpe: number): number | null {
  const repsToFailure = repMax + (10 - targetRpe);
  const load = e1rmKg / (1 + repsToFailure / 30) * (1 - firstWeekReduction);
  const rounded = Math.floor(load / barbellIncrementKg) * barbellIncrementKg;
  return rounded >= emptyBarKg ? rounded : null;
}

export type StrengthRatios = Readonly<{
  /** Row estimate over bench estimate, when both were reported. */
  row_to_bench?: number;
  /** Deadlift estimate over squat estimate, when both were reported. */
  deadlift_to_squat?: number;
}>;

const ratio = (top: number | undefined, bottom: number | undefined) =>
  top === undefined || bottom === undefined ? undefined : Math.round(top / bottom * 100) / 100;

/** Ratios between reported lifts, only for pairs the athlete gave both of. */
export function strengthRatios(estimates: readonly LiftEstimate[]): StrengthRatios {
  const of = (slug: ReportableLift) => estimates.find((item) => item.slug === slug)?.e1rm_kg;
  const rowToBench = ratio(of("barbell-row"), of("barbell-bench-press"));
  const deadliftToSquat = ratio(of("barbell-deadlift"), of("barbell-back-squat"));
  return {
    ...(rowToBench === undefined ? {} : { row_to_bench: rowToBench }),
    ...(deadliftToSquat === undefined ? {} : { deadlift_to_squat: deadliftToSquat }),
  };
}
