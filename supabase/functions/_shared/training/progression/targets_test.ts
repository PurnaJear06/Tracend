import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { repsAddedPerSession } from "../standard/progression.ts";
import {
  describeLastSession,
  describeTarget,
  describeTargetPrescription,
  parseProgressionSummary,
} from "./targets.ts";

const migration = new URL(
  "../../../../migrations/20261017140023_progression_targets.sql",
  import.meta.url,
);

function target(overrides: Record<string, unknown> = {}) {
  return {
    planned_exercise_id: "b3400000-0000-4000-8000-000000000001",
    exercise_key: "barbell-bench-press",
    name: "Barbell bench press",
    action: "add_load",
    reason: "top_of_range",
    load_kg: 62.5,
    reps: 5,
    sets: 3,
    confidence: "high",
    basis: {
      last_date: "2026-10-10",
      recent: [{
        local_date: "2026-10-10",
        load_kg: 60,
        sets: 3,
        min_reps: 8,
        total_reps: 24,
        min_rir: 3,
        effort_known: true,
        pain: false,
      }],
    },
    ...overrides,
  };
}

const payload = (targets: unknown[]) => ({ schema_version: "1.0", targets });

Deno.test("a version 1 summary parses into typed targets", () => {
  const [parsed] = parseProgressionSummary(payload([target()]));
  assertEquals(parsed.name, "Barbell bench press");
  assertEquals(parsed.action, "add_load");
  assertEquals(parsed.loadKg, 62.5);
  assertEquals(parsed.recent[0].minReps, 8);
  assertEquals(parsed.recent[0].minRir, 3);
  assertEquals(parsed.lastDate, "2026-10-10");
});

Deno.test("a bodyweight target has no load and a session may lack reps in reserve", () => {
  const [parsed] = parseProgressionSummary(payload([target({
    load_kg: null,
    confidence: "low",
    basis: {
      last_date: "2026-10-10",
      recent: [{ local_date: "2026-10-10", load_kg: null, sets: 2, min_reps: 12, min_rir: null }],
    },
  })]));
  assertEquals(parsed.loadKg, null);
  assertEquals(parsed.recent[0].minRir, null);
  assertEquals(describeTargetPrescription(parsed), "5 reps, 3 sets");
});

Deno.test("anything that is not the expected shape yields no targets", () => {
  assertEquals(parseProgressionSummary(null), []);
  assertEquals(parseProgressionSummary({ schema_version: "2.0", targets: [target()] }), []);
  assertEquals(parseProgressionSummary({ schema_version: "1.0" }), []);
  assertEquals(parseProgressionSummary(payload([])), []);
  assertEquals(parseProgressionSummary(payload([target({ action: "double_load" })])), []);
  assertEquals(parseProgressionSummary(payload([target({ reps: "5" })])), []);
  assertEquals(parseProgressionSummary(payload([target({ confidence: "certain" })])), []);
  assertEquals(
    parseProgressionSummary(payload([target({ basis: { last_date: "x", recent: [] } })])),
    [],
  );
});

Deno.test("one malformed row discards the summary rather than half-reading it", () => {
  assertEquals(parseProgressionSummary(payload([target(), target({ name: 7 })])), []);
});

Deno.test("targets read as plain sentences with the evidence they rest on", () => {
  const [parsed] = parseProgressionSummary(payload([target()]));
  assertEquals(describeTargetPrescription(parsed), "62.5 kg x 5 reps, 3 sets");
  assertEquals(describeLastSession(parsed), "2026-10-10: 60 kg, 3 sets, fewest reps 8");
  const line = describeTarget(parsed);
  assertStringIncludes(line, "Barbell bench press: 62.5 kg x 5 reps, 3 sets; add load");
  assertStringIncludes(line, "Last logged 2026-10-10");
  assert(!line.includes("not logged"));
});

Deno.test("a target built without reps in reserve says so", () => {
  const [parsed] = parseProgressionSummary(payload([target({ confidence: "low" })]));
  assertStringIncludes(describeTarget(parsed), "(reps in reserve were not logged)");
});

Deno.test("every reason has words for a hold and for a lowering", () => {
  const reasons = [
    "top_of_range",
    "within_range",
    "top_no_step",
    "incomplete",
    "effort",
    "below_range",
    "stall",
    "away",
    "skipped",
    "pain",
  ];
  for (const reason of reasons) {
    for (const action of ["hold", "lower"]) {
      const [parsed] = parseProgressionSummary(payload([target({ reason, action })]));
      assert(parsed, `${reason}/${action} parses`);
      assert(describeTarget(parsed).length > 40, `${reason}/${action} has words`);
    }
  }
});

// The rules run in SQL; these tests keep the TypeScript side and the migration from drifting.
Deno.test("the migration's rule numbers match the standard and the documented values", async () => {
  const sql = await Deno.readTextFile(migration);
  const literal = sql.match(/select '(\{"hold_after_gap_days".*?\})'::jsonb;/s);
  assert(literal, "progression_rules literal found");
  const rules = JSON.parse(literal[1]);
  assertEquals(rules, {
    hold_after_gap_days: 14,
    lower_after_gap_days: 28,
    lookback_days: 180,
    reps_added_per_session: repsAddedPerSession.value,
  });
});

Deno.test("the targets read no heart rate (D9)", async () => {
  const code = (await Deno.readTextFile(migration)).split("\n")
    .filter((line) => !line.trim().startsWith("--")).join("\n");
  assert(!/heart|bpm|hr_/i.test(code), "no heart-rate field in the progression SQL");
});

Deno.test("the hub keeps every 1.6 line and adds only the schema version and next_targets", async () => {
  const sql = await Deno.readTextFile(migration);
  const previous = await Deno.readTextFile(
    new URL(
      "../../../../migrations/20261004090000_exercise_muscle_references.sql",
      import.meta.url,
    ),
  );
  const body = (text: string) =>
    text.slice(text.indexOf("create or replace function public.get_my_training_hub"));
  const before = body(previous).split("\n");
  const after = body(sql).split("\n");
  const removed = before.filter((line) => !after.includes(line));
  const added = after.filter((line) => !before.includes(line));
  assertEquals(removed.map((line) => line.trim()), [
    "'schema_version','1.6','period_days',greatest(7,least(period_days,365)),",
    "'daily_load',private.daily_load(auth.uid(),private.local_date_for(auth.uid()))",
  ]);
  assertEquals(added.map((line) => line.trim()), [
    "'schema_version','1.7','period_days',greatest(7,least(period_days,365)),",
    "'daily_load',private.daily_load(auth.uid(),private.local_date_for(auth.uid())),",
    "'next_targets',private.next_session_targets(auth.uid())",
  ]);
});

Deno.test("an assisted target reads as help, and its reasons are about help", () => {
  const [assisted] = parseProgressionSummary(payload([target({
    exercise_key: "assisted-pull-up",
    name: "Assisted pull-up",
    load_kg: 15,
    reps: 6,
    sets: 2,
  })]));
  assertEquals(describeTargetPrescription(assisted), "15 kg help x 6 reps, 2 sets");
  assertStringIncludes(describeTarget(assisted), "the help is reduced by one step");
  assertStringIncludes(describeLastSession(assisted), "60 kg help");
  const [unassisted] = parseProgressionSummary(payload([target({
    exercise_key: "assisted chin-up",
    name: "Assisted chin-up",
    action: "hold",
    reason: "top_no_step",
    load_kg: 0,
  })]));
  assertEquals(describeTargetPrescription(unassisted), "unassisted, 5 reps, 3 sets");
  const [lowered] = parseProgressionSummary(payload([target({
    exercise_key: "assisted-pull-up",
    action: "lower",
    reason: "stall",
  })]));
  assertStringIncludes(describeTarget(lowered), "the help goes up one step");
});

// The advanced level planned one lift on a heavy and a light day, and a weighted pull-up logs added
// load, so the function was redefined. Plans without such a repeat and exercises without added load
// must keep today's targets: the redefinition is B3's text plus exactly these hunks.
Deno.test("the redefined next_session_targets is B3's function plus the range split and added load only", async () => {
  const body = (sql: string, start: string) => {
    const from = sql.indexOf(start);
    return sql.slice(
      from,
      sql.indexOf("revoke all on function private.next_session_targets", from),
    );
  };
  const original = body(
    await Deno.readTextFile(migration),
    "create function private.next_session_targets",
  );
  const redefined = body(
    await Deno.readTextFile(
      new URL(
        "../../../../migrations/20261023100050_advanced_level_catalog.sql",
        import.meta.url,
      ),
    ),
    "create or replace function private.next_session_targets",
  );
  const hunks: readonly (readonly [string, string])[] = [
    ["create or replace function", "create function"],
    [
      `    c.load_step_kg as step_kg,
    coalesce(c.added_load, false) as added_load,
    -- The same lift planned more than once with different rep ranges (an advanced plan's heavy
    -- and light days): each range keeps its own history, so a heavy 100 kg x 9 is never read
    -- as a light day's 100 kg x 10.
    e.exercise_slug is not null and exists (
      select 1 from public.planned_exercises o
      join public.planned_workouts ow on ow.id = o.planned_workout_id and ow.user_id = o.user_id
      where ow.plan_version_id = v.id and o.user_id = e.user_id
        and o.exercise_slug = e.exercise_slug
        and (o.rep_min, o.rep_max) is distinct from (e.rep_min, e.rep_max)) as split_range
`,
      "    c.load_step_kg as step_kg\n",
    ],
    ["pl.assisted, pl.added_load, p.id as performance_id", "pl.assisted, p.id as performance_id"],
    [
      `  where ((pl.exercise_slug is not null and p.exercise_slug = pl.exercise_slug)
    or (pl.exercise_slug is not null and p.exercise_slug is null
        and p.performance_kind = 'prescribed'
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.catalog_name_key)
    or (pl.exercise_slug is null and p.exercise_slug is null
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.name_key))
    -- A lift planned with several ranges counts only the performances logged against a planned
    -- exercise with this range, whichever plan version it came from.
    and (not pl.split_range
      or (pe.rep_min is not distinct from pl.rep_min and pe.rep_max is not distinct from pl.rep_max))
`,
      `  where (pl.exercise_slug is not null and p.exercise_slug = pl.exercise_slug)
    or (pl.exercise_slug is not null and p.exercise_slug is null
        and p.performance_kind = 'prescribed'
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.catalog_name_key)
    or (pl.exercise_slug is null and p.exercise_slug is null
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.name_key)
`,
    ],
    [
      `    -- Assisted: the load is machine help and 0 is unassisted, so it is kept. Added load (a weighted
    -- pull-up): the load is the weight added to the body, so no load and 0 both mean none added,
    -- a real starting point for the first step.
    case when pf.assisted then es.load_kg
      when pf.added_load then coalesce(es.load_kg, 0)
      else nullif(es.load_kg, 0) end as load_kg,`,
      `    -- Assisted: the load is machine help and 0 is unassisted, so it is kept.
    case when pf.assisted then es.load_kg else nullif(es.load_kg, 0) end as load_kg,`,
    ],
  ];
  let undone = redefined;
  for (const [added, was] of hunks) {
    assert(undone.includes(added), `missing hunk: ${added.slice(0, 60)}`);
    undone = undone.replace(added, was);
  }
  assertEquals(undone.trim(), original.trim());
});
