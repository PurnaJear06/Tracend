// Chooses the week's template from the split the policy sets for the number of days, the goal,
// the athlete's experience and the session length. Deterministic; no exercise is named here.
import type { Goal } from "../../onboarding/answers.ts";
import type { Split } from "../../onboarding/policy.ts";
import { sourced } from "../standard/sources.ts";
import { fullBodyDay, legsDay, lowerDay, pullDay, pushDay, upperDay } from "./days.ts";
import type { LengthTier, Profile, TailProfile, TemplateDay, WeekTemplate } from "./types.ts";

export type Experience = "beginner" | "intermediate";

export type TemplateInput = Readonly<{
  split: Split;
  goal: Goal;
  experience: Experience;
  sessionMinutes: number;
  /** Screening outcome `moderate_until_cleared`: the strength goal becomes `general`. */
  moderate?: boolean;
}>;

/** Only the strength goal trains for strength; the others split by what they emphasise. */
export const profileForGoal: Readonly<Record<Goal, Profile>> = Object.freeze({
  strength: "strength",
  muscle_gain: "size",
  aesthetic: "aesthetic",
  fat_loss: "lean",
  recomposition: "lean",
});

/** Sessions of 45 minutes or less are short; of more than 75, long. */
export const lengthTierFor = (sessionMinutes: number): LengthTier =>
  sessionMinutes <= 45 ? "short" : sessionMinutes <= 75 ? "standard" : "long";

/**
 * A beginner learns the main lifts first: at most two accessory exercises a session, so the
 * sets go to the lifts being learned and recovery stays easy.
 */
export const beginnerAccessoryLimit = sourced(
  2,
  ["tracend_in_house"],
  "A beginner has most to gain from practising the main lifts and recovers from less, so a " +
    "session keeps at most two accessory exercises. An in-house coaching choice, not a " +
    "finding from a source.",
);

function daysFor(split: Split, profile: TailProfile, count: number): TemplateDay[] {
  switch (split) {
    case "full_body":
      return (["A", "B", "C"] as const).slice(0, count).map((letter) =>
        fullBodyDay(letter, profile)
      );
    case "upper_lower":
      return [
        upperDay("A", profile),
        lowerDay("A", profile),
        upperDay("B", profile),
        lowerDay("B", profile),
      ];
    case "upper_lower_push_pull_legs":
      return [
        upperDay("A", profile),
        lowerDay("A", profile),
        pushDay(false, profile),
        pullDay(false, profile),
        legsDay(false, profile),
      ];
    case "push_pull_legs":
      return [
        pushDay(false, profile),
        pullDay(false, profile),
        legsDay(false, profile),
        pushDay(true, profile),
        pullDay(true, profile),
        legsDay(true, profile),
      ];
  }
}

/** The sessions each split has; the policy's days-to-split rule decides which split applies. */
const sessionsOf: Readonly<Record<Split, readonly [number, number]>> = {
  full_body: [1, 3],
  upper_lower: [4, 4],
  upper_lower_push_pull_legs: [5, 5],
  push_pull_legs: [6, 6],
};

export function weekTemplate(input: TemplateInput, days: number): WeekTemplate {
  const [lowest, highest] = sessionsOf[input.split];
  if (days < lowest || days > highest) {
    throw new RangeError(`${input.split} has ${lowest}-${highest} sessions, not ${days}`);
  }
  const goalProfile = profileForGoal[input.goal];
  const profile: Profile = input.moderate && goalProfile === "strength" ? "general" : goalProfile;
  const lengthTier = lengthTierFor(input.sessionMinutes);
  // General fitness shares the compound-led accessories of the lean goals.
  const built = daysFor(input.split, profile === "general" ? "lean" : profile, days);
  return {
    id: `${input.split}-${days}-${profile}-${input.experience}-${lengthTier}`,
    split: input.split,
    profile,
    lengthTier,
    days: built,
    accessoryLimit: input.experience === "beginner" ? beginnerAccessoryLimit.value : null,
  };
}
