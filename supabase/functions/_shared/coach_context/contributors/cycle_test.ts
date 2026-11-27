// The cycle contributor over the coach_cycle_state_v1 answer (PR 1's contract fixtures), and the
// promise that matters most: under a notice that does not name cycle data, nothing is read and the
// turn is exactly what it was before cycle support.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import regularFixture from "../../../../../test/contract/fixtures/my_cycle_v1_0_regular.json" with {
  type: "json",
};
import offFixture from "../../../../../test/contract/fixtures/my_cycle_v1_0_off.json" with {
  type: "json",
};
import lateFixture from "../../../../../test/contract/fixtures/my_cycle_v1_0_late.json" with {
  type: "json",
};
import contraceptionFixture from "../../../../../test/contract/fixtures/my_cycle_v1_0_contraception.json" with {
  type: "json",
};
import type { NoticeScope } from "../../ai_notice_coverage.ts";
import { noticeScopes } from "../../ai_notice_coverage.ts";
import { type CoachContextInput, noCoachContributions, renderCoachContext } from "../host.ts";
import { splitPlanPayload } from "./plan_fixtures.ts";
import {
  createCycleContributor,
  cycleBudgetChars,
  cycleContributorId,
  cycleExplainsDrift,
  cycleLongGapIn,
  parseCycleState,
  renderCycle,
} from "./cycle.ts";
import { createWatchOutsContributor } from "./watch_outs.ts";

const today = "2026-11-27";
const open: ReadonlySet<NoticeScope> = noticeScopes("ai-coaching-v7");
const input = (scopes?: ReadonlySet<NoticeScope>): CoachContextInput => ({
  userId: "u",
  question: "Why is my recovery low this week?",
  localDate: today,
  ...(scopes ? { noticeScopes: scopes } : {}),
});

type Json = Record<string, unknown>;
const answer = (patch: Json = {}, state: Json = {}): Json => ({
  ...structuredClone(regularFixture),
  ...patch,
  state: { ...regularFixture.state, ...state },
});

function countingSource(payload: unknown) {
  const calls: string[][] = [];
  const source = (userId: string, localDate: string) => {
    calls.push([userId, localDate]);
    return Promise.resolve(payload);
  };
  return { calls, source };
}

Deno.test("PR 1's fixtures parse: regular, off and hormonal contraception", () => {
  const regular = parseCycleState(regularFixture)!;
  assertEquals(regular.status, "regular");
  assertEquals(regular.phase, "second_half");
  assertEquals(regular.cycleDay, 18);
  assertEquals(regular.cycles.length, 3);
  assertEquals(regular.recentDays[4], {
    date: "2026-11-10",
    flow: "medium",
    cramps: "mild",
    isStart: true,
    source: "manual",
  });
  const off = parseCycleState(offFixture)!;
  assertEquals([off.trackingEnabled, off.status], [false, null]);
  const pill = parseCycleState(contraceptionFixture)!;
  assertEquals([pill.status, pill.periodDay, pill.weightWaterWindow], [
    "hormonal_contraception",
    2,
    true,
  ]);
});

Deno.test("an answer this code cannot read is unreadable, never 'tracking off'", () => {
  for (
    const payload of [
      null,
      {},
      answer({ schema_version: "2.0" }),
      answer({ status: "perimenopause" }),
      answer({}, { phase: "luteal" }),
      answer({}, { confidence: "certain" }),
      answer({}, { cycle_day: "18" }),
      answer({}, { no_period_long: null }),
      answer({}, { expected_from: "8 Dec" }),
      answer({ tracking_enabled: "yes" }),
      answer({ tracking_enabled: true, status: null }),
      answer({ recent_days: [{ local_date: "2026-11-10", flow: "gushing", is_start: false }] }),
      answer({ recent_days: null }),
      answer({ cycles: [{ length_days: 28, used: true }] }),
    ]
  ) {
    assertEquals(parseCycleState(payload), null, JSON.stringify(payload).slice(0, 80));
  }
});

Deno.test("without the cycle_data scope nothing is read and nothing renders", async () => {
  for (
    const scopes of [
      undefined,
      new Set<NoticeScope>(),
      noticeScopes("ai-coaching-v6"),
      new Set<NoticeScope>(["breathing_rate", "workout_notes"]),
    ]
  ) {
    const { calls, source } = countingSource(regularFixture);
    const rendered = await createCycleContributor(source).render(input(scopes));
    assertEquals(rendered, null);
    assertEquals(calls, []);
  }
});

Deno.test("with the scope and tracking off, or after the athlete deleted her cycle data, nothing renders", async () => {
  const { calls, source } = countingSource(offFixture);
  const rendered = await createCycleContributor(source).render(input(open));
  assert(typeof rendered === "object" && rendered !== null);
  assertEquals(rendered.text, "");
  assertEquals(rendered.trace, { cycle: "ok" });
  assertEquals(calls, [["u", today]]);
  const result = await renderCoachContext([createCycleContributor(source)], input(open));
  assertEquals(result.volatile, "");
  assertEquals(result.outcomes[0].outcome, "empty");
});

Deno.test("a regular cycle in its second half: status, day, phase, range, lengths, days and the rules", async () => {
  const { source } = countingSource(regularFixture);
  const rendered = await createCycleContributor(source).render(input(open));
  assert(typeof rendered === "object" && rendered !== null);
  const text = rendered.text;
  for (
    const line of [
      "Status: regular periods.",
      "Long gap without a period: no",
      "Today (2026-11-27): cycle day 18, second half of the cycle (confidence medium).",
      "Next period expected 2026-12-06 to 2026-12-10.",
      "Typical cycle length: 28 days (from the logged cycles).",
      "Recent cycle lengths, oldest first: 28 days, 28 days.",
    ]
  ) assertStringIncludes(text, line);
  assertStringIncludes(
    text,
    "The evidence does not support changing training or food by cycle phase",
  );
  assertStringIncludes(
    text,
    "resting heart rate often runs a little higher and HRV a little lower",
  );
  assertStringIncludes(text, "Never estimate fertile days, ovulation or the chance of pregnancy");
  assertStringIncludes(text, "worth seeing a doctor about");
  assert(!text.includes("Rule: no period logged"));
  assert(!text.includes("Weight-water window"));
  assertEquals(rendered.trace, { cycle: "ok" });
  // The values are records: the dates, the cycle day, the typical and recent lengths.
  // The fixture holds the app's 60 days; only the last 14 to the coaching date are listed.
  assert(!text.includes("Logged days"), "no day of the fixture falls in the 14 days to 2026-11-27");
  for (const value of ["2026-11-27", "18", "2026-12-06", "2026-12-10", "28 days"]) {
    assert((rendered.records ?? []).some((piece) => piece.includes(value)), value);
  }
});

Deno.test("a late period: the day, how late, the range that passed, and only the last 14 days", () => {
  const late = renderCycle(parseCycleState(lateFixture), today)!;
  assertStringIncludes(
    late,
    "Today (2026-11-27): cycle day 35; the period is 4 days later than the expected range, so Tracend gives no phase (confidence medium).",
  );
  assertStringIncludes(late, "The expected range was 2026-11-19 to 2026-11-23.");
  assert(!late.includes("Next period expected"));
  assert(!late.includes("Logged days"), "the logged days are all older than 14 days");
  const recent = renderCycle(parseCycleState(lateFixture), "2026-11-05")!;
  assertStringIncludes(
    recent,
    "Logged days in the last 14, oldest first: 2026-10-24 medium flow, start; 2026-10-25 heavy flow; 2026-10-26 medium flow; 2026-10-27 light flow.",
  );
  assert(!recent.includes("2026-09-29"));
});

Deno.test("each status says what Tracend shows for it", () => {
  const pill = renderCycle(parseCycleState(contraceptionFixture), today)!;
  assertStringIncludes(pill, "Status: hormonal contraception (pill, implant");
  assertStringIncludes(pill, "no cycle day, phase or prediction on hormonal contraception");
  assertStringIncludes(pill, "Today (2026-11-27): bleed day 2.");
  assertStringIncludes(pill, "Weight-water window: yes.");
  assertStringIncludes(pill, "2026-11-26 light flow; 2026-11-27 light flow");
  assert(!pill.includes("second half of a natural cycle"));
  const none = renderCycle(
    parseCycleState(answer({ status: "no_periods", recent_days: [], cycles: [] }, {
      cycle_day: null,
      phase: null,
      confidence: null,
      expected_from: null,
      expected_to: null,
    })),
    today,
  )!;
  assertStringIncludes(none, "Status: no periods at the moment.");
  assertStringIncludes(none, "do not ask about periods");
  assert(!none.includes("Period pain"));
  assert(!none.includes("Logged days"));
  const irregular = renderCycle(
    parseCycleState(answer({ status: "irregular" }, {
      phase: null,
      confidence: "low",
      expected_from: null,
      expected_to: null,
    })),
    today,
  )!;
  assertStringIncludes(irregular, "cycle day 18; Tracend gives no phase for irregular");
  assertStringIncludes(irregular, "No expected date for the next period");
  const late = renderCycle(
    parseCycleState(answer({}, { cycle_day: 40, phase: null, late_days: 4 })),
    today,
  )!;
  assertStringIncludes(late, "the period is 4 days later than the expected range");
  const oneDay = renderCycle(
    parseCycleState(answer({}, { cycle_day: 30, phase: null, late_days: 1 })),
    today,
  )!;
  assertStringIncludes(oneDay, "the period is 1 day later than the expected range");
  const period = renderCycle(
    parseCycleState(answer({}, { cycle_day: 2, period_day: 2, phase: "period" })),
    today,
  )!;
  assertStringIncludes(period, "cycle day 2, period day 2");
  const rough = renderCycle(parseCycleState(answer({}, { confidence: "low" })), today)!;
  assertStringIncludes(rough, "say it is a rough estimate");
});

Deno.test("a long gap without a period is a rule for Coach and a line the reply guard reads", async () => {
  for (const [status, months] of [["regular", "3"], ["irregular", "6"]]) {
    const { source } = countingSource(answer({ status }, { no_period_long: true }));
    const result = await renderCoachContext([createCycleContributor(source)], input(open));
    const text = result.texts[cycleContributorId];
    assertStringIncludes(text, "Long gap without a period: yes");
    assertStringIncludes(text, `no period logged for ${months} months or more`);
    assertStringIncludes(text, "keep calories at maintenance or above");
    assert(cycleLongGapIn(result));
  }
  const { source } = countingSource(regularFixture);
  const quiet = await renderCoachContext([createCycleContributor(source)], input(open));
  assertEquals(cycleLongGapIn(quiet), false);
  assertEquals(cycleLongGapIn(null), false);
  assertEquals(cycleLongGapIn(noCoachContributions), false);
  // Another block, or the athlete's words, cannot raise it: only the cycle block's own line counts.
  assertEquals(
    cycleLongGapIn({
      ...noCoachContributions,
      texts: { coach_notes: "Long gap without a period: yes" },
    }),
    false,
  );
});

Deno.test("a read that fails, times out or answers something unreadable renders nothing and says so in the trace", async () => {
  const cases: [() => Promise<unknown>, string][] = [
    [() => Promise.reject(new Error("down")), "failed"],
    [() => new Promise((resolve) => setTimeout(resolve, 100, regularFixture)), "timeout"],
    [() => Promise.resolve(null), "unavailable"],
    [() => Promise.resolve(answer({ status: "unknown" })), "unavailable"],
  ];
  for (const [read, status] of cases) {
    const rendered = await createCycleContributor(read, 20).render(input(open));
    assert(typeof rendered === "object" && rendered !== null);
    assertEquals([rendered.text, rendered.trace], ["", { cycle: status }]);
  }
});

Deno.test("the largest block fits well inside its budget, so the host never cuts a rule", () => {
  const days = Array.from({ length: 14 }, (_, index) => ({
    local_date: `2026-11-${String(14 + index).padStart(2, "0")}`,
    flow: "unspecified",
    cramps: "strong",
    is_start: index === 0,
    source: "apple_health",
  }));
  const cycles = Array.from({ length: 7 }, (_, index) => ({
    start_date: `2026-0${index + 3}-01`,
    length_days: index === 6 ? null : 60,
    used: index % 2 === 0 && index !== 6,
  }));
  const text = renderCycle(
    parseCycleState(answer({ status: "irregular", recent_days: days, cycles }, {
      cycle_day: 60,
      phase: null,
      late_days: 30,
      confidence: "low",
      no_period_long: true,
      weight_water_window: true,
    })),
    today,
  )!;
  assert(text.length <= cycleBudgetChars * 0.9, `${text.length}`);
  // The rules come before the days, so a cut could only shorten the list of days.
  assert(text.indexOf("Never estimate") < text.indexOf("Logged days"));
});

Deno.test("the watch-outs and the cycle block read the cycle state once for the turn", async () => {
  const { calls, source } = countingSource(regularFixture);
  await renderCoachContext([
    createCycleContributor(source),
    createWatchOutsContributor({
      planState: () => Promise.resolve(null),
      facts: () => Promise.resolve(null),
      schedule: () => Promise.resolve(null),
      cycle: source,
    }),
  ], input(open));
  assertEquals(calls.length, 1);
});

Deno.test("only the second half of a regular cycle at medium or high confidence explains a drift", () => {
  assert(cycleExplainsDrift(parseCycleState(regularFixture)));
  assert(cycleExplainsDrift(parseCycleState(answer({}, { confidence: "high" }))));
  for (
    const state of [
      answer({}, { confidence: "low" }),
      answer({}, { phase: "first_half" }),
      answer({}, { phase: "period", period_day: 1 }),
      answer({ status: "irregular" }),
      answer({ tracking_enabled: false }),
    ]
  ) assert(!cycleExplainsDrift(parseCycleState(state)), JSON.stringify(state.state));
  assert(!cycleExplainsDrift(null));
});

// ---- the turn is unchanged under the live notice ------------------------------------------------

const watchFacts = {
  schema_version: "1.0",
  local_date: today,
  sleep: { local_date: today, minutes: 400 },
  metrics: {
    local_date: today,
    recovery_score: 52,
    sleep_quality_score: 70,
    hrv_z: -1.4,
    rhr_z: -1.2,
    missing_components: [],
  },
  check_in: null,
  pain_flags: [],
  skipped: [],
  weigh_in: { local_date: today },
  health_sync: { at: "2026-11-27T06:00:00Z", local_date: today },
  as_of: "2026-11-27T07:00:00Z",
  plan: null,
};

function turnContributors(withCycle: boolean, metrics: Json = {}) {
  const { source } = countingSource(regularFixture);
  const facts = { ...watchFacts, metrics: { ...watchFacts.metrics, ...metrics } };
  const watch = createWatchOutsContributor({
    planState: () => Promise.resolve(splitPlanPayload(3, [])),
    facts: () => Promise.resolve(facts),
    schedule: () => Promise.resolve(null),
    ...(withCycle ? { cycle: source } : {}),
  });
  return withCycle ? [createCycleContributor(source), watch] : [watch];
}

Deno.test("a v6 athlete with cycle data gets no cycle block, no withheld line and the same watch-outs", async () => {
  const before = await renderCoachContext(turnContributors(false), input());
  for (const scopes of [undefined, noticeScopes("ai-coaching-v6")]) {
    const after = await renderCoachContext(turnContributors(true), input(scopes));
    assertEquals(after.stable, before.stable);
    assertEquals(after.volatile, before.volatile);
    assertEquals(after.texts, before.texts);
    assertEquals(after.records, before.records);
    assert(!/cycle|period|withheld/i.test(after.volatile), after.volatile);
    assertEquals(cycleLongGapIn(after), false);
  }
  // The drift is a watch-out, as before cycle support.
  assertStringIncludes(before.volatile, "resting heart rate is 1.2 spreads above their usual");
  assertStringIncludes(before.volatile, "HRV is 1.4 spreads below their usual");
});

Deno.test("under v7, a mild drift in the second half of her cycle is stated as expected, not a watch-out", async () => {
  const after = await renderCoachContext(turnContributors(true), input(open));
  const watch = after.texts.watch_outs;
  assertStringIncludes(
    watch,
    "resting heart rate is 1.2 spreads above their usual and HRV is 1.4 spreads below their usual: within what the second half of a natural cycle often brings (see the cycle block), so expected, not a watch-out by itself.",
  );
  assert(!watch.includes("(the recovery score's z-scores"));
  assertStringIncludes(after.texts.cycle, "second half of the cycle");
  // Two spreads or more stays a watch-out, in the second half too.
  const far = await renderCoachContext(
    turnContributors(true, { hrv_z: -2.3, rhr_z: -1.2 }),
    input(open),
  );
  assertStringIncludes(
    far.texts.watch_outs,
    "HRV is 2.3 spreads below their usual (the recovery score's z-scores",
  );
  assertStringIncludes(
    far.texts.watch_outs,
    "resting heart rate is 1.2 spreads above their usual: within what the second half",
  );
  assert(!/HRV is 2\.3[^\n]*second half/.test(far.texts.watch_outs));
  // The trace counts the line as data, not as a decision.
  const before = await renderCoachContext(turnContributors(false), input());
  assertEquals(
    after.traces?.watch_outs?.decisions,
    (before.traces?.watch_outs?.decisions as number) - 1,
  );
});
