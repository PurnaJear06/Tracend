// Rep ranges, effort and rest: what one exercise's working sets look like. The rules plan
// (onboarding/rules_plan.ts) builds every prescription from it.
import type { Goal } from "../../onboarding/answers.ts";
import type { ExperienceLevel } from "../../onboarding/catalog.ts";
import { sourced } from "./sources.ts";

export type Emphasis = "strength" | "hypertrophy";
export type Experience = ExperienceLevel;
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
    advanced: Object.freeze({
      compound: sourced(
        [3, 6] as const,
        ["acsm_2009", "acsm_2026", "tracend_in_house"],
        "ACSM 2009 gives intermediate and advanced lifters one recommendation (1-12 RM in a " +
          "periodized way, with eventual emphasis on heavy 1-6 RM loading), so no source sets " +
          "a separate advanced range and the intermediate range stands: ACSM 2026 finds " +
          "strength rises with loads of 80% of 1RM or more, and Tracend keeps at least 3 " +
          "reps, the lowest count its onboarding policy allows.",
      ),
      isolation: sourced(
        [6, 12] as const,
        ["acsm_2009"],
        "As for intermediates: ACSM 2009 does not separate assistance work for advanced " +
          "lifters from its 1-12 RM range for trained lifters.",
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
    advanced: Object.freeze({
      compound: sourced(
        [6, 12] as const,
        ["acsm_2009"],
        "ACSM 2009 recommends the same 1-12 RM span for intermediate and advanced lifters, " +
          "with emphasis on the 6-12 RM zone for hypertrophy, so the intermediate range " +
          "stands for advanced lifters.",
      ),
      isolation: sourced(
        [10, 15] as const,
        ["iversen_2021", "tracend_in_house"],
        "As for intermediates: the top of Iversen 2021's 6-15 RM range (in-house), because " +
          "isolation loads move in large relative steps.",
      ),
    }),
  }),
});

/**
 * Advanced lifters alternate heavier and lighter sessions inside the week for the same muscles
 * (weekly undulation) instead of repeating one rep range. The athlete's compound rep range is cut
 * in two: the heavy day takes its lower part, the light day the rest, so every rep stays inside
 * the range the standard sets for the goal. Isolation work keeps its range.
 */
export const undulation = sourced(
  "split_compound_range_in_two" as const,
  ["acsm_2009", "moesgaard_2022", "acsm_2026", "tracend_in_house"],
  "ACSM 2009 recommends that intermediate and advanced lifters train 1-12 RM in a periodized " +
    "way. Moesgaard 2022 (volume equated) finds undulating periodization raises 1RM strength " +
    "more than linear periodization in trained lifters and makes no difference for muscle size, " +
    "so the benefit claimed is for strength only; ACSM 2026 finds no consistent effect of " +
    "periodization across reviews. The split point (the heavy day takes the lower half of the " +
    "range, rounded down) is Tracend's own arithmetic on the cited range.",
);

export type SessionLoad = "heavy" | "light";

/**
 * The rep range of a compound exercise on a heavy or light day: the goal's range split in two.
 * [3, 6] gives [3, 4] and [5, 6]; [6, 12] gives [6, 9] and [10, 12].
 */
export function undulatedRepRange(
  range: readonly [number, number],
  load: SessionLoad,
): readonly [number, number] {
  const [min, max] = range;
  const heavyTop = min + Math.floor((max - min) / 2);
  return load === "heavy" ? [min, heavyTop] : [heavyTop + 1, max];
}

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
  advanced: sourced(
    [1, 3] as const,
    ["robinson_2024", "acsm_2026", "helms_2016", "refalo_2023"],
    "The same 1-3 reps left as for intermediates: none of the sources separates advanced " +
      "lifters. Robinson 2024 finds growth rises as sets end closer to failure while strength " +
      "gains are similar across a wide range, and ACSM 2026 finds failure itself unnecessary. " +
      "Refalo 2023 finds no evidence that training to momentary failure beats stopping short " +
      "for muscle size, so the range is not narrowed toward failure.",
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
