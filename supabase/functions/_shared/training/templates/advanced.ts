// The advanced variant of a week: the intermediate sessions plus what an advanced lifter's plan
// does differently. Everything is Tracend's own coaching choice built on the cited standard
// (ALGORITHMS §9); no exercise load or volume number is set here.
//   - Weekly undulation: each muscle meets a heavy day and a light day (`load`, applied to the
//     compound rep ranges by the rules plan; `undulation` in the standard).
//   - Staples: the unilateral leg slot prefers the Bulgarian split squat, and the push day of the
//     five-day split presses on an incline, so an advanced lifter with the equipment actually meets
//     them. The weighted pull-up and the close-grip bench press are met through the exercise
//     rotation, which offers a lift not yet used that week.
//   - One more direct accessory in sessions with room, for the first arm, chest, leg or calf muscle
//     a session does not already train directly.
import type { Split } from "../../onboarding/policy.ts";
import type { MovementPattern } from "../../onboarding/catalog.ts";
import type { SessionLoad } from "../standard/prescription.ts";
import type { Slot, TailProfile, TemplateDay } from "./types.ts";

/** A session holds at most 8 exercises (policy: min(8, 2 + minutes / 15)). */
const mostSlots = 8;

/**
 * Heavy and light sessions by split, in session order (none for a one-session week). Every muscle
 * meets a heavy and a light day in the week: full body alternates (the third session keeps the
 * whole range), the others run the heavy sessions first.
 */
const loadsBySplit: Readonly<Record<Split, readonly (SessionLoad | undefined)[]>> = {
  full_body: ["heavy", "light", undefined],
  upper_lower: ["heavy", "heavy", "light", "light"],
  upper_lower_push_pull_legs: ["heavy", "heavy", "light", "light", "light"],
  push_pull_legs: ["heavy", "heavy", "heavy", "light", "light", "light"],
};

// The objective is limited to 140 characters, the longest session text plus a note must fit.
const heavyNote = " Heavy day: lower reps on the big lifts.";
const lightNote = " Light day: higher reps on the big lifts.";

const bulgarian = ["bulgarian-split-squat"] as const;
const incline = ["incline-barbell-bench-press"] as const;

/** Sessions whose single-leg slot prefers the Bulgarian split squat. */
const singleLegSessions: readonly string[] = ["Full body B", "Lower A", "Legs"];

/**
 * The accessory an advanced session adds, in order of preference: the first one the session does
 * not already train directly. Strength templates keep their few accessories. No shoulder work is
 * added (lateral and rear-delt raises): presses and rows already carry the shoulders past the
 * standard's weekly maximum when their indirect sets are counted.
 */
const extraAccessory: Readonly<Record<string, readonly MovementPattern[]>> = {
  "Full body A": ["biceps", "triceps", "calves"],
  "Full body B": ["biceps", "triceps", "calves"],
  "Full body C": ["biceps", "triceps", "calves"],
  "Upper A": ["chest_fly", "triceps", "biceps"],
  "Upper B": ["chest_fly", "triceps", "biceps"],
  "Lower A": ["calves", "hamstring_curl", "quads_isolation"],
  "Lower B": ["calves", "hamstring_curl", "quads_isolation"],
  "Push": ["chest_fly", "triceps"],
  "Push 2": ["chest_fly", "triceps"],
  "Pull": ["biceps"],
  "Pull 2": ["biceps"],
  "Legs": ["hamstring_curl", "quads_isolation", "calves"],
  "Legs 2": ["hamstring_curl", "quads_isolation", "calves"],
};

function withExtra(day: TemplateDay): readonly Slot[] {
  if (day.slots.length >= mostSlots) return day.slots;
  const present = new Set(day.slots.flatMap((slot) => slot.patterns));
  const pattern = (extraAccessory[day.name] ?? []).find((candidate) => !present.has(candidate));
  return pattern ? [...day.slots, { patterns: [pattern], tier: "accessory" }] : day.slots;
}

function prefer(slots: readonly Slot[], index: number, slugs: readonly string[]): readonly Slot[] {
  return index < 0
    ? slots
    : slots.map((slot, at) => at === index ? { ...slot, prefers: slugs } : slot);
}

function withStaples(day: TemplateDay, split: Split, slots: readonly Slot[]): readonly Slot[] {
  let result = slots;
  if (singleLegSessions.includes(day.name)) {
    result = prefer(
      result,
      result.findIndex((slot) => slot.tier === "support" && slot.patterns[0] === "lunge"),
      bulgarian,
    );
  }
  // With upper and lower days already pressing flat, the push day presses on an incline.
  if (split === "upper_lower_push_pull_legs" && day.name === "Push") {
    result = prefer(
      result,
      result.findIndex((slot) => slot.tier === "main" && slot.patterns[0] === "horizontal_push"),
      incline,
    );
  }
  return result;
}

/** The advanced variant of the intermediate sessions of a split, in session order. */
export function advancedDays(
  days: readonly TemplateDay[],
  split: Split,
  profile: TailProfile,
): TemplateDay[] {
  // One session a week meets each muscle once: heavy and light need at least two.
  const loads = days.length < 2 ? [] : loadsBySplit[split];
  return days.map((day, index) => {
    const load = loads[index];
    const roomy = profile === "strength" ? day.slots : withExtra(day);
    return {
      ...day,
      objective: day.objective + (load === "heavy" ? heavyNote : load === "light" ? lightNote : ""),
      slots: withStaples(day, split, roomy),
      ...(load ? { load } : {}),
    };
  });
}
