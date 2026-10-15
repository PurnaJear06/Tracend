// Weekly volume and frequency per muscle. Rule data only; nothing reads it yet
// (B2 counts fractional volume with it).
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
  }),
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
