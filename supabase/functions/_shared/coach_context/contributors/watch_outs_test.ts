import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import cases from "./stale_sync_cases.json" with { type: "json" };
import { goalPhaseThresholds } from "../../training/goal_phase/thresholds.ts";
import { evidenceCodeReference } from "../../providers/daily_decision_provider.ts";
import { renderCoachContext } from "../host.ts";
import { readScheduleBody } from "../../training/schedule/lookup_body.ts";
import { splitPlanPayload } from "./plan_fixtures.ts";
import { parsePlanState } from "./training_plan.ts";
import { createTrainingPlanContributor } from "./training_plan.ts";
import {
  computeWatchOuts,
  createWatchOutsContributor,
  missedLookbackDays,
  parseWatchFacts,
  renderWatchOuts,
  scheduleSourceFromRpc,
  type WatchOutInputs,
  watchOutsBudgetChars,
  watchOutsLinesMaxChars,
  watchOutsLinesRoom,
  watchOutsMaxLines,
  watchOutThresholds,
} from "./watch_outs.ts";

// Wednesday 2026-10-14 in the six-day split: Monday and Tuesday done, Pull and rear delts today,
// Chest volume and delts tomorrow.
const introductionLength = () => renderWatchOuts(everything())!.split("\n")[0].length;
const wednesday = "2026-10-14";
const midweek = () => parsePlanState(splitPlanPayload(3, ["w-chest-a", "w-legs-a"]))!;

const factsOf = (patch: Record<string, unknown> = {}) =>
  parseWatchFacts({
    schema_version: "1.0",
    local_date: wednesday,
    sleep: null,
    metrics: null,
    check_in: null,
    pain_flags: [],
    skipped: [],
    weigh_in: { local_date: "2026-10-12" },
    health_sync: { at: "2026-10-14T06:00:00Z", local_date: "2026-10-14" },
    as_of: "2026-10-14T09:00:00Z",
    plan: { version: 3, starts_on: "2026-09-16", block_weeks: 6, ends_on: null },
    ...patch,
  })!;

const metrics = (patch: Record<string, unknown> = {}) => ({
  local_date: wednesday,
  recovery_score: 72,
  sleep_quality_score: 81,
  hrv_z: 0.3,
  rhr_z: 0.1,
  missing_components: [],
  ...patch,
});

const linesOf = (inputs: Partial<WatchOutInputs>) =>
  computeWatchOuts({ plan: null, facts: null, schedule: null, ...inputs }).map((item) => item.line);

// A back-to-back pair: Thursday and Friday both train chest, triceps, front and side delts.
function backToBackPlan() {
  const payload = splitPlanPayload(3, ["w-chest-a", "w-legs-a"]);
  const sessions = payload.sessions as Record<string, unknown>[];
  sessions[4].weekday = 5;
  sessions[4].name = "Chest again";
  sessions[4].exercises = sessions[3].exercises;
  return parsePlanState(payload)!;
}

Deno.test("back-to-back muscles: the overlap fact from the schedule module is the first line, and rest between ends it", () => {
  const lines = linesOf({ plan: backToBackPlan() });
  assertEquals(lines.length, 1);
  assertStringIncludes(
    lines[0],
    "Same muscles on consecutive days, with no rest day between (Tracend calculated from the dates): Thu 2026-10-15 then Fri 2026-10-16: chest, triceps, front and side delts.",
  );
  // The advice after the fact is in the block's introduction, once, not in the line.
  assert(!lines[0].includes("proposal"));
  assertEquals(linesOf({ plan: midweek() }), []);
});

Deno.test("a session due today or tomorrow on a poor recovery day names the session, the dates and the figures", () => {
  const lines = linesOf({
    plan: midweek(),
    facts: factsOf({
      metrics: metrics({ recovery_score: 31, sleep_quality_score: 44 }),
      sleep: { local_date: wednesday, minutes: 355 },
      check_in: {
        local_date: wednesday,
        pain_severity: 3,
        soreness: 4,
        energy: 2,
        sleep_quality: 2,
      },
    }),
  });
  assertEquals(lines.length, 1);
  assertEquals(
    lines[0],
    "- Due Pull and rear delts today (Wed 2026-10-14) and Chest volume and delts tomorrow (Thu 2026-10-15), with recovery score 31 on 2026-10-14 (below 40); sleep quality score 44 on 2026-10-14 (below 50, 355 min (5 h 55 min; 5.9 h) asleep on 2026-10-14); check-in pain 3/10 on 2026-10-14.",
  );
});

Deno.test("the due-session line fires for each reason alone and for none of the good days", () => {
  const plan = midweek();
  const reason = (patch: Record<string, unknown>) =>
    linesOf({ plan, facts: factsOf(patch) }).filter((line) => line.startsWith("- Due "));
  assertEquals(reason({ metrics: metrics({ recovery_score: 39 }) }).length, 1);
  assertEquals(reason({ metrics: metrics({ sleep_quality_score: 49 }) }).length, 1);
  assertEquals(
    reason({
      check_in: {
        local_date: wednesday,
        pain_severity: 1,
        soreness: 1,
        energy: 3,
        sleep_quality: 3,
      },
    })
      .length,
    1,
  );
  // At the threshold or above, with no pain: nothing.
  assertEquals(reason({ metrics: metrics({ recovery_score: 40, sleep_quality_score: 50 }) }), []);
  assertEquals(
    reason({
      check_in: {
        local_date: wednesday,
        pain_severity: 0,
        soreness: 5,
        energy: 1,
        sleep_quality: 1,
      },
    }),
    [],
  );
  assertEquals(reason({}), []);
  // A score that was not computed is not a low one.
  assertEquals(
    reason({ metrics: metrics({ recovery_score: null, sleep_quality_score: null }) }),
    [],
  );
});

Deno.test("no session due today or tomorrow, or today's already done: no due-session line even on a bad day", () => {
  const bad = factsOf({ metrics: metrics({ recovery_score: 20 }) });
  // Sunday with the week finished and Monday tomorrow still has a session due tomorrow...
  const sunday = parsePlanState(
    splitPlanPayload(7, [
      "w-chest-a",
      "w-legs-a",
      "w-pull",
      "w-chest-b",
      "w-legs-b",
      "w-shoulders",
    ]),
  )!;
  assertEquals(linesOf({ plan: sunday, facts: bad }).length, 1);
  // ...but with no weekday set on any session there is nothing due.
  const payload = splitPlanPayload(7, []);
  for (const session of payload.sessions as { weekday: number | null }[]) session.weekday = null;
  assertEquals(linesOf({ plan: parsePlanState(payload)!, facts: bad }), []);
  // Today's session already logged, tomorrow free (Friday done, Saturday has the last session... use Sunday).
  const doneToday = parsePlanState(
    splitPlanPayload(3, ["w-chest-a", "w-legs-a", "w-pull"], {
      recent_completed: [{
        planned_workout_id: "w-pull",
        local_date: wednesday,
        name: "Pull and rear delts",
        exercises: [{ slug: "lat-pulldown", sets: 4 }],
      }],
    }),
  )!;
  const due = linesOf({ plan: doneToday, facts: bad }).filter((line) => line.startsWith("- Due "));
  assertEquals(due.length, 1);
  assert(!due[0].includes("today"));
  assertStringIncludes(due[0], "tomorrow");
});

Deno.test("a pain flag on an exercise that the next seven days plan again names both dates", () => {
  const plan = midweek();
  const lines = linesOf({
    plan,
    facts: factsOf({
      pain_flags: [{ local_date: "2026-10-10", name: "Barbell row", slug: "barbell-row" }],
    }),
  });
  assertEquals(lines, [
    "- Barbell row (pain flagged on 2026-10-10) is planned again in Pull and rear delts on Wed 2026-10-14.",
  ]);
  // An exercise no planned session holds, or one with no catalog slug, says nothing.
  assertEquals(
    linesOf({
      plan,
      facts: factsOf({
        pain_flags: [{ local_date: "2026-10-10", name: "Zottman curl", slug: "zottman-curl" }],
      }),
    }),
    [],
  );
  assertEquals(
    linesOf({
      plan,
      facts: factsOf({
        pain_flags: [{ local_date: "2026-10-10", name: "Barbell row", slug: null }],
      }),
    }),
    [],
  );
});

Deno.test("behind plan: sessions of days already past that are undone, with what was finished", () => {
  const behind = parsePlanState(splitPlanPayload(3, ["w-chest-a"]))!;
  assertEquals(linesOf({ plan: behind }), [
    "- Behind plan this week: Legs A (Tuesday) not done, planned for days already past; 1 finished since Monday (2026-10-12).",
  ]);
  assertEquals(linesOf({ plan: midweek() }), []);
  const none = parsePlanState(splitPlanPayload(3, []))!;
  assertStringIncludes(
    linesOf({ plan: none })[0],
    "Chest priority and side delts (Monday) and Legs A (Tuesday) not done",
  );
  assertStringIncludes(linesOf({ plan: none })[0], "none finished since Monday");
});

Deno.test("behind plan: a session logged but not finished is not called undone", () => {
  const unfinished = [{
    planned_workout_id: "w-legs-a",
    local_date: "2026-10-13",
    name: "Legs A",
    logged_sets: 9,
  }];
  const logged = parsePlanState(splitPlanPayload(3, ["w-chest-a"], { unfinished }))!;
  assertEquals(linesOf({ plan: logged }), []);
  // Another session of the same week left undone is still behind plan.
  const other = parsePlanState(splitPlanPayload(3, [], { unfinished }))!;
  const line = linesOf({ plan: other })[0];
  assertStringIncludes(line, "Chest priority and side delts (Monday) not done");
  assert(!line.includes("Legs A"));
});

// The plan laid over the last weeks, as the schedule lookup returns it.
const scheduleBody = (days: Record<string, unknown>[], today = wednesday) => ({
  schema_version: "1.1",
  lookup: "plan_history",
  filter: "schedule",
  from: "2026-09-16",
  to: "2026-10-13",
  today,
  plan: { id: "v3", version: 3 },
  sessions: [{ id: "w-pull", version_id: "v3", name: "Pull day", weekday: 3, exercises: [] }],
  days,
});
const planned = (date: string, name = "Pull day", id = "w-pull") => ({
  date,
  weekday: 3,
  version_id: "v3",
  version: 3,
  block: false,
  planned: [{ id, name }],
  done: [],
});
const finished = (date: string, name = "Pull day", id = "w-pull") => ({
  ...planned(date, name, id),
  planned: [{ id, name }],
  done: [{ planned_workout_id: id, name, exercises: [] }],
});

Deno.test("the same session missed on each of its last planned days is named with those dates", () => {
  const lines = linesOf({
    schedule: readScheduleBody(scheduleBody([
      finished("2026-09-23"),
      planned("2026-09-30"),
      planned("2026-10-07"),
    ])),
  });
  assertEquals(lines, [
    "- Planned but not logged on each of its last days: Pull day (2026-09-30 and 2026-10-07).",
  ]);
});

Deno.test("one miss, or a miss followed by a session that was done, is not a repeat", () => {
  const one = scheduleBody([finished("2026-09-30"), planned("2026-10-07")]);
  assertEquals(linesOf({ schedule: readScheduleBody(one) }), []);
  const recovered = scheduleBody([
    planned("2026-09-23"),
    planned("2026-09-30"),
    finished("2026-10-07"),
  ]);
  assertEquals(linesOf({ schedule: readScheduleBody(recovered) }), []);
  // Today and later are not misses yet.
  const todayOnly = scheduleBody([planned("2026-10-07"), planned(wednesday)]);
  assertEquals(linesOf({ schedule: readScheduleBody(todayOnly) }), []);
  // A session logged under another plan version's workout id counts by name.
  const renamed = {
    ...planned("2026-10-07"),
    done: [{ planned_workout_id: "w-old", name: "Pull day", exercises: [] }],
  };
  assertEquals(
    linesOf({
      schedule: readScheduleBody(scheduleBody([planned("2026-09-30"), renamed])),
    }),
    [],
  );
});

Deno.test("an exercise skipped in each of its last sessions is named; one skip is not a pattern", () => {
  const lines = linesOf({
    facts: factsOf({
      skipped: [{
        name: "Cable chest fly",
        slug: "cable-chest-fly",
        sessions: 3,
        last_date: "2026-10-12",
      }],
    }),
  });
  assertEquals(lines, [
    "- Skipped in each of its last sessions: Cable chest fly (3 in a row, last 2026-10-12).",
  ]);
  assertEquals(
    linesOf({
      facts: factsOf({
        skipped: [{ name: "Cable chest fly", slug: null, sessions: 1, last_date: "2026-10-12" }],
      }),
    }),
    [],
  );
});

Deno.test("resting heart rate or HRV one spread or more off their usual: the engine's z-scores, adverse direction only", () => {
  const drift = (patch: Record<string, unknown>) =>
    linesOf({ facts: factsOf({ metrics: metrics(patch) }) });
  assertEquals(drift({ hrv_z: -1.4 }), [
    '- On 2026-10-14, HRV is 1.4 spreads below their usual (the recovery score\'s z-scores; the app calls one spread "than usual").',
  ]);
  assertStringIncludes(
    drift({ rhr_z: -2.06 })[0],
    "resting heart rate is 2.1 spreads above their usual",
  );
  assertStringIncludes(
    drift({ rhr_z: -1, hrv_z: -1 })[0],
    "resting heart rate is 1.0 spreads above their usual and HRV is 1.0 spreads below their usual",
  );
  // Inside one spread, or in the good direction, or a component the score could not use.
  assertEquals(drift({ hrv_z: -0.99, rhr_z: -0.5 }), []);
  assertEquals(drift({ hrv_z: 2.4, rhr_z: 3 }), []);
  assertEquals(drift({ hrv_z: -1.4, missing_components: ["hrv_sdnn"] }), []);
  assertEquals(drift({ rhr_z: -1.4, missing_components: ["resting_hr"] }), []);
  assertEquals(drift({ hrv_z: null, rhr_z: null }), []);
});

Deno.test("a weigh-in older than 14 days and an Apple Health sync older than 2 days are stale; at the limit they are not", () => {
  const stale = (patch: Record<string, unknown>) => linesOf({ facts: factsOf(patch) });
  assertEquals(stale({ weigh_in: { local_date: "2026-09-29" } }), [
    "- Last weigh-in was 2026-09-29, 15 days ago (older than 14 days, so no weight trend is current).",
  ]);
  assertEquals(stale({ weigh_in: { local_date: "2026-09-30" } }), []);
  assertEquals(stale({ weigh_in: null }), []);
  // 2026-10-14 09:00 now: a sync at 2026-10-11 08:00 is 3 days and 1 hour ago.
  assertEquals(
    stale({ health_sync: { at: "2026-10-11T08:00:00Z", local_date: "2026-10-11" } }),
    [
      "- Apple Health last synced on 2026-10-11, more than 73 hours ago (the app calls more than 48 hours stale), so recent sleep and recovery rows may be missing.",
    ],
  );
  // Exactly two days of elapsed time is not stale; a second more is.
  assertEquals(
    stale({ health_sync: { at: "2026-10-12T09:00:00Z", local_date: "2026-10-12" } }),
    [],
  );
  // Just over two days reads as over 48 hours, never as "2 days ago ... more than 2 days stale".
  assertEquals(
    stale({ health_sync: { at: "2026-10-12T08:59:59Z", local_date: "2026-10-12" } }),
    [
      "- Apple Health last synced on 2026-10-12, more than 48 hours ago (the app calls more than 48 hours stale), so recent sleep and recovery rows may be missing.",
    ],
  );
  // Without the database's now there is no elapsed time to judge.
  assertEquals(
    stale({
      as_of: null,
      health_sync: { at: "2026-10-01T08:00:00Z", local_date: "2026-10-01" },
    }),
    [],
  );
  assertEquals(stale({ health_sync: null }), []);
});

Deno.test("a plan older than its own block is flagged; a younger one, a temporary block and an unknown block are not", () => {
  const age = (plan: Record<string, unknown> | null) => linesOf({ facts: factsOf({ plan }) });
  assertEquals(age({ version: 3, starts_on: "2026-07-01", block_weeks: 6, ends_on: null }), [
    "- The current plan (v3) has run since 2026-07-01, 15 weeks; its block is 6 weeks.",
  ]);
  // Exactly the block length: the block is complete.
  assertEquals(
    age({ version: 3, starts_on: "2026-09-02", block_weeks: 6, ends_on: null }).length,
    1,
  );
  assertEquals(age({ version: 3, starts_on: "2026-09-03", block_weeks: 6, ends_on: null }), []);
  assertEquals(
    age({ version: 3, starts_on: "2026-01-01", block_weeks: 6, ends_on: "2026-10-20" }),
    [],
  );
  assertEquals(age({ version: 3, starts_on: "2026-01-01", block_weeks: null, ends_on: null }), []);
  assertEquals(age(null), []);
});

Deno.test("every threshold is one the product already uses, and the sources still say so", () => {
  assertEquals(watchOutThresholds.recoveryScoreBelow, 40);
  assertEquals(watchOutThresholds.sleepQualityBelow, 50);
  assertStringIncludes(
    evidenceCodeReference,
    `RECOVERY_BELOW_BASELINE = recovery score < ${watchOutThresholds.recoveryScoreBelow}`,
  );
  assertStringIncludes(
    evidenceCodeReference,
    `SLEEP_QUALITY_POOR = sleep quality score < ${watchOutThresholds.sleepQualityBelow}`,
  );
  // One spread is the app's "than usual" (recovery_readout_card.dart: magnitude < 1 is normal for you);
  // 14 days is the goal phase's stale reading (ALGORITHMS.md); 2 days is the app's stale sync.
  assertEquals(watchOutThresholds.driftSpreads, 1);
  assertEquals(watchOutThresholds.weighInStaleDays, 14);
  assertEquals(watchOutThresholds.healthSyncStaleDays, 2);
  assertEquals(watchOutThresholds.repeatedTimes, 2);
});

// Everything fires: back-to-back muscles, a due session on a bad day, a pain flag, behind plan,
// repeated misses, skips, drift, a stale weigh-in and sync, and an old plan.
function everything(): WatchOutInputs {
  const payload = splitPlanPayload(3, ["w-chest-a"]);
  const sessions = payload.sessions as Record<string, unknown>[];
  sessions[4].weekday = 5;
  sessions[4].exercises = sessions[3].exercises;
  return {
    plan: parsePlanState(payload)!,
    facts: factsOf({
      metrics: metrics({ recovery_score: 20, sleep_quality_score: 30, hrv_z: -2, rhr_z: -2 }),
      check_in: {
        local_date: wednesday,
        pain_severity: 4,
        soreness: 4,
        energy: 1,
        sleep_quality: 1,
      },
      pain_flags: [{ local_date: "2026-10-10", name: "Barbell row", slug: "barbell-row" }],
      skipped: [{ name: "Cable chest fly", slug: null, sessions: 3, last_date: "2026-10-12" }],
      weigh_in: { local_date: "2026-09-01" },
      health_sync: { at: "2026-10-01T08:00:00Z", local_date: "2026-10-01" },
      as_of: "2026-10-14T09:00:00Z",
      plan: { version: 3, starts_on: "2026-04-01", block_weeks: 6, ends_on: null },
    }),
    schedule: readScheduleBody(scheduleBody([planned("2026-09-30"), planned("2026-10-07")])),
  };
}

Deno.test("at most 8 lines and 900 characters, most important first; a line that does not fit is left out, never cut", () => {
  const found = computeWatchOuts(everything());
  assert(found.length <= watchOutsMaxLines, `${found.length} lines`);
  const total = found.reduce((sum, item) => sum + item.line.length + 1, 0);
  assert(total <= watchOutsLinesMaxChars, `${total} characters`);
  assert(found[0].line.startsWith("- Same muscles on consecutive days"));
  assert(found[1].line.startsWith("- Due "));
  // Whole lines only: each ends in a full stop.
  for (const item of found) assert(item.line.endsWith("."), item.line);
  // The block, introduction included, fits the contributor's budget.
  assert(renderWatchOuts(everything())!.length <= watchOutsBudgetChars);
  // The lowest-priority lines are the ones that make way.
  const kinds = found.map((item) => item.kind);
  assertEquals(kinds.filter((kind) => kind === "decision").length >= 5, true);
});

Deno.test("nothing found renders nothing, and a part that could not be read only drops its own lines", () => {
  assertEquals(renderWatchOuts({ plan: null, facts: null, schedule: null }), null);
  assertEquals(renderWatchOuts({ plan: midweek(), facts: factsOf(), schedule: null }), null);
  const all = everything();
  const withoutPlan = computeWatchOuts({ ...all, plan: null }).map((item) => item.line);
  assert(withoutPlan.every((line) => !line.startsWith("- Due ") && !line.startsWith("- Behind")));
  assert(withoutPlan.length > 0);
  const withoutFacts = computeWatchOuts({ ...all, facts: null }).map((item) => item.line);
  assert(withoutFacts.some((line) => line.startsWith("- Behind plan")));
  assert(!withoutFacts.some((line) => line.startsWith("- Last weigh-in")));
});

Deno.test("every line states dates and figures that the lines' own facts give, so the numbers check can ground a reply on them", () => {
  const text = renderWatchOuts(everything())!;
  for (const figure of ["20 on 2026-10-14", "below 40", "30 on 2026-10-14", "pain 4/10"]) {
    assertStringIncludes(text, figure);
  }
  assertStringIncludes(text, "2026-10-10");
});

Deno.test("parseWatchFacts reads the database payload and refuses a stranger", () => {
  assertEquals(parseWatchFacts(null), null);
  assertEquals(parseWatchFacts({ schema_version: "2.0", local_date: wednesday }), null);
  assertEquals(parseWatchFacts({ schema_version: "1.0" }), null);
  const bare = parseWatchFacts({ schema_version: "1.0", local_date: wednesday })!;
  assertEquals(bare.metrics, null);
  assertEquals(bare.painFlags, []);
  assertEquals(bare.plan, null);
  const full = factsOf({
    metrics: metrics({ hrv_z: "-1.4" }),
    plan: { version: 3, starts_on: "2026-09-16", block_weeks: 6, ends_on: "2026-10-20" },
  });
  assertEquals(full.metrics?.hrvZ, -1.4);
  assertEquals(full.plan?.temporary, true);
});

const planSource = () => Promise.resolve(splitPlanPayload(3, ["w-chest-a"]));
const factsSource = () =>
  Promise.resolve({
    schema_version: "1.0",
    local_date: wednesday,
    metrics: metrics({ recovery_score: 31 }),
    pain_flags: [{ local_date: "2026-10-10", name: "Barbell row", slug: "barbell-row" }],
    check_in: { local_date: wednesday, pain_severity: 0 },
    weigh_in: { local_date: "2026-10-12" },
    health_sync: { at: "2026-10-14T06:00:00Z", local_date: "2026-10-14" },
    as_of: "2026-10-14T09:00:00Z",
  });
const scheduleSource = () =>
  Promise.resolve(scheduleBody([planned("2026-09-30"), planned("2026-10-07")]));
const input = { userId: "user-1", question: "check my training", localDate: wednesday };

Deno.test("the contributor reports counts for the route and renders text with its introduction", async () => {
  const contributor = createWatchOutsContributor({
    planState: planSource,
    facts: factsSource,
    schedule: scheduleSource,
  });
  const result = await contributor.render(input);
  const block = result as { text: string; trace: Record<string, unknown> };
  assertStringIncludes(
    block.text,
    "Watch-outs: facts Tracend calculated across the athlete's records.",
  );
  assertStringIncludes(block.text, "A change to the plan is a proposal the athlete approves.");
  const lines = block.text.split("\n").filter((line) => line.startsWith("- "));
  assertEquals(block.trace, { lines: lines.length, decisions: lines.length, pain: true });
  assert(lines.length >= 3);
  assertEquals(contributor.id, "watch_outs");
  assertEquals(contributor.slot, "volatile");
});

Deno.test("a source that fails or times out drops only its lines; with all failing there is no text and pain is unknown", async () => {
  const failing = () => Promise.reject(new Error("down"));
  const noPlan = createWatchOutsContributor({
    planState: failing,
    facts: factsSource,
    schedule: scheduleSource,
  });
  const lines = ((await noPlan.render(input)) as { text: string }).text;
  assert(!lines.includes("Behind plan"));
  assertStringIncludes(lines, "Pull day (2026-09-30 and 2026-10-07)");
  const none = createWatchOutsContributor({
    planState: failing,
    facts: failing,
    schedule: failing,
  });
  // Nothing to show, and nothing known: no text, and pain is unknown (the route fails toward the
  // stronger model).
  assertEquals(await none.render(input), {
    text: "",
    shown: {},
    records: [],
    figures: [],
    trace: { lines: 0, decisions: 0, pain: null },
  });
  // An empty schedule payload (an athlete without a plan) reads as no schedule.
  const empty = createWatchOutsContributor({
    planState: planSource,
    facts: failing,
    schedule: () => Promise.resolve(null),
  });
  assertStringIncludes(((await empty.render(input)) as { text: string }).text, "Behind plan");
});

Deno.test("the plan state is read once for the turn, shared with the training plan block", async () => {
  let reads = 0;
  const shared = () => {
    reads += 1;
    return planSource();
  };
  const result = await renderCoachContext([
    createTrainingPlanContributor(shared),
    createWatchOutsContributor({ planState: shared, facts: factsSource, schedule: scheduleSource }),
  ], input);
  assertEquals(reads, 1);
  assertEquals(result.outcomes.map((item) => item.outcome), ["rendered", "rendered"]);
  assertEquals(result.traces?.watch_outs?.pain, true);
  assertStringIncludes(result.texts.training_plan, "Next 7 days from today");
  assert(!result.texts.training_plan.includes("Same muscles on consecutive days"));
});

Deno.test("the schedule is read for the four weeks before the coaching date, ending yesterday", async () => {
  const calls: unknown[] = [];
  const source = scheduleSourceFromRpc((name, params) => {
    calls.push([name, params]);
    return Promise.resolve({ data: { ok: true }, error: null });
  });
  assertEquals(await source("user-1", wednesday), { ok: true });
  assertEquals(calls, [[
    "coach_lookup_plan_history_v1",
    {
      p_user_id: "user-1",
      p_from: "2026-09-16",
      p_to: "2026-10-13",
      p_filter: "schedule",
    },
  ]]);
  assertEquals(missedLookbackDays, 28);
  const broken = scheduleSourceFromRpc(() => Promise.resolve({ data: null, error: { code: "x" } }));
  let failed = false;
  try {
    await broken("user-1", wednesday);
  } catch {
    failed = true;
  }
  assert(failed);
});

Deno.test("nothing to watch still reports the counts: no text, pain known and absent", async () => {
  const quiet = createWatchOutsContributor({
    planState: () => Promise.resolve(splitPlanPayload(3, ["w-chest-a", "w-legs-a"])),
    facts: () => Promise.resolve({ schema_version: "1.0", local_date: wednesday }),
    schedule: () => Promise.resolve(null),
  });
  assertEquals(await quiet.render(input), {
    text: "",
    shown: {},
    records: [],
    figures: [],
    trace: { lines: 0, decisions: 0, pain: false },
  });
  const result = await renderCoachContext([quiet], input);
  assertEquals(result.outcomes[0].outcome, "empty");
  assertEquals(result.volatile, "");
  // The host keeps the counts of an empty block for the route.
  assertEquals(result.traces?.watch_outs, { lines: 0, decisions: 0, pain: false });
});

Deno.test("pain on record is reported whether or not any line renders", async () => {
  const painOnly = createWatchOutsContributor({
    planState: () => Promise.resolve(null),
    facts: () =>
      Promise.resolve({
        schema_version: "1.0",
        local_date: wednesday,
        check_in: { local_date: wednesday, pain_severity: 2 },
      }),
    schedule: () => Promise.resolve(null),
  });
  const result = await renderCoachContext([painOnly], input);
  assertEquals(result.outcomes[0].outcome, "empty");
  assertEquals(result.traces?.watch_outs?.pain, true);
});

Deno.test("the lines are packed against the budget the introduction leaves, so the host never cuts a block", () => {
  assertEquals(watchOutsBudgetChars, 1_200);
  assert(watchOutsLinesRoom <= watchOutsLinesMaxChars);
  assert(introductionLength() + watchOutsLinesRoom <= watchOutsBudgetChars);
  const text = renderWatchOuts(everything())!;
  assert(text.length <= watchOutsBudgetChars, `${text.length} characters`);
});

Deno.test("the trace counts the lines kept, not the lines found", async () => {
  const contributor = createWatchOutsContributor({
    planState: () =>
      Promise.resolve(everything().plan === null ? null : splitPlanPayload(3, ["w-chest-a"])),
    facts: () =>
      Promise.resolve({
        schema_version: "1.0",
        local_date: wednesday,
        metrics: metrics({ recovery_score: 20, sleep_quality_score: 30, hrv_z: -2, rhr_z: -2 }),
        check_in: { local_date: wednesday, pain_severity: 4 },
        pain_flags: [{ local_date: "2026-10-10", name: "Barbell row", slug: "barbell-row" }],
        skipped: [{ name: "Cable chest fly", slug: null, sessions: 3, last_date: "2026-10-12" }],
        weigh_in: { local_date: "2026-09-01" },
        health_sync: { at: "2026-10-01T08:00:00Z", local_date: "2026-10-01" },
        as_of: "2026-10-14T09:00:00Z",
        plan: { version: 3, starts_on: "2026-04-01", block_weeks: 6, ends_on: null },
      }),
    schedule: () => Promise.resolve(scheduleBody([planned("2026-09-30"), planned("2026-10-07")])),
  });
  const block = (await contributor.render(input)) as unknown as {
    text: string;
    trace: { lines: number; decisions: number };
  };
  const lines = block.text.split("\n").filter((line) => line.startsWith("- "));
  assertEquals(block.trace.lines, lines.length);
  assert(lines.length < 10);
  const result = await renderCoachContext([contributor], input);
  assertEquals(result.outcomes[0].clipped, false);
});

Deno.test("a watch-outs read that times out leaves the host with a timeout outcome and no trace", async () => {
  const hanging = createWatchOutsContributor({
    planState: () => new Promise(() => {}),
    facts: () => new Promise(() => {}),
    schedule: () => new Promise(() => {}),
  });
  const result = await renderCoachContext([hanging], input, 20);
  assertEquals(result.outcomes[0].outcome, "timeout");
  assertEquals(result.traces?.watch_outs, undefined);
});

Deno.test("a slow facts or schedule read does not cost the back-to-back muscles: the plan's line survives", async () => {
  const payload = splitPlanPayload(3, ["w-chest-a", "w-legs-a"]);
  const sessions = payload.sessions as Record<string, unknown>[];
  sessions[4].weekday = 5;
  sessions[4].exercises = sessions[3].exercises;
  const slow = createWatchOutsContributor({
    planState: () => Promise.resolve(payload),
    facts: () => new Promise(() => {}),
    schedule: () => new Promise(() => {}),
  }, 20);
  const result = await renderCoachContext([slow], input, 500);
  assertEquals(result.outcomes[0].outcome, "rendered");
  assertStringIncludes(result.volatile, "Same muscles on consecutive days");
  // Pain is unknown (the facts never came), so the route fails toward the stronger model.
  assertEquals(result.traces?.watch_outs?.pain, null);
});

Deno.test("a session missed under an older version of the plan is not raised: only days planned by the plan in force count", () => {
  const older = (date: string) => ({ ...planned(date), version_id: "v2", version: 2 });
  const body = scheduleBody([older("2026-09-23"), older("2026-09-30"), planned("2026-10-07")]);
  assertEquals(linesOf({ schedule: readScheduleBody(body) }), []);
  // Two misses under the current version still count.
  const current = scheduleBody([older("2026-09-23"), planned("2026-09-30"), planned("2026-10-07")]);
  assertEquals(linesOf({ schedule: readScheduleBody(current) }), [
    "- Planned but not logged on each of its last days: Pull day (2026-09-30 and 2026-10-07).",
  ]);
  // Without a plan in force nothing is claimed.
  assertEquals(
    linesOf({ schedule: readScheduleBody({ ...scheduleBody([planned("2026-10-07")]), plan: {} }) }),
    [],
  );
});

Deno.test("the stale-sync rule is the app's: elapsed time since the last successful sync, pinned by the cases the app tests read", () => {
  assertEquals(cases.cases.length >= 6, true);
  for (const item of cases.cases) {
    const lines = linesOf({
      facts: factsOf({
        health_sync: {
          at: item.last_sync,
          local_date: item.last_sync.slice(0, 10),
        },
        as_of: item.now,
      }),
    }).filter((line) => line.startsWith("- Apple Health last synced"));
    assertEquals(lines.length, item.stale ? 1 : 0, item.name);
  }
  assertEquals(watchOutThresholds.healthSyncStaleMs, 2 * 86_400_000);
  // The weigh-in rule is the goal phase's own, read from it, and counts days between dates.
  assertEquals(watchOutThresholds.weighInStaleDays, goalPhaseThresholds.staleReadingDays.value);
});

Deno.test("two workouts that share a name are two sessions: a streak belongs to one planned workout, not to the name", () => {
  const day = (
    date: string,
    planned: { id: string; logged: boolean }[],
  ) => ({
    date,
    weekday: 3,
    version_id: "v3",
    version: 3,
    block: false,
    planned: planned.map(({ id }) => ({ id, name: "Pull day" })),
    done: planned.filter((item) => item.logged).map(({ id }) => ({
      planned_workout_id: id,
      name: "Pull day",
      exercises: [],
    })),
  });
  const body = (days: unknown[]) => ({
    ...scheduleBody([]),
    sessions: [
      { id: "w-pull-a", version_id: "v3", name: "Pull day", weekday: 3, exercises: [] },
      { id: "w-pull-b", version_id: "v3", name: "Pull day", weekday: 5, exercises: [] },
    ],
    days,
  });
  // B is missed on both of its days while A is done: B's streak, said under the shared name.
  const bMissed = body([
    day("2026-09-30", [{ id: "w-pull-a", logged: true }, { id: "w-pull-b", logged: false }]),
    day("2026-10-07", [{ id: "w-pull-a", logged: true }, { id: "w-pull-b", logged: false }]),
  ]);
  assertEquals(linesOf({ schedule: readScheduleBody(bMissed) }), [
    "- Planned but not logged on each of its last days: Pull day (2026-09-30 and 2026-10-07).",
  ]);
  // A and B each miss once, on different days: no workout has two misses in a row. A name-keyed
  // count would call it two.
  const oneEach = body([
    day("2026-09-30", [{ id: "w-pull-a", logged: false }, { id: "w-pull-b", logged: true }]),
    day("2026-10-07", [{ id: "w-pull-a", logged: true }, { id: "w-pull-b", logged: false }]),
  ]);
  assertEquals(linesOf({ schedule: readScheduleBody(oneEach) }), []);
  // B done after two misses ends B's streak even though A is missed again.
  const recovered = body([
    day("2026-09-23", [{ id: "w-pull-b", logged: false }]),
    day("2026-09-30", [{ id: "w-pull-b", logged: false }]),
    day("2026-10-07", [{ id: "w-pull-a", logged: false }, { id: "w-pull-b", logged: true }]),
  ]);
  assertEquals(linesOf({ schedule: readScheduleBody(recovered) }), []);
  // Two workouts, each missed twice, are two entries under the one name.
  const both = body([
    day("2026-09-30", [{ id: "w-pull-a", logged: false }, { id: "w-pull-b", logged: false }]),
    day("2026-10-07", [{ id: "w-pull-a", logged: false }, { id: "w-pull-b", logged: false }]),
  ]);
  const line = linesOf({ schedule: readScheduleBody(both) })[0];
  assertEquals(line.split("Pull day").length - 1, 2);
});

Deno.test("a workout made up on another day answers its own streak", () => {
  const body = scheduleBody([
    planned("2026-09-23"),
    planned("2026-09-30"),
    {
      ...planned("2026-10-02"),
      planned: [],
      done: [{ planned_workout_id: "w-pull", name: "Pull day", exercises: [] }],
    },
  ]);
  // Missed on the 23rd and 30th, then done on the 2nd (a make-up): the newest is a success.
  assertEquals(linesOf({ schedule: readScheduleBody(body) }), []);
});
