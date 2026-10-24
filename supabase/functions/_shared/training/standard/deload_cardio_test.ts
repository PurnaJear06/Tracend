// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import cardioFixture from "../../../../../test/contract/fixtures/training_guidance_v1_1.json" with {
  type: "json",
};
import withheldFixture from "../../../../../test/contract/fixtures/training_guidance_v1_1_withheld.json" with {
  type: "json",
};
import olderFixture from "../../../../../test/contract/fixtures/training_guidance_v1_0.json" with {
  type: "json",
};
import { parseTrainingGuidance } from "../guidance/payload.ts";
import { readinessEasyCardioMinutes } from "../readiness/rules.ts";
import * as proposalTraining from "../../coach_proposals/training.ts";
import * as joints from "../joints/rules.ts";
import * as readinessRules from "../readiness/rules.ts";
import { cardioRulesJson, cardioTypes } from "./cardio.ts";
import * as deloadRules from "./deload.ts";
import { deloadRulesJson } from "./deload.ts";
import * as progression from "./progression.ts";

const read = (name: string) =>
  Deno.readTextFile(new URL(`../../../../migrations/${name}`, import.meta.url));
const deloads = await read("20261024060125_deloads.sql");
const cardio = await read("20261024060225_cardio_dosing.sql");
const readiness = await read("20261023140024_day_adjustments.sql");

const code = (sql: string) =>
  sql.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n");

const literal = (sql: string, name: string) => {
  const match = sql.match(
    new RegExp(
      `create function private\\.${name}\\(\\)[^$]*\\$\\$\\s*select '(\\{.*?\\})'::jsonb;`,
      "s",
    ),
  );
  assert(match, `${name} literal found`);
  return JSON.parse(match[1]);
};

// The rules run in SQL; these tests keep the TypeScript numbers and the migrations from drifting.
Deno.test("the deload rules in the migration are the sourced values", () => {
  assertEquals(literal(deloads, "deload_rules"), JSON.parse(JSON.stringify(deloadRulesJson())));
});

Deno.test("the cardio rules in the migration are the sourced values", () => {
  assertEquals(literal(cardio, "cardio_rules"), JSON.parse(JSON.stringify(cardioRulesJson())));
});

Deno.test("the weekly row and the easy-cardio day card quote one dose", () => {
  const dose = readinessEasyCardioMinutes.value;
  assertEquals([...(literal(cardio, "cardio_rules").easy_minutes as number[])], [...dose]);
  assertEquals([...(literal(readiness, "readiness_rules").easy_cardio_minutes as number[])], [
    ...dose,
  ]);
});

Deno.test("every cardio workout name is an upper-case plugin name, once", () => {
  const names = cardioTypes.value;
  assertEquals(new Set(names).size, names.length);
  for (const name of names) assert(/^[A-Z][A-Z_]+$/.test(name), name);
  // Strength, sports and 'other' are never cardio.
  for (
    const excluded of ["TRADITIONAL_STRENGTH_TRAINING", "FUNCTIONAL_STRENGTH_TRAINING", "OTHER"]
  ) {
    assert(!names.includes(excluded), excluded);
  }
});

Deno.test("only the cardio rules may read heart rate (D9)", () => {
  const heart = /heart|bpm|hrv|resting_|pulse|acwr|monotony|strain_/i;
  assert(!heart.test(code(deloads)), "the deload SQL reads no heart signal");
  // Every sourced value, with the reasoning written beside it, outside the cardio rules.
  for (const rules of [deloadRules, readinessRules, joints, progression]) {
    for (const value of Object.values(rules)) {
      if (typeof value === "function") continue;
      assert(!heart.test(JSON.stringify(value)), JSON.stringify(value).slice(0, 80));
    }
  }
  // The cardio week reads no heart-derived measure either: heart rate enters as a share of reserve
  // the app turns into beats per minute, never as a stored reading.
  assert(
    !/resting_heart|hrv|daily_computed_metrics|recovery_score|bpm/i.test(code(cardio)),
    "the cardio SQL reads no heart reading and no recovery score",
  );
});

Deno.test("the migrations only add: new functions, one function replaced, nothing dropped or edited", () => {
  for (const sql of [code(deloads), code(cardio)]) {
    assert(!/\b(drop|alter|truncate)\b/i.test(sql), "no drop, alter or truncate");
    assert(!/\b(insert into|update|delete from)\b/i.test(sql), "no data is written");
  }
  const created = (sql: string) =>
    [...code(sql).matchAll(/create (?:or replace )?function ((?:private|public)\.\w+)\(/g)]
      .map((m) => m[1]);
  assertEquals(created(deloads), [
    "private.deload_rules",
    "private.is_deload_proposal",
    "private.readiness_band_on",
    "private.deload_signals",
    "private.training_guidance",
    "public.get_my_training_guidance_v1",
    "public.get_training_guidance_for_v1",
  ]);
  assertEquals(created(cardio), [
    "private.cardio_rules",
    "private.cardio_week",
    "private.training_guidance",
  ]);
  // The one replaced function is B5-3's own; the cardio migration touches no earlier function.
  assertEquals([...cardio.matchAll(/create or replace function ([\w.]+)\(/g)].map((m) => m[1]), [
    "private.training_guidance",
  ]);
});

Deno.test("every function is owner-run with an empty search path and granted to the right role only", () => {
  for (const sql of [deloads, cardio]) {
    const functions = [
      ...code(sql).matchAll(
        /create (?:or replace )?function ((?:private|public)\.\w+)\(/g,
      ),
    ];
    for (const [, name] of functions) {
      assert(
        new RegExp(`revoke all on function ${name.replace(".", "\\.")}\\(`).test(sql),
        `${name} is revoked from every role`,
      );
    }
    const bodies = code(sql).split(/create (?:or replace )?function /).slice(1);
    for (const body of bodies) {
      assert(
        /set search_path = ''/.test(body.split("$$")[0]),
        `search_path pinned: ${body.slice(0, 50)}`,
      );
    }
  }
  assert(
    deloads.includes(
      "grant execute on function public.get_my_training_guidance_v1(date) to authenticated;",
    ),
  );
  assert(
    deloads.includes(
      "grant execute on function public.get_training_guidance_for_v1(uuid, date) to service_role;",
    ),
  );
  assert(!/grant execute[^;]*private\./.test(deloads + cardio), "no private function is granted");
  for (const name of ["get_my_training_guidance_v1", "get_training_guidance_for_v1"]) {
    assert(
      new RegExp(
        `function public\\.${name}\\([^)]*\\)\\s*returns jsonb language plpgsql stable security definer`,
      )
        .test(deloads),
      `${name} is stable and runs as its owner`,
    );
  }
  // The two readers are B5-3's and B5-4 does not redefine them: they return what the builder returns.
  assert(!cardio.includes("function public."), "B5-4 defines no public function");
});

const between = (sql: string, start: string, end: string) => {
  const from = sql.indexOf(start);
  assert(from >= 0, `found ${start}`);
  return sql.slice(from, sql.indexOf(end, from) + end.length);
};

// private.training_guidance 1.1 is the B5-3 function plus these hunks, so the deload part, the
// safety-route rule and the shape of everything else cannot have changed.
Deno.test("training_guidance 1.1 is B5-3's function plus the cardio hunks only", () => {
  const original = between(deloads, "create function private.training_guidance", "end $$;");
  const redefined = between(
    cardio,
    "create or replace function private.training_guidance",
    "end $$;",
  );
  const hunks: readonly (readonly [string, string])[] = [
    ["create or replace function", "create function"],
    [
      `  deload jsonb := private.deload_signals(p_user, p_date);
  withheld text := case when route is not null then 'safety_route'
    when private.current_screening_outcome(p_user) = 'see_professional' then 'screening' end;
`,
      `  deload jsonb := private.deload_signals(p_user, p_date);
`,
    ],
    [
      `  return jsonb_build_object('schema_version', '1.1', 'local_date', p_date,
    'safety_route', route, 'deload', deload, 'cardio_withheld', withheld,
    'cardio_week', case when withheld is null
      then private.cardio_week(p_user, p_date, adjustment ->> 'band') end);`,
      `  return jsonb_build_object('schema_version', '1.0', 'local_date', p_date,
    'safety_route', route, 'deload', deload);`,
    ],
  ];
  let undone = redefined;
  for (const [added, was] of hunks) {
    assert(undone.includes(added), `missing hunk: ${added.slice(0, 60)}`);
    undone = undone.replace(added, () => was);
  }
  assertEquals(undone.trim(), original.trim());
  assertNotEquals(redefined.trim(), original.trim());
});

Deno.test("the guidance reads the day's safety route from the day adjustment, never decides one itself", () => {
  const body = between(deloads, "create function private.training_guidance", "end $$;");
  assert(body.includes("private.day_adjustment_compute(p_user, p_date, true) -> 'payload'"));
  assert(body.includes("adjustment ->> 'safety_route'"));
  // A day with a route turns a suggestion into not_due and nothing else.
  assert(body.includes("if route is not null and deload ->> 'status' = 'suggested' then"));
});

Deno.test("no deload rule is kept in the proposal builder any more", () => {
  assert(!("deloadRules" in proposalTraining), "the old in-house numbers are gone");
  assertEquals(Object.keys(deloadRules).includes("deloadSetFraction"), true);
});

Deno.test("the contract fixtures parse and say what they say", () => {
  const full = parseTrainingGuidance(cardioFixture);
  assert(full);
  assertEquals(full.deload.status, "suggested");
  assertEquals(full.deload.reasons, ["performance_drop", "run_down"]);
  assertEquals(
    [full.cardioWeek?.doneMin, full.cardioWeek?.targetMin, full.cardioWeek?.stretchMax],
    [
      85,
      150,
      300,
    ],
  );
  const withheld = parseTrainingGuidance(withheldFixture);
  assertEquals(
    [
      withheld?.safetyRoute,
      withheld?.cardioWithheld,
      withheld?.cardioWeek,
      withheld?.deload.status,
    ],
    ["clinician_today", "safety_route", null, "not_due"],
  );
  const older = parseTrainingGuidance(olderFixture);
  assertEquals([older?.schemaVersion, older?.deload.status, older?.cardioWeek], [
    "1.0",
    "running",
    null,
  ]);
});

Deno.test("a payload that is not exactly the shape yields nothing", () => {
  const base = () => JSON.parse(JSON.stringify(cardioFixture));
  const broken: [string, (j: Record<string, any>) => void][] = [
    ["another major version", (j) => (j.schema_version = "2.0")],
    ["a bad date", (j) => (j.local_date = "yesterday")],
    ["an unknown route", (j) => (j.safety_route = "rest")],
    ["an unknown deload status", (j) => (j.deload.status = "maybe")],
    ["an unknown reason", (j) => (j.deload.reasons = ["tired"])],
    ["a suggestion with no reason", (j) => (j.deload.reasons = [])],
    ["a suggestion that is suppressed", (j) => (j.deload.suppressed_by = "recent_deload")],
    [
      "a suggestion with a proposal",
      (j) => (j.deload.proposal_id = "00000000-0000-4000-8000-000000000002"),
    ],
    ["a pending status with no proposal", (j) => (j.deload.status = "pending")],
    ["a bad proposal id", (j) => (j.deload.proposal_id = "nope")],
    ["a negative week count", (j) => (j.deload.weeks_since = -1)],
    ["a suggestion on a day with a safety route", (j) => (j.safety_route = "urgent")],
    ["a cardio week and a withheld reason", (j) => (j.cardio_withheld = "screening")],
    ["no cardio week and no reason", (j) => (j.cardio_week = null)],
    ["a mistyped minute count", (j) => (j.cardio_week.done_min = "85")],
    ["a missing key of the week", (j) => delete j.cardio_week.window_to],
    ["an upper figure at the floor", (j) => (j.cardio_week.stretch_max = 150)],
    ["hard cardio with no weekly allowance", (j) => (j.cardio_week.vigorous_sessions_max = 0)],
    ["a reserve over 100", (j) => (j.cardio_week.easy_hr_reserve_max = 101)],
    ["a window that runs backwards", (j) => (j.cardio_week.window_from = "2026-10-25")],
    ["an intensity that is not a boolean", (j) => (j.cardio_week.intensity_known = "no")],
  ];
  for (const [label, change] of broken) {
    const payload = base();
    change(payload);
    assertEquals(parseTrainingGuidance(payload), null, label);
  }
  const route = JSON.parse(JSON.stringify(withheldFixture));
  route.cardio_withheld = "screening";
  assertEquals(parseTrainingGuidance(route), null, "a safety route that cardio does not honour");
  const free = JSON.parse(JSON.stringify(withheldFixture));
  free.safety_route = null;
  free.cardio_withheld = "screening";
  assert(parseTrainingGuidance(free), "see_professional withholds cardio with no route");
});

Deno.test("keys added by a later schema version are ignored", () => {
  const later = JSON.parse(JSON.stringify(cardioFixture));
  later.schema_version = "1.1";
  later.extra = { anything: true };
  later.deload.extra = 1;
  later.cardio_week.extra = [1];
  assert(parseTrainingGuidance(later));
});
