// Goal and phase proposals: cut, maintenance, diet break or gain, with an optional target. The
// phase decides the direction of the calorie target and the rules compute it (nutrition.ts); a
// target weight and date are checked against the healthy-weight floor and the weekly loss ceiling,
// the same limits B7's set_goal_target_v1 and Coach's safe ranges apply.
import { goalCalorieAdjustments, nutritionPolicy } from "../onboarding/policy.ts";
import { healthyFloorWeightKg } from "../training/goal_phase/bmi.ts";
import { reviewGoalPhase } from "../training/goal_phase/review.ts";
import { goalPhaseThresholds } from "../training/goal_phase/thresholds.ts";
import {
  addDays,
  answersFromState,
  basisOf,
  currentWeightKg,
  daysBetween,
  messageHasFigure,
  proposalExpiryHours,
  reasonText,
  shortDate,
} from "./common.ts";
import {
  isDeficitCut,
  limitRefusal,
  nutritionBasis,
  nutritionChange,
  nutritionEvidence,
  nutritionRowsAfter,
  nutritionRowsBefore,
  weeklyLossKg,
} from "./nutrition.ts";
import { kcal, refusals } from "./refusals.ts";
import type {
  AthleteState,
  BuildResult,
  CoachProposal,
  CoachProposalIntent,
  DisplayRow,
  GoalChange,
  GoalPhase,
} from "./types.ts";

const maxTargetLeadDays = 1096;
const round10 = (value: number) => Math.round(value / 10) * 10;

const phaseLabels: Readonly<Record<GoalPhase, string>> = {
  cut: "Cut (fat loss)",
  maintenance: "Maintenance",
  diet_break: "Diet break",
  gain: "Gain (muscle)",
};

const goalLabels: Readonly<Record<string, string>> = {
  fat_loss: "Fat loss",
  muscle_gain: "Muscle gain",
  recomposition: "Recomposition",
  strength: "Strength",
  aesthetic: "Aesthetic",
};

export function buildGoalOrPhase(
  intent: Extract<CoachProposalIntent, { kind: "goal_or_phase" }>,
  state: AthleteState,
): BuildResult {
  if (state.screening === "see_professional") return refusals.seeProfessional();
  const goal = state.goal;
  if (!goal) return refusals.noGoal();
  if (!state.nutrition) return refusals.noNutrition();
  const basis = nutritionBasis(state);
  if ("ok" in basis) return basis;
  const weightKg = currentWeightKg(state)!;
  const { phase } = intent;
  const today = state.today;

  if (goal.phase === phase && phase !== "diet_break") {
    return refusals.alreadyInPhase(phase.replace("_", " "));
  }
  if (phase === "diet_break" && goal.phase === "diet_break") {
    return refusals.alreadyInPhase("diet break");
  }

  // Targets belong to a cut or a gain.
  const wantsTarget = intent.targetWeightKg !== undefined || intent.targetDate !== undefined;
  if (wantsTarget && phase !== "cut" && phase !== "gain") {
    return refusals.noChange(`A ${phase.replace("_", " ")} phase doesn't set a target weight.`);
  }
  if (intent.targetDate !== undefined && intent.targetWeightKg === undefined) {
    return refusals.targetDateInvalid("A target date needs a target weight.");
  }
  let target: GoalChange["target"];
  if (intent.targetWeightKg !== undefined) {
    if (!messageHasFigure(state.athleteMessage, intent.targetWeightKg)) {
      return refusals.figureNotFromAthlete("target weight");
    }
    const floor = healthyFloorWeightKg(state.profile.heightCm);
    if (floor !== null && intent.targetWeightKg < floor) return refusals.targetBelowFloor(floor);
    if (phase === "cut" ? intent.targetWeightKg >= weightKg : intent.targetWeightKg <= weightKg) {
      return refusals.targetWrongDirection(phase);
    }
    if (intent.targetDate !== undefined) {
      const lead = daysBetween(today, intent.targetDate);
      if (lead <= 0 || lead > maxTargetLeadDays) {
        return refusals.targetDateInvalid("A target date must fall within the next three years.");
      }
      if (phase === "cut") {
        const ceiling = basis.weeklyLossCeilingKg;
        const needed = (weightKg - intent.targetWeightKg) / (lead / 7);
        if (needed > ceiling) {
          const earliestDays = Math.ceil((weightKg - intent.targetWeightKg) / ceiling * 7);
          return refusals.targetTooFast(addDays(today, earliestDays), ceiling);
        }
      }
    }
    target = {
      weight_kg: intent.targetWeightKg,
      ...(intent.targetDate === undefined ? {} : { date: intent.targetDate }),
    };
  }

  // Calories for the phase.
  let calories: number;
  let goalType = goal.goalType;
  let endsOn: string | null = null;
  let gated = false;
  if (phase === "cut") {
    if (basis.bmi < goalPhaseThresholds.bmiNearFloor.value) {
      return refusals.nearHealthyFloor(basis.bmi);
    }
    const review = reviewGoalPhase(state.goalPhase);
    if (review.outcome === "consider_maintenance_or_diet_break") {
      return refusals.cutTooLong(review.reasons[0]?.detail ?? "a long run of loss");
    }
    if (!state.eligibility.nutritionEligible) {
      return refusals.notEnoughLogging(state.eligibility.nutritionDetail);
    }
    gated = true;
    goalType = "fat_loss";
    calories = nutritionPolicy(answersFromState(state, weightKg, { goal: "fat_loss" }))
      .calories[1];
  } else if (phase === "gain") {
    goalType = "muscle_gain";
    const tdee = nutritionPolicy(answersFromState(state, weightKg, { goal: "muscle_gain" }));
    calories = round10(basis.maintenanceKcal * (1 + goalCalorieAdjustments.muscle_gain[0]));
    calories = Math.min(calories, tdee.calories[1]);
  } else {
    if (phase === "diet_break" && goal.goalType !== "fat_loss" && goal.phase !== "cut") {
      return refusals.dietBreakNeedsFatLoss();
    }
    calories = basis.maintenanceKcal;
    if (phase === "diet_break") {
      endsOn = addDays(today, goalPhaseThresholds.dietBreakWeeks.value * 7 - 1);
    }
  }
  const limit = limitRefusal(basis, calories);
  if (limit) return limit;
  const loss = weeklyLossKg(basis, calories);
  const currentCalories = state.nutrition.calories;
  gated = gated && isDeficitCut(basis, currentCalories, calories);

  const rationale = `${reasonText(intent.reason, intent.note)} ` +
    (phase === "diet_break"
      ? `A ${goalPhaseThresholds.dietBreakWeeks.value}-week diet break at maintenance, ${
        kcal(calories)
      } a day, until ${shortDate(endsOn!)}. ` +
        "Your fat-loss goal stays; Coach will suggest the next step before the break ends."
      : phase === "maintenance"
      ? `Your daily target moves to maintenance, ${kcal(calories)}, until you choose otherwise.`
      : phase === "cut"
      ? `A fat-loss phase at ${kcal(calories)} a day, about ${
        loss.toFixed(2)
      } kg a week, inside your limits.`
      : `A muscle-gain phase at ${kcal(calories)} a day.`);
  const nutrition = nutritionChange(basis, calories, rationale);
  if (nutrition === null) {
    return refusals.infeasible("no protein, fat and carbohydrate split fits that calorie target");
  }

  const change: GoalChange = {
    goal_type: goalType,
    phase,
    phase_started_on: today,
    phase_ends_on: endsOn,
    ...(target === undefined ? {} : { target }),
  };
  const phaseBefore = goal.phase ? phaseLabels[goal.phase] : goalLabels[goal.goalType];
  const phaseAfter = phase === "diet_break"
    ? `${phaseLabels[phase]} until ${shortDate(endsOn!)}`
    : phaseLabels[phase];
  const targetRows = (value: string | undefined): DisplayRow[] =>
    intent.targetWeightKg === undefined && value === undefined ? [] : [{
      label: "Target",
      value: value ?? "none",
    }];
  const beforeTarget = goal.target.weightKg === null ? undefined : `${goal.target.weightKg} kg`;
  const afterTarget = target?.weight_kg === undefined
    ? undefined
    : `${target.weight_kg} kg${target.date ? ` by ${shortDate(target.date)}` : ""}`;

  const proposal: CoachProposal = {
    kind: "goal_or_phase",
    title: phase === "diet_break"
      ? "Take a diet break"
      : phase === "maintenance"
      ? "Move to maintenance"
      : phase === "cut"
      ? "Start a fat-loss phase"
      : "Start a gain phase",
    rationale,
    benefit: phase === "diet_break" || phase === "maintenance"
      ? "Time at maintenance to recover and keep your progress."
      : phase === "cut"
      ? "A steady loss pace your logging supports."
      : "A small surplus to support muscle gain.",
    downside: phase === "cut"
      ? "A calorie deficit makes training and hunger harder; it is rechecked as your weight comes in."
      : phase === "gain"
      ? "Some of the weight gained will be fat."
      : "Fat loss pauses while you are at maintenance. Your training plan is unchanged.",
    confidence: gated ? "medium" : "low",
    evidence: [
      ...nutritionEvidence(gated, state),
      {
        code: "GOAL_PHASE_REVIEW",
        label: "Your weight history for the current goal",
        source: "policy_evaluation",
      },
    ],
    expiresInHours: proposalExpiryHours.default,
    endsOn,
    before: {
      rows: [
        { label: "Phase", value: phaseBefore },
        ...nutritionRowsBefore(state.nutrition),
        ...targetRows(beforeTarget),
      ],
    },
    after: {
      rows: [
        { label: "Phase", value: phaseAfter },
        ...nutritionRowsAfter(nutrition),
        ...targetRows(afterTarget ?? beforeTarget),
      ],
    },
    payload: { goal: change, nutrition },
    basis: basisOf(state, gated ? ["nutrition_change"] : []),
  };
  return { ok: true, proposal };
}
