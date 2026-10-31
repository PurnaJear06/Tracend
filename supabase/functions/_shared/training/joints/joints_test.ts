import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import ninetyReduce from "../../../../../test/contract/fixtures/day_adjustment_v1_0_reduce.json" with {
  type: "json",
};
import ninetySafety from "../../../../../test/contract/fixtures/day_adjustment_v1_0_safety.json" with {
  type: "json",
};
import jointFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_1_joint.json" with {
  type: "json",
};
import painFixture from "../../../../../test/contract/fixtures/pain_check_v1_0.json" with {
  type: "json",
};
import redFlagFixture from "../../../../../test/contract/fixtures/day_adjustment_v1_1_red_flag.json" with {
  type: "json",
};
import { parseDayAdjustment } from "../readiness/payload.ts";
import {
  painAreas,
  painOutcomes,
  painPatterns,
  questionsFor,
  redFlagCodes,
  redFlagQuestions,
} from "./red_flags.ts";
import { jointRulesJson, painRulesJson, rangeNotes, redFlagOutcomes } from "./rules.ts";

const migrationPath = (name: string) => new URL(`../../../../migrations/${name}`, import.meta.url);
const migration = await Deno.readTextFile(migrationPath("20261024060025_pain_checks.sql"));
const code = (sql: string) =>
  sql.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n");

const diagnosis = [
  "tendinitis",
  "tendonitis",
  "tendinopathy",
  "tendon",
  "sprain",
  "sciatica",
  "disc",
  "meniscus",
  "ligament",
  "cartilage",
  "rotator",
  "impingement",
  "arthritis",
  "bursitis",
  "fracture",
  "hernia",
  "diagnos",
];
const noDiagnosis = (words: string, where: string) => {
  for (const word of diagnosis) {
    assert(!new RegExp(`\\b${word}`, "i").test(words), `${where} names "${word}"`);
  }
  assert(
    !/\b(ai|model|claude|gemini|deepseek|groq|llm)\b/i.test(words),
    `${where} names a model or company`,
  );
};

// The rules run in SQL; these tests keep the TypeScript numbers and the migration from drifting.
Deno.test("the migration's rule numbers are the sourced values", () => {
  const pain = migration.match(/select '(\{"version":"pain-v1".*?\})'::jsonb;/s);
  assert(pain, "pain_rules literal found");
  assertEquals(JSON.parse(pain[1]), JSON.parse(JSON.stringify(painRulesJson())));
  const joint = migration.match(/select '(\{"version":"joint-v1".*?\})'::jsonb;/s);
  assert(joint, "joint_rules literal found");
  assertEquals(JSON.parse(joint[1]), JSON.parse(JSON.stringify(jointRulesJson())));
});

Deno.test("each red flag leads where the owner's brief says, and no further", () => {
  const expected: Record<string, string> = {
    bladder_bowel_saddle: "urgent",
    chest_or_breath: "urgent",
    numb_weak_limb: "clinician_today",
    pop_or_sudden: "clinician_today",
    cannot_bear_or_move: "clinician_today",
    rapid_swelling: "clinician_today",
    dislocated_or_cannot_lift: "clinician_today",
    locks_gives_way: "clinician",
    fever_unwell: "clinician",
    night_pain: "clinician",
  };
  assertEquals(Object.keys(redFlagOutcomes).sort(), Object.keys(expected).sort());
  for (const [flag, rule] of Object.entries(redFlagOutcomes)) {
    assertEquals(rule.value, expected[flag], flag);
  }
  assertEquals([...redFlagCodes], Object.keys(expected).sort());
});

Deno.test("every red flag has a plain question for at least one joint", () => {
  for (const code of redFlagCodes) {
    const question = redFlagQuestions[code];
    assert(question.question.length > 10 && question.question.length < 120, code);
    assert(question.areas.length > 0 && question.areas.every((a) => painAreas.includes(a)), code);
    noDiagnosis(question.question, `the question for ${code}`);
  }
  for (const area of painAreas) assert(questionsFor(area).length >= 4, `${area} is asked enough`);
  assert(questionsFor("back").includes("bladder_bowel_saddle"));
  assert(!questionsFor("knee").includes("bladder_bowel_saddle"));
  assert(questionsFor("knee").includes("locks_gives_way"));
  assert(questionsFor("shoulder").includes("dislocated_or_cannot_lift"));
});

Deno.test("the table accepts exactly the vocabulary the code and the app use", () => {
  const table = code(migration.slice(migration.indexOf("create table public.pain_reports")));
  const list = (pattern: RegExp) =>
    [...(table.match(pattern)?.[1] ?? "").matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
  assertEquals(list(/area text not null check \(area in \(([^)]*)\)/), [...painAreas]);
  assertEquals(list(/pattern text check \(pattern in \(([^)]*)\)/), [...painPatterns]);
  assertEquals(list(/outcome in \(([^)]*)\)\),\n\s+idempotency_key/), [...painOutcomes]);
  assertEquals(list(/source text not null check \(source in \(([^)]*)\)/), ["check_in", "workout"]);
  assert(
    /constraint pain_reports_outcome_matches_answers check \(\s+outcome = private\.pain_outcome\(severity::integer, red_flags\)\)/
      .test(table),
    "a stored outcome can never disagree with its answers",
  );
});

Deno.test("the range cues in SQL are the table in TypeScript", () => {
  const from = migration.indexOf("create function private.range_note_code(");
  const sql = migration.slice(from, migration.indexOf("$$;", from));
  const found = [...sql.matchAll(
    /when p_joint = '([a-z]+)' and p_pattern = '([a-z_]+)' then '([a-z_]+)'/g,
  )].map((m) => [m[3], m[1], m[2]]);
  const generic = sql.match(/else '([a-z_]+)' end/)?.[1];
  const table = rangeNotes.value.filter((note) => note.joint !== null).map((
    note,
  ) => [note.code, note.joint, note.pattern]);
  assertEquals(found, table);
  assertEquals(generic, rangeNotes.value.find((note) => note.joint === null)?.code);
  assertEquals(new Set(rangeNotes.value.map((note) => note.code)).size, rangeNotes.value.length);
  for (const note of rangeNotes.value) {
    assert(note.cue.length > 20 && note.cue.length < 130, note.code);
    noDiagnosis(note.cue, `the cue ${note.code}`);
  }
});

Deno.test("the words the athlete reads never diagnose or name a condition", () => {
  const sentences = migration.slice(
    migration.indexOf("create function private.joint_sentence("),
    migration.indexOf("-- 9. Starting the workout"),
  );
  noDiagnosis(code(sentences), "the SQL sentences");
  assert(
    !/hernia|fracture/i.test(
      code(
        migration.slice(
          migration.indexOf("create or replace function private.day_adjustment_explanation("),
        ),
      ),
    ),
    "no condition in the explanation",
  );
});

Deno.test("urgent copy names the emergency number, and every route has words", () => {
  const explanation = migration.slice(
    migration.indexOf("create or replace function private.day_adjustment_explanation("),
    migration.indexOf("create function private.day_adjustment_compute("),
  );
  for (const route of ["pain_referral", "urgent", "clinician_today"]) {
    assert(explanation.includes(`when '${route}' then`), `${route} has a sentence`);
  }
  assert(
    /else 'Please book a doctor or physio/.test(explanation),
    "clinician has the final sentence",
  );
  assert(/urgent care\. Call your local emergency number/.test(explanation));
});

Deno.test("no rule or word of the pain SQL reads a heart-rate signal (D9)", () => {
  assert(
    !/heart|bpm|hrv|resting_|pulse|acwr|monotony|strain_/i.test(code(migration)),
    "the migration reads reports, the plan and the catalog, never a heart signal or a load ratio",
  );
});

Deno.test("the migration is additive: new objects, widened checks, and replaced functions only", () => {
  const sql = code(migration);
  assert(!/\bdrop (table|column|schema|index|trigger)\b/i.test(sql));
  // The only functions dropped are the ones replaced by a signature with an optional argument.
  assertEquals(
    [...sql.matchAll(/drop function ([a-z0-9_.]+)\(([^)]*)\);/g)].map((m) => `${m[1]}(${m[2]})`),
    [
      "private.day_adjustment_compute(uuid, date)",
      "public.get_my_day_adjustment_v1(date)",
      "public.respond_to_day_adjustment_v1(date, boolean, text)",
    ],
  );
  // The only updates are the supersedes of the check-in and of the day's answer, copied from their definitions.
  assert(
    !/\btruncate\b|\bdelete from\b|\brename\b|\bupdate public\.(?!daily_check_ins c set superseded_at|day_adjustments a set superseded_at)/i
      .test(sql),
  );
  const drops = [...sql.matchAll(/drop constraint ([a-z_]+)/g)].map((m) => m[1]);
  assertEquals(drops, ["day_adjustments_kind_check", "day_adjustments_rules_kind_check"]);
  const widened = sql.match(
    /add constraint day_adjustments_kind_check check \(\s+kind in \(([^)]*)\)\),\s+add constraint day_adjustments_rules_kind_check check \(\s+rules_kind in \(([^)]*)\)\)/,
  );
  assert(widened, "both checks come back");
  const earlier = earlierKinds();
  for (const value of earlier.kinds) assert(widened[1].includes(`'${value}'`), `${value} is kept`);
  for (const value of earlier.rulesKinds) {
    assert(widened[2].includes(`'${value}'`), `${value} is kept`);
  }
  assert(widened[1].includes("'joint_adjust'") && widened[2].includes("'joint_adjust'"));
});

const earlierMigration = await Deno.readTextFile(
  migrationPath("20261023140024_day_adjustments.sql"),
);
function earlierKinds() {
  const kinds = earlierMigration.match(/kind text not null check \(kind in \(([^)]*)\)/s)?.[1] ??
    "";
  const rulesKinds = earlierMigration.match(/rules_kind in \(([^)]*)\)\),/s)?.[1] ?? "";
  const values = (text: string) => [...text.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
  return { kinds: values(kinds), rulesKinds: values(rulesKinds) };
}

Deno.test("every function runs as its owner with an empty search path, and only the right roles execute it", () => {
  const sql = code(migration);
  const headers = [
    ...sql.matchAll(/create (?:or replace )?function ([a-z_.]+)\(([^$]*?)\bas \$\$/gs),
  ];
  assert(headers.length >= 25, "found the functions");
  for (const header of headers) {
    assert(/set search_path\s*=\s*''/.test(header[0]), `${header[1]} has an empty search path`);
  }
  for (const header of headers.filter((h) => h[1].startsWith("public."))) {
    if (header[1] === "public.save_daily_check_in" || header[1] === "public.start_workout") {
      continue;
    }
    assert(/security definer/.test(header[0]), `${header[1]} is security definer`);
  }
  assert(!/grant [^;]*\sto\s+(anon|public)\b/i.test(sql), "nothing is granted to anon or public");
  assert(
    /grant execute on function public\.record_pain_check_v1\(\s*date, text, text, integer, text, text\[\], boolean, uuid, uuid\) to authenticated;/
      .test(sql),
  );
  assert(
    /grant execute on function public\.get_readiness_context_v1\(uuid, date\) to service_role;/
      .test(sql),
  );
  assert(
    /revoke all on function public\.get_readiness_context_v1\(uuid, date\) from public, anon, authenticated;/
      .test(sql),
  );
});

Deno.test("every report table and function the migration adds is private to the athlete", () => {
  const sql = code(migration);
  assert(/alter table public\.pain_reports enable row level security;/.test(sql));
  assert(/alter table public\.pain_reports force row level security;/.test(sql));
  assert(/using \(user_id = \(select auth\.uid\(\)\)\);/.test(sql));
  assert(/revoke all on public\.pain_reports from anon, authenticated;/.test(sql));
  assert(/grant select on public\.pain_reports to authenticated;/.test(sql));
});

// A redefined function must be its earlier definition plus the intended hunks and nothing else, so the
// rest of its behaviour is exactly what the earlier migration tested.
function between(text: string, start: string, end: string): string {
  const from = text.indexOf(start);
  assert(from >= 0, `missing ${start}`);
  const to = text.indexOf(end, from);
  assert(to > from, `missing ${end}`);
  return text.slice(from, to + end.length);
}

type Hunks = readonly (readonly [string, string])[];
// [was, added]: undoing replaces `added` with `was`. A hunk whose `was` is empty was only inserted.
function undo(redefined: string, hunks: Hunks): string {
  let text = redefined;
  for (const [was, added] of [...hunks].reverse()) {
    assertEquals(
      text.split(added).length - 1,
      1,
      `hunk is in the function once: ${added.slice(0, 70)}`,
    );
    text = text.replace(added, was);
  }
  return text.trim();
}

const readMigration = (name: string) => Deno.readTextFile(migrationPath(name));

Deno.test("readiness_rank is B4's function with joint_adjust between none and hold_load", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create function private.readiness_rank(",
    "$$;",
  );
  const redefined = between(migration, "create or replace function private.readiness_rank(", "$$;");
  const hunks: Hunks = [
    [
      "create function private.readiness_rank(",
      "create or replace function private.readiness_rank(",
    ],
    [
      "  select case when p_safety_route is not null then 4\n    else case p_kind when 'hold_load' then 1 when 'reduce_sets' then 2\n      when 'swap_to_easy_cardio' then 3 else 0 end end;",
      "  select case when p_safety_route is not null then 5\n    else case p_kind when 'joint_adjust' then 1 when 'hold_load' then 2 when 'reduce_sets' then 3\n      when 'swap_to_easy_cardio' then 4 else 0 end end;",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("day_adjustment_explanation is B4's function plus the safety, joint and counting hunks only", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create function private.day_adjustment_explanation(",
    "end $$;",
  );
  const redefined = between(
    migration,
    "create or replace function private.day_adjustment_explanation(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "create function private.day_adjustment_explanation(",
      "create or replace function private.day_adjustment_explanation(",
    ],
    [
      "  n integer;\nbegin\n",
      "  n integer;\n  joint_text text;\nbegin\n",
    ],
    [
      "  if p_safety_route = 'pain_referral' then\n    return 'Pain of 7 or more is too high to train through. Rest the area and see a doctor or physio before you train it again.';\n  end if;",
      "  if p_safety_route is not null then\n    return case p_safety_route\n      when 'pain_referral' then 'Pain of 7 or more is too high to train through. Rest the area and see a doctor or physio before you train it again.'\n      when 'urgent' then 'What you described needs urgent care. Call your local emergency number or go to an emergency department now. Tracend won''t suggest any training until you''ve been seen.'\n      when 'clinician_today' then 'Please see a doctor or physio today, before you train this area again. Tracend leaves training aside for today.'\n      else 'Please book a doctor or physio before you train this area again. Tracend leaves training aside for today.' end;\n  end if;",
    ],
    [
      "    select count(*) filter (where (c ->> 'sets_to')::integer < (c ->> 'sets_from')::integer),",
      "    select count(*) filter (where (c ->> 'sets_to')::integer < (c ->> 'sets_from')::integer\n        and coalesce(c ->> 'joint_action', '') <> 'drop'),",
    ],
    [
      "      else format('Try %s to %s minutes of easy walking",
      "      when 'joint_adjust' then ''\n      else format('Try %s to %s minutes of easy walking",
    ],
    [
      "    if p_with_reasons then\n      for i in 1..array_length(codes, 1) loop",
      "    if p_with_reasons and p_kind <> 'joint_adjust' then\n      for i in 1..array_length(codes, 1) loop",
    ],
    [
      "    return case when reasons <> ''\n      then upper(left(reasons, 1)) || substr(reasons, 2) || '. ' else '' end || action || note;",
      "    joint_text := private.joint_sentence(p_changes);\n    return case when reasons <> ''\n      then upper(left(reasons, 1)) || substr(reasons, 2) || '. ' else '' end || action\n      || case when joint_text = '' then '' when action = '' then joint_text\n        else ' ' || joint_text end || note;",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("day_adjustment_stands is B4's function plus the joint-coverage hunk only", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create function private.day_adjustment_stands(",
    "$$;",
  );
  const redefined = between(
    migration,
    "create or replace function private.day_adjustment_stands(",
    "$$;",
  );
  const hunks: Hunks = [
    [
      "create function private.day_adjustment_stands(",
      "create or replace function private.day_adjustment_stands(",
    ],
    [
      "      or private.readiness_rank(p_payload ->> 'kind', null)\n        <= greatest(private.readiness_rank(p_row.rules_kind, null),\n          private.readiness_rank(p_row.kind, null)));",
      "      or (private.readiness_rank(p_payload ->> 'kind', null)\n          <= greatest(private.readiness_rank(p_row.rules_kind, null),\n            private.readiness_rank(p_row.kind, null))\n        and (not (p_row.joint_capable or p_row.kind = 'joint_adjust')\n          or private.joint_change_keys(p_row.changes) = private.joint_change_keys((\n            select o -> 'changes' from jsonb_array_elements(p_payload -> 'options') o\n            where o ->> 'kind' = 'joint_adjust' limit 1)))));",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("day_adjustment_present is B4's function plus the lasting-pain sentence only", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create function private.day_adjustment_present(",
    "$$;",
  );
  const redefined = between(
    migration,
    "create or replace function private.day_adjustment_present(",
    "$$;",
  );
  const hunks: Hunks = [
    [
      "create function private.day_adjustment_present(",
      "create or replace function private.day_adjustment_present(",
    ],
    [
      "        array(select jsonb_array_elements_text(p_payload -> 'triggers')), null, p_row.changes,\n        p_row.origin = 'proposed', null),",
      "        array(select jsonb_array_elements_text(p_payload -> 'triggers')), null, p_row.changes,\n        p_row.origin = 'proposed', null) || private.persistent_sentence(p_payload -> 'joint_states')\n        || private.hold_reminder(p_payload -> 'joint_states', p_row.changes),",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("day_adjustment_compute is B4's function plus the joint and red-flag hunks only", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create function private.day_adjustment_compute(",
    "end $$;",
  );
  const redefined = between(
    migration,
    "create function private.day_adjustment_compute(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "create function private.day_adjustment_compute(p_user uuid, p_date date)",
      "create function private.day_adjustment_compute(p_user uuid, p_date date, p_joint boolean default true)",
    ],
    [
      "  inputs jsonb;\nbegin\n",
      "  inputs jsonb;\n  states jsonb;\n  joint_arr jsonb := '[]'::jsonb;\n  joint_c jsonb;\n  exercise_options jsonb := '[]'::jsonb;\n  report_route text;\n  report_severe boolean;\n  report_codes text[];\n  states_full jsonb;\n  merge_arr jsonb := '[]'::jsonb;\n  joint_only boolean := false;\n  hold_route text;\n  hold_severe boolean;\n  hold_codes text[];\nbegin\n",
    ],
    [
      "  workout_id := (workout ->> 'id')::uuid;\n",
      "  workout_id := (workout ->> 'id')::uuid;\n  states_full := private.joint_states_detail(p_user, p_date);\n  states := coalesce((select jsonb_agg(t.s - 'hold_codes' - 'hold_severe' order by t.n)\n    from jsonb_array_elements(states_full) with ordinality as t(s, n)), '[]'::jsonb);\n",
    ],
    [
      "    when version_block = 'next_session' and version_ends = p_date then 'coach_adjusted'\n  end;\n",
      "    when version_block = 'next_session' and version_ends = p_date then 'coach_adjusted'\n  end;\n  -- On a day Coach already adjusted, the readiness kinds are not offered twice, but a joint that is held,\n  -- limited or on watch still changes the exercises start_workout will create for that day.\n  joint_only := coalesce(unavailable = 'coach_adjusted', false);\n",
    ],
    [
      "    can_reduce := (reduce_c ->> 'sets_to')::integer < (reduce_c ->> 'sets_from')::integer;\n  end if;\n",
      "    can_reduce := (reduce_c ->> 'sets_to')::integer < (reduce_c ->> 'sets_from')::integer;\n    exercise_options := private.joint_options(p_user, workout_id, states);\n    joint_arr := private.joint_changes(p_user, workout_id, states, hold_c -> 'changes');\n  end if;\n  -- A joint that is held, limited or on watch changes the exercises it touches in every kind (the\n  -- stricter value per exercise wins), and alone as the joint_adjust kind.\n  -- A client that does not declare support for joint changes (p_joint false) is offered the readiness kinds\n  -- as they were, without them: it could not show a left-out or swapped exercise, and what it accepts is\n  -- what it was shown. joint_adjust, below, is the same for every client.\n  if p_joint then merge_arr := joint_arr; end if;\n  hold_c := private.day_changes_merged(hold_c, merge_arr);\n  reduce_c := private.day_changes_merged(reduce_c, merge_arr);\n  swap_c := private.day_changes_merged(swap_c, merge_arr);\n  joint_c := private.day_changes_merged(jsonb_build_object('changes', '[]'::jsonb,\n    'sets_from', (swap_c ->> 'sets_from')::integer, 'sets_to', (swap_c ->> 'sets_from')::integer),\n    joint_arr);\n",
    ],
    [
      "  triggers := array(select jsonb_array_elements_text(assessment -> 'triggers'));\n",
      "  triggers := array(select jsonb_array_elements_text(assessment -> 'triggers'));\n  -- A pain report that routes out (a red flag, or a severity of 7 or more) gives the day a safety route\n  -- just as a check-in pain of 7 or more does, even with no check-in, on a rest day or after the session\n  -- started: from reports dated today or stored today (a phone's date can differ from the server's), and\n  -- on every later day while the area stays held on an urgent or clinician_today outcome, until the\n  -- athlete's own clearance; a clearance recorded later the same day ends today's route for that area too\n  -- (only reports of an area still held count). A hold on a clinician outcome gives no route on later\n  -- days, only a reminder in the day's words. The strictest route wins.\n  select (array['clinician', 'clinician_today', 'urgent'])[max(\n      case pr.outcome when 'urgent' then 3 when 'clinician_today' then 2 else 1 end)],\n    coalesce(bool_or(pr.severity >= (private.pain_rules() ->> 'clinician_today_from')::integer), false)\n  into report_route, report_severe\n  from public.pain_reports pr\n  where pr.user_id = p_user and pr.outcome in ('urgent', 'clinician_today', 'clinician')\n    and (pr.local_date = p_date or private.local_day_of(p_user, pr.created_at) = p_date)\n    and exists (select 1 from jsonb_array_elements(states_full) hs\n      where hs ->> 'area' = pr.area and hs ->> 'state' = 'held');\n  report_codes := array(select distinct 'red_flag:' || f from public.pain_reports pr,\n    unnest(pr.red_flags) f\n    where pr.user_id = p_user and pr.outcome in ('urgent', 'clinician_today', 'clinician')\n      and (pr.local_date = p_date or private.local_day_of(p_user, pr.created_at) = p_date)\n      and exists (select 1 from jsonb_array_elements(states_full) hs\n        where hs ->> 'area' = pr.area and hs ->> 'state' = 'held')\n    order by 1);\n  select (array['clinician_today', 'urgent'])[max(case h ->> 'hold_outcome' when 'urgent' then 2 else 1 end)],\n    coalesce(bool_or((h ->> 'hold_severe')::boolean), false),\n    array(select distinct 'red_flag:' || c from jsonb_array_elements(states_full) h2,\n      jsonb_array_elements_text(h2 -> 'hold_codes') c\n      where h2 ->> 'state' = 'held' and h2 ->> 'hold_outcome' in ('urgent', 'clinician_today') order by 1)\n  into hold_route, hold_severe, hold_codes\n  from jsonb_array_elements(states_full) h\n  where h ->> 'state' = 'held' and h ->> 'hold_outcome' in ('urgent', 'clinician_today');\n  if hold_route is not null and (report_route is null\n      or private.safety_route_rank(hold_route) > private.safety_route_rank(report_route)) then\n    report_route := hold_route;\n  end if;\n  report_severe := coalesce(report_severe, false) or coalesce(hold_severe, false);\n  report_codes := report_codes || coalesce(hold_codes, '{}'::text[]);\n  if report_route is not null then\n    if safety is null\n       or private.safety_route_rank(report_route) > private.safety_route_rank(safety) then\n      safety := report_route;\n    end if;\n    triggers := array(select distinct t from unnest(\n      case when assessment ->> 'safety_route' is not null then array['pain_severe']\n        else '{}'::text[] end\n      || report_codes\n      || case when report_severe then array['pain_severe'] else '{}'::text[] end) t order by t);\n    band := 'red';\n  end if;\n",
    ],
    [
      "  kind := case when unavailable is not null or safety is not null then 'none'\n    else assessment ->> 'kind' end;\n",
      "  kind := case when unavailable is not null or safety is not null then 'none'\n    else assessment ->> 'kind' end;\n  -- A joint state changes the session even on a day the readiness rules ask for nothing, unless the\n  -- athlete said they cannot train.\n  if kind = 'none' and (unavailable is null or joint_only) and safety is null\n     and coalesce(check_in.available_to_train, true)\n     and jsonb_array_length(joint_c -> 'changes') > 0 then\n    kind := 'joint_adjust';\n  end if;\n",
    ],
    [
      "    when 'swap_to_easy_cardio' then swap_c else\n",
      "    when 'swap_to_easy_cardio' then swap_c when 'joint_adjust' then joint_c else\n",
    ],
    [
      "  if unavailable is null and safety is null and coalesce(check_in.available_to_train, true)\n     and workout_id is not null then\n    if can_hold then\n",
      "  if (unavailable is null or joint_only) and safety is null\n     and coalesce(check_in.available_to_train, true) and workout_id is not null then\n    if can_hold and not joint_only then\n",
    ],
    [
      "    if can_reduce then\n",
      "    if can_reduce and not joint_only then\n",
    ],
    [
      "    if (swap_c ->> 'sets_from')::integer > 0 then\n",
      "    if (swap_c ->> 'sets_from')::integer > 0 and not joint_only then\n",
    ],
    [
      "      'available', unavailable is null,\n      'unavailable_reason', unavailable,\n",
      "      'available', unavailable is null or kind = 'joint_adjust',\n      'unavailable_reason', case when kind = 'joint_adjust' then null else unavailable end,\n",
    ],
    [
      "        'sets_total_to', 0, 'changes', swap_c -> 'changes', 'cardio', cardio);\n    end if;\n",
      "        'sets_total_to', 0, 'changes', swap_c -> 'changes', 'cardio', cardio);\n    end if;\n    if jsonb_array_length(joint_c -> 'changes') > 0 then\n      options := options || jsonb_build_object('kind', 'joint_adjust',\n        'explanation', private.day_adjustment_explanation(band, 'joint_adjust', '{}', null,\n          joint_c -> 'changes', false, null),\n        'sets_total_to', (joint_c ->> 'sets_to')::integer, 'changes', joint_c -> 'changes',\n        'cardio', null);\n    end if;\n",
    ],
    [
      "    'screening', screening);\n",
      "    'screening', screening, 'joint_states', states);\n",
    ],
    [
      "      'schema_version', '1.0',\n",
      "      'schema_version', '1.1',\n",
    ],
    [
      "        chosen_c -> 'changes', true, unavailable),\n",
      "        chosen_c -> 'changes', true, unavailable)\n        || case when safety is null then private.persistent_sentence(states)\n          || private.hold_reminder(states, chosen_c -> 'changes') else '' end,\n",
    ],
    [
      "'recovery_low', (assessment ->> 'recovery_low')::boolean, 'sleep_minutes', sleep_minutes)));",
      "'recovery_low', (assessment ->> 'recovery_low')::boolean, 'sleep_minutes', sleep_minutes),\n      'joint_states', states,\n      'exercise_joint_options', exercise_options));",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("get_my_day_adjustment_v1 is B4's function plus the capability argument only", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create function public.get_my_day_adjustment_v1(",
    "end $$;",
  );
  const redefined = between(
    migration,
    "create function public.get_my_day_adjustment_v1(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "create function public.get_my_day_adjustment_v1(local_date date)",
      "create function public.get_my_day_adjustment_v1(local_date date, supports_joint_changes boolean default false)",
    ],
    [
      "  computed := private.day_adjustment_compute(uid, today);",
      "  computed := private.day_adjustment_compute(uid, today, coalesce(get_my_day_adjustment_v1.supports_joint_changes, false));",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("respond_to_day_adjustment_v1 is B4's function plus the capability argument and its column only", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create function public.respond_to_day_adjustment_v1(",
    "end $$;",
  );
  const redefined = between(
    migration,
    "create function public.respond_to_day_adjustment_v1(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "  local_date date, accept boolean, chosen_kind text default null\n) returns jsonb",
      "  local_date date, accept boolean, chosen_kind text default null,\n  supports_joint_changes boolean default false\n) returns jsonb",
    ],
    [
      "  computed := private.day_adjustment_compute(uid, today);",
      "  computed := private.day_adjustment_compute(uid, today, coalesce(respond_to_day_adjustment_v1.supports_joint_changes, false));",
    ],
    [
      "    rules_version, band, kind, origin, rules_kind, triggers, changes, cardio, inputs, inputs_hash,\n    status)\n  values (uid, today,",
      "    rules_version, band, kind, origin, rules_kind, triggers, changes, cardio, inputs, inputs_hash,\n    status, joint_capable)\n  values (uid, today,",
    ],
    [
      "    target_status)\n  returning * into new_row;",
      "    target_status, coalesce(respond_to_day_adjustment_v1.supports_joint_changes, false))\n  returning * into new_row;",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("the two RPCs keep every old call working: the new argument has a default, the old signatures are replaced", () => {
  assert(/drop function public\.get_my_day_adjustment_v1\(date\);/.test(migration));
  assert(
    /drop function public\.respond_to_day_adjustment_v1\(date, boolean, text\);/.test(migration),
  );
  assert(/supports_joint_changes boolean default false\)/.test(migration));
  assert(
    /chosen_kind text default null,\s+supports_joint_changes boolean default false\s+\) returns jsonb/
      .test(migration),
  );
  assert(/p_joint boolean default true/.test(migration));
  // The compute reads the capability from the argument, and every public caller passes it.
  assert(
    /day_adjustment_compute\(uid, today, coalesce\(get_my_day_adjustment_v1\.supports_joint_changes, false\)\)/
      .test(migration),
  );
  assert(
    /day_adjustment_compute\(uid, today, coalesce\(respond_to_day_adjustment_v1\.supports_joint_changes, false\)\)/
      .test(migration),
  );
  assert(/day_adjustment_compute\(p_user_id, p_local_date, true\)/.test(migration));
  assert(
    !/(?<!function private\.)day_adjustment_compute\([a-z_]+, [a-z_]+\)/.test(code(migration)),
    "no call leaves the capability out",
  );
});

Deno.test("progression_decision is B4's definition plus the left-out-exercise hunk only", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create or replace function private.progression_decision(",
    "end $$;",
  );
  const redefined = between(
    migration,
    "create or replace function private.progression_decision(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "  elsif v_sets < coalesce((s1 ->> 'sets_planned')::integer, p_set_count) then\n",
      "  elsif v_sets < coalesce((s1 ->> 'sets_planned')::integer, p_set_count)\n        or coalesce((s1 ->> 'sets_planned')::integer, 1) = 0 then\n",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("next_session_targets is B4's definition plus the joint-answer hunk only", async () => {
  const earlier = between(
    await readMigration("20261023140024_day_adjustments.sql"),
    "create or replace function private.next_session_targets(",
    "$$;",
  );
  const redefined = between(
    migration,
    "create or replace function private.next_session_targets(",
    "$$;",
  );
  const hunks: Hunks = [
    [
      "), marked as (\n  -- Done under an accepted hold_load or reduce_sets answer (B4) and the answer lists this exercise:\n  -- not evidence for lowering its load, and its planned set count is the adjusted one. An exercise\n  -- the answer left alone is judged as ever, however easy the rest of the session was.\n  select s.*, ch.sets_to is not null as adjusted, ch.sets_to as sets_planned\n  from sessions s\n  join public.workout_sessions ws on ws.id = s.session_id and ws.user_id = p_user\n  left join public.day_adjustments a on a.id = ws.day_adjustment_id and a.user_id = p_user\n    and a.status = 'accepted' and a.kind in ('hold_load', 'reduce_sets')\n  left join lateral (\n    select (c ->> 'sets_to')::integer as sets_to from jsonb_array_elements(a.changes) c\n    where c ->> 'planned_exercise_id' = s.logged_exercise_id::text limit 1) ch on true\n), ranked as (",
      "), marked as (\n  -- Done under an accepted answer that lists this exercise (hold_load, reduce_sets or joint_adjust,\n  -- B4 and B5), or one that limits its range for a joint: not evidence for lowering its load, and its\n  -- planned set count is the answer's (an easy-cardio answer keeps the plan's sets). An exercise the\n  -- answer left alone is judged as ever, however easy the rest of the session was.\n  select s.*, ch.listed is not null as adjusted, ch.sets_planned\n  from sessions s\n  join public.workout_sessions ws on ws.id = s.session_id and ws.user_id = p_user\n  left join public.day_adjustments a on a.id = ws.day_adjustment_id and a.user_id = p_user\n    and a.status = 'accepted'\n  left join lateral (\n    select true as listed,\n      case when a.kind <> 'swap_to_easy_cardio' then (c ->> 'sets_to')::integer end as sets_planned\n    from jsonb_array_elements(a.changes) c\n    where c ->> 'planned_exercise_id' = s.logged_exercise_id::text\n      and (a.kind in ('hold_load', 'reduce_sets', 'joint_adjust')\n        or c ->> 'joint_action' = 'limit') limit 1) ch on true\n), ranked as (",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("start_workout is the stale-close definition plus the left-out-exercise hunk only", async () => {
  const earlier = between(
    await readMigration("20261023150021_close_stale_workouts.sql"),
    "create or replace function public.start_workout(",
    "end $$;",
  );
  const redefined = between(
    migration,
    "create or replace function public.start_workout(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "    adjusted := found;\n  end if;\n",
      "    adjusted := found;\n    -- An answer that carries joint changes is applied only while they are the ones the rules ask for now;\n    -- otherwise the plan is built as written (the day's safety route is the card's business, not a rewrite\n    -- of the session). An answer without joint changes is applied as given, as before.\n    if adjusted and private.joint_change_keys(adjustment.changes) <> '{}'::text[]\n       and private.joint_change_keys(adjustment.changes) is distinct from private.joint_change_keys(\n         private.joint_changes(auth.uid(), p_planned_workout_id,\n           private.joint_states(auth.uid(), p_local_date), '[]'::jsonb)) then\n      adjusted := false;\n    end if;\n  end if;\n",
    ],
    [
      "  adjustment public.day_adjustments%rowtype; adjusted boolean := false; set_total integer;\n",
      "  adjustment public.day_adjustments%rowtype; adjusted boolean := false; set_total integer;\n  entry jsonb;\n",
    ],
    [
      "    insert into public.exercise_performances(\n      user_id,workout_session_id,planned_exercise_id,exercise_order,status,\n      performance_kind,performed_name,rest_seconds\n    ) values(\n      auth.uid(),result_id,exercise.id,exercise.exercise_order,'unknown',\n      'prescribed',exercise.display_name_snapshot,exercise.rest_seconds\n    ) returning id into performance_id;\n    set_total := exercise.set_count;\n    if adjusted and adjustment.kind='reduce_sets' then\n      select (c ->> 'sets_to')::integer into set_total\n      from jsonb_array_elements(adjustment.changes) c\n      where c ->> 'planned_exercise_id' = exercise.id::text;\n      set_total := coalesce(set_total, exercise.set_count);\n    end if;",
      "    -- What the accepted answer says about this exercise, if anything.\n    entry := null;\n    if adjusted then\n      select c into entry from jsonb_array_elements(adjustment.changes) c\n      where c ->> 'planned_exercise_id' = exercise.id::text limit 1;\n    end if;\n    -- An exercise the answer swaps for a gentler one is created as that exercise, a substitution made\n    -- for pain (the load is not written: the athlete picks it); every other exercise is as planned.\n    insert into public.exercise_performances(\n      user_id,workout_session_id,planned_exercise_id,exercise_order,status,\n      performance_kind,performed_name,rest_seconds,substitution_reason\n    ) values(\n      auth.uid(),result_id,exercise.id,exercise.exercise_order,'unknown',\n      case when entry ->> 'joint_action' = 'swap' then 'substituted' else 'prescribed' end,\n      case when entry ->> 'joint_action' = 'swap' then entry ->> 'swap_to_name'\n        else exercise.display_name_snapshot end,\n      exercise.rest_seconds,\n      case when entry ->> 'joint_action' = 'swap' then 'pain' end\n    ) returning id into performance_id;\n    -- A left-out exercise (a joint drop) gets no sets whatever the kind: its performance stays\n    -- 'unknown', never inferred as skipped. reduce_sets builds the adjusted set counts. Everything\n    -- else, an easy-cardio answer included, keeps the plan's sets.\n    set_total := exercise.set_count;\n    if entry is not null then\n      set_total := coalesce(case when entry ->> 'joint_action' = 'drop' then 0\n        when adjustment.kind='reduce_sets' then (entry ->> 'sets_to')::integer end, exercise.set_count);\n    end if;",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("save_daily_check_in is the phase 3 definition plus the pain check only", async () => {
  const earlier = between(
    await readMigration("20260701120000_phase_3_workout_check_in.sql"),
    "create function public.save_daily_check_in(",
    "end $$;",
  );
  const redefined = between(
    migration,
    "create or replace function public.save_daily_check_in(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "create function public.save_daily_check_in(",
      "create or replace function public.save_daily_check_in(",
    ],
    [
      "declare result_id uuid; next_revision integer;\n",
      "declare result_id uuid; next_revision integer;\n  new_build boolean; pain integer; main_area text; main_flags text[]; main_pattern text;\n  main_cleared boolean := false; follow jsonb; follow_areas text[] := '{}'; follow_area text;\n  follow_severity integer; follow_cleared boolean; report_date date; server_today date;\n",
    ],
    [
      "",
      "\n  new_build := payload ?| array['pain_area','pain_pattern','pain_red_flags','pain_cleared_by_clinician','pain_followups'];\n  if new_build then\n    pain := coalesce((payload->>'pain_severity')::integer, 0);\n    if jsonb_typeof(payload->'pain_area') = 'string' then\n      main_area := payload->>'pain_area';\n    elsif payload->'pain_area' is not null and jsonb_typeof(payload->'pain_area') <> 'null' then\n      raise exception 'pain_area must be text' using errcode='22023';\n    end if;\n    if main_area is null then\n      if pain > 0 then raise exception 'pain needs an area' using errcode='22023'; end if;\n      if (payload->'pain_red_flags' is not null and jsonb_typeof(payload->'pain_red_flags') <> 'null'\n            and payload->'pain_red_flags' <> '[]'::jsonb)\n         or (payload->'pain_pattern' is not null and jsonb_typeof(payload->'pain_pattern') <> 'null')\n         or (payload->'pain_cleared_by_clinician' is not null\n            and payload->'pain_cleared_by_clinician' not in ('null'::jsonb, 'false'::jsonb)) then\n        raise exception 'pain answers need an area' using errcode='22023';\n      end if;\n    else\n      if pain < 1 then raise exception 'a pain area needs a pain above 0' using errcode='22023'; end if;\n      if jsonb_typeof(payload->'pain_red_flags') is distinct from 'array' then\n        raise exception 'pain_red_flags must be a list' using errcode='22023';\n      end if;\n      if exists (select 1 from jsonb_array_elements(payload->'pain_red_flags') f\n          where jsonb_typeof(f) is distinct from 'string') then\n        raise exception 'pain_red_flags must be a list of codes' using errcode='22023';\n      end if;\n      main_flags := array(select jsonb_array_elements_text(payload->'pain_red_flags'));\n      if payload->'pain_pattern' is not null and jsonb_typeof(payload->'pain_pattern') = 'string' then\n        main_pattern := payload->>'pain_pattern';\n      elsif payload->'pain_pattern' is not null and jsonb_typeof(payload->'pain_pattern') <> 'null' then\n        raise exception 'pain_pattern must be text' using errcode='22023';\n      end if;\n      if payload->'pain_cleared_by_clinician' is not null\n         and jsonb_typeof(payload->'pain_cleared_by_clinician') <> 'null' then\n        if jsonb_typeof(payload->'pain_cleared_by_clinician') is distinct from 'boolean' then\n          raise exception 'pain_cleared_by_clinician must be true or false' using errcode='22023';\n        end if;\n        main_cleared := (payload->>'pain_cleared_by_clinician')::boolean;\n      end if;\n    end if;\n    if payload->'pain_followups' is not null and jsonb_typeof(payload->'pain_followups') <> 'null' then\n      if jsonb_typeof(payload->'pain_followups') is distinct from 'array' then\n        raise exception 'pain_followups must be a list' using errcode='22023';\n      end if;\n      follow_areas := case when main_area is null then '{}'::text[] else array[main_area] end;\n      for follow in select value from jsonb_array_elements(payload->'pain_followups') loop\n        if jsonb_typeof(follow) is distinct from 'object'\n           or jsonb_typeof(follow->'area') is distinct from 'string'\n           or jsonb_typeof(follow->'severity') is distinct from 'number'\n           or (follow->>'severity')::numeric <> trunc((follow->>'severity')::numeric)\n           or (follow->'cleared_by_clinician' is not null\n              and jsonb_typeof(follow->'cleared_by_clinician') not in ('boolean', 'null')) then\n          raise exception 'a pain follow-up needs an area and a whole severity' using errcode='22023';\n        end if;\n        follow_area := follow->>'area';\n        if follow_area = any(follow_areas) then\n          raise exception 'one pain report per area in a check-in' using errcode='22023';\n        end if;\n        follow_areas := follow_areas || follow_area;\n      end loop;\n    end if;\n    -- A pain check is for the athlete's today or yesterday by the server's clock. A phone a day ahead\n    -- (its date is the server's tomorrow) is stored under the server's today, so a red flag is never lost\n    -- and never dated in the future; anything else is refused.\n    if main_area is not null or (jsonb_typeof(payload->'pain_followups') = 'array'\n        and jsonb_array_length(payload->'pain_followups') > 0) then\n      server_today := private.local_date_for(auth.uid());\n      if save_daily_check_in.local_date is null or save_daily_check_in.local_date < server_today - 1\n         or save_daily_check_in.local_date > server_today + 1 then\n        raise exception 'a pain check is for today or yesterday' using errcode='22023';\n      end if;\n      report_date := least(save_daily_check_in.local_date, server_today);\n    end if;\n  end if;\n\n",
    ],
    [
      "",
      "\n  if main_area is not null then\n    perform private.insert_pain_report(auth.uid(), report_date, 'check_in',\n      result_id, null, main_area, pain, main_pattern, main_flags, main_cleared, null);\n  end if;\n  if new_build and payload->'pain_followups' is not null\n     and jsonb_typeof(payload->'pain_followups') = 'array' then\n    for follow in select value from jsonb_array_elements(payload->'pain_followups') loop\n      follow_severity := ((follow->>'severity')::numeric)::integer;\n      follow_cleared := coalesce((follow->>'cleared_by_clinician')::boolean, false);\n      perform private.insert_pain_report(auth.uid(), report_date, 'check_in',\n        result_id, null, follow->>'area', follow_severity, null, null, follow_cleared, null);\n    end loop;\n  end if;\n",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("no migration after this one's predecessors defines these functions again", async () => {
  const all = [...Deno.readDirSync(new URL("../../../../migrations/", import.meta.url))]
    .map((entry) => entry.name).filter((name) => name > "20261023150021_close_stale_workouts.sql");
  for (const name of all) {
    if (name === "20261024060025_pain_checks.sql") continue;
    const text = await readMigration(name);
    // The B5-3/B5-4 review fixes replace next_session_targets once (deload_cardio_review_test.ts pins
    // that definition against this one's), and the training-day integrity migration replaces
    // day_adjustment_compute once for the "day already done" check (training_day_integrity_test.ts
    // pins that definition against this one's); every other function stays untouched.
    const allowed = name === "20261024060325_deload_cardio_review_fixes.sql"
      ? ["next_session_targets"]
      : name === "20261024090000_training_day_integrity.sql"
      ? ["day_adjustment_compute"]
      : [];
    for (
      const fn of [
        "day_adjustment_compute",
        "day_adjustment_explanation",
        "day_adjustment_stands",
        "day_adjustment_present",
        "readiness_rank",
        "progression_decision",
        "next_session_targets",
        "save_daily_check_in",
        "get_my_day_adjustment_v1",
        "respond_to_day_adjustment_v1",
      ].filter((fn) => !allowed.includes(fn))
    ) {
      assert(
        !text.includes(`function private.${fn}(`) && !text.includes(`function public.${fn}(`),
        `${name} redefines ${fn}`,
      );
    }
  }
});

Deno.test("the contract fixtures parse and say what they say", () => {
  const joint = parseDayAdjustment(jointFixture);
  assert(joint);
  assertEquals([joint.schemaVersion, joint.kind, joint.status, joint.band], [
    "1.1",
    "joint_adjust",
    "proposed",
    "green",
  ]);
  assertEquals(joint.changes[0].joint, {
    action: "limit",
    joint: "shoulder",
    state: "watch",
    swapToSlug: null,
    swapToName: null,
    rangeNoteCode: "shoulder_press_depth",
    rangeNoteCodes: ["shoulder_press_depth"],
  });
  assertEquals(joint.jointStates, [
    {
      area: "shoulder",
      state: "watch",
      since: "2026-10-24",
      severity: 2,
      persistent: false,
      holdOutcome: null,
    },
  ]);
  assertEquals(joint.exerciseJointOptions.length, 5);
  assertEquals(joint.exerciseJointOptions[0].shoulder, {
    slug: "machine-chest-press",
    name: "Machine chest press",
  });
  assertEquals(joint.options.map((option) => option.kind), [
    "reduce_sets",
    "swap_to_easy_cardio",
    "joint_adjust",
  ]);
  const red = parseDayAdjustment(redFlagFixture);
  assert(red);
  assertEquals([red.safetyRoute, red.kind, red.status, red.band, red.options.length], [
    "clinician_today",
    "none",
    "none",
    "red",
    0,
  ]);
  assertEquals(red.triggers, ["red_flag:rapid_swelling"]);
  assertEquals(red.jointStates[0].state, "held");
  assertEquals(red.jointStates[0].holdOutcome, "clinician_today");
  const older = parseDayAdjustment(ninetyReduce);
  assert(older);
  assertEquals([older.schemaVersion, older.jointStates, older.exerciseJointOptions], [
    "1.0",
    [],
    [],
  ]);
  assertEquals(older.changes[0].joint, null);
  assertEquals(parseDayAdjustment(ninetySafety)?.safetyRoute, "pain_referral");
});

Deno.test("the pain check result has exactly its four keys", () => {
  assertEquals(Object.keys(painFixture).sort(), ["area_state", "id", "outcome", "schema_version"]);
  assertEquals(painFixture.schema_version, "1.0");
  assert(painOutcomes.includes(painFixture.outcome as typeof painOutcomes[number]));
  assert(["limited", "held", "watch", "none"].includes(painFixture.area_state));
});

Deno.test("a payload that contradicts itself about a joint yields nothing", () => {
  const mutate = (change: (copy: Record<string, unknown>) => void) => {
    const copy = structuredClone(jointFixture) as Record<string, unknown>;
    change(copy);
    return parseDayAdjustment(copy);
  };
  const first = (p: Record<string, unknown>) => (p.changes as Record<string, unknown>[])[0];
  assert(mutate(() => {}), "the unchanged fixture parses");
  assertEquals(mutate((p) => first(p).joint_action = "teleport"), null, "an unknown action");
  assertEquals(
    mutate((p) => first(p).joint_action = "drop"),
    null,
    "a left-out exercise keeps sets",
  );
  assertEquals(mutate((p) => first(p).joint_action = "swap"), null, "a swap names no exercise");
  assertEquals(mutate((p) => first(p).range_note_code = null), null, "a limit with no cue");
  assertEquals(mutate((p) => first(p).joint = "neck"), null, "an unknown joint");
  assertEquals(mutate((p) => first(p).joint_state = "cured"), null, "an unknown state");
  assertEquals(
    mutate((p) => first(p).swap_to_slug = "machine-chest-press"),
    null,
    "a limit with a swap",
  );
  assertEquals(mutate((p) => delete first(p).joint), null, "an action with no joint");
  assertEquals(mutate((p) => delete p.joint_states), null, "1.1 always carries the states");
  assertEquals(mutate((p) => delete p.exercise_joint_options), null, "and the swap options");
  assertEquals(mutate((p) => p.exercise_joint_options = [{ exercise_order: 1 }]), null);
  assertEquals(mutate((p) => p.schema_version = "1.2"), null, "a version it does not know");
  assertEquals(
    mutate((p) => first(p).range_note_codes = ["knee_squat_depth"]),
    null,
    "a primary cue missing from the list",
  );
  assertEquals(
    mutate((p) => first(p).range_note_codes = null),
    null,
    "a limit with no list of cues",
  );
  assertEquals(mutate((p) => first(p).range_note_codes = [1]), null, "a list of something else");
  assertEquals(
    mutate((p) => (p.joint_states as Record<string, unknown>[])[0].hold_outcome = "urgent"),
    null,
    "a hold outcome on an area that is not held",
  );
  assertEquals(
    mutate((p) => p.triggers = ["red_flag:made_up"]),
    null,
    "a red flag outside the list",
  );
  assertEquals(mutate((p) => p.changes = []), null, "a joint adjustment with no joint change");
  assertEquals(mutate((p) => p.safety_route = "urgent"), null, "a route with a kind in force");
  assertEquals(
    mutate((p) => {
      (p.joint_states as Record<string, unknown>[])[0].severity = 11;
    }),
    null,
    "a severity above 10",
  );
  const route = structuredClone(redFlagFixture) as Record<string, unknown>;
  for (const value of ["urgent", "clinician_today", "clinician", "pain_referral"]) {
    route.safety_route = value;
    assert(parseDayAdjustment(route), `${value} is a route`);
  }
  route.safety_route = "call_a_friend";
  assertEquals(parseDayAdjustment(route), null);
});
