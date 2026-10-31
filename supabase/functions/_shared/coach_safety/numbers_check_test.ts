import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { numberGroundOf, ungroundedNumbers } from "./numbers_check.ts";
import { ownerContext, ownerGoalPhasePayload } from "./fixtures.ts";
import { renderCoachContextParts } from "../providers/coach_chat_provider.ts";
import { renderGoalPhasePayload } from "../coach_context/contributors/goal_phase.ts";

const goalPhase = renderGoalPhasePayload(ownerGoalPhasePayload, "2026-10-14")!;
const file = renderCoachContextParts(ownerContext(), 96_000).file;
const ground = (question = "How am I doing?") => numberGroundOf([file, goalPhase, question]);
const missing = (answer: string, question?: string) => ungroundedNumbers(answer, ground(question));

// The two production replies for the owner's case (180 cm, 74.4 kg, fat loss, no target).
const badReply =
  "If you keep the current pace of about -0.62 kg/week, that's roughly 71.5 kg in 4 weeks and about 66.5 kg in 12 weeks.";
const goodReply =
  "Over the goal phase since 2026-07-04 you've gone from about 86.2 kg to 74.4 kg, a loss of 11.8 kg (13.7%) over 14.6 weeks, and your BMI is now about 23. Your recent pace is -0.62 kg/week over the last 4 weeks. Nutrition is logged on only 1 of the last 7 days, and 3 sessions in the last 7 days against 6 planned. If the weird feeling continues, please see a doctor.";

Deno.test("the production reply that projected weights has figures the data does not hold", () => {
  const found = missing(badReply);
  assert(found.includes("71.5"), found.join());
  assert(found.includes("66.5"), found.join());
  assert(found.includes("12"), found.join());
  assert(!found.includes("0.62"), "the pace is in the data");
});

Deno.test("the production reply that quoted the goal phase is fully grounded", () => {
  assertEquals(missing(goodReply), []);
});

Deno.test("rounding: a reply may round a figure to the digits it writes", () => {
  assertEquals(missing("You are about 74 kg."), []);
  assertEquals(missing("Your weight is 74.4 kg."), []);
  assertEquals(missing("About 14% of your starting weight."), []);
  assertEquals(missing("Your pace is around -0.6 kg/week."), []);
  assertEquals(missing("You lost 11.8 kg."), []);
  // Not a rounding of anything the athlete was given.
  assertEquals(missing("You lost 11.2 kg."), ["11.2"]);
  assertEquals(missing("Your pace is -0.9 kg/week."), ["0.9"]);
});

Deno.test("rounding: a rounded large figure matches within half its step, at most 5%", () => {
  // The target is 2000 kcal.
  assertEquals(missing("Your target is 2,000 kcal."), []);
  assertEquals(missing("Your target is about 2000 kcal."), []);
  assertEquals(missing("Aim for 1,800 kcal."), ["1,800"]);
  assertEquals(missing("Aim for 2,200 kcal."), ["2,200"]);
});

Deno.test("the athlete's own figures are theirs to repeat", () => {
  assertEquals(missing("Yes, 72 kg is reachable later.", "Can I get to 70 kg?"), ["72"]);
  assertEquals(missing("Yes, 70 kg is a fair target to talk about.", "Can I get to 70 kg?"), []);
  assertEquals(missing("1,500 kcal is too low for you.", "Can I eat 1,500 kcal?"), []);
});

Deno.test("harmless numbers are not checked", () => {
  assertEquals(
    missing(
      "Here is what I'd do:\n1. Keep your 3 sessions this week.\n2. Eat the 2nd meal earlier.\n3. Sleep well.\nOne question: how do you feel at 7:30 in the morning? Try 3 sets of 8-12 reps with 90 seconds rest, 3x10 for accessories, RPE 8. You have 2 options.",
    ),
    [],
  );
  assertEquals(missing("In 2026 we will see. That is 24/7 work."), []);
});

Deno.test("general guidance with units is a claim the context must hold", () => {
  assertEquals(missing("Aim for 1.6 g of protein per kg."), ["1.6"]);
  assertEquals(missing("Walk 45 minutes a day."), ["45"]);
  assertEquals(missing("Sleep 8 hours."), ["8"]);
  assertEquals(missing("Your 8-week trend is -0.72 kg/week."), []);
  assertEquals(missing("Rest 2 minutes between sets."), []);
  assertEquals(missing("Drink 3 litres of water."), []);
});

Deno.test("counts above ten and decimals need the data; small counts do not", () => {
  assertEquals(missing("You trained 12 times."), ["12"]);
  assertEquals(missing("You trained 4 times."), []);
  assertEquals(missing("About 2.5 sessions."), ["2.5"]);
});

Deno.test("dates must be dates the athlete was given", () => {
  assertEquals(missing("Since 2026-07-04 you have lost weight."), []);
  assertEquals(missing("Since 2026-07-05 you have lost weight."), ["2026-07-05"]);
  assertEquals(missing("Your last weigh-in was Oct 14."), []);
  assertEquals(missing("Your last weigh-in was Oct 12."), ["oct 12"]);
  assertEquals(missing("On 14 Oct you weighed in."), []);
});

Deno.test("the conversation never grounds a figure; the athlete's earlier messages do", () => {
  const withMemory = ownerContext({
    recent_messages: [
      { role: "assistant", content: "You will lose 9.7 kg by spring." },
      { role: "user", content: "I weigh 90.5 kg on my old scale." },
    ],
  });
  const { file: memoryFile } = renderCoachContextParts(withMemory, 96_000);
  assert(!memoryFile.includes("9.7"));
  const given = numberGroundOf([memoryFile, "I weigh 90.5 kg on my old scale."]);
  assertEquals(ungroundedNumbers("You will lose 9.7 kg.", given), ["9.7"]);
  assertEquals(ungroundedNumbers("Your old scale said 90.5 kg.", given), []);
});

Deno.test("negative signs and thousands separators are read, not guessed", () => {
  assertEquals(missing("About -0.72 kg/week over 8 weeks."), []);
  assertEquals(missing("Volume was 9,800 kg last week."), []);
  assertEquals(missing("Volume was 9,000 kg last week."), ["9,000"]);
});

Deno.test("a year-like figure with a unit or an energy context is a measurement, not a year", () => {
  const given = numberGroundOf(["Target 1800 kcal and 74.4 kg."]);
  const missingIn = (answer: string) => ungroundedNumbers(answer, given);
  // Measurements that look like years.
  assertEquals(missingIn("Aim for 2000 kcal a day."), ["2000"]);
  assertEquals(missingIn("Eat 1950 calories."), ["1950"]);
  assertEquals(missingIn("About 2020 g of food."), ["2020"]);
  assertEquals(missingIn("Walk 2000 steps more."), ["2000"]);
  assertEquals(missingIn("Eat around 2000 a day."), ["2000"]);
  assertEquals(missingIn("Stay under 2100."), ["2100"]);
  assertEquals(missingIn("A target of 1999 kcal works."), ["1999"]);
  assertEquals(missingIn("You weigh 1990 g less."), ["1990"]);
  // Real years and dates are not measurements.
  assertEquals(missingIn("Since 2025 you trained a lot."), []);
  assertEquals(missingIn("In 2026 you started."), []);
  assertEquals(missingIn("It was March 2026 when you began."), []);
  assertEquals(missingIn("By 2027 the goal may be near."), []);
  assertEquals(missingIn("On 2026-07-04 you began."), ["2026-07-04"]);
  // A given measurement that looks like a year grounds the same figure with its unit.
  assertEquals(missingIn("Aim for 1800 kcal a day."), []);
});

Deno.test("a figure with no unit matches a given figure of any unit", () => {
  const given = numberGroundOf(["Latest 74.4 kg; 54 completed sets."]);
  assertEquals(ungroundedNumbers("You are at 74.4.", given), []);
  assertEquals(ungroundedNumbers("You did 54 in total.", given), []);
  assertEquals(ungroundedNumbers("You did 54 sessions.", given), []);
  assertEquals(ungroundedNumbers("You did 54 kg.", given), ["54"]);
});

Deno.test("ranges give both ends the unit of the end: a digest range grounds its lower figure", () => {
  const given = numberGroundOf([
    "Protein: about 1.4 to 2.0 g per kg a day; 150 to 300 minutes a week.",
  ]);
  assertEquals(ungroundedNumbers("Aim for 1.4 g per kg.", given), []);
  assertEquals(ungroundedNumbers("Aim for 2.0 g per kg.", given), []);
  assertEquals(ungroundedNumbers("About 150 minutes a week.", given), []);
  assertEquals(ungroundedNumbers("About 1.4 kg of protein.", given), ["1.4"]);
});

Deno.test("the length of a session item in a plan is advice, not a claim about the athlete", () => {
  for (
    const reply of [
      "Day 1: 30 min easy walk.",
      "Walk for 30 minutes after dinner.",
      "Walk for 20-30 minutes.",
      "Do a 45-minute session in the hotel gym.",
      "Finish with 10 min of stretching.",
      "Day 3: 20 minutes of mobility and a 15 min brisk walk.",
      "Warm up for 10 minutes.",
      "Walk 20 min after dinner.",
      "Jog 15 minutes, then stretch.",
      "You can walk 30 min after dinner.",
      "You should do a 30-minute walk after dinner.",
      "Try 20 minutes of easy cycling.",
      "Do a 30-minute walk after dinner.",
    ]
  ) {
    assertEquals(missing(reply), [], reply);
  }
});

Deno.test("a duration that is not a round session item still has to be in the data", () => {
  for (
    const [reply, figure] of [
      ["You slept 450 minutes.", "450"],
      ["Your walk was 30 min.", "30"],
      ["You did a 30 minute walk yesterday.", "30"],
      ["Last week you did 45 min of cardio.", "45"],
      ["Walk 37 minutes.", "37"],
      ["Do a 120 minute session.", "120"],
      ["Walk for 45 hours.", "45"],
      ["Sleep 8 hours.", "8"],
      ["Walk 45 minutes a day.", "45"],
      ["You normally walk 45 minutes after dinner.", "45"],
      ["You usually do a 45 minute walk.", "45"],
      ["Your plan is a 45-minute walk after dinner.", "45"],
      ["Your plan has a 30 min walk on Tuesday.", "30"],
      ["Your warm-up is 10 minutes of easy cycling.", "10"],
      ["You walk 45 minutes after dinner.", "45"],
      ["Walk 30 minutes every morning.", "30"],
      ["Do a 20 min walk each evening.", "20"],
      ["Jog 20 min per session.", "20"],
      ["Walk 30 minutes nightly.", "30"],
      ["Walk 30 minutes three times a week.", "30"],
      ["Walk 30 minutes every other day.", "30"],
      ["Your average walk is 30 min.", "30"],
      ["Your last walk was 30 min.", "30"],
      ["Do a 30 min walk daily.", "30"],
    ] as const
  ) {
    assertEquals(missing(reply), [figure], reply);
  }
});

// Captured from the answer bank on 2026-10-24: each figure passed in its own sentence and failed
// once the reply's other lines (a reasoning step, a follow-up) were joined after or before it.
Deno.test("a figure's unit is read within its own line, and a range's unit across a line break", () => {
  const ground = numberGroundOf([
    "Latest weight 74.8 kg on 2026-10-13.",
    "[source: jager_2017_protein] about 1.4 to 2.0 g per kg a day for people who train.",
  ]);
  assertEquals(ungroundedNumbers("Latest reading and BMI\n74.8 kg on 2026-10-13", ground), []);
  assertEquals(
    ungroundedNumbers("1.4 to 2.0 g per kg a day\nPlateau point from meta-analysis", ground),
    [],
  );
  // The unit still decides: a BMI on the figure's own line is a BMI, and a gram range is not kcal.
  assertEquals(ungroundedNumbers("Your BMI is 74.8", ground), ["74.8"]);
  assertEquals(ungroundedNumbers("1.4 to 2.0 kcal per kg\nmore", ground), ["1.4", "2.0"]);
});

// Round 2 (hostile review of #177): the next line never lends a figure its unit, and a figure alone
// on its line keeps the measurement label that ends the line before.
Deno.test("a range takes no unit from the next line; a lone figure keeps the label above it", () => {
  const ground = numberGroundOf(["Protein 35 g at lunch."]);
  assertEquals(ungroundedNumbers("Body fat estimate: 25-28\nReps: 8-10 per set", ground), [
    "25",
    "28",
  ]);
  assertEquals(ungroundedNumbers("Your BMI:\n35", ground), ["35"]);
  assertEquals(ungroundedNumbers("Protein:\n35 g", ground), []);
});
