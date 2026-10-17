import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import type { CoachChatAnswerBreak } from "../contracts/coach_chat_v1.ts";
import type { ScreeningOutcome } from "../training/screening/outcome.ts";
import { weightClaimCheckFor } from "../training/goal_phase/guard.ts";
import { numberGroundOf } from "./numbers_check.ts";
import { coachReplyCheck } from "./reply_guard.ts";
import { ownerContext, ownerGoalPhasePayload } from "./fixtures.ts";
import { safeRangesOf } from "./safe_ranges.ts";
import { renderCoachContextParts } from "../providers/coach_chat_provider.ts";
import { renderGoalPhasePayload } from "../coach_context/contributors/goal_phase.ts";

const context = ownerContext();
const file = renderCoachContextParts(context, 96_000).file;
const goalPhase = renderGoalPhasePayload(ownerGoalPhasePayload, "2026-10-14")!;

function check(answer: string, options: { screening?: ScreeningOutcome; question?: string } = {}) {
  const question = options.question ?? "What should I do?";
  const result = coachReplyCheck({
    ranges: safeRangesOf(context),
    screening: options.screening ?? "cleared",
    ground: numberGroundOf([file, goalPhase, question]),
    weightClaim: weightClaimCheckFor(context, question),
  })(answer);
  return result as CoachChatAnswerBreak | null;
}

const broken = (answer: string, options?: Parameters<typeof check>[1]) =>
  check(answer, options)?.rules ?? [];

Deno.test("an honest reply from the data passes every rule", () => {
  assertEquals(
    check(
      "You've lost 11.8 kg since 2026-07-04, and your pace is -0.62 kg/week. **Keep your calories near 2000 kcal** and log your meals. Want to set a target on Progress?",
    ),
    null,
  );
});

Deno.test("calories_below_floor: advising a daily intake under the floor", () => {
  // The floor for this athlete is 1719 kcal (his resting energy; the sex minimum is 1500).
  assertEquals(safeRangesOf(context).calorieFloorKcal, 1719);
  for (
    const reply of [
      "Drop to 1,400 calories a day and you'll lose faster.",
      "I'd eat 1,200 kcal a day for the next month.",
      "Aim for 1,300-1,500 kcal daily.",
      "You should go down to 1500 kcal.",
      "Try keeping it at 1,600 calories each day.",
    ]
  ) {
    assert(broken(reply).includes("calories_below_floor"), reply);
  }
  for (
    const reply of [
      "Never go below 1,719 kcal a day.",
      "Eating 1,200 kcal a day is too low for you.",
      "Your target is 2000 kcal.",
      "Cut 300 kcal from your day if the scale stalls.",
      "A 400 kcal snack before training is fine.",
      "You burn about 600 kcal in a session.",
      "Keep dinner near 700 calories.",
      "Aim for 1,800 kcal a day.",
      "The floor is 1,719 kcal, so don't drop to 1,500 calories a day.",
    ]
  ) {
    assert(!broken(reply).includes("calories_below_floor"), reply);
  }
});

Deno.test("loss_rate_above_ceiling: advising a loss faster than 1% of body weight a week", () => {
  // 1% of 74.4 kg is 0.744 kg.
  for (
    const reply of [
      "Aim to lose 1 kg a week.",
      "You could try for 1.5% a week.",
      "Push for 2 lb per week.",
      "You should lose 6 kg in 4 weeks.",
      "Target 0.9-1.2 kg per week.",
    ]
  ) {
    assert(broken(reply).includes("loss_rate_above_ceiling"), reply);
  }
  for (
    const reply of [
      "Aim for about 0.5 kg a week.",
      "Aim for 0.7 kg per week, the ceiling is 0.74 kg.",
      "Losing more than 1 kg a week is too fast.",
      "You've been losing 0.9 kg a week, so slow down.",
      "Your pace over the last 4 weeks is 1.2 kg/week.",
      "Aim for 1% of body weight a week at most.",
    ]
  ) {
    assert(!broken(reply).includes("loss_rate_above_ceiling"), reply);
  }
});

Deno.test("effort_above_screening_cap: no vigorous effort until the health check clears", () => {
  for (const screening of ["moderate_until_cleared", "see_professional"] as const) {
    for (
      const reply of [
        "Finish with a few sprints.",
        "Go to failure on the last set.",
        "Try a heavy single at RPE 9.",
        "Add HIIT intervals twice a week.",
        "Push harder today, you have this.",
      ]
    ) {
      assert(broken(reply, { screening }).includes("effort_above_screening_cap"), reply);
    }
  }
  for (
    const reply of [
      "Keep the effort moderate: no sets to failure.",
      "Avoid sprints until a doctor clears you.",
      "Stay at a moderate pace and keep 3 reps in reserve.",
      "I won't suggest intervals until you have clearance.",
    ]
  ) {
    assert(
      !broken(reply, { screening: "moderate_until_cleared" }).includes(
        "effort_above_screening_cap",
      ),
      reply,
    );
  }
  assertEquals(broken("Finish with a few sprints.", { screening: "cleared" }), []);
});

Deno.test("claimed_action: Coach has no tools and says so", () => {
  for (
    const reply of [
      "I've updated your plan for next week.",
      "I lowered your calories to match.",
      "Done. Your target is now saved.",
      "Your plan has been updated.",
      "I'll set a reminder for you.",
      "Let me adjust that for you.",
      "I can change your calories for you.",
      "I will log that meal now.",
      "I have scheduled a deload.",
      "It's done!",
    ]
  ) {
    assert(broken(reply).includes("claimed_action"), reply);
  }
  for (
    const reply of [
      "You can change this in Progress, Set your target.",
      "I'd suggest lowering your calories only if the scale stalls.",
      "Want me to explain how to update your plan?",
      "I can explain why the trend moved.",
      "The plan is set for 6 sessions a week.",
      "I noted your sleep was short, so keep today easy.",
      "If you set a target, I can compare your pace with it.",
    ]
  ) {
    assert(!broken(reply).includes("claimed_action"), reply);
  }
});

Deno.test("numbers_not_grounded carries the figures for the repair and a safe count for the log", () => {
  const result = check("That is roughly 71.5 kg in 4 weeks and 66.5 kg in 12 weeks.", {
    question: "What now?",
  })!;
  assertEquals(result.rule, "projection_without_target");
  assert(result.rules!.includes("numbers_not_grounded"));
  assertEquals(result.detail, "71.5, 66.5, 12");
  const onlyNumbers = check("You might walk 45 minutes a day.")!;
  assertEquals(onlyNumbers.rule, "numbers_not_grounded");
  assertEquals(onlyNumbers.count, 1);
  assertEquals(onlyNumbers.detail, "45");
});

Deno.test("every broken rule is reported together, the goal phase rule first", () => {
  const result = check(
    "I've updated your plan: drop to 1,200 kcal a day and lose 1.5 kg a week, ending at 66.5 kg in 12 weeks.",
  )!;
  assertEquals(result.rule, "projection_without_target");
  assertEquals(result.rules, [
    "projection_without_target",
    "calories_below_floor",
    "loss_rate_above_ceiling",
    "claimed_action",
    "numbers_not_grounded",
  ]);
});
