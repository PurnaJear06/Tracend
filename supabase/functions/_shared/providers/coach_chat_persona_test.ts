// The persona rules of A10 as code-graded checks on recorded replies: answer first with named
// exercises, no unprompted recap of check-in or recovery numbers, no repeated caution, short.
// The graders are plain functions over the reply text; the recorded replies include the
// production failure of 2026-10-17.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { exerciseCatalogV2 } from "../onboarding/catalog_v2.ts";
import { coachChatInstructions } from "./coach_chat_provider.ts";

type Turn = Readonly<{ role: "user" | "assistant"; content: string }>;

const words = (text: string) => text.trim().split(/\s+/).filter(Boolean).length;
const sentencesOf = (text: string) =>
  text.split(/(?<=[.!?])\s+|\n+/).map((sentence) => sentence.trim()).filter(Boolean);

// Metrics the athlete's own app shows; reciting them unasked is a recap.
const recapMetrics: readonly [string, RegExp][] = [
  ["sleep", /\bsleep(?: quality)?\b[^.\n]{0,20}?\d/i],
  ["energy", /\benergy\b[^.\n]{0,20}?\d/i],
  ["mood", /\bmood\b[^.\n]{0,20}?\d/i],
  ["soreness", /\bsoreness\b[^.\n]{0,20}?\d/i],
  ["recovery", /\brecovery(?: score)?\b[^.\n]{0,20}?\d/i],
  ["hrv", /\bhrv\b[^.\n]{0,20}?\d/i],
  ["resting heart rate", /\bresting heart rate\b[^.\n]{0,20}?\d/i],
];

/** Metrics recited with a number that the question did not ask about. */
export function unpromptedRecap(reply: string, question: string): string[] {
  return recapMetrics.filter(([name, pattern]) =>
    pattern.test(reply) && !new RegExp(`\\b${name.split(" ")[0]}`, "i").test(question)
  ).map(([name]) => name);
}

const cautionCue =
  /\b(?:persists?|worsens?|see a doctor|physio|stop (?:if|the)|don'?t push|listen to your body|warm[- ]?up|take it easy|careful|sharp pain|dizzy)\b/i;
const content = (sentence: string) =>
  new Set(
    sentence.toLowerCase().replace(/[^a-z\s]/g, " ").split(/\s+/).filter((word) => word.length > 3),
  );

/** Cautions in the reply that say what a recent assistant turn already said. */
export function repeatedCautions(reply: string, thread: readonly Turn[], lookback = 3): string[] {
  const earlier = thread.filter((turn) => turn.role === "assistant").slice(-lookback)
    .flatMap((turn) => sentencesOf(turn.content)).filter((sentence) => cautionCue.test(sentence));
  return sentencesOf(reply).filter((sentence) => cautionCue.test(sentence)).filter((sentence) => {
    const mine = content(sentence);
    return earlier.some((old) => {
      const theirs = content(old);
      const shared = [...mine].filter((word) => theirs.has(word)).length;
      return mine.size > 0 && shared / Math.min(mine.size, theirs.size) >= 0.6;
    });
  });
}

/** Catalog or plan exercises the reply names. */
export function namedExercises(reply: string, names: readonly string[]): string[] {
  const lower = reply.toLowerCase();
  return names.filter((name) => lower.includes(name.toLowerCase()));
}

const setsAndReps = /\b\d+\s*(?:x|×|sets? of)\s*\d+(?:\s*[-–]\s*\d+)?\b/i;

/** The graded verdict for a reply to a routine question. */
export function gradeRoutineReply(
  reply: string,
  question: string,
  thread: readonly Turn[],
  names: readonly string[],
): string[] {
  const faults: string[] = [];
  if (namedExercises(reply, names).length < 3) faults.push("names fewer than 3 exercises");
  if (!setsAndReps.test(reply)) faults.push("no sets and reps");
  const recap = unpromptedRecap(reply, question);
  if (recap.length > 0) faults.push(`recaps ${recap.join(", ")}`);
  if (repeatedCautions(reply, thread).length > 0) faults.push("repeats a caution");
  if (words(reply) > 200) faults.push("over 200 words");
  return faults;
}

const question =
  "I am planning to do a workout in five minutes. Check my condition and tell me what to try now, and for the next 10 to 15 days I will be at home with no gym. What is the best way to train today?";

const thread: readonly Turn[] = [
  { role: "user", content: "I have a weird feeling in my chest area when I press." },
  {
    role: "assistant",
    content:
      "Keep the load moderate and stop a set if the weird feeling persists or turns into sharp pain. If it keeps coming back, see a doctor.",
  },
];

const planNames = [
  "Barbell bench press",
  "Incline dumbbell press",
  "Cable lateral raise",
  "Cable triceps pressdown",
  "Push-up",
  "Dumbbell floor press",
];

// The reply of 2026-10-17 that the owner called the same checking stuff again: a data recap, no
// exercises, and the earlier caution said again.
const productionFailure =
  "Today's check-in is fine: sleep 4/5, energy 4/5, mood 5/5, soreness 2/5, and recovery 71/100. Do a moderate session focused on the chest, side delts and triceps from your plan, and stop with 1 to 2 reps left. For the next 10 to 15 days at home, about 3 sessions a week of bodyweight or household-weight training works. If the weird feeling persists, stop and see a doctor.";

const specificReply =
  "Push day is on, so:\n- **Barbell bench press** 3 x 6-8 at 62.5 kg\n- **Incline dumbbell press** 3 x 8-10 at 24 kg\n- **Cable lateral raise** 3 x 12-15\n- **Cable triceps pressdown** 3 x 10-12\n\nAt home, swap in **Push-up** and **Dumbbell floor press** for the presses, keeping the same weekly sets for chest and triceps.";

Deno.test("the production reply fails: it recaps check-in numbers, names no exercise and repeats the caution", () => {
  const faults = gradeRoutineReply(productionFailure, question, thread, planNames);
  assert(faults.includes("names fewer than 3 exercises"), faults.join());
  assert(faults.includes("no sets and reps"), faults.join());
  assert(faults.some((fault) => fault.startsWith("recaps ")), faults.join());
  assert(faults.includes("repeats a caution"), faults.join());
});

Deno.test("a reply with named exercises, sets, reps and loads passes", () => {
  assertEquals(gradeRoutineReply(specificReply, question, thread, planNames), []);
});

Deno.test("a reply that recaps check-in numbers unprompted fails; the same numbers asked for do not", () => {
  const recap = `${specificReply}\n\nYour sleep was 4/5 and recovery 71/100 today.`;
  assertEquals(unpromptedRecap(recap, question), ["sleep", "recovery"]);
  assert(gradeRoutineReply(recap, question, thread, planNames).some((f) => f.startsWith("recaps")));
  assertEquals(unpromptedRecap("Your recovery is 71/100.", "How is my recovery?"), []);
});

Deno.test("a reply that repeats a caution from the last 3 turns fails; a short pointer back passes", () => {
  const repeated =
    `${specificReply}\n\nStop a set if the weird feeling persists or turns into sharp pain.`;
  assert(repeatedCautions(repeated, thread).length > 0);
  assert(gradeRoutineReply(repeated, question, thread, planNames).includes("repeats a caution"));
  const pointer = `${specificReply}\n\nSame caution as I said earlier.`;
  assertEquals(repeatedCautions(pointer, thread), []);
  // A caution from a turn older than the last three is not a repeat.
  const old: Turn[] = [
    thread[1],
    { role: "assistant", content: "Fine." },
    { role: "assistant", content: "Good." },
    { role: "assistant", content: "Sure." },
  ];
  assertEquals(repeatedCautions(repeated, old), []);
});

Deno.test("a routine reply stays within about 200 words", () => {
  assert(words(specificReply) <= 200);
  const long = `${specificReply} ${"filler ".repeat(200)}`;
  assert(gradeRoutineReply(long, question, thread, planNames).includes("over 200 words"));
});

Deno.test("the named exercises of the fixture plan are catalog exercises", () => {
  const catalog = new Set(exerciseCatalogV2.map((exercise) => exercise.name));
  for (const name of planNames) assert(catalog.has(name), name);
});

Deno.test("the persona asks for these behaviours: answer first, no recap, no repeats, short, home from the options", () => {
  const rules = coachChatInstructions([]);
  assertStringIncludes(rules, "Answer the question that was asked, first and concretely");
  assertStringIncludes(rules, "name the exercises with their sets, reps, rest and loads");
  assertStringIncludes(rules, "Never recite check-in, sleep, recovery, weight or other numbers");
  assertStringIncludes(rules, "Do not repeat advice or a caution you already gave");
  assertStringIncludes(rules, "about 120 words, at most 3 bullets and 1 question");
  assertStringIncludes(rules, "compact list of up to about 200 words");
  assertStringIncludes(rules, "Home options in the training plan reference data");
  // The honesty and safety rules of A9 are untouched.
  assertStringIncludes(rules, "You cannot change anything yourself.");
  assertStringIncludes(rules, "Safe Ranges");
  assert(!rules.includes("Looking up the athlete's records"), "lookups are a gateway-only block");
  assertStringIncludes(coachChatInstructions([], true), "Looking up the athlete's records");
});
