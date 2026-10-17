// The heart-rate profile (coaching platform chunk C3): resting heart rate, an estimated maximum,
// heart-rate zones and recovery after sets. Deterministic arithmetic over summaries only; raw
// samples never leave the phone. Heart rate informs; it never sets a load or a prescription
// (program decision D9). Sleeping heart rate is NOT an input here (D10, shadow mode).
//
// The Dart twin is lib/features/workout_hr/heart_rate_profile.dart. Both read the cases in
// profile_cases.json, so the two cannot drift apart.

/** One set's summary as `get_my_heart_rate_inputs_v1` returns it (Contract 4 values). */
export type HeartRateSetRow = Readonly<{
  local_date: string;
  start_bpm: number | null;
  peak_bpm: number | null;
  end_bpm: number | null;
  drop_30s_bpm: number | null;
  drop_60s_bpm: number | null;
  coverage: number;
  sample_count: number;
  source: "watch_workout" | "background";
}>;

export type HeartRateInputs = Readonly<{
  schema_version: string;
  as_of: string;
  birth_year: number | null;
  resting: ReadonlyArray<Readonly<{ local_date: string; bpm: number }>>;
  /** Sets of the last 60 days, for the recovery trend. */
  sets: readonly HeartRateSetRow[];
  /** The sets with the highest peaks of the last 365 days. */
  peak_candidates: readonly HeartRateSetRow[];
}>;

export type MaxBasis = "observed" | "age_formula" | "missing";
export type ZonesMissing = "no_resting" | "no_max" | "narrow_reserve";
export type RecoveryState = "improving" | "steady" | "slower" | "not_enough_data";

export type HeartRateZone = Readonly<{
  zone: number;
  label: string;
  low_bpm: number;
  high_bpm: number;
}>;

export type HeartRateProfile = Readonly<{
  schema_version: "1.0";
  as_of: string;
  age_years: number | null;
  resting: Readonly<{ bpm: number | null; days: number }>;
  max: Readonly<{
    bpm: number | null;
    basis: MaxBasis;
    formula_bpm: number | null;
    observed_bpm: number | null;
    observed_on: string | null;
  }>;
  zones: readonly HeartRateZone[];
  zones_missing: ZonesMissing | null;
  recovery: Readonly<{
    state: RecoveryState;
    recent_drop_60s_bpm: number | null;
    prior_drop_60s_bpm: number | null;
    change_bpm: number | null;
    recent_sets: number;
    prior_sets: number;
  }>;
}>;

// Estimated maximum: Tanaka, Monahan and Seals (2001), "Age-predicted maximal heart rate
// revisited", J Am Coll Cardiol 37(1):153-156: HRmax = 208 - 0.7 x age. Their sample covered adults
// of 18 to 81 and the fit has a residual of about 10 bpm, so the formula is used for 16 to 90.
export const tanakaIntercept = 208;
export const tanakaSlope = 0.7;
export const formulaAgeRange = Object.freeze({ min: 16, max: 90 });
export const tanakaResidualBpm = 10;

// An observed peak replaces the formula only when it is plausible and well measured. A wrist
// sensor spikes (cadence lock, a loose strap), so a peak more than two residuals (20 bpm) above
// the formula is refused; with no age the ceiling is 210 bpm. A trusted set was recorded by a
// Watch workout (readings every few seconds), has at least 8 readings and covered at least 60% of
// the set and the minute after it. Peaks below 120 bpm are never a maximum.
export const peakMinimumBpm = 120;
export const peakCeilingWithoutAgeBpm = 210;
export const peakMinimumSamples = 8;
export const peakMinimumCoverage = 0.6;

// Zones: heart-rate reserve (Karvonen, Kentala and Mustala 1957, Ann Med Exp Biol Fenn 35:307):
// target = resting + fraction x (maximum - resting). Five bands in 10-point steps from 50% to 100%
// of reserve, the five-zone layout common to heart-rate watches. Intensity anchors agree with the
// ACSM Guidelines (moderate 40-59% of reserve, vigorous 60-89%, near-maximal 90% and above).
// Below 50% is no zone.
export const zoneBands: ReadonlyArray<Readonly<{ zone: number; label: string }>> = Object
  .freeze([
    { zone: 1, label: "Easy" },
    { zone: 2, label: "Aerobic" },
    { zone: 3, label: "Tempo" },
    { zone: 4, label: "Hard" },
    { zone: 5, label: "Maximum" },
  ]);
export const zoneCutFractions = Object.freeze([0.5, 0.6, 0.7, 0.8, 0.9, 1]);
export const minimumReserveBpm = 20;

// Resting heart rate: the median of the daily values of the last 14 days, from at least 3 days.
export const restingWindowDays = 14;
export const restingMinimumDays = 3;
export const restingRange = Object.freeze({ min: 30, max: 120 });

// Recovery after sets: the drop in the minute after a set (Contract 4 `drop_60s_bpm`), compared
// between the last 28 days and the 28 days before. It is a trend of the athlete against
// themselves; one-minute recovery after maximal exercise (Cole et al. 1999, N Engl J Med
// 341:1351-1357) has no threshold for a set of lifting, so none is applied. A set counts when it
// has the drop, covered at least 60% and ended at least 20 bpm above resting heart rate (100 bpm
// when resting is unknown): a set that never raised the heart rate has nothing to recover from.
export const recoveryWindowDays = 28;
export const recoveryMinimumSets = 6;
export const recoveryMinimumCoverage = 0.6;
export const recoveryElevationBpm = 20;
export const recoveryElevationWithoutRestingBpm = 100;
export const recoveryTrendBpm = 3;

const dayMs = 86_400_000;

function dayNumber(date: string): number {
  return Math.floor(Date.parse(`${date}T00:00:00Z`) / dayMs);
}

/** Calendar days from `from` to `to` (both YYYY-MM-DD). */
function daysBetween(from: string, to: string): number {
  return dayNumber(to) - dayNumber(from);
}

function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function oneDecimal(value: number): number {
  return Math.round(value * 10) / 10;
}

/** Whole beats, halves rounding up (the same as Dart's `num.round` for positive values). */
function whole(value: number): number {
  return Math.round(value);
}

/** Age in whole years on `asOf`, or null when there is no birth year or the age is not one the formula covers. */
export function ageYears(birthYear: number | null, asOf: string): number | null {
  if (birthYear === null) return null;
  const age = Number(asOf.slice(0, 4)) - birthYear;
  return age >= formulaAgeRange.min && age <= formulaAgeRange.max ? age : null;
}

/** Tanaka et al. (2001): 208 - 0.7 x age, rounded to a whole beat. */
export function tanakaMaxHeartRate(age: number): number {
  return whole(tanakaIntercept - tanakaSlope * age);
}

/** Whether a set's peak can stand as the athlete's observed maximum. */
export function isTrustedPeak(row: HeartRateSetRow, formulaBpm: number | null): boolean {
  if (row.peak_bpm === null || row.source !== "watch_workout") return false;
  if (row.sample_count < peakMinimumSamples || row.coverage < peakMinimumCoverage) return false;
  const ceiling = formulaBpm === null
    ? peakCeilingWithoutAgeBpm
    : formulaBpm + 2 * tanakaResidualBpm;
  return row.peak_bpm >= peakMinimumBpm && row.peak_bpm <= ceiling;
}

/** Karvonen zones; empty when resting or maximum is missing or the reserve is too narrow. */
export function heartRateZones(resting: number, max: number): readonly HeartRateZone[] {
  const reserve = max - resting;
  if (reserve < minimumReserveBpm) return [];
  const cuts = zoneCutFractions.map((fraction) => whole(resting + fraction * reserve));
  return zoneBands.map((band, index) => ({
    zone: band.zone,
    label: band.label,
    low_bpm: cuts[index],
    high_bpm: index === zoneBands.length - 1 ? cuts[index + 1] : cuts[index + 1] - 1,
  }));
}

function restingBasis(inputs: HeartRateInputs): { bpm: number | null; days: number } {
  const values = inputs.resting
    .filter((row) => {
      const age = daysBetween(row.local_date, inputs.as_of);
      return age >= 0 && age < restingWindowDays && row.bpm >= restingRange.min &&
        row.bpm <= restingRange.max;
    })
    .map((row) => row.bpm);
  return {
    bpm: values.length >= restingMinimumDays ? whole(median(values)) : null,
    days: values.length,
  };
}

function recoveryTrend(
  inputs: HeartRateInputs,
  restingBpm: number | null,
): HeartRateProfile["recovery"] {
  const floor = restingBpm === null
    ? recoveryElevationWithoutRestingBpm
    : restingBpm + recoveryElevationBpm;
  const recent: number[] = [];
  const prior: number[] = [];
  for (const row of inputs.sets) {
    if (
      row.drop_60s_bpm === null || row.end_bpm === null || row.coverage < recoveryMinimumCoverage ||
      row.end_bpm < floor
    ) continue;
    const age = daysBetween(row.local_date, inputs.as_of);
    if (age >= 0 && age < recoveryWindowDays) recent.push(row.drop_60s_bpm);
    else if (age >= recoveryWindowDays && age < 2 * recoveryWindowDays) {
      prior.push(row.drop_60s_bpm);
    }
  }
  const recentDrop = recent.length >= recoveryMinimumSets ? oneDecimal(median(recent)) : null;
  const priorDrop = prior.length >= recoveryMinimumSets ? oneDecimal(median(prior)) : null;
  const change = recentDrop !== null && priorDrop !== null
    ? oneDecimal(recentDrop - priorDrop)
    : null;
  const state: RecoveryState = change === null
    ? "not_enough_data"
    : change >= recoveryTrendBpm
    ? "improving"
    : change <= -recoveryTrendBpm
    ? "slower"
    : "steady";
  return {
    state,
    recent_drop_60s_bpm: recentDrop,
    prior_drop_60s_bpm: priorDrop,
    change_bpm: change,
    recent_sets: recent.length,
    prior_sets: prior.length,
  };
}

/** The profile from the stored inputs; anything missing stays missing, nothing is invented. */
export function buildHeartRateProfile(inputs: HeartRateInputs): HeartRateProfile {
  const age = ageYears(inputs.birth_year, inputs.as_of);
  const formula = age === null ? null : tanakaMaxHeartRate(age);
  const resting = restingBasis(inputs);

  let observed: HeartRateSetRow | null = null;
  for (const row of inputs.peak_candidates) {
    if (!isTrustedPeak(row, formula)) continue;
    if (observed === null || row.peak_bpm! > observed.peak_bpm!) observed = row;
  }
  const observedBpm = observed?.peak_bpm ?? null;
  const useObserved = observedBpm !== null && (formula === null || observedBpm > formula);
  const maxBpm = useObserved ? observedBpm : formula;
  const basis: MaxBasis = useObserved ? "observed" : formula !== null ? "age_formula" : "missing";

  const zonesMissing: ZonesMissing | null = resting.bpm === null
    ? "no_resting"
    : maxBpm === null
    ? "no_max"
    : maxBpm - resting.bpm < minimumReserveBpm
    ? "narrow_reserve"
    : null;
  return {
    schema_version: "1.0",
    as_of: inputs.as_of,
    age_years: age,
    resting: { bpm: resting.bpm, days: resting.days },
    max: {
      bpm: maxBpm,
      basis,
      formula_bpm: formula,
      observed_bpm: observedBpm,
      observed_on: observed?.local_date ?? null,
    },
    zones: zonesMissing === null ? heartRateZones(resting.bpm!, maxBpm!) : [],
    zones_missing: zonesMissing,
    recovery: recoveryTrend(inputs, resting.bpm),
  };
}
