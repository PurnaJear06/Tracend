// What a training template is made of. A template is the week's shape: which sessions there are
// and, in priority order, which movement each session asks for. It names no exercise; the rules
// plan (onboarding/rules_plan.ts) picks the exercise for each slot from the athlete's equipment.
import type { MovementPattern } from "../../onboarding/catalog.ts";
import type { Split } from "../../onboarding/policy.ts";
import type { SessionLoad } from "../standard/prescription.ts";

/**
 * How much a slot matters. A session that is short on time or sets loses its last slots first
 * (accessory, then support), and the sets go to the main slots first.
 */
export type SlotTier = "main" | "support" | "accessory";

export type Slot = Readonly<{
  /** The movement patterns that may fill the slot, best first. */
  patterns: readonly MovementPattern[];
  tier: SlotTier;
  /**
   * The slot rotates through the exercises of its patterns during the week: a loaded and a
   * bodyweight form count the same, a compound comes before an isolation exercise, and an
   * exercise another session already used is passed over. Core work and the second vertical pull
   * of a week use it, so the trunk is not trained with one exercise and a pull-up returns as the
   * variation of a lat pulldown.
   */
  rotate?: true;
  /**
   * Exercises (catalog slugs) the slot takes first when the athlete can do them, after any focus
   * muscle that still needs sets. Only advanced templates set it, to place the staples an
   * advanced lifter expects; with none available the slot fills as usual.
   */
  prefers?: readonly string[];
}>;

export type TemplateDay = Readonly<{
  name: string;
  objective: string;
  /** Priority order: the plan keeps as many slots, from the first, as the session has room for. */
  slots: readonly Slot[];
  /**
   * Advanced templates only: a heavy day takes the lower part of each compound lift's rep range
   * and a light day the upper part (weekly undulation); absent, the whole range.
   */
  load?: SessionLoad;
}>;

/**
 * What the athlete is training for, reduced to what changes the shape of the week. `general` is
 * the strength goal held to moderate effort (screening outcome `moderate_until_cleared`).
 */
export type Profile = "strength" | "size" | "aesthetic" | "lean" | "general";
/** The profiles that have their own accessories. */
export type TailProfile = Exclude<Profile, "general">;
export type LengthTier = "short" | "standard" | "long";

export type WeekTemplate = Readonly<{
  /** For example "upper_lower-size-intermediate-standard"; stable, for tests and reports. */
  id: string;
  split: Split;
  profile: Profile;
  lengthTier: LengthTier;
  days: readonly TemplateDay[];
  /**
   * Most accessory exercises one session keeps, counted over the slots that find an exercise;
   * null for no limit. A beginner learns the main lifts first.
   */
  accessoryLimit: number | null;
}>;
