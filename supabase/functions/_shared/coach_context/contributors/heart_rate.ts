import type { CoachContextContributor } from "../host.ts";
import {
  buildHeartRateProfile,
  type HeartRateInputs,
  type HeartRateProfile,
} from "../../training/heart_rate/profile.ts";

// Contract 7 contributor for the heart-rate profile (chunk C3). It is not registered yet: the lead
// adds it to registry.ts with E3 in round 3, so the Coach prompt does not change in round 2.
//
// The text is computed by Tracend from Apple Watch summaries. It tells the Coach what is known and
// what is missing, never a guess. Heart rate informs rest, cardio dosing and recovery questions;
// it never sets a load or a prescription (D9). Sleeping heart rate is in shadow mode (D10) and is
// not part of it.

export const heartRateContributorId = "heart_rate_profile";
export const heartRateBudgetChars = 900;

export type HeartRateInputsLoader = (
  userId: string,
  localDate: string,
) => Promise<HeartRateInputs | null>;

function beats(value: number): string {
  return `${value} bpm`;
}

/** The compact text for the Coach; null when nothing at all is known. */
export function renderHeartRateProfile(profile: HeartRateProfile): string | null {
  const { resting, max, zones, recovery } = profile;
  if (resting.bpm === null && max.bpm === null && recovery.recent_drop_60s_bpm === null) {
    return null;
  }
  const lines = [
    "Heart-rate profile, worked out by Tracend from the athlete's Apple Watch summaries. It " +
    "informs rest, cardio and recovery talk. It never sets a load or a prescription.",
    resting.bpm === null
      ? "Resting heart rate: not enough days of data."
      : `Resting heart rate: ${beats(resting.bpm)} (median of ${resting.days} days).`,
  ];
  if (max.bpm === null) {
    lines.push("Maximum heart rate: unknown (no usable age or workout peak).");
  } else if (max.basis === "observed") {
    lines.push(
      `Maximum heart rate: ${beats(max.bpm)}, the highest trusted workout peak ` +
        `(${max.observed_on})` +
        (max.formula_bpm === null ? "." : `; the age formula says ${max.formula_bpm}.`),
    );
  } else {
    lines.push(
      `Maximum heart rate: ${beats(max.bpm)}, estimated from age ${profile.age_years} ` +
        "(208 - 0.7 x age, Tanaka 2001, about 10 bpm either way). No higher trusted peak yet.",
    );
  }
  if (zones.length > 0) {
    lines.push(
      "Zones (share of heart-rate reserve, Karvonen): " +
        zones.map((z) => `Z${z.zone} ${z.label} ${z.low_bpm}-${z.high_bpm}`).join(", ") + ".",
    );
  } else {
    lines.push(
      "Zones: not available (" +
        (profile.zones_missing === "no_resting"
          ? "resting heart rate is missing"
          : profile.zones_missing === "no_max"
          ? "maximum heart rate is unknown"
          : "the gap between resting and maximum is too small") +
        ").",
    );
  }
  if (recovery.state === "not_enough_data") {
    lines.push(
      recovery.recent_drop_60s_bpm === null
        ? "Recovery after sets: not enough tracked sets to judge."
        : `Recovery after sets: heart rate falls ${recovery.recent_drop_60s_bpm} bpm in the ` +
          "minute after a set (last 28 days); the earlier 28 days are too thin to compare.",
    );
  } else {
    lines.push(
      `Recovery after sets: heart rate falls ${recovery.recent_drop_60s_bpm} bpm in the minute ` +
        `after a set (last 28 days, ${recovery.recent_sets} sets), ${recovery.state} ` +
        `(${
          recovery.change_bpm! >= 0 ? "+" : ""
        }${recovery.change_bpm} bpm against the 28 days before).`,
    );
  }
  return lines.join("\n");
}

/** The contributor, reading inputs through `load` (the lead wires the service-role loader). */
export function createHeartRateContributor(load: HeartRateInputsLoader): CoachContextContributor {
  return Object.freeze({
    id: heartRateContributorId,
    slot: "volatile",
    budgetChars: heartRateBudgetChars,
    async render(input) {
      const inputs = await load(input.userId, input.localDate);
      return inputs === null ? null : renderHeartRateProfile(buildHeartRateProfile(inputs));
    },
  });
}
