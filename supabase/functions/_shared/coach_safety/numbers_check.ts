// The numbers check on a Coach reply (finding 3 of the Coach audit; AI_SAFETY_SPEC §12). Every
// figure the athlete would read as fact about themselves (kg, kcal, %, g, bpm, minutes, BMI,
// dates, counts above ten) must appear in what Coach was given: the athlete file, the calculated
// sections, the reference-data blocks, the Safe Ranges, or the athlete's own message. A figure
// Coach worked out for itself ("that is 3 kg in 4 weeks") is not in any of them and is refused,
// because that is how a window of data became "lost 7 kg". The model repairs once; a second
// failure ends in the labelled data summary, like every other validation failure.
//
// Matching is tolerant of rounding on purpose (the rule, in full):
//   1. A figure matches a given number when they are equal, or when they differ by no more than
//      half a unit of the last digit the reply writes: "74" matches 73.6 to 74.4, "0.62" matches
//      0.615 to 0.625, "14%" matches 13.7. The sign is ignored.
//   2. A rounded larger figure (100 or more, written with trailing zeros: "1,800", "2,000")
//      matches a given number within half its rounding step, but never by more than 5%.
//   3. The units must agree: "12 weeks" never matches 11.8 kg, and "0.9 kg" never matches
//      0.93%. A given number with no unit after it (a table cell) matches any unit.
//   4. A date written as YYYY-MM-DD must be a date in the given text; "Oct 4" or "4 Oct" must
//      match a month and day of one.
// Figures that carry no claim about the athlete are not checked (the allow-list): list numbers,
// ordinals, clock times, years, whole numbers up to ten with no measurement unit, and the
// prescription numbers a coach gives as advice (sets, reps, rest seconds, effort scales,
// "3x8", up to 30 reps and 10 sets).

export type GivenNumber = Readonly<{ value: number; unit: string }>;

export type NumberGround = Readonly<{
  /** Absolute values of every number in the given text, with the unit that follows each. */
  values: readonly GivenNumber[];
  /** Dates (YYYY-MM-DD) in the given text. */
  dates: ReadonlySet<string>;
  /** Month and day (MM-DD) of those dates. */
  monthDays: ReadonlySet<string>;
}>;

const months = [
  "jan",
  "feb",
  "mar",
  "apr",
  "may",
  "jun",
  "jul",
  "aug",
  "sep",
  "oct",
  "nov",
  "dec",
];
const monthWord = String
  .raw`(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)`;
const isoDate = /\b\d{4}-\d{2}-\d{2}\b/g;
const clockTime = /\b\d{1,2}:\d{2}(?::\d{2})?\b/g;
const ordinal = /\b\d+(?:st|nd|rd|th)\b/gi;
const monthThenDay = new RegExp(String.raw`\b(${monthWord})\.? (\d{1,2})\b`, "gi");
const dayThenMonth = new RegExp(String.raw`\b(\d{1,2}) (${monthWord})\b`, "gi");
const year = /\b(?:19|20)\d{2}\b/g;
const alwaysOn = /\b24\/7\b/g;
const listNumber = /^([ \t]*)\d+[.)](?=\s)/gm;

const blank = (match: string) => " ".repeat(match.length);

type Cleaned = Readonly<{ text: string; dates: string[]; monthDays: string[] }>;

/**
 * The text with dates, times, ordinals and list numbers blanked out, and the dates found. A
 * reply's years are blanked too (a year is not a claim about the athlete); the given text keeps
 * its years, because "2000 kcal" is a number there.
 */
function clean(text: string, blankYears: boolean): Cleaned {
  const dates: string[] = [];
  const monthDays: string[] = [];
  let out = text.replace(isoDate, (match) => {
    dates.push(match);
    return blank(match);
  });
  out = out.replace(clockTime, blank).replace(ordinal, blank).replace(alwaysOn, blank);
  out = out.replace(
    listNumber,
    (match, indent: string) => indent + " ".repeat(match.length - indent.length),
  );
  out = out.replace(monthThenDay, (match, month: string, day: string) => {
    monthDays.push(`${monthIndex(month)}-${day.padStart(2, "0")}`);
    return blank(match);
  });
  out = out.replace(dayThenMonth, (match, day: string, month: string) => {
    monthDays.push(`${monthIndex(month)}-${day.padStart(2, "0")}`);
    return blank(match);
  });
  if (blankYears) out = out.replace(year, blank);
  return { text: out, dates, monthDays };
}

function monthIndex(word: string): string {
  const index = months.indexOf(word.slice(0, 3).toLowerCase());
  return String(index + 1).padStart(2, "0");
}

const numberPattern = /(?<![A-Za-z0-9_.])(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d+))?/g;

type Token = Readonly<{
  value: number;
  decimals: number;
  raw: string;
  before: string;
  after: string;
  /** The unit class that follows the number: a known unit, "other" (some word), or "" (none). */
  unit: string;
}>;

const unitClasses: readonly (readonly [RegExp, string])[] = [
  [/^\s*(?:%|percent\b|per ?cent\b)/, "%"],
  [/^\s*(?:kgs?\b|kilos?\b|kilograms?\b)/, "kg"],
  [/^\s*(?:lbs?\b|pounds?\b)/, "lb"],
  [/^\s*(?:kcals?\b|calories?\b|cals?\b)/, "kcal"],
  [/^\s*(?:gr?\b|grams?\b)/, "g"],
  [/^\s*bpm\b/, "bpm"],
  [/^\s*(?:ms\b|milliseconds?\b)/, "ms"],
  [/^\s*(?:cm|mm)\b/, "cm"],
  [/^\s*(?:hours?\b|hrs?\b|h\b)/, "h"],
  [/^\s*(?:minutes?\b|mins?\b)/, "min"],
  [/^\s*-?\s*(?:weeks?\b|wks?\b)/, "wk"],
  [/^\s*-?\s*days?\b/, "d"],
  [/^\s*-?\s*months?\b/, "mo"],
  [/^\s*steps?\b/, "steps"],
];
const bmiBefore = /\bbmi\b[^.\d]{0,24}$/;

function unitOf(before: string, after: string): string {
  if (bmiBefore.test(before)) return "bmi";
  for (const [pattern, unit] of unitClasses) if (pattern.test(after)) return unit;
  return /^\s*[a-z]/.test(after) ? "other" : "";
}

function tokensOf(text: string): Token[] {
  const found: Token[] = [];
  for (const match of text.matchAll(numberPattern)) {
    const whole = match[1].replaceAll(",", "");
    const fraction = match[2] ?? "";
    const value = Number(fraction ? `${whole}.${fraction}` : whole);
    if (!Number.isFinite(value)) continue;
    const end = match.index + match[0].length;
    const before = text.slice(Math.max(0, match.index - 28), match.index).toLowerCase();
    const after = text.slice(end, end + 28).toLowerCase();
    found.push({
      value,
      decimals: fraction.length,
      raw: match[0],
      before,
      after,
      unit: unitOf(before, after),
    });
  }
  return found;
}

/** What the athlete was given, as numbers and dates to match a reply against. */
export function numberGroundOf(texts: readonly string[]): NumberGround {
  const values = new Map<string, GivenNumber>();
  const dates = new Set<string>();
  const monthDays = new Set<string>();
  for (const text of texts) {
    const cleaned = clean(text, false);
    for (const token of tokensOf(cleaned.text)) {
      values.set(`${token.value}|${token.unit}`, { value: token.value, unit: token.unit });
    }
    for (const date of cleaned.dates) {
      dates.add(date);
      monthDays.add(date.slice(5));
    }
    for (const monthDay of cleaned.monthDays) monthDays.add(monthDay);
  }
  return { values: [...values.values()], dates, monthDays };
}

const measurementUnit =
  /^\s*(?:%|percent\b|per ?cent\b|kgs?\b|kilos?\b|kilograms?\b|lbs?\b|pounds?\b|kcals?\b|calories?\b|cals?\b|gr?\b|grams?\b|bpm\b|ms\b|milliseconds?\b|cm\b|mm\b|litres?\b|liters?\b|ml\b|mg\b|oz\b|km\b|miles?\b|mmhg\b)/;
const timeUnit = /^\s*(?:hours?\b|hrs?\b|h\b|minutes?\b|mins?\b)/;
const prescriptionUnit = /^\s*(?:sets?\b|reps?\b|repetitions?\b|rounds?\b|seconds?\b|secs?\b|s\b)/;
const measuredBefore = /\b(?:bmi|rhr|hrv)\s*(?:of|is|was|at|about|around|~|:)?\s*$/;
const scaleBefore = /\b(?:rpe|rir)\s*(?:of|is|was|at|about|around|~|:)?\s*$/;
const timesAfter = /^\s*[x×]\s*\d/;
const timesBefore = /\d\s*[x×]\s*$/;
const rangeEnd = /^\s*(?:-|–|—|to)\s*\d[\d,]*(?:\.\d+)?(.*)$/;

/** Whether the figure is a claim about the athlete that must come from the given text. */
function mustBeGrounded(token: Token): boolean {
  const range = rangeEnd.exec(token.after);
  const after = range ? range[1] : token.after;
  const integer = token.decimals === 0;
  if (measurementUnit.test(after) || measuredBefore.test(token.before)) return true;
  if (timeUnit.test(after)) return !(integer && token.value <= 5);
  if (scaleBefore.test(token.before)) return !(integer && token.value <= 10);
  if (timesAfter.test(token.after) || timesBefore.test(token.before)) {
    return !(integer && token.value <= 30);
  }
  if (prescriptionUnit.test(after)) {
    const secondsLike = /^\s*(?:seconds?\b|secs?\b|s\b)/.test(after);
    const limit = secondsLike ? 300 : /^\s*sets?\b|^\s*rounds?\b/.test(after) ? 10 : 30;
    return !(integer && token.value <= limit);
  }
  if (!integer) return true;
  return token.value > 10;
}

/** Units agree when the reply's is the given number's, or the given number has no unit. */
function unitsAgree(token: Token, given: GivenNumber): boolean {
  if (given.unit === "") return true;
  const known = token.unit !== "" && token.unit !== "other";
  return known ? given.unit === token.unit : given.unit === token.unit || given.unit === "other";
}

function matches(token: Token, given: GivenNumber): boolean {
  if (!unitsAgree(token, given)) return false;
  const value = token.value;
  const difference = Math.abs(given.value - value);
  if (difference === 0) return true;
  if (difference <= 0.5 * 10 ** -token.decimals + 1e-9) return true;
  if (token.decimals === 0 && value >= 100) {
    const trailing = /0+$/.exec(String(value))?.[0].length ?? 0;
    if (trailing > 0) {
      return difference <= Math.min(0.5 * 10 ** trailing, 0.05 * value) + 1e-9;
    }
  }
  return false;
}

/**
 * The figures in a reply that are not in what the athlete was given, as written in the reply
 * (each once, in order). Empty when every checked figure is grounded.
 */
export function ungroundedNumbers(answer: string, ground: NumberGround): string[] {
  const cleaned = clean(answer, true);
  const missing: string[] = [];
  const add = (raw: string) => {
    if (!missing.includes(raw)) missing.push(raw);
  };
  for (const date of cleaned.dates) if (!ground.dates.has(date)) add(date);
  for (const monthDay of cleaned.monthDays) {
    if (!ground.monthDays.has(monthDay)) {
      add(`${months[Number(monthDay.slice(0, 2)) - 1]} ${Number(monthDay.slice(3))}`);
    }
  }
  for (const token of tokensOf(cleaned.text)) {
    if (!mustBeGrounded(token)) continue;
    if (ground.values.some((given) => matches(token, given))) continue;
    add(token.raw);
  }
  return missing;
}
