// Plain-language refusals. A refusal names the rule that stopped the change, in words an athlete
// can act on, and carries any figure the rule produced (the floor, the earliest date). Coach may
// quote the text; it never rewords a limit.
import { shortDate } from "./common.ts";
import type { BuildResult, RefusalCode } from "./types.ts";

export function refuse(code: RefusalCode, reason: string): Extract<BuildResult, { ok: false }> {
  return { ok: false, code, reason };
}

export const kcal = (value: number) => `${Math.round(value).toLocaleString("en-US")} kcal`;

export const refusals = {
  seeProfessional: () =>
    refuse(
      "screening_see_professional",
      "Your health check says a health professional should clear you before Tracend changes " +
        "your plan. Once they have, you can redo the health check in your profile.",
    ),
  screeningCapsIntensity: () =>
    refuse(
      "screening_caps_intensity",
      "Your health check caps your training at moderate effort until a health professional " +
        "clears you, so I can't raise the intensity or start a strength-focus block.",
    ),
  noPlan: () => refuse("no_active_plan", "You don't have an active training plan to change yet."),
  noNutrition: () =>
    refuse("no_active_nutrition", "You don't have an active nutrition target to change yet."),
  noGoal: () => refuse("no_active_goal", "You don't have an active goal to change yet."),
  noWeight: () =>
    refuse(
      "no_recent_weight",
      "I need a weight from the last two weeks to size your calories. Log one and ask again.",
    ),
  notEnoughLogging: (detail: string) =>
    refuse(
      "not_enough_logging",
      `There isn't enough complete logging yet to lower your calories safely (${detail}). ` +
        "Weigh in and log your meals on most days for two weeks, then ask again.",
    ),
  notEnoughTraining: (detail: string) =>
    refuse(
      "not_enough_training_evidence",
      `There isn't enough logged training yet to push harder (${detail}).`,
    ),
  belowFloor: (floor: number) =>
    refuse(
      "below_calorie_floor",
      `That is below your calorie floor of ${kcal(floor)} a day. Tracend never sets a target ` +
        "under it, whatever the goal.",
    ),
  atFloor: (floor: number) =>
    refuse(
      "below_calorie_floor",
      `You're already at your calorie floor of ${kcal(floor)} a day. Tracend won't go lower.`,
    ),
  aboveCeiling: (ceiling: number) =>
    refuse(
      "above_calorie_ceiling",
      `That is above the highest daily target Tracend sets (${kcal(ceiling)}).`,
    ),
  tooFast: (calories: number, weeklyKg: number, ceilingKg: number) =>
    refuse(
      "weight_loss_too_fast",
      `${kcal(calories)} a day would lose about ${weeklyKg.toFixed(2)} kg a week, above the ` +
        `${ceilingKg.toFixed(2)} kg a week (1% of your weight) that Tracend allows.`,
    ),
  nearHealthyFloor: (bmi: number) =>
    refuse(
      "weight_near_healthy_floor",
      `Your BMI is ${bmi.toFixed(1)}, close to the bottom of the healthy range, so Tracend ` +
        "won't set a lower calorie target or a fat-loss phase.",
    ),
  targetBelowFloor: (floorKg: number) =>
    refuse(
      "target_below_healthy_floor",
      `A target weight under ${floorKg} kg is below the healthy range for your height ` +
        "(BMI 18.5), so Tracend can't set it.",
    ),
  targetWrongDirection: (phase: string) =>
    refuse(
      "target_wrong_direction",
      `That target weight doesn't fit a ${phase} phase from your current weight.`,
    ),
  targetDateInvalid: (detail: string) => refuse("target_date_invalid", detail),
  targetTooFast: (earliest: string, ceilingKg: number) =>
    refuse(
      "weight_loss_too_fast",
      `That date needs more than ${ceilingKg.toFixed(2)} kg a week (1% of your weight), the ` +
        `fastest Tracend allows. The earliest date that fits is ${earliest}.`,
    ),
  cutTooLong: (detail: string) =>
    refuse(
      "cut_too_long",
      `Your weight history says a maintenance period or a diet break comes before more loss ` +
        `(${detail}).`,
    ),
  dietBreakNeedsFatLoss: () =>
    refuse(
      "diet_break_needs_fat_loss",
      "A diet break follows a fat-loss phase. Your goal isn't fat loss right now.",
    ),
  alreadyOnTarget: (calories: number) =>
    refuse("already_on_target", `Your calorie target is already ${kcal(calories)}.`),
  alreadyInPhase: (phase: string) =>
    refuse("already_in_phase", `You're already in a ${phase} phase.`),
  noChange: (detail: string) => refuse("no_change", detail),
  datesInvalid: () =>
    refuse("dates_invalid", "The end date must not be before the start date, or in the past."),
  blockTooLong: (days: number) =>
    refuse(
      "block_too_long",
      `A temporary block can last up to ${days} days. For longer, change your weekly schedule.`,
    ),
  blockStartTooFar: () =>
    refuse(
      "block_start_too_far",
      "A block starts as soon as you approve it. Ask again closer to the start date.",
    ),
  blockActive: (endsOn: string) =>
    refuse(
      "block_already_active",
      `A temporary block is already running until ${
        shortDate(endsOn)
      }. Let it end first, or undo it.`,
    ),
  infeasible: (detail: string) =>
    refuse("plan_infeasible", `I can't build a full session within your limits: ${detail}`),
  notInPlan: () => refuse("exercise_not_in_plan", "That exercise isn't in your active plan."),
  noSubstitute: () =>
    refuse(
      "no_substitute",
      "I don't have a substitute for that exercise that fits your equipment and the movements " +
        "you avoid.",
    ),
  substituteNotAllowed: () =>
    refuse(
      "substitute_not_allowed",
      "That exercise isn't a like-for-like substitute that fits your equipment and the " +
        "movements you avoid.",
    ),
  invalidSchedule: (detail: string) => refuse("invalid_schedule", detail),
  noUpcomingSession: () =>
    refuse("no_upcoming_session", "I don't see a planned session to adjust."),
  heavierNotSupported: (detail: string) => refuse("heavier_not_supported", detail),
  figureNotFromAthlete: (what: string) =>
    refuse(
      "figure_not_from_athlete",
      `I can only use a ${what} you've given me yourself. Tell me the figure you want.`,
    ),
  profileIncomplete: () =>
    refuse(
      "profile_incomplete",
      "I don't have enough of your profile (sex, birth year, height, equipment) to size a " +
        "change. Finish your profile and ask again.",
    ),
  planChanged: () =>
    refuse(
      "plan_changed",
      "Your plan changed while I was preparing this. Ask again and I'll start from the latest.",
    ),
  screeningChanged: () =>
    refuse(
      "screening_changed",
      "Your health check changed while I was preparing this, so I can't put it forward. Once it's up to date, ask again.",
    ),
  evidenceChanged: () =>
    refuse(
      "evidence_changed",
      "The logged data this change rests on changed while I was preparing it. Ask again and I'll check it afresh.",
    ),
  invalidIntent: () =>
    refuse(
      "invalid_intent",
      "I couldn't turn that into a change I can put forward. Tell me what you'd like to change and I'll try again.",
    ),
} as const;
