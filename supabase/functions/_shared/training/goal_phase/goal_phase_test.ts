import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  bmiOf,
  findImplausibleReadings,
  goalPhaseSources,
  goalPhaseThresholds,
  healthyFloorWeightKg,
  parseGoalPhaseInputs,
  renderGoalPhase,
  reviewGoalPhase,
  summarizeGoalPhase,
} from "./index.ts";
import { longCutInputs, longCutPayload } from "./fixtures.ts";
import type { GoalPhaseInputs, WeightReading } from "./types.ts";

function weekly(start: string, kgs: readonly number[]): WeightReading[] {
  const first = Date.parse(`${start}T00:00:00Z`);
  return kgs.map((kg, index) => ({
    date: new Date(first + index * 7 * 86_400_000).toISOString().slice(0, 10),
    kg,
  }));
}

function inputs(overrides: Partial<GoalPhaseInputs>): GoalPhaseInputs {
  return { ...longCutInputs, ...overrides };
}

Deno.test("the owner's case: 90.0 to 74.8 kg is -15.2 kg and -16.9%, the 60 kg reading excluded", () => {
  const summary = summarizeGoalPhase(longCutInputs);
  assertEquals(summary.startWeightKg, 90);
  assertEquals(summary.currentWeightKg, 74.8);
  assertEquals(summary.changeKg, -15.2);
  assertEquals(summary.changePct, -16.9);
  assertEquals(summary.weeks, 18.9);
  assertEquals(summary.weeklyRateKg, -0.81);
  assertEquals(summary.weeklyRatePct, -0.9);
  assertEquals(summary.bmi, 23.1);
  assertEquals(summary.phaseStart, "2026-06-01");
  assertEquals(summary.phaseStartSource, "goal_activation");
  assertEquals(summary.hasTarget, false);
  assertEquals(summary.excluded, [{ date: "2026-07-02", kg: 60, reason: "implausible_jump" }]);
  assertEquals(summary.readingsUsed, longCutInputs.readings.length - 1);
  assertEquals(summary.confidence, "high");
  const review = reviewGoalPhase(summary);
  assertEquals(review.outcome, "consider_maintenance_or_diet_break");
  assertEquals(review.needsTarget, true);
  assertEquals(review.reasons.map((r) => r.code), ["long_continuous_deficit", "large_total_loss"]);
});

Deno.test("the owner's case renders the totals, the exclusion and the outcome as reference data", () => {
  const payloadSummary = summarizeGoalPhase(parseGoalPhaseInputs(longCutPayload, "2026-10-14"));
  const text = renderGoalPhase(payloadSummary, reviewGoalPhase(payloadSummary))!;
  assertStringIncludes(text, "-15.2 kg (-16.9%)");
  assertStringIncludes(text, "Start 90 kg (2026-06-03");
  assertStringIncludes(text, "now 74.8 kg (2026-10-13");
  assertStringIncludes(text, "Excluded reading");
  assertStringIncludes(text, "60 kg on 2026-07-02");
  assertStringIncludes(text, "Review outcome: consider_maintenance_or_diet_break (no target set)");
  assertStringIncludes(text, "BMI now 23.1");
  assertStringIncludes(text, "Target: none set");
  assert(!text.includes("86.2"), "the stale goal weight never reaches the phase summary");
});

Deno.test("a lone implausible reading is excluded; two readings or a steady fall are not", () => {
  assertEquals(findImplausibleReadings(weekly("2026-01-01", [80, 79.5, 79])), []);
  assertEquals(findImplausibleReadings(weekly("2026-01-01", [80, 60])), []);
  assertEquals(
    findImplausibleReadings(weekly("2026-01-01", [80, 79.5, 120, 79])).map((e) => e.kg),
    [120],
  );
  // A typo at the newest end is judged against its one neighbour.
  assertEquals(
    findImplausibleReadings(weekly("2026-01-01", [80, 79.5, 79, 47.8])).map((e) => e.kg),
    [47.8],
  );
  // A fast but real fall over a long gap is not a jump.
  assertEquals(findImplausibleReadings(weekly("2026-01-01", [90, 87, 84, 81, 78])), []);
});

Deno.test("the goal's saved weight is never a start weight; missing data lowers confidence", () => {
  const none = summarizeGoalPhase(inputs({ readings: [] }));
  assertEquals(none.startWeightKg, null);
  assertEquals(none.currentWeightKg, null);
  assertEquals(none.confidence, "low");
  assert(none.notes.includes("no weight readings"));

  const one = summarizeGoalPhase(inputs({ readings: [{ date: "2026-10-12", kg: 75 }] }));
  assertEquals(one.changeKg, null);
  assertEquals(one.currentWeightKg, 75);
  assertEquals(one.confidence, "low");

  const before = summarizeGoalPhase(inputs({ readings: [{ date: "2026-05-01", kg: 90 }] }));
  assertEquals(before.currentWeightKg, null);
  assert(before.notes.includes("no weight reading on or after the goal began"));

  const unknown = summarizeGoalPhase(inputs({ activatedOn: null, heightCm: null }));
  assertEquals(unknown.phaseStartSource, "first_reading");
  assertEquals(unknown.bmi, null);
  assert(unknown.notes.some((n) => n.includes("activation date unknown")));
  assert(unknown.notes.includes("height unknown; BMI not calculated"));
  assertEquals(unknown.confidence, "medium");

  const stale = summarizeGoalPhase(inputs({ today: "2026-12-30" }));
  assertEquals(stale.confidence, "low");
  assert(stale.notes.some((n) => n.includes("older than 14 days")));
});

Deno.test("no goal means no review text", () => {
  const summary = summarizeGoalPhase(inputs({ goalType: null }));
  assertEquals(summary.hasGoal, false);
  assertEquals(renderGoalPhase(summary, reviewGoalPhase(summary)), null);
});

Deno.test("healthy BMI, fat loss and no target: ask for a target", () => {
  const summary = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [82, 81.8, 81.6, 81.5, 81.3]),
    activatedOn: "2026-09-01",
  }));
  const review = reviewGoalPhase(summary);
  assertEquals(review.outcome, "ask_target");
  assertEquals(review.needsTarget, true);
});

Deno.test("with a target set, a steady loss continues", () => {
  const summary = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [82, 81.8, 81.6, 81.5, 81.3]),
    activatedOn: "2026-09-01",
    target: { ...longCutInputs.target, weightKg: 76 },
  }));
  const review = reviewGoalPhase(summary);
  assertEquals(review.outcome, "continue");
  assertEquals(review.needsTarget, false);
});

Deno.test("the target is reached within the tolerance, for a loss and for a gain", () => {
  const loss = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [82, 80, 78, 76.4, 76.3]),
    activatedOn: "2026-09-01",
    target: { ...longCutInputs.target, weightKg: 76 },
  }));
  assertEquals(reviewGoalPhase(loss).outcome, "target_reached");
  const gain = summarizeGoalPhase(inputs({
    goalType: "muscle_gain",
    readings: weekly("2026-09-01", [70, 70.4, 70.8, 71.1, 71.4]),
    activatedOn: "2026-09-01",
    target: { ...longCutInputs.target, weightKg: 71.5 },
  }));
  assertEquals(reviewGoalPhase(gain).outcome, "target_reached");
});

Deno.test("a sustained loss above 1% of body weight a week is slow_down", () => {
  const summary = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-08", [85, 83.9, 82.8, 81.6, 80.5, 79.4]),
    activatedOn: "2026-09-08",
    target: { ...longCutInputs.target, weightKg: 70 },
  }));
  const review = reviewGoalPhase(summary);
  assertEquals(review.outcome, "slow_down");
  assertEquals(review.reasons[0].code, "fast_sustained_loss");
  // Two fast weeks are noise.
  const brief = summarizeGoalPhase(inputs({
    readings: weekly("2026-10-01", [85, 83.9, 82.8]),
    activatedOn: "2026-10-01",
    target: { ...longCutInputs.target, weightKg: 70 },
  }));
  assertEquals(reviewGoalPhase(brief).outcome, "continue");
});

Deno.test("a BMI below the healthy floor, or near it and still falling, is maintenance", () => {
  const below = summarizeGoalPhase(inputs({
    heightCm: 180,
    readings: weekly("2026-09-01", [62, 61.5, 61, 60.5, 60]),
    activatedOn: "2026-09-01",
    target: { ...longCutInputs.target, weightKg: 55 },
  }));
  assertEquals(below.bmi, 18.5);
  // 60 kg at 180 cm is BMI 18.5, which is the floor, not below it, but near it and falling.
  assertEquals(reviewGoalPhase(below).reasons[0].code, "bmi_near_healthy_floor");
  const under = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [60, 59.5, 59, 58.5, 58]),
    activatedOn: "2026-09-01",
    target: { ...longCutInputs.target, weightKg: 55 },
  }));
  assertEquals(reviewGoalPhase(under).reasons[0].code, "bmi_below_healthy_range");
  assertEquals(reviewGoalPhase(under).outcome, "consider_maintenance_or_diet_break");
  // Already stable near the floor: nothing to review.
  const holding = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [62, 62, 62.1, 62, 62]),
    activatedOn: "2026-09-01",
    target: { ...longCutInputs.target, weightKg: 62 },
  }));
  assertEquals(reviewGoalPhase(holding).outcome, "target_reached");
});

Deno.test("a long phase that has already levelled off is not a continuing deficit", () => {
  const readings = [
    ...weekly("2026-05-01", [90, 88, 86, 84, 82, 80, 78, 77, 76, 75.5, 75, 75, 75, 75.2, 75, 75]),
    ...weekly("2026-08-21", [75, 75.1, 75, 74.9, 75, 75]),
  ];
  const summary = summarizeGoalPhase(
    inputs({ readings, activatedOn: "2026-05-01", today: "2026-10-01" }),
  );
  assertEquals(summary.recentRateKgPerWeek !== null && summary.recentRateKgPerWeek > -0.1, true);
  assertEquals(reviewGoalPhase(summary).outcome, "ask_target");
});

Deno.test("BMI arithmetic and the floor weight", () => {
  assertEquals(bmiOf(74.8, 180), 23.1);
  assertEquals(healthyFloorWeightKg(180), 59.9);
  assertEquals(healthyFloorWeightKg(null), null);
  assertEquals(healthyFloorWeightKg(50), null);
});

Deno.test("every threshold names sources that exist, and in-house values say so", () => {
  for (const [name, item] of Object.entries(goalPhaseThresholds)) {
    assert(item.sources.length > 0, name);
    for (const id of item.sources) assert(id in goalPhaseSources, `${name}: ${id}`);
  }
  for (const item of Object.values(goalPhaseSources)) {
    if (item.id === "tracend_in_house") continue;
    assert(item.doi !== null && /^10\.\d{4,9}\//.test(item.doi), `${item.id} needs a DOI`);
  }
});

Deno.test("the payload parser reads only what is valid", () => {
  const parsed = parseGoalPhaseInputs({
    height_cm: "180",
    goal: {
      goal_type: "fat_loss",
      activated_on: "2026-06-01T05:00:00Z",
      target: { weight_kg: "72.5" },
    },
    readings: [
      { date: "2026-06-03", kg: 90 },
      { date: "not a date", kg: 80 },
      { date: "2026-06-04", kg: -3 },
      { date: "2026-06-05", kg: "x" },
      null,
    ],
  }, "2026-10-14");
  assertEquals(parsed.readings, [{ date: "2026-06-03", kg: 90 }]);
  assertEquals(parsed.heightCm, 180);
  assertEquals(parsed.activatedOn, "2026-06-01");
  assertEquals(parsed.target.weightKg, 72.5);
  assertEquals(parseGoalPhaseInputs(null, "2026-10-14").goalType, null);
  assertEquals(parseGoalPhaseInputs({ goal: null }, "2026-10-14").target.weightKg, null);
});
