// Calorie and macro targets for a proposal. Every number comes from the onboarding nutrition policy
// (sex-based floor, resting energy, protein and fat ranges) and Coach's safe ranges (weekly loss
// ceiling, healthy-weight floor). The model chooses a direction; a figure the athlete asked for is
// checked against the same limits and refused when it breaks one.
import { nutritionBounds, type NutritionPolicy, nutritionPolicy } from "../onboarding/policy.ts";
import { bmiOf } from "../training/goal_phase/bmi.ts";
import { goalPhaseThresholds } from "../training/goal_phase/thresholds.ts";
import {
  answersFromState,
  basisOf,
  currentWeightKg,
  messageHasFigure,
  proposalExpiryHours,
  reasonText,
} from "./common.ts";
import { kcal, refusals } from "./refusals.ts";
import type {
  AthleteState,
  BuildResult,
  CoachProposal,
  CoachProposalIntent,
  DisplayRow,
  NutritionChange,
  ProposalEvidence,
  StateNutrition,
} from "./types.ts";

/**
 * Energy in one kilogram of body weight lost or gained, the long-standing 3,500 kcal per pound
 * rule of thumb. It sizes the weekly loss a calorie gap implies; no target is derived from it.
 */
export const kcalPerKgBodyWeight = 7700;

/** The share of the current target one "lower" or "raise" step moves it. */
export const stepFraction = 0.05;

/** Raising calories never goes past 15% above maintenance, the top of the muscle-gain range. */
export const surplusCapFraction = 0.15;

const round10 = (value: number) => Math.round(value / 10) * 10;

export type NutritionBasis = Readonly<{
  policy: NutritionPolicy;
  weightKg: number;
  bmi: number;
  maintenanceKcal: number;
  surplusCapKcal: number;
  weeklyLossCeilingKg: number;
}>;

export function nutritionBasis(
  state: AthleteState,
): NutritionBasis | Extract<BuildResult, { ok: false }> {
  const weightKg = currentWeightKg(state);
  if (weightKg === null) return refusals.noWeight();
  const policy = nutritionPolicy(answersFromState(state, weightKg));
  const maintenanceKcal = round10((policy.tdeeKcal[0] + policy.tdeeKcal[1]) / 2);
  return {
    policy,
    weightKg,
    bmi: bmiOf(weightKg, state.profile.heightCm),
    maintenanceKcal,
    surplusCapKcal: round10(policy.tdeeKcal[1] * (1 + surplusCapFraction)),
    weeklyLossCeilingKg: weightKg * goalPhaseThresholds.fastRatePctPerWeek.value / 100,
  };
}

/** Kilograms a week a calorie target loses (positive) or gains (negative) against maintenance. */
export function weeklyLossKg(basis: NutritionBasis, calories: number): number {
  return (basis.maintenanceKcal - calories) * 7 / kcalPerKgBodyWeight;
}

/**
 * Macros for a calorie target: protein in the middle of the policy range, fat at a quarter of the
 * calories (inside the policy's minimum and maximum), carbohydrate the remainder. Returns null when
 * no split stays inside the bounds.
 */
export function macrosFor(
  policy: NutritionPolicy,
  calories: number,
): Pick<NutritionChange, "protein_g" | "carbohydrate_g" | "fat_g"> | null {
  const fatMin = policy.fatMinG(calories);
  const fatMax = policy.fatMaxG(calories);
  if (fatMin > fatMax) return null;
  const fat = Math.min(fatMax, Math.max(fatMin, Math.round(0.25 * calories / 9)));
  const [proteinLow, proteinHigh] = policy.protein;
  const [carbLow, carbHigh] = nutritionBounds.carbohydrateG;
  for (
    let protein = Math.round((proteinLow + proteinHigh) / 2);
    protein >= proteinLow;
    protein -= 5
  ) {
    const carbohydrate = Math.round((calories - 4 * protein - 9 * fat) / 4);
    if (carbohydrate >= carbLow && carbohydrate <= carbHigh) {
      return { protein_g: protein, carbohydrate_g: carbohydrate, fat_g: fat };
    }
  }
  return null;
}

export function nutritionChange(
  basis: NutritionBasis,
  calories: number,
  rationale: string,
): NutritionChange | null {
  const macros = macrosFor(basis.policy, calories);
  return macros === null ? null : { calories, ...macros, rationale };
}

const amount = (value: number | undefined, unit: string) =>
  value === undefined ? "none" : `${value.toLocaleString("en-US")} ${unit}`;

/** The nutrition rows of the before column (null: no target yet). */
export function nutritionRowsBefore(before: StateNutrition | null): DisplayRow[] {
  return [
    { label: "Calories", value: amount(before?.calories, "kcal") },
    { label: "Protein", value: amount(before?.proteinG, "g") },
    { label: "Carbs", value: amount(before?.carbohydrateG, "g") },
    { label: "Fat", value: amount(before?.fatG, "g") },
  ];
}

export function nutritionRowsAfter(after: NutritionChange): DisplayRow[] {
  return [
    { label: "Calories", value: amount(after.calories, "kcal") },
    { label: "Protein", value: amount(after.protein_g, "g") },
    { label: "Carbs", value: amount(after.carbohydrate_g, "g") },
    { label: "Fat", value: amount(after.fat_g, "g") },
  ];
}

export function nutritionEvidence(gated: boolean, state: AthleteState): ProposalEvidence[] {
  return [
    {
      code: "NUTRITION_POLICY_V2",
      label: "Tracend's calorie floor and protein and fat ranges for you",
      source: "policy_evaluation",
    },
    {
      code: "ENERGY_ESTIMATE",
      label: "Your estimated daily energy from age, height, weight and activity",
      source: "policy_evaluation",
    },
    ...(gated
      ? [{
        code: "CHANGE_ELIGIBILITY_NUTRITION",
        label: `Enough complete logging to lower calories (${state.eligibility.nutritionDetail})`,
        source: "policy_evaluation",
      }]
      : []),
  ];
}

/**
 * True when the change lowers calories below maintenance, which is a deficit and which the
 * eligibility gate covers. A move that stays at or above maintenance is not a cut.
 */
export const isDeficitCut = (basis: NutritionBasis, current: number, next: number) =>
  next < current && next < basis.maintenanceKcal;

/**
 * Checks a calorie target against every limit: the floor, the ceiling, the weekly loss ceiling and
 * the healthy-weight floor. Returns the refusal, or null when the target is allowed.
 */
export function limitRefusal(
  basis: NutritionBasis,
  calories: number,
): Extract<BuildResult, { ok: false }> | null {
  const floor = basis.policy.floorKcal;
  if (calories < floor) return refusals.belowFloor(floor);
  if (calories > basis.policy.ceilingKcal) return refusals.aboveCeiling(basis.policy.ceilingKcal);
  if (calories > basis.surplusCapKcal) return refusals.aboveCeiling(basis.surplusCapKcal);
  const loss = weeklyLossKg(basis, calories);
  if (loss > basis.weeklyLossCeilingKg) {
    return refusals.tooFast(calories, loss, basis.weeklyLossCeilingKg);
  }
  if (loss > 0 && basis.bmi < goalPhaseThresholds.bmiNearFloor.value) {
    return refusals.nearHealthyFloor(basis.bmi);
  }
  return null;
}

export function buildNutritionTargets(
  intent: Extract<CoachProposalIntent, { kind: "nutrition_targets" }>,
  state: AthleteState,
): BuildResult {
  if (state.screening === "see_professional") return refusals.seeProfessional();
  if (!state.nutrition) return refusals.noNutrition();
  const basis = nutritionBasis(state);
  if ("ok" in basis) return basis;
  const current = state.nutrition.calories;

  let calories: number;
  if (intent.requestedCalories !== undefined) {
    if (!messageHasFigure(state.athleteMessage, intent.requestedCalories)) {
      return refusals.figureNotFromAthlete("calorie figure");
    }
    calories = intent.requestedCalories;
  } else if (intent.direction === "maintenance") {
    calories = basis.maintenanceKcal;
  } else if (intent.direction === "lower") {
    calories = Math.max(round10(current * (1 - stepFraction)), basis.policy.floorKcal);
    if (current <= basis.policy.floorKcal) return refusals.atFloor(basis.policy.floorKcal);
  } else {
    calories = Math.min(round10(current * (1 + stepFraction)), basis.surplusCapKcal);
  }

  if (intent.direction === "lower" && calories >= current) {
    return refusals.noChange("That wouldn't lower your calories.");
  }
  if (intent.direction === "raise" && calories <= current) {
    return refusals.noChange("That wouldn't raise your calories.");
  }
  if (Math.abs(calories - current) < 10) return refusals.alreadyOnTarget(current);

  const limit = limitRefusal(basis, calories);
  if (limit) return limit;

  const gated = isDeficitCut(basis, current, calories);
  if (gated && !state.eligibility.nutritionEligible) {
    return refusals.notEnoughLogging(state.eligibility.nutritionDetail);
  }

  const direction = calories < current ? "lower" : "raise";
  const rationale = `${reasonText(intent.reason, intent.note)} ` +
    (intent.direction === "maintenance"
      ? `Your daily target moves to about maintenance, ${kcal(calories)}.`
      : `Your daily target goes ${direction} to ${kcal(calories)}, inside the limits Tracend ` +
        `sets for you (floor ${kcal(basis.policy.floorKcal)}).`);
  const change = nutritionChange(basis, calories, rationale);
  if (change === null) {
    return refusals.infeasible("no protein, fat and carbohydrate split fits that calorie target");
  }
  const proposal: CoachProposal = {
    kind: "nutrition_targets",
    title: intent.direction === "maintenance"
      ? "Move your calories to maintenance"
      : `${direction === "lower" ? "Lower" : "Raise"} your calories`,
    rationale,
    benefit: direction === "lower"
      ? "A steadier pace of fat loss that your recent logging supports."
      : "More fuel for training and recovery.",
    downside: direction === "lower"
      ? "Less food each day can make training and hunger harder; the target is rechecked as " +
        "your weight and logging come in."
      : "A higher target slows or pauses fat loss while it lasts.",
    confidence: gated ? "medium" : "low",
    evidence: nutritionEvidence(gated, state),
    expiresInHours: proposalExpiryHours.default,
    endsOn: null,
    before: { rows: nutritionRowsBefore(state.nutrition) },
    after: { rows: nutritionRowsAfter(change) },
    payload: { nutrition: change },
    basis: basisOf(state, gated ? ["nutrition_change"] : []),
  };
  return { ok: true, proposal };
}
