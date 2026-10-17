import {
  allowedExercises,
  catalogBySlug,
  type CatalogExercise,
  type EquipmentItem,
  type ExerciseRole,
  type MovementPattern,
} from "./catalog.ts";
import {
  type OnboardingPlan,
  PlanBlockedByScreeningError,
  type PlanExercise,
  type PlanPolicies,
  type PlanWorkout,
} from "./plan_contract.ts";
import {
  estimateWorkoutMinutes,
  moderateEffortRpe,
  nutritionBounds,
  screeningBlocksPlan,
} from "./policy.ts";
import {
  goalEmphasis,
  repRanges,
  restSeconds,
  targetRepsInReserve,
} from "../training/standard/prescription.ts";
import { weeklySetsPerMuscle } from "../training/standard/volume.ts";
import { weekTemplate } from "../training/templates/select.ts";
import type { SlotTier } from "../training/templates/types.ts";
import {
  fractionalWeeklySets,
  setWeights,
  supportingMuscles,
  weeklyTargets,
} from "../training/templates/volume.ts";

// The rules plan: a complete onboarding plan built only by deterministic code
// from onboarding-policy-v2 and the catalog. It is used whenever a model is
// not used (no AI consent, no evaluated provider, budget reached) or its plan
// fails validation after one repair, so every athlete gets a valid plan.
//
// The week's shape comes from a template (_shared/training/templates) chosen by the policy's split,
// the goal, the experience and the session length; this file picks the exercise for each slot,
// sets the prescription from the coaching standard and spreads the weekly sets toward the
// standard's volume (ALGORITHMS §9).

type Experience = PlanPolicies["answers"]["experience"];

// Equipment for a movement, most preferred first. An experienced lifter starts
// from the barbell; a beginner from dumbbells and machines, which take less
// skill to load safely, then the barbell.
const equipmentPreference: Readonly<Record<Experience, readonly EquipmentItem[]>> = {
  intermediate: [
    "barbell",
    "dumbbells",
    "pull_up_bar",
    "machines",
    "cables",
    "kettlebells",
    "bands",
  ],
  beginner: ["dumbbells", "machines", "barbell", "cables", "kettlebells", "bands", "pull_up_bar"],
};

function equipmentRank(exercise: CatalogExercise, experience: Experience): number {
  const order = equipmentPreference[experience];
  const ranks = exercise.equipment.map((item) => order.indexOf(item)).filter((rank) => rank >= 0);
  return ranks.length ? Math.min(...ranks) : order.length;
}

// A bench or a pull-up bar only holds the body, so an exercise that needs
// nothing else is bodyweight.
const supportOnly: readonly EquipmentItem[] = ["bench", "pull_up_bar"];

function isBodyweight(exercise: CatalogExercise): boolean {
  return exercise.equipment.every((item) => supportOnly.includes(item));
}

// A bodyweight exercise that needs nothing at all (not even a bar), other than trunk work,
// which has no loaded form worth preferring: a rotating slot still ranks it last.
function isFloorBodyweight(exercise: CatalogExercise): boolean {
  return exercise.equipment.length === 0 && exercise.pattern !== "core";
}

// The database catalog carries no role, so it is read from catalog.ts by slug.
function roleOf(exercise: CatalogExercise): ExerciseRole | undefined {
  return catalogBySlug.get(exercise.slug)?.role;
}

/**
 * The athlete's exercises, best first: loaded before bodyweight, compound
 * before isolation, a regression only after every other form, preferred
 * equipment for their experience, the standard form before a variation, then
 * slug, so the database catalog (read in slug order) and catalog.ts rank the
 * same way.
 */
function rankExercises(
  exercises: readonly CatalogExercise[],
  experience: Experience,
): CatalogExercise[] {
  const key = (exercise: CatalogExercise) => [
    isBodyweight(exercise) ? 1 : 0,
    exercise.compound ? 0 : 1,
    roleOf(exercise) === "regression" ? 1 : 0,
    equipmentRank(exercise, experience),
    roleOf(exercise) === "variation" ? 1 : 0,
  ];
  return [...exercises].sort((a, b) =>
    compareKeys(key(a), key(b)) || (a.slug < b.slug ? -1 : a.slug > b.slug ? 1 : 0)
  );
}

// Compares two ranking keys position by position; 0 when they are equal.
function compareKeys(left: readonly number[], right: readonly number[]): number {
  const index = left.findIndex((value, position) => value !== right[position]);
  return index >= 0 ? left[index] - right[index] : 0;
}

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
const clamp = (value: number, [low, high]: readonly [number, number]) =>
  Math.min(high, Math.max(low, value));

/**
 * Reps, effort and rest for one exercise, from the coaching standard
 * (_shared/training/standard/prescription.ts), inside the policy's limits. Choices where the
 * standard and the policy differ are in ALGORITHMS §9:
 * - beginners and every non-strength goal use the standard's hypertrophy or novice reps;
 * - strength rest is 180 s, 240 s (the policy cap, below the standard's 300 s) in sessions of 90
 *   minutes or more, and 120 s in sessions of 45 minutes or less, which cannot hold more;
 * - hypertrophy compound rest is the standard's 90 s in sessions of 45 minutes or less, else 120 s.
 * Under `moderate_until_cleared` the emphasis is never strength and effort stays at RPE 7.
 */
function prescription(
  exercise: CatalogExercise,
  policies: PlanPolicies,
): Omit<PlanExercise, "slug" | "sets" | "notes"> {
  const { answers, training } = policies;
  const moderate = policies.screening === "moderate_until_cleared";
  const emphasis = moderate ? "hypertrophy" : goalEmphasis.value[answers.goal];
  const kind = exercise.compound ? "compound" : "isolation";
  const [repMin, repMax] = repRanges[emphasis][answers.experience][kind].value;
  // Short sleep starts the block half a point easier (trainingPolicy).
  const lighter = training.startLighter ? 0.5 : 0;
  const [repsLeftLow, repsLeftHigh] = targetRepsInReserve[answers.experience].value;
  // A compound lift stops mid-range of the standard's reps left, an isolation exercise at 2.
  const repsLeft = exercise.compound
    ? (repsLeftLow + repsLeftHigh) / 2
    : Math.min(repsLeftHigh, Math.max(repsLeftLow, 2));
  const effort = Math.min(10 - repsLeft, moderate ? moderateEffortRpe : 10) - lighter;
  const [restLow, restHigh] = restSeconds[emphasis][kind].value;
  const minutes = answers.sessionMinutes;
  const rest = !exercise.compound
    ? 75
    : emphasis === "strength"
    ? minutes >= 90 ? restHigh : minutes > 45 ? restLow : 120
    : minutes <= 45
    ? restLow
    : 120;
  return {
    rep_min: repMin,
    rep_max: repMax,
    target_rpe: effort,
    rest_seconds: clamp(rest, training.restSeconds),
  };
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

/** Hard sets one exercise may reach when the weekly volume is spread (the policy allows 5). */
const sharedSetsCap = (exercise: CatalogExercise, strength: boolean) =>
  strength || !exercise.compound ? 3 : 4;

/** The bonus a main lift gets over an accessory when two additions would help equally. */
const tierBonus: Readonly<Record<SlotTier, number>> = { main: 0.3, support: 0.2, accessory: 0 };

/**
 * Spreads the sessions' spare sets over the week toward the standard's volume. Every chosen
 * exercise starts at 2 sets and the main lifts first reach 3. Then, one set at a time, the
 * addition that helps the muscles furthest below their weekly target most (indirect sets count
 * 0.5) is made, a main lift before an accessory when they help equally; once every target is met
 * or out of reach, spare room goes toward the stretch target (hypertrophy emphasis only). An
 * addition must keep the session set budget, session length, exercise count, the policy's weekly
 * maximum for the exercise's target muscle and the standard's maximum for that muscle counting
 * indirect sets; when none helps, the sets stay as they are. The plan the sessions start from is
 * not trimmed: it can pass the standard's maximum for a muscle that many exercises train
 * indirectly (glutes), which only the policy's direct count limits.
 */
function spreadSets(
  workouts: PlanWorkout[],
  tiers: ReadonlyMap<string, SlotTier>,
  policies: PlanPolicies,
  limit: number,
): PlanWorkout[] {
  const { answers, training, catalog } = policies;
  const bySlug = new Map(catalog.map((exercise) => [exercise.slug, exercise]));
  const strength = policies.screening !== "moderate_until_cleared" &&
    goalEmphasis.value[answers.goal] === "strength";
  const trained = [...new Set(catalog.flatMap((exercise) => exercise.muscles))];
  const emphasis = strength ? "strength" : "hypertrophy";
  let targets = weeklyTargets(emphasis, answers.experience, trained);
  const ceiling = weeklySetsPerMuscle.maximum[answers.experience].value;
  const days = workouts.map((workout) => ({ ...workout, exercises: [...workout.exercises] }));
  const fits = (exercises: PlanExercise[]) =>
    exercises.reduce((total, exercise) => total + exercise.sets, 0) <=
      training.setBudgetPerSession && estimateWorkoutMinutes(exercises) <= limit;
  const tierOf = (day: number, slug: string) => tiers.get(`${day}|${slug}`) ?? "accessory";
  // The score of one more set on an exercise, or null when that set is not allowed: the
  // exercise is at its set cap, or the set would pass the policy's weekly maximum for the target
  // muscle or the standard's maximum for any muscle it trains, or the session cannot hold it.
  const addition = (
    d: number,
    index: number,
    direct: ReadonlyMap<string, number>,
    weekly: ReadonlyMap<string, number>,
  ): number | null => {
    const planned = days[d].exercises[index];
    const entry = bySlug.get(planned.slug);
    if (!entry || planned.sets >= sharedSetsCap(entry, strength)) return null;
    if ((direct.get(entry.muscles[0]) ?? 0) + 1 > training.maxWeeklySetsPerMuscle) return null;
    let score = 0;
    const worked = entry.muscles[0];
    if (!supportingMuscles.includes(worked) && (weekly.get(worked) ?? 0) + 1 > ceiling) return null;
    for (const [muscle, weight] of setWeights(entry)) {
      const current = weekly.get(muscle) ?? 0;
      const target = targets[muscle] ?? 0;
      if (target > current) score += weight * (target - current) / target;
    }
    const next = [...days[d].exercises];
    next[index] = { ...planned, sets: planned.sets + 1 };
    return fits(next) ? score : null;
  };
  const add = (d: number, index: number) => {
    days[d].exercises[index] = {
      ...days[d].exercises[index],
      sets: days[d].exercises[index].sets + 1,
    };
  };

  // The main lifts first reach 3 sets, whatever the targets say: the standard's 2-3 sets an
  // exercise for strength, and the work that earns most of a session's effect for the rest.
  days.forEach((day, d) =>
    day.exercises.forEach((planned, index) => {
      if (tierOf(d, planned.slug) !== "main" || planned.sets >= 3) return;
      const score = addition(
        d,
        index,
        weeklySetsByMuscle(days, catalog),
        fractionalWeeklySets(days, catalog),
      );
      if (score !== null) add(d, index);
    })
  );

  let stretched = false;
  for (;;) {
    const direct = weeklySetsByMuscle(days, catalog);
    const weekly = fractionalWeeklySets(days, catalog);
    let best: { day: number; index: number; score: number } | null = null;
    days.forEach((day, d) => {
      day.exercises.forEach((planned, index) => {
        const score = addition(d, index, direct, weekly);
        if (score === null || score <= 0) return;
        const total = score + tierBonus[tierOf(d, planned.slug)];
        if (!best || total > best.score) best = { day: d, index, score: total };
      });
    });
    if (!best) {
      // Every target is met or out of reach: spare room goes toward the stretch target.
      if (strength || stretched) return days;
      stretched = true;
      targets = weeklyTargets(emphasis, answers.experience, trained, true);
      continue;
    }
    const { day, index } = best as { day: number; index: number; score: number };
    add(day, index);
  }
}

const profileText = {
  strength: "strength",
  size: "muscle size",
  aesthetic: "a muscular, defined look",
  lean: "losing fat while keeping muscle",
  general: "general fitness at moderate effort",
} as const;

const splitText = {
  full_body: "Full-body sessions",
  upper_lower: "An upper / lower split",
  upper_lower_push_pull_legs: "Upper, lower, push, pull and legs sessions",
  push_pull_legs: "A push / pull / legs split, twice through",
} as const;

export function buildRulesPlan(policies: PlanPolicies): OnboardingPlan {
  // Contract 8: a plan is never built while the outcome says to see a professional first.
  if (screeningBlocksPlan(policies.screening)) {
    throw new PlanBlockedByScreeningError("see_professional");
  }
  const { answers, training, nutrition } = policies;
  const allowed = rankExercises(
    allowedExercises(
      policies.catalog,
      answers.equipment,
      answers.experience,
      answers.avoidPatterns,
    ),
    answers.experience,
  );
  const template = weekTemplate({
    split: training.split,
    goal: answers.goal,
    experience: answers.experience,
    sessionMinutes: answers.sessionMinutes,
    moderate: policies.screening === "moderate_until_cleared",
  }, answers.trainingWeekdays.length);
  const usedThisWeek = new Set<string>();
  const weeklySets = new Map<string, number>();
  const tiers = new Map<string, SlotTier>();
  const limit = answers.sessionMinutes + training.sessionOverrunMinutes;

  const built: PlanWorkout[] = template.days.map((day, dayIndex) => {
    const exercises: PlanExercise[] = [];
    let sessionSets = 0;
    let accessories = 0;
    for (const slot of day.slots) {
      if (exercises.length >= training.maxExercisesPerSession) break;
      if (
        slot.tier === "accessory" && template.accessoryLimit !== null &&
        accessories >= template.accessoryLimit
      ) continue;
      const fill = (patterns: readonly MovementPattern[]) =>
        patterns.flatMap((pattern) =>
          allowed.filter((exercise) =>
            exercise.pattern === pattern && !exercises.some((item) => item.slug === exercise.slug)
          )
        );
      const own = fill(slot.patterns);
      const pool = own.length
        ? own
        : fill(slot.patterns.flatMap((pattern) => substitutes[pattern] ?? []));
      // An exercise for a focus muscle still short of its weekly minimum comes
      // first, the least-served focus muscle (then the athlete's focus order)
      // before the others, then a loaded exercise before a bodyweight one;
      // otherwise the slot's pattern order holds. A rotating slot (core work,
      // the second vertical pull of a week) puts a compound first and ignores
      // loaded versus bodyweight for trunk work and bar exercises, so it moves
      // through the forms it has; a floor exercise (no equipment) still ranks last.
      const focus = training.priorityMinimums;
      const grade = (exercise: CatalogExercise) => {
        const index = focus.findIndex((item) =>
          item.muscle === exercise.muscles[0] && (weeklySets.get(item.muscle) ?? 0) < item.sets
        );
        const served = index >= 0 ? weeklySets.get(focus[index].muscle) ?? 0 : Infinity;
        const form = slot.rotate
          ? [exercise.compound ? 0 : 1, isFloorBodyweight(exercise) ? 1 : 0]
          : [isBodyweight(exercise) ? 1 : 0];
        return [served, index >= 0 ? index : focus.length, ...form];
      };
      const candidates = pool.sort((a, b) => compareKeys(grade(a), grade(b)));
      const top = candidates[0];
      if (!top) continue;
      // An exercise not used yet this week adds variety, but never at the cost
      // of a focus muscle, by dropping from loaded to bodyweight, or to a
      // regression.
      const choice = candidates.find((exercise) =>
        !usedThisWeek.has(exercise.slug) &&
        (exercise === top ||
          compareKeys(grade(exercise), grade(top)) === 0 && roleOf(exercise) !== "regression")
      ) ?? top;
      const target = choice.muscles[0];
      const room = Math.min(
        training.setBudgetPerSession - sessionSets,
        training.maxWeeklySetsPerMuscle - (weeklySets.get(target) ?? 0),
      );
      const base = prescription(choice, policies);
      // Two sets first (spreadSets adds more); in a short session, a shorter
      // rest, so the session still covers its movement patterns.
      const variants: PlanExercise[] = [
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
      tiers.set(`${dayIndex}|${choice.slug}`, slot.tier);
      if (slot.tier === "accessory") accessories++;
      sessionSets += fit.sets;
      usedThisWeek.add(choice.slug);
      weeklySets.set(target, (weeklySets.get(target) ?? 0) + fit.sets);
    }
    return {
      weekday: answers.trainingWeekdays[dayIndex],
      name: day.name,
      objective: day.objective,
      warm_up: "Five minutes of easy movement, then two lighter sets of the first exercise.",
      cool_down: "Easy walking and breathing; note any pain or unusual fatigue.",
      exercises,
    };
  });
  const workouts = spreadSets(
    topUpPriorities(built, policies, allowed, limit),
    tiers,
    policies,
    limit,
  );

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
    rationale: `${splitText[template.split]} for ${
      profileText[template.profile]
    }, using only exercises your equipment allows, within Tracend's volume and effort limits.`,
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
