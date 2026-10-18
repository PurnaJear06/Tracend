// Plain-text helpers for matching an athlete's words to saved facts. Matching is deliberately
// shallow: lower case, no punctuation, a light plural strip, and a small list of filler words. Two
// phrases are the same subject when every word of the shorter appears in the longer.

const fillerWords = new Set([
  "a",
  "an",
  "the",
  "my",
  "your",
  "his",
  "her",
  "our",
  "their",
  "of",
  "on",
  "in",
  "at",
  "to",
  "for",
  "and",
  "or",
  "with",
  "without",
  "from",
  "by",
  "as",
  "i",
  "me",
  "is",
  "are",
  "am",
  "was",
  "were",
  "be",
  "been",
  "it",
  "its",
  "this",
  "that",
  "these",
  "those",
  "any",
  "some",
  "much",
  "very",
  "really",
  "just",
  "so",
  "too",
  "all",
  "only",
  "also",
  "now",
  "again",
  "still",
  "not",
  "no",
  "do",
  "does",
  "did",
  "have",
  "has",
  "had",
  "can",
  "will",
  "would",
  "should",
  "im",
  "ive",
  "dont",
  "doesnt",
  "when",
  "while",
  "than",
  "then",
  "there",
  "if",
  "but",
]);

/** Lower case, straight apostrophes, single spaces. */
export function normalizeText(text: string): string {
  return text.toLowerCase().replace(/[‘’ʼ`]/g, "'").replace(/\s+/g, " ").trim();
}

/** One word without a plural ending: squats -> squat, presses -> press, potatoes -> potato. */
export function stem(word: string): string {
  if (word.length <= 3) return word;
  if (word.endsWith("ies") && word.length > 4) return `${word.slice(0, -3)}y`;
  if (/(?:ss|x|z|ch|sh|o)es$/.test(word)) return word.slice(0, -2);
  if (word.endsWith("s") && !word.endsWith("ss") && !word.endsWith("us")) return word.slice(0, -1);
  return word;
}

/** The words of a phrase that carry its meaning, stemmed, in order, without repeats. */
export function contentWords(text: string): string[] {
  const words = normalizeText(text).replace(/'/g, "").split(/[^a-z0-9]+/).filter((word) =>
    word.length >= 2 && !fillerWords.has(word)
  ).map(stem);
  return [...new Set(words)];
}

/**
 * True when one phrase's content words are all in the other. A phrase with no content words
 * matches nothing.
 */
export function sameSubject(a: string, b: string): boolean {
  const left = contentWords(a);
  const right = contentWords(b);
  if (left.length === 0 || right.length === 0) return false;
  const [short, long] = left.length <= right.length ? [left, right] : [right, left];
  return short.every((word) => long.includes(word));
}

/** True when the phrase contains the word (after the same normalising). */
export function hasWord(text: string, word: string): boolean {
  return contentWords(text).includes(stem(word));
}

/** One line of text that is safe inside a prompt section: no angle brackets, clipped. */
export function flatten(text: string, max: number): string {
  const flat = text.replace(/[<>]/g, "").replace(/\s+/g, " ").trim();
  return flat.length <= max ? flat : `${flat.slice(0, Math.max(0, max - 1)).trimEnd()}…`;
}

/** YYYY-MM-DD of a timestamp string, or the empty string. */
export function dateOf(value: unknown): string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}/.test(value) ? value.slice(0, 10) : "";
}
