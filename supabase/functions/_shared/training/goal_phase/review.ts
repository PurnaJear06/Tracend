// The phase review: one outcome from the summary and the thresholds. Coach reads the outcome and
// explains it; it never sets or changes it (Architecture rule 1), and the athlete alone sets a
// target (rule 2). Safety outcomes come before "ask for a target", so an athlete deep in a long
// cut is told so even while no target is set; `needsTarget` still says a target is missing.
import { goalPhaseThresholds as limits } from "./thresholds.ts";
import type { GoalPhaseReview, GoalPhaseSummary, ReviewReason } from "./types.ts";

const lossGoalTypes = ["fat_loss"];
const gainGoalTypes = ["muscle_gain"];

/** The sign of the goal: -1 to lose weight, 1 to gain, 0 when the goal does not say. */
function goalDirection(summary: GoalPhaseSummary): -1 | 0 | 1 {
  const target = summary.target.weightKg;
  if (target !== null && summary.startWeightKg !== null && target !== summary.startWeightKg) {
    return target < summary.startWeightKg ? -1 : 1;
  }
  if (summary.goalType !== null && lossGoalTypes.includes(summary.goalType)) return -1;
  if (summary.goalType !== null && gainGoalTypes.includes(summary.goalType)) return 1;
  return 0;
}

function targetReached(summary: GoalPhaseSummary): ReviewReason | null {
  const target = summary.target.weightKg;
  const current = summary.currentWeightKg;
  if (target === null || current === null) return null;
  const direction = goalDirection(summary);
  const slack = limits.targetToleranceKg.value;
  const reached = direction < 0
    ? current <= target + slack
    : direction > 0
    ? current >= target - slack
    : false;
  return reached
    ? {
      code: "target_weight_reached",
      detail: `current ${current} kg is at the target of ${target} kg`,
      sources: [],
    }
    : null;
}

/** The pace now, in kg a week: the recent fit when there is one, else the phase average. */
function currentPace(summary: GoalPhaseSummary): number | null {
  return summary.recentRateKgPerWeek ?? summary.weeklyRateKg;
}

function maintenanceReasons(summary: GoalPhaseSummary): ReviewReason[] {
  const reasons: ReviewReason[] = [];
  const pace = currentPace(summary);
  const stillLosing = pace !== null && pace <= -limits.stillLosingKgPerWeek.value;
  const bmi = summary.bmi;
  if (bmi !== null && bmi < limits.bmiHealthyFloor.value) {
    reasons.push({
      code: "bmi_below_healthy_range",
      detail: `BMI ${bmi} is below ${limits.bmiHealthyFloor.value}, the underweight range`,
      sources: ["who_2004"],
    });
  } else if (bmi !== null && bmi < limits.bmiNearFloor.value && stillLosing) {
    reasons.push({
      code: "bmi_near_healthy_floor",
      detail: `BMI ${bmi} is close to ${limits.bmiHealthyFloor.value} and weight is still falling`,
      sources: ["who_2004", "tracend_in_house"],
    });
  }
  // The loss is judged over the continuous run of falling weight when it differs from the goal
  // phase (it began before the goal, or the weight rose first): the athlete's body does not
  // know the date the goal was activated.
  const run = summary.continuousLoss;
  const weeks = run?.weeks ?? summary.weeks;
  const changePct = run?.changePct ?? summary.changePct;
  const since = run?.startDate ?? summary.phaseStart;
  if (stillLosing && weeks !== null && changePct !== null) {
    if (
      weeks >= limits.longDeficitWeeks.value &&
      changePct <= -limits.longDeficitMinimumLossPct.value
    ) {
      reasons.push({
        code: "long_continuous_deficit",
        detail: `${weeks} weeks of falling weight since ${since} (${changePct}% from the start ` +
          `of the run); a continuous deficit this long is usually broken up`,
        sources: ["byrne_2018", "trexler_2014", "jensen_2014"],
      });
    }
    if (
      weeks >= limits.largeLossMinimumWeeks.value &&
      changePct <= -limits.largeLossPct.value
    ) {
      reasons.push({
        code: "large_total_loss",
        detail: `${Math.abs(changePct)}% of body weight lost since ${since}`,
        sources: ["jensen_2014", "tracend_in_house"],
      });
    }
  }
  return reasons;
}

function fastRate(summary: GoalPhaseSummary): ReviewReason | null {
  const pace = currentPace(summary);
  const current = summary.currentWeightKg;
  const weeks = summary.weeks;
  if (pace === null || current === null || weeks === null) return null;
  if (weeks < limits.fastRateMinimumWeeks.value) return null;
  const pct = (Math.abs(pace) / current) * 100;
  if (pace < 0 && pct > limits.fastRatePctPerWeek.value) {
    return {
      code: "fast_sustained_loss",
      detail: `losing ${Math.abs(pace)} kg a week, about ${pct.toFixed(1)}% of body weight, ` +
        `above ${limits.fastRatePctPerWeek.value}% a week`,
      sources: ["helms_2014", "garthe_2011"],
    };
  }
  return null;
}

export function reviewGoalPhase(summary: GoalPhaseSummary): GoalPhaseReview {
  const needsTarget = summary.hasGoal && !summary.hasTarget;
  const reached = targetReached(summary);
  if (reached) return { outcome: "target_reached", reasons: [reached], needsTarget };

  const maintenance = maintenanceReasons(summary);
  if (maintenance.length > 0) {
    return { outcome: "consider_maintenance_or_diet_break", reasons: maintenance, needsTarget };
  }
  const fast = fastRate(summary);
  if (fast) return { outcome: "slow_down", reasons: [fast], needsTarget };
  if (needsTarget) {
    return {
      outcome: "ask_target",
      reasons: [{
        code: "no_target",
        detail: "the goal has no target weight, body-fat range or physique goal",
        sources: [],
      }],
      needsTarget,
    };
  }
  return { outcome: "continue", reasons: [], needsTarget };
}
