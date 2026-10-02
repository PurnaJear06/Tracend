import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  type OnboardingPlan,
  OnboardingPlanValidationError,
  type OnboardingPlanValidationRule,
  parseOnboardingPlan,
  validateOnboardingPlan,
} from "./plan_contract.ts";
import { buildRulesPlan } from "./rules_plan.ts";
import { answersFor, equipmentSets, policiesFor } from "./test_helpers.ts";

const policies = policiesFor(answersFor({ equipment: equipmentSets.dumbbells }));
const valid = buildRulesPlan(policies);

type Mutable<T> = { -readonly [K in keyof T]: Mutable<T[K]> };
const copy = (): Mutable<OnboardingPlan> => structuredClone(valid) as Mutable<OnboardingPlan>;

function rule(fn: () => void): OnboardingPlanValidationRule {
  const error = assertThrows(fn, OnboardingPlanValidationError);
  return error.rule;
}
const invalid = (plan: Mutable<OnboardingPlan>) =>
  rule(() => validateOnboardingPlan(plan as OnboardingPlan, policies));
const parsed = (value: unknown) => rule(() => parseOnboardingPlan(JSON.stringify(value)));

Deno.test("a valid plan round-trips through JSON and validates", () => {
  const plan = parseOnboardingPlan(JSON.stringify(valid));
  validateOnboardingPlan(plan, policies);
  assertEquals(plan.workouts.length, 3);
});

Deno.test("shape rules", () => {
  assertEquals(rule(() => parseOnboardingPlan("{not json")), "json_syntax");
  assertEquals(parsed([]), "invalid_root");
  assertEquals(parsed({ ...copy(), extra: 1 }), "unexpected_keys");
  const missing = copy() as Record<string, unknown>;
  delete missing.downside;
  assertEquals(parsed(missing), "missing_field");
  assertEquals(parsed({ ...copy(), block_weeks: "six" }), "invalid_type");
  assertEquals(parsed({ ...copy(), title: "x".repeat(81) }), "text_too_long");
  assertEquals(parsed({ ...copy(), assumptions: Array(7).fill("a") }), "list_too_long");
  assertEquals(parsed({ ...copy(), confidence: "certain" }), "invalid_enum");
});

Deno.test("schedule rules", () => {
  assertEquals(invalid({ ...copy(), block_weeks: 12 }), "block_weeks_out_of_range");
  const fewer = copy();
  fewer.workouts.pop();
  assertEquals(invalid(fewer), "workout_count_mismatch");
  const moved = copy();
  moved.workouts[0].weekday = 2;
  assertEquals(invalid(moved), "weekday_mismatch");
});

Deno.test("exercise rules", () => {
  const empty = copy();
  empty.workouts[0].exercises = [];
  assertEquals(invalid(empty), "exercise_count_out_of_range");
  const invented = copy();
  invented.workouts[0].exercises[0].slug = "jefferson-curl";
  assertEquals(invalid(invented), "unknown_exercise");
  const machine = copy();
  machine.workouts[0].exercises[0].slug = "leg-press";
  assertEquals(invalid(machine), "exercise_not_allowed");
  const twice = copy();
  twice.workouts[0].exercises[1].slug = twice.workouts[0].exercises[0].slug;
  assertEquals(invalid(twice), "duplicate_exercise_in_workout");
  const sets = copy();
  sets.workouts[0].exercises[0].sets = 6;
  assertEquals(invalid(sets), "sets_out_of_range");
  const reps = copy();
  reps.workouts[0].exercises[0].rep_min = 12;
  reps.workouts[0].exercises[0].rep_max = 8;
  assertEquals(invalid(reps), "reps_out_of_range");
  const rpe = copy();
  rpe.workouts[0].exercises[0].target_rpe = 10;
  assertEquals(invalid(rpe), "rpe_out_of_range");
  const rest = copy();
  rest.workouts[0].exercises[0].rest_seconds = 30;
  assertEquals(invalid(rest), "rest_out_of_range");
});

Deno.test("an exercise from a movement the athlete avoids is rejected", () => {
  const avoiding = policiesFor(answersFor({
    equipment: equipmentSets.dumbbells,
    limitations: "Squats and overhead pressing hurt; avoid both",
    avoidPatterns: ["squat", "vertical_push"],
  }));
  // The plan built without the request starts with a squat.
  assertEquals(valid.workouts[0].exercises[0].slug, "bodyweight-squat");
  assertEquals(
    rule(() => validateOnboardingPlan(valid, avoiding)),
    "exercise_avoided",
  );
  const pressing = copy();
  pressing.workouts[0].exercises[0].slug = "dumbbell-shoulder-press";
  assertEquals(
    rule(() => validateOnboardingPlan(pressing as OnboardingPlan, avoiding)),
    "exercise_avoided",
  );
});

Deno.test("volume and time rules", () => {
  const budget = copy();
  for (const exercise of budget.workouts[0].exercises) exercise.sets = 5;
  assertEquals(invalid(budget), "session_set_budget_exceeded");

  const shortSession = policiesFor(
    answersFor({ equipment: equipmentSets.dumbbells, sessionMinutes: 30 }),
  );
  const long = structuredClone(buildRulesPlan(shortSession)) as Mutable<OnboardingPlan>;
  for (const exercise of long.workouts[0].exercises) exercise.rest_seconds = 180;
  assertEquals(
    rule(() => validateOnboardingPlan(long as OnboardingPlan, shortSession)),
    "session_too_long",
  );

  const volume = copy();
  for (const workout of volume.workouts) {
    workout.exercises = [
      { ...workout.exercises[0], slug: "goblet-squat", sets: 5, rest_seconds: 60 },
      { ...workout.exercises[0], slug: "dumbbell-reverse-lunge", sets: 5, rest_seconds: 60 },
      { ...workout.exercises[0], slug: "one-arm-dumbbell-row", sets: 3 },
      { ...workout.exercises[0], slug: "dumbbell-romanian-deadlift", sets: 3 },
      { ...workout.exercises[0], slug: "dumbbell-floor-press", sets: 3 },
    ];
  }
  assertEquals(invalid(volume), "weekly_muscle_volume_exceeded");

  const pushOnly = copy();
  for (const workout of pushOnly.workouts) {
    workout.exercises = [{ ...workout.exercises[0], slug: "dumbbell-floor-press", sets: 3 }];
  }
  assertEquals(invalid(pushOnly), "pattern_coverage_missing");
});

Deno.test("nutrition rules", () => {
  const { calories, protein } = policies.nutrition;
  assertEquals(
    invalid({ ...copy(), nutrition: { ...valid.nutrition, calories: calories[1] + 200 } }),
    "calories_out_of_range",
  );
  assertEquals(
    invalid({ ...copy(), nutrition: { ...valid.nutrition, protein_g: protein[0] - 20 } }),
    "protein_out_of_range",
  );
  assertEquals(
    invalid({ ...copy(), nutrition: { ...valid.nutrition, fat_g: 20 } }),
    "fat_out_of_range",
  );
  assertEquals(
    invalid({ ...copy(), nutrition: { ...valid.nutrition, carbohydrate_g: 10 } }),
    "carbohydrate_out_of_range",
  );
  assertEquals(
    invalid({
      ...copy(),
      nutrition: { ...valid.nutrition, carbohydrate_g: valid.nutrition.carbohydrate_g + 60 },
    }),
    "macro_sum_mismatch",
  );
});
