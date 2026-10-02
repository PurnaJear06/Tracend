// Focus muscles: the weekly minimum, how policiesFor fits it to what the
// athlete can do, and that every plan, the rules plan included, meets it.
import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { type Muscle, muscles } from "./catalog.ts";
import { validRulesPlan } from "./generate.ts";
import {
  buildOnboardingProposal,
  OnboardingPlanValidationError,
  validateOnboardingPlan,
} from "./plan_contract.ts";
import { priorityMinimumSets } from "./policy.ts";
import { weeklySetsByMuscle } from "./rules_plan.ts";
import { answersFor, equipmentSets, policiesFor, weekdaysFor } from "./test_helpers.ts";
import { exerciseCatalogV1 } from "./catalog.ts";

Deno.test("the minimum is a share of the week's budget, rounded down and capped", () => {
  // 20 sets a session x 3 days x 0.3 = 18 -> capped at 10.
  assertEquals(priorityMinimumSets(20, 3, 1, 20), 10);
  // Split between two focus muscles: 18 / 2 = 9.
  assertEquals(priorityMinimumSets(20, 3, 2, 20), 9);
  // One short day: 10 x 1 x 0.3 = 3.
  assertEquals(priorityMinimumSets(10, 1, 1, 20), 3);
  // 10 x 1 x 0.3 / 2 = 1.5 -> 1, rounded down.
  assertEquals(priorityMinimumSets(10, 1, 2, 20), 1);
  assertEquals(priorityMinimumSets(20, 6, 1, 8), 8);
  assertEquals(priorityMinimumSets(20, 3, 0, 20), 0);
});

Deno.test("focus never raises a volume limit", () => {
  for (const experience of ["beginner", "intermediate"] as const) {
    const plain = policiesFor(answersFor({ experience })).training;
    const focused = policiesFor(answersFor({ experience, priorityMuscles: ["chest"] })).training;
    assertEquals(focused.maxWeeklySetsPerMuscle, plain.maxWeeklySetsPerMuscle);
    assertEquals(focused.setBudgetPerSession, plain.setBudgetPerSession);
  }
});

Deno.test("every schedule, length, equipment and focus gets a valid plan that meets its minimums", () => {
  const pairs: Muscle[][] = [[], ...muscles.map((muscle) => [muscle]), ["chest", "back"], [
    "quads",
    "shoulders",
  ], ["biceps", "calves"]];
  for (const weekdays of Object.values(weekdaysFor)) {
    for (const sessionMinutes of [30, 60, 90]) {
      for (const equipment of Object.values(equipmentSets)) {
        for (const priorityMuscles of pairs) {
          const policies = policiesFor(answersFor({
            trainingWeekdays: weekdays,
            sessionMinutes,
            equipment,
            priorityMuscles,
            path: "experienced",
            experience: "intermediate",
          }));
          const plan = validRulesPlan(policies);
          const weekly = weeklySetsByMuscle(plan.workouts, exerciseCatalogV1);
          for (const item of policies.training.priorityMinimums) {
            assert(
              (weekly.get(item.muscle) ?? 0) >= item.sets,
              `${weekdays.length}d ${sessionMinutes}min ${equipment.join("+")} ${item.muscle}`,
            );
          }
        }
      }
    }
  }
});

Deno.test("a gym athlete keeps the full minimum, and the plan gives the muscle more than without focus", () => {
  const answers = answersFor({ path: "experienced", experience: "intermediate" });
  const plain = validRulesPlan(policiesFor(answers));
  const focusedPolicies = policiesFor({ ...answers, priorityMuscles: ["shoulders"] });
  assertEquals(focusedPolicies.training.priorityMinimums, [{ muscle: "shoulders", sets: 10 }]);
  const focused = validRulesPlan(focusedPolicies);
  const before = weeklySetsByMuscle(plain.workouts, exerciseCatalogV1).get("shoulders") ?? 0;
  const after = weeklySetsByMuscle(focused.workouts, exerciseCatalogV1).get("shoulders") ?? 0;
  assert(after >= 10 && after > before, `${before} -> ${after}`);
});

Deno.test("a minimum the athlete's equipment cannot hold is lowered, never failed", () => {
  // Bodyweight only has no exercise aimed at the back as its target muscle?
  // Whatever it has, the minimum is what the rules plan reached.
  const policies = policiesFor(answersFor({
    equipment: [],
    trainingWeekdays: [3],
    sessionMinutes: 30,
    priorityMuscles: ["calves", "biceps"],
  }));
  const plan = validRulesPlan(policies);
  const weekly = weeklySetsByMuscle(plan.workouts, exerciseCatalogV1);
  for (const item of policies.training.priorityMinimums) {
    assert((weekly.get(item.muscle) ?? 0) >= item.sets);
  }
});

Deno.test("a model plan that skips a focus muscle is rejected", () => {
  const policies = policiesFor(answersFor({
    path: "experienced",
    experience: "intermediate",
    priorityMuscles: ["calves"],
  }));
  const plain = validRulesPlan(policiesFor(answersFor({
    path: "experienced",
    experience: "intermediate",
  })));
  const withoutCalves = {
    ...plain,
    workouts: plain.workouts.map((workout) => ({
      ...workout,
      exercises: workout.exercises.filter((exercise) =>
        exerciseCatalogV1.find((entry) => entry.slug === exercise.slug)?.muscles[0] !== "calves"
      ),
    })),
  };
  const error = assertThrows(
    () => validateOnboardingPlan(withoutCalves, policies),
    OnboardingPlanValidationError,
  );
  assertEquals(error.rule, "priority_volume_missing");
});

Deno.test("the proposal tells the athlete their focus and carries the minimums", () => {
  const policies = policiesFor(answersFor({ priorityMuscles: ["chest"] }));
  const proposal = buildOnboardingProposal(validRulesPlan(policies), policies, {
    origin: "rules",
    provider: null,
    model: null,
    fallbackReason: "provider_mock",
  });
  const notes = proposal.training.assumptions as string[];
  assert(notes[0].startsWith("Your focus: chest gets at least"));
  const calculation = proposal.training.calculation as Record<string, unknown>;
  assertEquals(calculation.priority_minimums, policies.training.priorityMinimums);
});
