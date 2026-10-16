// Rep ranges, effort and rest: what one exercise's working sets look like.
// Rule data only; nothing reads it yet (B2 builds templates from it).
import type { Goal } from "../../onboarding/answers.ts";
import { sourced } from "./sources.ts";

export type Emphasis = "strength" | "hypertrophy";
export type Experience = "beginner" | "intermediate";
/** Compound: several joints move (a squat). Isolation: one joint (a curl). */
export type ExerciseClass = "compound" | "isolation";

export const goalEmphasis = sourced<Readonly<Record<Goal, Emphasis>>>(
  Object.freeze({
    strength: "strength",
    muscle_gain: "hypertrophy",
    recomposition: "hypertrophy",
    aesthetic: "hypertrophy",
    fat_loss: "hypertrophy",
  }),
  ["acsm_2026", "schoenfeld_2021", "tracend_in_house"],
  "Only the strength goal trains for maximal strength. ACSM 2026 finds that muscle size " +
    "responds to loads from light to heavy when volume is enough, and Schoenfeld 2021 argues " +
    "the same, so every body-composition goal uses the hypertrophy ranges. Fat loss keeps the " +
    "same lifting so the calorie deficit, not the training, does the fat loss (in-house).",
);

/** Working-set rep range [min, max] by emphasis, experience and exercise class. */
export const repRanges = Object.freeze({
  strength: Object.freeze({
    beginner: Object.freeze({
      compound: sourced(
        [8, 12] as const,
        ["acsm_2009"],
        "ACSM 2009 recommends loads of an 8-12 repetition maximum for novices, whatever the " +
          "goal, before heavier loading.",
      ),
      isolation: sourced(
        [8, 12] as const,
        ["acsm_2009"],
        "The same novice range from ACSM 2009; assistance exercises do not need heavier loads.",
      ),
    }),
    intermediate: Object.freeze({
      compound: sourced(
        [3, 6] as const,
        ["acsm_2009", "acsm_2026", "tracend_in_house"],
        "ACSM 2009 moves trained lifters toward heavy 1-6 RM loads for strength, and ACSM 2026 " +
          "finds strength rises with heavier loads (80% of 1RM or more). Tracend keeps at " +
          "least 3 reps, the lowest count its onboarding policy allows.",
      ),
      isolation: sourced(
        [6, 12] as const,
        ["acsm_2009"],
        "Assistance exercises stay in the moderate part of ACSM 2009's 1-12 RM range for " +
          "trained lifters.",
      ),
    }),
  }),
  hypertrophy: Object.freeze({
    beginner: Object.freeze({
      compound: sourced(
        [8, 12] as const,
        ["acsm_2009"],
        "ACSM 2009 recommends an 8-12 RM range for novices.",
      ),
      isolation: sourced(
        [10, 15] as const,
        ["iversen_2021", "tracend_in_house"],
        "Iversen 2021 recommends 6-15 RM loads for size. Isolation work uses the top of that " +
          "range because its loads are small, so one equipment step is a large jump and reps " +
          "carry the progression (in-house).",
      ),
    }),
    intermediate: Object.freeze({
      compound: sourced(
        [6, 12] as const,
        ["acsm_2009"],
        "ACSM 2009 recommends emphasising the 6-12 RM zone for hypertrophy in trained lifters.",
      ),
      isolation: sourced(
        [10, 15] as const,
        ["iversen_2021", "tracend_in_house"],
        "As for beginners: the top of Iversen 2021's 6-15 RM range, because isolation loads " +
          "move in large relative steps (in-house).",
      ),
    }),
  }),
});

/** RPE on the reps-in-reserve scale is 10 minus the reps left (RPE 8 = 2 reps left). */
export const rpeFromRirOffset = sourced(
  10,
  ["zourdos_2016"],
  "Zourdos 2016 anchors the scale so that RPE 10 means no reps left, RPE 9 one rep left, " +
    "and so on.",
);

/** Reps left in reserve at the end of a working set, [min, max]. */
export const targetRepsInReserve = Object.freeze({
  beginner: sourced(
    [2, 3] as const,
    ["zourdos_2016", "acsm_2026", "tracend_in_house"],
    "Novices rate effort near their maximum less accurately than experienced lifters " +
      "(Zourdos 2016), and ACSM 2026 finds training to failure adds nothing consistent, so " +
      "beginners stop two to three reps short (in-house choice inside that evidence).",
  ),
  intermediate: sourced(
    [1, 3] as const,
    ["robinson_2024", "acsm_2026", "helms_2016"],
    "Robinson 2024 finds muscle growth rises as sets end closer to failure while strength " +
      "gains are similar across a wide range; ACSM 2026 finds failure itself unnecessary. One " +
      "to three reps left keeps sets hard without failure, and the reps-left scale lets the " +
      "load be adjusted set to set (Helms 2016).",
  ),
});

/** Rest between working sets, in seconds [min, max]. */
export const restSeconds = Object.freeze({
  strength: Object.freeze({
    compound: sourced(
      [180, 300] as const,
      ["acsm_2009"],
      "ACSM 2009 recommends 3-5 minute rests with heavy strength loading.",
    ),
    isolation: sourced(
      [60, 120] as const,
      ["acsm_2009", "singer_2024"],
      "Assistance work uses ACSM 2009's 1-2 minute hypertrophy rests; Singer 2024 finds a " +
        "small benefit from resting longer than 60 seconds.",
    ),
  }),
  hypertrophy: Object.freeze({
    compound: sourced(
      [90, 180] as const,
      ["singer_2024", "acsm_2009", "tracend_in_house"],
      "Singer 2024 finds a small benefit from rests longer than 60 seconds and no clear " +
        "difference beyond 90 seconds; ACSM 2009 recommends 1-2 minutes. Heavy multi-joint " +
        "sets may rest up to 3 minutes so the next set keeps its reps, the onboarding " +
        "policy's maximum outside the strength goal (in-house).",
    ),
    isolation: sourced(
      [60, 120] as const,
      ["acsm_2009", "singer_2024"],
      "ACSM 2009 recommends 1-2 minute rests for hypertrophy; Singer 2024 finds a small " +
        "benefit from resting longer than 60 seconds.",
    ),
  }),
});
