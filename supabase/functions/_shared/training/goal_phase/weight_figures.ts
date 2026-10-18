// The weights in a sentence of Coach's reply, and which of them are the athlete's body weight.
// A "kg" figure is not always a body weight: "overhead press is 55 kg x 6" is a load. The goal
// phase check (guard.ts) must read only body weights, so the sentence is tokenised into words and
// figures and each figure is classified from its surroundings:
//   - a figure written with rep notation ("55 kg x 6", "50 kg for 8", "60 kg per side") is a load;
//   - otherwise the nearest cue within a few words decides. A load cue is an exercise name or
//     catalog slug, a barbell word (plate, bar, rack), a lifting word (reps, load, 1RM). A body
//     cue is a word about the person (weigh, body weight, scale, BMI, height, target, goal), a
//     movement of the person toward a weight ("get down to", "drop to"), "you" as the subject of
//     a verb that lands on a weight ("you'll be at", "you will hit", "you could reach"), or a
//     time frame right after the figure ("66.5 kg in 12 weeks", "70 kg by March"), which is a
//     forecast of where something will be (the weakest cue: any load cue beats it);
//   - a figure with no body cue nearby is not a body weight, and a tie goes to the load.
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

// Lifts and lifting words a coach writes whether or not the catalog holds them.
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
    "lift",
    "lifted",
    "lifting",
    "lifts",
    "load",
    "loaded",
    "loading",
    "loads",
    "lunge",
    "lunges",
    "plate",
    "plates",
    "pr",
    "press",
    "presses",
    "pressdown",
    "pulldown",
    "pulldowns",
    "rack",
    "rdl",
    "rep",
    "reps",
    "rir",
    "rm",
    "row",
    "rows",
    "rpe",
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
const oneRepMax = /^\d+rm$/;
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
  if (loadWords.has(word) || oneRepMax.test(word)) return true;
  return word === "set" && index > 0 && setQualifier.has(words[index - 1].text);
}

// Rep notation straight after or before the figure: "x 6", "for 8 reps", "per side", "reps".
const timeUnitWord =
  /^(?:weeks?|wks?|days?|months?|years?|hours?|hrs?|minutes?|mins?|seconds?|secs?|kg|kgs|lbs?|%|percent)$/;
const repsAfter =
  /^\s*(?:[x×*]\s*\d|(?:reps?|sets?|rm)\b|(?:per|a|each)\s+(?:side|hand|arm|leg)\b)/i;
const repsBefore = /\d\s*[x×*]\s*$/i;

function hasRepNotation(sentence: string, index: number, length: number): boolean {
  const after = sentence.slice(index + length);
  if (repsAfter.test(after) || repsBefore.test(sentence.slice(0, index))) return true;
  const forReps = /^\s*for\s+(\d{1,2})\b(?!\.\d)\s*([a-z%]*)/i.exec(after);
  return forReps !== null && !timeUnitWord.test(forReps[2].toLowerCase());
}

// ---- body cues ---------------------------------------------------------------------------

type Cue = Readonly<{ from: number; to: number }>;

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

// Single words about the person or what they aim for.
const bodyWord =
  /^(?:weigh|weighs|weighed|weighing|weighin|weighins|scales?|bmi|height|bodyweight|target|targets|aim|aims|aiming|goal|goals)$/;

// "get down to", "drop to": a movement of the person toward a weight.
const movementPhrases: readonly (readonly RegExp[])[] = [
  [
    /^(?:get|getting|go|going|come|coming|slim|slimming|cut|cutting|bring|bringing)$/,
    /^down$/,
    /^to$/,
  ],
  [/^(?:drop|dropping|dip|dipping|fall|falling|sink|sinking)$/, /^to$/],
  [/^(?:drop|dropping|dip|dipping|fall|falling|sink|sinking)$/, /^down$/, /^to$/],
];

// "you" as the subject of a verb that lands on a weight.
const landsOnWeight =
  /^(?:be|been|being|reach|reaching|hit|hitting|weigh|weighing|get|getting|drop|dropping|fall|falling|dip|dipping|land|end|sit|come|hover|stay|slim|shrink)$/;
const youSubject = /^you(?:'ll|'d|'re|'ve)?$/;

function bodyCuesIn(words: readonly Word[]): Cue[] {
  const cues: Cue[] = [];
  for (let i = 0; i < words.length; i++) {
    const word = words[i].text;
    if (bodyWord.test(word)) cues.push({ from: i, to: i });
    if (word === "weight" || word === "weights") {
      if (i === 0 || !notBodyBefore.has(words[i - 1].text)) cues.push({ from: i, to: i });
    }
    for (const phrase of movementPhrases) {
      if (
        phrase.every((pattern, offset) => words[i + offset] && pattern.test(words[i + offset].text))
      ) {
        cues.push({ from: i, to: i + phrase.length - 1 });
      }
    }
    if (youSubject.test(word)) {
      // "you", then up to three words (will, could, just ...), then the verb.
      for (let j = i + 1; j <= i + 4 && j < words.length; j++) {
        if (/^\d/.test(words[j].text)) break;
        if (landsOnWeight.test(words[j].text)) {
          cues.push({ from: j, to: j });
          break;
        }
      }
    }
  }
  return cues;
}

// A time frame straight after the figure: a forecast of a weight, "in 12 weeks", "by March".
const countWord =
  "(?:\\d+(?:\\s*(?:-|–|to)\\s*\\d+)?|a|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|several|a few|a couple of)";
const monthWord =
  "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";
const timeFrameAfter = new RegExp(
  `^\\s*(?:or so\\s*)?(?:(?:in|within|after|over)\\s+(?:about |around |roughly |another |just |only |the next )?${countWord}\\s*(?:days?|weeks?|months?|years?)\\b|by\\s+(?:the )?(?:end|then|next|christmas|summer|winter|spring|autumn|fall|\\d|${monthWord}\\b))`,
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
 * Every weight figure in the sentence, in kg, each marked as the athlete's body weight or not.
 * `bodyWeight` is true when a body cue is closer to the figure than any load cue.
 */
export function weightFiguresIn(sentence: string): WeightFigure[] {
  const words = wordsOf(sentence);
  const bodyCues = bodyCuesIn(words);
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
    const body = nearest(bodyCues.map(cueDistance));
    const load = hasRepNotation(sentence, start, match[0].length) ? 0 : nearest(
      words.flatMap((_, index) =>
        isLoadWord(words, index) ? [cueDistance({ from: index, to: index })] : []
      ),
    );
    found.push({
      kgs,
      index: start,
      before: sentence.slice(0, start),
      // A time frame is a weaker cue than a word about the person: any load cue beats it.
      bodyWeight: body !== null
        ? load === null || body < load
        : load === null && timeFrameAfter.test(sentence.slice(end)),
    });
  }
  return found;
}
