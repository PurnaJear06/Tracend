import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { catalogBySlug } from "../onboarding/catalog.ts";
import { catalogV2BySlug, loadStepKgFor } from "../onboarding/catalog_v2.ts";
import type { ProgressionTarget } from "../training/progression/targets.ts";
import { buildCoachProposal } from "./build.ts";
import { plannedExerciseIdFor, proposalRpcPayloads, stateFixture } from "./fixtures.ts";
import { parseAthleteState } from "./state.ts";
import { isRefusal, rulesTraining } from "./plan_rules.ts";
import { swapCandidates } from "./training.ts";
import type { AthleteState, StatePlanExercise, TrainingChange } from "./types.ts";

const withExperience = (experience: string) => {
  const data = structuredClone(proposalRpcPayloads());
  data.inputs.profile.experience = experience;
  return parseAthleteState(data);
};

Deno.test("the athlete's level reaches the rules as it is stored, advanced included", () => {
  assertEquals(withExperience("beginner")?.profile.experience, "beginner");
  assertEquals(withExperience("intermediate")?.profile.experience, "intermediate");
  assertEquals(withExperience("advanced")?.profile.experience, "advanced");
  assertEquals(withExperience("expert"), null);
});

Deno.test("swaps offer the advanced staples only to an advanced athlete, and never a harsher joint rating", () => {
  const level = (experience: "intermediate" | "advanced") =>
    stateFixture({ profile: { ...stateFixture().profile, experience } });
  const slugs = (from: string, experience: "intermediate" | "advanced") =>
    swapCandidates(from, level(experience), []).map((exercise) => exercise.slug);
  // A close-grip bench press replaces the bench press at the same shoulder rating; an
  // intermediate is not offered it.
  assert(slugs("barbell-bench-press", "advanced").includes("close-grip-bench-press"));
  assert(!slugs("barbell-bench-press", "intermediate").includes("close-grip-bench-press"));
  // The lat pulldown lists the weighted pull-up as a substitute and an advanced athlete may do it,
  // but it would load the shoulder harder: only the joint rule keeps it from being offered, while
  // the way back from it is.
  assert(catalogV2BySlug.get("lat-pulldown")!.substitutes.includes("weighted-pull-up"));
  assert(!slugs("lat-pulldown", "advanced").includes("weighted-pull-up"));
  assert(slugs("weighted-pull-up", "advanced").includes("lat-pulldown"));
  // The Bulgarian split squat loads the knee harder than the step-up and the lunge, so it is not
  // offered as their swap either; the swap away from it is.
  assert(!slugs("dumbbell-step-up", "advanced").includes("bulgarian-split-squat"));
  assert(slugs("bulgarian-split-squat", "advanced").includes("dumbbell-step-up"));
});

// ---- heavy and light days of one lift: each planned exercise has its own target -----------------

const heavyDay = 0;
const lightDay = 1;
/** A plan whose first two days both train the bench press: heavy (5-6 reps) and light (10-12). */
function splitBenchState(progression: ReturnType<typeof benchTarget>[]) {
  const base = stateFixture();
  const bench = (day: number, repMin: number, repMax: number): StatePlanExercise => ({
    plannedExerciseId: plannedExerciseIdFor(day, 0),
    slug: "barbell-bench-press",
    name: "Barbell Bench Press",
    sets: 3,
    repMin,
    repMax,
    targetRpe: 8,
    restSeconds: 150,
    notes: "",
    targetLoadKg: null,
  });
  const workouts = base.plan!.workouts.map((workout, index) =>
    index === heavyDay
      ? { ...workout, exercises: [bench(heavyDay, 5, 6)] }
      : index === lightDay
      ? { ...workout, exercises: [bench(lightDay, 10, 12)] }
      : workout
  );
  return stateFixture({ plan: { ...base.plan!, workouts }, progression });
}

const benchTarget = (day: number, loadKg: number): ProgressionTarget => ({
  plannedExerciseId: plannedExerciseIdFor(day, 0),
  exerciseKey: "barbell-bench-press",
  name: "Barbell Bench Press",
  action: "add_load",
  reason: "top_of_range",
  loadKg,
  reps: day === heavyDay ? 5 : 10,
  sets: 3,
  confidence: "high",
  lastDate: "2026-10-16",
  recent: [{ localDate: "2026-10-16", loadKg, sets: 3, minReps: 10, minRir: 2 }],
});

const step = loadStepKgFor(catalogBySlug.get("barbell-bench-press")!)!;

function nextSessionLoad(
  state: AthleteState,
  direction: "heavier" | "lighter",
  day: number,
): number | undefined {
  const result = buildCoachProposal(
    { kind: "next_session_adjustment", reason: "athlete_request", direction, session: "today" },
    { ...state, today: day === heavyDay ? heavyMonday : lightWednesday, todayWorkoutDone: false },
  );
  if (!result.ok) throw new Error(`refused: ${result.code}`);
  const change = result.proposal.payload.training as Extract<TrainingChange, { mode: "block" }>;
  return change.weekly_structure[day].exercises[0].start_load_kg;
}

// 2026-10-19 is a Monday (the heavy day, weekday 1); 2026-10-21 a Wednesday (the light day).
const heavyMonday = "2026-10-19";
const lightWednesday = "2026-10-21";

Deno.test("a lighter light day starts from the light day's own target, not the heavy day's", () => {
  const state = splitBenchState([benchTarget(heavyDay, 105), benchTarget(lightDay, 82.5)]);
  assertEquals(nextSessionLoad(state, "lighter", lightDay), 82.5 - step);
  assertEquals(nextSessionLoad(state, "lighter", heavyDay), 105 - step);
});

Deno.test("a heavier light day adds a step to the light day's target", () => {
  const state = splitBenchState([benchTarget(heavyDay, 105), benchTarget(lightDay, 82.5)]);
  assertEquals(nextSessionLoad(state, "heavier", lightDay), 82.5 + step);
  assertEquals(nextSessionLoad(state, "heavier", heavyDay), 105 + step);
});

Deno.test("a light day without a target of its own never borrows the heavy day's", () => {
  const state = splitBenchState([benchTarget(heavyDay, 105)]);
  // No light history: the load is unknown, so a lighter day lowers sets and effort but keeps no load.
  assertEquals(nextSessionLoad(state, "lighter", lightDay), undefined);
  // Heavier needs a target of the light day's own; the heavy day's is not a basis.
  const refused = buildCoachProposal(
    {
      kind: "next_session_adjustment",
      reason: "athlete_request",
      direction: "heavier",
      session: "today",
    },
    { ...state, today: lightWednesday, todayWorkoutDone: false },
  );
  assert(!refused.ok);
  assertEquals(refused.code, "heavier_not_supported");
});

Deno.test("a plan payload without planned exercise ids has no targets to match", () => {
  const data = structuredClone(proposalRpcPayloads());
  for (const workout of data.inputs.plan!.workouts) {
    for (const exercise of workout.exercises) {
      delete (exercise as { planned_exercise_id?: string }).planned_exercise_id;
    }
  }
  const state = parseAthleteState(data)!;
  assert(
    state.plan!.workouts.every((workout) =>
      workout.exercises.every((exercise) => exercise.plannedExerciseId === null)
    ),
  );
});

// ---- a rebuilt plan carries loads per range for a lift on a heavy and a light day ---------------

/** The fixture plan with the bench press on its first two days, in the given ranges and loads. */
function benchPlan(days: readonly { repMin: number; repMax: number; loadKg: number | null }[]) {
  const base = stateFixture().plan!;
  const workouts = base.workouts.map((workout, index) =>
    index < days.length
      ? {
        ...workout,
        exercises: [{
          plannedExerciseId: plannedExerciseIdFor(index, 0),
          slug: "barbell-bench-press",
          name: "Barbell Bench Press",
          sets: 3,
          repMin: days[index].repMin,
          repMax: days[index].repMax,
          targetRpe: 8,
          restSeconds: 150,
          notes: "",
          targetLoadKg: days[index].loadKg,
        }],
      }
      : workout
  );
  return { ...base, workouts };
}

/** Each bench in the plan rebuilt for an advanced athlete: its range and the load it starts at. */
function rebuiltBenches(old: ReturnType<typeof benchPlan>) {
  const state = stateFixture({
    profile: { ...stateFixture().profile, experience: "advanced" },
    plan: old,
  });
  const rebuilt = rulesTraining(state, {}, old);
  if (isRefusal(rebuilt)) throw new Error(`refused: ${rebuilt.code}`);
  return rebuilt.workouts.flatMap((workout) =>
    workout.exercises.filter((exercise) => exercise.slug === "barbell-bench-press").map((e) => ({
      range: `${e.rep_min}-${e.rep_max}`,
      load: e.start_load_kg,
    }))
  );
}

Deno.test("a rebuilt plan gives each range of a lift on two days its own load", () => {
  const benches = rebuiltBenches(
    benchPlan([{ repMin: 6, repMax: 9, loadKg: 100 }, { repMin: 10, repMax: 12, loadKg: 80 }]),
  );
  assert(benches.length > 0);
  for (const bench of benches) {
    assertEquals(
      bench.load,
      bench.range === "6-9" ? 100 : bench.range === "10-12" ? 80 : undefined,
    );
  }
  assert(benches.some((bench) => bench.range === "6-9" && bench.load === 100));
});

Deno.test("a rebuilt plan carries nothing for a split lift whose ranges no longer match", () => {
  const benches = rebuiltBenches(
    benchPlan([{ repMin: 5, repMax: 6, loadKg: 105 }, { repMin: 10, repMax: 12, loadKg: 82.5 }]),
  );
  assert(benches.length > 0);
  for (const bench of benches) {
    assertEquals(bench.load, bench.range === "10-12" ? 82.5 : undefined);
  }
  assert(benches.some((bench) => bench.range === "6-9"));
});

Deno.test("a rebuilt plan still carries a lift held in one range by its slug", () => {
  const benches = rebuiltBenches(
    benchPlan([{ repMin: 8, repMax: 10, loadKg: 90 }, { repMin: 8, repMax: 10, loadKg: 92.5 }]),
  );
  assert(benches.length > 0);
  for (const bench of benches) assertEquals(bench.load, 92.5);
});
