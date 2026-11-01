// B5a: onboarding applies the healthy-weight floors Coach and the goal screen already apply. Under
// BMI 19.5 a goal with a deficit starts at maintenance, and a target weight under BMI 18.5 is
// never carried into the plan (so approval never stores it).
import { assert, assertEquals, assertStringIncludes, assertThrows } from "jsr:@std/assert@1.0.14";
import { answersSnapshot, parseOnboardingAnswers } from "./answers.ts";
import { goalCalorieAdjustments, nutritionPolicy } from "./policy.ts";
import {
  buildOnboardingProposal,
  claimsDeficitWhileHeld,
  healthyWeightHoldRationale,
  type OnboardingPlan,
  OnboardingPlanValidationError,
  validateOnboardingPlan,
} from "./plan_contract.ts";
import { onboardingSystemPrompt } from "./generate.ts";
import { buildRulesPlan } from "./rules_plan.ts";
import { answersFor, policiesFor } from "./test_helpers.ts";
import { goalPhaseThresholds } from "../training/goal_phase/thresholds.ts";

// The audit's case: a woman of 165 cm and 45 kg (BMI 16.5) who chose fat loss.
const underweight = answersFor({
  goal: "fat_loss",
  sex: "female",
  birthYear: 1990,
  age: 36,
  heightCm: 165,
  weightKg: 45,
  dailyActivity: "mostly_sitting",
  trainingWeekdays: [1, 3, 5],
  sessionMinutes: 60,
});

Deno.test("under BMI 19.5 fat loss starts at maintenance, never a deficit", () => {
  const policy = nutritionPolicy(underweight);
  // BMR 10 x 45 + 6.25 x 165 - 5 x 36 - 161 = 1140.25; x 1.2 = 1368.3, + training 81 -> 1449.3.
  assertEquals(policy.tdeeKcal, [1449, 1449]);
  assertEquals(policy.bmi, 16.5);
  assertEquals(policy.healthyWeightHold, true);
  assertEquals(policy.calories, [1450, 1450]);
  assert(policy.calories[0] >= policy.tdeeKcal[0], "the lowest target is maintenance");
});

Deno.test("every goal with a deficit is held, and goals without one are unchanged", () => {
  for (const goal of ["fat_loss", "recomposition", "aesthetic"] as const) {
    const policy = nutritionPolicy({ ...underweight, goal });
    assertEquals(policy.healthyWeightHold, true, goal);
    assert(policy.calories[0] >= policy.tdeeKcal[0] - 5, `${goal} has no deficit`);
  }
  for (const goal of ["muscle_gain", "strength"] as const) {
    const held = nutritionPolicy({ ...underweight, goal });
    assertEquals(held.healthyWeightHold, false, goal);
    assert(goalCalorieAdjustments[goal][0] >= 0);
  }
});

Deno.test("the threshold is Coach's: BMI rounded to one decimal, below 19.5", () => {
  assertEquals(goalPhaseThresholds.bmiNearFloor.value, 19.5);
  // 53.0 kg at 165 cm is BMI 19.47, which rounds to 19.5: not held, as in Coach.
  const atThreshold = nutritionPolicy({ ...underweight, weightKg: 53 });
  assertEquals(atThreshold.bmi, 19.5);
  assertEquals(atThreshold.healthyWeightHold, false);
  assert(atThreshold.calories[0] < atThreshold.tdeeKcal[0], "a deficit is allowed again");
  // An exact tie, 77.8 kg at 200 cm (BMI 19.45), rounds up here and in SQL alike.
  assertEquals(nutritionPolicy({ ...underweight, heightCm: 200, weightKg: 77.8 }).bmi, 19.5);
  const below = nutritionPolicy({ ...underweight, weightKg: 52.9 });
  assertEquals(below.bmi, 19.4);
  assertEquals(below.healthyWeightHold, true);
});

Deno.test("a held plan says why, in plain words, and carries the maintenance rationale", () => {
  const policies = policiesFor(underweight);
  const proposal = buildOnboardingProposal(buildRulesPlan(policies), policies, {
    origin: "rules",
    provider: null,
    model: null,
    fallbackReason: null,
  });
  const assumptions = proposal.training.assumptions as string[];
  assertStringIncludes(
    assumptions[0],
    "Calories start at maintenance rather than a deficit, because your BMI is 16.5, below the healthy range.",
  );
  assertEquals(proposal.nutrition.rationale, healthyWeightHoldRationale);
  assert((proposal.nutrition.calories as number) >= 1449, "no deficit");
  const calculation = proposal.training.calculation as Record<string, unknown>;
  assertEquals(calculation.healthy_weight_hold, true);
  assertEquals(calculation.bmi, 16.5);
  for (const text of [...assumptions, proposal.nutrition.rationale as string]) {
    assert(!/disorder|anorexi|underweight|diagnos/i.test(text), text);
  }
});

Deno.test("an athlete above the threshold gets the usual plan, with no hold keys", () => {
  const policies = policiesFor(answersFor({ goal: "fat_loss" }));
  assertEquals(policies.nutrition.healthyWeightHold, false);
  const proposal = buildOnboardingProposal(buildRulesPlan(policies), policies, {
    origin: "rules",
    provider: null,
    model: null,
    fallbackReason: null,
  });
  const calculation = proposal.training.calculation as Record<string, unknown>;
  assertEquals("healthy_weight_hold" in calculation, false);
  assert(proposal.nutrition.rationale !== healthyWeightHoldRationale);
});

const payload = {
  goal: "fat_loss",
  sex: "female",
  birth_year: 1990,
  height_cm: 165,
  weight_kg: 45,
  daily_activity: "mostly_sitting",
  training_weekdays: [1, 3, 5],
  session_minutes: 60,
  equipment_items: ["dumbbells"],
};

Deno.test("a target under BMI 18.5 is never carried into the plan, and the plan says so", () => {
  const parsed = parseOnboardingAnswers("beginner", { ...payload, target_weight_kg: 40 }, 2026);
  assert(parsed.ok);
  assertEquals(parsed.answers.targetWeightKg, null);
  assertEquals(parsed.answers.targetBelowHealthyFloorKg, 40);
  const snapshot = answersSnapshot(parsed.answers);
  // Approval copies target_weight_kg into the goal; it is null, so nothing under the floor is stored.
  assertEquals(snapshot.target_weight_kg, null);
  assertEquals(snapshot.target_below_healthy_floor_kg, 40);
  const policies = policiesFor(parsed.answers);
  const proposal = buildOnboardingProposal(buildRulesPlan(policies), policies, {
    origin: "rules",
    provider: null,
    model: null,
    fallbackReason: null,
  });
  assert(
    (proposal.training.assumptions as string[]).includes(
      "No target weight is set: 40 kg is under the healthy range for your height, which starts at 50.4 kg (BMI 18.5).",
    ),
  );
});

Deno.test("a target at or above the floor is kept, and other snapshots are unchanged", () => {
  const atFloor = parseOnboardingAnswers("beginner", { ...payload, target_weight_kg: 50.4 }, 2026);
  assert(atFloor.ok);
  assertEquals(atFloor.answers.targetWeightKg, 50.4);
  assertEquals(atFloor.answers.targetBelowHealthyFloorKg, undefined);
  assertEquals("target_below_healthy_floor_kg" in answersSnapshot(atFloor.answers), false);
  const none = parseOnboardingAnswers("beginner", payload, 2026);
  assert(none.ok);
  assertEquals("target_below_healthy_floor_kg" in answersSnapshot(none.answers), false);
});

Deno.test("the model is told the held window, never the goal's deficit", () => {
  const prompt = onboardingSystemPrompt(policiesFor(underweight));
  assertStringIncludes(prompt, "goal adjustment 0% to 0%");
  assert(!prompt.includes("-25%"), "the fat-loss deficit is not offered");
  assertStringIncludes(
    prompt,
    "Calories are held at maintenance: the athlete's BMI is 16.5, under 19.5, so Tracend sets no calorie deficit for this goal.",
  );
  const usual = onboardingSystemPrompt(policiesFor(answersFor({ goal: "fat_loss" })));
  assertStringIncludes(usual, "goal adjustment -25% to -10%");
  assert(!usual.includes("held at maintenance"));
});

Deno.test("the model is told no target is set when the athlete's was under the floor", () => {
  const parsed = parseOnboardingAnswers("beginner", { ...payload, target_weight_kg: 40 }, 2026);
  assert(parsed.ok);
  assertStringIncludes(
    onboardingSystemPrompt(policiesFor(parsed.answers)),
    "the plan sets no target weight",
  );
});

Deno.test("while held, a plan whose text claims a deficit or weight loss is rejected", () => {
  const policies = policiesFor(underweight);
  const plan = buildRulesPlan(policies) as OnboardingPlan;
  validateOnboardingPlan(plan, policies);
  for (
    const claim of [
      "A moderate deficit for steady fat loss.",
      "You should lose about 0.4 kg a week.",
      "Calories sit below maintenance.",
      "Steady weight loss over the block.",
    ]
  ) {
    const claiming = { ...plan, expected_benefit: claim };
    assert(claimsDeficitWhileHeld(claiming, policies.nutrition), claim);
    const error = assertThrows(
      () => validateOnboardingPlan(claiming, policies),
      OnboardingPlanValidationError,
    );
    assertEquals(error.rule, "deficit_claim_while_held");
  }
  const honest = { ...plan, assessment: "Maintenance calories rather than a deficit for now." };
  validateOnboardingPlan(honest, policies);
  // Without the hold the same words are an ordinary fat-loss plan.
  const usual = policiesFor(answersFor({ goal: "fat_loss" }));
  assertEquals(
    claimsDeficitWhileHeld(
      { ...buildRulesPlan(usual), expected_benefit: "A moderate deficit." },
      usual.nutrition,
    ),
    false,
  );
});
