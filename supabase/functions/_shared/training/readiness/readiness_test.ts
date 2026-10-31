import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import cardioFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_0_cardio.json" with {
  type: "json",
};
import holdFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_0_hold.json" with {
  type: "json",
};
import noneFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_0_none.json" with {
  type: "json",
};
import reduceFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_0_reduce.json" with {
  type: "json",
};
import respondFixture from "../../../../../test/contract/fixtures/respond_to_day_adjustment_v1_0.json" with {
  type: "json",
};
import safetyFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_0_safety.json" with {
  type: "json",
};
import unknownFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_0_unknown.json" with {
  type: "json",
};
import reaskedFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_0_reasked.json" with {
  type: "json",
};
import safetyStartedFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_0_safety_started.json" with {
  type: "json",
};
import { parseDayAdjustment, readinessTriggers } from "./payload.ts";
import { readinessRulesJson } from "./rules.ts";

const migrationPath = (name: string) => new URL(`../../../../migrations/${name}`, import.meta.url);
const migration = await Deno.readTextFile(migrationPath("20261023140024_day_adjustments.sql"));
const code = (sql: string) =>
  sql.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n");

// The rules run in SQL; these tests keep the TypeScript numbers and the migration from drifting.
Deno.test("the migration's rule numbers are the sourced values", () => {
  const literal = migration.match(/select '(\{"version":"readiness-v1".*?\})'::jsonb;/s);
  assert(literal, "readiness_rules literal found");
  assertEquals(JSON.parse(literal[1]), JSON.parse(JSON.stringify(readinessRulesJson())));
});

Deno.test("no rule or word of the readiness SQL reads a heart-rate signal (D9)", () => {
  assert(
    // The training hub's unchanged body (section 11) carries the load ratio for the Train screen.
    !/heart|bpm|hrv|resting_|pulse|acwr|monotony|strain_/i.test(
      code(migration.slice(0, migration.indexOf("-- 11. Training hub 1.8"))),
    ),
    "the migration reads the recovery score only, never a heart signal or a load ratio",
  );
});

Deno.test("the words the athlete reads never diagnose or name a condition", () => {
  const diagnosis = [
    "tendinitis",
    "tendonitis",
    "tendinopathy",
    "sprain",
    "sciatica",
    "disc",
    "meniscus",
    "rotator",
    "impingement",
    "arthritis",
    "fracture",
    "hernia",
    "diagnos",
  ];
  const from = migration.indexOf("create function private.day_adjustment_explanation");
  const to = migration.indexOf("-- 7. Computing the day");
  const words = code(migration.slice(from, to)).toLowerCase();
  for (const word of diagnosis) {
    assert(!new RegExp(`\\b${word}`).test(words), `the sentences name "${word}"`);
  }
  assert(
    !/\b(ai|model|claude|gemini|deepseek|groq|llm)\b/i.test(words),
    "no model or company name",
  );
});

Deno.test("every trigger has words, and the table accepts exactly the codes the rules produce", async () => {
  const table = migration.match(
    /triggers text\[\] not null check \(triggers <@ array\[([^\]]*)\]/s,
  );
  assert(table);
  const stored = [...table[1].matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
  const reasons = migration.match(/codes constant text\[\] := array\[([^\]]*)\]/s);
  assert(reasons);
  const withWords = [...reasons[1].matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
  const phrases = migration.match(/phrases constant text\[\] := array\[(.*?)\];\n/s);
  assert(phrases);
  assertEquals((phrases[1].match(/'(?:[^']|'')+'/g) ?? []).length, withWords.length);
  // Everything else has its own sentence in the explanation: the missing check-in, the athlete who
  // cannot train, a pain of 1 to 3, and the safety route.
  const own = ["not_available", "no_check_in", "pain_mild"];
  assertEquals([...withWords, ...own].sort(), [...stored].sort());
  // The coach-standing-state migration widens the answers' list by exactly the break day's trigger,
  // which has its own sentence in the explanation and no points.
  const standing = await Deno.readTextFile(
    new URL("../../../../migrations/20261101200000_coach_standing_state.sql", import.meta.url),
  );
  const widened = standing.match(
    /add constraint day_adjustments_triggers_check check \(triggers <@ array\[([^\]]*)\]/s,
  );
  assert(widened);
  assertEquals(
    [...widened[1].matchAll(/'([a-z_]+)'/g)].map((match) => match[1]),
    [...stored, "paused"],
  );
  assertEquals([...stored, "pain_severe", "paused"].sort(), [...readinessTriggers].sort());
  const rules = readinessRulesJson().points as Record<string, number>;
  assertEquals(Object.keys(rules).sort(), [...withWords, "pain_mild"].sort());
});

Deno.test("the contract fixtures parse and say what they say", () => {
  const none = parseDayAdjustment(noneFixture);
  assert(none);
  assertEquals([none.kind, none.status, none.band, none.options.length], [
    "none",
    "none",
    "green",
    3,
  ]);
  const hold = parseDayAdjustment(holdFixture);
  assertEquals(hold?.kind, "hold_load");
  assertEquals(hold?.changes[0].loadNote, "Keep last time's 60 kg");
  assertEquals(hold?.changes[1].loadNote, null);
  const reduce = parseDayAdjustment(reduceFixture);
  assertEquals([reduce?.kind, reduce?.setsTotalFrom, reduce?.setsTotalTo], ["reduce_sets", 9, 7]);
  const cardio = parseDayAdjustment(cardioFixture);
  assertEquals([cardio?.kind, cardio?.cardio?.minutesMax, cardio?.setsTotalTo], [
    "swap_to_easy_cardio",
    30,
    0,
  ]);
  const safety = parseDayAdjustment(safetyFixture);
  assertEquals([safety?.safetyRoute, safety?.kind, safety?.options.length], [
    "pain_referral",
    "none",
    0,
  ]);
  const started = parseDayAdjustment(safetyStartedFixture);
  assertEquals([started?.safetyRoute, started?.unavailableReason, started?.kind, started?.status], [
    "pain_referral",
    "session_started",
    "none",
    "none",
  ]);
  const reasked = parseDayAdjustment(reaskedFixture);
  assertEquals(reasked?.previousAnswer?.reason, "check_in");
  const unknown = parseDayAdjustment(unknownFixture);
  assertEquals([unknown?.band, unknown?.confidence, unknown?.signals.recoveryLow], [
    "unknown",
    null,
    true,
  ]);
  const answered = parseDayAdjustment(respondFixture);
  assertEquals([answered?.status, answered?.origin], ["accepted", "proposed"]);
});

Deno.test("a payload that is not exactly the shape yields nothing", () => {
  const mutate = (change: (copy: Record<string, unknown>) => void) => {
    const copy = structuredClone(reduceFixture) as Record<string, unknown>;
    change(copy);
    return parseDayAdjustment(copy);
  };
  assert(mutate(() => {}), "the unchanged fixture parses");
  assertEquals(parseDayAdjustment(null), null);
  assertEquals(parseDayAdjustment([]), null);
  assertEquals(mutate((p) => p.schema_version = "2.0"), null);
  assertEquals(mutate((p) => delete p.signals), null);
  assertEquals(mutate((p) => delete p.options), null);
  assertEquals(mutate((p) => p.kind = "double_sets"), null);
  assertEquals(mutate((p) => p.band = "purple"), null);
  assertEquals(mutate((p) => p.triggers = ["sleep_poor", "sore", "tired"]), null);
  assertEquals(mutate((p) => p.status = "applied"), null);
  assertEquals(mutate((p) => p.status = "none"), null, "a kind in force has a status");
  assertEquals(mutate((p) => p.available = false), null, "unavailable needs a reason");
  assertEquals(mutate((p) => p.unavailable_reason = "holiday"), null);
  assertEquals(mutate((p) => p.safety_route = "pain_referral"), null, "a safety route has no kind");
  assertEquals(mutate((p) => p.sets_total_to = 12), null, "sets never go up");
  assertEquals(mutate((p) => p.cardio = { minutes_min: 20 }), null);
  assertEquals(
    mutate((p) => {
      p.cardio = {
        minutes_min: 20,
        minutes_max: 30,
        effort: "easy",
        talk_test: true,
        vigorous_allowed: false,
      };
    }),
    null,
    "a cardio dose belongs to the easy-cardio kind only",
  );
  assertEquals(
    mutate((p) => {
      (p.changes as Record<string, unknown>[])[0].sets_to = 5;
    }),
    null,
    "a change that adds sets",
  );
  assertEquals(
    mutate((p) => {
      (p.changes as Record<string, unknown>[])[0].sets_to = "3";
    }),
    null,
  );
  assertEquals(
    mutate((p) => {
      delete (p.changes as Record<string, unknown>[])[0].rpe_to;
    }),
    null,
  );
  assertEquals(
    mutate((p) => {
      (p.options as Record<string, unknown>[])[2].cardio = null;
    }),
    null,
    "an easy-cardio option carries its dose",
  );
  const previous = (answer: Record<string, unknown>) =>
    mutate((p) => {
      p.previous_answer = answer;
    });
  assertEquals(previous({ kind: "reduce_sets", status: "maybe", reason: "check_in" }), null);
  assertEquals(previous({ kind: "reduce_sets", status: "accepted" }), null, "no reason given");
  assertEquals(previous({ kind: "reduce_sets", status: "accepted", reason: "whim" }), null);
  assert(previous({ kind: "reduce_sets", status: "accepted", reason: "new_data" }));
  assertEquals(mutate((p) => p.local_date = 20261024), null);
});

Deno.test("keys added by a later schema version are ignored", () => {
  const copy = structuredClone(reduceFixture) as Record<string, unknown>;
  copy.joint_states = [];
  assert(parseDayAdjustment(copy));
});

// A redefined function must be its earlier definition plus the intended hunks and nothing else, so
// the rest of its behaviour is exactly what the earlier migration tested.
function between(text: string, start: string, end: string | null): string {
  const from = text.indexOf(start);
  assert(from >= 0, `missing ${start}`);
  const to = end === null ? text.length : text.indexOf(end, from);
  assert(to > from, `missing ${end}`);
  return text.slice(from, to);
}

function undo(redefined: string, hunks: readonly (readonly [string, string])[]): string {
  let text = redefined;
  for (const [added, was] of hunks) {
    assert(text.includes(added), `missing hunk: ${added.slice(0, 70)}`);
    text = text.replace(added, was);
  }
  return text.trim();
}

Deno.test("progression_decision is B3's function plus the adjusted-session hunks only", async () => {
  const marker = "from public, anon, authenticated;";
  const original = await Deno.readTextFile(migrationPath("20261017140023_progression_targets.sql"));
  const from = original.indexOf("create function private.progression_decision(");
  const b3 = original.slice(
    from,
    original.indexOf(
      marker,
      original.indexOf("revoke all on function private.progression_decision("),
    ) + marker.length,
  );
  const redefinedFrom = migration.indexOf(
    "create or replace function private.progression_decision(",
  );
  const redefined = migration.slice(
    redefinedFrom,
    migration.indexOf(
      marker,
      migration.indexOf("revoke all on function private.progression_decision(", redefinedFrom),
    ) + marker.length,
  );
  const hunks: readonly (readonly [string, string])[] = [
    ["create or replace function", "create function"],
    [
      `       and nullif(s2 ->> 'load_kg', '')::numeric is not distinct from v_load and v_can_lower
       and not coalesce((s1 ->> 'adjusted')::boolean, false)
       and not coalesce((s2 ->> 'adjusted')::boolean, false) then`,
      `       and nullif(s2 ->> 'load_kg', '')::numeric is not distinct from v_load and v_can_lower then`,
    ],
    [
      "elsif v_sets < coalesce((s1 ->> 'sets_planned')::integer, p_set_count) then",
      "elsif v_sets < p_set_count then",
    ],
    [
      `  elsif s3 is not null and v_min_reps < p_rep_max
        and not coalesce((s1 ->> 'adjusted')::boolean, false)
        and not coalesce((s2 ->> 'adjusted')::boolean, false)
        and not coalesce((s3 ->> 'adjusted')::boolean, false)
        and nullif`,
      `  elsif s3 is not null and v_min_reps < p_rep_max
        and nullif`,
    ],
  ];
  assertEquals(undo(redefined, hunks), b3.trim());
});

Deno.test("next_session_targets is the advanced-level definition plus the adjusted-session hunks only", async () => {
  const end = "revoke all on function private.next_session_targets";
  const earlier = between(
    await Deno.readTextFile(migrationPath("20261023100050_advanced_level_catalog.sql")),
    "create or replace function private.next_session_targets",
    end,
  );
  const redefined = between(
    migration,
    "create or replace function private.next_session_targets",
    end,
  );
  const hunks: readonly (readonly [string, string])[] = [
    [
      "s.local_date, s.completed_at, s.id as session_id, p.planned_exercise_id as logged_exercise_id\n",
      "s.local_date, s.completed_at, s.id as session_id\n",
    ],
    ["    pf.pain_flag, pf.logged_exercise_id,\n", "    pf.pain_flag,\n"],
    [
      `    bool_or(t.pain_flag) as pain,
    max(t.logged_exercise_id::text)::uuid as logged_exercise_id
`,
      "    bool_or(t.pain_flag) as pain\n",
    ],
    [
      `), marked as (
  -- Done under an accepted hold_load or reduce_sets answer (B4) and the answer lists this exercise:
  -- not evidence for lowering its load, and its planned set count is the adjusted one. An exercise
  -- the answer left alone is judged as ever, however easy the rest of the session was.
  select s.*, ch.sets_to is not null as adjusted, ch.sets_to as sets_planned
  from sessions s
  join public.workout_sessions ws on ws.id = s.session_id and ws.user_id = p_user
  left join public.day_adjustments a on a.id = ws.day_adjustment_id and a.user_id = p_user
    and a.status = 'accepted' and a.kind in ('hold_load', 'reduce_sets')
  left join lateral (
    select (c ->> 'sets_to')::integer as sets_to from jsonb_array_elements(a.changes) c
    where c ->> 'planned_exercise_id' = s.logged_exercise_id::text limit 1) ch on true
), ranked as (`,
      "), ranked as (",
    ],
    ["  from marked s\n)", "  from sessions s\n)"],
    [
      `      'effort_known', r.effort_known, 'pain', r.pain, 'adjusted', r.adjusted,
      'sets_planned', r.sets_planned) order by r.rn) as sess`,
      "      'effort_known', r.effort_known, 'pain', r.pain) order by r.rn) as sess",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("start_workout is the workout-truth definition plus the day-adjustment hunks only", async () => {
  const earlier = between(
    await Deno.readTextFile(migrationPath("20260711190000_workout_truth_repair.sql")),
    "create or replace function public.start_workout(",
    "create or replace function public.get_my_workout_session(",
  );
  const redefined = between(
    migration,
    "create or replace function public.start_workout(",
    "-- 11. Training hub 1.8",
  );
  const hunks: readonly (readonly [string, string])[] = [
    [
      `declare result_id uuid; version_id uuid; exercise record; performance_id uuid; n integer;
  adjustment public.day_adjustments%rowtype; adjusted boolean := false; set_total integer;
`,
      "declare result_id uuid; version_id uuid; exercise record; performance_id uuid; n integer;\n",
    ],
    [
      `  -- The same lock respond_to_day_adjustment_v1 takes: an answer and a start never interleave.
  perform pg_advisory_xact_lock(hashtextextended(
    'day_adjustment:' || auth.uid()::text || coalesce(p_local_date::text, ''), 0));
`,
      "",
    ],
    [
      `  -- The athlete's accepted answer for today is applied as given (it can only make the day easier);
  -- a start for any other date, from history, gets the plan as written.
  if p_local_date = private.local_date_for(auth.uid()) then
    select * into adjustment from public.day_adjustments a
    where a.user_id=auth.uid() and a.local_date=p_local_date
      and a.planned_workout_id=p_planned_workout_id and a.superseded_at is null
      and a.status='accepted';
    adjusted := found;
  end if;

`,
      "",
    ],
    [
      `    user_id,plan_version_id,planned_workout_id,local_date,timezone,idempotency_key,actual_started_at,
    day_adjustment_id
  ) values(
    auth.uid(),version_id,p_planned_workout_id,p_local_date,p_timezone,p_idempotency_key,now(),
    case when adjusted then adjustment.id end
  )`,
      `    user_id,plan_version_id,planned_workout_id,local_date,timezone,idempotency_key,actual_started_at
  ) values(
    auth.uid(),version_id,p_planned_workout_id,p_local_date,p_timezone,p_idempotency_key,now()
  )`,
    ],
    [
      `    set_total := exercise.set_count;
    if adjusted and adjustment.kind='reduce_sets' then
      select (c ->> 'sets_to')::integer into set_total
      from jsonb_array_elements(adjustment.changes) c
      where c ->> 'planned_exercise_id' = exercise.id::text;
      set_total := coalesce(set_total, exercise.set_count);
    end if;
    for n in 1..set_total loop`,
      "    for n in 1..exercise.set_count loop",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("start_workout takes the answer's lock before it reads anything, with respond's key", () => {
  const start = between(
    migration,
    "create or replace function public.start_workout(",
    "-- 11. Training hub 1.8",
  );
  const respond = between(
    migration,
    "create function public.respond_to_day_adjustment_v1(",
    "revoke all on function public.respond_to_day_adjustment_v1",
  );
  const lock = start.indexOf("pg_advisory_xact_lock");
  assert(lock > 0);
  for (
    const read of ["select w.plan_version_id", "from public.workout_sessions", "day_adjustments a"]
  ) {
    assert(lock < start.indexOf(read), `the lock comes before "${read}"`);
  }
  assert(!start.includes("day_adjustment_compute"), "start never depends on the heavy compute");
  const key = (text: string) =>
    text.match(/'day_adjustment:' \|\| ([a-z.()_]+)::text \|\| ([a-z_.:()' ,]+?), 0\)/);
  assert(
    key(start) && key(respond),
    "both build the key from 'day_adjustment:', the user and the date",
  );
});

Deno.test("the hub 1.8 definition is the 1.7 one with only the schema version changed", async () => {
  const hub = (sql: string) =>
    between(sql, "create or replace function public.get_my_training_hub(", "\n$$;");
  const earlier = hub(
    await Deno.readTextFile(migrationPath("20261017140023_progression_targets.sql")),
  );
  const redefined = hub(migration);
  assertEquals(
    undo(redefined, [["'schema_version','1.8'", "'schema_version','1.7'"]]),
    earlier.trim(),
  );
});
