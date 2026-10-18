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
import { weightFiguresIn } from "./weight_figures.ts";

export type WeightClaimRule = "weight_below_healthy_floor" | "projection_without_target";

export type WeightClaimContext = Readonly<{
  currentKg: number | null;
  floorKg: number | null;
  hasTarget: boolean;
  /** -1 weight falling, 1 rising, 0 flat or unknown. */
  direction: -1 | 0 | 1;
}>;

const numberWord =
  "(?:\\d+(?:\\s*(?:-|–|to)\\s*\\d+)?|a|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|several|a few|a couple of)";
const months =
  "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";

// A claim about where the weight will be: a time ("in 12 weeks", "by March") or a pace cue.
const timeCue = new RegExp(
  [
    `\\bin (?:about |around |roughly |another |just |only )?(?:the next )?${numberWord} ?(?:days?|weeks?|months?|years?)\\b`,
    `\\bwithin (?:the next )?${numberWord}\\b`,
    `\\bby (?:the )?(?:end|then|week|month|next|christmas|summer|winter|spring|autumn|fall|\\d|${months}\\b)`,
    "\\bat (?:this|that|the same|the current) (?:pace|rate)\\b",
    "\\bif you (?:keep|continue|carry on|stay|maintain)\\b",
    "\\bkeep(?:ing)? (?:going|this up|up)\\b",
    "\\bon track\\b",
    "\\bproject(?:ed|ion|ing)?\\b",
    "\\bextrapolat",
  ].join("|"),
  "i",
);

// The subset of cues that read the trend forward, which a target proposal does not excuse.
const paceCue =
  /\bat (?:this|that|the same|the current) (?:pace|rate)\b|\bif you (?:keep|continue|carry on|stay|maintain)\b|\bon track\b|\bproject(?:ed|ion|ing)?\b|\bextrapolat/i;

// Where the sentence looks ahead at all (used for the healthy-floor rule).
const lookAhead = new RegExp(
  `${timeCue.source}|\\bwill\\b|\\bwould\\b|'ll\\b|\\bcould\\b|\\bgoing to\\b|\\breach(?:ing)?\\b|\\bhit(?:ting)?\\b|\\bend(?:ing)? up\\b|\\bends? at\\b|\\bdown to\\b|\\bget(?:ting)? to\\b|\\bhead(?:ing|ed|s)\\b|\\btrend(?:ing|s)? (?:to|toward|towards)\\b|\\b(?:put|puts|putting|leave|leaves|leaving) you\\b|\\bland(?:s|ing)?\\b|\\bexpect(?:ed|ing)?\\b|\\bwhere (?:it|this|that) (?:goes|ends|leads)\\b`,
  "i",
);

// A sentence that proposes a target to the athlete is the "ask for a target" reply, not a forecast.
const targetProposal = /\b(?:target|aim|aiming|goal)\b/i;

// A limit: the weight is directly governed by "below", "under", "less than" and the like.
const limitBefore =
  /\b(?:below|under|beneath|less than|lower than|stop at)\s+(?:about |around |roughly |~)?$/i;

/**
 * Body weights in a sentence, in kg; weights that are the object of a limit word are left out.
 * A figure counts only when its surroundings say it is a body weight (weight_figures.ts): a load
 * on the bar ("overhead press is 55 kg x 6") is not one.
 */
function bodyWeightsIn(sentence: string): number[] {
  const found: number[] = [];
  for (const figure of weightFiguresIn(sentence)) {
    if (!figure.bodyWeight) continue;
    if (limitBefore.test(figure.before)) continue;
    for (const kg of figure.kgs) if (kg >= 30 && kg <= 300) found.push(kg);
  }
  return found;
}

/** The first rule the answer text breaks, or null. */
export function weightClaimViolation(
  answer: string,
  question: string,
  context: WeightClaimContext,
): WeightClaimRule | null {
  // Every figure the athlete wrote is theirs, whatever it measures.
  const own = weightFiguresIn(question).flatMap((figure) => [...figure.kgs]);
  const theirs = (kg: number) => own.some((value) => Math.abs(value - kg) < 0.5);
  for (const sentence of answer.split(/(?<=[.!?])\s+|\n+/)) {
    const asksOrProposes = sentence.trim().endsWith("?") ||
      (targetProposal.test(sentence) && !paceCue.test(sentence));
    const forwardLooking = lookAhead.test(sentence) || targetProposal.test(sentence);
    for (const kg of bodyWeightsIn(sentence)) {
      if (theirs(kg)) continue;
      if (forwardLooking && context.floorKg !== null && kg < context.floorKg - 0.05) {
        return "weight_below_healthy_floor";
      }
      if (
        !context.hasTarget && !asksOrProposes && timeCue.test(sentence) &&
        context.currentKg !== null && (
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
