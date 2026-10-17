// BMI and the weight at the healthy floor. Kept apart from the summary so the calculators
// (coach_calculations.ts) can use the floor without importing the whole review.
import { goalPhaseThresholds } from "./thresholds.ts";
import { round } from "./math.ts";
import type { GoalTarget } from "./types.ts";

export function bmiOf(weightKg: number, heightCm: number): number {
  const meters = heightCm / 100;
  return round(weightKg / (meters * meters), 1);
}

/** The weight (kg) at the healthy BMI floor for this height, or null without a usable height. */
export function healthyFloorWeightKg(heightCm: number | null): number | null {
  if (heightCm === null || !Number.isFinite(heightCm) || heightCm < 100 || heightCm > 250) {
    return null;
  }
  const meters = heightCm / 100;
  return round(goalPhaseThresholds.bmiHealthyFloor.value * meters * meters, 1);
}

/** True when the goal has an end point: a weight, a body-fat range or a physique goal. */
export function hasGoalTarget(target: GoalTarget): boolean {
  return target.weightKg !== null || target.bodyFatMinPct !== null ||
    target.bodyFatMaxPct !== null || target.physique !== null;
}
