// The weights in a sentence of Coach's reply, and which of them are the athlete's body weight.
// A "kg" figure is not always a body weight: "overhead press is 55 kg x 6" is a load. The goal
// phase check (guard.ts) must read only body weights, so the sentence is tokenised into words and
// figures and each figure is classified from its surroundings:
//   - a figure written with rep notation ("55 kg x 6", "50 kg for 8", "60 kg per side") is a load;
//   - otherwise the nearest cue within a few words decides. A load cue is an exercise name or
//     catalog slug, a barbell word (plate, bar, rack), a lifting word (reps, load, 1RM). A body
//     cue is a word about the person (weigh, body weight, scale, BMI, height, target, goal), a
//     movement of the person toward a weight ("get down to", "drop to"), projection or pace
//     wording ("at this pace", "would put you at", "on track for", "heading to", "you'd land
//     at"), or "you" as the subject of a verb that lands on a weight ("you'll be at", "you will
//     hit", "you could reach"). The nearer cue wins and a tie goes to the load;
//   - a figure with no load cue within reach is a body weight, with or without a body cue: this is
//     a safety check, so an unclear figure fails closed. Only a clear load cue clears a figure.
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

// Verbs that put a load on the bar. "pull" is a lift by itself. The others read as a load only
// when a lift is in context (the sentence, an earlier sentence of the paragraph, or the athlete's
// question): "you'll try 40 kg" after "your bench is moving well" is a load, and "you could go to
// 55 kg" with no lift anywhere is a body weight (fail closed).
const liftVerbs = new Set(["pull", "pulls"]);
const progressionWords = new Set([
  "add",
  "adds",
  "adding",
  "try",
  "tries",
  "trying",
  "attempt",
  "attempts",
  "attempting",
]);
const progressionPhrases: readonly (readonly RegExp[])[] = [
  [/^(?:move|moves|moving|work|works|working)$/, /^up$/, /^to$/],
  [/^(?:go|goes|going)$/, /^to$/],
];

/** Whether the sentence names a lift or lifting (an exercise, a bar, reps, a load). */
export function namesLift(sentence: string): boolean {
  const words = wordsOf(sentence);
  return words.some((_, index) => isLoadWord(words, index));
}

function loadCuesIn(words: readonly Word[], liftInContext: boolean): Cue[] {
  const cues: Cue[] = [];
  for (let i = 0; i < words.length; i++) {
    if (isLoadWord(words, i) || liftVerbs.has(words[i].text)) cues.push({ from: i, to: i });
    if (!liftInContext) continue;
    if (progressionWords.has(words[i].text)) cues.push({ from: i, to: i });
    for (const phrase of progressionPhrases) {
      if (
        phrase.every((pattern, offset) => words[i + offset] && pattern.test(words[i + offset].text))
      ) {
        cues.push({ from: i, to: i + phrase.length - 1 });
      }
    }
  }
  return cues;
}

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

/** A cue's place in the sentence; a strong body cue is a word or phrase that is about the person's weight. */
type Cue = Readonly<{ from: number; to: number; strong?: true }>;

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

// Single words about the person's weight (strong) or what they aim for (weak: a lift has targets).
const strongBodyWord =
  /^(?:weigh|weighs|weighed|weighing|weighin|weighins|scales?|bmi|height|bodyweight)$/;
const weakBodyWord = /^(?:target|targets|aim|aims|aiming|goal|goals)$/;

// "get down to", "drop to", "at this pace", "put you at", "land at": wording that is about the
// person's weight. These (and the words above) win over a load cue carried from an earlier
// sentence when they are as near as it.
const strongPhrases: readonly (readonly RegExp[])[] = [
  [
    /^(?:get|getting|go|going|come|coming|slim|slimming|cut|cutting|bring|bringing)$/,
    /^down$/,
    /^to$/,
  ],
  [/^(?:drop|dropping|dip|dipping|fall|falling|sink|sinking)$/, /^to$/],
  [/^(?:drop|dropping|dip|dipping|fall|falling|sink|sinking)$/, /^down$/, /^to$/],
  [/^at$/, /^(?:this|that|the|your|current|same)$/, /^(?:pace|rate)$/],
  [/^(?:put|putting|puts|leave|leaves|leaving|take|takes|taking|bring|brings)$/, /^(?:you|your)$/],
  [/^(?:on|off)$/, /^(?:track|course|pace)$/],
  [
    /^(?:land|lands|landing|end|ends|ending|finish|finishes|finishing|settle|settles|settling)$/,
    /^(?:at|on|around)$/,
  ],
];

// Weaker projection wording, which a lift's progression can share ("if you keep this up you will
// hit 52.5 kg"): it counts unless a load cue is as near, or one is carried from the sentence before.
const weakPhrases: readonly (readonly RegExp[])[] = [
  [/^(?:heading|headed|trending|tracking|moving|going|aiming)$/, /^(?:to|toward|towards)$/],
  [/^(?:project|projects|projected|projecting|projection|extrapolate|extrapolated)$/],
  [/^(?:if|when)$/, /^you$/, /^(?:keep|continue|carry|stay|maintain)$/],
];

// "you" as the subject of a verb that lands on a weight.
const landsOnWeight =
  /^(?:be|been|being|reach|reaching|hit|hitting|weigh|weighing|get|getting|drop|dropping|fall|falling|dip|dipping|land|end|sit|come|hover|stay|slim|shrink)$/;
const youSubject = /^you(?:'ll|'d|'re|'ve)?$/;

function bodyCuesIn(words: readonly Word[]): Cue[] {
  const cues: Cue[] = [];
  for (let i = 0; i < words.length; i++) {
    const word = words[i].text;
    if (strongBodyWord.test(word)) cues.push({ from: i, to: i, strong: true });
    if (weakBodyWord.test(word)) cues.push({ from: i, to: i });
    if (word === "weight" || word === "weights") {
      if (i === 0 || !notBodyBefore.has(words[i - 1].text)) {
        cues.push({ from: i, to: i, strong: true });
      }
    }
    const matches = (phrase: readonly RegExp[]) =>
      phrase.every((pattern, offset) => words[i + offset] && pattern.test(words[i + offset].text));
    for (const phrase of strongPhrases) {
      if (matches(phrase)) cues.push({ from: i, to: i + phrase.length - 1, strong: true });
    }
    for (const phrase of weakPhrases) {
      if (matches(phrase)) cues.push({ from: i, to: i + phrase.length - 1 });
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

/** A load carried from the sentence before counts as a load cue this many words away. */
const carriedDistance = 2;

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
export function weightFiguresIn(sentence: string, carriedLoad = false): WeightFigure[] {
  const words = wordsOf(sentence);
  const bodyCues = bodyCuesIn(words);
  // A lift in context: this sentence names one, or an earlier sentence or the question did.
  const loadCues = loadCuesIn(words, carriedLoad || namesLift(sentence));
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
    const strongBody = nearest(bodyCues.filter((cue) => cue.strong).map(cueDistance));
    const load = hasRepNotation(sentence, start, match[0].length)
      ? 0
      : nearest(loadCues.map(cueDistance));
    found.push({
      kgs,
      index: start,
      before: sentence.slice(0, start),
      // A figure fails closed: it is a body weight unless a load cue is as near as any body cue.
      // Where the sentence before names a lift and this one has no load cue of its own, the lift
      // carries over: only wording about the person's weight, as near as two words away, overrides it.
      bodyWeight: carriedLoad && load === null
        ? strongBody !== null && strongBody <= carriedDistance
        : load === null || (body !== null && body < load),
    });
  }
  return found;
}
