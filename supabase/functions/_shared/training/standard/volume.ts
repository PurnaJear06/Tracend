// Weekly volume and frequency per muscle. Rule data. B2 counts fractional volume with it, and the
// Coach's week-ahead schedule (_shared/training/schedule) reads the recovery gap below.
import { sourced } from "./sources.ts";

/** Hard working sets per muscle per week. */
export const weeklySetsPerMuscle = Object.freeze({
  minimum: sourced(
    4,
    ["iversen_2021"],
    "Iversen 2021 recommends at least 4 weekly sets per muscle group for strength and size " +
      "when time is short.",
  ),
  growth: sourced(
    10,
    ["acsm_2026", "schoenfeld_2017"],
    "ACSM 2026 finds hypertrophy enhanced at 10 or more sets per muscle group a week, and " +
      "Schoenfeld 2017 finds a graded dose-response with more weekly sets.",
  ),
  /**
   * The weekly sets an advanced lifter's plan builds toward before it stretches: the bottom of
   * the range Baz-Valle 2022 gives trained lifters, where the intermediate level aims at the
   * growth level above.
   */
  advancedGrowth: sourced(
    12,
    ["baz_valle_2022"],
    "Baz-Valle 2022 studied lifters with at least a year of training and called fewer than 12 " +
      "weekly sets per muscle its low-volume group, suggesting 12-20 sets as the standard for " +
      "trained lifters. Advanced lifters start the climb at the bottom of that range. No " +
      "source separates advanced from other trained lifters, so this is the most defensible " +
      "cited value.",
  ),
  maximum: Object.freeze({
    beginner: sourced(
      12,
      ["tracend_in_house", "baz_valle_2022"],
      "Tracend's onboarding policy caps beginners at 12. Baz-Valle 2022 studied only trained " +
        "lifters, below 12 weekly sets being its low-volume group; beginners grow on less and " +
        "recover from less, so the cap is an in-house choice.",
    ),
    intermediate: sourced(
      20,
      ["baz_valle_2022"],
      "Baz-Valle 2022 suggests 12-20 weekly sets per muscle as the standard for trained " +
        "lifters, finding no difference above 20 for the quadriceps or biceps.",
    ),
    advanced: sourced(
      20,
      ["baz_valle_2022", "pelland_2026"],
      "The same 20 as for intermediates: Baz-Valle 2022 found no difference between 12-20 and " +
        "more than 20 sets for the quadriceps or biceps (more helped only the triceps), and " +
        "Pelland 2026 finds returns diminish with each added set. No source puts advanced " +
        "lifters above 20.",
    ),
  }),
});

/** Training days a week by experience: the frequency ACSM 2009 recommends for each level. */
export const trainingDaysPerWeek = Object.freeze({
  beginner: sourced(
    [2, 3] as const,
    ["acsm_2009"],
    "ACSM 2009 recommends 2-3 days a week for novices.",
  ),
  intermediate: sourced(
    [3, 4] as const,
    ["acsm_2009"],
    "ACSM 2009 recommends 3-4 days a week for intermediate lifters.",
  ),
  advanced: sourced(
    [4, 5] as const,
    ["acsm_2009", "pelland_2026"],
    "ACSM 2009 recommends 4-5 days a week for advanced lifters, years into training. Pelland " +
      "2026 finds frequency matters little for muscle size once weekly volume is counted, so " +
      "fewer days still work: each session simply carries more.",
  ),
});

/**
 * How much a set counts toward a muscle it trains indirectly (a catalog
 * exercise's secondary muscle). Its target and other primary muscles count 1.
 */
export const indirectSetFraction = sourced(
  0.5,
  ["pelland_2026"],
  "Pelland 2026 compared ways of counting indirect sets and found counting each as half a " +
    "set (the fractional method) fits the hypertrophy and strength data best. The abstract's " +
    "Methods state the 0.5 weight ('0.5 for fractional') and its Results name that method " +
    "the strongest.",
);

/** Sessions a week that train each muscle. */
export const sessionsPerMusclePerWeek = sourced(
  2,
  ["acsm_2011", "acsm_2026"],
  "ACSM 2011 recommends training each major muscle group on 2-3 days a week, and ACSM 2026 " +
    "finds strength enhanced with 2 or more sessions a week. Hypertrophy did not depend on " +
    "frequency once volume was equal (ACSM 2026), so 2 is a minimum, not a target.",
);

/** Working sets per exercise in a session when the goal is strength. */
export const strengthSetsPerExercise = sourced(
  [2, 3] as const,
  ["acsm_2026", "tracend_in_house"],
  "ACSM 2026 lists 2-3 sets a session among the prescriptions that enhanced voluntary " +
    "strength (multiple sets beat single sets). Applying it per exercise is Tracend's reading.",
);

/**
 * Whole days between two sessions that train the same muscle. Sessions carry a date, not a time,
 * so the gap is counted in calendar days: 1 means the muscle is not trained on two days in a row.
 */
export const minimumDaysBetweenSessionsPerMuscle = sourced(
  1,
  ["acsm_2011", "tracend_in_house"],
  "ACSM 2011 recommends training each major muscle group on 2-3 days a week, which only works " +
    "with rest days in between, and the research library's guideline summary (ICFSR 2021) " +
    "advises at least a day between sessions for the same muscles. Reading that as one calendar " +
    "day is Tracend's choice (no open source gives an hour count that dates alone could apply), " +
    "so the rule flags only a muscle trained on consecutive days.",
);
