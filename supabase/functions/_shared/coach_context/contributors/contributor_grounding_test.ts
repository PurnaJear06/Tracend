// What each contributor declared `records` grounds in a reply's numbers check (finding P1 of the
// review of PR #159): its record values, and nothing else. Each test renders one contributor on
// fixture data and hands it to `probeContributor` (contributor_probe.ts), which lists the numbers in
// the text that are not record values (the fixed wording: windows, thresholds, ids, definitions),
// asserts none of them grounds a figure or the athlete's own data or target, and asserts every
// value the contributor marked is a value of the fixture and grounds.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import cases from "../../training/heart_rate/profile_cases.json" with { type: "json" };
import { numberGroundOf, ungroundedNumbers } from "../../coach_safety/numbers_check.ts";
import { factWire, makeFact } from "../../coach_memory/memory_fixtures.ts";
import { longCutPayload } from "../../training/goal_phase/fixtures.ts";
import {
  parseGoalPhaseInputs,
  reviewGoalPhase,
  summarizeGoalPhase,
} from "../../training/goal_phase/index.ts";
import { buildHeartRateProfile, type HeartRateInputs } from "../../training/heart_rate/profile.ts";
import { readScheduleBody } from "../../training/schedule/lookup_body.ts";
import { dayOf } from "../../training/schedule/week_ahead.ts";
import { contributorGrounding } from "../grounding.ts";
import { type CoachContextContributor, type RenderedBlock } from "../host.ts";
import { coachContextContributors } from "../registry.ts";
import type { ServiceRpc } from "../service_source.ts";
import { createCoachNotesContributor } from "./coach_notes.ts";
import { createConfirmedFactsContributor } from "./confirmed_facts.ts";
import { probeContributor } from "./contributor_probe.ts";
import { createCoverageBriefContributor } from "./coverage_brief.ts";
import { createGoalPhaseContributor } from "./goal_phase.ts";
import { createHeartRateContributor } from "./heart_rate.ts";
import { createMemorySource } from "./memory_source.ts";
import { createNutritionStateContributor } from "./nutrition_state.ts";
import { ownersPlanPayload, splitPlanPayload } from "./plan_fixtures.ts";
import { createProposalsContributor } from "./proposals.ts";
import { createScreeningContributor } from "./screening.ts";
import { createTrainingPlanContributor } from "./training_plan.ts";
import { createWatchOutsContributor } from "./watch_outs.ts";

const input = { userId: "u", question: "Status?", localDate: "2026-10-18" };

async function blockOf(contributor: CoachContextContributor, localDate = input.localDate) {
  const rendered = await contributor.render({ ...input, localDate });
  assert(typeof rendered === "object" && rendered !== null, `${contributor.id} renders a block`);
  return rendered as RenderedBlock;
}

Deno.test("every contributor that grounds as records has a probe here", () => {
  const probed = [
    "screening",
    "confirmed_facts",
    "goal_phase",
    "training_plan",
    "nutrition_state",
    "coach_proposals",
    "heart_rate_profile",
    "coach_notes",
    "watch_outs",
    "coverage_brief",
  ];
  assertEquals(
    Object.entries(contributorGrounding).filter(([, kind]) => kind === "records").map(([id]) => id)
      .sort(),
    [...probed].sort(),
  );
  for (const id of probed) {
    assert(coachContextContributors.some((contributor) => contributor.id === id), id);
  }
});

Deno.test("coverage brief: counts, dates and ages ground; its windows and sizes do not", async () => {
  const today = "2026-10-20";
  const domain = (first: string, last: string, count: number) => ({ first, last, count });
  const none = { first: null, last: null, count: 0 };
  const payload = {
    schema_version: "1.2",
    local_date: today,
    schedule: { version: 3, starts_on: "2026-09-28", weekdays: [1, 2, 3, 4, 5, 6] },
    domains: {
      workouts: domain("2026-06-03", "2026-10-19", 61),
      meals: domain("2026-06-10", "2026-10-20", 91),
      body: domain("2026-06-03", "2026-10-16", 41),
      check_ins: domain("2026-07-01", "2026-10-20", 71),
      recovery: domain("2026-06-01", "2026-10-20", 121),
      plan_history: domain("2026-06-03", "2026-09-01", 4),
      goals: domain("2026-06-03", "2026-06-03", 2),
      weekly_reviews: none,
      health_history: domain("2025-10-01", "2026-09-01", 13),
      watch_workouts: domain("2026-05-01", "2026-10-19", 56),
      proposals: domain("2026-09-01", "2026-10-15", 5),
      daily_decisions: domain("2026-08-01", "2026-10-20", 62),
      past_messages: domain("2026-09-01", "2026-10-20", 31),
    },
  };
  const block = await blockOf(
    createCoverageBriefContributor(() => Promise.resolve(payload)),
    today,
  );
  const ages = Object.values(payload.domains).map((item) =>
    dayOf(today) - dayOf(item.last ?? today)
  )
    .filter((days) => Number.isFinite(days));
  const inputs = probeContributor({
    id: "coverage_brief",
    block,
    fixture: payload,
    calculated: ages,
    fixed: ["14|other", "28|other", "3|", "60|other", "7|d", "8|wk", "90|other"],
  });
  // The two readings that the review of PR #159 named.
  for (const side of [inputs.ground, inputs.athleteGround!]) {
    assertEquals(ungroundedNumbers("You lost 3 kg.", side), ["3"]);
    assertEquals(ungroundedNumbers("Your weight over the last 28 days fell 28 kg.", side), ["28"]);
  }
  // A real count and a real date still ground.
  assertEquals(
    ungroundedNumbers(
      "You have 61 sessions logged, the last on 2026-10-19.",
      inputs.athleteGround!,
    ),
    [],
  );
});

Deno.test("watch-outs: dates, scores and counts ground; thresholds, limits and the app's rule do not", async () => {
  const wednesday = "2026-10-14";
  const planPayload = splitPlanPayload(3, ["w-chest-a"]);
  const sessions = planPayload.sessions as Record<string, unknown>[];
  sessions[4].weekday = 5;
  sessions[4].exercises = sessions[3].exercises;
  const facts = {
    schema_version: "1.0",
    local_date: wednesday,
    sleep: { local_date: wednesday, minutes: 355 },
    metrics: {
      local_date: wednesday,
      recovery_score: 31,
      sleep_quality_score: 44,
      hrv_z: -2.3,
      rhr_z: -1.6,
      missing_components: [],
    },
    check_in: { local_date: wednesday, pain_severity: 3 },
    pain_flags: [{ local_date: "2026-10-10", name: "Barbell row", slug: "barbell-row" }],
    skipped: [{ name: "Cable chest fly", slug: null, sessions: 3, last_date: "2026-10-12" }],
    weigh_in: { local_date: wednesday },
    health_sync: { at: "2026-10-14T06:00:00Z", local_date: wednesday },
    as_of: "2026-10-14T09:00:00Z",
    plan: { version: 3, starts_on: "2026-10-01", block_weeks: 6, ends_on: null },
  };
  const planned = (date: string) => ({
    date,
    weekday: 3,
    version_id: "v3",
    version: 3,
    block: false,
    planned: [{ id: "w-pull", name: "Pull day" }],
    done: [],
  });
  const schedule = {
    schema_version: "1.1",
    lookup: "plan_history",
    filter: "schedule",
    from: "2026-09-16",
    to: "2026-10-13",
    today: wednesday,
    plan: { id: "v3", version: 3 },
    sessions: [{ id: "w-pull", version_id: "v3", name: "Pull day", weekday: 3, exercises: [] }],
    days: [planned("2026-09-30"), planned("2026-10-07")],
  };
  readScheduleBody(schedule);
  const decisions = await blockOf(
    createWatchOutsContributor({
      planState: () => Promise.resolve(planPayload),
      facts: () => Promise.resolve(facts),
      schedule: () => Promise.resolve(schedule),
    }),
    wednesday,
  );
  assert((decisions.records ?? []).length >= 10);
  const inputs = probeContributor({
    id: "watch_outs",
    block: decisions,
    fixture: { planPayload, facts, schedule },
    // The sleep in hours and minutes, the spreads to one decimal, the two finished sessions.
    calculated: [5, 55, 5.9, 2.3, 1.6, 2],
    // "3/10" is the scale of the pain score; 40 and 50 are the thresholds the lines apply.
    fixed: ["10|other", "40|", "50|"],
  });
  for (const side of [inputs.ground, inputs.athleteGround!]) {
    // "(below 40)" is the rule the line applies, not a reading.
    assertEquals(ungroundedNumbers("Your HRV was 40 ms.", side), ["40"]);
    assertEquals(ungroundedNumbers("Your recovery score was 40.", side), ["40"]);
    assertEquals(ungroundedNumbers("Your sleep quality was 50.", side), ["50"]);
  }
  assertEquals(
    ungroundedNumbers("Your recovery score was 31 on 2026-10-14.", inputs.athleteGround!),
    [],
  );
  // The lines about stale data: the age of the weigh-in and the sync, and the plan's age.
  const stale = {
    ...facts,
    sleep: null,
    metrics: null,
    check_in: null,
    pain_flags: [],
    skipped: [],
    weigh_in: { local_date: "2026-09-01" },
    health_sync: { at: "2026-10-01T08:00:00Z", local_date: "2026-10-01" },
    plan: { version: 3, starts_on: "2026-04-01", block_weeks: 6, ends_on: null },
  };
  const data = await blockOf(
    createWatchOutsContributor({
      planState: () => Promise.resolve(null),
      facts: () => Promise.resolve(stale),
      schedule: () => Promise.resolve(null),
    }),
    wednesday,
  );
  assertEquals((data.records ?? []).length >= 5, true);
  const second = probeContributor({
    id: "watch_outs",
    block: data,
    fixture: stale,
    // 43 days since the weigh-in, 337 hours since the sync, 28 weeks of plan.
    calculated: [43, 313, 28],
    // 14 days is when a weigh-in goes stale and 48 hours when the sync does.
    fixed: ["14|d", "48|h"],
  });
  for (const side of [second.ground, second.athleteGround!]) {
    assertEquals(ungroundedNumbers("Your last weigh-in was 14 days ago.", side), ["14"]);
    assertEquals(ungroundedNumbers("Apple Health synced 48 hours ago.", side), ["48"]);
  }
  assertEquals(
    ungroundedNumbers("Your last weigh-in was 43 days ago.", second.athleteGround!),
    [],
  );
});

Deno.test("training plan: the plan's sets, loads and names ground; the block's own rules do not", async () => {
  const payload = structuredClone(ownersPlanPayload()) as {
    sessions: { exercises: { sets: number }[] }[];
  };
  // A week of the plan gives no muscle 7 sets, so the 7 days the block looks at stand apart.
  payload.sessions[0].exercises[1].sets = 2;
  const block = await blockOf(
    createTrainingPlanContributor(() => Promise.resolve(payload)),
    "2026-10-17",
  );
  const inputs = probeContributor({
    id: "training_plan",
    block,
    fixture: payload,
    calculated: [],
    fixed: ["7|d"],
  });
  assert(inputs.athleteGround!.values.length > 10);
});

Deno.test("training plan: an unfinished session's sets and day ground as records", async () => {
  const payload = splitPlanPayload(7, [
    "w-chest-a",
    "w-legs-a",
    "w-pull",
    "w-chest-b",
    "w-shoulders",
  ], {
    unfinished: [{
      planned_workout_id: "w-legs-b",
      local_date: "2026-10-16",
      name: "Legs B",
      logged_sets: 23,
    }],
  });
  const block = await blockOf(
    createTrainingPlanContributor(() => Promise.resolve(payload)),
    "2026-10-18",
  );
  const inputs = probeContributor({
    id: "training_plan",
    block,
    fixture: payload,
    // The plan's sets a week for each muscle are sums of the plan's sets.
    calculated: [24, 14, 10, 7, 6, 3],
    fixed: [],
  });
  assert(block.text.includes("(23 sets logged)"));
  assertEquals(
    ungroundedNumbers("Legs B logged 23 sets on 2026-10-16.", inputs.athleteGround!),
    [],
  );
  assertEquals(ungroundedNumbers("You did 25 sets of Legs B.", inputs.athleteGround!), ["25"]);
});

Deno.test("nutrition: days, averages and the target ground; the rule for a complete day and the windows do not", async () => {
  const day = (
    local_date: string,
    meals: number,
    calories: number,
    complete: boolean,
    protein_g = 120,
  ) => ({ local_date, meals, calories, protein_g, carbohydrate_g: 200, fat_g: 60, complete });
  const payload = {
    schema_version: "1.0",
    local_date: "2026-10-17",
    target: { calories: 2000, protein_g: 150, carbohydrate_g: 220, fat_g: 65 },
    rules: { min_meals: 6, min_target_share: 0.55 },
    days: [
      day("2026-10-17", 1, 380, false, 30),
      day("2026-10-16", 4, 1900, true, 140),
      day("2026-10-15", 3, 2100, true, 160),
      day("2026-10-13", 2, 1500, true, 100),
    ],
    schedule: [
      {
        label: "Lunch",
        local_time: "13:00",
        logged: false,
        foods: [{ name: "Rice", quantity: "200 g" }, { name: "Chicken", quantity: "150 g" }],
      },
    ],
    eaten_today: [{
      meal_type: "breakfast",
      source: "photo_analysis",
      from_schedule: false,
      foods: [{ name: "Eggs", serving: "3", calories: 230, protein_g: 18 }],
    }],
    sources: { window_days: 14, meals: 22, photo_estimate: 5, from_schedule: 9, typed_in: 8 },
  };
  const block = await blockOf(
    createNutritionStateContributor(() => Promise.resolve(payload)),
    "2026-10-17",
  );
  const inputs = probeContributor({
    id: "nutrition_state",
    block,
    fixture: payload,
    // The averages of the complete days, and how far each is from the target.
    calculated: [1833, 133, 167, 17, 20],
    // The 7 and 14 days it looks at, and the rule for a complete day (6 meals or 55% of the target).
    fixed: ["14|d", "55|%", "6|other", "7|d"],
  });
  for (const side of [inputs.ground, inputs.athleteGround!]) {
    // A complete day needs 6 meals or 55% of the target here: a rule, not a reading.
    assertEquals(ungroundedNumbers("You ate 55% of your target.", side), ["55"]);
  }
});

Deno.test("goal phase: weights, dates, rates and the target ground; the window of the recent rate and the rules in a reason do not", async () => {
  const block = await blockOf(
    createGoalPhaseContributor(() => Promise.resolve(longCutPayload)),
    "2026-10-14",
  );
  const summary = summarizeGoalPhase(parseGoalPhaseInputs(longCutPayload, "2026-10-14"));
  const review = reviewGoalPhase(summary);
  const inputs = probeContributor({
    id: "goal_phase",
    block,
    fixture: { payload: longCutPayload, summary, review },
    calculated: [],
    fixed: ["2013|", "2014|", "2018|", "4|wk"],
  });
  for (const side of [inputs.ground, inputs.athleteGround!]) {
    assertEquals(ungroundedNumbers("Over the last 4 weeks you lost 4 kg.", side), ["4"]);
  }
});

Deno.test("heart rate: measured and calculated values ground; the age formula and its windows do not", async () => {
  const given = cases.find((item) => item.name === "recovery improving")!
    .inputs as unknown as HeartRateInputs;
  const profile = buildHeartRateProfile(given);
  const block = await blockOf(
    createHeartRateContributor(() => Promise.resolve(given)),
    "2026-10-17",
  );
  const inputs = probeContributor({
    id: "heart_rate_profile",
    block,
    fixture: profile,
    calculated: [],
    fixed: ["0.7|other", "10|bpm", "2001|", "208|other", "28|d"],
  });
  for (const side of [inputs.ground, inputs.athleteGround!]) {
    // 208 - 0.7 x age is the formula Tracend uses, not the athlete's maximum.
    assertEquals(ungroundedNumbers("Your maximum heart rate is 208 bpm.", side), ["208"]);
  }
});

Deno.test("screening: the day it was answered grounds; the rules and their figures do not", async () => {
  const record = { outcome: "moderate_until_cleared" as const, screenedAt: "2026-10-09T08:00:00Z" };
  const block = await blockOf(createScreeningContributor(() => Promise.resolve(record)));
  probeContributor({
    id: "screening",
    block,
    fixture: record,
    calculated: [],
    fixed: ["3|other"],
  });
});

const memoryRpc = (facts: unknown[], notes: unknown[]): ServiceRpc => () =>
  Promise.resolve({
    data: { schema_version: "1.0", local_date: "2026-10-18", facts, notes },
    error: null,
  });

Deno.test("confirmed facts: the athlete's statement and its dates ground; the id in brackets does not", async () => {
  const fact = makeFact(
    "injury_limitation",
    "knee",
    "Left knee hurts on deep squats, about 6 weeks now",
    { reconfirmOn: "2026-10-01" },
  );
  const wire = factWire(fact);
  const block = await blockOf(
    createConfirmedFactsContributor(createMemorySource(memoryRpc([wire], []))),
  );
  const inputs = probeContributor({
    id: "confirmed_facts",
    block,
    fixture: { statement: fact.statement },
    calculated: [],
    fixed: ["0|", "1|", "4000|", "8000|"],
  });
  assertEquals(
    ungroundedNumbers("You told me the pain began about 6 weeks ago.", inputs.athleteGround!),
    [],
  );
  // The fact's id is for the suggestions only; a number inside it is not data.
  const digits = numberGroundOf([`[${fact.id}]`]).values.filter((given) => given.value > 100);
  assert(digits.length > 0);
  for (const given of digits) {
    assert(
      !inputs.athleteGround!.values.some((have) => have.value === given.value),
      `${given.value}`,
    );
  }
});

Deno.test("Coach's notes: only a note's dates ground; a figure inside a note does not", async () => {
  const notes = [{
    id: "n1",
    entry_kind: "conversation",
    note_date: "2026-10-12",
    summary: "Asked about training 5 days a week at 85 kg.",
  }, {
    id: "n2",
    entry_kind: "advice",
    note_date: "2026-10-05",
    summary: "Suggested 4 sessions.",
    follow_through: { status: "partly", checked_on: "2026-10-12", detail: "2 of 4 sessions" },
  }];
  const block = await blockOf(
    createCoachNotesContributor(createMemorySource(memoryRpc([], notes))),
  );
  const inputs = probeContributor({
    id: "coach_notes",
    block,
    fixture: {},
    calculated: [],
    fixed: ["2|other", "4|other", "5|d", "85|kg"],
  });
  for (const side of [inputs.ground, inputs.athleteGround!]) {
    assertEquals(ungroundedNumbers("You train 5 days a week at 85 kg.", side), ["85"]);
  }
  assertEquals(
    ungroundedNumbers("My notes say we spoke on 2026-10-12.", inputs.athleteGround!),
    [],
  );
});

Deno.test("proposals: dates ground as records; a proposal's title and figures ground only as the proposal's", async () => {
  const payload = {
    schema_version: "1.1",
    local_date: "2026-10-17",
    block: { title: "12-week deload", kind: "deload", ends_on: "2026-10-24" },
    phase: { phase: "cut", started_on: "2026-08-04", ends_on: "2026-11-30" },
    proposals: [
      {
        kind: "nutrition_targets",
        title: "Raise intake to 2350 kcal",
        status: "pending",
        created_on: "2026-10-17",
        expires_at: "2026-10-24T08:00:00Z",
        ends_on: null,
        figures: { calories: 2350, protein_g: 165, sessions_per_week: 5 },
      },
      {
        kind: "training_schedule",
        title: "Train 4 days",
        status: "accepted",
        created_on: "2026-09-02",
        expires_at: null,
        ends_on: "2026-09-30",
        figures: null,
      },
    ],
  };
  const block = await blockOf(
    createProposalsContributor(() => Promise.resolve(payload)),
    "2026-10-17",
  );
  const inputs = probeContributor({
    id: "coach_proposals",
    block,
    fixture: payload,
    calculated: [],
    fixed: [],
  });
  // The running block's title is the athlete's approved plan: a record, unlike a pending title.
  assertEquals(ungroundedNumbers("You are on a 12-week deload.", inputs.athleteGround!), []);
  assertEquals(ungroundedNumbers("The proposal sets 2350 kcal.", inputs.ground), []);
  assertEquals(ungroundedNumbers("Your target is 2350 kcal.", inputs.athleteGround!), ["2350"]);
});
