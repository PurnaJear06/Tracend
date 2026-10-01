import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { type Goal, goals } from "./answers.ts";
import { exerciseCatalogV1 } from "./catalog.ts";
import {
  buildOnboardingProposal,
  OnboardingPlanValidationError,
  validateOnboardingPlan,
} from "./plan_contract.ts";
import { buildRulesPlan } from "./rules_plan.ts";
import { answersFor, equipmentSets, policiesFor, weekdaysFor } from "./test_helpers.ts";

Deno.test("the rules plan is valid for every equipment set, schedule, path and goal", () => {
  let checked = 0;
  for (const [equipmentName, equipment] of Object.entries(equipmentSets)) {
    for (const days of [1, 2, 3, 4, 5, 6]) {
      for (const path of ["beginner", "experienced"] as const) {
        for (const goal of goals as readonly Goal[]) {
          for (const sessionMinutes of [30, 45, 60, 90, 120]) {
            for (
              const [sex, weightKg, heightCm] of [
                ["female", 52, 160],
                ["male", 140, 178],
                ["unspecified", 75, 170],
              ] as const
            ) {
              const answers = answersFor({
                path,
                experience: path === "experienced" ? "intermediate" : "beginner",
                goal,
                equipment,
                trainingWeekdays: weekdaysFor[days],
                sessionMinutes,
                sex,
                weightKg,
                heightCm,
              });
              const policies = policiesFor(answers);
              const plan = buildRulesPlan(policies);
              try {
                validateOnboardingPlan(plan, policies);
              } catch (error) {
                if (error instanceof OnboardingPlanValidationError) {
                  throw new Error(
                    `${equipmentName} ${days}d ${path} ${goal} ${sessionMinutes}min ${sex}: ` +
                      `${error.rule} at ${error.path}`,
                  );
                }
                throw error;
              }
              checked++;
            }
          }
        }
      }
    }
  }
  assertEquals(checked, 4 * 6 * 2 * 5 * 5 * 3);
});

Deno.test("the rules plan lands on the athlete's chosen weekdays", () => {
  const policies = policiesFor(answersFor({ trainingWeekdays: [2, 4, 6, 7].slice(0, 4) }));
  const proposal = buildOnboardingProposal(buildRulesPlan(policies), policies, {
    origin: "rules",
    provider: null,
    model: null,
    fallbackReason: "provider_not_configured",
  });
  const structure = proposal.training.weekly_structure as Array<Record<string, unknown>>;
  assertEquals(structure.map((workout) => workout.preferred_weekday), [2, 4, 6, 7]);
  assertEquals(structure.map((workout) => workout.workout_order), [1, 2, 3, 4]);
  assertEquals(proposal.training.split, "upper_lower");
  assertEquals(proposal.training.origin, "rules");
  for (const workout of structure) {
    const exercises = workout.exercises as Array<Record<string, unknown>>;
    assert(exercises.length > 0);
    for (const exercise of exercises) {
      assert(typeof exercise.name === "string" && exercise.name.length > 0);
    }
  }
});

Deno.test("bodyweight-only plans use only bodyweight exercises", () => {
  const policies = policiesFor(answersFor({ equipment: [] }));
  const plan = buildRulesPlan(policies);
  const bySlug = new Map(exerciseCatalogV1.map((exercise) => [exercise.slug, exercise]));
  for (const workout of plan.workouts) {
    for (const exercise of workout.exercises) {
      assertEquals(bySlug.get(exercise.slug)?.equipment, []);
    }
  }
});
