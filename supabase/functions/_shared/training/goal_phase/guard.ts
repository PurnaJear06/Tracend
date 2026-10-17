// The reply check behind the "no projection as a goal" rule. After Coach answers, a deterministic
// check reads the reply's sentences about a future body weight and refuses two things:
//   - a future weight below the healthy BMI floor for the athlete's height, and
//   - a future weight beyond today's, in the direction of the trend, when the goal has no target
//     (a trend is history, not a goal).
// A weight the athlete wrote in their own question is theirs to ask about and is never flagged;
// sentences that warn against a weight ("do not go below ...") are not claims about the future.
// The model repairs once; a second failure is the existing unavailable path.
import { calculateCoachNumbers } from "../../coach_calculations.ts";
import { hasGoalTarget, healthyFloorWeightKg } from "./bmi.ts";
import { type GoalTarget, noGoalTarget } from "./types.ts";

export type WeightClaimRule = "weight_below_healthy_floor" | "projection_without_target";

export type WeightClaimContext = Readonly<{
  currentKg: number | null;
  floorKg: number | null;
  hasTarget: boolean;
  /** -1 weight falling, 1 rising, 0 flat or unknown. */
  direction: -1 | 0 | 1;
}>;

const kgWord = "(?:kg|kgs|kilos?|kilograms?)";
const lbWord = "(?:lbs?|pounds?)";
const weightPattern = new RegExp(
  `(\\d{2,3}(?:[.,]\\d+)?)(?:\\s*(?:-|–|to)\\s*(\\d{2,3}(?:[.,]\\d+)?))?\\s*(${kgWord}|${lbWord})\\b`,
  "gi",
);

const futureCue = new RegExp(
  [
    "\\bwill\\b",
    "\\bwould\\b",
    "'ll\\b",
    "\\bcould\\b",
    "\\bgoing to\\b",
    "\\bproject(?:ed|ion|ing)?\\b",
    "\\bon track\\b",
    "\\bat (?:this|that|the same|the current) (?:pace|rate)\\b",
    "\\bby (?:the )?(?:end|then|week|month|next|christmas|summer|winter|spring|autumn|fall|\\d)",
    "\\bin (?:about |around |roughly |another |just )?(?:the next )?\\d+(?:\\s*(?:-|–|to)\\s*\\d+)? ?(?:days?|weeks?|months?)\\b",
    "\\bwithin\\b",
    "\\breach(?:ing)?\\b",
    "\\bhit(?:ting)?\\b",
    "\\bend(?:ing)? up\\b",
    "\\bdown to\\b",
    "\\bget(?:ting)? to\\b",
  ].join("|"),
  "i",
);

// A sentence that warns against a weight is a limit, not a prediction.
const warning =
  /\b(?:below|under|beneath|less than|lower than|don'?t|do not|never|avoid|shouldn'?t|should not|stop at|not go)\b/i;

function toKg(amount: number, unit: string): number {
  return /^(?:lb|pound)/i.test(unit) ? amount / 2.20462 : amount;
}

function weightsIn(sentence: string): number[] {
  const found: number[] = [];
  for (const match of sentence.matchAll(weightPattern)) {
    for (const raw of [match[1], match[2]]) {
      if (raw === undefined) continue;
      const kg = toKg(Number(raw.replace(",", ".")), match[3]);
      if (kg >= 30 && kg <= 300) found.push(kg);
    }
  }
  return found;
}

/** The first rule the answer text breaks, or null. */
export function weightClaimViolation(
  answer: string,
  question: string,
  context: WeightClaimContext,
): WeightClaimRule | null {
  const own = weightsIn(question);
  const theirs = (kg: number) => own.some((value) => Math.abs(value - kg) < 0.5);
  for (const sentence of answer.split(/(?<=[.!?])\s+|\n+/)) {
    if (!futureCue.test(sentence) || warning.test(sentence)) continue;
    for (const kg of weightsIn(sentence)) {
      if (theirs(kg)) continue;
      if (context.floorKg !== null && kg < context.floorKg - 0.05) {
        return "weight_below_healthy_floor";
      }
      if (
        !context.hasTarget && context.currentKg !== null && (
          (context.direction < 0 && kg <= context.currentKg - 1) ||
          (context.direction > 0 && kg >= context.currentKg + 1)
        )
      ) return "projection_without_target";
    }
  }
  return null;
}

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/** The goal's target as the frozen athlete file shows it (the goal details). */
export function targetFromDetails(details: Record<string, unknown>): GoalTarget {
  const text = (value: unknown) =>
    typeof value === "string" && value.trim() !== "" ? value.trim() : null;
  return {
    ...noGoalTarget,
    weightKg: num(details.target_weight_kg),
    bodyFatMinPct: num(details.target_body_fat_pct_min),
    bodyFatMaxPct: num(details.target_body_fat_pct_max),
    physique: text(details.target_physique),
    physiqueNote: text(details.target_physique_note),
    date: text(details.target_date),
  };
}

/** What the guard needs, from the prepared Coach context (nothing is fetched). */
export function weightClaimContextOf(context: Record<string, unknown>): WeightClaimContext {
  const goal = obj(context.active_goal);
  const weight = calculateCoachNumbers(context)?.weight ?? null;
  const trend = weight?.trends[0]?.kg_per_week ?? null;
  return {
    currentKg: weight?.latest_kg ?? null,
    floorKg: healthyFloorWeightKg(num(obj(context.profile_context).height_cm)),
    hasTarget: hasGoalTarget(targetFromDetails(obj(goal.details))),
    direction: trend === null || Math.abs(trend) < 0.05 ? 0 : trend < 0 ? -1 : 1,
  };
}

/** The check Coach chat applies to every answer for this turn. */
export function weightClaimCheckFor(
  context: Record<string, unknown>,
  question: string,
): (answer: string) => WeightClaimRule | null {
  const facts = weightClaimContextOf(context);
  return (answer) => weightClaimViolation(answer, question, facts);
}
