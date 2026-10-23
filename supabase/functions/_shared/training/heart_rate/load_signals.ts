// Load signals for the training engine (coaching platform chunk C4): what the athlete's Apple Watch
// heart rate says about rest and recovery across the last 28 days of finished workouts. Pure
// arithmetic over per-set summaries and the heart-rate profile; raw samples never leave the phone.
//
// Heart rate informs; it never sets a load or a prescription (program decision D9). A signal can
// lower the confidence the engine puts in a progression step or suggest a longer rest. Nothing here can raise a load, a repetition target or a set count: the
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

/** Why the engine is asked to act: the reasons a sentence is chosen by. */
export type LoadSignalReason = "rest_short" | "slow_settling" | "recovery_slower";

/**
 * What the training engine may do with the signals. Nothing here carries a load, repetitions or
 * sets: `confidence` only ever lowers, `rest` only ever allows a longer rest. `reasons` say which
 * rule fired (`recovery_slower` is a comparison with the athlete's own earlier weeks; `slow_settling`
 * is a fixed line, so it must never be worded as "than usual").
 */
export type LoadSignals = Readonly<{
  engine: Readonly<{
    confidence: "none" | "lower";
    rest: "none" | "allow_longer";
    reasons: readonly LoadSignalReason[];
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

function isTracked(set: LoadSignalSet): boolean {
  return set.source === "watch_workout" && set.coverage >= trackedMinimumCoverage;
}

/**
 * The signals from the stored workouts and the heart-rate profile as of the same date. Anything
 * missing stays missing; a rule with too little behind it fires nothing.
 */
export function computeLoadSignals(
  inputs: WorkoutLoadInputs,
  profile: HeartRateProfile,
): LoadSignals {
  const sessions = inputs.sessions.filter((session) => {
    const age = daysBetween(session.local_date, inputs.as_of);
    return age >= 0 && age < loadSignalWindowDays && session.completed_sets > 0;
  });

  const reasons: LoadSignalReason[] = [];
  const resting = profile.resting.bpm;
  const max = profile.max.bpm;
  if (profile.zones_missing === null && resting !== null && max !== null) {
    const reserve = max - resting;
    const fractions: number[] = [];
    const rests: number[] = [];
    const settleSessions = new Set<number>();
    sessions.forEach((session, index) => {
      for (const set of session.sets) {
        if (
          !isTracked(set) || set.start_bpm === null || set.rest_before_seconds === null ||
          set.rest_before_seconds < settleMinimumRestSeconds
        ) continue;
        fractions.push((set.start_bpm - resting) / reserve);
        rests.push(set.rest_before_seconds);
        settleSessions.add(index);
      }
    });
    if (
      fractions.length >= settleMinimumSets && settleSessions.size >= settleMinimumSessions &&
      median(fractions) >= settleElevatedFraction
    ) {
      reasons.push(median(rests) < shortRestSeconds ? "rest_short" : "slow_settling");
    }
  }
  if (profile.recovery.state === "slower") reasons.push("recovery_slower");

  return {
    engine: {
      confidence: reasons.includes("slow_settling") || reasons.includes("recovery_slower")
        ? "lower"
        : "none",
      rest: reasons.includes("rest_short") ? "allow_longer" : "none",
      reasons,
    },
  };
}
