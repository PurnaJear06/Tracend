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
