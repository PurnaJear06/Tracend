import { assertEquals } from "jsr:@std/assert@1.0.14";
import { weightClaimCheckFor, weightClaimViolation } from "./guard.ts";
import { longCutContext } from "./fixtures.ts";

const noTarget = { currentKg: 74.8, floorKg: 59.9, hasTarget: false, direction: -1 } as const;
const withTarget = { ...noTarget, hasTarget: true } as const;

Deno.test("a trend projected into a future weight is refused when the goal has no target", () => {
  assertEquals(
    weightClaimViolation(
      "At this pace you would be at about 66.5 kg in 12 weeks.",
      "What should I do next?",
      noTarget,
    ),
    "projection_without_target",
  );
  assertEquals(
    weightClaimViolation("You could reach 68-70 kg by December.", "How am I doing?", noTarget),
    "projection_without_target",
  );
  assertEquals(
    weightClaimViolation("You will hit 150 lbs in two months.", "How am I doing?", noTarget),
    "projection_without_target",
  );
});

Deno.test("a weight below the healthy floor is refused even with a target", () => {
  assertEquals(
    weightClaimViolation("You will be at 55 kg in 10 weeks.", "How am I doing?", withTarget),
    "weight_below_healthy_floor",
  );
});

Deno.test("history, warnings, targets and the athlete's own numbers pass", () => {
  const ask = "How am I doing?";
  for (
    const sentence of [
      "You went from 90 kg to 74.8 kg in 19 weeks.",
      "Your weight is 74.8 kg today.",
      "Do not go below 60 kg in the next 6 weeks.",
      "You lost 15 kg over the goal phase.",
      "Since 3 June your recorded weight went from 90 kg to 74.8 kg over 19 weeks, 15.2 kg in all.",
      "Your goal phase started at 83 kg on 9 July and you are at 74.8 kg today.",
      "You would be at 75 kg if you hold this week.",
    ]
  ) {
    assertEquals(weightClaimViolation(sentence, ask, noTarget), null, sentence);
  }
  assertEquals(
    weightClaimViolation("You will reach 70 kg in 6 weeks.", "When will I reach 70 kg?", noTarget),
    null,
  );
  assertEquals(
    weightClaimViolation(
      "At this pace you will reach 70 kg in 6 weeks.",
      "How am I doing?",
      withTarget,
    ),
    null,
  );
});

Deno.test("a rising trend is checked in the other direction, and a flat one never", () => {
  const gain = { ...noTarget, currentKg: 70, direction: 1 } as const;
  assertEquals(
    weightClaimViolation("You will be 74 kg in 8 weeks.", "How am I doing?", gain),
    "projection_without_target",
  );
  assertEquals(
    weightClaimViolation("You will be 68 kg in 8 weeks.", "How am I doing?", gain),
    null,
  );
  assertEquals(
    weightClaimViolation(
      "You will be 66 kg in 8 weeks.",
      "How am I doing?",
      { ...noTarget, direction: 0 },
    ),
    null,
  );
});

Deno.test("the check reads its facts from the prepared Coach context", () => {
  const check = weightClaimCheckFor(longCutContext, "What now?");
  assertEquals(
    check("Keep going and you will be at 66.5 kg in 12 weeks."),
    "projection_without_target",
  );
  assertEquals(check("Your weight is 74.8 kg and your BMI is 23."), null);
  const targeted = {
    ...longCutContext,
    active_goal: { goal_type: "fat_loss", details: { target_weight_kg: 70 } },
  };
  assertEquals(
    weightClaimCheckFor(targeted, "What now?")("At this pace you will reach 70 kg in 8 weeks."),
    null,
  );
});

Deno.test("asking for a target may name a weight; a forecast may not", () => {
  const ask = "How am I doing?";
  for (
    const sentence of [
      "Would something like 70 kg be a target you want to aim for?",
      "Many people at your height could aim for 70–72 kg.",
      "A goal weight of 72 kg would be a sensible place to start.",
      "What weight do you want to reach, maybe 72 kg?",
    ]
  ) {
    assertEquals(weightClaimViolation(sentence, ask, noTarget), null, sentence);
  }
  assertEquals(
    weightClaimViolation(
      "Aim for 66 kg and at this pace you will get there in 12 weeks.",
      ask,
      noTarget,
    ),
    "projection_without_target",
  );
});

Deno.test("a target suggestion below the healthy floor is still refused", () => {
  const ask = "How am I doing?";
  assertEquals(
    weightClaimViolation("Would 55 kg be a target you want to aim for?", ask, noTarget),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation("You could aim for 52 kg.", ask, withTarget),
    "weight_below_healthy_floor",
  );
});

Deno.test("a warning word only excuses the weight it governs", () => {
  const ask = "How am I doing?";
  assertEquals(
    weightClaimViolation(
      "If you don't change anything you will be at 66.5 kg in 12 weeks.",
      ask,
      noTarget,
    ),
    "projection_without_target",
  );
  assertEquals(
    weightClaimViolation(
      "Never let your weight fall under 60 kg, and at this rate you would be at 66 kg in 12 weeks.",
      ask,
      noTarget,
    ),
    "projection_without_target",
  );
  assertEquals(
    weightClaimViolation("Do not go below 60 kg in the next 6 weeks.", ask, noTarget),
    null,
  );
  assertEquals(
    weightClaimViolation("Stay under 75 kg, and avoid dropping below 60 kg.", ask, noTarget),
    null,
  );
});

Deno.test("a body weight with a cue is still read, next to a lift", () => {
  const ask = "How am I doing?";
  assertEquals(
    weightClaimViolation(
      "Your bench could reach 80 kg, and at this pace you will weigh 55 kg in 10 weeks.",
      ask,
      withTarget,
    ),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation("Keep lifting and you'll be at 55 kg in 10 weeks.", ask, withTarget),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation("You could get down to 52 kg by March.", ask, withTarget),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation("Your bodyweight will drop to 55 kg by summer.", ask, withTarget),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation("On the scale you should see 56 kg in 8 weeks.", ask, withTarget),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation("Your goal weight of 54 kg is possible in 12 weeks.", ask, withTarget),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation(
      "With the deadlift at 140 kg you will weigh 66 kg in 12 weeks.",
      ask,
      noTarget,
    ),
    "projection_without_target",
  );
});

Deno.test("projection and pace wording is a body-weight claim, and an unclear figure fails closed", () => {
  const ask = "How am I doing?";
  for (
    const sentence of [
      "At this pace, I would put you at 45 kg.",
      "On track for 48 kg by March.",
      "You are heading to 50 kg.",
      "Heading toward 52 kg if nothing changes.",
      "You'd land at 47 kg.",
      "That would leave you at 45 kg.",
      "If you keep this up, 49 kg is where it ends.",
      "Projected: 46 kg.",
      "The trend ends at 50 kg.",
      "45 kg is where this goes.",
      "Expect 44 kg soon.",
    ]
  ) {
    assertEquals(
      weightClaimViolation(sentence, ask, withTarget),
      "weight_below_healthy_floor",
      sentence,
    );
  }
  assertEquals(
    weightClaimViolation("At this pace, I would put you at 66 kg.", ask, noTarget),
    "projection_without_target",
  );
  // A clear load cue still clears the figure, even beside pace wording.
  assertEquals(
    weightClaimViolation("At this pace your squat reaches 50 kg x 8.", ask, withTarget),
    null,
  );
});

const lifting = "What is my next Upper B?";

Deno.test("a load attached to a lift in its own sentence is never read as a body weight", () => {
  for (
    const sentence of [
      "Next Upper B, overhead press is 55 kg x 6, and you will hit it if you keep the reps clean.",
      "Next Upper B, overhead press is 55 kg × 6, and you will hit it if you keep the reps clean.",
      "Curl 32.5 kg x 8.",
      "Your next target is 100 kg on the deadlift, and you will get there in 12 weeks.",
      "Aim for a 100 kg deadlift in 16 weeks.",
      "Your goal is a 100 kg deadlift by December.",
      "You will squat 55 kg per side by March.",
      "Load 20 kg plates and a 15 kg plate to make 55 kg on the bar.",
      "Two 25 kg plates plus the 20 kg bar gives you 70 kg.",
      "Drop the load to 50 kg for 8 reps on the back-off set.",
      "Back off to 40 kg for 10 reps, then work back up to 55 kg.",
      "Hold incline dumbbell press 50 kg x 8 until all sets hit 8 reps.",
      "Bench 45 kg x 6 next week.",
      "Add 32.5 kg per side next week.",
      "Squat 100 kg for 5.",
      "Deadlift 140 kg 3x3.",
      "Squat 3x5 at 50 kg.",
      "Do sets of 5 at 55 kg.",
      "Your squat will be 70 kg x 5 in 8 weeks if you keep adding weight.",
      "Plan:\n- Bench 40 kg x 8\n- Row 45 kg x 10",
    ]
  ) {
    assertEquals(weightClaimViolation(sentence, lifting, noTarget), null, sentence);
    assertEquals(weightClaimViolation(sentence, lifting, withTarget), null, sentence);
  }
});

Deno.test("a figure not attached to a lift in its own sentence is a body weight, whatever came before", () => {
  const cutting = "Should I keep benching while I cut?";
  const floor = { currentKg: 74.8, floorKg: 59.9, hasTarget: true, direction: -1 } as const;
  for (
    const answer of [
      "If you hold this deficit you will hit 52 kg by December.",
      "You'll be down at 50 kg.",
      "Keep cutting until you reach 50 kg.",
      "Your goal could be 48 kg.",
      "A target of 50 kg is realistic.",
      "You could reach 50 kg by March.",
      "Your weight in March will likely be close to 50 kg.",
      "Plan:\n- Bench 40 kg x 8\n- Aim for 50 kg by March",
      "Bench is going well. You'll be 50 kg by March.",
      "Your bench is moving well. Next week you'll try 40 kg.",
      "Your bench is moving well. You'll move up to 45 kg next week.",
      "Your bench is moving well. Then you could go to 50 kg.",
      "Your bench is moving well. If you keep this up you will hit 52.5 kg soon.",
      "Your bench is moving well.\n\nIf you keep this up you will hit 52.5 kg soon.",
      "Your bench is moving well.\nIf you keep this up you will hit 52.5 kg soon.",
      "You could go to 55 kg.",
      "You could pull 55 kg.",
      "You could add 55 kg.",
      "Your bench goal could be 48 kg by March.",
      "Dropping down to 52 kg would suit your bench.",
      "Drop to 50 kg.",
      "Lose a few more kilos to get to 55 kg.",
      "Aim for 52 kg.",
      "Get down to 52 kg.",
      "Keep going until you reach 52 kg.",
    ]
  ) {
    for (const ask of [cutting, "How should I progress my bench?"]) {
      assertEquals(weightClaimViolation(answer, ask, floor), "weight_below_healthy_floor", answer);
    }
  }
  // Written with its exercise and reps, the same load passes.
  for (
    const answer of [
      "Bench 45 kg x 6 next week.",
      "Next week, bench 40 kg x 8, then bench 45 kg x 6.",
      "Your bench is moving well. Next week: bench 45 kg x 6.",
    ]
  ) {
    assertEquals(
      weightClaimViolation(answer, "How should I progress my bench?", floor),
      null,
      answer,
    );
  }
});

// Captured from the answer bank on 2026-10-24: every one of these replies was refused as a body
// weight below the healthy floor, because "0.26 kg" was read as 26 kg, so the repair could not fix
// it and the athlete got the fallback.
Deno.test("a weekly rate written with a decimal is not a body weight", () => {
  const ask = "How's my weight trending this month?";
  for (
    const sentence of [
      "Over the last 4 weeks of readings it is falling **0.26 kg a week**, and over the last 8 weeks **0.39 kg a week**.",
      "Over the last 8 weeks of readings it dropped about **0.39 kg a week**, and over the last 4 weeks about **0.26 kg a week**.",
      "Here's where you are: **74.8 kg** on 2026-10-13, down **-0.26 kg/week** over the last 4 weeks of readings and **-0.39 kg/week** over the last 8.",
      "Your weight is **78.4 kg** on 2026-09-27, falling **0.47 kg a week** over the last 8 weeks of readings, and you've trained **4 sessions** in the last 7 days.",
      "You will lose 0.55 kg a week for the next 8 weeks.",
    ]
  ) {
    assertEquals(weightClaimViolation(sentence, ask, withTarget), null, sentence);
    assertEquals(weightClaimViolation(sentence, ask, noTarget), null, sentence);
  }
  // The rate's neighbour is still read: a body weight below the floor in the same sentence fails.
  assertEquals(
    weightClaimViolation(
      "You're losing 0.39 kg a week, so in 8 weeks you'll be at 55 kg.",
      ask,
      withTarget,
    ),
    "weight_below_healthy_floor",
  );
  assertEquals(
    weightClaimViolation("Keep going and you'll reach 55.5 kg by March.", ask, withTarget),
    "weight_below_healthy_floor",
  );
});
