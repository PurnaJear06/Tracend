import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { renderSafeRanges, safeRangesOf } from "./safe_ranges.ts";
import { ownerContext } from "./fixtures.ts";
import { renderCoachContextParts } from "../providers/coach_chat_provider.ts";
import { calorieFloorKcal } from "../onboarding/policy.ts";

Deno.test("the owner's case: the floor is his resting energy, the ceiling 1% of 74.4 kg", () => {
  const ranges = safeRangesOf(ownerContext());
  assertEquals(ranges.calorieFloorKcal, 1719);
  assertEquals(ranges.calorieFloorBasis, "resting_energy");
  assertEquals(ranges.weightKg, 74.4);
  assertEquals(Math.round(ranges.weeklyLossCeilingKg! * 1000) / 1000, 0.744);
  assertEquals(ranges.healthyFloorKg, 59.9);
  assertEquals(ranges.longestCutWeeks, 16);
  assertEquals(ranges.painEscalated, false);
  const text = renderSafeRanges(ranges);
  assertStringIncludes(text, "Calorie floor: 1719 kcal a day");
  assertStringIncludes(text, "1% of body weight a week, which is 0.74 kg at 74.4 kg");
  assertStringIncludes(text, "BMI 18.5, which is 59.9 kg at 180 cm");
  assertStringIncludes(text, "Longest continuous cut: 16 weeks");
  assert(!text.includes("pain of 7"));
});

Deno.test("the floor is the policy's: the sex-based minimum when resting energy is lower", () => {
  const woman = safeRangesOf(ownerContext({
    profile_context: { height_cm: 160, sex: "female", age: 40 },
    weight_series_8w: [{ measured_on: "2026-10-14", weight_kg: 50, waist_cm: null }],
  }));
  assertEquals(woman.calorieFloorKcal, calorieFloorKcal("female", 50, 160, 40));
  assertEquals(woman.calorieFloorKcal, 1200);
  assertEquals(woman.calorieFloorBasis, "sex_minimum");
});

Deno.test("missing data degrades to what is known, never to a guess", () => {
  const ranges = safeRangesOf({});
  assertEquals(ranges.calorieFloorKcal, 1500);
  assertEquals(ranges.weightKg, null);
  assertEquals(ranges.weeklyLossCeilingKg, null);
  assertEquals(ranges.healthyFloorKg, null);
  const text = renderSafeRanges(ranges);
  assertStringIncludes(text, "Weekly loss ceiling: 1% of body weight a week. Never advise");
  assertStringIncludes(text, "height is not on file");
});

Deno.test("today's pain of 7 or more is stated in the section", () => {
  const ranges = safeRangesOf(ownerContext({
    permitted_evidence: ["APPROVED_PLAN_ACTIVE", "CHECK_IN_SAFETY_ESCALATION"],
  }));
  assert(ranges.painEscalated);
  assertStringIncludes(renderSafeRanges(ranges), "Today's check-in: pain of 7 or more");
});

Deno.test("the athlete file carries the section before the plan, even for an empty context", () => {
  for (const context of [ownerContext(), {}]) {
    const { file } = renderCoachContextParts(context, 96_000);
    assertStringIncludes(file, "## Safe Ranges (set by Tracend rules");
  }
  const { file } = renderCoachContextParts(ownerContext(), 96_000);
  assert(file.indexOf("## Safe Ranges") < file.indexOf("## Active Training Plan"));
});
