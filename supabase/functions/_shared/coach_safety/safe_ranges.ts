// The deterministic "Safe Ranges" section of the Coach context (docs/AI_SAFETY_SPEC.md §11) and
// the numbers the reply guard (reply_guard.ts) holds replies to. Every value comes from a rule
// Tracend already applies elsewhere: the calorie floor from onboarding/policy.ts, the weekly loss
// ceiling and the healthy-weight floor from the goal phase thresholds, the longest cut from the
// same table. Coach quotes them; it never sets or changes them.
import { calculateCoachNumbers } from "../coach_calculations.ts";
import { calorieFloorKcal, sexFloorKcal } from "../onboarding/policy.ts";
import { sexes } from "../onboarding/answers.ts";
import { healthyFloorWeightKg } from "../training/goal_phase/bmi.ts";
import { goalPhaseThresholds } from "../training/goal_phase/thresholds.ts";
import { checkInEscalated } from "./red_flags.ts";

export type SafeRanges = Readonly<{
  /** Daily calories below which Coach never advises, whatever the goal. */
  calorieFloorKcal: number;
  /** Whether the floor is the athlete's resting energy or the sex-based minimum. */
  calorieFloorBasis: "resting_energy" | "sex_minimum";
  /** The athlete's latest weight, or null without a reading. */
  weightKg: number | null;
  /** The most Coach advises losing in a week (1% of body weight), or null without a weight. */
  weeklyLossCeilingKg: number | null;
  weeklyLossCeilingPct: number;
  /** The weight at BMI 18.5 for the athlete's height, or null without a usable height. */
  healthyFloorKg: number | null;
  healthyFloorBmi: number;
  heightCm: number | null;
  /** Weeks of continuous loss after which Coach advises a maintenance period or a diet break. */
  longestCutWeeks: number;
  /** Today's check-in put the athlete in the daily policy's escalate outcome (pain 7 or more). */
  painEscalated: boolean;
}>;

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function latestWeightKg(context: Record<string, unknown>): number | null {
  const calculated = calculateCoachNumbers(context)?.weight?.latest_kg ?? null;
  if (calculated !== null) return calculated;
  return num(
    obj(Array.isArray(context.weight_series_8w) ? context.weight_series_8w[0] : null).weight_kg,
  );
}

/** The safe ranges for the athlete in a prepared Coach context (nothing is fetched). */
export function safeRangesOf(context: Record<string, unknown>): SafeRanges {
  const profile = obj(context.profile_context);
  const sex = sexes.find((item) => item === profile.sex) ?? "unspecified";
  const age = num(profile.age);
  const heightCm = num(profile.height_cm);
  const weightKg = latestWeightKg(context);
  const calorieFloor = weightKg !== null && heightCm !== null && age !== null
    ? calorieFloorKcal(sex, weightKg, heightCm, age)
    : sexFloorKcal[sex];
  const sexMinimum = sexFloorKcal[sex];
  const ceilingPct = goalPhaseThresholds.fastRatePctPerWeek.value;
  return {
    calorieFloorKcal: calorieFloor,
    calorieFloorBasis: calorieFloor > sexMinimum ? "resting_energy" : "sex_minimum",
    weightKg,
    weeklyLossCeilingKg: weightKg === null ? null : weightKg * ceilingPct / 100,
    weeklyLossCeilingPct: ceilingPct,
    healthyFloorKg: healthyFloorWeightKg(heightCm),
    healthyFloorBmi: goalPhaseThresholds.bmiHealthyFloor.value,
    heightCm,
    longestCutWeeks: goalPhaseThresholds.longDeficitWeeks.value,
    painEscalated: checkInEscalated(context),
  };
}

/** The Safe Ranges section: the limits, then today's pain rule when it applies. */
export function renderSafeRanges(ranges: SafeRanges): string {
  const lines = [
    "## Safe Ranges (set by Tracend rules; you quote them and never change them)",
    `- Calorie floor: ${ranges.calorieFloorKcal} kcal a day (${
      ranges.calorieFloorBasis === "resting_energy"
        ? "the athlete's resting energy, which is above the sex-based minimum"
        : "the sex-based minimum"
    }). Never advise a daily intake below it, whatever the goal.`,
    ranges.weeklyLossCeilingKg === null
      ? `- Weekly loss ceiling: ${ranges.weeklyLossCeilingPct}% of body weight a week. Never advise a faster loss.`
      : `- Weekly loss ceiling: ${ranges.weeklyLossCeilingPct}% of body weight a week, which is ${
        Math.round(ranges.weeklyLossCeilingKg * 100) / 100
      } kg at ${ranges.weightKg} kg (the latest reading). Never advise a faster loss.`,
    ranges.healthyFloorKg === null
      ? `- Healthy-weight floor: BMI ${ranges.healthyFloorBmi}. The athlete's height is not on file, so its weight cannot be stated; never advise a weight that low.`
      : `- Healthy-weight floor: BMI ${ranges.healthyFloorBmi}, which is ${ranges.healthyFloorKg} kg at ${ranges.heightCm} cm. Never advise a weight below it.`,
    `- Longest continuous cut: ${ranges.longestCutWeeks} weeks. After that, advise a maintenance period or a diet break before any more loss.`,
    "- Effort cap: set by the athlete's health check. The screening reference data states it when it applies; without that block there is no cap.",
  ];
  if (ranges.painEscalated) {
    lines.push(
      "- Today's check-in: pain of 7 or more. Give no training advice today. Say the pain is too high to train through and recommend a doctor or physio before the area is trained again.",
    );
  }
  return lines.join("\n") + "\n";
}
