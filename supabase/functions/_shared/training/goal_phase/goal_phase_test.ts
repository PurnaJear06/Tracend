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
import { lateGoalInputs, lateGoalPayload, longCutInputs, longCutPayload } from "./fixtures.ts";
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
  assertStringIncludes(
    text,
    "latest weight 74.8 kg (median of the last 3 readings, up to 2026-10-13, 1 day ago)",
  );
  assertStringIncludes(text, "Excluded reading");
  assertStringIncludes(text, "60 kg on 2026-07-02");
  assertStringIncludes(text, "Review outcome: consider_maintenance_or_diet_break (no target set)");
  assertStringIncludes(text, "BMI 23.1 at the latest weight");
  assertStringIncludes(text, "Target: none set");
  assert(!text.includes("86.2"), "the stale goal weight never reaches the phase summary");
});

Deno.test("goal activated a month into the cut: the history is 90 to 74.8 kg, the phase is shorter", () => {
  const summary = summarizeGoalPhase(lateGoalInputs);
  assertEquals(summary.phaseStart, "2026-07-03");
  assertEquals(summary.startWeightKg, 83);
  assertEquals(summary.firstReadingDate, "2026-07-09");
  assertEquals(summary.changeKg, -8.2);
  assertEquals(summary.changePct, -9.9);
  assertEquals(summary.weeks, 13.7);
  assertEquals(summary.history, {
    startDate: "2026-06-03",
    startWeightKg: 90,
    changeKg: -15.2,
    changePct: -16.9,
    weeks: 18.9,
    readingsUsed: lateGoalInputs.readings.length - 1,
    sparse: false,
    capped: false,
  });
  assertEquals(summary.continuousLoss?.startDate, "2026-06-03");
  assertEquals(summary.continuousLoss?.beganBeforeGoalPhase, true);
  assertEquals(summary.continuousLoss?.weeks, 18.9);
  // The implausible reading is out of the history as well as the phase.
  assertEquals(summary.excluded.map((e) => e.date), ["2026-07-02"]);
  const review = reviewGoalPhase(summary);
  assertEquals(review.outcome, "consider_maintenance_or_diet_break");
  assertEquals(review.reasons.map((r) => r.code), ["long_continuous_deficit", "large_total_loss"]);
  assertStringIncludes(review.reasons[0].detail, "18.9 weeks of falling weight since 2026-06-03");
  // Judged on the goal window alone (13.7 weeks, -9.9%), neither rule would fire.
  assertEquals(
    reviewGoalPhase({ ...summary, continuousLoss: null }).outcome,
    "ask_target",
  );
});

Deno.test("goal activated a month into the cut: Coach sees the history beside the goal phase", () => {
  const summary = summarizeGoalPhase(parseGoalPhaseInputs(lateGoalPayload, "2026-10-14"));
  const text = renderGoalPhase(summary, reviewGoalPhase(summary))!;
  assertStringIncludes(
    text,
    "Recorded history, all weight readings: 90 kg on 2026-06-03 (median of the first readings) " +
      "to latest weight 74.8 kg (median of the last 3 readings, up to 2026-10-13, 1 day ago): " +
      "-15.2 kg (-16.9%) over 18.9 weeks",
  );
  assertStringIncludes(text, "one continuous loss");
  assertStringIncludes(text, "Goal phase (fat loss, since 2026-07-03): Start 83 kg (2026-07-09");
  assertStringIncludes(text, "-8.2 kg (-9.9%) over 13.7 weeks");
  assertStringIncludes(text, "18.9 weeks of falling weight since 2026-06-03");
  assert(text.indexOf("Recorded history") < text.indexOf("Goal phase (fat loss"));
});

Deno.test("history equal to the goal phase adds no second line", () => {
  const summary = summarizeGoalPhase(longCutInputs);
  assertEquals(summary.history, null);
  assertEquals(summary.continuousLoss, null);
  const text = renderGoalPhase(summary, reviewGoalPhase(summary))!;
  assert(!text.includes("Recorded history"));
  assert(!text.includes("Continuous loss"));
  assert(!text.includes("Goal phase ("));
  // A first reading a few days before the goal says nothing the phase does not.
  const near = summarizeGoalPhase(inputs({
    readings: [{ date: "2026-09-04", kg: 82 }, ...weekly("2026-09-08", [81.8, 81.6, 81.5, 81.3])],
    activatedOn: "2026-09-06",
  }));
  assertEquals(near.history, null);
});

Deno.test("one reading before the goal still gives a history; none gives none", () => {
  const one = summarizeGoalPhase(inputs({
    readings: [{ date: "2026-08-20", kg: 85 }, ...weekly("2026-09-01", [84, 83.5, 83, 82.6, 82.2])],
    activatedOn: "2026-09-01",
  }));
  assertEquals(one.history?.startDate, "2026-08-20");
  assertEquals(one.history?.startWeightKg, 85);
  assertEquals(one.history?.readingsUsed, 6);
  assertEquals(one.history?.changeKg, -2.8);
  assertEquals(one.phaseStart, "2026-09-01");
  assertEquals(one.startWeightKg, 84);
  const none = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [84, 83.5, 83, 82.6, 82.2]),
    activatedOn: "2026-09-01",
  }));
  assertEquals(none.history, null);
  // Only readings before the goal: no phase, so no history or run is claimed.
  const before = summarizeGoalPhase(inputs({
    readings: weekly("2026-07-01", [85, 84, 83]),
    activatedOn: "2026-09-01",
  }));
  assertEquals(before.history, null);
  assertEquals(before.continuousLoss, null);
});

Deno.test("a flat stretch before the goal is history, not a loss that began earlier", () => {
  const summary = summarizeGoalPhase(inputs({
    readings: [
      ...weekly("2026-06-01", [86.3, 86, 86.4, 86.1, 86.2, 86.3]),
      ...weekly("2026-07-13", [86, 85, 84, 83, 82, 81, 80, 79, 78]),
    ],
    activatedOn: "2026-07-13",
    today: "2026-09-08",
  }));
  assertEquals(summary.history?.startDate, "2026-06-01");
  assertEquals(summary.continuousLoss, null);
  assertEquals(summary.weeks, 8);
});

Deno.test("weight rose, then fell: the continuous loss starts at the high point", () => {
  const readings = [
    ...weekly("2026-01-05", [70, 71.5, 73, 74.5, 76, 77.5, 79, 80]),
    ...weekly("2026-03-02", [79, 78, 77, 76, 75, 74, 73, 72, 71, 70.5, 70, 69.5]),
    ...weekly("2026-05-18", [69, 68.5, 68, 67.5, 67, 66.5, 66]),
  ];
  // The goal was activated at the first reading: its window holds the rise and the fall.
  const during = summarizeGoalPhase(inputs({
    readings,
    activatedOn: "2026-01-05",
    today: "2026-06-30",
  }));
  assertEquals(during.history, null);
  assertEquals(during.startWeightKg, 70);
  assertEquals(during.weeks, 25);
  assertEquals(during.continuousLoss, {
    startDate: "2026-02-23",
    startWeightKg: 80,
    changeKg: -14,
    changePct: -17.5,
    weeks: 18,
    weeklyRateKg: -0.78,
    confirmed: true,
    beganBeforeGoalPhase: false,
  });
  const review = reviewGoalPhase(during);
  assertEquals(review.reasons.map((r) => r.code), ["long_continuous_deficit", "large_total_loss"]);
  assertStringIncludes(review.reasons[0].detail, "18 weeks of falling weight since 2026-02-23");
  const text = renderGoalPhase(during, review)!;
  assertStringIncludes(
    text,
    "Continuous loss: from the high of 80 kg on 2026-02-23 to latest weight 66 kg (reading on 2026-06-29, 1 day ago): -14 kg (-17.5%) over 18 " +
      "weeks; the weight rose before it fell.",
  );
  assert(!text.includes("Recorded history"));

  // The goal was activated after the high point: the run began before the goal phase.
  const after = summarizeGoalPhase(inputs({
    readings,
    activatedOn: "2026-04-13",
    today: "2026-06-30",
  }));
  assertEquals(after.history?.startDate, "2026-01-05");
  assertEquals(after.history?.startWeightKg, 70);
  assertEquals(after.history?.changeKg, -4);
  assertEquals(after.continuousLoss?.startDate, "2026-02-23");
  assertEquals(after.continuousLoss?.beganBeforeGoalPhase, true);
  assertEquals(after.startWeightKg, 73);
  const afterText = renderGoalPhase(after, reviewGoalPhase(after))!;
  assertStringIncludes(afterText, "Recorded history, all weight readings: 70 kg on 2026-01-05");
  assertStringIncludes(afterText, "Continuous loss: from the high of 80 kg on 2026-02-23");
  assert(!afterText.includes("rose before it fell"));
});

Deno.test("a small rebound does not end the run; a large one does", () => {
  const withBreak = (rebound: number) => [
    ...weekly("2026-01-05", [90, 88.5, 87, 85.5, 84, 82.5, 81]),
    ...weekly("2026-02-23", [
      81 + rebound / 2,
      81 + rebound,
      81 + rebound / 2,
      80,
      79,
      78,
      77,
      76,
      75,
      74,
    ]),
  ];
  const run = (rebound: number) =>
    summarizeGoalPhase(inputs({
      readings: withBreak(rebound),
      activatedOn: "2026-01-05",
      today: "2026-05-04",
    }));
  // A 2 kg (2.4%) diet-break rise keeps one run from 90 kg: it is the whole goal phase.
  assertEquals(run(2).continuousLoss, null);
  assertEquals(run(2).startWeightKg, 90);
  // A 4 kg (4.9%) rebound ends it: the run starts at the top of the rebound.
  const large = run(4);
  assertEquals(large.continuousLoss?.startDate, "2026-03-02");
  assertEquals(large.continuousLoss?.startWeightKg, 85);
  assertEquals(large.continuousLoss?.beganBeforeGoalPhase, false);
});

Deno.test("a newly activated goal still shows the whole history, before it has a rate", () => {
  // Two readings in the first days of the goal: under two weeks, so no phase rate.
  const days = summarizeGoalPhase({ ...lateGoalInputs, activatedOn: "2026-10-10" });
  assertEquals(days.weeks, null);
  assertEquals(days.weeklyRateKg, null);
  assertEquals(days.history?.startDate, "2026-06-03");
  assertEquals(days.history?.startWeightKg, 90);
  assertEquals(days.history?.changeKg, -15.2);
  assertEquals(days.continuousLoss?.startDate, "2026-06-03");
  // One reading since the goal began: the same.
  const one = summarizeGoalPhase({ ...lateGoalInputs, activatedOn: "2026-10-12" });
  assertEquals(one.readingsUsed, 1);
  assertEquals(one.changeKg, null);
  assertEquals(one.history?.changePct, -16.9);
  const text = renderGoalPhase(one, reviewGoalPhase(one))!;
  assertStringIncludes(text, "Recorded history, all weight readings: 90 kg on 2026-06-03");
  // The 19-week cut is judged even though the goal is days old.
  assertEquals(reviewGoalPhase(one).outcome, "consider_maintenance_or_diet_break");
});

Deno.test("sparse readings: the pace of a later run, not the whole phase, says it is still falling", () => {
  // Up 15 kg over 15 weeks, then down every 4 weeks to 76.6 kg; the phase as a whole rose.
  const gain = weekly("2026-01-05", [
    70,
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
    82,
    83,
    84,
    85,
  ]);
  const cut = [83.8, 82.6, 81.4, 80.2, 79, 77.8, 76.6].map((kg, index) => ({
    date: new Date(Date.parse("2026-05-18T00:00:00Z") + index * 28 * 86_400_000)
      .toISOString().slice(0, 10),
    kg,
  }));
  const summary = summarizeGoalPhase(inputs({
    readings: [...gain, ...cut],
    activatedOn: "2026-01-05",
    today: "2026-10-31",
  }));
  assertEquals(summary.recentRateKgPerWeek, null);
  assert(summary.weeklyRateKg! > 0, "the phase as a whole rose");
  assertEquals(summary.continuousLoss?.startDate, "2026-04-20");
  assertEquals(summary.continuousLoss?.startWeightKg, 85);
  assertEquals(summary.continuousLoss?.weeks, 28);
  assertEquals(summary.continuousLoss?.weeklyRateKg, -0.3);
  const review = reviewGoalPhase(summary);
  assertEquals(review.outcome, "consider_maintenance_or_diet_break");
  assertEquals(review.reasons.map((r) => r.code), ["long_continuous_deficit"]);
});

Deno.test("a goal that predates the first reading names the first reading as the start", () => {
  const summary = summarizeGoalPhase(inputs({ activatedOn: "2025-01-01" }));
  assertEquals(summary.phaseStart, "2025-01-01");
  assertEquals(summary.firstReadingDate, "2026-06-03");
  assertEquals(summary.continuousLoss, null);
  const review = reviewGoalPhase(summary);
  assertEquals(review.outcome, "consider_maintenance_or_diet_break");
  for (const reason of review.reasons) {
    assertStringIncludes(reason.detail, "since 2026-06-03");
    assert(!reason.detail.includes("2025-01-01"), reason.detail);
  }
});

Deno.test("two sparse weights months apart are shown, but never drive the review", () => {
  const summary = summarizeGoalPhase(inputs({
    readings: [
      { date: "2026-01-05", kg: 90 },
      { date: "2026-10-05", kg: 75.2 },
      { date: "2026-10-12", kg: 75 },
    ],
    activatedOn: "2026-10-01",
    today: "2026-10-14",
  }));
  assertEquals(summary.history?.sparse, true);
  assertEquals(summary.history?.weeks, 40);
  assertEquals(summary.continuousLoss?.confirmed, false);
  const review = reviewGoalPhase(summary);
  assertEquals(review.outcome, "ask_target");
  const text = renderGoalPhase(summary, review)!;
  assertStringIncludes(text, "Recorded history, all weight readings: 90 kg on 2026-01-05");
  assertStringIncludes(text, "sparse readings, trend not confirmed");
  assert(!text.includes("one continuous loss"));
});

Deno.test("a gap of more than five weeks inside the run leaves it unconfirmed", () => {
  const readings = [
    ...weekly("2026-01-05", [90, 89, 88, 87, 86, 85]),
    ...weekly("2026-04-20", [79, 78, 77, 76]),
  ];
  const summary = summarizeGoalPhase(inputs({
    readings,
    activatedOn: "2026-04-20",
    today: "2026-05-14",
  }));
  assertEquals(summary.continuousLoss?.startDate, "2026-01-05");
  assertEquals(summary.continuousLoss?.confirmed, false);
  assertEquals(summary.history?.sparse, true);
  assert(reviewGoalPhase(summary).outcome !== "consider_maintenance_or_diet_break");
  // The same weights without the gap are confirmed and do drive the review.
  const dense = summarizeGoalPhase(inputs({
    readings: weekly("2026-01-05", [
      90,
      89,
      88,
      87,
      86,
      85,
      84,
      83,
      82,
      81,
      80,
      79,
      78,
      77,
      76,
      75,
      74.5,
      74,
      73.5,
      73,
      72.5,
      72,
    ]),
    activatedOn: "2026-04-20",
    today: "2026-06-05",
  }));
  assertEquals(dense.continuousLoss?.confirmed, true);
  assertEquals(reviewGoalPhase(dense).outcome, "consider_maintenance_or_diet_break");
});

Deno.test("at the 400-reading cap the history is the newest window, not the whole journey", () => {
  const first = Date.parse("2025-09-01T00:00:00Z");
  const day = (index: number) => new Date(first + index * 86_400_000).toISOString().slice(0, 10);
  const readings = (count: number) =>
    Array.from({ length: count }, (_, index) => ({
      date: day(index),
      kg: Math.round((90 - index * 0.03) * 10) / 10,
    }));
  const capped = summarizeGoalPhase(inputs({
    readings: readings(400),
    activatedOn: "2026-08-01",
    today: "2026-10-05",
  }));
  assertEquals(capped.history?.capped, true);
  const text = renderGoalPhase(capped, reviewGoalPhase(capped))!;
  assertStringIncludes(
    text,
    "Recorded history, the newest 400 readings, from 2025-09-01 (older readings may exist)",
  );
  assert(!text.includes("all weight readings"));
  const whole = summarizeGoalPhase(inputs({
    readings: readings(399),
    activatedOn: "2026-08-01",
    today: "2026-10-04",
  }));
  assertEquals(whole.history?.capped, false);
  assertStringIncludes(renderGoalPhase(whole, reviewGoalPhase(whole))!, "all weight readings");
});

Deno.test("moving the activation date never changes the history or the run", () => {
  const at = (activatedOn: string) => summarizeGoalPhase({ ...lateGoalInputs, activatedOn });
  for (const [a, b] of [["2026-10-12", "2026-10-10"], ["2026-07-03", "2026-07-10"]]) {
    const one = at(a);
    const other = at(b);
    assertEquals(one.history, other.history);
    assertEquals(one.continuousLoss, other.continuousLoss);
    assertEquals(one.history?.changeKg, -15.2);
  }
});

Deno.test("a run's average pace is not evidence of losing now when the latest reading is stale", () => {
  const gain = weekly("2026-01-05", [70, 72, 74, 76, 78, 80, 82, 84, 85]);
  const cut = [83.8, 82.6, 81.4, 80.2, 79, 77.8, 76.6].map((kg, index) => ({
    date: new Date(Date.parse("2026-03-23T00:00:00Z") + index * 28 * 86_400_000)
      .toISOString().slice(0, 10),
    kg,
  }));
  const at = (today: string) =>
    summarizeGoalPhase(inputs({
      readings: [...gain, ...cut],
      activatedOn: "2026-01-05",
      today,
    }));
  const fresh = at("2026-09-14");
  assertEquals(fresh.continuousLoss?.confirmed, true);
  assertEquals(fresh.recentRateKgPerWeek, null);
  assertEquals(reviewGoalPhase(fresh).outcome, "consider_maintenance_or_diet_break");
  const stale = at("2027-01-20");
  assertEquals(stale.latestReadingStale, true);
  assertEquals(reviewGoalPhase(stale).outcome, "ask_target");
});

Deno.test("every rendered change equals the rendered start minus the rendered current weight", () => {
  const cases: GoalPhaseInputs[] = [
    lateGoalInputs,
    longCutInputs,
    { ...lateGoalInputs, activatedOn: "2026-10-12" },
    { ...lateGoalInputs, activatedOn: "2026-10-10" },
    { ...lateGoalInputs, activatedOn: "2026-09-02" },
  ];
  let checked = 0;
  for (const input of cases) {
    const summary = summarizeGoalPhase(input);
    const text = renderGoalPhase(summary, reviewGoalPhase(summary))!;
    for (const line of text.split("\n")) {
      const match = line.match(
        /^- .*?(\d+(?:\.\d+)?) kg (?:on|\().*? to latest weight (\d+(?:\.\d+)?) kg[^:]*: ([+-]?\d+(?:\.\d+)?) kg/,
      );
      if (!match) continue;
      const [start, current, change] = [match[1], match[2], match[3]].map(Number);
      assertEquals(Math.round((current - start) * 10) / 10, change, line);
      assertEquals(current, summary.currentWeightKg, line);
      checked++;
    }
  }
  assert(checked >= 6, `${checked} lines checked`);
});

Deno.test("a stale latest reading: no rate counts as losing now and the text never says now", () => {
  const rising = weekly("2026-01-05", [70, 72, 74, 76, 78, 80, 82, 84, 85]);
  const falling = weekly("2026-03-02", [
    84,
    83,
    82,
    81,
    80,
    79,
    78,
    77,
    76,
    75,
    74,
    73,
    72,
    71,
    70,
  ]);
  const cases: GoalPhaseInputs[] = [
    // The owner's cut, reviewed three months after the last weigh-in.
    { ...lateGoalInputs, today: "2027-01-20" },
    { ...longCutInputs, today: "2027-01-20" },
    // Gain then cut, and a fast loss: both rate-driven when fresh.
    inputs({ readings: [...rising, ...falling], activatedOn: "2026-01-05", today: "2026-08-01" }),
    inputs({
      readings: weekly("2026-09-08", [85, 83.9, 82.8, 81.6, 80.5, 79.4]),
      activatedOn: "2026-09-08",
      today: "2026-11-10",
      target: { ...longCutInputs.target, weightKg: 70 },
    }),
    // A BMI near the floor and still falling when fresh.
    inputs({
      readings: weekly("2026-09-01", [62, 61.5, 61, 60.5, 60]),
      activatedOn: "2026-09-01",
      today: "2026-10-14",
      target: { ...longCutInputs.target, weightKg: 55 },
    }),
  ];
  for (const input of cases) {
    const summary = summarizeGoalPhase(input);
    assertEquals(summary.latestReadingStale, true);
    const review = reviewGoalPhase(summary);
    const rateCodes = [
      "long_continuous_deficit",
      "large_total_loss",
      "bmi_near_healthy_floor",
      "fast_sustained_loss",
    ];
    for (const reason of review.reasons) assert(!rateCodes.includes(reason.code), reason.code);
    assert(review.outcome !== "slow_down");
    const text = renderGoalPhase(summary, review)!;
    assert(!/\b(now|current|currently)\b/i.test(text), text);
    assertStringIncludes(text, "latest weight");
    assertStringIncludes(text, "days ago");
  }
  // Absolute-state reasons still fire, labelled with the reading's date.
  const under = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [60, 59.5, 59, 58.5, 58]),
    activatedOn: "2026-09-01",
    today: "2026-12-01",
  }));
  const review = reviewGoalPhase(under);
  assertEquals(review.reasons.map((r) => r.code), ["bmi_below_healthy_range"]);
  assertStringIncludes(review.reasons[0].detail, "latest weight (reading on 2026-09-29)");
  const reached = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [82, 80, 78, 76.4, 76.3]),
    activatedOn: "2026-09-01",
    today: "2026-12-01",
    target: { ...longCutInputs.target, weightKg: 76 },
  }));
  const done = reviewGoalPhase(reached);
  assertEquals(done.outcome, "target_reached");
  assertStringIncludes(done.reasons[0].detail, "76.3 kg (reading on 2026-09-29)");
});

Deno.test("the latest weight says what it is: a median of readings, or one reading", () => {
  const median = summarizeGoalPhase(longCutInputs);
  assertEquals(median.currentReadingsUsed, 3);
  assertStringIncludes(
    renderGoalPhase(median, reviewGoalPhase(median))!,
    "median of the last 3 readings, up to 2026-10-13",
  );
  const single = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [82, 81.8, 81.6, 81.5, 81.3]),
    activatedOn: "2026-09-01",
    today: "2026-09-30",
  }));
  assertEquals(single.currentReadingsUsed, 1);
  const text = renderGoalPhase(single, reviewGoalPhase(single))!;
  assertStringIncludes(text, "latest weight 81.3 kg (reading on 2026-09-29, 1 day ago)");
  assert(!text.includes("latest recorded weight"));
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
    today: "2026-09-30",
    target: { ...longCutInputs.target, weightKg: 55 },
  }));
  assertEquals(below.bmi, 18.5);
  // 60 kg at 180 cm is BMI 18.5, which is the floor, not below it, but near it and falling.
  assertEquals(reviewGoalPhase(below).reasons[0].code, "bmi_near_healthy_floor");
  const under = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [60, 59.5, 59, 58.5, 58]),
    activatedOn: "2026-09-01",
    today: "2026-09-30",
    target: { ...longCutInputs.target, weightKg: 55 },
  }));
  assertEquals(reviewGoalPhase(under).reasons[0].code, "bmi_below_healthy_range");
  assertEquals(reviewGoalPhase(under).outcome, "consider_maintenance_or_diet_break");
  // Already stable near the floor: nothing to review.
  const holding = summarizeGoalPhase(inputs({
    readings: weekly("2026-09-01", [62, 62, 62.1, 62, 62]),
    activatedOn: "2026-09-01",
    today: "2026-09-30",
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
