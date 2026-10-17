// Every value the goal phase review compares against, with its basis in Tracend's own words.
// `inHouse` marks a value the literature does not give as a single number: the owner or a coach
// reviews those (docs/handoff/training-engine.md). Changing a value changes the review, so each
// carries the sources that support it.
import type { GoalPhaseSourceId } from "./sources.ts";

export type Threshold = Readonly<{
  value: number;
  unit: string;
  basis: string;
  sources: readonly GoalPhaseSourceId[];
  inHouse: boolean;
}>;

const threshold = (entry: Threshold): Threshold => Object.freeze(entry);

export const goalPhaseThresholds = Object.freeze({
  // BMI
  bmiHealthyFloor: threshold({
    value: 18.5,
    unit: "kg/m2",
    basis: "Below 18.5 is the underweight range for adults. A weight target under it is never " +
      "accepted and no projection goes below it.",
    sources: ["who_2004"],
    inHouse: false,
  }),
  bmiNearFloor: threshold({
    value: 19.5,
    unit: "kg/m2",
    basis: "One point above the floor. An athlete who is still losing at this BMI is close " +
      "enough to the floor that the next weeks decide whether they cross it.",
    sources: ["who_2004", "tracend_in_house"],
    inHouse: true,
  }),
  // Pace
  fastRatePctPerWeek: threshold({
    value: 1,
    unit: "% of body weight a week",
    basis: "Guidance for athletes who want to keep muscle while losing weight is 0.5 to 1% of " +
      "body weight a week; a trial of elite athletes kept or gained lean mass at 0.7% a week but " +
      "not at 1.4%. Sustained loss above 1% a week is faster than that evidence supports.",
    sources: ["helms_2014", "garthe_2011"],
    inHouse: false,
  }),
  fastRateMinimumWeeks: threshold({
    value: 3,
    unit: "weeks",
    basis: "A fast week or two is noise (water, glycogen, a missed weigh-in); the pace counts as " +
      "sustained after three weeks of readings.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  // Duration and size of a cut
  longDeficitWeeks: threshold({
    value: 16,
    unit: "weeks",
    basis: "The continuous arm of the main trial on breaking up a diet ran 16 weeks, and the " +
      "intermittent arm lost more with 2-week breaks; metabolic adaptation also grows with the " +
      "length of the deficit. After 16 weeks of continuous loss a maintenance period or a diet " +
      "break is worth considering.",
    sources: ["byrne_2018", "trexler_2014"],
    inHouse: true,
  }),
  longDeficitMinimumLossPct: threshold({
    value: 5,
    unit: "% of start weight",
    basis: "Guidelines see clinically meaningful change from a loss of 3 to 5% of body weight, " +
      "so a long phase counts as a real deficit only once the weight has moved by at least 5%.",
    sources: ["jensen_2014"],
    inHouse: false,
  }),
  largeLossPct: threshold({
    value: 10,
    unit: "% of start weight",
    basis: "Guidelines set an initial goal of 5 to 10% of body weight over about six months; a " +
      "loss past the top of that range, after at least 12 weeks, is a natural checkpoint to hold " +
      "the new weight before deciding on more.",
    sources: ["jensen_2014", "tracend_in_house"],
    inHouse: true,
  }),
  largeLossMinimumWeeks: threshold({
    value: 12,
    unit: "weeks",
    basis: "A big loss in fewer weeks is judged by its pace instead (slow_down).",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  // Still moving
  stillLosingKgPerWeek: threshold({
    value: 0.1,
    unit: "kg a week",
    basis: "Below this the weight is stable from week to week; the athlete is already holding.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  // Target
  targetToleranceKg: threshold({
    value: 0.5,
    unit: "kg",
    basis: "Daily weight moves by about this much with water and food; within it the target " +
      "counts as reached.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  // Recorded history before the goal
  continuousRunTolerancePct: threshold({
    value: 3,
    unit: "% of body weight",
    basis: "Body weight scatters by up to about 2 to 3% with fluid, food and glycogen. A rise " +
      "smaller than this does not end a run of loss, and a start weight must sit at least this " +
      "far above the goal phase's start weight before the loss counts as having begun before " +
      "the goal.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  runMinimumReadings: threshold({
    value: 4,
    unit: "readings",
    basis: "A run counts as continuous loss for the review only with at least this many " +
      "readings in it; two weights months apart say nothing about what happened between them.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  runMaximumGapDays: threshold({
    value: 35,
    unit: "days",
    basis: "A run counts as continuous loss for the review only when no two readings in it are " +
      "further apart than this (five weeks); a longer gap could hide a rebound or a break.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  historyMinimumLeadDays: threshold({
    value: 7,
    unit: "days",
    basis: "The recorded history is shown beside the goal phase only when the first reading is " +
      "at least a week before the first reading of the goal phase; less adds nothing.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  // Data
  implausibleBaseFraction: threshold({
    value: 0.03,
    unit: "fraction of body weight",
    basis: "Day to day, body weight moves by up to about 2 to 3% with fluid, food and glycogen.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
  implausibleWeeklyFraction: threshold({
    value: 0.015,
    unit: "fraction of body weight per week of gap",
    basis: "Added for each week between two readings: sustained change above 1.5% a week is " +
      "beyond even aggressive diets, so a larger gap is not a real change.",
    sources: ["helms_2014", "tracend_in_house"],
    inHouse: true,
  }),
  staleReadingDays: threshold({
    value: 14,
    unit: "days",
    basis: "A weight older than two weeks no longer says where the athlete is.",
    sources: ["tracend_in_house"],
    inHouse: true,
  }),
});
