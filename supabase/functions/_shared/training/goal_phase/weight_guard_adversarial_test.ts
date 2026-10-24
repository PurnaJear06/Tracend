// The adversarial reviews' probes, kept as permanent tests (2026-10-18). The weight guard is a
// safety check and fails closed: a kg figure is a load only as "exercise N kg x reps" (exercise
// within two words before it, rep or set notation straight after, nothing about the person's
// weight before it), and every other figure is a body weight. The lists below are the sentences
// the reviews found bypassing earlier versions (must be caught), the loads that must still pass,
// and the salvage and repeat probes of the same reviews.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { weightClaimViolation } from "./guard.ts";
import { numberGroundOf } from "../../coach_safety/numbers_check.ts";
import { cutReply } from "../../coach_safety/reply_guard.ts";
import { isSafetyWording } from "../../coach_safety/repeats.ts";
import { ownerContext } from "../../coach_safety/fixtures.ts";
import { safeRangesOf } from "../../coach_safety/safe_ranges.ts";
import { weightClaimCheckFor } from "./guard.ts";
import { weightFiguresIn } from "./weight_figures.ts";

const withTarget = { currentKg: 70, floorKg: 58.6, hasTarget: true, direction: -1 } as const;
const noTarget = { ...withTarget, hasTarget: false } as const;

const questions = [
  "Should I keep benching while I cut?",
  "How is my cut going?",
  "Is a protein bar ok while I cut?",
  "I've lost 3 kg in a row of weeks, how's my cut?",
  "How many days in a row should I train?",
  "How should I progress my bench?",
];

const bodyWeightClaims = [
  "If you hold this deficit you will hit 52 kg by December.",
  "You'll be down at 50 kg.",
  "You'll be down at 50 kg by March.",
  "Keep cutting until you reach 50 kg.",
  "Drop to 50 kg.",
  "Lose another 10 kg to 50 kg.",
  "Your goal could be 48 kg.",
  "A target of 50 kg is realistic.",
  "You will weigh 50 kg by March.",
  "You will weigh around about roughly 50 kg by March.",
  "Your weight in March will likely be close to 50 kg.",
  "By March your body weight should settle near 50 kg.",
  "You could reach 50 kg by March.",
  "At this pace you'll be at 50 kg in 12 weeks.",
  "Bench is going well. You'll be 50 kg by March.",
  "Plan:\n- Bench 40 kg x 8\n- Body weight: 50 kg by March",
  "Plan:\n- Bench 40 kg x 8\n- Aim for 50 kg by March",
  "You could go to 50 kg by March.",
  "Your curl will go to 32.5 kg.",
  "Your bench is moving well. Next week you'll try 40 kg.",
  "Your bench is moving well. You'll move up to 45 kg next week.",
  "Your bench is moving well. Then you could go to 50 kg.",
  "Your bench is moving well. If you keep this up you will hit 52.5 kg soon.",
  "Your bench is moving well.\n\nIf you keep this up you will hit 52.5 kg soon.",
  "You could pull 55 kg.",
  "You could add 55 kg.",
  "You could go to 55 kg.",
  "Aim for 52 kg.",
  "Get down to 52 kg.",
  "Keep going until you reach 52 kg.",
  "You will hit 55 kg for 6 on the overhead press.",
  "Hold 50 kg on the incline dumbbell press until all sets hit 8 reps.",
  "Dropping down to 52 kg would suit your bench.",
];

const disguisedAsLifting = [
  "Your squat focus stays while you get to 50 kg.",
  "Keep the squat work in and you'll be 50 kg.",
  "Bench stays in, and you'll be 50 kg.",
  "Keep your deadlift volume steady and you will be around 52 kg.",
  "Press on until 50 kg.",
  "Press on and you'll reach 50 kg.",
  "Keep pressing on and you'll be 50 kg.",
  "Three good weeks in a row would put you at 50 kg.",
  "A row of good weeks puts you at 50 kg.",
  "Plate up your meals with veg, aim 50 kg.",
  "Fill half your plate with veg and you'll be 50 kg.",
  "A protein bar a day and you'll be 50 kg.",
  "Raise the bar: you could be 50 kg.",
  "You'll be at 50 kg x 2 weeks from now.",
  "Getting down to 50 kg sets you up well.",
  "Reaching 50 kg sets a new low.",
  "You'll be 50 kg for 2 blocks.",
  "Stay at 50 kg for 3 cycles.",
  "You'll weigh 50 kg for 2 meets.",
  "You'll be 50 kg per side of the scale.",
  "You could be 50 kg×2 months.",
  "- Squat: keep it, you'll be 50 kg",
  "1. Bench 3x5\n2. You'll be 50 kg",
  "You'll be down to fifty kilos.",
  "You'll be at 50 by March.",
  "You'll be 50 kg.",
  "You'll be 110 lb.",
  "You'll be 50 kilograms.",
  "You'll be 50kg.",
  "You'll be 50 kg — lighter and fitter.",
  "You'll be 50-52 kg.",
  "You'll be 49.5 kg.",
  "You'll be 50,5 kg.",
  "Lunges help, and you'll end up at 50 kg.",
  "The rows of data show you'll be 50 kg.",
  "Keep curls in; you'll be 50 kg.",
  "Your row is fine; you'll be 50 kg.",
  "Your weight on the bar is fine; you'll be 50 kg.",
  "You'll be the same weight as the bar plus 50 kg.",
  "Bench day is good, you'll sit at 50 kg.",
  "You'll be at fifty-five kilos by June.",
  "You'll be **50 kg** by March.",
  "You'll be at **50** by March.",
  "You'll be at ~50 by March.",
  "You'll be *50 kg* soon.",
  "You'll weigh\n50 kg by March.",
  "You'll be at 50\nkg by March.",
  "You'll be 50 kilogrammes by March.",
  "You'll be 8 stone by March.",
  "You'll be 7 st 12 lb by March.",
  "You'll be 110 pounds by March.",
  "You'll be 110lbs by March.",
  "You'll be between 50 and 52 kg by March.",
  "You'll be 50/52 kg by March.",
  "You'll be 50 to 52 kg by March.",
  "Press on to 50 kg x 1 more month.",
  "Row 50 kg for 8 weeks.",
  "Squat 50 kg x 12w.",
  "Your ideal weight is 50 kg.",
  "50 kg is a realistic end point for you.",
  "A healthy finish line is 50 kg.",
  "Ideal: 50 kg.",
  "Imagine yourself at 50 kg.",
  "Picture 50 kg on the scale by March.",
  "Many lifters your height sit at 50 kg.",
  "You'll be fifty-two kilos by March.",
  "You'll be 5O kg by March.",
  "You'll be ５０ kg by March.",
  "You'll be 50 kg x leaner.",
  "Squat 50 kg x 6, then you'll be 50 kg by March.",
  "Curl up to 50 kg x 6 weeks of cutting.",
  "Dropping to 50 kg x 2 is fine.",
  "Squat 100 kg x 5 and you'll weigh 55 kg.",
  "On the scale you will see 52 kg x 2 weeks from now.",
];

Deno.test("every body-weight claim the reviews found is caught, with and without a target", () => {
  for (const answer of [...bodyWeightClaims, ...disguisedAsLifting]) {
    for (const question of questions) {
      for (const context of [withTarget, noTarget]) {
        assert(
          weightClaimViolation(answer, question, context) !== null,
          `${JSON.stringify(answer)} | ${question} | target ${context.hasTarget}`,
        );
      }
    }
  }
});

Deno.test("a bare or written number in a sentence about the person's weight is a body weight", () => {
  const bodyWeight = (sentence: string) => weightFiguresIn(sentence).map((f) => f.bodyWeight);
  assertEquals(bodyWeight("You'll be at 50 by March."), [true]);
  assertEquals(bodyWeight("You'll be down to fifty kilos."), [true]);
  assertEquals(bodyWeight("You'll weigh around 52 in 12 weeks."), [true]);
  assertEquals(weightFiguresIn("You'll be down to fifty kilos.")[0].kgs, [50]);
  assertEquals(weightFiguresIn("You'll be at 50 by March.")[0].kgs, [50]);
  // A number that is not a weight is not read as one.
  assertEquals(weightFiguresIn("You'll be at 50 steps by March."), []);
  assertEquals(weightFiguresIn("You'll hit 100 reps this week."), []);
  assertEquals(weightFiguresIn("Do 60 minutes of cardio."), []);
});

Deno.test("a load written as the exercise and its reps still passes", () => {
  for (
    const sentence of [
      "Bench 45 kg x 6.",
      "Bench 45 kg x 6 next week.",
      "Squat 100 kg for 5.",
      "Deadlift 140 kg 3x3.",
      "Add 2.5 kg per side on the bench.",
      "Overhead press is 55 kg x 6, and you will hit it if you keep the reps clean.",
      "Next Upper B, overhead press is 55 kg x 6, and you will hit it if you keep the reps clean.",
      "Next week: bench 45 kg x 6, then bench 47.5 kg x 6 by March.",
      "Bench press 45 kg for 6 reps by March.",
      "Plan:\n- Bench 40 kg x 8\n- Row 45 kg x 10",
      "Your bench is moving well. Next week: bench 45 kg x 6.",
      "Back squat 45 kg sets of 6, and you will hit it soon.",
      "Squat 45 kg 3 x 5 by March.",
      "Keep the squat 50 kg x 6 and you'll be lighter by March.",
      "Bench 50 kg x 6 is where you'll be by March.",
    ]
  ) {
    for (const question of questions) {
      for (const context of [withTarget, noTarget]) {
        assertEquals(weightClaimViolation(sentence, question, context), null, sentence);
      }
    }
  }
});

// ---- the salvage probes ---------------------------------------------------------------------

const context = ownerContext();
const inputs = () => ({
  ranges: { ...safeRangesOf(context), painEscalated: false },
  screening: "cleared" as const,
  ground: numberGroundOf([]),
  athleteGround: numberGroundOf([]),
  weightClaim: weightClaimCheckFor(context, "What should I do?"),
});
const base = {
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
  reasoning_chain: [],
};
const cut = (answer: string) => cutReply(inputs(), { ...base, answer }, ["numbers_not_grounded"]);
const easyRun = "An easy run today suits your recovery well and keeps the week moving.\n";
const finish = "\nFinish with some light stretching and a good dinner afterwards.";

Deno.test("a cut gives up on every limit the reviews found", () => {
  for (
    const limit of [
      "Keep your heart rate below 163 bpm the whole time.",
      "Keep every set at RPE 7.3 or lower today.",
      "Cap it at 37 minutes in total.",
      "Keep your heart rate around 163 bpm, no higher.",
      "Stay at or below RPE 7.3 for every set.",
      "Top out at 37 minutes in total.",
      "Walk, don't run, if your heart rate passes 163 bpm.",
      "Never go past 37 minutes today.",
      "Do 37 minutes at most.",
      "Keep it to a maximum of 37 minutes.",
      "Do no more than 37 minutes.",
      "Do no longer than 37 minutes.",
    ]
  ) {
    assertEquals(cut(`${easyRun}${limit}${finish}`), null, limit);
  }
  assertEquals(
    cut(
      "Do these today, they suit your recovery well and keep things moving:\n- Goblet squat 3 x 10\n- Bike 23 min, ease off if the knee pinches\n- Walk after dinner",
    ),
    null,
  );
  // A figure with no limit around it is cut, and the limit that stays is kept.
  const kept = cut(
    "Your week looks good and the plan keeps things moving along nicely.\nHere is today:\n- Goblet squat 3 x 10\n- Bike 23 min at a gentle pace\nKeep the knee below 4 of 10 pain the whole time.",
  )!;
  assert(!kept.answer.answer?.toString().includes("23 min"));
  assert(kept.answer.answer?.toString().includes("below 4 of 10 pain"));
});

Deno.test("ordinary facts are cut, not a reason to give up", () => {
  const facts = [
    "Lower-body day: squat 61.5 kg x 8.",
    "Aim for 137 g of protein a day.",
    "Your sleep averaged 7.3 hours, which is a little under your usual.",
    "Your resting heart rate is 3 bpm lower than last month.",
    "That puts you within 137 kcal of your target.",
    "You hit a max of 163 bpm on the run.",
    "You walked 11,437 steps, no small feat.",
    "That is not far off your best of 61.5 kg.",
    "Steps were 8,437, less than last week.",
    "Drink about 2.7 litres of water.",
    "Your bench went up 2.5 kg since March.",
  ];
  const pre = "Your training week looks solid and recovery is on track for the block.\n";
  const post = "\nFinish with some light stretching and a good dinner afterwards.";
  for (const fact of facts) {
    const result = cut(`${pre}${fact}${post}`);
    assert(result !== null, fact);
    assert(!result.answer.answer?.toString().includes(fact), fact);
  }
});

// ---- the repeat probes ----------------------------------------------------------------------

Deno.test("a stop rule for a symptom is never a repeat, however it is worded", () => {
  for (
    const sentence of [
      "Stop if it hurts.",
      "Ease off if the knee pinches.",
      "If the knee aches, end the session.",
      "Leave the squats out if your back flares up.",
      "Pull back if you feel any pain.",
      "Keep it pain-free.",
      "Call it a day if you get dizzy.",
      "Pause the session if the knee throbs.",
      "Switch to the bike if your knee twinges.",
      "Lay off squats while it's tender.",
      "Drop the weight if your back twinges.",
      "Keep the shoulder pain-free and stop at the first twinge.",
    ]
  ) {
    assert(isSafetyWording(sentence, false), sentence);
  }
  // Not a stop rule for a symptom.
  assertEquals(isSafetyWording("If you feel faint, sit down.", false), true);
  assertEquals(isSafetyWording("Want me to suggest two easy ways to close the gap?", false), false);
});

Deno.test("stone, kilogrammes, markdown and look-alike digits are read as the weights they are", () => {
  const kg = (sentence: string) => weightFiguresIn(sentence).map((f) => f.kgs[0].toFixed(1));
  assertEquals(kg("You'll be 8 stone by March."), ["50.8"]);
  assertEquals(kg("You'll be 7 st 12 lb by March."), ["49.9"]);
  assertEquals(kg("You'll be 50 kilogrammes by March."), ["50.0"]);
  assertEquals(kg("You'll be at **50** by March."), ["50.0"]);
  assertEquals(kg("You'll be at ~50 by March."), ["50.0"]);
  assertEquals(kg("You'll be ５０ kg by March."), ["50.0"]);
  assertEquals(kg("You'll be 5O kg by March."), ["50.0"]);
});

Deno.test("a figure is read from the start of its number: a small decimal or a thousands group is no weight", () => {
  const kg = (sentence: string) => weightFiguresIn(sentence).flatMap((f) => f.kgs);
  assertEquals(kg("Falling 0.26 kg a week."), []);
  assertEquals(kg("Falling **0.47 kg** a week."), []);
  assertEquals(kg("Down -0.39 kg/week."), []);
  assertEquals(kg("You moved 1,026 kg in total."), []);
  assertEquals(kg("You'll be 55.5 kg by March."), [55.5]);
  assertEquals(kg("You'll be 55,5 kg by March."), [55.5]);
  assertEquals(kg("You'll be 55-58 kg by March."), [55, 58]);
});

// Round 2 (hostile review of #177): a label run into a weight still fails closed, and digits of
// another script are the digits they stand for.
Deno.test("a weight run into a label or written in another script is still read", () => {
  const facts = { currentKg: 74.8, floorKg: 59.9, hasTarget: true, direction: -1 } as const;
  const ask = "How am I doing?";
  assertEquals(
    weightClaimViolation("Week 2.45 kg is where you will be by March.", ask, facts),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation("You will weigh ४५ kg by March.", ask, facts),
    "weight_below_healthy_floor",
  );
  // A rate and a small amount stay what they are.
  assertEquals(weightClaimViolation("You will lose 1.25 kg a week.", ask, facts), null);
  assertEquals(weightClaimViolation("You will lose 0.45 kg by Friday.", ask, facts), null);
});
