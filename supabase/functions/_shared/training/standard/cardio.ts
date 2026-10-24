// Cardio dosing (B5-4, rules version cardio-v1): how much cardio a week, what counts, and what
// intensity is open today. The week is worked out in SQL (migrations 20261024060225_cardio_dosing.sql
// and 20261024060325_deload_cardio_review_fixes.sql: private.cardio_rules, private.cardio_week) because the workouts and the check-in live in the
// database; a test keeps this file equal to the migration. Heart rate may inform cardio dosing
// (decision D9): the easy ceiling is a share of heart-rate reserve that the app turns into beats
// per minute from the athlete's own profile, with the talk test as the plain-words rule. It never
// sets a lifting load and never picks an intensity by itself: the athlete decides.
import { sourced } from "./sources.ts";

export const cardioVersion = sourced(
  "cardio-v1" as const,
  ["tracend_in_house"],
  "Names this rule set so a later change of numbers can be told apart from today's. In-house.",
);

/** The weekly dose in minutes of moderate cardio: the floor, and the upper end of the health range. */
export const cardioWeeklyDose = sourced(
  Object.freeze({ floorMin: 150, upperMin: 300 }),
  ["who_2020", "acsm_2011"],
  "Adults get the health benefit from 150 to 300 minutes of moderate activity a week, or half " +
    "that much vigorous, or a mix (WHO 2020), and ACSM 2011 gives moderate sessions of at " +
    "least 30 minutes on 5 days for the same total. The floor is the target; the upper end is " +
    "shown only for the goals that ask for more (see cardioStretchGoals).",
);

/** A vigorous minute counts as this many moderate minutes. */
export const cardioVigorousCountsAs = sourced(
  2,
  ["who_2020"],
  "WHO 2020 treats 75 to 150 vigorous minutes as equal to 150 to 300 moderate ones, so a " +
    "vigorous minute counts double. Workout records carry no intensity, so every observed " +
    "minute is counted as moderate and the figure says so.",
);

/** The goals whose weekly target also shows the upper figure. */
export const cardioStretchGoals = sourced<readonly string[]>(
  Object.freeze(["fat_loss", "recomposition"]),
  ["tracend_in_house"],
  "In-house mapping (owner decision O11): fat loss and recomposition show the 150 to 300 range " +
    "because the extra activity helps a deficit; every other goal shows the 150-minute floor.",
);

/** The easy-cardio day's dose in minutes, as B4's swap offers it. */
export const cardioEasyMinutes = sourced(
  Object.freeze([20, 30] as const),
  ["acsm_2011", "who_2020", "tracend_in_house"],
  "Guidelines count activity of any length towards the week and list sessions of 20 minutes or " +
    "more for hard effort and 30 for moderate (ACSM 2011, WHO 2020). An easy day is kept " +
    "shorter than the 30 listed for moderate effort. The range is in-house, and the same " +
    "numbers as the readiness card's easy day (a test pins them together).",
);

/** Easy effort stays below this share of heart-rate reserve. */
export const cardioEasyHrReserveMax = sourced(
  60,
  ["acsm_2011", "tracend_in_house"],
  "ACSM 2011 puts moderate effort at 40 to 59% of heart-rate reserve and vigorous from 60%, " +
    "so below 60% is moderate or easier; the app's Easy zone tops out at the same line. The " +
    "talk test (full sentences) is the rule in plain words, for athletes without a heart-rate " +
    "profile.",
);

/** Hard cardio only for an athlete the health check has cleared. */
export const cardioVigorousOnlyWhenCleared = sourced(
  true as const,
  ["riebe_2015"],
  "Moderate effort is the default for an athlete with a health-screening flag (Riebe 2015), so " +
    "an athlete held to moderate effort, or told to see a professional first, is never offered " +
    "hard cardio. Hard cardio is also left out on an amber or red readiness day, with no " +
    "check-in, and while a joint is held or limited (in-house: the strictest rule wins).",
);

/** Hard cardio sessions a week for an athlete cleared for them. */
export const cardioVigorousSessionsMax = sourced(
  2,
  ["tracend_in_house"],
  "In-house cap: two hard sessions a week leave room for lifting and recovery. No open " +
    "source sets the number.",
);

/** Hours between hard cardio and a lifting session when explosive strength matters. */
export const cardioLiftSeparationHours = sourced(
  3,
  ["schumann_2022"],
  "Cardio does not blunt muscle size or maximal strength, and a gap of about three hours " +
    "between the two protects explosive strength (Schumann 2022).",
);

/** The most minutes one workout counts for. */
export const cardioWorkoutCapMin = sourced(
  180,
  ["tracend_in_house"],
  "In-house guard against a mislogged workout (a watch left running): three hours is more than " +
    "the guideline needs from one session.",
);

/** The observed week, and how many of its days must have an Apple Health summary. */
export const cardioObservedWindow = sourced(
  Object.freeze({ windowDays: 7, minSummaryDays: 5 }),
  ["tracend_in_house"],
  "In-house: the last seven days, shown only when at least five of them have Apple Health data. " +
    "With fewer the minutes would be a guess, so none is shown and the athlete is asked to " +
    "connect Apple Health; zero is never shown for missing data.",
);

/** The workout names the health plugin writes for cardio on iOS; strength and other workouts are not counted. */
export const cardioTypes = sourced<readonly string[]>(
  Object.freeze([
    "WALKING",
    "RUNNING",
    "BIKING",
    "HIKING",
    "ELLIPTICAL",
    "ROWING",
    "SWIMMING",
    "STAIR_CLIMBING",
    "STAIRS",
    "STEP_TRAINING",
    "HAND_CYCLING",
    "JUMP_ROPE",
    "CARDIO_DANCE",
    "MIXED_CARDIO",
    "HIGH_INTENSITY_INTERVAL_TRAINING",
    "WHEELCHAIR_WALK_PACE",
    "WHEELCHAIR_RUN_PACE",
    "CROSS_COUNTRY_SKIING",
    "PADDLE_SPORTS",
    "SOCIAL_DANCE",
  ]),
  ["tracend_in_house"],
  "In-house list of the plugin's workout types that are cardio; the names are the ones " +
    "lib/features/health writes. Sports, strength training and 'other' are not counted, and " +
    "steps are never converted to minutes. Counting fewer workouts can only understate the week.",
);

/** The rules as private.cardio_rules() returns them. */
export function cardioRulesJson(): Readonly<Record<string, unknown>> {
  return {
    version: cardioVersion.value,
    weekly_floor_min: cardioWeeklyDose.value.floorMin,
    weekly_upper_min: cardioWeeklyDose.value.upperMin,
    vigorous_counts_as: cardioVigorousCountsAs.value,
    easy_minutes: cardioEasyMinutes.value,
    easy_hr_reserve_max_pct: cardioEasyHrReserveMax.value,
    vigorous_sessions_max: cardioVigorousSessionsMax.value,
    lift_separation_hours: cardioLiftSeparationHours.value,
    workout_cap_min: cardioWorkoutCapMin.value,
    window_days: cardioObservedWindow.value.windowDays,
    min_summary_days: cardioObservedWindow.value.minSummaryDays,
    stretch_goals: cardioStretchGoals.value,
    cardio_types: cardioTypes.value,
  };
}
