import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  coachLookupCatalogue,
  coachLookupNames,
  lookupSpec,
} from "../../coach_lookups/catalogue.ts";
import { coachContextContributorTimeoutMs, renderCoachContext } from "../host.ts";
import {
  ageText,
  coverageBriefBudgetChars,
  coverageBriefReadTimeoutMs,
  coverageDomains,
  createCoverageBriefContributor,
  renderCoverageBrief,
} from "./coverage_brief.ts";

const domain = (first: string, last: string, count: number) => ({ first, last, count });
const none = { first: null, last: null, count: 0 };
const today = "2026-10-20";
const payload = {
  schema_version: "1.2",
  local_date: today,
  schedule: { version: 3, starts_on: "2026-09-28", weekdays: [1, 2, 3, 4, 5, 6] },
  domains: {
    workouts: domain("2026-06-03", "2026-10-19", 61),
    meals: domain("2026-06-10", "2026-10-20", 90),
    body: domain("2026-06-03", "2026-10-16", 40),
    check_ins: domain("2026-07-01", "2026-10-20", 70),
    recovery: domain("2026-06-01", "2026-10-20", 120),
    plan_history: domain("2026-06-03", "2026-09-01", 3),
    goals: domain("2026-06-03", "2026-06-03", 1),
    weekly_reviews: none,
    health_history: domain("2025-10-01", "2026-09-01", 12),
    watch_workouts: domain("2026-05-01", "2026-10-19", 55),
    proposals: domain("2026-09-01", "2026-10-15", 4),
    daily_decisions: domain("2026-08-01", "2026-10-20", 60),
    past_messages: domain("2026-09-01", "2026-10-20", 30),
  },
};

// The keys get_coach_data_index_v1 reports under `domains` (migration 20261020100017, checked in
// supabase/tests/database/coach_investigation_test.sql).
const indexKeys = Object.keys(payload.domains);

const lines = (text: string) => text.split("\n").filter((line) => line.startsWith("- "));

Deno.test("the brief has one line per kind of record, in a fixed shape, and covers the plan ahead, watch workouts, proposals and notes", () => {
  const text = renderCoverageBrief(payload, today);
  assertEquals(lines(text).length, coverageDomains.length);
  for (const line of lines(text)) {
    // kind | what the context shows | what a lookup adds | what exists | neighbours
    assertEquals(line.slice(2).split(" | ").length, 5, line);
  }
  const ids = coverageDomains.map((item) => item.id);
  for (
    const id of [
      "training",
      "plan_ahead",
      "recovery",
      "check_ins",
      "body",
      "nutrition",
      "goals",
      "proposals",
      "decisions",
      "watch_workouts",
      "conversation",
    ]
  ) {
    assert(ids.includes(id), id);
  }
  assertStringIncludes(text, "- training | 28 d session totals (no sets, loads, notes)");
  assertStringIncludes(text, "(every set with load, reps, swaps)");
});

Deno.test("each line says what exists and how fresh it is", () => {
  const text = renderCoverageBrief(payload, today);
  assertStringIncludes(text, "61 sessions 2026-06-03..2026-10-19, last 1 d ago");
  assertStringIncludes(text, "120 days 2026-06-01..2026-10-20, last today");
  assertStringIncludes(text, "40 weigh-in days 2026-06-03..2026-10-16, last 4 d ago");
  assertStringIncludes(text, "55 workouts 2026-05-01..2026-10-19, last 1 d ago");
  assertStringIncludes(text, "1 goals 2026-06-03, last 139 d ago");
  assertStringIncludes(text, "repeats Mon Tue Wed Thu Fri Sat since 2026-09-28");
  assertStringIncludes(text, "| weekly_reviews | none yet |");
  assertEquals(ageText("2026-10-20", today), "today");
  assertEquals(ageText("2026-10-19", today), "1 d ago");
  assertEquals(ageText("2026-10-10", today), "10 d ago");
});

Deno.test("the brief is compact: the full one fits the budget, and so does one with no index", () => {
  const full = renderCoverageBrief(payload, today);
  assert(full.length <= coverageBriefBudgetChars, `${full.length} characters`);
  // About 2,000 to 2,600 characters, against the 1,900 of the data index it replaces.
  assert(full.length > 1_800 && full.length < 2_700, `${full.length} characters`);
  const unreadable = renderCoverageBrief(null, today);
  assert(unreadable.length <= coverageBriefBudgetChars);
  // Worst case: every count at six digits and every span two full dates.
  const wide = Object.fromEntries(
    Object.keys(payload.domains).map((key) => [key, domain("2025-01-01", "2026-10-20", 999_999)]),
  );
  const widest = renderCoverageBrief({ ...payload, domains: wide }, today);
  assert(widest.length <= coverageBriefBudgetChars, `${widest.length} characters`);
});

Deno.test("an unreadable or missing index still shows the map, with the counts marked unavailable", () => {
  for (const bad of [null, undefined, { schema_version: "9" }, "oops"]) {
    const text = renderCoverageBrief(bad, today);
    assertEquals(lines(text).length, coverageDomains.length);
    assertStringIncludes(text, "counts unavailable");
    assertStringIncludes(text, "recovery, check_ins, plan_ahead, nutrition");
  }
});

Deno.test("the neighbour map is a static table: the same text whatever the question, for the same records", async () => {
  const contributor = createCoverageBriefContributor(() => Promise.resolve(payload));
  const first = await contributor.render({
    userId: "u",
    question: "check my training",
    localDate: today,
  });
  const second = await contributor.render({ userId: "u", question: "hi", localDate: today });
  assertEquals(first, second);
  assertEquals(first, renderCoverageBrief(payload, today));
});

Deno.test("a failing index read leaves the static brief, not nothing", async () => {
  const contributor = createCoverageBriefContributor(() => Promise.reject(new Error("down")));
  const context = await renderCoachContext([contributor], {
    userId: "u",
    question: "q",
    localDate: today,
  });
  assertEquals(context.outcomes[0].outcome, "rendered");
  assertStringIncludes(context.volatile, "counts unavailable");
});

Deno.test("every neighbour is a kind in the table, none names itself, and each kind has at least two", () => {
  const ids = new Set(coverageDomains.map((item) => item.id));
  assertEquals(ids.size, coverageDomains.length);
  for (const item of coverageDomains) {
    assert(item.also.length >= 2, item.id);
    assertEquals(item.also.includes(item.id), false, item.id);
    assertEquals(new Set(item.also).size, item.also.length, item.id);
    for (const neighbour of item.also) assert(ids.has(neighbour), `${item.id}: ${neighbour}`);
  }
});

Deno.test("every lookup the brief names is in the catalogue, and every catalogue lookup is reachable from a kind", () => {
  for (const item of coverageDomains) {
    assert(item.lookups.length > 0, item.id);
    for (const reach of item.lookups) {
      const spec = lookupSpec(reach.lookup);
      assert(spec, `${item.id}: ${reach.lookup}`);
      if (reach.filter) {
        // A filter the brief names is one the catalogue explains.
        assertStringIncludes(spec.filterMeaning, reach.filter);
        assertStringIncludes(item.adds, `filter ${reach.filter}`);
      }
      assertStringIncludes(item.adds, reach.lookup);
    }
  }
  const reached = new Set(coverageDomains.flatMap((item) => item.lookups.map((r) => r.lookup)));
  for (const name of coachLookupNames) assert(reached.has(name), `${name} is not reachable`);
  // The four filters that reach the newer kinds are each named by exactly one kind.
  for (const filter of ["schedule", "proposals", "workouts", "decisions"]) {
    assertEquals(
      coverageDomains.filter((item) => item.lookups.some((r) => r.filter === filter)).length,
      1,
      filter,
    );
  }
  assertEquals(coachLookupCatalogue.length, 11);
});

Deno.test("the index keys the brief counts all exist in the index the database reports", () => {
  for (const item of coverageDomains) {
    for (const key of item.index) assert(indexKeys.includes(key), `${item.id}: ${key}`);
  }
  // Every key the index reports is counted by some kind, so a new record kind is not silently dropped.
  const counted = new Set(coverageDomains.flatMap((item) => item.index));
  for (const key of indexKeys) assert(counted.has(key), key);
});

Deno.test("a slow index read leaves the static brief inside the host's limit, not nothing", async () => {
  const hanging = createCoverageBriefContributor(() => new Promise(() => {}), 20);
  const context = await renderCoachContext([hanging], {
    userId: "u",
    question: "q",
    localDate: today,
  }, 500);
  assertEquals(context.outcomes[0].outcome, "rendered");
  assertStringIncludes(context.volatile, "counts unavailable");
  assert(coverageBriefReadTimeoutMs < coachContextContributorTimeoutMs);
});
