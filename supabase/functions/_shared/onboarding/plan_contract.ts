import type { DailyActivity, OnboardingAnswers } from "./answers.ts";
import { activityFromSteps, type HealthSummary } from "./health_summary.ts";
import {
  allowedExercises,
  type AvoidablePattern,
  avoidablePatternLabels,
  type CatalogExercise,
  catalogVersion,
} from "./catalog.ts";
import {
  confidenceCap,
  estimateWorkoutMinutes,
  nutritionBounds,
  type NutritionPolicy,
  onboardingPolicyVersion,
  type TrainingPolicy,
} from "./policy.ts";

// The onboarding plan contract: what a model (or the rules fallback) returns,
// how it is validated against onboarding-policy-v1 and the catalog, and the
// change_proposals 2.0 payload deterministic code builds from it. A plan is
// either valid as a whole or rejected with one finite rule name; nothing is
// partially applied (AI_SAFETY_SPEC §12).

// Text limits keep a whole plan small enough to generate inside the output
// token limit and the time budget: a six-day plan has about 40 exercises, so
// every character per exercise or workout is multiplied. The 2026-10-02 eval
// showed a 2-day plan of 9,500 characters under the earlier, looser limits.
export const onboardingPlanLimits = Object.freeze({
  titleMaxLength: 80,
  assessmentMaxLength: 300,
  listMaxItems: 4,
  listItemMaxLength: 140,
  progressionMaxLength: 200,
  rationaleMaxLength: 400,
  benefitMaxLength: 200,
  downsideMaxLength: 200,
  workoutNameMaxLength: 60,
  workoutTextMaxLength: 140,
  exerciseNotesMaxLength: 80,
  nutritionRationaleMaxLength: 240,
});

export const onboardingPlanValidationRules = [
  "json_syntax",
  "invalid_root",
  "unexpected_keys",
  "missing_field",
  "invalid_type",
  "text_too_long",
  "list_too_long",
  "invalid_enum",
  "block_weeks_out_of_range",
  "workout_count_mismatch",
  "weekday_mismatch",
  "exercise_count_out_of_range",
  "unknown_exercise",
  "exercise_not_allowed",
  "exercise_avoided",
  "duplicate_exercise_in_workout",
  "sets_out_of_range",
  "reps_out_of_range",
  "rpe_out_of_range",
  "rest_out_of_range",
  "session_set_budget_exceeded",
  "session_too_long",
  "weekly_muscle_volume_exceeded",
  "pattern_coverage_missing",
  "calories_out_of_range",
  "protein_out_of_range",
  "fat_out_of_range",
  "carbohydrate_out_of_range",
  "macro_sum_mismatch",
] as const;
export type OnboardingPlanValidationRule = typeof onboardingPlanValidationRules[number];

export class OnboardingPlanValidationError extends Error {
  readonly rule: OnboardingPlanValidationRule;
  readonly path: string;

  constructor(rule: OnboardingPlanValidationRule, path: string) {
    super(`${rule} at ${path}`);
    this.name = "OnboardingPlanValidationError";
    this.rule = rule;
    this.path = path;
  }
}

export type PlanExercise = Readonly<{
  slug: string;
  sets: number;
  rep_min: number;
  rep_max: number;
  target_rpe: number;
  rest_seconds: number;
  notes: string;
}>;

export type PlanWorkout = Readonly<{
  weekday: number;
  name: string;
  objective: string;
  warm_up: string;
  cool_down: string;
  exercises: readonly PlanExercise[];
}>;

export type PlanNutrition = Readonly<{
  calories: number;
  protein_g: number;
  carbohydrate_g: number;
  fat_g: number;
  rationale: string;
}>;

export type OnboardingPlan = Readonly<{
  title: string;
  block_weeks: number;
  assessment: string;
  assumptions: readonly string[];
  missing_information: readonly string[];
  kept_from_current_plan: readonly string[];
  changed_from_current_plan: readonly string[];
  progression: string;
  rationale: string;
  expected_benefit: string;
  downside: string;
  confidence: "low" | "medium" | "high";
  workouts: readonly PlanWorkout[];
  nutrition: PlanNutrition;
}>;

const rootKeys = [
  "title",
  "block_weeks",
  "assessment",
  "assumptions",
  "missing_information",
  "kept_from_current_plan",
  "changed_from_current_plan",
  "progression",
  "rationale",
  "expected_benefit",
  "downside",
  "confidence",
  "workouts",
  "nutrition",
] as const;
const workoutKeys = ["weekday", "name", "objective", "warm_up", "cool_down", "exercises"] as const;
const exerciseKeys = [
  "slug",
  "sets",
  "rep_min",
  "rep_max",
  "target_rpe",
  "rest_seconds",
  "notes",
] as const;
const nutritionKeys = ["calories", "protein_g", "carbohydrate_g", "fat_g", "rationale"] as const;

/** The JSON shape shown to the model; every key is required. */
export const onboardingPlanJsonShape = {
  title: "string",
  block_weeks: "integer",
  assessment: "string",
  assumptions: ["string"],
  missing_information: ["string"],
  kept_from_current_plan: ["string"],
  changed_from_current_plan: ["string"],
  progression: "string",
  rationale: "string",
  expected_benefit: "string",
  downside: "string",
  confidence: "low | medium | high",
  workouts: [{
    weekday: "integer 1-7 (1 = Monday)",
    name: "string",
    objective: "string",
    warm_up: "string",
    cool_down: "string",
    exercises: [{
      slug: "catalog slug",
      sets: "integer",
      rep_min: "integer",
      rep_max: "integer",
      target_rpe: "number",
      rest_seconds: "integer",
      notes: "string",
    }],
  }],
  nutrition: {
    calories: "integer",
    protein_g: "integer",
    carbohydrate_g: "integer",
    fat_g: "integer",
    rationale: "string",
  },
};

function fail(rule: OnboardingPlanValidationRule, path: string): never {
  throw new OnboardingPlanValidationError(rule, path);
}

function record(value: unknown, keys: readonly string[], path: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(path === "$" ? "invalid_root" : "invalid_type", path);
  }
  const object = value as Record<string, unknown>;
  for (const key of Object.keys(object)) {
    if (!keys.includes(key)) fail("unexpected_keys", `${path}.${key}`);
  }
  for (const key of keys) {
    if (!(key in object)) fail("missing_field", `${path}.${key}`);
  }
  return object;
}

function text(value: unknown, max: number, path: string, required = true): string {
  if (typeof value !== "string") fail("invalid_type", path);
  const trimmed = value.trim();
  if (required && !trimmed) fail("missing_field", path);
  if (trimmed.length > max) fail("text_too_long", path);
  return trimmed;
}

function list(value: unknown, path: string): string[] {
  if (!Array.isArray(value)) fail("invalid_type", path);
  if (value.length > onboardingPlanLimits.listMaxItems) fail("list_too_long", path);
  return value.map((item, index) =>
    text(item, onboardingPlanLimits.listItemMaxLength, `${path}[${index}]`)
  );
}

function int(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) fail("invalid_type", path);
  return value;
}

function num(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) fail("invalid_type", path);
  return value;
}

/** Parses the model's JSON text into a plan, checking shape and lengths only. */
export function parseOnboardingPlan(content: string): OnboardingPlan {
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch {
    fail("json_syntax", "$");
  }
  const root = record(value, rootKeys, "$");
  const limits = onboardingPlanLimits;
  const confidence = root.confidence;
  if (confidence !== "low" && confidence !== "medium" && confidence !== "high") {
    fail("invalid_enum", "$.confidence");
  }
  if (!Array.isArray(root.workouts)) fail("invalid_type", "$.workouts");
  const workouts = root.workouts.map((item, w) => {
    const path = `$.workouts[${w}]`;
    const workout = record(item, workoutKeys, path);
    if (!Array.isArray(workout.exercises)) fail("invalid_type", `${path}.exercises`);
    return {
      weekday: int(workout.weekday, `${path}.weekday`),
      name: text(workout.name, limits.workoutNameMaxLength, `${path}.name`),
      objective: text(workout.objective, limits.workoutTextMaxLength, `${path}.objective`),
      warm_up: text(workout.warm_up, limits.workoutTextMaxLength, `${path}.warm_up`),
      cool_down: text(workout.cool_down, limits.workoutTextMaxLength, `${path}.cool_down`),
      exercises: workout.exercises.map((entry, e) => {
        const exercisePath = `${path}.exercises[${e}]`;
        const exercise = record(entry, exerciseKeys, exercisePath);
        return {
          slug: text(exercise.slug, 80, `${exercisePath}.slug`),
          sets: int(exercise.sets, `${exercisePath}.sets`),
          rep_min: int(exercise.rep_min, `${exercisePath}.rep_min`),
          rep_max: int(exercise.rep_max, `${exercisePath}.rep_max`),
          target_rpe: num(exercise.target_rpe, `${exercisePath}.target_rpe`),
          rest_seconds: int(exercise.rest_seconds, `${exercisePath}.rest_seconds`),
          notes: text(
            exercise.notes,
            limits.exerciseNotesMaxLength,
            `${exercisePath}.notes`,
            false,
          ),
        };
      }),
    };
  });
  const nutrition = record(root.nutrition, nutritionKeys, "$.nutrition");
  return {
    title: text(root.title, limits.titleMaxLength, "$.title"),
    block_weeks: int(root.block_weeks, "$.block_weeks"),
    assessment: text(root.assessment, limits.assessmentMaxLength, "$.assessment"),
    assumptions: list(root.assumptions, "$.assumptions"),
    missing_information: list(root.missing_information, "$.missing_information"),
    kept_from_current_plan: list(root.kept_from_current_plan, "$.kept_from_current_plan"),
    changed_from_current_plan: list(root.changed_from_current_plan, "$.changed_from_current_plan"),
    progression: text(root.progression, limits.progressionMaxLength, "$.progression"),
    rationale: text(root.rationale, limits.rationaleMaxLength, "$.rationale"),
    expected_benefit: text(root.expected_benefit, limits.benefitMaxLength, "$.expected_benefit"),
    downside: text(root.downside, limits.downsideMaxLength, "$.downside"),
    confidence,
    workouts,
    nutrition: {
      calories: int(nutrition.calories, "$.nutrition.calories"),
      protein_g: int(nutrition.protein_g, "$.nutrition.protein_g"),
      carbohydrate_g: int(nutrition.carbohydrate_g, "$.nutrition.carbohydrate_g"),
      fat_g: int(nutrition.fat_g, "$.nutrition.fat_g"),
      rationale: text(
        nutrition.rationale,
        limits.nutritionRationaleMaxLength,
        "$.nutrition.rationale",
      ),
    },
  };
}

export type PlanPolicies = Readonly<{
  answers: OnboardingAnswers;
  /** The athlete's last 28 days of Apple Health; null when there is none. */
  health: HealthSummary | null;
  nutrition: NutritionPolicy;
  training: TrainingPolicy;
  catalog: readonly CatalogExercise[];
}>;

const between = (value: number, [low, high]: readonly [number, number]) =>
  value >= low && value <= high;

/** Throws OnboardingPlanValidationError on the first rule the plan breaks. */
export function validateOnboardingPlan(plan: OnboardingPlan, policies: PlanPolicies): void {
  const { answers, training, nutrition } = policies;
  if (!between(plan.block_weeks, training.blockWeeks)) {
    fail("block_weeks_out_of_range", "$.block_weeks");
  }
  if (plan.workouts.length !== answers.trainingWeekdays.length) {
    fail("workout_count_mismatch", "$.workouts");
  }
  const weekdays = plan.workouts.map((workout) => workout.weekday).sort((a, b) => a - b);
  if (weekdays.some((day, index) => day !== answers.trainingWeekdays[index])) {
    fail("weekday_mismatch", "$.workouts");
  }
  const allowed = new Map(
    allowedExercises(policies.catalog, answers.equipment, answers.experience)
      .map((exercise) => [exercise.slug, exercise]),
  );
  const known = new Set(policies.catalog.map((exercise) => exercise.slug));
  const weeklySets = new Map<string, number>();
  const patterns = new Set<string>();
  plan.workouts.forEach((workout, w) => {
    const path = `$.workouts[${w}]`;
    if (
      workout.exercises.length < 1 || workout.exercises.length > training.maxExercisesPerSession
    ) {
      fail("exercise_count_out_of_range", `${path}.exercises`);
    }
    const seen = new Set<string>();
    let sessionSets = 0;
    workout.exercises.forEach((exercise, e) => {
      const exercisePath = `${path}.exercises[${e}]`;
      if (!known.has(exercise.slug)) fail("unknown_exercise", `${exercisePath}.slug`);
      const entry = allowed.get(exercise.slug);
      if (!entry) fail("exercise_not_allowed", `${exercisePath}.slug`);
      if (training.avoidPatterns.includes(entry.pattern)) {
        fail("exercise_avoided", `${exercisePath}.slug`);
      }
      if (seen.has(exercise.slug)) fail("duplicate_exercise_in_workout", `${exercisePath}.slug`);
      seen.add(exercise.slug);
      if (!between(exercise.sets, training.setsPerExercise)) {
        fail("sets_out_of_range", `${exercisePath}.sets`);
      }
      if (
        exercise.rep_min > exercise.rep_max || !between(exercise.rep_min, training.reps) ||
        !between(exercise.rep_max, training.reps)
      ) {
        fail("reps_out_of_range", `${exercisePath}.rep_min`);
      }
      if (!between(exercise.target_rpe, training.rpe)) {
        fail("rpe_out_of_range", `${exercisePath}.target_rpe`);
      }
      if (!between(exercise.rest_seconds, training.restSeconds)) {
        fail("rest_out_of_range", `${exercisePath}.rest_seconds`);
      }
      sessionSets += exercise.sets;
      const target = entry.muscles[0];
      weeklySets.set(target, (weeklySets.get(target) ?? 0) + exercise.sets);
      patterns.add(entry.pattern);
    });
    if (sessionSets > training.setBudgetPerSession) {
      fail("session_set_budget_exceeded", `${path}.exercises`);
    }
    if (
      estimateWorkoutMinutes(workout.exercises) >
        answers.sessionMinutes + training.sessionOverrunMinutes
    ) {
      fail("session_too_long", `${path}.exercises`);
    }
  });
  for (const [muscle, sets] of weeklySets) {
    if (sets > training.maxWeeklySetsPerMuscle) {
      fail("weekly_muscle_volume_exceeded", `$.workouts:${muscle}`);
    }
  }
  for (const group of training.requiredPatternGroups) {
    if (!group.some((pattern) => patterns.has(pattern))) {
      fail("pattern_coverage_missing", `$.workouts:${group.join("|")}`);
    }
  }
  const food = plan.nutrition;
  if (!between(food.calories, nutrition.calories)) {
    fail("calories_out_of_range", "$.nutrition.calories");
  }
  if (!between(food.protein_g, nutrition.protein)) {
    fail("protein_out_of_range", "$.nutrition.protein_g");
  }
  if (
    food.fat_g < nutrition.fatMinG(food.calories) || food.fat_g > nutrition.fatMaxG(food.calories)
  ) {
    fail("fat_out_of_range", "$.nutrition.fat_g");
  }
  if (!between(food.carbohydrate_g, nutritionBounds.carbohydrateG)) {
    fail("carbohydrate_out_of_range", "$.nutrition.carbohydrate_g");
  }
  const macroCalories = 4 * food.protein_g + 4 * food.carbohydrate_g + 9 * food.fat_g;
  if (Math.abs(macroCalories - food.calories) > nutrition.macroTolerance * food.calories) {
    fail("macro_sum_mismatch", "$.nutrition");
  }
}

export type PlanOrigin = Readonly<{
  origin: "ai" | "rules";
  provider: string | null;
  model: string | null;
  /** Why the rules plan was used instead of a model, when it was. */
  fallbackReason: string | null;
}>;

export type OnboardingProposalPayload = Readonly<{
  training: Record<string, unknown>;
  nutrition: Record<string, unknown>;
  evidence: readonly Record<string, string>[];
  rationale: string;
  benefit: string;
  downside: string;
  confidence: "low" | "medium" | "high";
}>;

const confidenceRank = { low: 0, medium: 1, high: 2 } as const;

const activityRank: Record<DailyActivity, number> = {
  mostly_sitting: 0,
  some_standing: 1,
  mostly_standing: 2,
  physical_labour: 3,
};

const activityLabels: Record<DailyActivity, string> = {
  mostly_sitting: "mostly sitting",
  some_standing: "some standing",
  mostly_standing: "mostly standing",
  physical_labour: "physical labour",
};

const hoursAndMinutes = (minutes: number) => `${Math.floor(minutes / 60)} h ${minutes % 60} min`;

/**
 * Notes deterministic code always adds, whatever the model wrote, most
 * important first. Apple Health notes never change a number: the athlete's
 * answers set the targets, and only short sleep (trainingPolicy) changes effort.
 */
export function requiredNotes(plan: OnboardingPlan, policies: PlanPolicies): string[] {
  const { answers, health, nutrition, training } = policies;
  const avoided = answers.avoidPatterns.map((pattern: AvoidablePattern) =>
    avoidablePatternLabels[pattern]
  );
  const steps = health?.steps_per_day;
  const implied = steps === undefined ? null : activityFromSteps(steps);
  return [
    ...(avoided.length ? [`Leaves out, as you asked: ${avoided.join(", ")}.`] : []),
    ...(nutrition.ceilingApplied
      ? [
        `Your estimated needs are above ${nutrition.ceilingKcal} kcal, the most Tracend sets; weigh-ins over 2-3 weeks will show whether to change it.`,
      ]
      : []),
    ...(training.startLighter && health?.sleep_minutes_per_night !== undefined
      ? [
        `Sleep has averaged ${
          hoursAndMinutes(health.sleep_minutes_per_night)
        } a night, so this block keeps effort at RPE ${training.rpe[1]} or below.`,
      ]
      : []),
    ...(health?.weight_latest_kg !== undefined &&
        Math.abs(health.weight_latest_kg - answers.weightKg) > 3
      ? [
        `Apple Health's latest weight is ${health.weight_latest_kg} kg (${health.weight_latest_date}); the plan uses the ${answers.weightKg} kg you entered.`,
      ]
      : []),
    ...(plan.nutrition.carbohydrate_g < nutrition.carbohydrateFlagBelowG
      ? ["Carbohydrate is below 2 g per kg of body weight, which may limit training energy."]
      : []),
    ...(steps !== undefined && implied !== null &&
        Math.abs(activityRank[answers.dailyActivity] - activityRank[implied]) >= 2
      ? [
        `You average ${steps} steps a day, which looks like "${
          activityLabels[implied]
        }"; calories use your answer, "${activityLabels[answers.dailyActivity]}".`,
      ]
      : []),
  ];
}

/** What deterministic code knows is missing, before the model's own list. */
export function requiredMissingInformation(health: HealthSummary | null): string[] {
  if (!health) {
    return ["Apple Health isn't connected, so your daily activity is your own estimate."];
  }
  return health.workouts_per_week === undefined
    ? [
      "No workouts were found in Apple Health for the last 4 weeks; training history is from your answers.",
    ]
    : [];
}

/**
 * The change_proposals 2.0 payload. Deterministic code orders the workouts by
 * weekday, names exercises from the catalog, sets each workout's length, and
 * caps confidence; the model's words are carried as its proposal.
 */
export function buildOnboardingProposal(
  plan: OnboardingPlan,
  policies: PlanPolicies,
  origin: PlanOrigin,
): OnboardingProposalPayload {
  const bySlug = new Map(policies.catalog.map((exercise) => [exercise.slug, exercise]));
  const workouts = [...plan.workouts].sort((a, b) => a.weekday - b.weekday);
  const cap = confidenceCap(policies.answers, policies.nutrition);
  const confidence = confidenceRank[plan.confidence] > confidenceRank[cap] ? cap : plan.confidence;
  const notes = requiredNotes(plan, policies);
  const missing = requiredMissingInformation(policies.health);
  return {
    training: {
      title: plan.title,
      block_weeks: plan.block_weeks,
      sessions_per_week: workouts.length,
      split: policies.training.split,
      weekly_structure: workouts.map((workout, index) => ({
        workout_order: index + 1,
        name: workout.name,
        objective: workout.objective,
        preferred_weekday: workout.weekday,
        estimated_minutes: estimateWorkoutMinutes(workout.exercises),
        warm_up_guidance: workout.warm_up,
        cool_down_guidance: workout.cool_down,
        exercises: workout.exercises.map((exercise, order) => ({
          exercise_order: order + 1,
          slug: exercise.slug,
          name: bySlug.get(exercise.slug)!.name,
          sets: exercise.sets,
          rep_min: exercise.rep_min,
          rep_max: exercise.rep_max,
          target_rpe: exercise.target_rpe,
          rest_seconds: exercise.rest_seconds,
          notes: exercise.notes,
        })),
      })),
      prescription: {
        strategy: policies.answers.path === "experienced"
          ? "preserve_validated_practices"
          : "foundation_block",
        progression: plan.progression,
        review_after_weeks: 2,
      },
      origin: origin.origin,
      provider: origin.provider,
      model: origin.model,
      fallback_reason: origin.fallbackReason,
      policy_version: onboardingPolicyVersion,
      catalog_version: catalogVersion,
      assessment: plan.assessment,
      // Tracend's own notes first; the model's fill what is left of the limit.
      assumptions: [...notes, ...plan.assumptions].slice(0, onboardingPlanLimits.listMaxItems),
      missing_information: [...missing, ...plan.missing_information]
        .slice(0, onboardingPlanLimits.listMaxItems),
      kept_from_current_plan: plan.kept_from_current_plan,
      changed_from_current_plan: plan.changed_from_current_plan,
      calculation: {
        bmr_kcal: policies.nutrition.bmrKcal,
        activity_factor: policies.nutrition.activityFactor,
        tdee_kcal: policies.nutrition.tdeeKcal,
        calorie_range_kcal: policies.nutrition.calories,
        floor_kcal: policies.nutrition.floorKcal,
        floor_applied: policies.nutrition.floorApplied,
        ceiling_kcal: policies.nutrition.ceilingKcal,
        ceiling_applied: policies.nutrition.ceilingApplied,
        protein_range_g: policies.nutrition.protein,
        ...(policies.health ? { health: policies.health } : {}),
      },
    },
    nutrition: {
      calories: plan.nutrition.calories,
      protein_g: plan.nutrition.protein_g,
      carbohydrate_g: plan.nutrition.carbohydrate_g,
      fat_g: plan.nutrition.fat_g,
      rationale: plan.nutrition.rationale,
    },
    evidence: [
      {
        code: "ONBOARDING_ANSWERS_CONFIRMED",
        label: "Your reviewed onboarding answers",
        source: "feature_snapshot",
      },
      {
        code: "ONBOARDING_POLICY_V1",
        label: "Tracend's safe ranges for calories, protein, fat and training volume",
        source: "policy_evaluation",
      },
      ...(policies.health
        ? [{
          code: "APPLE_HEALTH_SUMMARY_28D",
          label: "Your Apple Health summary for the last 28 days",
          source: "feature_snapshot",
        }]
        : []),
    ],
    rationale: plan.rationale,
    benefit: plan.expected_benefit,
    downside: plan.downside,
    confidence,
  };
}
