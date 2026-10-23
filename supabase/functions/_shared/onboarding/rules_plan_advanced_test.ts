import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  advancedTrainingYears,
  answersSnapshot,
  goals,
  parseOnboardingAnswers,
} from "./answers.ts";
import { allowedExercises, catalogBySlug, exerciseCatalogV1 } from "./catalog.ts";
import { policiesFor } from "./generate.ts";
import { validateOnboardingPlan } from "./plan_contract.ts";
import { buildRulesPlan, weeklySetsByMuscle } from "./rules_plan.ts";
import { answersFor, equipmentSets, weekdaysFor } from "./test_helpers.ts";
import {
  repRanges,
  targetRepsInReserve,
  undulatedRepRange,
} from "../training/standard/prescription.ts";
import { weeklySetsPerMuscle } from "../training/standard/volume.ts";
import { weekTemplate } from "../training/templates/select.ts";
import { fractionalWeeklySets, weeklyTargets } from "../training/templates/volume.ts";
import { splitForDays } from "./policy.ts";
import type { ScreeningOutcome } from "../training/screening/outcome.ts";

const staples = [
  "weighted-pull-up",
  "close-grip-bench-press",
  "incline-barbell-bench-press",
  "bulgarian-split-squat",
] as const;

const advancedPlan = (
  overrides: Parameters<typeof answersFor>[0],
  screening?: ScreeningOutcome,
) => {
  const policies = policiesFor(
    answersFor({
      experience: "advanced",
      path: "experienced",
      trainingYears: "over_5",
      ...overrides,
    }),
    exerciseCatalogV1,
    null,
    null,
    screening,
  );
  return { policies, plan: buildRulesPlan(policies) };
};

const slugsOf = (plan: ReturnType<typeof buildRulesPlan>) =>
  plan.workouts.flatMap((workout) => workout.exercises.map((exercise) => exercise.slug));

// --- Level plumbing -------------------------------------------------------------------------

const payload = {
  goal: "muscle_gain",
  sex: "male",
  birth_year: 1990,
  height_cm: 180,
  weight_kg: 85,
  daily_activity: "mostly_sitting",
  training_weekdays: [1, 3, 5],
  session_minutes: 60,
  equipment_items: ["barbell", "bench"],
  current_plan: "Upper/lower",
  training_years: "over_5",
};

const experienceOf = (path: string, extra: Record<string, unknown>) => {
  const parsed = parseOnboardingAnswers(path, { ...payload, ...extra }, 2026);
  if (!parsed.ok) throw new Error(`expected answers: ${parsed.missing}`);
  return parsed.answers.experience;
};

Deno.test("advanced is the athlete's choice, from three years of training", () => {
  assertEquals(experienceOf("experienced", { experience: "advanced" }), "advanced");
  assertEquals(
    experienceOf("experienced", { experience: "advanced", training_years: "3_5" }),
    "advanced",
  );
  // Fewer years, the beginner path and an unknown value never reach advanced.
  assertEquals(
    experienceOf("experienced", { experience: "advanced", training_years: "1_2" }),
    "intermediate",
  );
  assertEquals(
    experienceOf("experienced", { experience: "advanced", training_years: "under_1" }),
    "beginner",
  );
  assertEquals(experienceOf("beginner", { experience: "advanced" }), "beginner");
  assertEquals(experienceOf("experienced", { experience: "expert" }), "intermediate");
  // The athlete who did not choose it, and every older draft, stay intermediate.
  assertEquals(experienceOf("experienced", { experience: "intermediate" }), "intermediate");
  assertEquals(experienceOf("experienced", {}), "intermediate");
  const { training_years: _years, ...older } = payload;
  const withoutYears = parseOnboardingAnswers(
    "experienced",
    { ...older, experience: "advanced" },
    2026,
  );
  assert(withoutYears.ok && withoutYears.answers.experience === "intermediate");
  assertEquals([...advancedTrainingYears], ["3_5", "over_5"]);
});

Deno.test("the level is part of the answers snapshot, so a changed level builds a new plan", () => {
  const snapshot = (experience: string) => {
    const parsed = parseOnboardingAnswers("experienced", { ...payload, experience }, 2026);
    if (!parsed.ok) throw new Error("expected answers");
    return answersSnapshot(parsed.answers);
  };
  assertEquals(snapshot("advanced").experience, "advanced");
  assertEquals(snapshot("intermediate").experience, "intermediate");
  // Nothing else in the snapshot moves, so existing drafts keep their hashes.
  assertEquals({ ...snapshot("advanced"), experience: "" }, {
    ...snapshot("intermediate"),
    experience: "",
  });
});

Deno.test("only an advanced athlete is offered the advanced staples", () => {
  const equipment = equipmentSets.gym;
  for (const experience of ["beginner", "intermediate"] as const) {
    const offered = allowedExercises(exerciseCatalogV1, equipment, experience).map((e) => e.slug);
    for (const slug of staples) assert(!offered.includes(slug), `${experience} sees ${slug}`);
  }
  const advanced = allowedExercises(exerciseCatalogV1, equipment, "advanced").map((e) => e.slug);
  for (const slug of staples) assert(advanced.includes(slug), slug);
  // Equipment still decides: no dumbbells, no weighted pull-up or Bulgarian split squat; no
  // barbell, no bench press variations.
  const noDumbbells = allowedExercises(
    exerciseCatalogV1,
    ["barbell", "bench", "pull_up_bar"],
    "advanced",
  )
    .map((e) => e.slug);
  assert(
    !noDumbbells.includes("weighted-pull-up") && !noDumbbells.includes("bulgarian-split-squat"),
  );
  assert(noDumbbells.includes("close-grip-bench-press"));
  const noBarbell = allowedExercises(
    exerciseCatalogV1,
    ["dumbbells", "bench", "pull_up_bar"],
    "advanced",
  )
    .map((e) => e.slug);
  assert(noBarbell.includes("weighted-pull-up") && noBarbell.includes("bulgarian-split-squat"));
  assert(!noBarbell.includes("close-grip-bench-press"));
});

// --- Validity and screening -------------------------------------------------------------------

Deno.test("every goal, day count, length, equipment set and screening outcome builds a valid advanced plan", () => {
  let checked = 0;
  for (const goal of goals) {
    for (const days of [1, 2, 3, 4, 5, 6]) {
      for (const sessionMinutes of [30, 45, 60, 90, 120]) {
        for (const equipment of Object.values(equipmentSets)) {
          for (const screening of [undefined, "cleared", "moderate_until_cleared"] as const) {
            const { policies, plan } = advancedPlan({
              goal,
              trainingWeekdays: weekdaysFor[days],
              sessionMinutes,
              equipment,
            }, screening);
            validateOnboardingPlan(plan, policies);
            assertEquals(plan.workouts.length, days);
            checked++;
          }
        }
      }
    }
  }
  assertEquals(checked, 5 * 6 * 5 * 4 * 3);
});

Deno.test("advanced never bypasses screening: moderate effort caps the plan, see_professional builds none", () => {
  for (const goal of ["strength", "muscle_gain"] as const) {
    const { policies, plan } = advancedPlan({ goal, sessionMinutes: 90 }, "moderate_until_cleared");
    assertEquals(policies.training.rpe, [6, 7]);
    for (const exercise of plan.workouts.flatMap((workout) => workout.exercises)) {
      assert(exercise.target_rpe <= 7, `${exercise.slug} @${exercise.target_rpe}`);
      assert(exercise.rep_min >= 6 && exercise.rest_seconds <= 180, exercise.slug);
    }
    // Hypertrophy reps, split into heavy and light days: never the strength 3-6.
    const [first] = plan.workouts[0].exercises;
    assertEquals(
      [first.rep_min, first.rep_max],
      [...undulatedRepRange(repRanges.hypertrophy.advanced.compound.value, "heavy")],
    );
  }
  let error: unknown;
  try {
    advancedPlan({}, "see_professional");
  } catch (caught) {
    error = caught;
  }
  assertEquals((error as Error | undefined)?.name, "PlanBlockedByScreeningError");
});

// --- Prescription -----------------------------------------------------------------------------

Deno.test("heavy and light days split the compound range; isolation and the range's ends are the standard's", () => {
  assertEquals(undulatedRepRange([3, 6], "heavy"), [3, 4]);
  assertEquals(undulatedRepRange([3, 6], "light"), [5, 6]);
  assertEquals(undulatedRepRange([6, 12], "heavy"), [6, 9]);
  assertEquals(undulatedRepRange([6, 12], "light"), [10, 12]);
  for (const goal of goals) {
    for (const days of [1, 2, 3, 4, 5, 6]) {
      const emphasis = goal === "strength" ? "strength" : "hypertrophy";
      const { policies, plan } = advancedPlan({ goal, trainingWeekdays: weekdaysFor[days] });
      const template = weekTemplate({
        split: splitForDays(days),
        goal,
        experience: "advanced",
        sessionMinutes: policies.answers.sessionMinutes,
      }, days);
      plan.workouts.forEach((workout, index) => {
        const load = template.days[index].load;
        for (const exercise of workout.exercises) {
          const kind = catalogBySlug.get(exercise.slug)!.compound ? "compound" : "isolation";
          const standard = repRanges[emphasis].advanced[kind].value;
          const expected = kind === "compound" && load
            ? undulatedRepRange(standard, load)
            : standard;
          assertEquals(
            [exercise.rep_min, exercise.rep_max],
            [...expected],
            `${goal} ${days}d ${workout.name} ${exercise.slug}`,
          );
        }
      });
    }
  }
});

Deno.test("every muscle meets a heavy and a light day in the week", () => {
  for (const days of [2, 4, 5, 6]) {
    const loads = weekTemplate({
      split: splitForDays(days),
      goal: "muscle_gain",
      experience: "advanced",
      sessionMinutes: 60,
    }, days).days.map((day) => day.load);
    assert(loads.includes("heavy") && loads.includes("light"), `${days} days: ${loads}`);
  }
  // The third full-body session keeps the whole range; intermediates have no heavy or light days.
  assertEquals(
    weekTemplate({
      split: "full_body",
      goal: "strength",
      experience: "advanced",
      sessionMinutes: 60,
    }, 3)
      .days.map((day) => day.load),
    ["heavy", "light", undefined],
  );
  for (const experience of ["beginner", "intermediate"] as const) {
    const template = weekTemplate(
      { split: "push_pull_legs", goal: "muscle_gain", experience, sessionMinutes: 60 },
      6,
    );
    for (const day of template.days) {
      assertEquals(day.load, undefined);
      assert(day.slots.every((slot) => slot.prefers === undefined));
    }
  }
});

Deno.test("effort stays the standard's reps in reserve; the plan's text names the heavy and light days", () => {
  assertEquals([...targetRepsInReserve.advanced.value], [
    ...targetRepsInReserve.intermediate.value,
  ]);
  const { plan } = advancedPlan({ goal: "muscle_gain" });
  assertStringIncludes(plan.progression, "Heavy and light days");
  assert(plan.progression.length <= 200);
  for (const workout of plan.workouts) assert(workout.objective.length <= 140, workout.name);
  // Compound lifts stop mid-range of 1-3 reps left: RPE 8; isolation at 2 reps left.
  for (const exercise of plan.workouts.flatMap((workout) => workout.exercises)) {
    assertEquals(exercise.target_rpe, 8, exercise.slug);
  }
});

// --- Volume -----------------------------------------------------------------------------------

Deno.test("an advanced lifter's weekly targets start at 12 sets and stretch toward 16, never past 20", () => {
  const muscles = ["quads", "back", "core"] as const;
  assertEquals(weeklyTargets("hypertrophy", "advanced", muscles), { quads: 12, back: 12, core: 4 });
  assertEquals(weeklyTargets("hypertrophy", "advanced", muscles, true), {
    quads: 16,
    back: 16,
    core: 4,
  });
  assertEquals(weeklyTargets("strength", "advanced", muscles), { quads: 6, back: 6, core: 4 });
  assertEquals(weeklySetsPerMuscle.maximum.advanced.value, 20);
  // The intermediate targets are unchanged.
  assertEquals(weeklyTargets("hypertrophy", "intermediate", muscles, true), {
    quads: 15,
    back: 15,
    core: 4,
  });
});

Deno.test("an advanced plan never passes the policy's weekly maximum and trains each major muscle", () => {
  for (const goal of ["muscle_gain", "aesthetic", "strength"] as const) {
    for (const days of [3, 4, 5, 6]) {
      const { plan } = advancedPlan({
        goal,
        trainingWeekdays: weekdaysFor[days],
        sessionMinutes: 90,
      });
      for (const [muscle, sets] of weeklySetsByMuscle(plan.workouts, exerciseCatalogV1)) {
        assert(sets <= 20, `${goal} ${days}d ${muscle}: ${sets}`);
      }
      const weekly = fractionalWeeklySets(plan.workouts, exerciseCatalogV1);
      for (const muscle of ["quads", "back", "shoulders", "biceps", "triceps"] as const) {
        assert(
          (weekly.get(muscle) ?? 0) >= (goal === "strength" ? 6 : 10),
          `${goal} ${days}d ${muscle}`,
        );
      }
    }
  }
});

Deno.test("an advanced plan on fewer than four days says what the standard recommends", () => {
  const three = advancedPlan({ trainingWeekdays: weekdaysFor[3] }).plan;
  const note = three.assumptions.find((line) => line.includes("ACSM 2009"));
  assertEquals(
    note,
    "Advanced lifters often train 4-5 days a week (ACSM 2009); on 3, each session carries more of the weekly volume.",
  );
  assert(note!.length <= 140);
  assertEquals(advancedPlan({ trainingWeekdays: weekdaysFor[4] }).plan.assumptions.length, 1);
  assertEquals(
    advancedPlan({ experience: "intermediate", trainingWeekdays: weekdaysFor[3] }).plan.assumptions
      .length,
    1,
  );
});

// --- The staples ----------------------------------------------------------------------------------

Deno.test("an advanced plan meets the staples its equipment allows, and nobody else does", () => {
  // Four days, full gym: weighted pull-up (Upper A), close-grip bench (Upper B), Bulgarian (Lower A).
  const four = slugsOf(
    advancedPlan({ goal: "muscle_gain", trainingWeekdays: weekdaysFor[4] }).plan,
  );
  for (const slug of ["weighted-pull-up", "close-grip-bench-press", "bulgarian-split-squat"]) {
    assert(four.includes(slug), `4 days: ${slug} in ${four}`);
  }
  // Five days: the push day presses on an incline.
  const five = slugsOf(advancedPlan({ goal: "aesthetic", trainingWeekdays: weekdaysFor[5] }).plan);
  assert(five.includes("incline-barbell-bench-press"), `${five}`);
  // The Bulgarian split squat is used once a week, in the first leg session that wants it.
  assertEquals(five.filter((slug) => slug === "bulgarian-split-squat").length, 1);
  // Dumbbells and a bar are enough for the weighted pull-up; a home kit has no barbell press.
  const home = slugsOf(
    advancedPlan({ equipment: equipmentSets.home, trainingWeekdays: weekdaysFor[4] }).plan,
  );
  assert(home.includes("weighted-pull-up") && home.includes("bulgarian-split-squat"), `${home}`);
  assert(!home.includes("close-grip-bench-press"));
  // Beginner and intermediate plans never contain one.
  for (const experience of ["beginner", "intermediate"] as const) {
    for (const days of [3, 4, 5, 6]) {
      const { plan } = advancedPlan({ experience, trainingWeekdays: weekdaysFor[days] });
      for (const slug of slugsOf(plan)) {
        assert(!staples.includes(slug as never), `${experience} ${slug}`);
      }
    }
  }
});

Deno.test("a focus muscle still comes before a preferred exercise", () => {
  // Hamstrings are the focus: the single-leg slot prefers the Bulgarian split squat only after the
  // focus muscle's sets are met, and the focus minimum is reached either way.
  const { policies, plan } = advancedPlan({
    goal: "muscle_gain",
    trainingWeekdays: weekdaysFor[4],
    priorityMuscles: ["hamstrings"],
  });
  validateOnboardingPlan(plan, policies);
  const direct = weeklySetsByMuscle(plan.workouts, exerciseCatalogV1);
  for (const priority of policies.training.priorityMinimums) {
    assert((direct.get(priority.muscle) ?? 0) >= priority.sets, priority.muscle);
  }
});

Deno.test("golden: a four-day size plan for an advanced lifter in a full gym", () => {
  const { plan } = advancedPlan({
    goal: "muscle_gain",
    trainingWeekdays: weekdaysFor[4],
    sessionMinutes: 60,
  });
  assertEquals(
    plan.workouts.map((workout) =>
      `${workout.name}: ${
        workout.exercises.map((e) => `${e.slug} ${e.sets}x${e.rep_min}-${e.rep_max}`).join(", ")
      }`
    ),
    [
      "Upper A: barbell-bench-press 4x6-9, barbell-row 4x6-9, barbell-overhead-press 2x6-9, weighted-pull-up 3x6-9, dumbbell-lateral-raise 2x10-15, dumbbell-overhead-triceps-extension 2x10-15",
      "Lower A: barbell-back-squat 4x6-9, barbell-deadlift 4x6-9, bulgarian-split-squat 4x6-9, lying-leg-curl 3x10-15, dumbbell-calf-raise 3x10-15, cable-crunch 2x10-15",
      "Upper B: lat-pulldown 4x10-12, dumbbell-shoulder-press 4x10-12, chest-supported-dumbbell-row 2x10-12, close-grip-bench-press 4x10-12, dumbbell-rear-delt-fly 2x10-15, barbell-curl 3x10-15",
      "Lower B: barbell-romanian-deadlift 4x10-12, barbell-front-squat 4x10-12, leg-extension 2x10-15, barbell-hip-thrust 2x10-12, seated-calf-raise 3x10-15, hanging-knee-raise 2x10-15",
    ],
  );
});
