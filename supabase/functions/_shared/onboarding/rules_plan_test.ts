import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { dailyActivities, type Goal, goals, sexes } from "./answers.ts";
import {
  type AvoidablePattern,
  avoidablePatterns,
  catalogBySlug,
  exerciseCatalogV1,
} from "./catalog.ts";
import { OnboardingPlanInfeasibleError, validRulesPlan } from "./generate.ts";
import { nutritionBounds } from "./policy.ts";
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

const within = (value: number, [low, high]: readonly [number, number]) =>
  value >= low && value <= high;

Deno.test("the rules plan's nutrition is valid and storable at every body size and activity", () => {
  let checked = 0;
  for (const weightKg of [35, 60, 120, 180, 250]) {
    for (const heightCm of [120, 150, 190, 230]) {
      for (const age of [18, 32, 100]) {
        for (const dailyActivity of dailyActivities) {
          for (const goal of goals) {
            for (const sex of sexes) {
              for (const days of [1, 6]) {
                for (const sessionMinutes of [30, 120]) {
                  const answers = answersFor({
                    weightKg,
                    heightCm,
                    age,
                    birthYear: 2026 - age,
                    dailyActivity,
                    goal,
                    sex,
                    trainingWeekdays: weekdaysFor[days],
                    sessionMinutes,
                  });
                  const label = `${weightKg}kg ${heightCm}cm ${age}y ${dailyActivity} ${goal} ` +
                    `${sex} ${days}d ${sessionMinutes}min`;
                  const plan = validRulesPlan(policiesFor(answers));
                  const food = plan.nutrition;
                  assert(within(food.calories, nutritionBounds.calories), label);
                  assert(within(food.protein_g, nutritionBounds.proteinG), label);
                  assert(within(food.carbohydrate_g, nutritionBounds.carbohydrateG), label);
                  assert(within(food.fat_g, nutritionBounds.fatG), label);
                  checked++;
                }
              }
            }
          }
        }
      }
    }
  }
  assertEquals(checked, 5 * 4 * 3 * 4 * 5 * 3 * 2 * 2);
});

Deno.test("a 180 kg labourer gaining muscle is capped at the ceiling, not refused", () => {
  const answers = answersFor({
    sex: "male",
    age: 32,
    heightCm: 190,
    weightKg: 180,
    dailyActivity: "physical_labour",
    goal: "muscle_gain",
    trainingWeekdays: weekdaysFor[6],
    sessionMinutes: 120,
  });
  const policies = policiesFor(answers);
  assert(policies.nutrition.tdeeKcal[0] > 6000, "the estimate is above the ceiling");
  assertEquals(policies.nutrition.calories, [6000, 6000]);
  assert(policies.nutrition.ceilingApplied);
  const plan = validRulesPlan(policies);
  assertEquals(plan.nutrition.calories, 6000);
  assert(plan.nutrition.carbohydrate_g <= 1000);
  const proposal = buildOnboardingProposal(plan, policies, {
    origin: "rules",
    provider: null,
    model: null,
    fallbackReason: "provider_mock",
  });
  assertEquals(proposal.confidence, "low");
  assert(
    (proposal.training.assumptions as string[]).some((note) => note.includes("above 6000 kcal")),
  );
  const calculation = proposal.training.calculation as Record<string, unknown>;
  assertEquals([calculation.ceiling_kcal, calculation.ceiling_applied], [6000, true]);
});

Deno.test("one avoided movement always leaves a valid plan without it", () => {
  let checked = 0;
  for (const avoid of avoidablePatterns) {
    for (const [equipmentName, equipment] of Object.entries(equipmentSets)) {
      for (const days of [1, 2, 3, 4, 5, 6]) {
        for (const path of ["beginner", "experienced"] as const) {
          for (const sessionMinutes of [30, 60, 120]) {
            const answers = answersFor({
              path,
              experience: path === "experienced" ? "intermediate" : "beginner",
              equipment,
              trainingWeekdays: weekdaysFor[days],
              sessionMinutes,
              limitations: "It hurts",
              avoidPatterns: [avoid],
            });
            let plan;
            try {
              plan = validRulesPlan(policiesFor(answers));
            } catch (error) {
              if (error instanceof OnboardingPlanInfeasibleError) {
                throw new Error(
                  `${avoid} ${equipmentName} ${days}d ${path} ${sessionMinutes}min: ${error.rule}`,
                );
              }
              throw error;
            }
            for (const workout of plan.workouts) {
              for (const exercise of workout.exercises) {
                assert(catalogBySlug.get(exercise.slug)!.pattern !== avoid);
              }
            }
            checked++;
          }
        }
      }
    }
  }
  assertEquals(checked, 7 * 4 * 6 * 2 * 3);
});

Deno.test("several avoided movements: a valid plan without them, or a refusal", () => {
  const combos: AvoidablePattern[][] = [
    ["squat", "vertical_push"],
    ["squat", "lunge"],
    ["hinge", "squat"],
    ["horizontal_push", "vertical_push"],
    ["vertical_push", "vertical_pull"],
    ["horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull"],
  ];
  let refused = 0;
  for (const avoid of combos) {
    for (const equipment of Object.values(equipmentSets)) {
      for (const days of [1, 3, 4, 5, 6]) {
        const answers = answersFor({
          equipment,
          trainingWeekdays: weekdaysFor[days],
          limitations: "It hurts",
          avoidPatterns: avoid,
        });
        try {
          const plan = validRulesPlan(policiesFor(answers));
          for (const workout of plan.workouts) {
            for (const exercise of workout.exercises) {
              assert(
                !avoid.includes(catalogBySlug.get(exercise.slug)!.pattern as AvoidablePattern),
              );
            }
          }
        } catch (error) {
          if (!(error instanceof OnboardingPlanInfeasibleError)) throw error;
          refused++;
        }
      }
    }
  }
  // Only all four upper-body patterns at once can leave an upper day empty.
  assert(refused > 0 && refused < 4 * 5);
});
