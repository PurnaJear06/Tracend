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
import type { ScreeningState } from "../coach_context/contributors/screening.ts";
import { type NumberGround, ungroundedNumbers } from "./numbers_check.ts";
import type { SafeRanges } from "./safe_ranges.ts";

const sentencesOf = (answer: string) =>
  answer.split(/(?<=[.!?])\s+|\n+/).map((sentence) => sentence.trim()).filter(Boolean);

const toNumber = (raw: string) => Number(raw.replaceAll(",", ""));

// A sentence that warns against, limits or rejects a thing is not advising it.
const warning =
  /\b(?:never|don'?t|do not|avoid|shouldn'?t|should not|must not|not (?:go|drop|eat|safe|recommend\w*|advis\w*|healthy|sustainable)|can'?t|cannot|isn'?t (?:safe|advis\w*|recommend\w*|healthy)|too (?:low|fast|much|aggressive|quick)|dangerous\w*|unsafe|risky|below which|no lower|without going|instead of|rather than|hold off|not a good idea)\b/i;

// ---- calories_below_floor -------------------------------------------------------------------

const kcalFigure =
  /(\d{1,2},\d{3}|\d{3,4})(?:\s*(?:-|–|to)\s*(\d{1,2},\d{3}|\d{3,4}))?\s*(?:kcal|calories|cals?)\b/gi;
const intakeVerb =
  /\b(?:eat|eating|consume|consuming|have|having|aim for|aiming for|target|targeting|set (?:it |your calories |your target |your intake )?at|stay at|stay under|settle on|calorie (?:target|intake|goal) of)\s*(?:about |around |roughly |approximately |just |only |closer to |~)?(?:between |from )?$/i;
const reduceVerb =
  /\b(?:drop|dropping|reduce|reducing|cut|cutting|lower|lowering|go|going|move|moving|bring|bringing|come|coming|down|fall|falling|get|getting|set|keep|keeping|limit|limiting|stay|staying)\b.{0,25}\b(?:to|at|around|under|below|between)\s*(?:about |around |roughly |approximately |just |only |~)?(?:between |from )?$/i;
const dailyCue =
  /\b(?:a day|per day|each day|every day|daily|\/day|total|on a (?:normal|training|rest) day)\b/i;
// Words that make a figure something other than the day's total: a meal, or energy burned.
const notADailyTotal =
  /\b(?:breakfast|lunch|dinner|snack|snacks|meal|meals|serving|portion|bar|per meal|with each|post-workout|pre-workout|shake|drink|slice|piece|cup|bowl|burn|burned|burning|expend\w*|tdee|maintenance|cardio|treadmill|session|workout|walk|run)\b/i;
const mealAfterFigure =
  /^\s*(?:snacks?|meals?|dinners?|lunch|breakfast|servings?|portions?|bars?|shakes?|drinks?|slices?|pieces?|cups?|bowls?|per meal|per serving|at (?:dinner|lunch|breakfast)|for (?:dinner|lunch|breakfast|a meal|a snack))\b/i;
// A limit word directly governing the figure: "don't go below 1,500 kcal", "never under 1,200",
// "don't drop to 1,500 calories". A negation earlier in the sentence ("don't skip meals; drop to
// 900") does not govern it.
const negator = String.raw`(?:never|not|no|avoid\w*|\w+n't|cannot|mustn't)`;
const limitBeforeFigure = new RegExp(
  String
    .raw`\b${negator}\b[^.;,]{0,30}?\b(?:below|under|beneath|less than|lower than|fewer than)\s*(?:about |around |roughly |approximately |~)?(?:between |from )?$|\b${negator}\s+(?:(?:ever|even|really|to|go|get|let|your|calories|intake|yourself|be|you)\s+){0,3}(?:eat|go|drop|dip|fall|set|have|consume|reduce|cut|aim|stay|take|plan|limit|restrict|diet|run|lower)\b[^.;,]{0,25}$`,
  "i",
);
// A judgement of the figure itself: "1,200 kcal a day is too low".
const judgementAfterFigure =
  /^\s*(?:a day |per day |daily |each day )?(?:is|are|would be|will be|was|isn'?t|aren'?t)?\s*(?:far |way |much |dangerously |really |too |not )*(?:too low|too little|too few|too aggressive|dangerously low|unsafe|safe|not enough|below (?:the|your) floor|under (?:the|your) floor|not recommended|not advisable)/i;
const modalCue = /\b(?:should|try|aim|let'?s|recommend|suggest|set|drop|stick|go)\b/i;

function belowCalorieFloor(sentence: string, floor: number): boolean {
  for (const match of sentence.matchAll(kcalFigure)) {
    const low = Math.min(
      toNumber(match[1]),
      match[2] === undefined ? Infinity : toNumber(match[2]),
    );
    if (low >= floor) continue;
    const before = sentence.slice(0, match.index);
    const after = sentence.slice(match.index + match[0].length);
    if (limitBeforeFigure.test(before) || judgementAfterFigure.test(after)) continue;
    if (mealAfterFigure.test(after)) continue;
    const reduce = reduceVerb.exec(before);
    if (reduce) {
      if (!notADailyTotal.test(before.slice(reduce.index))) return true;
      continue;
    }
    const intake = intakeVerb.exec(before);
    if (intake && /\b(?:day|daily)\b/i.test(sentence)) {
      if (!notADailyTotal.test(before.slice(intake.index))) return true;
      continue;
    }
    if (
      dailyCue.test(sentence.slice(match.index)) && modalCue.test(sentence) &&
      !notADailyTotal.test(before.slice(-20))
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

// ---- effort_above_screening_cap and training_advice_on_pain_day -----------------------------

const vigorous =
  /\b(?:all[- ]out|max(?:imal|imum)?[- ]effort|maximal|to failure|until failure|go (?:hard|heavy)|push (?:harder|hard|through)|push to your limit|1[- ]?rm|one[- ]rep max|heavy (?:single|triple|double)s?|sprints?|sprinting|hiit|high[- ]intensity|intervals?|vigorous|rpe ?(?:9|10)|(?:0|zero|1|one) (?:reps? in reserve|rir)|failure|test your max|max out|burnout set)\b/i;
// A sentence that rules the thing out. "Moderate", "limited" and "cleared" do not: "keep HIIT
// moderate" still advises HIIT.
const prohibition =
  /\b(?:no|not|never|avoid|avoiding|skip|instead of|rather than|don'?t|do not|shouldn'?t|should not|until (?:you|your|cleared|a doctor|you've)|stay away|without|off the table|out of bounds|wait)\b/i;

const countWords = "(?:\\d+|one|two|three|four|five|six|seven|a couple of|a few|several)";
// Any prescription of training: sets and reps, loads on a lift, minutes of exercise, a
// programme, a weekly frequency, steps, or exercises to do.
const prescriptionPatterns: readonly RegExp[] = [
  /\b\d+\s*(?:x|\u00d7)\s*\d+\b/i,
  /\b\d+(?:\s*(?:-|\u2013|to)\s*\d+)?\s*(?:sets?|reps?|repetitions?|rounds?)\b/i,
  /\b(?:rpe|rir)\s*\d|\b\d+\s*rir\b|\breps? in reserve\b/i,
  /\b\d+(?:\.\d+)?\s*(?:kg|lbs?|pounds?)\b.{0,25}\b(?:squat|deadlift|bench|press|row|curl|lift|lunge|carry|pull)/i,
  /\b(?:squat|deadlift|bench|press|row|curl|lunge)\w*\b.{0,25}\b\d+(?:\.\d+)?\s*(?:kg|lbs?|pounds?)\b/i,
  /\b\d+(?:[,.]\d+)?(?:\s*(?:-|\u2013|to)\s*\d+(?:[,.]\d+)?)?\s*(?:minutes?|mins?|hours?)\b.{0,30}\b(?:cardio|run|running|jog\w*|walk\w*|cycl\w+|swim\w*|rowing|workout|session|training|exercise|elliptical|bike|hiit)\b/i,
  /\b(?:cardio|run|running|jog\w*|walk\w*|cycl\w+|swim\w*|workout|session|training|exercise|bike)\b.{0,30}\b\d+(?:[,.]\d+)?(?:\s*(?:-|\u2013|to)\s*\d+)?\s*(?:minutes?|mins?|hours?)\b/i,
  /\b(?:aim|target|go for|get|hit|reach|do|walk)\b.{0,15}\b\d{1,3}(?:,\d{3})?\s*steps\b/i,
  new RegExp(
    String
      .raw`\b${countWords}(?:[- ]day)?\s+(?:split|programme|program|routine|circuit)\b|\b(?:push|pull)(?:,|\s+and)?\s*(?:pull|legs?)\b|\b(?:full[- ]body|upper[- ]lower|upper/lower)\b`,
    "i",
  ),
  new RegExp(
    String
      .raw`\b(?:once|twice|${countWords}\s*(?:x|times))\s*(?:a|per|each|every)?\s*(?:a |per |each |every )?week\b.{0,30}\b(?:train\w*|workouts?|lift\w*|cardio|sessions?|exercise)\b|\b(?:train\w*|workouts?|lift\w*|cardio|sessions?|exercise)\b.{0,30}\b(?:once|twice|${countWords}\s*(?:x|times))\s*(?:a|per|each|every)\s*week\b|\btrain\s+${countWords}\s+times\b`,
    "i",
  ),
  /\b(?:do|perform|try|add|start with|begin with|finish with|superset|include)\b.{0,40}\b(?:squats?|deadlifts?|bench|presses|press|rows?|curls?|pull-?ups?|push-?ups?|lunges?|planks?|burpees?|hiit|intervals?|sprints?|circuits?|cardio|stretches)\b/i,
];
// A sentence that declines to prescribe ("I can't give you sets or reps until you are cleared").
const declinesToPrescribe =
  /\b(?:can'?t|cannot|won'?t|will not|not able|unable|never|avoid|don'?t|do not|hold off|wait until)\b|\bno (?:training|workouts?|sets?|reps?|exercise|sessions?|programme|program|cardio|prescription\w*|advice)\b|\bnot (?:to |able to |safe to )?(?:train|exercise|lift|work out|do)\b/i;

function prescribesTraining(sentence: string): boolean {
  if (declinesToPrescribe.test(sentence)) return false;
  return prescriptionPatterns.some((pattern) => pattern.test(sentence)) ||
    vigorous.test(sentence);
}

/**
 * Whether the sentence breaks the health check's cap. moderate_until_cleared (and an unreadable
 * health check, which is treated the same) rules out vigorous effort; see_professional rules out
 * every training prescription.
 */
function aboveScreeningCap(sentence: string, screening: ScreeningState): boolean {
  if (screening === "cleared") return false;
  if (screening === "see_professional") return prescribesTraining(sentence);
  return vigorous.test(sentence) && !prohibition.test(sentence);
}

/** Training advice on a day of check-in pain of 7 or more. */
function trainingOnPainDay(sentence: string, painEscalated: boolean): boolean {
  return painEscalated && prescribesTraining(sentence);
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
  screening: ScreeningState;
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
    if (has((s) => trainingOnPainDay(s, inputs.ranges.painEscalated))) {
      broken.push("training_advice_on_pain_day");
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
