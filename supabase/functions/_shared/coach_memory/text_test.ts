import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  contentWords,
  dateOf,
  flatten,
  hasWord,
  normalizeText,
  sameSubject,
  stem,
} from "./text.ts";

Deno.test("normalizeText lowers case, straightens apostrophes and collapses spaces", () => {
  assertEquals(normalizeText("  I  DON’T   like\nSquats "), "i don't like squats");
});

Deno.test("stem removes plural endings and leaves other words alone", () => {
  const cases: Record<string, string> = {
    squats: "squat",
    presses: "press",
    benches: "bench",
    potatoes: "potato",
    berries: "berry",
    knees: "knee",
    cheeses: "cheese",
    lunges: "lunge",
    glass: "glass",
    focus: "focus",
    gas: "gas",
    run: "run",
    running: "running",
  };
  for (const [word, expected] of Object.entries(cases)) assertEquals(stem(word), expected, word);
});

Deno.test("contentWords drops filler, stems and removes repeats", () => {
  assertEquals(contentWords("I don't eat the Mushrooms, mushroom soup"), [
    "eat",
    "mushroom",
    "soup",
  ]);
  assertEquals(contentWords("a the of"), []);
  assertEquals(contentWords(""), []);
});

Deno.test("sameSubject holds when the shorter phrase's words are all in the longer", () => {
  assertEquals(sameSubject("squats", "barbell back squats"), true);
  assertEquals(sameSubject("barbell back squats", "squat"), true);
  assertEquals(sameSubject("left knee", "knee"), true);
  assertEquals(sameSubject("left knee", "right knee"), false);
  assertEquals(sameSubject("mushrooms", "mushroom pizza"), true);
  assertEquals(sameSubject("peanuts", "almonds"), false);
  assertEquals(sameSubject("", "squats"), false);
  assertEquals(sameSubject("the of", "squats"), false);
});

Deno.test("hasWord matches the stemmed word", () => {
  assertEquals(hasWord("my squats are heavy", "squat"), true);
  assertEquals(hasWord("my lunges", "squat"), false);
});

Deno.test("flatten removes angle brackets and line breaks and clips with an ellipsis", () => {
  assertEquals(flatten("a <b>\n\tc", 50), "a b c");
  assertEquals(flatten("abcdefghij", 6), "abcde…");
  assertEquals(flatten("abc", 3), "abc");
});

Deno.test("dateOf reads the date part of a timestamp and nothing else", () => {
  assertEquals(dateOf("2026-10-17T05:00:00+00:00"), "2026-10-17");
  assertEquals(dateOf("17 Oct"), "");
  assertEquals(dateOf(null), "");
});
