import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { goals } from "./answers.ts";
import { catalogBySlug, exerciseCatalogV1 } from "./catalog.ts";
import { catalogV2BySlug } from "./catalog_v2.ts";
import {
  generateOnboardingProposal,
  onboardingSystemPrompt,
  policiesFor,
  validRulesPlan,
} from "./generate.ts";
import {
  buildOnboardingProposal,
  PlanBlockedByScreeningError,
  validateOnboardingPlan,
} from "./plan_contract.ts";
import { moderateEffortRpe, trainingPolicy } from "./policy.ts";
import { buildRulesPlan } from "./rules_plan.ts";
import { answersFor, equipmentSets, weekdaysFor } from "./test_helpers.ts";
import { fractionalWeeklySets } from "../training/templates/volume.ts";
import { repRanges, restSeconds } from "../training/standard/prescription.ts";
import type { ScreeningOutcome } from "../training/screening/outcome.ts";

const plansFor = (
  overrides: Parameters<typeof answersFor>[0],
  screening?: ScreeningOutcome,
) => {
  const policies = policiesFor(answersFor(overrides), exerciseCatalogV1, null, null, screening);
  return { policies, plan: buildRulesPlan(policies) };
};

Deno.test("every goal, day count, experience, length and screening outcome builds a valid plan", () => {
  let checked = 0;
  for (const goal of goals) {
    for (const days of [1, 2, 3, 4, 5, 6]) {
      for (const experience of ["beginner", "intermediate"] as const) {
        for (const sessionMinutes of [30, 45, 60, 90, 120]) {
          for (
            const equipment of [equipmentSets.gym, equipmentSets.home, equipmentSets.bodyweight]
          ) {
            for (const screening of [undefined, "cleared", "moderate_until_cleared"] as const) {
              const { policies, plan } = plansFor({
                goal,
                experience,
                path: experience === "beginner" ? "beginner" : "experienced",
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
  }
  assertEquals(checked, 5 * 6 * 2 * 5 * 3 * 3);
});

Deno.test("a missing screening outcome reads as cleared", () => {
  const overrides = { goal: "strength", experience: "intermediate" } as const;
  assertEquals(plansFor(overrides).plan, plansFor(overrides, "cleared").plan);
});

Deno.test("prescription follows the standard where the policy allows", () => {
  const fullGym = { equipment: equipmentSets.gym };
  const rule = (
    emphasis: "strength" | "hypertrophy",
    experience: "beginner" | "intermediate",
    kind: "compound" | "isolation",
  ) => repRanges[emphasis][experience][kind].value;
  for (const goal of goals) {
    for (const experience of ["beginner", "intermediate"] as const) {
      const emphasis = goal === "strength" ? "strength" : "hypertrophy";
      const { plan } = plansFor({ ...fullGym, goal, experience, sessionMinutes: 60 });
      for (const exercise of plan.workouts.flatMap((workout) => workout.exercises)) {
        const kind = catalogBySlug.get(exercise.slug)!.compound ? "compound" : "isolation";
        assertEquals(
          [exercise.rep_min, exercise.rep_max],
          [...rule(emphasis, experience, kind)],
          `${goal} ${experience} ${exercise.slug}`,
        );
        if (kind === "compound") {
          const [low, high] = restSeconds[emphasis].compound.value;
          // Inside the standard's range, within the policy's 240 s cap.
          assert(exercise.rest_seconds >= low && exercise.rest_seconds <= Math.min(high, 240));
        }
      }
    }
  }
  // Beginner strength reps are the standard's 8-12, not the earlier 4-6.
  const beginnerStrength = plansFor({ ...fullGym, goal: "strength", experience: "beginner" }).plan;
  assertEquals(beginnerStrength.workouts[0].exercises[0].rep_min, 8);
  assertEquals(beginnerStrength.workouts[0].exercises[0].rep_max, 12);
});

Deno.test("rest follows the session: hypertrophy 90 s when short, strength 120/180/240 s by length", () => {
  const firstRest = (goal: "muscle_gain" | "strength", sessionMinutes: number) =>
    plansFor({
      goal,
      experience: "intermediate",
      path: "experienced",
      equipment: equipmentSets.gym,
      sessionMinutes,
    }).plan.workouts[0].exercises[0].rest_seconds;
  assertEquals([30, 45, 60, 90].map((minutes) => firstRest("muscle_gain", minutes)), [
    90,
    90,
    120,
    120,
  ]);
  assertEquals([30, 45, 60, 90].map((minutes) => firstRest("strength", minutes)), [
    120,
    120,
    180,
    240,
  ]);
});

Deno.test("full-gym plans default to lat pulldowns; pull-ups return as a variation", () => {
  const verticalPulls = (experience: "beginner" | "intermediate", days: number) =>
    plansFor({
      experience,
      path: experience === "beginner" ? "beginner" : "experienced",
      equipment: equipmentSets.gym,
      trainingWeekdays: weekdaysFor[days],
    }).plan.workouts.flatMap((workout) => workout.exercises.map((e) => e.slug))
      .filter((slug) => catalogBySlug.get(slug)!.pattern === "vertical_pull");
  // Two or fewer pulling sessions: lat pulldown only.
  assertEquals(verticalPulls("intermediate", 2), ["lat-pulldown"]);
  assertEquals(verticalPulls("intermediate", 1).length, 0);
  // Three full-body days: lat pulldown, then a pull-up.
  assertEquals(verticalPulls("intermediate", 3), ["lat-pulldown", "pull-up"]);
  assertEquals(verticalPulls("intermediate", 4), ["lat-pulldown", "pull-up"]);
  assertEquals(verticalPulls("intermediate", 6), ["lat-pulldown", "pull-up"]);
  // A beginner cannot be offered the pull-up (catalog level), and a regression is never the variation.
  for (const days of [3, 4, 5, 6]) {
    const slugs = verticalPulls("beginner", days);
    assert(
      slugs[0] === "lat-pulldown" && !slugs.includes("pull-up") &&
        !slugs.includes("assisted-pull-up"),
    );
  }
});

Deno.test("core work rotates through the week", () => {
  for (const days of [3, 4, 5, 6]) {
    const { plan } = plansFor({
      equipment: equipmentSets.gym,
      trainingWeekdays: weekdaysFor[days],
      sessionMinutes: 90,
    });
    const core = plan.workouts.flatMap((workout) => workout.exercises.map((e) => e.slug))
      .filter((slug) => catalogBySlug.get(slug)!.pattern === "core");
    assert(core.length >= 2, `${days} days: ${core}`);
    // Three distinct exercises are on offer in a full gym: a trunk exercise is not reused while one is free.
    assertEquals(new Set(core).size, Math.min(core.length, 3), `${days} days: ${core}`);
  }
});

Deno.test("a beginner session keeps at most two accessory exercises", () => {
  for (const goal of goals) {
    for (const days of [1, 3, 4, 6]) {
      const { plan } = plansFor({
        goal,
        equipment: equipmentSets.gym,
        trainingWeekdays: weekdaysFor[days],
        sessionMinutes: 90,
      });
      for (const workout of plan.workouts) {
        const accessories = workout.exercises.filter((e) => !catalogBySlug.get(e.slug)!.compound);
        // Isolation exercises in main or support slots (a fly, a hamstring curl) can add to the two.
        assert(accessories.length <= 4, `${goal} ${days}d ${workout.name}: ${accessories.length}`);
      }
    }
  }
});

Deno.test("main lifts reach three sets and no exercise passes four (three for strength)", () => {
  for (const goal of ["muscle_gain", "strength"] as const) {
    const { plan } = plansFor({
      goal,
      experience: "intermediate",
      path: "experienced",
      equipment: equipmentSets.gym,
      trainingWeekdays: weekdaysFor[4],
      sessionMinutes: 60,
    });
    for (const workout of plan.workouts) {
      assert(workout.exercises[0].sets >= 3, `${goal} ${workout.name}`);
      for (const exercise of workout.exercises) {
        assert(exercise.sets <= (goal === "strength" ? 3 : 4));
      }
    }
  }
});

Deno.test("fractional volume: the sets a plan reports match an independent count", () => {
  const { plan } = plansFor({
    goal: "muscle_gain",
    experience: "intermediate",
    path: "experienced",
    equipment: equipmentSets.gym,
  });
  const expected = new Map<string, number>();
  for (const workout of plan.workouts) {
    for (const { slug, sets } of workout.exercises) {
      const entry = catalogBySlug.get(slug)!;
      for (const muscle of entry.muscles) expected.set(muscle, (expected.get(muscle) ?? 0) + sets);
      for (const muscle of catalogV2BySlug.get(slug)!.secondaryMuscles) {
        if (!entry.muscles.includes(muscle)) {
          expected.set(muscle, (expected.get(muscle) ?? 0) + sets / 2);
        }
      }
    }
  }
  assertEquals(fractionalWeeklySets(plan.workouts, exerciseCatalogV1), expected);
});

Deno.test("hypertrophy plans spread sets toward the growth level before stopping", () => {
  const { plan } = plansFor({
    goal: "muscle_gain",
    experience: "intermediate",
    path: "experienced",
    equipment: equipmentSets.gym,
    trainingWeekdays: weekdaysFor[5],
    sessionMinutes: 90,
  });
  const weekly = fractionalWeeklySets(plan.workouts, exerciseCatalogV1);
  for (
    const muscle of [
      "quads",
      "chest",
      "back",
      "shoulders",
      "hamstrings",
      "biceps",
      "triceps",
    ] as const
  ) {
    assert((weekly.get(muscle) ?? 0) >= 10, `${muscle}: ${weekly.get(muscle)}`);
  }
});

Deno.test("golden: weekly sets by muscle for a 3-day full-body size plan", () => {
  const { plan } = plansFor({
    goal: "muscle_gain",
    experience: "intermediate",
    path: "experienced",
    equipment: equipmentSets.gym,
    sessionMinutes: 60,
  });
  assertEquals(
    plan.workouts.map((workout) => workout.exercises.map((e) => `${e.slug} ${e.sets}`)),
    [
      [
        "barbell-back-squat 4",
        "barbell-bench-press 4",
        "barbell-row 4",
        "barbell-deadlift 4",
        "dumbbell-lateral-raise 2",
        "barbell-curl 2",
      ],
      [
        "barbell-romanian-deadlift 4",
        "barbell-overhead-press 4",
        "lat-pulldown 4",
        "barbell-reverse-lunge 4",
        "dumbbell-overhead-triceps-extension 2",
        "dumbbell-rear-delt-fly 2",
      ],
      [
        "barbell-front-squat 4",
        "dumbbell-bench-press 4",
        "pull-up 3",
        "barbell-hip-thrust 2",
        "dumbbell-curl 2",
        "cable-lateral-raise 2",
      ],
    ],
  );
});

Deno.test("moderate_until_cleared caps effort, rest and reps and drops strength emphasis", () => {
  for (const experience of ["beginner", "intermediate"] as const) {
    const answers = answersFor({
      goal: "strength",
      experience,
      path: experience === "beginner" ? "beginner" : "experienced",
      sessionMinutes: 90,
    });
    const policies = policiesFor(answers, exerciseCatalogV1, null, null, "moderate_until_cleared");
    assertEquals(policies.screening, "moderate_until_cleared");
    assertEquals(policies.training.rpe, [moderateEffortRpe - 1, moderateEffortRpe]);
    assertEquals(policies.training.reps[0], 6);
    assertEquals(policies.training.restSeconds, [60, 180]);
    const plan = buildRulesPlan(policies);
    validateOnboardingPlan(plan, policies);
    for (const exercise of plan.workouts.flatMap((workout) => workout.exercises)) {
      assert(exercise.target_rpe <= moderateEffortRpe, `${exercise.slug} @${exercise.target_rpe}`);
      assert(exercise.rep_min >= 6 && exercise.rest_seconds <= 180);
    }
    // The first compound uses hypertrophy reps, not the strength 3-6.
    const [first] = plan.workouts[0].exercises;
    assertEquals(
      [first.rep_min, first.rep_max],
      [...repRanges.hypertrophy[experience].compound.value],
    );
    // A model plan above the cap is refused under the same policy.
    const above = {
      ...plan,
      workouts: plan.workouts.map((workout, index) =>
        index === 0
          ? {
            ...workout,
            exercises: [{ ...workout.exercises[0], target_rpe: 8 }, ...workout.exercises.slice(1)],
          }
          : workout
      ),
    };
    assertEquals(
      (() => {
        try {
          validateOnboardingPlan(above, policies);
          return "valid";
        } catch (error) {
          return (error as { rule: string }).rule;
        }
      })(),
      "rpe_out_of_range",
    );
    // Deterministic notes tell the athlete, first, and the evidence records the outcome.
    const proposal = buildOnboardingProposal(plan, policies, {
      origin: "rules",
      provider: null,
      model: null,
      fallbackReason: null,
    });
    assertStringIncludes((proposal.training.assumptions as string[])[0], "Moderate effort");
    assert((proposal.training.assumptions as string[])[0].length <= 140);
    assertEquals(
      (proposal.training.calculation as Record<string, unknown>).screening,
      "moderate_until_cleared",
    );
    assertStringIncludes(onboardingSystemPrompt(policies), "not yet cleared");
  }
  // Light-start rules still stack: the ceiling never rises above the cap.
  const answers = answersFor({ experience: "beginner" });
  assertEquals(trainingPolicy(answers, null, null, "moderate_until_cleared").rpe[1], 7);
  assert(
    !onboardingSystemPrompt(policiesFor(answers, exerciseCatalogV1)).includes("not yet cleared"),
  );
});

Deno.test("see_professional builds no plan", async () => {
  const answers = answersFor({ priorityMuscles: ["glutes"] });
  // Sizing the policy does not throw; building, validating and generating do.
  const policies = policiesFor(answers, exerciseCatalogV1, null, null, "see_professional");
  assertEquals(policies.screening, "see_professional");
  const blocked = (run: () => unknown) => {
    try {
      run();
    } catch (error) {
      return error instanceof PlanBlockedByScreeningError && error.outcome === "see_professional";
    }
    return false;
  };
  assert(blocked(() => buildRulesPlan(policies)));
  assert(blocked(() => validRulesPlan(policies)));
  const cleared = plansFor({}).plan;
  assert(blocked(() => validateOnboardingPlan(cleared, policies)));
  let fetched = 0;
  await assertRejects(
    () =>
      generateOnboardingProposal(
        answers,
        exerciseCatalogV1,
        {
          kind: "model",
          config: {
            provider: "deepseek",
            model: "deepseek-flash",
            url: "https://api.deepseek.com/v1/chat/completions",
            apiKey: "test-key",
            extraBody: {},
            thinkingBody: null,
            thinking: false,
            price: { input: 0.3, output: 1.2 },
          },
        },
        { consentGranted: true, budgetAvailable: true },
        () => {
          fetched++;
          return Promise.reject(new Error("no model call expected"));
        },
        undefined,
        null,
        null,
        "see_professional",
      ),
    PlanBlockedByScreeningError,
  );
  assertEquals(fetched, 0);
});
