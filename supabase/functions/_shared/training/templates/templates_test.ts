import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { goals } from "../../onboarding/answers.ts";
import { catalogBySlug, exerciseCatalogV1 } from "../../onboarding/catalog.ts";
import { splitForDays } from "../../onboarding/policy.ts";
import { beginnerAccessoryLimit, lengthTierFor, profileForGoal, weekTemplate } from "./select.ts";
import { fractionalWeeklySets, setWeights, strengthWeeklyTarget, weeklyTargets } from "./volume.ts";
import type { WeekTemplate } from "./types.ts";

const experiences = ["beginner", "intermediate"] as const;

function templateFor(
  goal: typeof goals[number],
  days: number,
  experience: typeof experiences[number],
  sessionMinutes: number,
  moderate = false,
): WeekTemplate {
  return weekTemplate(
    { split: splitForDays(days), goal, experience, sessionMinutes, moderate },
    days,
  );
}

const outline = (template: WeekTemplate) =>
  template.days.map((day) =>
    `${day.name}: ${
      day.slots.map((slot) => `${slot.tier[0]}${slot.rotate ? "~" : ""}:${slot.patterns.join("/")}`)
        .join(" ")
    }`
  );

Deno.test("every goal, day count, experience and length has a template of the right shape", () => {
  const ids = new Set<string>();
  for (const goal of goals) {
    for (const days of [1, 2, 3, 4, 5, 6]) {
      for (const experience of experiences) {
        for (const sessionMinutes of [30, 45, 60, 90]) {
          const template = templateFor(goal, days, experience, sessionMinutes);
          assertEquals(template.days.length, days);
          assertEquals(template.split, splitForDays(days));
          assertEquals(template.profile, profileForGoal[goal]);
          assertEquals(template.lengthTier, lengthTierFor(sessionMinutes));
          ids.add(template.id);
          for (const day of template.days) {
            // The most a session can hold is 8 exercises; the main lifts come first.
            assert(day.slots.length >= 4 && day.slots.length <= 8, `${template.id} ${day.name}`);
            assertEquals(day.slots[0].tier, "main");
            const tiers = day.slots.map((slot) => slot.tier);
            assertEquals(tiers, [...tiers].sort((a, b) => order(a) - order(b)), day.name);
          }
        }
      }
    }
  }
  // goal profile (4: lean covers two goals) x days x experience x length tier (3).
  assertEquals(ids.size, 4 * 6 * 2 * 3);
});

const order = (tier: string) => ({ main: 0, support: 1, accessory: 2 })[tier]!;

Deno.test("a template is refused for a day count its split does not have", () => {
  assertThrows(
    () =>
      weekTemplate({
        split: "upper_lower",
        goal: "strength",
        experience: "beginner",
        sessionMinutes: 60,
      }, 3),
    RangeError,
  );
});

Deno.test("golden: the week's shape by split, goal and experience", () => {
  assertEquals(outline(templateFor("strength", 3, "intermediate", 60)), [
    "Full body A: m:squat m:horizontal_push m:horizontal_pull/vertical_pull s:hinge a~:core a:biceps",
    "Full body B: m:hinge m:vertical_push/horizontal_push m:vertical_pull/horizontal_pull s:lunge/squat a~:core a:triceps",
    "Full body C: m:squat/lunge m:horizontal_push m~:vertical_pull/horizontal_pull s:hinge a~:core a:calves",
  ]);
  assertEquals(outline(templateFor("muscle_gain", 4, "intermediate", 60)), [
    "Upper A: m:horizontal_push m:horizontal_pull s:vertical_push s:vertical_pull/horizontal_pull a:lateral_raise a:triceps a:biceps",
    "Lower A: m:squat m:hinge s:lunge s:hamstring_curl/hinge a:calves a~:core a:quads_isolation",
    "Upper B: m~:vertical_pull/horizontal_pull m:vertical_push/horizontal_push s:horizontal_pull s:horizontal_push a:rear_delts/lateral_raise a:biceps a:triceps",
    "Lower B: m:hinge m:squat/lunge s:quads_isolation/lunge s:hamstring_curl/hinge a:calves a~:core a:hamstring_curl",
  ]);
  assertEquals(templateFor("aesthetic", 5, "beginner", 60).days.map((day) => day.name), [
    "Upper A",
    "Lower A",
    "Push",
    "Pull",
    "Legs",
  ]);
  assertEquals(templateFor("fat_loss", 6, "intermediate", 90).days.map((day) => day.name), [
    "Push",
    "Pull",
    "Legs",
    "Push 2",
    "Pull 2",
    "Legs 2",
  ]);
});

Deno.test("goals, day counts and lengths change the template", () => {
  const key = (template: WeekTemplate) => JSON.stringify(template.days);
  const variants = new Set(
    goals.flatMap((goal) =>
      [1, 2, 3, 4, 5, 6].map((days) =>
        `${goal}${days}:${key(templateFor(goal, days, "intermediate", 60))}`
      )
    ).map((entry) => entry.slice(entry.indexOf(":") + 1)),
  );
  // Fat loss and recomposition share one template per day count; every other goal differs.
  assertEquals(variants.size, 4 * 6);
  // Experience and session length change the id and the beginner's accessory limit, not the sessions.
  const beginner = templateFor("muscle_gain", 3, "beginner", 60);
  assertEquals(beginner.accessoryLimit, beginnerAccessoryLimit.value);
  assertEquals(templateFor("muscle_gain", 3, "intermediate", 60).accessoryLimit, null);
  assert(templateFor("muscle_gain", 3, "beginner", 30).id !== beginner.id);
});

Deno.test("moderate effort turns the strength goal into general fitness", () => {
  const moderate = templateFor("strength", 3, "intermediate", 60, true);
  assertEquals(moderate.profile, "general");
  assertEquals(outline(moderate), outline(templateFor("fat_loss", 3, "intermediate", 60)));
  assertEquals(templateFor("muscle_gain", 3, "intermediate", 60, true).profile, "size");
});

const exercise = (slug: string) => catalogBySlug.get(slug)!;

Deno.test("a set counts 1 for the target and other primary muscles and half for secondary muscles", () => {
  assertEquals(
    Object.fromEntries(setWeights(exercise("barbell-deadlift"))),
    { quads: 0.5, core: 0.5, back: 1, hamstrings: 1, glutes: 1 },
  );
  assertEquals(
    Object.fromEntries(setWeights(exercise("barbell-bench-press"))),
    { shoulders: 0.5, chest: 1, triceps: 1 },
  );
  assertEquals(Object.fromEntries(setWeights(exercise("dumbbell-curl"))), { biceps: 1 });
});

Deno.test("weekly volume sums sets times weight over the week, indirect sets at half", () => {
  const plan = (slug: string, sets: number) => ({
    slug,
    sets,
    rep_min: 6,
    rep_max: 10,
    target_rpe: 8,
    rest_seconds: 120,
    notes: "",
  });
  const totals = fractionalWeeklySets([
    { exercises: [plan("barbell-deadlift", 3), plan("dumbbell-curl", 2)] },
    { exercises: [plan("barbell-bench-press", 4), plan("barbell-deadlift", 1)] },
  ], exerciseCatalogV1);
  assertEquals(Object.fromEntries(totals), {
    back: 4,
    hamstrings: 4,
    glutes: 4,
    quads: 2,
    core: 2,
    biceps: 2,
    chest: 4,
    triceps: 4,
    shoulders: 2,
  });
  // A slug the catalog does not know adds nothing.
  assertEquals(
    fractionalWeeklySets([{ exercises: [plan("not-an-exercise", 5)] }], exerciseCatalogV1).size,
    0,
  );
});

Deno.test("weekly targets come from the standard: growth level, strength arithmetic, trunk minimum", () => {
  const muscles = ["quads", "back", "core"] as const;
  assertEquals(weeklyTargets("hypertrophy", "intermediate", muscles), {
    quads: 10,
    back: 10,
    core: 4,
  });
  assertEquals(weeklyTargets("hypertrophy", "intermediate", muscles, true), {
    quads: 15,
    back: 15,
    core: 4,
  });
  // A beginner never aims past the beginner maximum of 12 sets.
  assertEquals(weeklyTargets("hypertrophy", "beginner", muscles, true), {
    quads: 11,
    back: 11,
    core: 4,
  });
  assertEquals(strengthWeeklyTarget.value, 6);
  assertEquals(weeklyTargets("strength", "intermediate", muscles), { quads: 6, back: 6, core: 4 });
});
