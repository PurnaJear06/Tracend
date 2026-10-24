// The deload (B5-3, rules version deload-v1): one lighter week, and the signs that one could help.
// The week is built by the Coach proposal builder (_shared/coach_proposals/training.ts) from the
// values below, so the athlete approves a card, a new plan version is written, an audit event is
// stored and the regular plan returns on its own. When one could help is worked out in SQL
// (migration 20261024060125_deloads.sql: private.deload_rules, private.deload_signals) because the
// sessions, check-ins and targets live in the database; a test keeps this file equal to the
// migration. Nothing here applies a deload: the signals only suggest, and the athlete decides.
// Heart rate is not an input to any value (decision D9).
import { sourced } from "./sources.ts";

export const deloadVersion = sourced(
  "deload-v1" as const,
  ["tracend_in_house"],
  "Names this rule set so a later change of numbers can be told apart from today's. In-house, " +
    "like the cut-offs below.",
);

/** How long a deload runs, in weeks. A longer easing is the moderate-effort block instead. */
export const deloadWeeks = sourced(
  1,
  ["bell_2023", "coleman_2024", "tracend_in_house"],
  "Experts describe a deload as about a week (Bell 2023 background, not a consensus " +
    "statement), and the one trial of a one-week deload tested exactly that length (Coleman " +
    "2024). Fixing it at one week keeps the change small and easy to approve; a longer easing " +
    "is a different change. The choice is in-house.",
);

/** The share of sets kept, rounded up with at least one per exercise. */
export const deloadSetFraction = sourced(
  0.5,
  ["bell_2023", "tracend_in_house"],
  "Experts agree the way to cut volume in a deload is fewer sets (Bell 2023: 100% agreement), " +
    "keeping the main lifts and the exercises the athlete knows. Half is an in-house figure in " +
    "the range coaches use; rounding up leaves at least one set on every exercise.",
);

/** Effort never above this on a deload week; an exercise with no target takes it. */
export const deloadRpeCap = sourced(
  7,
  ["tracend_in_house"],
  "In-house and deliberately cautious: the experts allow effort to stay as planned when volume " +
    "drops (Bell 2023), but a week meant to recover is better kept three reps from failure. " +
    "An exercise with no effort target gets this one.",
);

/** Loads stay where the last sets left them, and never rise. */
export const deloadHoldsLoad = sourced(
  true as const,
  ["bell_2023"],
  "Experts agree that load may stay as it is while volume drops (Bell 2023: 95.2% agreement). " +
    "The week starts from the load of the last working sets, or the lower of that and the " +
    "progression target when the target steps down; it never takes the target's step up.",
);

/** Exercises that must be heading down before the lifts count as a reason. */
export const deloadPerformanceDrop = sourced(
  Object.freeze({ minExercises: 2 }),
  ["bell_2023", "tracend_in_house"],
  "A deload can be driven by training data (Bell 2023: 100% agreement). A single lift going " +
    "badly is normal, so it takes two different exercises whose current target is to lower " +
    "the load because of a stall or two sessions under the rep range, each needing two or " +
    "three comparable sessions. The count is in-house.",
);

/** Days of the last week that read amber or red, among those with a check-in. */
export const deloadRunDown = sourced(
  Object.freeze({ windowDays: 7, minDays: 4 }),
  ["bell_2023", "saw_2016", "tracend_in_house"],
  "Experts agree a deload fits when athletes feel physically and mentally fatigued, whatever " +
    "week of the programme it is (Bell 2023: 100% agreement), and self-reported wellness is " +
    "the measure that tracks the training response best (Saw 2016). Four amber or red days " +
    "out of the last seven that have a check-in is an in-house reading of 'feeling run down'.",
);

/** The end of a block of training: how long, and how much of it was actually trained. */
export const deloadBlockDone = sourced(
  Object.freeze({
    weeksMin: 4,
    weeksMax: 8,
    minCompletionPct: 75,
    completionWindowDays: 28,
  }),
  ["bell_2023", "tracend_in_house"],
  "Experts schedule a deload between training blocks (Bell 2023: 100% agreement); the 4 to " +
    "8 weeks they give for a block are background in the paper, not a consensus statement, " +
    "so the plan's own length is kept inside that range. Offering it only after at least " +
    "three quarters of the planned sessions were done in the last four weeks is in-house: " +
    "there is nothing to recover from otherwise.",
);

/** Days after a deload ends before another is suggested. */
export const deloadRecentDays = sourced(
  28,
  ["tracend_in_house"],
  "In-house: a month between suggestions stops the offer from repeating, whatever the " +
    "signals say. The athlete can still ask for a deload at any time.",
);

/** Weeks of the last few that must contain a completed session. */
export const deloadActiveWeeks = sourced(
  Object.freeze({ windows: 4, minActive: 3 }),
  ["tracend_in_house"],
  "In-house: with fewer than three of the last four weeks trained there is no training load " +
    "to recover from, so nothing is suggested.",
);

/** The rules as private.deload_rules() returns them. */
export function deloadRulesJson(): Readonly<Record<string, unknown>> {
  return {
    version: deloadVersion.value,
    weeks: deloadWeeks.value,
    set_fraction: deloadSetFraction.value,
    rpe_cap: deloadRpeCap.value,
    performance_drop_min_exercises: deloadPerformanceDrop.value.minExercises,
    run_down_window_days: deloadRunDown.value.windowDays,
    run_down_min_days: deloadRunDown.value.minDays,
    block_weeks_min: deloadBlockDone.value.weeksMin,
    block_weeks_max: deloadBlockDone.value.weeksMax,
    block_done_min_completion_pct: deloadBlockDone.value.minCompletionPct,
    completion_window_days: deloadBlockDone.value.completionWindowDays,
    recent_deload_days: deloadRecentDays.value,
    active_week_windows: deloadActiveWeeks.value.windows,
    active_week_windows_min: deloadActiveWeeks.value.minActive,
  };
}

/** Sets in a deload week: half, rounded up, never fewer than one. */
export const deloadSets = (sets: number) => Math.max(1, Math.ceil(sets * deloadSetFraction.value));

/** Effort in a deload week: the plan's target capped, and the cap when there is no target. */
export const deloadRpe = (targetRpe: number | null) =>
  Math.min(targetRpe ?? deloadRpeCap.value, deloadRpeCap.value);
