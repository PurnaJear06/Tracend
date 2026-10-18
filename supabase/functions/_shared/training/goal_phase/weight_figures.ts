// The weights in a sentence of Coach's reply, and which of them are the athlete's body weight.
// A "kg" figure is not always a body weight: "overhead press is 55 kg x 6" is a load. The goal
// phase check (guard.ts) reads only body weights, and it is a safety check, so the rule is strict
// and fails closed:
//   - a figure is a LOAD only when it is attached to a lift in its own sentence or list item: rep
//     or set notation ("55 kg x 6", "50 kg for 8", "3x5", "sets of"), per-side wording, or an
//     exercise name, catalog slug, or bar or plate word within a few words of it;
//   - every other figure is a BODY WEIGHT;
//   - a sentence with a time horizon ("by March", "in 8 weeks", "soon", "next week") or cut,
//     deficit, loss, drop, target, goal or pace wording is never a load on an exercise name alone:
//     it needs rep or set notation, because "your goal could be 48 kg" and "bench is going well,
//     you'll be 50 kg by March" are about the person;
//   - a word about the person's weight (weigh, scale, body weight, BMI, height) nearer than the
//     lift word makes it a body weight.
// Nothing carries from one sentence to the next, and the athlete's question carries nothing: a
// load Coach writes without its exercise and reps ("you'll move up to 45 kg") is a figure the
// guard cannot clear, so the reply is repaired to write it as "bench 45 kg x 6".
// The distance counts the words between the cue and the figure, not the small function words
// ("on", "the", "to"), so "55 kg on overhead press" and "weigh about 70 kg" both read as adjacent.
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
type Cue = Readonly<{ from: number; to: number }>;

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

// Exercise names and catalog slugs, and the barbell words that mean a load on a bar.
const loadWords = new Set([
  ...catalogLiftWords,
  ...[
    "bar",
    "barbell",
    "barbells",
    "bench",
    "benching",
    "curl",
    "curls",
    "deadlift",
    "deadlifts",
    "deadlifting",
    "dumbbell",
    "dumbbells",
    "extension",
    "extensions",
    "flies",
    "fly",
    "kettlebell",
    "kettlebells",
    "lunge",
    "lunges",
    "plate",
    "plates",
    "press",
    "presses",
    "pressdown",
    "pulldown",
    "pulldowns",
    "rack",
    "rdl",
    "rep",
    "reps",
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
// "the next set", "top set": a set of a lift. A bare "set" is also a verb ("set a target"), so it
// counts only after one of these.
const setQualifier = new Set([
  "next",
  "last",
  "top",
  "working",
  "final",
  "first",
  "second",
  "third",
]);

function isLoadWord(words: readonly Word[], index: number): boolean {
  const word = words[index].text;
  if (loadWords.has(word)) return true;
  return word === "set" && index > 0 && setQualifier.has(words[index - 1].text);
}

// Rep or set notation straight after or before the figure: "x 6", "3x5", "for 8 reps", "sets of",
// "per side", "reps".
const timeUnitWord =
  /^(?:weeks?|wks?|days?|months?|years?|hours?|hrs?|minutes?|mins?|seconds?|secs?|kg|kgs|lbs?|%|percent)$/;
const repsAfter =
  /^\s*(?:[x×*]\s*\d|\d+\s*[x×]\s*\d|(?:reps?|sets?|rm)\b|(?:per|a|each)\s+(?:side|hand|arm|leg)\b|(?:at|@)\s*\d+\s*reps?\b)/i;
const repsBefore =
  /(?:\d\s*[x×*]\s*|\bsets? of \d+(?:\s*(?:-|–|to)\s*\d+)?\s*(?:at|@|with)\s*|\d\s*[x×]\s*\d+\s*(?:at|@)\s*)$/i;

function hasRepNotation(sentence: string, index: number, length: number): boolean {
  const after = sentence.slice(index + length);
  if (repsAfter.test(after) || repsBefore.test(sentence.slice(0, index))) return true;
  const forReps = /^\s*for\s+(\d{1,2})\b(?!\.\d)\s*([a-z%]*)/i.exec(after);
  return forReps !== null && !timeUnitWord.test(forReps[2].toLowerCase());
}

// ---- the person's weight --------------------------------------------------------------------

// A weight that is not the body's: "the weight on the bar", "add weight", "the same weight".
const notBodyBefore = new Set([
  "the",
  "that",
  "this",
  "extra",
  "added",
  "more",
  "less",
  "same",
  "working",
  "total",
  "heavier",
  "lighter",
  "heavy",
  "light",
  "lower",
  "higher",
  "add",
  "adding",
  "plate",
  "bar",
]);
const bodyWord =
  /^(?:weigh|weighs|weighed|weighing|weighin|weighins|scales?|bmi|height|bodyweight)$/;

/** Words about the person's weight: weigh, scale, body weight, BMI, height. */
function bodyCuesIn(words: readonly Word[]): Cue[] {
  const cues: Cue[] = [];
  for (let i = 0; i < words.length; i++) {
    const word = words[i].text;
    if (bodyWord.test(word)) cues.push({ from: i, to: i });
    if (word === "weight" || word === "weights") {
      if (i === 0 || !notBodyBefore.has(words[i - 1].text)) cues.push({ from: i, to: i });
    }
  }
  return cues;
}

// Wording that makes a sentence about the person and not a lift: a time horizon, or a cut, a
// loss, a target or a pace.
const months =
  "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";
const aboutThePerson = new RegExp(
  [
    String
      .raw`\b(?:by|before|until|till)\s+(?:the |next |this |then\b|end\b|christmas|summer|winter|spring|autumn|fall|\d|week|month|year|${months}\b)`,
    String
      .raw`\bin\s+(?:about |around |roughly |another |just |only |the next )?(?:\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|several|a few|a couple of)\s*(?:-\s*\d+\s*)?(?:days?|weeks?|months?|years?)\b`,
    String
      .raw`\bwithin\b|\bsoon\b|\beventually\b|\bsomeday\b|\bnext (?:week|month|year|block)\b|\bthis (?:week|month|year)\b|\bin time\b`,
    String
      .raw`\b(?:cut|cuts|cutting|deficit|lose|loses|losing|loss|lost|shed|shedding|drop|drops|dropping|dip|dips|dipping|fall|falls|falling|slim|slimming|leaner|lean|target|targets|goal|goals|aim|aims|aiming|pace|rate|trend|trending|project\w*|extrapolat\w*|heading|on track)\b`,
  ].join("|"),
  "i",
);

// ---- classification ----------------------------------------------------------------------

// Function words that do not count toward the distance between a cue and a figure.
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
]);

/** Cues farther than this many words from the figure do not govern it. */
const reach = 5;

/** Words between a cue and the figure, not counting function words; null when too far. */
function distance(words: readonly Word[], from: number, to: number): number | null {
  let count = 0;
  for (let i = from; i <= to; i++) if (!skipWord.has(words[i].text)) count += 1;
  return count <= reach ? count : null;
}

function nearest(distances: readonly (number | null)[]): number | null {
  const near = distances.filter((value): value is number => value !== null);
  return near.length ? Math.min(...near) : null;
}

/**
 * Every weight figure in the sentence, in kg, each marked as the athlete's body weight or not
 * (see the top of this file for the rule).
 */
export function weightFiguresIn(sentence: string): WeightFigure[] {
  const words = wordsOf(sentence);
  const bodyCues = bodyCuesIn(words);
  const aboutPerson = aboutThePerson.test(sentence);
  const found: WeightFigure[] = [];
  for (const match of sentence.matchAll(weightPattern)) {
    const kgs = [match[1], match[2]].filter((raw): raw is string => raw !== undefined)
      .map((raw) => toKg(Number(raw.replace(",", ".")), match[3]));
    const start = match.index;
    const end = start + match[0].length;
    // The words wholly before the figure end at lastBefore; those wholly after it start at firstAfter.
    const lastBefore = words.findLastIndex((word) => word.end <= start);
    const firstAfter = words.findIndex((word) => word.start >= end);
    const cueDistance = (cue: Cue) =>
      cue.to <= lastBefore
        ? distance(words, cue.to + 1, lastBefore)
        : firstAfter !== -1 && cue.from >= firstAfter
        ? distance(words, firstAfter, cue.from - 1)
        : null;
    const notation = hasRepNotation(sentence, start, match[0].length);
    const body = nearest(bodyCues.map(cueDistance));
    const lift = nearest(
      words.flatMap((_, index) =>
        isLoadWord(words, index) ? [cueDistance({ from: index, to: index })] : []
      ),
    );
    const load = notation ||
      (lift !== null && !aboutPerson && (body === null || lift <= body));
    found.push({
      kgs,
      index: start,
      before: sentence.slice(0, start),
      bodyWeight: !load,
    });
  }
  return found;
}
