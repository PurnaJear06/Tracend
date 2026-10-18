// The weights in a sentence of Coach's reply, and which of them are the athlete's body weight.
// A "kg" figure is not always a body weight: "overhead press 55 kg x 6" is a load. The goal phase
// check (guard.ts) reads only body weights, and it is a safety check, so the rule is strict and
// fails closed. A figure is a LOAD only when ALL of these hold:
//   (a) an exercise name or catalog slug is within two words before the figure, in the same
//       sentence or list item;
//   (b) real rep or set notation is directly after it: "x 6" (not followed by a time unit: "x 2
//       weeks" is a duration), "for 8" (then the end, reps, sets or punctuation), "3x5", "sets of
//       5", or "N kg per side" (with no scale or body word in the sentence);
//   (c) nothing before it in the sentence is about the person's weight: weigh, scale, body weight,
//       BMI, height, "your weight", "puts you at", or "you'll be / reach / hit / get to / end up /
//       sit / land".
// Every other figure is a BODY WEIGHT. There is no exercise-word-alone branch and no bar-or-plate
// branch, nothing carries from one sentence to the next, the question carries nothing, and a
// progression verb is never a load cue. A load Coach writes without its exercise and reps
// ("you'll move up to 45 kg") is repaired into "bench 45 kg x 6".
// Figures written without the unit are read too: in a sentence about the person's weight, a bare
// number from 30 to 300 straight after "you'll be at" or "weigh" ("You'll be at 50 by March"),
// and a written number with kilos or kg ("fifty kilos").
import { exerciseCatalogV1 } from "../../onboarding/catalog.ts";

const kgWord = "(?:kg|kgs|kilos?|kilograms?)";
const lbWord = "(?:lbs?|pounds?)";
const weightPattern = new RegExp(
  `(\\d{2,3}(?:[.,]\\d+)?)(?:\\s*(?:-|–|to)\\s*(\\d{2,3}(?:[.,]\\d+)?))?\\s*(${kgWord}|${lbWord})\\b`,
  "gi",
);

export type WeightFigure = Readonly<{
  /** The figures written (a range gives two), in kg. */
  kgs: readonly number[];
  /** Where the figure starts in the sentence, and the text before it. */
  index: number;
  before: string;
  /** Whether the surroundings say this is the athlete's body weight. */
  bodyWeight: boolean;
}>;

function toKg(amount: number, unit: string): number {
  return /^(?:lb|pound)/i.test(unit) ? amount / 2.20462 : amount;
}

type Word = Readonly<{ text: string; start: number; end: number }>;

function wordsOf(sentence: string): Word[] {
  const lower = sentence.toLowerCase().replaceAll("’", "'");
  return [...lower.matchAll(/[a-z0-9]+(?:'[a-z]+)?/g)].map((match) => ({
    text: match[0],
    start: match.index,
    end: match.index + match[0].length,
  }));
}

// ---- load cues ---------------------------------------------------------------------------

// Words of the catalog's exercise names and slugs that are also ordinary English or a body part:
// they name no lift on their own.
const notALiftWord = new Set([
  "apart",
  "bar",
  "barbell",
  "barbells",
  "dumbbell",
  "dumbbells",
  "kettlebell",
  "kettlebells",
  "plate",
  "plates",
  "rack",
  "arm",
  "assisted",
  "back",
  "bird",
  "bodyweight",
  "bug",
  "calf",
  "chest",
  "chin",
  "crunch",
  "dead",
  "deck",
  "dip",
  "dog",
  "doorway",
  "elevated",
  "face",
  "floor",
  "front",
  "hands",
  "hanging",
  "hinge",
  "hip",
  "knee",
  "lat",
  "lateral",
  "leg",
  "lying",
  "machine",
  "one",
  "pike",
  "pull",
  "push",
  "raise",
  "rear",
  "reverse",
  "seated",
  "shoulder",
  "single",
  "split",
  "standing",
  "step",
  "supported",
  "swing",
  "through",
  "towel",
  "up",
]);

const catalogLiftWords = exerciseCatalogV1.flatMap((exercise) =>
  `${exercise.name} ${exercise.slug}`.toLowerCase().split(/[^a-z0-9']+/)
).filter((word) => word !== "" && !notALiftWord.has(word));

// Exercise names and catalog slugs: the lifts a load is attached to (not the bar or the plates).
const liftWords = new Set([
  ...catalogLiftWords,
  ...[
    "bench",
    "benching",
    "curl",
    "curls",
    "deadlift",
    "deadlifts",
    "deadlifting",
    "extension",
    "extensions",
    "flies",
    "fly",
    "lunge",
    "lunges",
    "press",
    "presses",
    "pressdown",
    "pulldown",
    "pulldowns",
    "rdl",
    "row",
    "rows",
    "shrug",
    "shrugs",
    "snatch",
    "squat",
    "squats",
    "squatting",
    "thrust",
    "thrusts",
  ],
]);

// Function words that do not count toward the distance between the exercise and the figure.
const skipWord = new Set([
  "a",
  "an",
  "and",
  "at",
  "by",
  "for",
  "in",
  "is",
  "of",
  "on",
  "the",
  "to",
  "with",
  "your",
  "my",
  "will",
  "would",
  "could",
  "can",
  "about",
  "around",
  "roughly",
  "just",
  "only",
  "was",
  "now",
]);

/** Whether an exercise name is within two words before `end` (an offset into the sentence). */
function exerciseBefore(words: readonly Word[], start: number): boolean {
  const before = words.filter((word) => word.end <= start);
  let counted = 0;
  for (let i = before.length - 1; i >= 0 && counted <= 2; i--) {
    if (liftWords.has(before[i].text)) return true;
    if (!skipWord.has(before[i].text)) counted += 1;
  }
  return false;
}

// ---- real rep or set notation, straight after the figure --------------------------------------

const timeUnit =
  "(?:weeks?|wks?|months?|days?|years?|blocks?|cycles?|meets?|hours?|hrs?|minutes?|mins?|seconds?|secs?|phases?|sessions?)";
const repNotationAfter = [
  // "x 6", "× 6", "*6", but not "x 2 weeks".
  new RegExp(
    String.raw`^\s*[x×*]\s*\d+(?:\s*(?:-|–|to)\s*\d+)?(?!\d|\.\d)(?!\s*${timeUnit}\b)`,
    "i",
  ),
  // "for 8" then the end, reps, sets or punctuation.
  /^\s*for\s+\d{1,2}(?:\s*(?:-|–|to)\s*\d{1,2})?\s*(?:$|reps?\b|sets?\b|[.,;:!?)])/i,
  // "3x5", "3 x 5".
  /^\s*\d+\s*[x×]\s*\d+/i,
  // "sets of 5", "set 5".
  /^\s*sets?\s+(?:of\s+)?\d/i,
];
const perSide = /^\s*(?:per|a|each)\s+side\b/i;

function repNotationAfterFigure(
  sentence: string,
  end: number,
  bodyWordInSentence: boolean,
): boolean {
  const after = sentence.slice(end);
  if (repNotationAfter.some((pattern) => pattern.test(after))) return true;
  return perSide.test(after) && !bodyWordInSentence;
}

// ---- the person's weight ------------------------------------------------------------------------

const bodyWords = new RegExp(
  String.raw`\b(?:weigh(?:s|ed|ing|-?ins?)?|scales?|bmi|height|body[- ]?weight|your weight)\b`,
  "i",
);
// "you'll be", "you will reach", "you could get down to", "puts you at".
const personProjection = new RegExp(
  String
    .raw`\byou(?:'ll|'d|'re| will| would| could| can| might| may| are going to)?\s+(?:be|being|reach|hit|weigh|get(?: down)? to|end up|sit|land)\b|\b(?:put|puts|putting)\s+you\b`,
  "i",
);
const aboutThePerson = (text: string) => bodyWords.test(text) || personProjection.test(text);

// ---- figures written another way ----------------------------------------------------------------

const tens: Readonly<Record<string, number>> = {
  twenty: 20,
  thirty: 30,
  forty: 40,
  fifty: 50,
  sixty: 60,
  seventy: 70,
  eighty: 80,
  ninety: 90,
};
const ones: Readonly<Record<string, number>> = {
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
};
// "fifty kilos", "fifty-five kg", "one hundred and ten pounds".
const writtenWeight = new RegExp(
  String
    .raw`\b(?:(one|two) hundred(?: and)?[ -]?)?(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)?(?:[ -](one|two|three|four|five|six|seven|eight|nine))?\s+(${kgWord}|${lbWord})\b`,
  "gi",
);
// A bare number straight after the projection ("you'll be at 50 by March"), not a unit.
const bareAfter =
  /^\s*(?:$|[.,;:!?)]|(?:by|in|within|before|after|from|if|when|and|or|but|then|soon|next|this|once|at|on)\b)/i;
const bareBefore = new RegExp(
  String
    .raw`(?:${personProjection.source}|${bodyWords.source})(?:\s+(?:at|around|about|near|nearly|roughly|close to|down|down to|to|over|under|just|only|almost|approximately|like|up|exactly|is|of))*\s*$`,
  "i",
);

type Hit = Readonly<{ start: number; end: number; kgs: readonly number[]; bare: boolean }>;

function hitsIn(sentence: string): Hit[] {
  const hits: Hit[] = [];
  for (const match of sentence.matchAll(weightPattern)) {
    const kgs = [match[1], match[2]].filter((raw): raw is string => raw !== undefined)
      .map((raw) => toKg(Number(raw.replace(",", ".")), match[3]));
    hits.push({ start: match.index, end: match.index + match[0].length, kgs, bare: false });
  }
  for (const match of sentence.matchAll(writtenWeight)) {
    const [, hundreds, ten, one, unit] = match.map((part) => part?.toLowerCase());
    if (!ten && !one && !hundreds) continue;
    const value = (hundreds ? (hundreds === "one" ? 100 : 200) : 0) + (ten ? tens[ten] : 0) +
      (one ? ones[one] : 0);
    const start = match.index + match[0].search(/\S/);
    hits.push({
      start,
      end: match.index + match[0].length,
      kgs: [toKg(value, unit)],
      bare: false,
    });
  }
  // A bare number in a sentence about the person's weight.
  if (aboutThePerson(sentence)) {
    for (
      const match of sentence.matchAll(/(?<![\d.,-])(\d{2,3})(?![\d.,]\d)(?!\s*(?:kg|lb|%))/gi)
    ) {
      const value = Number(match[1]);
      const end = match.index + match[0].length;
      if (value < 30 || value > 300) continue;
      if (hits.some((hit) => match.index >= hit.start && match.index < hit.end)) continue;
      if (
        !bareBefore.test(sentence.slice(0, match.index)) || !bareAfter.test(sentence.slice(end))
      ) {
        continue;
      }
      hits.push({ start: match.index, end, kgs: [value], bare: true });
    }
  }
  return hits.sort((a, b) => a.start - b.start);
}

/**
 * Every weight figure in the sentence, in kg, each marked as the athlete's body weight or not
 * (see the top of this file for the rule).
 */
export function weightFiguresIn(sentence: string): WeightFigure[] {
  const words = wordsOf(sentence);
  const bodyWordInSentence = bodyWords.test(sentence);
  return hitsIn(sentence).map((hit) => {
    const before = sentence.slice(0, hit.start);
    const load = !hit.bare && exerciseBefore(words, hit.start) &&
      repNotationAfterFigure(sentence, hit.end, bodyWordInSentence) && !aboutThePerson(before);
    return { kgs: hit.kgs, index: hit.start, before, bodyWeight: !load };
  });
}
