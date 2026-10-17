// The reply guard for Coach chat: deterministic checks on the answer text, run after the model
// answers and before anything is stored or shown. Each rule is a finite validation rule with its
// own repair instruction (coach_chat_provider.ts, repairRuleHint), like the goal phase check it
// sits beside (training/goal_phase/guard.ts). A reply that breaks rules is repaired once with
// every broken rule named; a second failure ends in the labelled data summary.
//
// The rules:
//   calories_below_floor        advises a daily intake under the calorie floor
//   loss_rate_above_ceiling     advises losing weight faster than the weekly ceiling
//   effort_above_screening_cap  advises vigorous or maximal effort when the health check caps it
//   claimed_action              says Coach changed, saved, scheduled or will do something
//   numbers_not_grounded        states a figure that is not in the athlete's data or message
// Sentences that warn against a thing ("never go below 1,200 kcal") or describe the athlete's
// past ("you lost 0.9 kg a week") are not advice and never break a rule.
import type {
  CoachChatAnswerBreak,
  CoachChatAnswerCheck,
  CoachChatValidationRule,
} from "../contracts/coach_chat_v1.ts";
import type { ScreeningOutcome } from "../training/screening/outcome.ts";
import { type NumberGround, ungroundedNumbers } from "./numbers_check.ts";
import type { SafeRanges } from "./safe_ranges.ts";

const sentencesOf = (answer: string) =>
  answer.split(/(?<=[.!?])\s+|\n+/).map((sentence) => sentence.trim()).filter(Boolean);

const toNumber = (raw: string) => Number(raw.replaceAll(",", ""));

// A sentence that warns against, limits or rejects a thing is not advising it.
const warning =
  /\b(?:never|don'?t|do not|avoid|shouldn'?t|should not|must not|not (?:go|drop|eat|safe|recommend\w*|advis\w*|healthy|sustainable)|can'?t|cannot|isn'?t (?:safe|advis\w*|recommend\w*|healthy)|too (?:low|fast|much|aggressive|quick)|dangerous\w*|unsafe|risky|below which|floor|minimum|no lower|without going|instead of|rather than|hold off|not a good idea)\b/i;

// ---- calories_below_floor -------------------------------------------------------------------

const kcalFigure =
  /(\d{1,2},\d{3}|\d{3,4})(?:\s*(?:-|–|to)\s*(\d{1,2},\d{3}|\d{3,4}))?\s*(?:kcal|calories|cals?)\b/gi;
const intakeVerb =
  /\b(?:eat|eating|consume|consuming|have|having|aim for|aiming for|target|targeting|set (?:it |your calories |your target |your intake )?at|stay at|stay under|settle on|calorie (?:target|intake|goal) of)\s*(?:about |around |roughly |approximately |just |only |closer to |~)?(?:between |from )?$/i;
const reduceVerb =
  /\b(?:drop|dropping|reduce|reducing|cut|cutting|lower|lowering|go|going|move|moving|bring|bringing|come|coming|down|fall|falling|get|getting|set|keep|keeping|limit|limiting|stay|staying)\b.{0,25}\b(?:to|at|around|under|below|between)\s*(?:about |around |roughly |approximately |just |only |~)?(?:between |from )?$/i;
const dailyCue =
  /\b(?:a day|per day|each day|every day|daily|\/day|total|on a (?:normal|training|rest) day)\b/i;
const notADailyTotal =
  /\b(?:breakfast|lunch|dinner|snack|meal|serving|portion|bar|per meal|with each|post-workout|pre-workout|shake|drink|slice|piece|cup|bowl|burn|burned|burning|expend\w*|tdee|maintenance|cardio|treadmill|session|workout|walk|run)\b/i;

function belowCalorieFloor(sentence: string, floor: number): boolean {
  if (warning.test(sentence) || notADailyTotal.test(sentence)) return false;
  for (const match of sentence.matchAll(kcalFigure)) {
    const low = Math.min(
      toNumber(match[1]),
      match[2] === undefined ? Infinity : toNumber(match[2]),
    );
    if (low >= floor) continue;
    const before = sentence.slice(0, match.index);
    if (reduceVerb.test(before)) return true;
    if (intakeVerb.test(before) && /\b(?:day|daily)\b/i.test(sentence)) return true;
    if (
      dailyCue.test(sentence.slice(match.index)) &&
      /\b(?:should|try|aim|let'?s|recommend|suggest|set|drop|stick|go)\b/i.test(sentence)
    ) {
      return true;
    }
  }
  return false;
}

// ---- loss_rate_above_ceiling ----------------------------------------------------------------

const weeklyLoss =
  /(\d+(?:\.\d+)?)(?:\s*(?:-|–|to)\s*(\d+(?:\.\d+)?))?\s*(kgs?|kilos?|kilograms?|lbs?|pounds?|%|percent)(?:\s+of\s+(?:your\s+)?(?:body\s*)?weight)?\s*(?:a|per|each|every|\/)\s*week\b/gi;
const lossOverWeeks =
  /\b(?:lose|losing|drop|dropping|shed|shedding)\s+(?:about |around |roughly |another |a further )?(\d+(?:\.\d+)?)\s*(kgs?|kilos?|kilograms?|lbs?|pounds?)?\s*(?:in|over|within)\s*(?:about |around |the next )?(\d+)\s*weeks?\b/gi;
const lossCue =
  /\b(?:aim|aiming|target|targeting|go for|lose|losing|drop|dropping|shed|shedding|shoot for|should|try|push for|up to|as much as|get to|take it to|speed|faster|increase|step up)\b/i;
const describesAthlete =
  /\b(?:you(?:'re| are| were| have| lost|'ve)|your (?:pace|rate|loss|trend|average|current)|over the (?:last|past)|last \d+ weeks?|so far|currently|recent(?:ly)?|has been|have been)\b/i;
const exceedsOrWarns = /\b(?:more than|faster than|above|exceed\w*|beyond|over \d)\b/i;

function kilograms(amount: number, unit: string, weightKg: number | null): number | null {
  const lowered = unit.toLowerCase();
  if (lowered.startsWith("lb") || lowered.startsWith("pound")) return amount / 2.20462;
  if (lowered === "%" || lowered === "percent") {
    return weightKg === null ? null : amount * weightKg / 100;
  }
  return amount;
}

function lossAboveCeiling(sentence: string, ranges: SafeRanges): boolean {
  if (warning.test(sentence) || describesAthlete.test(sentence) || exceedsOrWarns.test(sentence)) {
    return false;
  }
  if (!lossCue.test(sentence)) return false;
  const ceilingKg = ranges.weeklyLossCeilingKg;
  const slack = 0.05;
  for (const match of sentence.matchAll(weeklyLoss)) {
    const amount = Math.max(Number(match[1]), match[2] === undefined ? 0 : Number(match[2]));
    const unit = match[3].toLowerCase();
    if (unit === "%" || unit === "percent") {
      if (amount > ranges.weeklyLossCeilingPct + slack) return true;
      continue;
    }
    const kg = kilograms(amount, unit, ranges.weightKg);
    if (kg !== null && ceilingKg !== null && kg > ceilingKg + slack) return true;
  }
  for (const match of sentence.matchAll(lossOverWeeks)) {
    const kg = kilograms(Number(match[1]), match[2] ?? "kg", ranges.weightKg);
    const weeks = Number(match[3]);
    if (kg !== null && weeks > 0 && ceilingKg !== null && kg / weeks > ceilingKg + slack) {
      return true;
    }
  }
  return false;
}

// ---- effort_above_screening_cap -------------------------------------------------------------

const vigorous =
  /\b(?:all[- ]out|max(?:imal|imum)?[- ]effort|maximal|to failure|until failure|go (?:hard|heavy)|push (?:harder|hard|through)|push to your limit|1[- ]?rm|one[- ]rep max|heavy (?:single|triple|double)s?|sprints?|sprinting|hiit|high[- ]intensity|intervals?|vigorous|rpe ?(?:9|10)|(?:0|zero|1|one) (?:reps? in reserve|rir)|failure|test your max|max out|burnout set)\b/i;
const protective =
  /\b(?:no|not|never|avoid|skip|instead of|rather than|don'?t|do not|shouldn'?t|should not|until (?:you|your|cleared|a doctor|you've)|stay away|without|keep (?:it |things |the effort )?(?:moderate|light|easy)|moderate|cap|limit\w*|clearance|cleared)\b/i;

function aboveScreeningCap(sentence: string, screening: ScreeningOutcome): boolean {
  if (screening === "cleared") return false;
  return vigorous.test(sentence) && !protective.test(sentence);
}

// ---- claimed_action -------------------------------------------------------------------------

const actionVerbs =
  "updated|changed|adjusted|lowered|raised|increased|reduced|set|saved|scheduled|logged|recorded|added|removed|swapped|replaced|moved|cancell?ed|booked|created|modified|reset|switched|applied|bumped|rescheduled|deleted|turned|stored";
const actionBase =
  "update|change|adjust|lower|raise|increase|reduce|set|save|schedule|log|record|add|remove|swap|replace|move|cancel|book|create|modify|reset|switch|apply|bump|reschedule|delete|turn|remember|note|store";
const claimedPatterns: readonly RegExp[] = [
  new RegExp(
    String
      .raw`\b(?:i|we|tracend|coach)(?:'ve| have| has)?\s+(?:just |already |now |gone ahead and |also |have )*(?:${actionVerbs})\b`,
    "i",
  ),
  new RegExp(
    String
      .raw`\b(?:i|we)(?:'ll| will| am going to|'m going to|'m gonna| shall)\s+(?:go ahead and |just |also |now |quickly )?(?:${actionBase})\b`,
    "i",
  ),
  new RegExp(
    String
      .raw`\b(?:i|we)(?: can| could| would|'d)\s+(?:go ahead and |just |also |quickly )?(?:${actionBase})\s+(?:your|the|that|this|it|those|them)\b`,
    "i",
  ),
  new RegExp(String.raw`\blet me\s+(?:go ahead and |just |quickly )?(?:${actionBase})\b`, "i"),
  new RegExp(
    String
      .raw`\b(?:your|the) (?:plan|target|targets|calories|protein|macros?|goal|workout|workouts|schedule|sessions?|program|programme|reminder|nutrition|meal plan|numbers)\b[^.!?\n]{0,40}\b(?:has been|have been|is now|are now|was|were)\s+(?:${actionVerbs})\b`,
    "i",
  ),
  /\b(?:consider it|it'?s|it is|that'?s|that is) done\b/i,
];

function claimsAnAction(sentence: string): boolean {
  if (/\?\s*$/.test(sentence)) return false;
  return claimedPatterns.some((pattern) => pattern.test(sentence));
}

// ---- the combined check ---------------------------------------------------------------------

export type ReplyCheckInputs = Readonly<{
  ranges: SafeRanges;
  screening: ScreeningOutcome;
  /** What Coach was given: the numbers a reply may state. */
  ground: NumberGround;
  /** The goal phase check (training/goal_phase/guard.ts): runs first and keeps its own rules. */
  weightClaim: (answer: string) => CoachChatValidationRule | null;
}>;

function listIn(figures: readonly string[]): string {
  return figures.slice(0, 6).join(", ");
}

/**
 * The check Coach chat applies to every answer: the goal phase rules, the safe-range and
 * screening rules, no claimed actions, and the numbers check. It reports the first rule broken
 * and every other one, so a single repair can fix them together.
 */
export function coachReplyCheck(inputs: ReplyCheckInputs): CoachChatAnswerCheck {
  return (answer): CoachChatAnswerBreak | null => {
    const broken: CoachChatValidationRule[] = [];
    const weight = inputs.weightClaim(answer);
    if (weight) broken.push(weight);
    const sentences = sentencesOf(answer);
    const has = (test: (sentence: string) => boolean) => sentences.some(test);
    if (has((s) => belowCalorieFloor(s, inputs.ranges.calorieFloorKcal))) {
      broken.push("calories_below_floor");
    }
    if (has((s) => lossAboveCeiling(s, inputs.ranges))) broken.push("loss_rate_above_ceiling");
    if (has((s) => aboveScreeningCap(s, inputs.screening))) {
      broken.push("effort_above_screening_cap");
    }
    if (has(claimsAnAction)) broken.push("claimed_action");
    const ungrounded = ungroundedNumbers(answer, inputs.ground);
    if (ungrounded.length > 0) broken.push("numbers_not_grounded");
    if (broken.length === 0) return null;
    return {
      rule: broken[0],
      rules: broken,
      ...(ungrounded.length > 0
        ? {
          detail: listIn(ungrounded),
          ...(broken[0] === "numbers_not_grounded" ? { count: ungrounded.length } : {}),
        }
        : {}),
    };
  };
}
