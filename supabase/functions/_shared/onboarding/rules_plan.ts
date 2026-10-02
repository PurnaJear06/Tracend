import { allowedExercises, type CatalogExercise, type MovementPattern } from "./catalog.ts";
import type { OnboardingPlan, PlanExercise, PlanPolicies, PlanWorkout } from "./plan_contract.ts";
import { estimateWorkoutMinutes, nutritionBounds, type Split } from "./policy.ts";

// The rules plan: a complete onboarding plan built only by deterministic code
// from onboarding-policy-v2 and the catalog. It is used whenever a model is
// not used (no AI consent, no evaluated provider, budget reached) or its plan
// fails validation after one repair, so every athlete gets a valid plan.

type Slot = readonly MovementPattern[];

// When a slot has nothing the athlete can do (equipment, or a movement they
// avoid), its sibling pattern fills it, so a day keeps its balance.
const substitutes: Readonly<Partial<Record<MovementPattern, readonly MovementPattern[]>>> = {
  squat: ["lunge"],
  lunge: ["squat"],
  horizontal_push: ["vertical_push"],
  vertical_push: ["horizontal_push"],
  horizontal_pull: ["vertical_pull"],
  vertical_pull: ["horizontal_pull"],
};
type DayTemplate = Readonly<{ name: string; objective: string; slots: readonly Slot[] }>;

const fullBodyA: DayTemplate = {
  name: "Full body A",
  objective: "Squat, press and row patterns with a hinge, at a repeatable effort.",
  slots: [["squat"], ["horizontal_push"], ["horizontal_pull", "vertical_pull"], ["hinge"], [
    "core",
  ], ["lateral_raise", "biceps"]],
};
const fullBodyB: DayTemplate = {
  name: "Full body B",
  objective: "Hinge, overhead press and pulling, with single-leg work.",
  slots: [
    ["hinge"],
    ["vertical_push", "horizontal_push"],
    ["vertical_pull", "horizontal_pull"],
    [
      "lunge",
      "squat",
    ],
    ["core"],
    ["triceps", "calves"],
  ],
};
const fullBodyC: DayTemplate = {
  name: "Full body C",
  objective: "A second squat and press day with arm and trunk accessories.",
  slots: [["squat", "lunge"], ["horizontal_push"], ["horizontal_pull"], ["hinge"], ["biceps"], [
    "core",
  ]],
};
const upperA: DayTemplate = {
  name: "Upper A",
  objective: "Horizontal pressing and pulling first, then shoulders and arms.",
  slots: [
    ["horizontal_push"],
    ["horizontal_pull"],
    ["vertical_push"],
    [
      "vertical_pull",
      "horizontal_pull",
    ],
    ["lateral_raise", "rear_delts"],
    ["triceps"],
    ["biceps"],
  ],
};
const upperB: DayTemplate = {
  name: "Upper B",
  objective: "Vertical pulling and pressing first, then upper-back and arm work.",
  slots: [
    ["vertical_pull", "horizontal_pull"],
    ["vertical_push", "horizontal_push"],
    [
      "horizontal_pull",
    ],
    ["horizontal_push"],
    ["rear_delts", "lateral_raise"],
    ["biceps"],
    ["triceps"],
  ],
};
const lowerA: DayTemplate = {
  name: "Lower A",
  objective: "Squat-led lower body with a hinge and single-leg work.",
  slots: [["squat"], ["hinge"], ["lunge"], ["hamstring_curl", "hinge"], ["calves"], ["core"]],
};
const lowerB: DayTemplate = {
  name: "Lower B",
  objective: "Hinge-led lower body with quad and hamstring accessories.",
  slots: [
    ["hinge"],
    ["squat", "lunge"],
    ["quads_isolation", "lunge"],
    [
      "hamstring_curl",
      "hinge",
    ],
    ["calves"],
    ["core"],
  ],
};
const push: DayTemplate = {
  name: "Push",
  objective: "Chest, shoulders and triceps.",
  slots: [
    ["horizontal_push"],
    ["vertical_push"],
    ["chest_fly", "horizontal_push"],
    [
      "lateral_raise",
    ],
    ["triceps"],
    ["core"],
  ],
};
const pull: DayTemplate = {
  name: "Pull",
  objective: "Back, rear shoulders and biceps.",
  slots: [
    ["vertical_pull", "horizontal_pull"],
    ["horizontal_pull"],
    [
      "rear_delts",
      "horizontal_pull",
    ],
    ["biceps"],
    ["core"],
  ],
};
const legs: DayTemplate = {
  name: "Legs",
  objective: "Squat, hinge and single-leg work with leg accessories.",
  slots: [["squat"], ["hinge"], ["lunge"], ["quads_isolation", "squat"], [
    "hamstring_curl",
    "hinge",
  ], ["calves"]],
};

const templates: Readonly<Record<Split, (days: number) => DayTemplate[]>> = {
  full_body: (days) => [fullBodyA, fullBodyB, fullBodyC].slice(0, days),
  upper_lower: () => [upperA, lowerA, upperB, lowerB],
  upper_lower_push_pull_legs: () => [upperA, lowerA, push, pull, legs],
  push_pull_legs: () => [
    push,
    pull,
    legs,
    { ...push, name: "Push 2" },
    { ...pull, name: "Pull 2" },
    { ...legs, name: "Legs 2" },
  ],
};

function prescription(
  exercise: CatalogExercise,
  policies: PlanPolicies,
): Omit<PlanExercise, "slug" | "sets" | "notes"> {
  const { answers, training } = policies;
  const strength = answers.goal === "strength";
  const beginner = answers.experience === "beginner";
  // Short sleep starts the block half a point easier (trainingPolicy).
  const lighter = training.startLighter ? 0.5 : 0;
  if (exercise.compound) {
    return {
      rep_min: strength ? 4 : beginner ? 8 : 6,
      rep_max: strength ? 6 : beginner ? 12 : 10,
      target_rpe: (beginner ? 7.5 : 8) - lighter,
      // A session of 45 minutes or less keeps rests at two minutes, so it can
      // still cover its movement patterns.
      rest_seconds: Math.min(
        training.restSeconds[1],
        answers.sessionMinutes <= 45 ? 120 : strength ? 180 : 150,
      ),
    };
  }
  return { rep_min: 10, rep_max: 15, target_rpe: 8 - lighter, rest_seconds: 75 };
}

/** Weekly sets per target muscle (the catalog's first muscle). */
export function weeklySetsByMuscle(
  workouts: readonly PlanWorkout[],
  catalog: readonly CatalogExercise[],
): Map<string, number> {
  const bySlug = new Map(catalog.map((exercise) => [exercise.slug, exercise]));
  const totals = new Map<string, number>();
  for (const workout of workouts) {
    for (const exercise of workout.exercises) {
      const target = bySlug.get(exercise.slug)?.muscles[0];
      if (target) totals.set(target, (totals.get(target) ?? 0) + exercise.sets);
    }
  }
  return totals;
}

/**
 * Raises each focus muscle toward its weekly minimum, one step at a time:
 * first by adding a set to an exercise that already targets it, then by adding
 * an exercise for it to the session with the most room, then by swapping an
 * accessory for another muscle for one aimed at it. Every step keeps the
 * session set budget, the session length, the exercise count and the weekly
 * maximum; when nothing fits, the muscle stays below its minimum and
 * policiesFor lowers the minimum to what fits.
 */
function topUpPriorities(
  workouts: PlanWorkout[],
  policies: PlanPolicies,
  allowed: readonly CatalogExercise[],
  limit: number,
): PlanWorkout[] {
  const { training, catalog } = policies;
  const bySlug = new Map(catalog.map((exercise) => [exercise.slug, exercise]));
  const days: (Omit<PlanWorkout, "exercises"> & { exercises: PlanExercise[] })[] = workouts.map((
    workout,
  ) => ({ ...workout, exercises: [...workout.exercises] }));
  const sessionSets = (day: Readonly<{ exercises: readonly PlanExercise[] }>) =>
    day.exercises.reduce((total, exercise) => total + exercise.sets, 0);
  const fits = (exercises: PlanExercise[]) =>
    exercises.reduce((total, exercise) => total + exercise.sets, 0) <=
      training.setBudgetPerSession &&
    exercises.length <= training.maxExercisesPerSession &&
    estimateWorkoutMinutes(exercises) <= limit;

  for (const priority of training.priorityMinimums) {
    let weekly = weeklySetsByMuscle(days, catalog).get(priority.muscle) ?? 0;
    while (weekly < priority.sets && weekly < training.maxWeeklySetsPerMuscle) {
      let added = false;
      // One more set on an exercise already aimed at the muscle.
      for (const day of days) {
        const index = day.exercises.findIndex((exercise) =>
          bySlug.get(exercise.slug)?.muscles[0] === priority.muscle &&
          exercise.sets < training.setsPerExercise[1]
        );
        if (index < 0) continue;
        const next = [...day.exercises];
        next[index] = { ...next[index], sets: next[index].sets + 1 };
        if (fits(next)) {
          day.exercises = next;
          added = true;
          break;
        }
      }
      if (!added) {
        // A new exercise for the muscle, in the session with the most room.
        const ordered = [...days].sort((a, b) => sessionSets(a) - sessionSets(b));
        for (const day of ordered) {
          const choice = allowed.find((exercise) =>
            exercise.muscles[0] === priority.muscle &&
            !day.exercises.some((item) => item.slug === exercise.slug)
          );
          if (!choice) continue;
          const sets = Math.min(2, priority.sets - weekly);
          const next = [...day.exercises, {
            slug: choice.slug,
            sets,
            ...prescription(choice, policies),
            notes: "",
          }];
          if (fits(next)) {
            day.exercises = next;
            added = true;
            break;
          }
        }
      }
      if (!added) {
        // A full session swaps one accessory aimed at a muscle that is not a
        // focus for an exercise aimed at this one. Accessories never cover a
        // required movement group, so coverage holds.
        const focus = new Set(training.priorityMinimums.map((item) => item.muscle as string));
        for (const day of days) {
          const choice = allowed.find((exercise) =>
            exercise.muscles[0] === priority.muscle &&
            !day.exercises.some((item) => item.slug === exercise.slug)
          );
          const index = day.exercises.findIndex((exercise) => {
            const entry = bySlug.get(exercise.slug);
            return entry !== undefined && !entry.compound && !focus.has(entry.muscles[0]);
          });
          if (!choice || index < 0) continue;
          const next = [...day.exercises];
          next[index] = {
            slug: choice.slug,
            sets: day.exercises[index].sets,
            ...prescription(choice, policies),
            notes: "",
          };
          if (fits(next)) {
            day.exercises = next;
            added = true;
            break;
          }
        }
      }
      if (!added) break;
      weekly = weeklySetsByMuscle(days, catalog).get(priority.muscle) ?? 0;
    }
  }
  return days;
}

export function buildRulesPlan(policies: PlanPolicies): OnboardingPlan {
  const { answers, training, nutrition } = policies;
  const allowed = allowedExercises(
    policies.catalog,
    answers.equipment,
    answers.experience,
    answers.avoidPatterns,
  );
  const days = templates[training.split](answers.trainingWeekdays.length);
  const usedThisWeek = new Set<string>();
  const weeklySets = new Map<string, number>();
  const limit = answers.sessionMinutes + training.sessionOverrunMinutes;

  const built: PlanWorkout[] = days.map((day, index) => {
    const exercises: PlanExercise[] = [];
    let sessionSets = 0;
    const slotCount = Math.min(training.maxExercisesPerSession, day.slots.length);
    const defaultSets = Math.min(
      3,
      Math.max(2, Math.floor(training.setBudgetPerSession / slotCount)),
    );
    for (const slot of day.slots) {
      if (exercises.length >= training.maxExercisesPerSession) break;
      const fill = (patterns: readonly MovementPattern[]) =>
        patterns.flatMap((pattern) =>
          allowed.filter((exercise) =>
            exercise.pattern === pattern && !exercises.some((item) => item.slug === exercise.slug)
          )
        );
      const own = fill(slot);
      const candidates = own.length
        ? own
        : fill(slot.flatMap((pattern) => substitutes[pattern] ?? []));
      const choice = candidates.find((exercise) => !usedThisWeek.has(exercise.slug)) ??
        candidates[0];
      if (!choice) continue;
      const target = choice.muscles[0];
      const room = Math.min(
        training.setBudgetPerSession - sessionSets,
        training.maxWeeklySetsPerMuscle - (weeklySets.get(target) ?? 0),
      );
      const base = prescription(choice, policies);
      // Full prescription first; in a short session, fewer sets and then a
      // shorter rest, so the session still covers its movement patterns.
      const variants: PlanExercise[] = [
        { slug: choice.slug, sets: defaultSets, ...base, notes: "" },
        { slug: choice.slug, sets: 2, ...base, notes: "" },
        {
          slug: choice.slug,
          sets: 2,
          ...base,
          rest_seconds: Math.max(training.restSeconds[0], Math.min(base.rest_seconds, 120)),
          notes: "",
        },
      ];
      const fit = variants.find((candidate) =>
        candidate.sets <= room && estimateWorkoutMinutes([...exercises, candidate]) <= limit
      );
      if (!fit) continue;
      exercises.push(fit);
      sessionSets += fit.sets;
      usedThisWeek.add(choice.slug);
      weeklySets.set(target, (weeklySets.get(target) ?? 0) + fit.sets);
    }
    return {
      weekday: answers.trainingWeekdays[index],
      name: day.name,
      objective: day.objective,
      warm_up: "Five minutes of easy movement, then two lighter sets of the first exercise.",
      cool_down: "Easy walking and breathing; note any pain or unusual fatigue.",
      exercises,
    };
  });
  const workouts = topUpPriorities(built, policies, allowed, limit);

  const [low, high] = nutrition.calories;
  const calories = Math.round((low + high) / 2 / 10) * 10;
  const deficit = answers.goal === "fat_loss" || answers.goal === "recomposition";
  const reference = nutrition.protein[0] / 1.6;
  const protein = Math.min(
    nutrition.protein[1],
    Math.max(nutrition.protein[0], Math.round(reference * (deficit ? 2.0 : 1.8))),
  );
  // A quarter of calories from fat, more when carbohydrate would otherwise
  // pass its upper bound.
  const fat = Math.min(
    nutrition.fatMaxG(calories),
    Math.max(
      nutrition.fatMinG(calories),
      Math.round(0.25 * calories / 9),
      Math.ceil((calories - 4 * protein - 4 * nutritionBounds.carbohydrateG[1]) / 9),
    ),
  );
  const carbohydrate = Math.max(20, Math.round((calories - 4 * protein - 9 * fat) / 4));
  const experienced = answers.path === "experienced";

  return {
    title: experienced ? "Structured continuation block" : "Foundation block",
    block_weeks: 6,
    assessment: `${
      experienced
        ? "Built by Tracend's rules from your schedule, equipment and goal. Your current plan was not compared exercise by exercise; tell the Coach what you want to keep."
        : "Built by Tracend's rules from your schedule, equipment and goal, so the first weeks set a measurable baseline."
    }${training.priorityMinimums.length ? ` Your focus muscles get extra weekly sets.` : ""}`,
    assumptions: [
      "Calories are an estimate from your height, weight, age and activity; weigh-ins over 2-3 weeks will confirm them.",
      ...(answers.limitations
        ? [
          "Tracend's rules use the movements you chose to avoid but cannot read your note; tell the Coach anything it did not cover.",
        ]
        : []),
    ],
    missing_information: answers.sex === "unspecified"
      ? ["Sex was not given, so the calorie range covers both estimates."]
      : [],
    kept_from_current_plan: [],
    changed_from_current_plan: [],
    progression:
      "When every set reaches the top of its rep range at the target effort, add a small amount of load next session.",
    rationale:
      "A balanced split for your training days, using only exercises your equipment allows, within Tracend's volume and effort limits.",
    expected_benefit: "A clear starting plan that can be measured before it changes.",
    downside: "Targets are first estimates and need two to three weeks of data to refine.",
    confidence: "medium",
    workouts,
    nutrition: {
      calories,
      protein_g: protein,
      carbohydrate_g: carbohydrate,
      fat_g: fat,
      rationale:
        "The middle of Tracend's calorie range for your goal, with protein and fat inside the safe ranges and carbohydrate from the rest.",
    },
  };
}
