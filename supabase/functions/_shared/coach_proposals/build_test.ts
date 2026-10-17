import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { catalogBySlug } from "../onboarding/catalog.ts";
import { loadStepKgFor } from "../onboarding/catalog_v2.ts";
import { calorieFloorKcal } from "../onboarding/policy.ts";
import { summarizeGoalPhase } from "../training/goal_phase/summary.ts";
import { noGoalTarget } from "../training/goal_phase/types.ts";
import type { ProgressionTarget } from "../training/progression/targets.ts";
import { buildCoachProposal, buildFromRawIntent } from "./build.ts";
import { addDays } from "./common.ts";
import { baseAnswers, planFor, stateFixture, today, weightReadings } from "./fixtures.ts";
import { nutritionBasis } from "./nutrition.ts";
import type {
  AthleteState,
  BuildResult,
  CoachProposal,
  CoachProposalIntent,
  NutritionChange,
  TrainingChange,
} from "./types.ts";

function proposalOf(result: BuildResult): CoachProposal {
  if (!result.ok) throw new Error(`refused: ${result.code}: ${result.reason}`);
  return result.proposal;
}

function refusalOf(result: BuildResult) {
  if (result.ok) throw new Error("expected a refusal");
  return result;
}

const trainingOf = (proposal: CoachProposal): TrainingChange => proposal.payload.training!;
const withMessage = (message: string, overrides: Partial<AthleteState> = {}) =>
  stateFixture({ athleteMessage: message, ...overrides });

/** The nutrition rules every stored target obeys, whatever built it. */
function assertNutritionObeysRules(change: NutritionChange, state: AthleteState) {
  const floor = calorieFloorKcal(
    state.profile.sex,
    state.goalPhase.currentWeightKg!,
    state.profile.heightCm,
    state.profile.age,
  );
  assert(change.calories >= floor, `${change.calories} is under the floor ${floor}`);
  assert(change.calories >= 1000 && change.calories <= 6000);
  assert(change.protein_g >= 30 && change.protein_g <= 400);
  assert(change.carbohydrate_g >= 20 && change.carbohydrate_g <= 1000);
  assert(change.fat_g >= 20 && change.fat_g <= 300);
  const macros = 4 * change.protein_g + 4 * change.carbohydrate_g + 9 * change.fat_g;
  assert(Math.abs(macros - change.calories) <= 0.05 * change.calories, "macros do not add up");
}

function stateWithReadings(readings: ReturnType<typeof weightReadings>, activatedDaysAgo = 40) {
  return summarizeGoalPhase({
    today,
    goalType: "fat_loss",
    activatedOn: addDays(today, -activatedDaysAgo),
    heightCm: 176,
    target: noGoalTarget,
    readings,
  });
}

const progression = (
  slug: string,
  loadKg: number,
  action: ProgressionTarget["action"] = "add_load",
  confidence: ProgressionTarget["confidence"] = "high",
): ProgressionTarget => ({
  plannedExerciseId: "x",
  exerciseKey: slug,
  name: slug,
  action,
  reason: "top_of_range",
  loadKg,
  reps: 8,
  sets: 3,
  confidence,
  lastDate: "2026-10-16",
  recent: [{ localDate: "2026-10-16", loadKg, sets: 3, minReps: 8, minRir: 2 }],
});

// ---- the intent parser ---------------------------------------------------------------------

Deno.test("an intent outside the vocabulary builds nothing", () => {
  const state = stateFixture();
  const cases: unknown[] = [
    null,
    "lower my calories",
    { kind: "rewrite_plan", reason: "athlete_request" },
    { kind: "nutrition_targets", reason: "because", direction: "lower" },
    { kind: "nutrition_targets", reason: "athlete_request", direction: "sideways" },
    { kind: "nutrition_targets", reason: "athlete_request", direction: "lower", calories: 1800 },
    {
      kind: "nutrition_targets",
      reason: "athlete_request",
      direction: "lower",
      requested_calories: "1800",
    },
    {
      kind: "temporary_block",
      reason: "travel",
      setting: "bodyweight",
      start_date: "2026-02-30",
      end_date: "2026-03-02",
    },
    {
      kind: "temporary_block",
      reason: "travel",
      setting: "moon",
      start_date: today,
      end_date: today,
    },
    { kind: "training_schedule", reason: "time", weeks: 8 },
    { kind: "training_schedule", reason: "time", weeks: 8, weekdays: [1, 1, 2] },
    { kind: "training_schedule", reason: "time", weeks: 20, days_per_week: 4 },
    { kind: "intensity_or_phase", reason: "fatigue", weeks: 1 },
    { kind: "intensity_or_phase", reason: "fatigue", weeks: 1, level: "deload", focus: "size" },
    { kind: "goal_or_phase", reason: "plateau", phase: "bulk" },
    {
      kind: "next_session_adjustment",
      reason: "fatigue",
      direction: "lighter",
      session: "yesterday",
    },
    { kind: "exercise_swap", reason: "preference", from_exercise: "Bad Slug!" },
  ];
  for (const raw of cases) {
    const result = buildFromRawIntent(raw, state);
    assertEquals(result.ok, false, JSON.stringify(raw));
    assertEquals(refusalOf(result).code, "invalid_intent", JSON.stringify(raw));
  }
});

Deno.test("a note with a figure is dropped and a plain note is quoted", () => {
  const base = {
    kind: "next_session_adjustment",
    reason: "fatigue",
    direction: "lighter",
    session: "next",
  };
  const state = stateFixture();
  const withFigure = buildFromRawIntent({ ...base, note: "slept 4 hours" }, state);
  assertEquals(proposalOf(withFigure).rationale.includes("slept"), false);
  const plain = buildFromRawIntent({ ...base, note: "slept badly" }, state);
  assertStringIncludes(proposalOf(plain).rationale, '"slept badly"');
});

// ---- owner case: home for 10-15 days with no gym -------------------------------------------

Deno.test("home for two weeks with no gym becomes a bodyweight block that ends on the date", () => {
  const state = withMessage("I'll be home for 10-15 days with no gym");
  const proposal = proposalOf(buildFromRawIntent({
    kind: "temporary_block",
    reason: "travel",
    setting: "bodyweight",
    start_date: today,
    end_date: "2026-10-30",
  }, state));
  const training = trainingOf(proposal);
  assertEquals(training.mode, "block");
  if (training.mode !== "block") throw new Error("unreachable");
  assertEquals(training.block_kind, "temporary_block");
  assertEquals(training.ends_on, "2026-10-30");
  assertEquals(training.block_weeks, 2);
  assertEquals(proposal.endsOn, "2026-10-30");
  assertEquals(training.weekly_structure.length, state.plan!.workouts.length);
  assertEquals(
    training.weekly_structure.map((workout) => workout.preferred_weekday),
    state.plan!.workouts.map((workout) => workout.weekday),
  );
  for (const workout of training.weekly_structure) {
    for (const exercise of workout.exercises) {
      assertEquals(catalogBySlug.get(exercise.slug!)!.equipment, [], exercise.slug!);
    }
  }
  assertStringIncludes(proposal.rationale, "current plan comes back the day after");
  assertEquals(proposal.basis.training_version_id, state.plan!.versionId);
});

Deno.test("a minimal-equipment block keeps only portable equipment the athlete owns", () => {
  const state = withMessage("home for a week", {
    profile: {
      ...stateFixture().profile,
      equipment: ["dumbbells", "barbell", "machines", "bench"],
    },
  });
  const proposal = proposalOf(buildCoachProposal({
    kind: "temporary_block",
    reason: "travel",
    setting: "minimal_equipment",
    startDate: today,
    endDate: addDays(today, 6),
  }, state));
  const slugs = trainingOf(proposal).mode === "block"
    ? (trainingOf(proposal) as Extract<TrainingChange, { mode: "block" }>).weekly_structure
      .flatMap((workout) => workout.exercises.map((exercise) => exercise.slug!))
    : [];
  assert(slugs.length > 0);
  for (const slug of slugs) {
    for (const item of catalogBySlug.get(slug)!.equipment) {
      assert(["dumbbells", "bench"].includes(item), `${slug} needs ${item}`);
    }
  }
});

Deno.test("a block refuses bad dates, a long block, a far start and a running block", () => {
  const state = stateFixture();
  const block = (start: string, end: string): CoachProposalIntent => ({
    kind: "temporary_block",
    reason: "travel",
    setting: "bodyweight",
    startDate: start,
    endDate: end,
  });
  assertEquals(
    refusalOf(buildCoachProposal(block(today, addDays(today, -1)), state)).code,
    "dates_invalid",
  );
  assertEquals(
    refusalOf(buildCoachProposal(block(addDays(today, -9), addDays(today, -2)), state)).code,
    "dates_invalid",
  );
  assertEquals(
    refusalOf(buildCoachProposal(block(today, addDays(today, 60)), state)).code,
    "block_too_long",
  );
  assertEquals(
    refusalOf(buildCoachProposal(block(addDays(today, 5), addDays(today, 12)), state)).code,
    "block_start_too_far",
  );
  const running = stateFixture({
    plan: planFor([1, 3, 5], { blockEndsOn: "2026-10-25", blockKind: "temporary_block" }),
  });
  const refused = refusalOf(buildCoachProposal(block(today, addDays(today, 6)), running));
  assertEquals(refused.code, "block_already_active");
  assertStringIncludes(refused.reason, "25 Oct");
});

Deno.test("a block under a moderate screening keeps effort at 7 or lower", () => {
  const state = stateFixture({ screening: "moderate_until_cleared" });
  const proposal = proposalOf(buildCoachProposal({
    kind: "temporary_block",
    reason: "travel",
    setting: "bodyweight",
    startDate: today,
    endDate: addDays(today, 8),
  }, state));
  const change = trainingOf(proposal) as Extract<TrainingChange, { mode: "block" }>;
  for (const workout of change.weekly_structure) {
    for (const exercise of workout.exercises) assert(exercise.target_rpe! <= 7);
  }
  assertEquals(proposal.basis.screening, "moderate_until_cleared");
});

Deno.test("nothing changes the plan while the health check says see a professional", () => {
  const state = stateFixture({ screening: "see_professional" });
  const intents: CoachProposalIntent[] = [
    {
      kind: "temporary_block",
      reason: "travel",
      setting: "bodyweight",
      startDate: today,
      endDate: addDays(today, 5),
    },
    { kind: "training_schedule", reason: "time", daysPerWeek: 4, weeks: 8 },
    {
      kind: "exercise_swap",
      reason: "preference",
      fromSlug: state.plan!.workouts[0].exercises[0].slug!,
    },
    { kind: "intensity_or_phase", reason: "fatigue", level: "deload", weeks: 1 },
    { kind: "goal_or_phase", reason: "athlete_request", phase: "maintenance" },
    { kind: "next_session_adjustment", reason: "fatigue", direction: "lighter", session: "next" },
  ];
  for (const intent of intents) {
    assertEquals(refusalOf(buildCoachProposal(intent, state)).code, "screening_see_professional");
  }
});

// ---- owner case: 4 days a week for two months ----------------------------------------------

Deno.test("four days a week for two months becomes a new schedule", () => {
  const state = withMessage("Let's change my plan for the next 2 months to 4 days a week");
  const proposal = proposalOf(buildFromRawIntent({
    kind: "training_schedule",
    reason: "athlete_request",
    days_per_week: 4,
    weeks: 8,
  }, state));
  const training = trainingOf(proposal);
  assertEquals(training.mode, "new_version");
  if (training.mode !== "new_version") throw new Error("unreachable");
  assertEquals(training.weekly_structure.length, 4);
  assertEquals(training.block_weeks, 8);
  assertEquals(new Set(training.weekly_structure.map((w) => w.preferred_weekday)).size, 4);
  assertEquals(training.profile!.training_days.length, 4);
  assert([1, 3, 5].every((day) => training.profile!.training_days.includes(day)));
  assertEquals(training.profile!.session_minutes, 60);
  assertEquals(proposal.endsOn, null);
  assertEquals(proposal.after.sessions!.length, 4);
  assertEquals(proposal.before.sessions!.length, 3);
});

Deno.test("a schedule keeps the loads of exercises that stay", () => {
  const plan = planFor([1, 3, 5]);
  const first = plan.workouts[0].exercises[0];
  const loaded = {
    ...plan,
    workouts: plan.workouts.map((workout) => ({
      ...workout,
      exercises: workout.exercises.map((exercise) =>
        exercise.slug === first.slug ? { ...exercise, targetLoadKg: 62.5 } : exercise
      ),
    })),
  };
  const proposal = proposalOf(buildCoachProposal(
    { kind: "training_schedule", reason: "time", daysPerWeek: 4, weeks: 8 },
    stateFixture({ plan: loaded }),
  ));
  const change = trainingOf(proposal) as Extract<TrainingChange, { mode: "new_version" }>;
  const kept = change.weekly_structure.flatMap((workout) =>
    workout.exercises.filter((exercise) => exercise.slug === first.slug)
  );
  assert(kept.length > 0 && kept.every((exercise) => exercise.start_load_kg === 62.5));
});

Deno.test("a schedule refuses a mismatch, no change and a running block", () => {
  const state = stateFixture();
  const refuse = (intent: CoachProposalIntent) => refusalOf(buildCoachProposal(intent, state));
  assertEquals(
    refuse({
      kind: "training_schedule",
      reason: "time",
      weeks: 8,
      daysPerWeek: 3,
      weekdays: [1, 2, 3, 4],
    }).code,
    "invalid_schedule",
  );
  assertEquals(
    refuse({
      kind: "training_schedule",
      reason: "time",
      weeks: 8,
      weekdays: [1, 3, 5],
      sessionMinutes: 60,
    }).code,
    "no_change",
  );
  const running = stateFixture({
    plan: planFor([1, 3, 5], { blockEndsOn: "2026-10-25", blockKind: "intensity" }),
  });
  assertEquals(
    refusalOf(
      buildCoachProposal(
        { kind: "training_schedule", reason: "time", weeks: 8, daysPerWeek: 4 },
        running,
      ),
    ).code,
    "block_already_active",
  );
});

Deno.test("a schedule changes only the session length when only that is asked", () => {
  const proposal = proposalOf(buildCoachProposal(
    { kind: "training_schedule", reason: "time", weeks: 6, sessionMinutes: 45 },
    stateFixture(),
  ));
  const change = trainingOf(proposal) as Extract<TrainingChange, { mode: "new_version" }>;
  assertEquals(change.weekly_structure.length, 3);
  assertEquals(change.profile, { training_days: [1, 3, 5], session_minutes: 45 });
  for (const workout of change.weekly_structure) assert(workout.estimated_minutes <= 45 + 7);
});

// ---- owner case: a diet break ---------------------------------------------------------------

Deno.test("a diet break is maintenance calories for two weeks and keeps the fat-loss goal", () => {
  const state = withMessage("Take a diet break");
  const proposal = proposalOf(buildFromRawIntent({
    kind: "goal_or_phase",
    reason: "diet_fatigue",
    phase: "diet_break",
  }, state));
  assertEquals(proposal.kind, "goal_or_phase");
  const goal = proposal.payload.goal!;
  assertEquals(goal.phase, "diet_break");
  assertEquals(goal.goal_type, "fat_loss");
  assertEquals(goal.phase_started_on, today);
  assertEquals(goal.phase_ends_on, addDays(today, 13));
  const nutrition = proposal.payload.nutrition!;
  const basis = nutritionBasis(state);
  if ("ok" in basis) throw new Error("no basis");
  assertEquals(nutrition.calories, basis.maintenanceKcal);
  assertNutritionObeysRules(nutrition, state);
  assertStringIncludes(proposal.rationale, "2-week diet break");
  assertEquals(proposal.endsOn, goal.phase_ends_on);
  assert(
    proposal.after.rows.some((row) => row.label === "Phase" && row.value.startsWith("Diet break")),
  );
});

Deno.test("a diet break needs a fat-loss goal and is not repeated", () => {
  const gain = stateFixture({ goal: { ...stateFixture().goal!, goalType: "muscle_gain" } });
  assertEquals(
    refusalOf(
      buildCoachProposal(
        { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
        gain,
      ),
    ).code,
    "diet_break_needs_fat_loss",
  );
  const onBreak = stateFixture({
    goal: { ...stateFixture().goal!, phase: "diet_break", phaseEndsOn: addDays(today, 5) },
  });
  assertEquals(
    refusalOf(
      buildCoachProposal(
        { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
        onBreak,
      ),
    ).code,
    "already_in_phase",
  );
});

Deno.test("maintenance and gain phases compute their own calories", () => {
  const state = stateFixture();
  const maintenance = proposalOf(buildCoachProposal(
    { kind: "goal_or_phase", reason: "plateau", phase: "maintenance" },
    state,
  ));
  assertEquals(maintenance.payload.goal!.phase_ends_on, null);
  assertEquals(maintenance.payload.goal!.goal_type, "fat_loss");
  const gain = proposalOf(buildCoachProposal(
    { kind: "goal_or_phase", reason: "athlete_request", phase: "gain" },
    state,
  ));
  assertEquals(gain.payload.goal!.goal_type, "muscle_gain");
  assert(gain.payload.nutrition!.calories > maintenance.payload.nutrition!.calories);
  assertNutritionObeysRules(gain.payload.nutrition!, state);
});

Deno.test("a cut needs enough logging, a healthy weight and no long run of loss", () => {
  const cut: CoachProposalIntent = {
    kind: "goal_or_phase",
    reason: "athlete_request",
    phase: "cut",
  };
  const ok = proposalOf(buildCoachProposal(cut, stateFixture()));
  assertEquals(ok.payload.goal!.goal_type, "fat_loss");
  assertNutritionObeysRules(ok.payload.nutrition!, stateFixture());
  assert(ok.evidence.some((item) => item.code === "CHANGE_ELIGIBILITY_NUTRITION"));

  const unlogged = stateFixture({
    eligibility: {
      ...stateFixture().eligibility,
      nutritionEligible: false,
      nutritionDetail: "6 weight days (need 14)",
    },
  });
  const refused = refusalOf(buildCoachProposal(cut, unlogged));
  assertEquals(refused.code, "not_enough_logging");
  assertStringIncludes(refused.reason, "6 weight days");

  const light = stateFixture({ goalPhase: stateWithReadings(weightReadings(30, 57)) });
  assertEquals(refusalOf(buildCoachProposal(cut, light)).code, "weight_near_healthy_floor");

  const long = Array.from({ length: 24 }, (_, week) => ({
    date: addDays(today, -(23 - week) * 7),
    kg: Math.round((93 - week * 0.6) * 10) / 10,
  }));
  const tired = stateFixture({ goalPhase: stateWithReadings(long, 168) });
  assertEquals(refusalOf(buildCoachProposal(cut, tired)).code, "cut_too_long");
});

Deno.test("a target weight needs the athlete's figure, the healthy floor and a safe pace", () => {
  const cut = (extra: Record<string, unknown>) => ({
    kind: "goal_or_phase",
    reason: "athlete_request",
    phase: "cut",
    ...extra,
  });
  const state = withMessage("I want to get to 74 kg by January");
  const ok = proposalOf(
    buildFromRawIntent(cut({ target_weight_kg: 74, target_date: "2027-03-01" }), state),
  );
  assertEquals(ok.payload.goal!.target, { weight_kg: 74, date: "2027-03-01" });

  assertEquals(
    refusalOf(buildFromRawIntent(cut({ target_weight_kg: 70 }), state)).code,
    "figure_not_from_athlete",
  );
  const low = withMessage("get to 50 kg");
  assertEquals(
    refusalOf(buildFromRawIntent(cut({ target_weight_kg: 50 }), low)).code,
    "target_below_healthy_floor",
  );
  const up = withMessage("get to 85 kg");
  assertEquals(
    refusalOf(buildFromRawIntent(cut({ target_weight_kg: 85 }), up)).code,
    "target_wrong_direction",
  );
  const fast = refusalOf(buildFromRawIntent(
    cut({ target_weight_kg: 74, target_date: addDays(today, 14) }),
    state,
  ));
  assertEquals(fast.code, "weight_loss_too_fast");
  assertStringIncludes(fast.reason, "earliest date");
  assertEquals(
    refusalOf(buildFromRawIntent(cut({ target_date: "2027-03-01" }), state)).code,
    "target_date_invalid",
  );
  assertEquals(
    refusalOf(buildFromRawIntent(cut({ target_weight_kg: 74, target_date: "2031-01-01" }), state))
      .code,
    "target_date_invalid",
  );
  const maintenance = buildFromRawIntent({
    kind: "goal_or_phase",
    reason: "plateau",
    phase: "maintenance",
    target_weight_kg: 74,
  }, state);
  assertEquals(refusalOf(maintenance).code, "no_change");
});

Deno.test("a goal change needs a goal, a target of calories and a recent weight", () => {
  const intent: CoachProposalIntent = {
    kind: "goal_or_phase",
    reason: "plateau",
    phase: "maintenance",
  };
  assertEquals(
    refusalOf(buildCoachProposal(intent, stateFixture({ goal: null }))).code,
    "no_active_goal",
  );
  assertEquals(
    refusalOf(buildCoachProposal(intent, stateFixture({ nutrition: null }))).code,
    "no_active_nutrition",
  );
  const stale = stateFixture({
    goalPhase: stateWithReadings(
      weightReadings(30, 80).map((r) => ({ ...r, date: addDays(r.date, -25) })),
    ),
  });
  assertEquals(refusalOf(buildCoachProposal(intent, stale)).code, "no_recent_weight");
});

// ---- owner case: lower my calories to 1,200 ------------------------------------------------

Deno.test("lowering calories to 1,200 is refused with the floor reason", () => {
  const state = withMessage("Lower my calories to 1,200");
  const refused = refusalOf(buildFromRawIntent({
    kind: "nutrition_targets",
    reason: "athlete_request",
    direction: "lower",
    requested_calories: 1200,
  }, state));
  assertEquals(refused.code, "below_calorie_floor");
  // The floor is the athlete's resting energy here, which is above the 1,500 kcal minimum.
  const floor = calorieFloorKcal("male", state.goalPhase.currentWeightKg!, 176, 32);
  assert(floor > 1500);
  assertStringIncludes(refused.reason, `${floor.toLocaleString("en-US")} kcal`);
});

Deno.test("a calorie figure the athlete did not give is refused", () => {
  const refused = refusalOf(buildFromRawIntent({
    kind: "nutrition_targets",
    reason: "athlete_request",
    direction: "lower",
    requested_calories: 2000,
  }, withMessage("I want to eat less")));
  assertEquals(refused.code, "figure_not_from_athlete");
});

Deno.test("an athlete's own calorie figure inside the limits is used", () => {
  const state = withMessage("set my calories to 2,100 please");
  const proposal = proposalOf(buildFromRawIntent({
    kind: "nutrition_targets",
    reason: "athlete_request",
    direction: "lower",
    requested_calories: 2100,
  }, state));
  assertEquals(proposal.payload.nutrition!.calories, 2100);
  assertNutritionObeysRules(proposal.payload.nutrition!, state);
  assertEquals(proposal.before.rows[0], { label: "Calories", value: "2,300 kcal" });
  assertEquals(proposal.after.rows[0], { label: "Calories", value: "2,100 kcal" });
});

Deno.test("lowering without a figure steps down five percent and needs the logging gate", () => {
  const state = stateFixture();
  const proposal = proposalOf(buildCoachProposal(
    { kind: "nutrition_targets", reason: "plateau", direction: "lower" },
    state,
  ));
  assertEquals(proposal.payload.nutrition!.calories, 2190);
  assertNutritionObeysRules(proposal.payload.nutrition!, state);
  const gated = stateFixture({
    eligibility: {
      ...state.eligibility,
      nutritionEligible: false,
      nutritionDetail: "9 weight days (need 14)",
    },
  });
  assertEquals(
    refusalOf(
      buildCoachProposal(
        { kind: "nutrition_targets", reason: "plateau", direction: "lower" },
        gated,
      ),
    ).code,
    "not_enough_logging",
  );
  // Easing off is never gated by logging.
  const raise = proposalOf(buildCoachProposal(
    { kind: "nutrition_targets", reason: "diet_fatigue", direction: "raise" },
    gated,
  ));
  assertEquals(raise.payload.nutrition!.calories, 2420);
  const maintenance = proposalOf(buildCoachProposal(
    { kind: "nutrition_targets", reason: "diet_fatigue", direction: "maintenance" },
    gated,
  ));
  assertNutritionObeysRules(maintenance.payload.nutrition!, gated);
});

Deno.test("a calorie target never loses weight faster than one percent a week", () => {
  const labour = stateFixture({
    profile: { ...stateFixture().profile, dailyActivity: "physical_labour" },
    athleteMessage: "go down to 1746",
  });
  const refused = refusalOf(buildFromRawIntent({
    kind: "nutrition_targets",
    reason: "athlete_request",
    direction: "lower",
    requested_calories: 1746,
  }, labour));
  assertEquals(refused.code, "weight_loss_too_fast");
  assertStringIncludes(refused.reason, "1% of your weight");
});

Deno.test("a calorie cut is refused near the healthy-weight floor", () => {
  const light = stateFixture({
    goalPhase: stateWithReadings(weightReadings(30, 57)),
    nutrition: { ...stateFixture().nutrition!, calories: 1900 },
  });
  const refused = refusalOf(buildCoachProposal(
    { kind: "nutrition_targets", reason: "athlete_request", direction: "lower" },
    light,
  ));
  assertEquals(refused.code, "weight_near_healthy_floor");
});

Deno.test("calorie changes refuse a missing target, a stale weight and a pointless move", () => {
  const lower: CoachProposalIntent = {
    kind: "nutrition_targets",
    reason: "plateau",
    direction: "lower",
  };
  assertEquals(
    refusalOf(buildCoachProposal(lower, stateFixture({ nutrition: null }))).code,
    "no_active_nutrition",
  );
  const stale = stateFixture({
    goalPhase: stateWithReadings(
      weightReadings(30, 80).map((r) => ({ ...r, date: addDays(r.date, -25) })),
    ),
  });
  assertEquals(refusalOf(buildCoachProposal(lower, stale)).code, "no_recent_weight");
  const atFloor = stateFixture({ nutrition: { ...stateFixture().nutrition!, calories: 1500 } });
  assertEquals(refusalOf(buildCoachProposal(lower, atFloor)).code, "below_calorie_floor");
  const opposite = withMessage("make it 2400", {});
  assertEquals(
    refusalOf(
      buildFromRawIntent({
        kind: "nutrition_targets",
        reason: "plateau",
        direction: "lower",
        requested_calories: 2400,
      }, opposite),
    ).code,
    "no_change",
  );
  const same = withMessage("keep 2300");
  assertEquals(
    refusalOf(
      buildFromRawIntent({
        kind: "nutrition_targets",
        reason: "plateau",
        direction: "raise",
        requested_calories: 2300,
      }, same),
    ).code,
    "no_change",
  );
  const huge = withMessage("eat 5000");
  assertEquals(
    refusalOf(
      buildFromRawIntent({
        kind: "nutrition_targets",
        reason: "athlete_request",
        direction: "raise",
        requested_calories: 5000,
      }, huge),
    ).code,
    "above_calorie_ceiling",
  );
});

// ---- owner case: tomorrow I'm tired, go lighter --------------------------------------------

Deno.test("tomorrow I'm tired becomes a lighter next session within one load step", () => {
  const plan = planFor([1, 3, 5]);
  const exercises = plan.workouts[0].exercises;
  const squat = exercises.find((exercise) =>
    catalogBySlug.get(exercise.slug!)?.compound &&
    loadStepKgFor(catalogBySlug.get(exercise.slug!)!) !== null
  )!;
  const step = loadStepKgFor(catalogBySlug.get(squat.slug!)!)!;
  const state = withMessage("Tomorrow I'm tired, go lighter", {
    progression: [progression(squat.slug!, 60, "hold")],
    todayWorkoutDone: false,
  });
  const proposal = proposalOf(buildFromRawIntent({
    kind: "next_session_adjustment",
    reason: "fatigue",
    direction: "lighter",
    session: "next",
  }, state));
  const change = trainingOf(proposal) as Extract<TrainingChange, { mode: "block" }>;
  assertEquals(change.block_kind, "next_session");
  assertEquals(change.ends_on, "2026-10-19");
  assertEquals(proposal.expiresInHours, 24);
  assertEquals(change.weekly_structure.length, 3);
  const adjusted = change.weekly_structure[0].exercises.find((e) => e.slug === squat.slug)!;
  assertEquals(adjusted.start_load_kg, 60 - step);
  assertEquals(adjusted.sets, squat.sets >= 3 ? squat.sets - 1 : squat.sets);
  assert(adjusted.target_rpe! <= squat.targetRpe!);
  // The other sessions are untouched.
  assertEquals(
    change.weekly_structure[1].exercises.map((e) => e.sets),
    plan.workouts[1].exercises.map((e) => e.sets),
  );
  assertEquals(
    change.weekly_structure[2].exercises.map((e) => e.slug),
    plan.workouts[2].exercises.map((e) => e.slug),
  );
  for (const [i, e] of change.weekly_structure[0].exercises.entries()) {
    assert(e.sets <= plan.workouts[0].exercises[i].sets);
  }
});

Deno.test("heavier moves at most one step above the logged target and only where earned", () => {
  const plan = planFor([1, 3, 5]);
  const squat = plan.workouts[0].exercises.find((exercise) =>
    loadStepKgFor(catalogBySlug.get(exercise.slug!)!) !== null
  )!;
  const step = loadStepKgFor(catalogBySlug.get(squat.slug!)!)!;
  const intent: CoachProposalIntent = {
    kind: "next_session_adjustment",
    reason: "athlete_request",
    direction: "heavier",
    session: "next",
  };
  const earned = stateFixture({ progression: [progression(squat.slug!, 80, "add_load")] });
  const change = trainingOf(proposalOf(buildCoachProposal(intent, earned))) as Extract<
    TrainingChange,
    { mode: "block" }
  >;
  const raised = change.weekly_structure[0].exercises.filter((e) => e.start_load_kg !== undefined);
  assertEquals(raised.length, 1);
  assertEquals(raised[0].start_load_kg, 80 + step);

  for (
    const held of [
      stateFixture({ progression: [progression(squat.slug!, 80, "hold")] }),
      stateFixture({ progression: [progression(squat.slug!, 80, "add_load", "low")] }),
      stateFixture({ progression: [] }),
    ]
  ) {
    assertEquals(refusalOf(buildCoachProposal(intent, held)).code, "heavier_not_supported");
  }
  const unproven = stateFixture({
    progression: [progression(squat.slug!, 80, "add_load")],
    eligibility: {
      ...earned.eligibility,
      trainingEligible: false,
      trainingDetail: "0 comparable sessions",
    },
  });
  assertEquals(
    refusalOf(buildCoachProposal(intent, unproven)).code,
    "not_enough_training_evidence",
  );
});

Deno.test("today's session can be adjusted until it is done", () => {
  const monday = "2026-10-19";
  const intent: CoachProposalIntent = {
    kind: "next_session_adjustment",
    reason: "fatigue",
    direction: "lighter",
    session: "today",
  };
  const proposal = proposalOf(buildCoachProposal(intent, stateFixture({ today: monday })));
  assertEquals(
    (trainingOf(proposal) as Extract<TrainingChange, { mode: "block" }>).ends_on,
    monday,
  );
  assertEquals(
    refusalOf(buildCoachProposal(intent, stateFixture({ today: monday, todayWorkoutDone: true })))
      .code,
    "no_upcoming_session",
  );
  assertEquals(
    refusalOf(buildCoachProposal(intent, stateFixture({ today: "2026-10-20" }))).code,
    "no_upcoming_session",
  );
});

// ---- swaps, intensity and phases -----------------------------------------------------------

Deno.test("a swap replaces one exercise with a like-for-like substitute", () => {
  const state = stateFixture();
  const from = state.plan!.workouts[0].exercises.find((exercise) => exercise.slug !== null)!;
  const proposal = proposalOf(buildCoachProposal(
    { kind: "exercise_swap", reason: "preference", fromSlug: from.slug! },
    state,
  ));
  const change = trainingOf(proposal) as Extract<TrainingChange, { mode: "new_version" }>;
  const all = change.weekly_structure.flatMap((workout) => workout.exercises);
  assertEquals(all.some((exercise) => exercise.slug === from.slug), false);
  const replacement = all.find((exercise) => exercise.notes.startsWith("Replaces"))!;
  assertEquals(replacement.start_load_kg, undefined);
  assertEquals(replacement.sets, from.sets);
  assertEquals(change.weekly_structure.length, state.plan!.workouts.length);
});

Deno.test("a swap respects equipment, avoided movements and the named substitute", () => {
  const state = stateFixture();
  const from = state.plan!.workouts[0].exercises[0];
  const notALink = refusalOf(buildCoachProposal(
    { kind: "exercise_swap", reason: "preference", fromSlug: from.slug!, toSlug: "band-curl" },
    state,
  ));
  assertEquals(notALink.code, "substitute_not_allowed");
  assertEquals(
    refusalOf(
      buildCoachProposal({
        kind: "exercise_swap",
        reason: "preference",
        fromSlug: "no-such-exercise",
      }, state),
    ).code,
    "exercise_not_in_plan",
  );
  const bare = stateFixture({ profile: { ...state.profile, equipment: [] } });
  const bareRefusal = buildCoachProposal({
    kind: "exercise_swap",
    reason: "preference",
    fromSlug: from.slug!,
  }, bare);
  // The plan uses gym equipment the bare profile no longer owns, so no substitute fits.
  assertEquals(bareRefusal.ok, false);
});

Deno.test("a deload halves the sets at effort 7 or lower and ends on its own", () => {
  const state = stateFixture();
  const proposal = proposalOf(buildCoachProposal(
    { kind: "intensity_or_phase", reason: "fatigue", level: "deload", weeks: 1 },
    state,
  ));
  const change = trainingOf(proposal) as Extract<TrainingChange, { mode: "block" }>;
  assertEquals(change.block_kind, "intensity");
  assertEquals(change.ends_on, addDays(today, 6));
  change.weekly_structure.forEach((workout, w) => {
    workout.exercises.forEach((exercise, e) => {
      const before = state.plan!.workouts[w].exercises[e];
      assertEquals(exercise.sets, Math.max(1, Math.ceil(before.sets / 2)));
      assert(exercise.target_rpe! <= 7);
    });
  });
});

Deno.test("moderate effort caps effort and changes nothing under an existing cap", () => {
  const intent: CoachProposalIntent = {
    kind: "intensity_or_phase",
    reason: "illness_recovery",
    level: "moderate",
    weeks: 2,
  };
  const proposal = proposalOf(buildCoachProposal(intent, stateFixture()));
  const change = trainingOf(proposal) as Extract<TrainingChange, { mode: "block" }>;
  for (const workout of change.weekly_structure) {
    for (const e of workout.exercises) assert(e.target_rpe! <= 7);
  }
  assertEquals(
    refusalOf(buildCoachProposal(intent, stateFixture({ screening: "moderate_until_cleared" })))
      .code,
    "no_change",
  );
});

Deno.test("normal intensity ends a running phase and otherwise changes nothing", () => {
  const normal: CoachProposalIntent = {
    kind: "intensity_or_phase",
    reason: "athlete_request",
    level: "normal",
    weeks: 1,
  };
  assertEquals(refusalOf(buildCoachProposal(normal, stateFixture())).code, "no_change");
  const running = stateFixture({
    plan: planFor([1, 3, 5], { blockEndsOn: "2026-10-22", blockKind: "intensity" }),
  });
  const proposal = proposalOf(buildCoachProposal(normal, running));
  assertEquals(trainingOf(proposal), { mode: "end_block" });
  const travel = stateFixture({
    plan: planFor([1, 3, 5], { blockEndsOn: "2026-10-22", blockKind: "temporary_block" }),
  });
  assertEquals(refusalOf(buildCoachProposal(normal, travel)).code, "no_change");
});

Deno.test("a strength phase is capped by the screening and needs training evidence", () => {
  const intent: CoachProposalIntent = {
    kind: "intensity_or_phase",
    reason: "plateau",
    focus: "strength",
    weeks: 6,
  };
  const ok = proposalOf(buildCoachProposal(intent, stateFixture()));
  const change = trainingOf(ok) as Extract<TrainingChange, { mode: "block" }>;
  assertEquals(change.block_kind, "focus");
  assertEquals(change.ends_on, addDays(today, 41));
  const capped = refusalOf(
    buildCoachProposal(intent, stateFixture({ screening: "moderate_until_cleared" })),
  );
  assertEquals(capped.code, "screening_caps_intensity");
  assertStringIncludes(capped.reason, "moderate");
  const unproven = stateFixture({
    eligibility: { ...stateFixture().eligibility, trainingEligible: false, trainingDetail: "none" },
  });
  assertEquals(
    refusalOf(buildCoachProposal(intent, unproven)).code,
    "not_enough_training_evidence",
  );
  const size = proposalOf(
    buildCoachProposal({ ...intent, focus: "size" } as CoachProposalIntent, unproven),
  );
  assertEquals(size.kind, "intensity_or_phase");
});

// ---- invariants over every proposal ---------------------------------------------------------

Deno.test("every proposal is complete, serialisable and based on the current versions", () => {
  const state = withMessage("lower to 2100 kcal and 74 kg");
  const intents: CoachProposalIntent[] = [
    {
      kind: "temporary_block",
      reason: "travel",
      setting: "bodyweight",
      startDate: today,
      endDate: addDays(today, 9),
    },
    { kind: "training_schedule", reason: "time", daysPerWeek: 4, weeks: 8 },
    {
      kind: "exercise_swap",
      reason: "preference",
      fromSlug: state.plan!.workouts[0].exercises[0].slug!,
    },
    { kind: "intensity_or_phase", reason: "fatigue", level: "deload", weeks: 1 },
    { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
    { kind: "nutrition_targets", reason: "plateau", direction: "lower", requestedCalories: 2100 },
    { kind: "next_session_adjustment", reason: "fatigue", direction: "lighter", session: "next" },
  ];
  const kinds = new Set<string>();
  for (const intent of intents) {
    const proposal = proposalOf(buildCoachProposal(intent, state));
    kinds.add(proposal.kind);
    assertEquals(proposal.kind, intent.kind);
    assertEquals(JSON.parse(JSON.stringify(proposal)), proposal);
    assert(proposal.title.length > 0 && proposal.title.length <= 120);
    assert(proposal.rationale.length > 0 && proposal.rationale.length <= 2000);
    assert(proposal.benefit.length > 0 && proposal.benefit.length <= 1000);
    assert(proposal.downside.length > 0 && proposal.downside.length <= 1000);
    assert(proposal.evidence.length > 0);
    assert(proposal.expiresInHours > 0 && proposal.expiresInHours <= 72);
    assertEquals(proposal.basis, {
      training_version_id: state.plan!.versionId,
      nutrition_version_id: state.nutrition!.versionId,
      goal_id: state.goal!.id,
      screening: "cleared",
    });
    assertNotEquals(JSON.stringify(proposal.before), JSON.stringify(proposal.after));
    if (proposal.payload.nutrition) assertNutritionObeysRules(proposal.payload.nutrition, state);
  }
  assertEquals(kinds.size, 7);
  assertEquals(baseAnswers.goal, "fat_loss");
});

// ---- the payload shape the database accepts --------------------------------------------------

/**
 * A mirror of private.is_valid_coach_training / _nutrition / _goal in migration 18, so a change to
 * either side that breaks the other fails here before it fails in production.
 */
function assertStoredShape(proposal: CoachProposal) {
  const int = (value: unknown, low: number, high: number) =>
    typeof value === "number" && Number.isInteger(value) && value >= low && value <= high;
  const text = (value: unknown, low: number, high: number) =>
    typeof value === "string" && value.length >= low && value.length <= high;
  const { training, nutrition, goal } = proposal.payload;
  assert(training || nutrition || goal);
  if (training) {
    assert(["new_version", "block", "end_block"].includes(training.mode));
    if (training.mode !== "end_block") {
      assert(text(training.title, 1, 120) && int(training.block_weeks, 1, 24));
      assert(training.weekly_structure.length >= 1 && training.weekly_structure.length <= 7);
      if (training.mode === "block") assert(/^\d{4}-\d{2}-\d{2}$/.test(training.ends_on));
      if (training.mode === "new_version" && training.profile) {
        assert(int(training.profile.session_minutes, 15, 180));
        assert(training.profile.training_days.length >= 1);
      }
      assertEquals(
        new Set(training.weekly_structure.map((workout) => workout.workout_order)).size,
        training.weekly_structure.length,
      );
      for (const workout of training.weekly_structure) {
        assertEquals(Object.keys(workout).sort(), [
          "cool_down_guidance",
          "estimated_minutes",
          "exercises",
          "name",
          "objective",
          "preferred_weekday",
          "warm_up_guidance",
          "workout_order",
        ]);
        assert(int(workout.workout_order, 1, 7) && text(workout.name, 1, 120));
        assert(text(workout.objective, 1, 500));
        assert(workout.preferred_weekday === null || int(workout.preferred_weekday, 1, 7));
        assert(int(workout.estimated_minutes, 15, 180));
        assert(text(workout.warm_up_guidance, 1, 500) && text(workout.cool_down_guidance, 1, 500));
        assert(workout.exercises.length >= 1 && workout.exercises.length <= 30);
        for (const exercise of workout.exercises) {
          const keys = Object.keys(exercise).sort();
          assertEquals(
            keys.filter((key) => key !== "start_load_kg"),
            [
              "exercise_order",
              "name",
              "notes",
              "rep_max",
              "rep_min",
              "rest_seconds",
              "sets",
              "slug",
              "target_rpe",
            ],
          );
          assert(int(exercise.exercise_order, 1, 30) && int(exercise.sets, 1, 12));
          assert(int(exercise.rep_min, 1, 100) && int(exercise.rep_max, 1, 100));
          assert(exercise.rep_max >= exercise.rep_min);
          assert(exercise.slug === null || text(exercise.slug, 1, 80));
          assert(text(exercise.name, 1, 120) && text(exercise.notes, 0, 500));
          assert(
            exercise.target_rpe === null || (exercise.target_rpe >= 1 && exercise.target_rpe <= 10),
          );
          assert(int(exercise.rest_seconds, 15, 600));
          if ("start_load_kg" in exercise) {
            assert(exercise.start_load_kg! >= 0 && exercise.start_load_kg! <= 2000);
          }
        }
      }
    }
  }
  if (nutrition) {
    assert(int(nutrition.calories, 1000, 6000) && int(nutrition.protein_g, 30, 400));
    assert(int(nutrition.carbohydrate_g, 20, 1000) && int(nutrition.fat_g, 20, 300));
    assert(text(nutrition.rationale, 1, 2000));
  }
  if (goal) {
    assert(
      ["fat_loss", "muscle_gain", "recomposition", "strength", "aesthetic"].includes(
        goal.goal_type,
      ),
    );
    assert(["cut", "maintenance", "diet_break", "gain"].includes(goal.phase));
    assert(/^\d{4}-\d{2}-\d{2}$/.test(goal.phase_started_on));
    assert(goal.phase_ends_on === null || /^\d{4}-\d{2}-\d{2}$/.test(goal.phase_ends_on));
    if (goal.target) assert(goal.target.weight_kg! >= 30 && goal.target.weight_kg! <= 300);
  }
  assert(text(proposal.title, 1, 120) && text(proposal.rationale, 1, 2000));
  assert(text(proposal.benefit, 1, 1000) && text(proposal.downside, 1, 1000));
  assert(proposal.expiresInHours >= 1 && proposal.expiresInHours <= 168);
}

Deno.test("every proposal fits the shape the database stores", () => {
  const plan = stateFixture().plan!;
  const running = stateFixture({
    plan: planFor([1, 3, 5], { blockEndsOn: "2026-10-22", blockKind: "focus" }),
  });
  const state = withMessage("lower to 2100 kcal and 74 kg", {
    progression: [progression(plan.workouts[0].exercises[0].slug!, 60, "add_load")],
  });
  const intents: CoachProposalIntent[] = [
    {
      kind: "temporary_block",
      reason: "travel",
      setting: "bodyweight",
      startDate: today,
      endDate: addDays(today, 9),
    },
    {
      kind: "temporary_block",
      reason: "travel",
      setting: "minimal_equipment",
      startDate: today,
      endDate: addDays(today, 9),
    },
    { kind: "training_schedule", reason: "time", daysPerWeek: 5, weeks: 8, sessionMinutes: 45 },
    { kind: "training_schedule", reason: "time", daysPerWeek: 2, weeks: 4 },
    { kind: "exercise_swap", reason: "preference", fromSlug: plan.workouts[0].exercises[0].slug! },
    { kind: "intensity_or_phase", reason: "fatigue", level: "deload", weeks: 1 },
    { kind: "intensity_or_phase", reason: "fatigue", level: "moderate", weeks: 2 },
    { kind: "intensity_or_phase", reason: "plateau", focus: "size", weeks: 6 },
    { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
    {
      kind: "goal_or_phase",
      reason: "athlete_request",
      phase: "cut",
      targetWeightKg: 74,
      targetDate: "2027-06-01",
    },
    { kind: "nutrition_targets", reason: "plateau", direction: "lower", requestedCalories: 2100 },
    { kind: "next_session_adjustment", reason: "fatigue", direction: "lighter", session: "next" },
    {
      kind: "next_session_adjustment",
      reason: "athlete_request",
      direction: "heavier",
      session: "next",
    },
  ];
  for (const intent of intents) assertStoredShape(proposalOf(buildCoachProposal(intent, state)));
  assertStoredShape(proposalOf(buildCoachProposal(
    { kind: "intensity_or_phase", reason: "athlete_request", level: "normal", weeks: 1 },
    running,
  )));
});

Deno.test("a light athlete's floor is the sex minimum", () => {
  const state = withMessage("Lower my calories to 1,100", {
    profile: { ...stateFixture().profile, sex: "female", heightCm: 150, age: 30, birthYear: 1996 },
    goalPhase: stateWithReadings(weightReadings(30, 45)),
    nutrition: { ...stateFixture().nutrition!, calories: 1600 },
  });
  const refused = refusalOf(buildFromRawIntent({
    kind: "nutrition_targets",
    reason: "athlete_request",
    direction: "lower",
    requested_calories: 1100,
  }, state));
  assertEquals(refused.code, "below_calorie_floor");
  assertStringIncludes(refused.reason, "1,200 kcal");
});
