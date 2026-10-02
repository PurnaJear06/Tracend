import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1.0.14";
import { answersSnapshot, parseOnboardingAnswers } from "./answers.ts";
import {
  confidenceCap,
  estimateWorkoutMinutes,
  mifflinStJeor,
  nutritionBounds,
  nutritionPolicy,
  splitForDays,
  trainingEnergyPerDay,
  trainingPolicy,
} from "./policy.ts";
import type { AvoidablePattern } from "./catalog.ts";
import { answersFor } from "./test_helpers.ts";

Deno.test("Mifflin-St Jeor matches the published equation", () => {
  // 10 x 80 + 6.25 x 180 - 5 x 30 + 5 = 1780
  assertEquals(mifflinStJeor("male", 80, 180, 30), 1780);
  // 10 x 60 + 6.25 x 165 - 5 x 28 - 161 = 1330.25
  assertAlmostEquals(mifflinStJeor("female", 60, 165, 28), 1330.25);
});

Deno.test("training energy uses net MET 4 over the week", () => {
  // 4 x 3.5 x 75 / 200 = 5.25 kcal/min; x 60 min x 4 sessions / 7 = 180 kcal/day
  assertAlmostEquals(trainingEnergyPerDay(75, 60, 4), 180);
});

Deno.test("fat loss for a sedentary man: a deficit window above the floor", () => {
  const policy = nutritionPolicy(answersFor({
    goal: "fat_loss",
    sex: "male",
    weightKg: 80,
    heightCm: 180,
    age: 30,
    trainingWeekdays: [1, 3, 5],
    sessionMinutes: 60,
    dailyActivity: "mostly_sitting",
  }));
  // BMR 1780 x 1.2 = 2136 + training 4 x 3.5 x 80 / 200 x 180 / 7 = 144 -> TDEE 2280
  assertEquals(policy.bmrKcal, [1780, 1780]);
  assertEquals(policy.tdeeKcal, [2280, 2280]);
  // -25%..-10% of 2280 = 1710..2052 -> rounded to 10
  assertEquals(policy.calories, [1780, 2050]);
  assert(policy.floorApplied, "1710 is below the 1780 BMR floor");
  // 1.6..2.6 g/kg in a deficit
  assertEquals(policy.protein, [128, 208]);
});

Deno.test("muscle gain differs from fat loss for the same athlete", () => {
  const base = { sex: "female" as const, weightKg: 60, heightCm: 165, age: 28 };
  const gain = nutritionPolicy(answersFor({ ...base, goal: "muscle_gain" }));
  const loss = nutritionPolicy(answersFor({ ...base, goal: "fat_loss" }));
  assert(gain.calories[0] > loss.calories[1]);
  assertEquals(gain.protein[1], Math.round(2.2 * 60));
});

Deno.test("unspecified sex carries both equations as a range and caps confidence low", () => {
  const answers = answersFor({ sex: "unspecified", weightKg: 70, heightCm: 172, age: 35 });
  const policy = nutritionPolicy(answers);
  assertEquals(policy.bmrKcal, [
    Math.round(mifflinStJeor("female", 70, 172, 35)),
    Math.round(mifflinStJeor("male", 70, 172, 35)),
  ]);
  assertEquals(policy.bmrKcal[1] - policy.bmrKcal[0], 166);
  assertEquals(confidenceCap(answers, policy), "low");
});

Deno.test("a high BMI uses the weight at BMI 25 for protein", () => {
  const policy = nutritionPolicy(answersFor({ weightKg: 140, heightCm: 178, goal: "fat_loss" }));
  const reference = 25 * 1.78 ** 2;
  assertEquals(policy.protein[0], Math.round(1.6 * reference));
  assert(policy.protein[1] < 2.6 * 140);
});

Deno.test("physical labour raises maintenance without double counting training", () => {
  const sitting = nutritionPolicy(answersFor({ dailyActivity: "mostly_sitting" }));
  const labour = nutritionPolicy(answersFor({ dailyActivity: "physical_labour" }));
  const bmr = sitting.bmrKcal[0];
  assertAlmostEquals(labour.tdeeKcal[0] - sitting.tdeeKcal[0], bmr * (1.725 - 1.2), 1);
});

Deno.test("fat bounds follow calories and body weight", () => {
  const policy = nutritionPolicy(answersFor({ weightKg: 78 }));
  assertEquals(policy.fatMinG(2000), Math.ceil(Math.max(0.2 * 2000 / 9, 39)));
  assertEquals(policy.fatMaxG(2000), Math.floor(0.35 * 2000 / 9));
  // From BMI 30 the per-kg minimum follows the weight at BMI 25, so the
  // minimum never passes the 35% maximum for a very heavy athlete.
  const heavy = nutritionPolicy(answersFor({ weightKg: 250, heightCm: 150, goal: "fat_loss" }));
  assertEquals(heavy.fatMinG(0), Math.ceil(0.5 * 25 * 1.5 ** 2));
  assert(heavy.fatMinG(heavy.calories[0]) <= heavy.fatMaxG(heavy.calories[0]));
});

Deno.test("nutrition bounds equal the database check, and the range never leaves them", async () => {
  const sql = await Deno.readTextFile(
    new URL("../../../migrations/20261002092000_onboarding_plan_v2.sql", import.meta.url),
  );
  const bound = (field: string) => {
    const match = sql.match(
      new RegExp(`jsonb_int_between\\(nutrition -> '${field}', (\\d+), (\\d+)\\)`),
    );
    assert(match, `${field} bound not found in the migration`);
    return [Number(match[1]), Number(match[2])];
  };
  assertEquals(bound("calories"), [...nutritionBounds.calories]);
  assertEquals(bound("protein_g"), [...nutritionBounds.proteinG]);
  assertEquals(bound("carbohydrate_g"), [...nutritionBounds.carbohydrateG]);
  assertEquals(bound("fat_g"), [...nutritionBounds.fatG]);

  const huge = nutritionPolicy(answersFor({
    weightKg: 180,
    heightCm: 190,
    dailyActivity: "physical_labour",
    goal: "muscle_gain",
    trainingWeekdays: [1, 2, 3, 4, 5, 6],
    sessionMinutes: 120,
  }));
  assertEquals(huge.calories, [6000, 6000]);
  assert(huge.ceilingApplied && !huge.floorApplied);
  assertEquals(confidenceCap(answersFor(), huge), "low");
  assert(!nutritionPolicy(answersFor()).ceilingApplied);
});

Deno.test("movements to avoid leave the required groups; a fully avoided group is dropped", () => {
  const groups = (avoidPatterns: readonly AvoidablePattern[]) =>
    trainingPolicy(answersFor({ avoidPatterns })).requiredPatternGroups;
  assertEquals(groups([]).length, 4);
  assertEquals(groups(["squat", "vertical_push"]), [
    ["lunge"],
    ["hinge"],
    ["horizontal_push"],
    ["horizontal_pull", "vertical_pull"],
  ]);
  assertEquals(groups(["squat", "lunge"]).length, 3);
});

Deno.test("splits and session limits by schedule", () => {
  assertEquals([1, 2, 3, 4, 5, 6].map(splitForDays), [
    "full_body",
    "full_body",
    "full_body",
    "upper_lower",
    "upper_lower_push_pull_legs",
    "push_pull_legs",
  ]);
  const short = trainingPolicy(answersFor({ sessionMinutes: 30 }));
  assertEquals([short.setBudgetPerSession, short.maxExercisesPerSession], [10, 4]);
  const long = trainingPolicy(answersFor({ sessionMinutes: 90, experience: "intermediate" }));
  assertEquals([long.setBudgetPerSession, long.maxExercisesPerSession], [30, 8]);
  assertEquals(long.maxWeeklySetsPerMuscle, 20);
  assertEquals(trainingPolicy(answersFor({ goal: "strength" })).reps, [3, 20]);
});

Deno.test("workout minutes: warm-up plus work and rest for every set", () => {
  // 8 + 3 x (0.75 + 2) + 3 x (0.75 + 1.25) = 22.25
  assertEquals(
    estimateWorkoutMinutes([{ sets: 3, rest_seconds: 120 }, { sets: 3, rest_seconds: 75 }]),
    22,
  );
});

Deno.test("answers: complete drafts parse, old drafts list what is missing", () => {
  const parsed = parseOnboardingAnswers("experienced", {
    goal: "strength",
    sex: "female",
    birth_year: 1990,
    height_cm: 168,
    weight_kg: 63.46,
    target_weight_kg: null,
    daily_activity: "some_standing",
    training_weekdays: [5, 1, 3, 3, 9],
    session_minutes: 75,
    equipment_items: ["barbell", "bench", "rowing_machine"],
    equipment: "Garage gym",
    nutrition_context: "Vegetarian",
    constraints: "",
    current_plan: "5/3/1, three days",
  }, 2026);
  assert(parsed.ok);
  if (!parsed.ok) return;
  assertEquals(parsed.answers.trainingWeekdays, [1, 3, 5]);
  assertEquals(parsed.answers.equipment, ["barbell", "bench"]);
  assertEquals(parsed.answers.experience, "intermediate");
  assertEquals(parsed.answers.weightKg, 63.5);
  assertEquals(parsed.answers.age, 36);
  assertEquals(answersSnapshot(parsed.answers).equipment_items, ["barbell", "bench"]);
  assertEquals(parsed.answers.avoidPatterns, []);

  const old = parseOnboardingAnswers("beginner", {
    goal: "recomposition",
    training_days: 3,
    session_minutes: 60,
    weight_kg: 75,
    equipment: "Full gym",
  }, 2026);
  assertEquals(old, {
    ok: false,
    missing: [
      "sex",
      "birth_year",
      "height_cm",
      "daily_activity",
      "training_weekdays",
      "equipment_items",
    ],
  });
});

Deno.test("answers: under-18s, seven training days and an experienced path without a plan are refused", () => {
  const base = {
    goal: "fat_loss",
    sex: "male",
    birth_year: 2010,
    height_cm: 175,
    weight_kg: 70,
    daily_activity: "mostly_sitting",
    training_weekdays: [1, 2, 3, 4, 5, 6, 7],
    session_minutes: 60,
    equipment_items: [],
  };
  const parsed = parseOnboardingAnswers("experienced", base, 2026);
  assertEquals(parsed, {
    ok: false,
    missing: ["birth_year", "training_weekdays", "current_plan"],
  });
});

Deno.test("answers: movements to avoid are kept, and a written limitation needs them", () => {
  const complete = {
    goal: "fat_loss",
    sex: "male",
    birth_year: 1994,
    height_cm: 180,
    weight_kg: 90,
    daily_activity: "mostly_sitting",
    training_weekdays: [1, 3, 5],
    session_minutes: 60,
    equipment_items: ["dumbbells"],
  };
  assertEquals(
    parseOnboardingAnswers("beginner", {
      ...complete,
      constraints: "Squats and overhead pressing hurt; avoid both",
    }, 2026),
    { ok: false, missing: ["avoid_patterns"] },
  );
  const parsed = parseOnboardingAnswers("beginner", {
    ...complete,
    constraints: "Squats and overhead pressing hurt; avoid both",
    avoid_patterns: ["vertical_push", "squat", "jumping"],
  }, 2026);
  assert(parsed.ok);
  if (!parsed.ok) return;
  assertEquals(parsed.answers.avoidPatterns, ["squat", "vertical_push"]);
  assertEquals(answersSnapshot(parsed.answers).avoid_patterns, ["squat", "vertical_push"]);
  // A limitation answered with "none of these" is complete.
  const none = parseOnboardingAnswers("beginner", {
    ...complete,
    constraints: "I dislike burpees",
    avoid_patterns: [],
  }, 2026);
  assert(none.ok);
});
