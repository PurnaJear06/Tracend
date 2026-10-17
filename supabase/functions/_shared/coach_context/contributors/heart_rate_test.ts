import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import cases from "../../training/heart_rate/profile_cases.json" with { type: "json" };
import type { HeartRateInputs } from "../../training/heart_rate/profile.ts";
import { buildHeartRateProfile } from "../../training/heart_rate/profile.ts";
import { renderCoachContext, validateCoachContextContributors } from "../host.ts";
import { coachContextContributors } from "../registry.ts";
import {
  createHeartRateContributor,
  heartRateBudgetChars,
  heartRateContributorId,
  renderHeartRateProfile,
} from "./heart_rate.ts";

function inputsNamed(name: string): HeartRateInputs {
  const found = cases.find((given) => given.name === name);
  assert(found, name);
  return found.inputs as unknown as HeartRateInputs;
}

const request = {
  userId: "user-1",
  question: "How hard should I push cardio?",
  localDate: "2026-10-17",
};

Deno.test("the contributor is valid and is not registered yet", () => {
  const contributor = createHeartRateContributor(() => Promise.resolve(null));
  validateCoachContextContributors([contributor]);
  assertEquals(contributor.id, heartRateContributorId);
  assertEquals(contributor.slot, "volatile");
  assertEquals(contributor.budgetChars, heartRateBudgetChars);
  assertEquals(coachContextContributors.map((c) => c.id).includes(heartRateContributorId), false);
});

Deno.test("the text states resting, an age-formula maximum, zones and the missing trend", () => {
  const text = renderHeartRateProfile(
    buildHeartRateProfile(inputsNamed("formula from age with resting and zones")),
  )!;
  assertStringIncludes(text, "Resting heart rate: 59 bpm (median of 13 days).");
  assertStringIncludes(text, "Maximum heart rate: 183 bpm, estimated from age 36");
  assertStringIncludes(text, "Tanaka 2001");
  assertStringIncludes(text, "Z1 Easy 121-132");
  assertStringIncludes(text, "Z5 Maximum 171-183");
  assertStringIncludes(text, "Recovery after sets: not enough tracked sets to judge.");
  assertStringIncludes(text, "never sets a load or a prescription");
});

Deno.test("an observed peak, a recovery trend and honest gaps are all stated", () => {
  const observed = renderHeartRateProfile(
    buildHeartRateProfile(inputsNamed("a trusted higher peak replaces the formula")),
  )!;
  assertStringIncludes(observed, "Maximum heart rate: 190 bpm, the highest trusted workout peak");
  assertStringIncludes(observed, "the age formula says 183");
  const improving = renderHeartRateProfile(
    buildHeartRateProfile(inputsNamed("recovery improving")),
  )!;
  assertStringIncludes(improving, "falls 30 bpm in the minute after a set");
  assertStringIncludes(improving, "improving (+6 bpm against the 28 days before)");
  const slower = renderHeartRateProfile(buildHeartRateProfile(inputsNamed("recovery slower")))!;
  assertStringIncludes(slower, "slower (-7 bpm");
  const noMax = renderHeartRateProfile(
    buildHeartRateProfile(inputsNamed("no birth year and no peaks leaves the maximum missing")),
  )!;
  assertStringIncludes(noMax, "Maximum heart rate: unknown");
  assertStringIncludes(noMax, "Zones: not available (maximum heart rate is unknown)");
  const noResting = renderHeartRateProfile(
    buildHeartRateProfile(inputsNamed("fewer than three resting days leaves zones missing")),
  )!;
  assertStringIncludes(noResting, "Resting heart rate: not enough days of data.");
  assertStringIncludes(noResting, "resting heart rate is missing");
});

Deno.test("nothing is rendered when nothing is known, and sleeping heart rate never appears", () => {
  const empty: HeartRateInputs = {
    schema_version: "1.0",
    as_of: "2026-10-17",
    birth_year: null,
    resting: [],
    sets: [],
    peak_candidates: [],
  };
  assertEquals(renderHeartRateProfile(buildHeartRateProfile(empty)), null);
  for (const given of cases) {
    const text = renderHeartRateProfile(
      buildHeartRateProfile(given.inputs as unknown as HeartRateInputs),
    );
    if (text !== null) assertEquals(/sleep/i.test(text), false, given.name);
  }
});

Deno.test("every rendered case fits the budget", () => {
  for (const given of cases) {
    const text = renderHeartRateProfile(
      buildHeartRateProfile(given.inputs as unknown as HeartRateInputs),
    );
    if (text !== null) assert(text.length <= heartRateBudgetChars, `${given.name}: ${text.length}`);
  }
});

Deno.test("the host renders it as labelled reference data, and a failed load leaves it out", async () => {
  const given = inputsNamed("recovery improving");
  const seen: string[] = [];
  const working = createHeartRateContributor((userId, localDate) => {
    seen.push(`${userId}:${localDate}`);
    return Promise.resolve(given);
  });
  const result = await renderCoachContext([working], request);
  assertEquals(seen, ["user-1:2026-10-17"]);
  assertStringIncludes(result.volatile, '<reference_data source="heart_rate_profile">');
  assertEquals(result.outcomes[0].outcome, "rendered");
  const missing = await renderCoachContext(
    [createHeartRateContributor(() => Promise.resolve(null))],
    request,
  );
  assertEquals(missing.outcomes[0].outcome, "empty");
  const failing = await renderCoachContext(
    [createHeartRateContributor(() => Promise.reject(new Error("down")))],
    request,
  );
  assertEquals(failing.outcomes[0].outcome, "failed");
  assertEquals(failing.volatile, "");
});
