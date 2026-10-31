// The numbers behind the same-day readiness adjustment (B4, rules version readiness-v1). The rules
// run in SQL (migration 20261023140024_day_adjustments.sql: private.readiness_rules,
// private.readiness_assessment) because the answers, the plan and the session live in the database;
// this module holds each number with its sources and a basis in our own words, and a test keeps it
// equal to the migration. Only the athlete's check-in, last night's sleep and the recovery score are
// read. Load measures (acute:chronic ratio, monotony, strain) are not inputs, and the recovery score
// never adjusts a session by itself (decisions D9 and O1).
import { sourced } from "../standard/sources.ts";

export const readinessVersion = sourced(
  "readiness-v1" as const,
  ["tracend_in_house"],
  "Names this rule set in every stored answer, so a later change of numbers can be told apart " +
    "from today's. In-house, like the bands below.",
);

/**
 * Points per signal. The check-in scales run 1 to 5: sleep quality, energy and mood from poor to
 * good, soreness from good to very sore (5). Sleep quality, energy, soreness, mood and pain are
 * the check-in's points; sleep_short comes from Apple Health and recovery_low from the recovery
 * score.
 */
export const readinessPoints = sourced(
  Object.freeze({
    sleep_very_poor: 2,
    sleep_poor: 1,
    energy_very_low: 2,
    energy_low: 1,
    very_sore: 2,
    sore: 1,
    mood_very_low: 1,
    pain_moderate: 2,
    pain_mild: 0,
    sleep_short: 1,
    recovery_low: 1,
  }),
  ["saw_2016", "tracend_in_house"],
  "Self-reported wellness tracks the training response more consistently than objective " +
    "markers do (Saw 2016), so the check-in leads and carries most of the points. The mapping " +
    "from a 1-5 answer to points is in-house: the worst answer counts twice the next one, and a " +
    "low mood counts only at its lowest because it is the weakest signal. Mild pain is a note, " +
    "not a point.",
);

/** Pain bands: 1-3 a note, 4-6 two points, 7 or more routes out of training advice. */
export const readinessPainBands = sourced(
  Object.freeze({ referralFrom: 7, moderateFrom: 4, mildFrom: 1 }),
  ["tracend_in_house"],
  "In-house bands. Seven or more already routes to a doctor or physio in the daily decision " +
    "and the Coach safety screen, so the same-day adjustment matches them; 4-6 is enough to " +
    "ease the session but not to stop advice. Needs a coach's review before an external beta.",
);

/** Under this many minutes of sleep a night counts as short; 0 means no sleep was recorded. */
export const readinessShortSleepMinutes = sourced(
  360,
  ["craven_2022"],
  "Sleep loss in the meta-analysis meant six hours or less; strength and the lower body were " +
    "affected (Craven 2022). A night under six hours is one point.",
);

/** Sleep minutes outside 1 to this are not a night of sleep (a sync artefact). */
export const readinessValidSleepMaxMinutes = sourced(
  960,
  ["tracend_in_house"],
  "Sixteen hours is more than any real night; a larger value is a sync artefact and is " +
    "treated as missing, never as sleep. In-house.",
);

/** A recovery score under this reads low (the "Poor" band of ALGORITHMS section 1). */
export const readinessRecoveryLowBelow = sourced(
  35,
  ["tracend_in_house"],
  "An in-house cut-off at the upper edge of the app's Poor recovery band. It adds a point only next to a point from " +
    "the check-in, and only at medium or high confidence: a score built from the body's own " +
    "signals informs the athlete but never adjusts a session by itself (D9).",
);

/** Points that make a day amber, ease the session by a set, and send it to easy cardio. */
export const readinessBandPoints = sourced(
  Object.freeze({ amberFrom: 1, reduceFrom: 2, redFrom: 4 }),
  ["hickmott_2022", "tracend_in_house"],
  "Easing back on a poor day is a sound use of effort-based autoregulation (Hickmott 2022). " +
    "The cut-offs are in-house: one point holds last time's loads, two or three take a set off, " +
    "four or more swap the session for easy cardio. To be reviewed with a coach after four " +
    "weeks of real data.",
);

/** The lighter session: a set fewer from three sets, effort one point lower, not below 6. */
export const readinessReduceSets = sourced(
  Object.freeze({ minSets: 3, setsCut: 1, rpeDrop: 1, rpeFloor: 6 }),
  ["bell_2023", "hickmott_2022", "tracend_in_house"],
  "Experts agree that the way to cut training volume is fewer sets, with load free to stay " +
    "(Bell 2023), and the same numbers as Coach's lighter next session keep the two paths " +
    "agreeing (ALGORITHMS section 10). An exercise with fewer than three sets keeps them. Effort " +
    "never goes above the plan's.",
);

/** The easy-cardio day: minutes, as a range. */
export const readinessEasyCardioMinutes = sourced(
  Object.freeze([20, 30] as const),
  ["acsm_2011", "who_2020", "tracend_in_house"],
  "Guidelines count activity of any length towards a weekly dose and list sessions of 20 minutes " +
    "or more (ACSM 2011, WHO 2020). An easy day is kept shorter than the 30 minutes listed for " +
    "moderate effort. The range is in-house.",
);

/** Answers a day: a guard against a stuck client, not a rule about the athlete. */
export const readinessAnswersPerDay = sourced(
  20,
  ["tracend_in_house"],
  "A limit on stored answers a day so a stuck client cannot fill the table; ordinary use is one " +
    "or two. In-house.",
);

/** Minutes before the day's scores are made again after an attempt, failed or not. */
export const readinessMetricsRetryMinutes = sourced(
  10,
  ["tracend_in_house"],
  "Scores are made when none exist and again when Apple Health data arrives after them; a limit " +
    "of one attempt in ten minutes keeps a scoring error from being retried on every read. " +
    "In-house.",
);

/** Load measures are not inputs. */
export const readinessUsesLoadRatio = sourced(
  false as const,
  ["impellizzeri_2020"],
  "The acute:chronic workload ratio is not used to manage load or to decide a day's readiness: " +
    "its conceptual and statistical problems make it unfit to steer training (Impellizzeri " +
    "2020). It stays as background context only.",
);

/** The rules as private.readiness_rules() returns them. */
export function readinessRulesJson(): Readonly<Record<string, unknown>> {
  return {
    version: readinessVersion.value,
    points: readinessPoints.value,
    pain_referral_from: readinessPainBands.value.referralFrom,
    pain_moderate_from: readinessPainBands.value.moderateFrom,
    pain_mild_from: readinessPainBands.value.mildFrom,
    sleep_short_below_minutes: readinessShortSleepMinutes.value,
    sleep_valid_max_minutes: readinessValidSleepMaxMinutes.value,
    recovery_low_below: readinessRecoveryLowBelow.value,
    amber_from_points: readinessBandPoints.value.amberFrom,
    reduce_from_points: readinessBandPoints.value.reduceFrom,
    red_from_points: readinessBandPoints.value.redFrom,
    reduce_min_sets: readinessReduceSets.value.minSets,
    reduce_sets_cut: readinessReduceSets.value.setsCut,
    reduce_rpe_drop: readinessReduceSets.value.rpeDrop,
    reduce_rpe_floor: readinessReduceSets.value.rpeFloor,
    easy_cardio_minutes: readinessEasyCardioMinutes.value,
    answers_per_day: readinessAnswersPerDay.value,
    metrics_retry_minutes: readinessMetricsRetryMinutes.value,
  };
}
