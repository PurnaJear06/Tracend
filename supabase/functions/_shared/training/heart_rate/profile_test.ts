import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import cases from "./profile_cases.json" with { type: "json" };
import {
  ageYears,
  buildHeartRateProfile,
  type HeartRateInputs,
  type HeartRateSetRow,
  heartRateZones,
  isTrustedPeak,
  tanakaMaxHeartRate,
} from "./profile.ts";

Deno.test("every shared case produces its expected profile (the Dart twin reads the same file)", () => {
  assert(cases.length >= 15);
  for (const given of cases) {
    assertEquals(
      JSON.parse(JSON.stringify(buildHeartRateProfile(given.inputs as HeartRateInputs))),
      given.expected,
      given.name,
    );
  }
});

Deno.test("Tanaka 2001: 208 - 0.7 x age, and only for the ages it covers", () => {
  assertEquals(tanakaMaxHeartRate(20), 194);
  assertEquals(tanakaMaxHeartRate(36), 183);
  assertEquals(tanakaMaxHeartRate(50), 173);
  assertEquals(ageYears(1990, "2026-10-17"), 36);
  assertEquals(ageYears(null, "2026-10-17"), null);
  assertEquals(ageYears(2011, "2026-10-17"), null);
  assertEquals(ageYears(2010, "2026-10-17"), 16);
  assertEquals(ageYears(1936, "2026-10-17"), 90);
  assertEquals(ageYears(1935, "2026-10-17"), null);
});

Deno.test("Karvonen zones: resting plus 50 to 100 percent of the reserve", () => {
  assertEquals(heartRateZones(60, 180).map((z) => [z.zone, z.low_bpm, z.high_bpm]), [
    [1, 120, 131],
    [2, 132, 143],
    [3, 144, 155],
    [4, 156, 167],
    [5, 168, 180],
  ]);
  assertEquals(heartRateZones(60, 70), []);
});

Deno.test("a peak needs a Watch workout, enough readings, coverage and a sane value", () => {
  const row: HeartRateSetRow = {
    local_date: "2026-10-01",
    start_bpm: 100,
    peak_bpm: 190,
    end_bpm: 180,
    drop_30s_bpm: 10,
    drop_60s_bpm: 20,
    coverage: 0.9,
    sample_count: 20,
    source: "watch_workout",
  };
  assert(isTrustedPeak(row, 183));
  assert(isTrustedPeak({ ...row, peak_bpm: 203 }, 183));
  assert(!isTrustedPeak({ ...row, peak_bpm: 204 }, 183));
  assert(!isTrustedPeak({ ...row, peak_bpm: 119 }, null));
  assert(!isTrustedPeak({ ...row, sample_count: 7 }, 183));
  assert(!isTrustedPeak({ ...row, coverage: 0.59 }, 183));
  assert(!isTrustedPeak({ ...row, source: "background" }, 183));
  assert(!isTrustedPeak({ ...row, peak_bpm: null }, 183));
});

Deno.test("sleeping heart rate is not an input of the profile (D10, shadow mode)", () => {
  const inputs = cases[0].inputs as unknown as Record<string, unknown>;
  assertEquals(Object.keys(inputs).sort(), [
    "as_of",
    "birth_year",
    "peak_candidates",
    "resting",
    "schema_version",
    "sets",
  ]);
  const withExtra = { ...inputs, sleeping_heart_rate: [{ local_date: "2026-10-16", bpm: 40 }] };
  assertEquals(
    buildHeartRateProfile(withExtra as unknown as HeartRateInputs),
    buildHeartRateProfile(inputs as unknown as HeartRateInputs),
  );
});
