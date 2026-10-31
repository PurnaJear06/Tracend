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
//   numbers_not_grounded        states a figure that is not in the athlete's data or message, or
//                               a library figure without citing its source, or as the athlete's
//                               own target
//   citation_not_retrieved      names a library source that Coach was not shown this turn (here:
//                               a source id written in the text, or a study named by its authors
//                               and year, or an institution's fact sheet or guidelines, that no
//                               shown source matches; an evidence item that cites an unshown id is
//                               refused by parseCoachChatAnswer)
//   repeats_previous_turn       ends with the same (or nearly the same) question as the previous
//                               reply, or says again a sentence of it (coach_safety/repeats.ts)
//
// The design rule for every exemption (a warning, a decline, a prohibition, a description of the
// athlete's past): it applies only when it provably governs the matched figure or prescription.
// The reply is cut into clauses (at commas, semicolons, colons, dashes, contrast words and a
// conjunction that starts a new clause: "..., and don't skip the warm-up"); the exemption must
// sit in the same clause, within a short window before the match. Nothing in another clause can
// cover it. When in doubt the reply is flagged: a repair is cheap, a missed breach is not.
import {
  type CoachChatAnswerBreak,
  type CoachChatAnswerCheck,
  coachChatAnswerLimits,
  type CoachChatValidationRule,
  visibleText,
} from "../contracts/coach_chat_v1.ts";
import type { ScreeningState } from "../coach_context/contributors/screening.ts";
import {
  namedShownSources,
  type ShownSources,
  type StudyMention,
  studyMentions,
  unshownStudies,
} from "../library/mentions.ts";
import { unshownKeysIn } from "../library/retrieval.ts";
import {
  mergeGrounds,
  type NumberGround,
  numberGroundOf,
  ungroundedNumbers,
} from "./numbers_check.ts";
import { type RepeatInputs, repeatsOf } from "./repeats.ts";
import { asciiDigits } from "../ascii_digits.ts";
import type { SafeRanges } from "./safe_ranges.ts";

const sentencesOf = (answer: string) =>
  answer.split(/(?<=[.!?।])\s+|\n+/).map((sentence) => sentence.trim()).filter(Boolean);

// A conjunction starts a new clause only when a verb or a subject follows it ("and don't skip");
// "sprints and intervals" stays one list.
const clauseBreak = new RegExp(
  String
    .raw`[;:()–—।]|,(?!\d)|\s-\s|\s(?:but|however|although|though|yet|while|whereas|then|so)\s|\sand\s+(?=(?:don'?t|do not|never|please|you|you'?ll|you'?re|i|we|it|they|then|also|try|add|do|use|keep|go|start|finish|eat|drop|aim|lose|walk|run|train|follow|include|make|take|set|stay|avoid|skip|should|can|could|will|would|just)\b)`,
  "i",
);

/** The sentence's clauses, in order. */
function clausesOf(sentence: string): string[] {
  return sentence.split(clauseBreak).map((clause) => clause.trim()).filter(Boolean);
}

/** The last `max` words of `before`: the window in which an exemption may govern a match. */
function windowBefore(before: string, max = 6): string {
  return before.split(/\s+/).filter(Boolean).slice(-max).join(" ");
}

/**
 * Whether a judgement or a refusal in `clause` may be trusted for the sentence it sits in: never in
 * a question ("Losing 10 kg in 4 weeks unsafe? Not with my plan.") and never when a later clause
 * turns it round ("..., but you can", "..., so follow my plan", "..., for men it's ideal").
 */
function settledIn(sentence: string, clause: string): boolean {
  if (sentence.includes("?")) return false;
  const at = sentence.indexOf(clause);
  const rest = at === -1 ? sentence : sentence.slice(at + clause.length);
  if (/\b(?:but|yet|so|though|although|however|unless|except)\b/i.test(rest)) return false;
  // "for" turns it round only when it opens a later clause (", for men like you it's ideal"), not
  // inside one (", even for one week").
  return !rest.split(/[,;:()–—]/).some((part) => /^\s*for\b/i.test(part));
}

const globalCopy = (pattern: RegExp) =>
  new RegExp(pattern.source, pattern.flags.includes("g") ? pattern.flags : pattern.flags + "g");

// A word that rules out, declines or warns against the thing that follows it.
const prohibitionWord =
  /\b(?:no|not|never|avoid\w*|skip\w*|stop|instead of|rather than|don'?t|do not|doesn'?t|shouldn'?t|should not|mustn'?t|can'?t|cannot|won'?t|will not|unable|stay away|without|off the table|out of bounds|wait|hold off)\b/i;

/** Whether a prohibition governs a match: it is in the window just before it, in its clause. */
const prohibitedBefore = (before: string) => prohibitionWord.test(windowBefore(before));

// ---- calories_below_floor -------------------------------------------------------------------

// The unit of a calorie figure in English, and in the languages an athlete is likely to be answered
// in (Spanish, Portuguese, French, Italian, German, Scandinavian, Russian, Hindi, Chinese, Japanese,
// Korean, Thai, Arabic). A unit this does not know leaves a figure unseen, so the list errs wide.
// A thousands separator is a comma or, as in Spanish, German and Portuguese, a point: "2.000 kcal" is 2000.
const kcalFigure = new RegExp(
  String
    .raw`(\d{1,2}[,.]\d{3}|\d{3,4})(?:\s*(?:-|–|to)\s*(\d{1,2}[,.]\d{3}|\d{3,4}))?\s*(?:(?:kcal|kkal|calories|cals?)\b|(?:(?:kilo)?calor[ií]as?|(?:kilo)?calorie[ns]?|(?:kilo)?kalori(?:en|er|e|s|a)?|ккал|калори\p{L}*|कैलोरी|किलोकैलोरी|कैलरी|कैल)(?![\p{L}\p{M}])|卡路里|大卡|千卡|キロカロリー|カロリー|칼로리|킬로칼로리|แคลอรี่|سعر(?:ة|ات)|كالوري)`,
  "giu",
);
const intakeVerb =
  /\b(?:eat|eating|consume|consuming|have|having|aim for|aiming for|target|targeting|set (?:it |your calories |your target |your intake )?at|stay at|stay under|settle on|calorie (?:target|intake|goal) of)\s*(?:about |around |roughly |approximately |just |only |closer to |~)?(?:between |from )?$/i;
const reduceVerb =
  /\b(?:drop|dropping|reduce|reducing|cut|cutting|lower|lowering|go|going|move|moving|bring|bringing|come|coming|down|fall|falling|get|getting|set|keep|keeping|limit|limiting|stay|staying)\b.{0,25}\b(?:to|at|around|under|below|between)\s*(?:about |around |roughly |approximately |just |only |~)?(?:between |from )?$/i;
const dailyCue =
  /\b(?:a day|per day|each day|every day|daily|\/day|days?|total|on a (?:normal|training|rest) day)\b/i;
// A daily cue in other languages: "al día", "par jour", "pro Tag", "प्रति दिन", "रोज़". English is
// matched after the figure only, as before; these are matched after it and in the few words before it,
// because Hindi, Turkish and others put the cue first ("रोज़ 800 kcal खाओ", "günde 800 kcal"). A
// figure under the floor with any of them near it is a daily total unless an English exemption
// proves otherwise, which is never true of text in another language: such a reply is flagged for the
// repair. A cue this list does not know leaves a figure with no verb and no cue unflagged (as in
// English), so it errs wide.
const wordCues = [
  // Spanish, Portuguese
  String.raw`(?:al|por|cada|en un|ao|no) d[ií]as?`,
  String.raw`todos (?:los|os) d[ií]as`,
  String.raw`diari(?:o|a|os|as|amente)`,
  String.raw`di[aá]ri(?:o|a|os|as)`,
  // French
  String.raw`(?:par|chaque|tous les) jours?`,
  String.raw`au quotidien`,
  String.raw`quotidien(?:ne)?s?`,
  String.raw`journali(?:er|ère|eres|ères)`,
  // German, Dutch, Scandinavian
  String.raw`(?:pro|am|je|jeden|per|elke|om) (?:tag|dag|dagen)`,
  String.raw`t(?:ä|ae|a)glich(?:e[nrms]?)?`,
  String.raw`dagelijks\p{L}*`,
  String.raw`dagligen`,
  // Italian
  String.raw`(?:al|ogni|tutti i) giorn[oi]`,
  String.raw`(?:giornalier|quotidian)\p{L}*`,
  // Indonesian, Malay, Turkish, Polish, Vietnamese
  String.raw`(?:per|setiap|tiap|se)\s?hari(?:-hari)?`,
  String.raw`harian`,
  String.raw`g(?:ü|u)nde|g(?:ü|u)nl(?:ü|u)k|her g(?:ü|u)n`,
  String.raw`dziennie|codziennie|na dzie(?:ń|n)|dziennych`,
  String.raw`(?:mỗi|một|hàng) ngày`,
  // Russian
  String.raw`в (?:день|сутки)|ежедневн\p{L}*|каждый день|суточн\p{L}*`,
  // Hindi, Bengali, Tamil, Arabic
  String.raw`प्रति\s*दिन|प्रतिदिन|हर\s*दिन|दिन\s*में|दैनिक`,
  String.raw`रो(?:ज\u093c?|\u095b)(?:ाना)?`,
  String.raw`প্রতিদিন|দিনে`,
  String.raw`தினமும்|ஒரு நாளைக்கு`,
  String.raw`(?:في|كل) اليوم|كل يوم|يومي\p{L}*`,
];
// Scripts written without spaces: a cue is found inside a word.
const unspacedCues = String.raw`每天|每日|一天|一日|毎日|日あたり|하루|매일|일일|ต่อวัน|ทุกวัน`;
const foreignDailyCue = new RegExp(
  String
    .raw`(?<![\p{L}\p{M}\p{N}])(?:${
    wordCues.join("|")
  })(?![\p{L}\p{M}\p{N}])|${unspacedCues}|/(?:jour|dia|día|tag|giorno|hari|день)`,
  "iu",
);
// Words that make a figure something other than the day's total: a meal, or energy burned.
const notADailyTotal =
  /\b(?:breakfast|lunch|dinner|snack|snacks|meal|meals|serving|portion|bar|per meal|with each|post-workout|pre-workout|shake|drink|slice|piece|cup|bowl|burn|burned|burning|expend\w*|tdee|maintenance|cardio|treadmill|session|workout|walk|run)\b/i;
const mealAfterFigure =
  /^\s*(?:(?:as|for|at|per|in|with|before|after|a|an|the|each|every|your|pre-workout|post-workout)\s+){0,3}(?:snacks?|meals?|dinners?|lunch|breakfast|servings?|portions?|bars?|shakes?|drinks?|slices?|pieces?|cups?|bowls?)\b/i;
// A limit word directly governing the figure: "don't go below 1,500 kcal", "never under 1,200",
// "don't drop to 1,500 calories". It is read in the figure's own clause, so a negation earlier in
// the sentence ("don't skip meals, drop to 900") does not govern it.
const negator = String.raw`(?:never|not|no|avoid\w*|\w+n't|cannot|mustn't)`;
const limitBeforeFigure = new RegExp(
  String
    .raw`\b${negator}\b[^.;,]{0,30}?\b(?:below|under|beneath|less than|lower than|fewer than)\s*(?:about |around |roughly |approximately |~)?(?:between |from )?$|\b${negator}\s+(?:(?:ever|even|really|to|go|get|let|your|calories|intake|yourself|be|you)\s+){0,3}(?:eat|go|drop|dip|fall|have|consume|reduce|cut|aim|stay|take|plan|limit|restrict|diet|run|lower)\b[^.;,]{0,25}$`,
  "i",
);
// What may follow a limit's figure in its clause: the day, "for you", an "even ..." aside. Anything
// else ("... unless you feel fine", "... if you want") may turn the limit into permission.
const limitTail =
  /^\s*(?:(?:a|per|each|every) day|daily|on a (?:normal|training|rest) day)?\s*(?:for you|even\b[^;:]*|for (?:one|a) week)?\s*[.!]?\s*$/i;
// A judgement of the figure itself: "1,200 kcal a day is too low", "... is below your floor",
// "... isn't safe". A negated warning is approval ("isn't below your floor", "is not too low"), and
// "safe" alone is approval too.
const judgementAfterFigure =
  /^\s*(?:a day |per day |daily |each day )?(?:is|are|would be|will be|was)?\s*(?:far |way |much |dangerously |really |too )*(?:too low|too little|too few|too aggressive|dangerously low|unsafe|not enough|(?:below|under) (?:the|your)(?: [\d,.]+ ?(?:kcal|calories))?(?: calorie)? floor|not recommended|not advisable)\b|^\s*(?:a day |per day |daily |each day )?(?:isn'?t|aren'?t|is not|are not|wouldn'?t be|would not be)\s+(?:safe|healthy|enough|advisable|recommended)(?:\s+for you)?\s*[.!]?\s*$/i;
// Coach's own refusal with the figure as its object, in exactly these shapes: "I can't support 800
// kcal a day", "I won't tell you to eat 700 calories a day", "I can't help you plan 800 kcal a day
// for a week". The whole clause before the figure is the refusal, the figure follows the verb
// directly, and nothing after it but the day, "even ...", "for one week" or "for you". Anything
// else ("I can't recommend 800 kcal a day enough", "I wouldn't tell most people to eat ...") is
// flagged and left to the repair.
const declineBeforeFigure =
  /^\s*(?:no,?\s+)?i\s+(?:can'?t|cannot|won'?t|will not|wouldn'?t|would not|don'?t|do not)\s+(?:(?:support|recommend|advise|endorse|approve|prescribe|set|plan)\s+(?:you to eat\s+|eating\s+|(?:going|dropping|cutting)(?: down)? to\s+|a plan of\s+)?|tell you to eat\s+|help (?:you )?(?:eat|plan)\s+)$/i;
const declineAfterFigure =
  /^\s*(?:a day|per day|daily)?\s*(?:even\b[^;:]*|for (?:one|a) week|for you)?\s*[.!]?\s*$/i;
/**
 * Whether nothing follows the clause in its sentence but an "even ..." aside: a refusal followed by
 * anything else ("; set it yourself in Progress", ", but you can") is not trusted.
 */
function endsTheSentence(sentence: string, clause: string): boolean {
  if (sentence.includes("?")) return false;
  const at = sentence.indexOf(clause);
  const rest = at === -1 ? sentence : sentence.slice(at + clause.length);
  return /^\s*(?:,\s*even\b[^,;:]*)?\s*[.!]?\s*$/i.test(rest);
}
const declineVeto = /\b(?:enough|lightly|unless|most|every|other people|others|anyone else)\b/i;

const changeByAmount =
  /\b(?:cut|reduce|trim|shave|remove|subtract|save|drop|lower|add|increase|extra|another|an additional)\s+(?:about |around |roughly |another |an extra |an additional |just |only |~)?$/i;
// The athlete's own intake, said right before the figure ("you've been eating 1,300 kcal a day").
const describesIntake =
  /\b(?:you'?ve been|you have been|you'?re (?:eating|having|on|at)|you are (?:eating|having|on|at)|you were|you ate|you averaged|you logged|your (?:intake|average|logged|current|usual|typical)|averag\w+|logged|so far|last (?:week|month)|yesterday|currently|recently)\b/i;

const kcalNumber = (raw: string) => Number(raw.replace(/[,.]/g, ""));

function belowCalorieFloor(sentence: string, floor: number): boolean {
  for (const clause of clausesOf(sentence)) {
    for (const match of clause.matchAll(kcalFigure)) {
      const low = Math.min(
        kcalNumber(match[1]),
        match[2] === undefined ? Infinity : kcalNumber(match[2]),
      );
      if (low >= floor) continue;
      const before = clause.slice(0, match.index);
      const after = clause.slice(match.index + match[0].length);
      if (limitBeforeFigure.test(before) && limitTail.test(after) && settledIn(sentence, clause)) {
        continue;
      }
      if (judgementAfterFigure.test(after) && settledIn(sentence, clause)) continue;
      if (
        declineBeforeFigure.test(before) && declineAfterFigure.test(after) &&
        !declineVeto.test(sentence) && endsTheSentence(sentence, clause)
      ) continue;
      if (mealAfterFigure.test(after) || describesIntake.test(windowBefore(before))) continue;
      // A change by an amount ("cut 300 kcal from your day"), not a target.
      if (changeByAmount.test(before)) continue;
      const reduce = reduceVerb.exec(before);
      if (reduce) {
        if (!notADailyTotal.test(before.slice(reduce.index))) return true;
        continue;
      }
      // After an intake verb a figure under the floor is advice, with or without a day word.
      const intake = intakeVerb.exec(before);
      if (intake) {
        if (!notADailyTotal.test(before.slice(intake.index))) return true;
        continue;
      }
      // A daily figure under the floor, said with no limit, judgement or description around it.
      if (dailyCue.test(after) && !notADailyTotal.test(before.slice(-20))) return true;
      // The same in another language: its cue after the figure or in the few words before it.
      if (
        (foreignDailyCue.test(after) || foreignDailyCue.test(windowBefore(before))) &&
        !notADailyTotal.test(before.slice(-20))
      ) return true;
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
// The athlete's own past or present pace, said right before the figure ("you've been losing").
const describesAthlete =
  /\b(?:you(?:'re| are| were| have| lost|'ve)|your (?:pace|rate|loss|trend|average|current)|over the (?:last|past)|so far|currently|recently|has been|have been)\b/i;
// A judgement of the figure itself that ends its clause: "losing more than 1 kg a week is too
// fast", "losing 10 kg in 4 weeks isn't safe". A negated warning is approval ("is not dangerous",
// "isn't unsafe for you"), and anything after the judgement ("... for most people", "... without
// me") leaves the figure flagged.
const lossJudgementAfter =
  /^\s*(?:(?:is|are|would be|will be)\s+(?:far |way |much )?(?:too fast|too much|too aggressive|too quick|unsafe|dangerous|risky|not safe|not recommended|not sustainable|not realistic|not healthy)|(?:isn'?t|aren'?t|wouldn'?t be|would not be|won'?t be|will not be)\s+(?:safe|realistic|healthy|sustainable|advisable))\s*[.!]?\s*$/i;

function kilograms(amount: number, unit: string, weightKg: number | null): number | null {
  const lowered = unit.toLowerCase();
  if (lowered.startsWith("lb") || lowered.startsWith("pound")) return amount / 2.20462;
  if (lowered === "%" || lowered === "percent") {
    return weightKg === null ? null : amount * weightKg / 100;
  }
  return amount;
}

function lossAboveCeiling(sentence: string, ranges: SafeRanges): boolean {
  const ceilingKg = ranges.weeklyLossCeilingKg;
  const slack = 0.05;
  for (const clause of clausesOf(sentence)) {
    // A total over a number of weeks is a rate; it is checked before anything is exempted.
    for (const match of clause.matchAll(lossOverWeeks)) {
      const before = windowBefore(clause.slice(0, match.index));
      if (prohibitionWord.test(before) || describesAthlete.test(before)) continue;
      // A judgement of the pace itself: "Losing 10 kg in 4 weeks isn't safe".
      if (
        lossJudgementAfter.test(clause.slice(match.index + match[0].length)) &&
        settledIn(sentence, clause)
      ) continue;
      const kg = kilograms(Number(match[1]), match[2] ?? "kg", ranges.weightKg);
      const weeks = Number(match[3]);
      if (kg !== null && weeks > 0 && ceilingKg !== null && kg / weeks > ceilingKg + slack) {
        return true;
      }
    }
    for (const match of clause.matchAll(weeklyLoss)) {
      const before = clause.slice(0, match.index);
      const after = clause.slice(match.index + match[0].length);
      const near = windowBefore(before);
      if (prohibitionWord.test(near) || describesAthlete.test(near)) continue;
      if (lossJudgementAfter.test(after) && settledIn(sentence, clause)) continue;
      if (!lossCue.test(before)) continue;
      const amount = Math.max(Number(match[1]), match[2] === undefined ? 0 : Number(match[2]));
      const unit = match[3].toLowerCase();
      if (unit === "%" || unit === "percent") {
        if (amount > ranges.weeklyLossCeilingPct + slack) return true;
        continue;
      }
      const kg = kilograms(amount, unit, ranges.weightKg);
      if (kg !== null && ceilingKg !== null && kg > ceilingKg + slack) return true;
    }
  }
  return false;
}

// ---- effort_above_screening_cap and training_advice_on_pain_day -----------------------------

const vigorous =
  /\b(?:all[- ]out|max(?:imal|imum)?[- ]effort|maximal|to failure|until failure|go (?:hard|heavy)|push (?:harder|hard|through)|push to your limit|1[- ]?rm|one[- ]rep max|heavy (?:single|triple|double)s?|sprints?|sprinting|hiit|high[- ]intensity|intervals?|vigorous|rpe ?(?:9|10)|(?:0|zero|1|one) (?:reps? in reserve|rir)|failure|test your max|max out|burnout set)\b/gi;

const countWords = "(?:\\d+|one|two|three|four|five|six|seven|a couple of|a few|several)";
// Any prescription of training: sets and reps, loads on a lift, minutes of exercise, a
// programme, a weekly frequency, steps, or exercises to do.
const prescriptionPatterns: readonly RegExp[] = [
  /\b\d+\s*(?:x|×)\s*\d+\b/i,
  /\b\d+(?:\s*(?:-|–|to)\s*\d+)?\s*(?:sets?|reps?|repetitions?|rounds?)\b/i,
  /\b(?:rpe|rir)\s*\d|\b\d+\s*rir\b|\breps? in reserve\b/i,
  /\b\d+(?:\.\d+)?\s*(?:kg|lbs?|pounds?)\b.{0,25}\b(?:squat|deadlift|bench|press|row|curl|lift|lunge|carry|pull)/i,
  /\b(?:squat|deadlift|bench|press|row|curl|lunge)\w*\b.{0,25}\b\d+(?:\.\d+)?\s*(?:kg|lbs?|pounds?)\b/i,
  /\b\d+(?:[,.]\d+)?(?:\s*(?:-|–|to)\s*\d+(?:[,.]\d+)?)?\s*(?:minutes?|mins?|hours?)\b.{0,30}\b(?:cardio|run|running|jog\w*|walk\w*|cycl\w+|swim\w*|rowing|workout|session|training|exercise|elliptical|bike|hiit)\b/i,
  /\b(?:cardio|run|running|jog\w*|walk\w*|cycl\w+|swim\w*|workout|session|training|exercise|bike)\b.{0,30}\b\d+(?:[,.]\d+)?(?:\s*(?:-|–|to)\s*\d+)?\s*(?:minutes?|mins?|hours?)\b/i,
  /\b(?:aim|target|go for|get|hit|reach|do|walk)\b.{0,15}\b\d{1,3}(?:,\d{3})?\s*steps\b/i,
  new RegExp(
    String
      .raw`\b${countWords}(?:[- ]day)?\s+(?:split|programme|program|routine|circuit)\b|\b(?:push|pull)(?:,|\s+and)?\s*(?:pull|legs?)\b|\b(?:push|pull|legs|upper|lower|full[- ]body)\s+(?:day|routine|split|programme|program|workout)s?\b|\b(?:full[- ]body|upper[- ]lower|upper/lower)\b`,
    "i",
  ),
  new RegExp(
    String
      .raw`\b(?:once|twice|${countWords}\s*(?:x|times))\s*(?:a|per|each|every)?\s*(?:a |per |each |every )?week\b.{0,30}\b(?:train\w*|workouts?|lift\w*|cardio|sessions?|exercise)\b|\b(?:train\w*|workouts?|lift\w*|cardio|sessions?|exercise)\b.{0,30}\b(?:once|twice|${countWords}\s*(?:x|times))\s*(?:a|per|each|every)\s*week\b|\btrain\s+${countWords}\s+times\b`,
    "i",
  ),
  /\b(?:do|perform|try|add|start with|begin with|finish with|superset|include)\b.{0,40}\b(?:squats?|deadlifts?|bench|presses|press|rows?|curls?|pull-?ups?|push-?ups?|lunges?|planks?|burpees?|hiit|intervals?|sprints?|circuits?|cardio|stretches)\b/i,
].map(globalCopy);

// An effort word that is the subject of a clause ruling it out, and nothing else: "high-intensity
// intervals are off the table for now", "sprints are not allowed until you are cleared". Only
// another effort or training noun, or "and/or <word>", may sit between the match and is/are; after
// the phrase only "for now", "today", "this week", "until ..." or the clause end. Never in a clause
// that gives an order before the match ("Go all-out ... as lifting is not allowed"), in a question,
// or with a later clause that turns it round.
const ruledOutAfter =
  /^(?:\s+(?:and|or)\s+[\w-]+|\s+(?:intervals?|sprints?|sessions?|work|training|efforts?|sets?|cardio|conditioning))?\s+(?:is|are)\s+(?:still\s+)?(?:off the table|ruled out|out of bounds|not (?:allowed|cleared|advised|recommended|safe))(?:\s+(?:for now|today|this week|until\b[^;:]*))?\s*[.!]?\s*$/i;
const orderBefore = /\b(?:do|go|push|add|try|max|finish|start|hit|smash)\b/i;

/** Whether a clause holds a match of the patterns that no prohibition in its window governs. */
function hasUngovernedMatch(
  clause: string,
  patterns: readonly RegExp[],
  ruledOut?: Readonly<{ sentence: string }>,
): boolean {
  return patterns.some((pattern) =>
    [...clause.matchAll(pattern)].some((match) => {
      const before = clause.slice(0, match.index);
      if (prohibitedBefore(before)) return false;
      const excused = ruledOut !== undefined && !orderBefore.test(before) &&
        ruledOutAfter.test(clause.slice(match.index + match[0].length)) &&
        settledIn(ruledOut.sentence, clause);
      return !excused;
    })
  );
}

/** Any training prescription not ruled out right before it, in its own clause. */
function prescribesTraining(sentence: string): boolean {
  return clausesOf(sentence).some((clause) =>
    hasUngovernedMatch(clause, [...prescriptionPatterns, vigorous])
  );
}

/**
 * Whether the sentence breaks the health check's cap. moderate_until_cleared (and an unreadable
 * health check, which is treated the same) rules out vigorous effort, however it is worded
 * ("keep HIIT moderate" still advises HIIT); see_professional rules out every training
 * prescription.
 */
function aboveScreeningCap(sentence: string, screening: ScreeningState): boolean {
  if (screening === "cleared") return false;
  if (screening === "see_professional") return prescribesTraining(sentence);
  return clausesOf(sentence).some((clause) => hasUngovernedMatch(clause, [vigorous], { sentence }));
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
  // Not a condition: "until that's done", "once it's done" is about the athlete's step.
  /(?<!\b(?:until|once|when|after|before|unless|till|if)\s+)\b(?:consider it|it'?s|it is|that'?s|that is) done\b/i,
];

/** A claim in a clause. Only a clause that is itself the question is exempt ("Want me to ...?"). */
function claimsAnAction(sentence: string): boolean {
  const clauses = clausesOf(sentence);
  const asks = sentence.trimEnd().endsWith("?");
  return clauses.some((clause, index) =>
    !(asks && index === clauses.length - 1) &&
    claimedPatterns.some((pattern) => pattern.test(clause))
  );
}

// ---- the combined check ---------------------------------------------------------------------

export type ReplyCheckInputs = Readonly<{
  ranges: SafeRanges;
  screening: ScreeningState;
  /**
   * What Coach was given: the numbers a reply may state. It holds the athlete's records and
   * calculations, the other contributors and the coaching principles digest, but not the library.
   */
  ground: NumberGround;
  /**
   * The numbers a sentence that states the athlete's own target or prescription may use: the
   * athlete's data and Tracend's calculations only, never the digest or the library. Default:
   * `ground`.
   */
  athleteGround?: NumberGround;
  /**
   * The text shown for each library source this turn, by source id. A figure only a source holds is
   * accepted when the reply cites that source in its evidence, and never in a sentence about the
   * athlete's own target.
   */
  librarySources?: Readonly<Record<string, string>>;
  /** The label shown for each library source, by source id (its title and year). */
  libraryLabels?: Readonly<Record<string, string>>;
  /**
   * What the athlete wrote in this conversation. A study the athlete named themselves is theirs to
   * ask about, so the reply naming it is not a citation of a source Coach was not shown.
   */
  athleteText?: readonly string[];
  /** The previous reply and the turn's need for referral wording; none without a previous reply. */
  repetition?: RepeatInputs;
  /** The goal phase check (training/goal_phase/guard.ts): runs first and keeps its own rules. */
  weightClaim: (answer: string) => CoachChatValidationRule | null;
}>;

// ---- the athlete's own target ------------------------------------------------------------

// A sentence that tells the athlete their own number or what to do: "your protein target is ...",
// "you should eat ...", "aim for ...", "cut 300 kcal a day". The numbers in it are Tracend's to
// give, from the athlete's data; a guideline figure from the library or the digest is general
// guidance and belongs in a sentence that says whose guidance it is.
const ownTargetPatterns: readonly RegExp[] = [
  /\byour (?:\w+ ){0,2}(?:target|goal|number|allowance|intake|requirement|needs?)\b/i,
  /\byou (?:should|need to|must|ought to|have to|'ll need to|will need to) (?:eat|aim|take|have|get|consume|drink|cut|lose|gain|do|train|lift|sleep|add|reduce|hit|reach)\b/i,
  /\b(?:aim for|aim to|aiming for|target of|go for|shoot for|stay (?:at|under|around))\b/i,
  /\b(?:cut|reduce|drop|eat|add|take|consume|drink)\b(?:[^.!?\n]|\.(?=\d)){0,40}\b(?:a|per|each|every) (?:day|week|meal)\b/i,
];

function statesOwnTarget(sentence: string): boolean {
  return ownTargetPatterns.some((pattern) => pattern.test(sentence));
}

function listIn(figures: readonly string[]): string {
  return figures.slice(0, 6).join(", ");
}

/** The sources shown this turn, as the mention matcher reads them (label, and text for the author). */
function shownOf(inputs: ReplyCheckInputs): ShownSources {
  return Object.fromEntries(
    Object.entries(inputs.librarySources ?? {}).map((
      [id, text],
    ) => [id, { label: inputs.libraryLabels?.[id] ?? id, text }]),
  );
}

/** The grounds of the library sources a reply cites, by id, computed once. */
function libraryGrounder(inputs: ReplyCheckInputs): (ids: readonly string[]) => NumberGround[] {
  const grounds = new Map<string, NumberGround>();
  return (ids) =>
    ids.flatMap((id) => {
      const text = inputs.librarySources?.[id];
      if (text === undefined) return [];
      if (!grounds.has(id)) grounds.set(id, numberGroundOf([text]));
      return [grounds.get(id)!];
    });
}

/**
 * Studies and sources a text names that Coach was not shown this turn. A study the athlete named
 * in this conversation is theirs to ask about and is left out, but only the same reference: the
 * athlete's own message has to carry the same surname and year ("What does Kreider 2017 say?"), or
 * the same institution's initials beside a kind of document ("the NIH fact sheet"). A surname alone
 * ("I train on a Smith machine") names no study.
 */
function unshownNames(inputs: ReplyCheckInputs, text: string, shown: ShownSources): string[] {
  const athlete = studyMentions((inputs.athleteText ?? []).join("\n"));
  const named = (mention: StudyMention) =>
    athlete.some((theirs) =>
      (mention.initials === true) === (theirs.initials === true) &&
      mention.year === theirs.year &&
      mention.authors.some((author) => theirs.authors.includes(author))
    );
  const names = unshownStudies(text, shown).filter((mention) => !named(mention)).map((mention) =>
    [...mention.authors, mention.year ?? ""].join(" ").trim()
  );
  return [...names, ...unshownKeysIn(text, new Set(Object.keys(shown)))];
}

/**
 * The check Coach chat applies to every answer: the goal phase rules, the safe-range and
 * screening rules, no claimed actions, the numbers check, the citations and the repeats. It
 * reports the first rule broken and every other one, so a single repair can fix them together.
 */
export function coachReplyCheck(inputs: ReplyCheckInputs): CoachChatAnswerCheck {
  const libraryGround = libraryGrounder(inputs);
  const shown = shownOf(inputs);
  return (written, citedLibrarySources = [], writtenReply): CoachChatAnswerBreak | null => {
    // Every rule reads digits of any script as the ASCII digits they stand for ("४५ kg").
    const answer = asciiDigits(written);
    const replyText = writtenReply === undefined ? undefined : asciiDigits(writtenReply);
    const broken: CoachChatValidationRule[] = [];
    const sentences = sentencesOf(answer);
    // The sentences that broke a rule, in reply order: the repair names them, because a rule's
    // hint alone does not say which sentence it read as advice (a refusal that restates the figure,
    // a follow-up chip in the athlete's voice), and a repair that cannot find it fails again.
    const flagged = new Set<string>();
    const flag = (rule: CoachChatValidationRule, test: (sentence: string) => boolean) => {
      const hits = sentences.filter(test);
      if (hits.length === 0) return;
      if (!broken.includes(rule)) broken.push(rule);
      for (const sentence of hits) flagged.add(sentence);
    };
    const weight = inputs.weightClaim(answer);
    if (weight) {
      broken.push(weight);
      for (const sentence of sentences) if (inputs.weightClaim(sentence)) flagged.add(sentence);
    }
    flag("calories_below_floor", (s) => belowCalorieFloor(s, inputs.ranges.calorieFloorKcal));
    flag("loss_rate_above_ceiling", (s) => lossAboveCeiling(s, inputs.ranges));
    flag("effort_above_screening_cap", (s) => aboveScreeningCap(s, inputs.screening));
    flag(
      "training_advice_on_pain_day",
      (s) => trainingOnPainDay(s, inputs.ranges.painEscalated),
    );
    flag("claimed_action", claimsAnAction);
    // A sentence about the athlete's own target or prescription takes its numbers from the
    // athlete's data alone; any other sentence may also use the digest and a library source the
    // reply cites.
    const otherGround = mergeGrounds(inputs.ground, ...libraryGround(citedLibrarySources));
    const ownGround = inputs.athleteGround ?? inputs.ground;
    const own = sentences.filter(statesOwnTarget);
    const other = sentences.filter((sentence) => !statesOwnTarget(sentence));
    const ungrounded = [
      ...ungroundedNumbers(other.join("\n"), otherGround),
      ...ungroundedNumbers(own.join("\n"), ownGround),
    ];
    if (ungrounded.length > 0) {
      broken.push("numbers_not_grounded");
      for (const sentence of sentences) {
        const ground = statesOwnTarget(sentence) ? ownGround : otherGround;
        if (ungroundedNumbers(sentence, ground).length > 0) flagged.add(sentence);
      }
    }
    if (unshownNames(inputs, answer, shown).length > 0) {
      broken.push("citation_not_retrieved");
      for (const sentence of sentences) {
        if (unshownNames(inputs, sentence, shown).length > 0) flagged.add(sentence);
      }
    }
    if (inputs.repetition) {
      const repeats = repeatsOf(replyText ?? answer, inputs.repetition);
      if (repeats.closing !== null || repeats.sentences.length > 0) {
        broken.push("repeats_previous_turn");
      }
    }
    if (broken.length === 0) return null;
    const quoted = [...flagged].slice(0, maxFlaggedSentences).map((sentence) =>
      sentence.length > maxFlaggedChars ? `${sentence.slice(0, maxFlaggedChars)}...` : sentence
    );
    return {
      rule: broken[0],
      rules: broken,
      ...(ungrounded.length > 0
        ? {
          detail: listIn(ungrounded),
          ...(broken[0] === "numbers_not_grounded" ? { count: ungrounded.length } : {}),
        }
        : {}),
      ...(quoted.length > 0 ? { sentences: quoted } : {}),
    };
  };
}

/** At most this many flagged sentences go to the repair, each cut to this many characters. */
const maxFlaggedSentences = 6;
const maxFlaggedChars = 300;

// ---- salvage: a reply that fails only these rules is cut, not thrown away ----------------------

/** The rules a cut can fix: each is a fault of particular sentences, not of the whole reply. */
const cuttableRules: readonly CoachChatValidationRule[] = [
  "numbers_not_grounded",
  "citation_not_retrieved",
  "repeats_previous_turn",
];

/** Whether every rule broken is one a cut can fix. */
export function isCuttable(rules: readonly CoachChatValidationRule[]): boolean {
  return rules.length > 0 && rules.every((rule) => cuttableRules.includes(rule));
}

/** What a cut removed or changed; `label_rebuilt` is a library label written again from the source. */
export type CutName =
  | "numbers_stripped"
  | "study_stripped"
  | "closing_question_stripped"
  | "repeat_stripped"
  | "label_rebuilt";

export type CutReply = Readonly<{
  answer: Record<string, unknown>;
  /** Finite names of what was cut, for the turn trace. */
  cuts: readonly CutName[];
}>;

const noticeFor = {
  numbers_stripped: "Left out lines with figures that are not in your data.",
  study_stripped: "Left out a line that named a source I was not shown.",
} as const;

// Sentence breaks, and the list markers that must stay with their sentence.
const unitBreak = /(\n+|(?<=[.!?])(?<!(?:^|\n)[ \t]*\d{1,2}[.)])[ \t]+)/;
const unitMarker = /^\s*(?:[-*•]|\d+[.)])\s+/;

type Removed = Readonly<{ unit: string; reasons: readonly CutName[] }>;

/**
 * Removes the units a test flags, with the break after each; returns the rest and what went. A
 * unit that introduces a list (it ends in ":" or list items follow it) takes its whole list with
 * it when it is cut: a lead-in cut alone would leave a bare list whose meaning it set ("skip all of
 * these:" and then the exercises).
 */
function cutUnits(
  text: string,
  flagged: (unit: string) => readonly CutName[],
): Readonly<{ text: string; units: number; removed: readonly Removed[] }> {
  const parts = text.split(unitBreak);
  const out: string[] = [];
  const removed: Removed[] = [];
  const isItem = (index: number) => unitMarker.test(parts[index] ?? "");
  const nextUnit = (index: number) => {
    for (let j = index + 2; j < parts.length; j += 2) if (parts[j].trim() !== "") return j;
    return -1;
  };
  let units = 0;
  for (let i = 0; i < parts.length; i += 2) {
    const unit = parts[i];
    if (unit.trim() === "") {
      out.push(unit, parts[i + 1] ?? "");
      continue;
    }
    units += 1;
    const reasons = flagged(unit.replace(unitMarker, "").trim());
    if (reasons.length === 0) {
      out.push(unit, parts[i + 1] ?? "");
      continue;
    }
    removed.push({ unit, reasons });
    const next = nextUnit(i);
    if (!isItem(i) && (/:\s*$/.test(unit.trim()) || (next !== -1 && isItem(next)))) {
      // Its list goes too: every item up to the first line that is not one.
      for (let j = next; j !== -1 && isItem(j); j = nextUnit(j)) {
        units += 1;
        removed.push({ unit: parts[j], reasons });
        parts[j] = "";
        parts[j + 1] = "";
      }
    }
  }
  return { text: out.join("").replace(/\n{3,}/g, "\n\n").trim(), units, removed };
}

// What makes a sentence more than a fact: a prohibition, a limit, a symptom or a stop rule, and the
// words that put a condition on, or a caveat after, a recommendation. Cutting such a sentence can
// turn "skip these", "only if it doesn't hurt" or "stop at 17 days" into a plain recommendation, so
// a cut that would remove one gives up and the turn ends in the data summary.
// A prohibition is one only in directive form: "don't", "do not", "never", "avoid", "skip", "stop",
// "no" with an activity ("no squatting"). A plain "no" or "not" in a fact ("no small feat", "not
// far off your best") is not one.
const directiveProhibition =
  /\b(?:don'?t|do not|never|avoid\w*|skip\w*|stop\w*|shouldn'?t|should not|mustn'?t|must not|can'?t|cannot|won'?t|will not|unable|stay away|off the table|out of bounds|wait|hold off|instead of|rather than|not (?:recommended|advised|safe|allowed))\b|\bno\s+(?:\w+ing|squats?|lunges?|jumps?|sprints?|runs?|intervals?|lifting|training|exercise|cardio|workouts?|heavy)\b/i;
// A comparative or limit word is a limit only in a directive: "keep it below", "stay under",
// "hold the load at or beneath", "cap it", "go no lower", "aim for at most". In a fact it is a
// comparison: "3 bpm lower than last month", "a max of 163 bpm", "within 137 kcal of your target".
const directiveLimit =
  /\b(?:keep|stay|stick|hold|go|aim|set|limit|remain|cap|top out)\b[^.!?]{0,30}\b(?:below|under|beneath|lower|less|fewer|within|max\w*|over|above|beyond|past)\b|\bor (?:lower|less|fewer|under|below)\b|\bat or (?:below|under|beneath)\b/i;
const cautionWord = new RegExp(
  `${directiveProhibition.source}|${directiveLimit.source}|\\b(?:limit\\w*|careful\\w*|caution\\w*|pain\\w*|hurt\\w*|pinch\\w*|sharp|swell\\w*|dizz\\w*|numb\\w*|injur\\w*|sore\\w*|steer clear|cap(?:s|ped|ping)?|ceiling|ease off|back off|ach(?:e|es|ed|ing)|flare\\w*|top(?:s|ped)? out|no (?:more|higher|longer)|at most)\\b`,
  "i",
);
const conditionWord =
  /\b(?:until|unless|except|only|provided|as long as|if|but|however|although|though|no more than|no less than|instead|otherwise)\b/i;

/** Whether removing a unit could change what is left from advice into something else. */
function changesMeaning(removed: Removed): boolean {
  // A repeated closing question asks something; it sets no rule for what comes before it.
  if (removed.reasons.includes("closing_question_stripped")) return false;
  if (cautionWord.test(removed.unit)) return true;
  // A repeated sentence is only a repeat; a figure or a source is a fault in a claim, which a
  // condition or a caveat may be attached to.
  return removed.reasons.some((reason) => reason !== "repeat_stripped") &&
    conditionWord.test(removed.unit);
}

/** A line left alone before a list that was cut away ("Here is the plan:"). */
function withoutDanglingLead(text: string): string {
  const lines = text.split("\n");
  while (lines.length > 0 && /:\s*$/.test(lines[lines.length - 1])) lines.pop();
  return lines.join("\n").trim();
}

/**
 * Cuts the sentences that break the cuttable rules out of a reply that failed only those rules,
 * deterministically: the sentences with a figure that is not in the athlete's data, those that
 * name a source Coach was not shown, and the closing question or sentences that repeat the
 * previous reply. The same cut runs on the follow-up chips, the notes on missing data and the
 * reasoning steps. Nothing is rewritten and nothing is added except a note in `missing_data`
 * saying a line was left out. Null when too little is left to be an answer (under half the
 * sentences, or under 40 characters): the reply then ends in the data summary as before. The
 * caller must still run the full check on the result.
 */
export function cutReply(
  inputs: ReplyCheckInputs,
  candidate: Record<string, unknown>,
  rules: readonly CoachChatValidationRule[],
): CutReply | null {
  if (!isCuttable(rules) || typeof candidate.answer !== "string") return null;
  const original = candidate.answer;
  const libraryGround = libraryGrounder(inputs);
  const shown = shownOf(inputs);
  // A library citation is labelled by the server from the retrieved title and year, never by the
  // model, so its label is rebuilt before anything is read: a figure or an unshown study in the
  // model's wording must not make the cut give up, and the citation stays.
  let relabelled = false;
  const evidence =
    (Array.isArray(candidate.evidence) ? candidate.evidence as Record<string, unknown>[] : []).map(
      (item) => {
        const label = item.source === "library" ? shown[String(item.code)]?.label : undefined;
        if (label === undefined || label === item.label) return item;
        relabelled = true;
        return { ...item, label };
      },
    );
  candidate = { ...candidate, evidence };
  const declared = evidence.filter((item) => item.source === "library").map((item) =>
    item.code as string
  );
  const cited = [
    ...new Set([
      ...declared,
      ...namedShownSources(visibleText(candidate, false).join("\n"), shown),
    ]),
  ];
  const merged = mergeGrounds(inputs.ground, ...libraryGround(cited));
  const repeats = rules.includes("repeats_previous_turn") && inputs.repetition
    ? repeatsOf(original, inputs.repetition)
    : null;
  const flaggedBy = (unit: string, answerText: boolean) => {
    const reasons: CutName[] = [];
    if (rules.includes("numbers_not_grounded")) {
      const ground = statesOwnTarget(unit) ? inputs.athleteGround ?? inputs.ground : merged;
      if (ungroundedNumbers(unit, ground).length > 0) reasons.push("numbers_stripped");
    }
    if (rules.includes("citation_not_retrieved") && unshownNames(inputs, unit, shown).length > 0) {
      reasons.push("study_stripped");
    }
    if (answerText && repeats) {
      if (unit === repeats.closing) reasons.push("closing_question_stripped");
      else if (repeats.sentences.includes(unit)) reasons.push("repeat_stripped");
    }
    return reasons;
  };

  const cuts = new Set<CutName>();
  const mark = (unit: string, answerText: boolean) => {
    const reasons = flaggedBy(unit, answerText);
    for (const reason of reasons) cuts.add(reason);
    return reasons.length > 0;
  };
  const main = cutUnits(original, (unit) => {
    const reasons = flaggedBy(unit, true);
    for (const reason of reasons) cuts.add(reason);
    return reasons;
  });
  if (main.removed.some((removed) => changesMeaning(removed))) return null;
  const answerText = withoutDanglingLead(main.text);
  const keptUnits = answerText === "" ? 0 : cutUnits(answerText, () => []).units;
  if (answerText.length < 40 || keptUnits * 2 < main.units) return null;

  const strings = (value: unknown) =>
    Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
  const keepString = (text: string) => !mark(text, false);
  const reasoning = (Array.isArray(candidate.reasoning_chain) ? candidate.reasoning_chain : [])
    .filter((item) => {
      const step = item as Record<string, unknown>;
      return keepString(`${step.step ?? ""} ${step.value ?? ""}`.trim());
    });
  const missingData = strings(candidate.missing_data).filter(keepString);
  const notes = [...cuts].flatMap((cut) =>
    cut === "numbers_stripped" || cut === "study_stripped" ? [noticeFor[cut]] : []
  );
  const cut: Record<string, unknown> = {
    ...candidate,
    answer: answerText,
    suggested_follow_ups: strings(candidate.suggested_follow_ups).filter(keepString),
    // The notices take their place first: the contract allows a fixed number of notes, so the
    // last of the model's own are the ones to go.
    missing_data: [
      ...missingData.slice(
        0,
        Math.max(0, coachChatAnswerLimits.missingDataMaxItems - notes.length),
      ),
      ...notes,
    ],
    evidence: evidence.filter((item) =>
      item.source === "library" || keepString(String(item.label ?? ""))
    ),
  };
  if (Array.isArray(candidate.reasoning_chain)) cut.reasoning_chain = reasoning;
  if (relabelled) cuts.add("label_rebuilt");
  return cuts.size === 0 ? null : { answer: cut, cuts: [...cuts] };
}
