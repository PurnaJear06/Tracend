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
  const referral =
    "Talk to your doctor before you change your supplements or your usual routine this week.";
  const earlier = {
    previousReply: `${referral} Want me to plan around it?`,
    referralNeeded: true,
  };
  // A referral line stands when the turn needs one, and is an ordinary repeat when it does not.
  assertEquals(repeatsOf(referral, earlier).sentences, []);
  assertEquals(repeatsOf(referral, { ...earlier, referralNeeded: false }).sentences, [referral]);
  // A stop rule for pain or another symptom always stands, on any turn.
  const stopRule = "If the knee pinches or swells, stop the set and rest it for the day.";
  const pain = { previousReply: `${stopRule} Want me to plan around it?`, referralNeeded: false };
  assertEquals(repeatsOf(stopRule, pain).sentences, []);
  assertEquals(
    repeatsOf("Sharp pain on any rep means stop, rest and see a physio before you train again.", {
      previousReply:
        "Sharp pain on any rep means stop, rest and see a physio before you train again.",
      referralNeeded: false,
    }).sentences,
    [],
  );
  // Any caution or limit stands when the turn needs referral wording.
  const limit = "Never push through the last rep if your form breaks down on the way up.";
  assertEquals(repeatsOf(limit, { previousReply: limit, referralNeeded: true }).sentences, []);
  assertEquals(repeatsOf(limit, { previousReply: limit, referralNeeded: false }).sentences, [
    limit,
  ]);
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

Deno.test("more ways to say stop for a symptom are never repeats", () => {
  for (
    const rule of [
      "If the knee aches, end the session and go home.",
      "When your shoulder flares up, ease off and rest it for the day.",
      "If the back aches at all, pull back and leave the heavy pulls out this week.",
      "If the knee hurts, call it a day and rest it properly tonight.",
    ]
  ) {
    assertEquals(
      repeatsOf(rule, {
        previousReply: `${rule} Want me to plan around it?`,
        referralNeeded: false,
      })
        .sentences,
      [],
      rule,
    );
  }
});

Deno.test("an opposite sentence is not a repeat: negation is kept", () => {
  const plain = "Should we increase training volume this week?";
  const opposite = "Should we not increase training volume this week?";
  assertEquals(similarity(contentWords(plain), contentWords(opposite)), 0);
  assertEquals(similarity(contentWords(plain), contentWords(plain)), 1);
  assertEquals(
    repeatsOf(`Sleep is steady. ${opposite}`, {
      previousReply: `Fine. ${plain}`,
      referralNeeded: false,
    })
      .closing,
    null,
  );
  assertEquals(
    repeatsOf(`Sleep is steady. ${plain}`, {
      previousReply: `Fine. ${plain}`,
      referralNeeded: false,
    })
      .closing,
    `${plain}`,
  );
  for (
    const [a, b] of [
      [
        "Do increase the weekly training volume across all your upper days.",
        "Don't increase the weekly training volume across all your upper days.",
      ],
      [
        "You can skip the warm-up sets on your accessory movements today.",
        "You can't skip the warm-up sets on your accessory movements today.",
      ],
      [
        "Eat protein before training sessions on your heaviest leg days.",
        "Never eat protein before training sessions on your heaviest leg days.",
      ],
    ]
  ) {
    assertEquals(repeatsOf(a, { previousReply: b, referralNeeded: false }).sentences, [], a);
  }
});
