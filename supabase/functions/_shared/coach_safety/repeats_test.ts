import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  closingQuestion,
  contentWords,
  isSafetyWording,
  repeatsOf,
  similarity,
} from "./repeats.ts";

const previousReply =
  "You are at about 120 g on the days you logged. Your calorie target stays the same this week while we watch how your weight trend settles. Want me to suggest two easy ways to close the protein gap?";
const base = { previousReply, referralNeeded: false };

Deno.test("the closing question is the last sentence when it is a question", () => {
  assertEquals(
    closingQuestion(previousReply),
    "Want me to suggest two easy ways to close the protein gap?",
  );
  assertEquals(closingQuestion("Keep going. Sleep well."), null);
  assertEquals(closingQuestion("Is that clear? Keep going."), null);
  assertEquals(
    closingQuestion("Fine.\nShould I check your **sleep**?"),
    "Should I check your **sleep**?",
  );
});

Deno.test("similarity is the Dice coefficient of content words, figures and function words left out", () => {
  const a = contentWords("Want me to suggest two easy ways to close the 40 g protein gap?");
  const b = contentWords("Should I suggest two simple ways to close your protein gap?");
  assertEquals(similarity(a, a), 1);
  assertEquals(similarity(a, new Set()), 0);
  assertEquals(similarity(a, b) > 0.7, true);
  assertEquals(similarity(a, contentWords("How did your last session feel?")), 0);
});

Deno.test("the same closing question, reworded, is a repeat; a new one is not", () => {
  for (
    const question of [
      "Want me to suggest two easy ways to close the protein gap?",
      "Should I suggest two simple ways to close your protein gap?",
      "Do you want two quick ways to close the protein gap?",
    ]
  ) {
    assertEquals(
      repeatsOf(`Sleep is steady this week. ${question}`, base).closing,
      question,
      question,
    );
  }
  for (
    const question of [
      "How did your legs feel after yesterday's session?",
      "Do you want to move leg day to Friday?",
      "Is your sleep better since the weekend?",
    ]
  ) {
    assertEquals(repeatsOf(`Sleep is steady this week. ${question}`, base).closing, null, question);
  }
});

Deno.test("a short closing question is never a repeat", () => {
  const short = { previousReply: "Fine. How is your sleep?", referralNeeded: false };
  assertEquals(repeatsOf("Fine. How is your sleep?", short).closing, null);
});

Deno.test("a sentence said again is a repeat only when it is long and nearly word for word", () => {
  const again = repeatsOf(
    "Your calorie target stays the same this week while we watch how your weight trend settles. Training is on track.",
    base,
  );
  assertEquals(again.sentences, [
    "Your calorie target stays the same this week while we watch how your weight trend settles.",
  ]);
  assertEquals(repeatsOf("Your calorie target changes next week.", base).sentences, []);
  assertEquals(
    repeatsOf("Training is on track.", { ...base, previousReply: "Training is on track." })
      .sentences,
    [],
  );
});

Deno.test("safety wording is never a repeat", () => {
  const earlier = {
    previousReply:
      "If the pain gets worse, see a doctor or physio before you train that area again. Want me to plan around it?",
    referralNeeded: true,
  };
  assertEquals(
    repeatsOf(
      "If the pain gets worse, see a doctor or physio before you train that area again.",
      earlier,
    ).sentences,
    [],
  );
  // Without a need for it, the same line is an ordinary repeat.
  assertEquals(
    repeatsOf(
      "If the pain gets worse, see a doctor or physio before you train that area again.",
      { ...earlier, referralNeeded: false },
    ).sentences.length,
    1,
  );
  // Urgent wording always stands.
  assertEquals(isSafetyWording("If it gets worse call your local emergency number.", false), true);
  assertEquals(isSafetyWording("Want me to suggest a doctor-approved snack plan?", false), false);
});

Deno.test("asking the same thing again is not a repeat", () => {
  const input = {
    previousReply: "Add a shake. Want me to suggest two easy ways to close the protein gap?",
    previousQuestion: "How can I close my protein gap?",
    question: "how do I close the protein gap",
    referralNeeded: false,
  };
  assertEquals(repeatsOf(input.previousReply, input).closing, null);
  assertEquals(
    repeatsOf(input.previousReply, { ...input, question: "What about my sleep?" }).closing !== null,
    true,
  );
});
