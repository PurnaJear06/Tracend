import { blockOf, type CoachContextContributor, sharedRead } from "../host.ts";
import { plain, record } from "../../recorded_text.ts";
import { coachServiceRpc } from "../service_source.ts";
import { heartRateInputsReadKey, loadHeartRateInputs } from "../../training/heart_rate/inputs.ts";
import {
  buildHeartRateProfile,
  type HeartRateInputs,
  type HeartRateProfile,
} from "../../training/heart_rate/profile.ts";

// Contract 7 contributor for the heart-rate profile (chunk C3), registered with E3.
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
  return `${record(value)} bpm`;
}

/** The compact text for the Coach; null when nothing at all is known. */
export function renderHeartRateProfile(profile: HeartRateProfile): string | null {
  const marked = heartRateMarked(profile);
  return marked === null ? null : plain(marked);
}

// The measured and calculated values are marked records (`../../recorded_text.ts`); the formula and
// its constants, the 28-day windows and the zone definitions are fixed wording and ground nothing.
function heartRateMarked(profile: HeartRateProfile): string | null {
  const { resting, max, zones, recovery } = profile;
  if (resting.bpm === null && max.bpm === null && recovery.recent_drop_60s_bpm === null) {
    return null;
  }
  const lines = [
    "Heart-rate profile, worked out by Tracend from the athlete's Apple Watch summaries. It " +
    "informs rest, cardio and recovery talk. It never sets a load or a prescription.",
    resting.bpm === null
      ? "Resting heart rate: not enough days of data."
      : `Resting heart rate: ${beats(resting.bpm)} (median of ${record(resting.days)} days).`,
  ];
  if (max.bpm === null) {
    lines.push("Maximum heart rate: unknown (no usable age or workout peak).");
  } else if (max.basis === "observed") {
    lines.push(
      `Maximum heart rate: ${beats(max.bpm)}, the highest trusted workout peak ` +
        `(${record(max.observed_on ?? "")})` +
        (max.formula_bpm === null ? "." : `; the age formula says ${record(max.formula_bpm)}.`),
    );
  } else {
    lines.push(
      `Maximum heart rate: ${beats(max.bpm)}, estimated from age ${
        record(profile.age_years ?? "")
      } ` +
        "(208 - 0.7 x age, Tanaka 2001, about 10 bpm either way). No higher trusted peak yet.",
    );
  }
  if (zones.length > 0) {
    lines.push(
      "Zones (share of heart-rate reserve, Karvonen): " +
        zones.map((z) => `Z${z.zone} ${z.label} ${record(`${z.low_bpm}-${z.high_bpm}`)}`).join(
          ", ",
        ) + ".",
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
        : `Recovery after sets: heart rate falls ${
          record(recovery.recent_drop_60s_bpm)
        } bpm in the ` +
          "minute after a set (last 28 days); the earlier 28 days are too thin to compare.",
    );
  } else {
    lines.push(
      `Recovery after sets: heart rate falls ${
        record(recovery.recent_drop_60s_bpm!)
      } bpm in the minute ` +
        `after a set (last 28 days, ${record(recovery.recent_sets)} sets), ${recovery.state} ` +
        `(${
          record(`${recovery.change_bpm! >= 0 ? "+" : ""}${recovery.change_bpm}`)
        } bpm against the 28 days before).`,
    );
  }
  return lines.join("\n");
}

/** The contributor, reading inputs through `load`. */
export function createHeartRateContributor(load: HeartRateInputsLoader): CoachContextContributor {
  return Object.freeze({
    id: heartRateContributorId,
    slot: "volatile",
    budgetChars: heartRateBudgetChars,
    async render(input) {
      const inputs = await sharedRead(
        input,
        heartRateInputsReadKey,
        () => load(input.userId, input.localDate),
      ) as HeartRateInputs | null;
      const marked = inputs === null ? null : heartRateMarked(buildHeartRateProfile(inputs));
      return marked === null ? null : blockOf(marked);
    },
  });
}

/** The profile's inputs from `get_heart_rate_inputs_v1` over the service role; null when unavailable. */
export const heartRateInputsFromService: HeartRateInputsLoader = (userId, localDate) =>
  loadHeartRateInputs(
    {
      rpc: async (name, args) => {
        const { data, error } = await coachServiceRpc(name, args);
        return { data, error: error ? { message: "heart_rate_inputs_unavailable" } : null };
      },
    },
    userId,
    localDate,
  );

/** The registered contributor: it reads `get_heart_rate_inputs_v1` with the service role. */
export const heartRateContributor: CoachContextContributor = createHeartRateContributor(
  heartRateInputsFromService,
);
