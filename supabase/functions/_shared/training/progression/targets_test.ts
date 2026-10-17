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
