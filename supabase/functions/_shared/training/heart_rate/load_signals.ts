// Load signals for the training engine (coaching platform chunk C4): what the athlete's Apple Watch
// heart rate says about rest and recovery across the last 28 days of finished workouts. Pure
// arithmetic over per-set summaries and the heart-rate profile; raw samples never leave the phone.
//
// Heart rate informs; it never sets a load or a prescription (program decision D9). A signal can
// lower the confidence the engine puts in a progression step, suggest a longer rest, and ask the
// athlete a question. Nothing here can raise a load, a repetition target or a set count: the
// inputs hold no load, repetitions or reps in reserve (`get_workout_load_inputs_v1`) and the
// output has no field that could carry one. No signal ever raises confidence, because nothing in
// the evidence supports saying a heart rate agrees with an effort. Sleeping heart rate is NOT an
// input (D10, shadow mode).
//
// The thresholds are Tracend's own choices, not research values, and wait for a coach's review.
// A heart rate that a medicine blunts (a beta-blocker) reads low, which only removes a caution.

import type { HeartRateProfile } from "./profile.ts";

/** One finished set that has a heart-rate summary, as `get_workout_load_inputs_v1` returns it. */
export type LoadSignalSet = Readonly<{
  exercise_order: number;
  set_number: number;
  /** Rest actually taken before the set; null when the app did not record it. */
  rest_before_seconds: number | null;
  start_bpm: number | null;
  peak_bpm: number | null;
  end_bpm: number | null;
  drop_30s_bpm: number | null;
  drop_60s_bpm: number | null;
  coverage: number;
  sample_count: number;
  source: "watch_workout" | "background";
}>;

export type LoadSignalSession = Readonly<{
  local_date: string;
  /** Sets the athlete finished, with or without a heart-rate summary. */
  completed_sets: number;
  sets: readonly LoadSignalSet[];
}>;

export type WorkoutLoadInputs = Readonly<{
  schema_version: string;
  as_of: string;
  sessions: readonly LoadSignalSession[];
}>;

/** The window the signals look at, in days ending on the coaching date. */
export const loadSignalWindowDays = 28;
/** A set counts as tracked by a Watch workout with at least this share of the set and its minute after. */
export const trackedMinimumCoverage = 0.6;
/** A rest shorter than this is not a rest between sets (a set ticked during its own rest). */
export const settleMinimumRestSeconds = 30;
/** Tracked sets, in at least this many workouts, are needed before the start heart rate is judged. */
export const settleMinimumSets = 12;
export const settleMinimumSessions = 2;
/**
 * The middle start heart rate, as a share of heart-rate reserve (Karvonen), at which the heart had
 * not settled when the set began. 50% of reserve is where the Easy zone begins (ALGORITHMS.md).
 */
export const settleElevatedFraction = 0.5;
/** A median rest shorter than this is a short rest for lifting sets; at or above it the rest was ample. */
export const shortRestSeconds = 120;

export type SetStartState = "steady" | "elevated" | "not_enough_data";
export type SetStartReason = "no_profile" | "too_few_sets";
export type SetStartCause = "rest_short" | "slow_settling";

export type LoadSignals = Readonly<{
  schema_version: "1.0";
  as_of: string;
  window_days: number;
  tracking: Readonly<{
    sessions: number;
    sessions_with_watch: number;
    completed_sets: number;
    watch_sets: number;
  }>;
  set_start: Readonly<{
    state: SetStartState;
    reason: SetStartReason | null;
    sets: number;
    sessions: number;
    median_reserve_fraction: number | null;
    median_rest_seconds: number | null;
    cause: SetStartCause | null;
  }>;
  recovery: Readonly<{ state: HeartRateProfile["recovery"]["state"]; change_bpm: number | null }>;
  /** What the engine may do with the signals. Nothing here carries a load, repetitions or sets. */
  engine: Readonly<{
    confidence: "none" | "lower";
    rest: "none" | "allow_longer";
    question: "recovery_check" | null;
    reasons: readonly ("rest_short" | "slow_settling" | "recovery_slower")[];
  }>;
}>;

const dayMs = 86_400_000;

function daysBetween(from: string, to: string): number {
  return Math.floor(Date.parse(`${to}T00:00:00Z`) / dayMs) -
    Math.floor(Date.parse(`${from}T00:00:00Z`) / dayMs);
}

function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function twoDecimals(value: number): number {
  return Math.round(value * 100) / 100;
}

function isTracked(set: LoadSignalSet): boolean {
  return set.source === "watch_workout" && set.coverage >= trackedMinimumCoverage;
}

/**
 * The signals from the stored workouts and the heart-rate profile as of the same date. Anything
 * missing stays missing; a signal with too little behind it says so and changes nothing.
 */
export function computeLoadSignals(
  inputs: WorkoutLoadInputs,
  profile: HeartRateProfile,
): LoadSignals {
  const sessions = inputs.sessions.filter((session) => {
    const age = daysBetween(session.local_date, inputs.as_of);
    return age >= 0 && age < loadSignalWindowDays && session.completed_sets > 0;
  });

  let completedSets = 0;
  let watchSets = 0;
  let sessionsWithWatch = 0;
  for (const session of sessions) {
    completedSets += session.completed_sets;
    const tracked = session.sets.filter(isTracked).length;
    watchSets += tracked;
    if (tracked > 0) sessionsWithWatch += 1;
  }

  const resting = profile.resting.bpm;
  const max = profile.max.bpm;
  const hasProfile = profile.zones_missing === null && resting !== null && max !== null;
  const fractions: number[] = [];
  const rests: number[] = [];
  const settleSessions = new Set<string>();
  if (hasProfile) {
    const reserve = max - resting;
    sessions.forEach((session, index) => {
      for (const set of session.sets) {
        if (
          !isTracked(set) || set.start_bpm === null || set.rest_before_seconds === null ||
          set.rest_before_seconds < settleMinimumRestSeconds
        ) continue;
        fractions.push((set.start_bpm - resting) / reserve);
        rests.push(set.rest_before_seconds);
        settleSessions.add(`${index}`);
      }
    });
  }

  let setStart: LoadSignals["set_start"];
  if (!hasProfile) {
    setStart = {
      state: "not_enough_data",
      reason: "no_profile",
      sets: 0,
      sessions: 0,
      median_reserve_fraction: null,
      median_rest_seconds: null,
      cause: null,
    };
  } else if (fractions.length < settleMinimumSets || settleSessions.size < settleMinimumSessions) {
    setStart = {
      state: "not_enough_data",
      reason: "too_few_sets",
      sets: fractions.length,
      sessions: settleSessions.size,
      median_reserve_fraction: null,
      median_rest_seconds: null,
      cause: null,
    };
  } else {
    const middleFraction = median(fractions);
    const middleRest = Math.round(median(rests));
    const elevated = middleFraction >= settleElevatedFraction;
    setStart = {
      state: elevated ? "elevated" : "steady",
      reason: null,
      sets: fractions.length,
      sessions: settleSessions.size,
      median_reserve_fraction: twoDecimals(middleFraction),
      median_rest_seconds: middleRest,
      cause: elevated ? (middleRest < shortRestSeconds ? "rest_short" : "slow_settling") : null,
    };
  }

  const reasons: LoadSignals["engine"]["reasons"][number][] = [];
  if (setStart.cause !== null) reasons.push(setStart.cause);
  if (profile.recovery.state === "slower") reasons.push("recovery_slower");
  const lowersConfidence = reasons.includes("slow_settling") || reasons.includes("recovery_slower");

  return {
    schema_version: "1.0",
    as_of: inputs.as_of,
    window_days: loadSignalWindowDays,
    tracking: {
      sessions: sessions.length,
      sessions_with_watch: sessionsWithWatch,
      completed_sets: completedSets,
      watch_sets: watchSets,
    },
    set_start: setStart,
    recovery: { state: profile.recovery.state, change_bpm: profile.recovery.change_bpm },
    engine: {
      confidence: lowersConfidence ? "lower" : "none",
      rest: reasons.includes("rest_short") ? "allow_longer" : "none",
      question: lowersConfidence ? "recovery_check" : null,
      reasons,
    },
  };
}
