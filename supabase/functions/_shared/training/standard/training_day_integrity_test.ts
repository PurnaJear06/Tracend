import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

// The training-day-integrity migration replaces seven functions. Each must be its latest earlier
// definition plus the intended hunks and nothing else, so everything else it does is what the earlier
// migration (and its pgTAP tests) already proved.
const read = (name: string) =>
  Deno.readTextFile(new URL(`../../../../migrations/${name}`, import.meta.url));
const integrity = await read("20261024090000_training_day_integrity.sql");

function between(text: string, start: string, end: string): string {
  const from = text.indexOf(start);
  assert(from >= 0, `missing ${start}`);
  const to = text.indexOf(end, from);
  assert(to > from, `missing ${end}`);
  return text.slice(from, to + end.length);
}

type Hunks = readonly (readonly [string, string])[];
// [was, added]: undoing replaces `added` with `was`.
function undo(redefined: string, hunks: Hunks): string {
  let text = redefined;
  for (const [was, added] of [...hunks].reverse()) {
    assertEquals(
      text.split(added).length - 1,
      1,
      `hunk is in the function once: ${added.slice(0, 70)}`,
    );
    text = text.replace(added, () => was);
  }
  return text.trim();
}

async function pinned(
  file: string,
  start: string,
  redefinedStart: string,
  end: string,
  hunks: Hunks,
) {
  const earlier = between(await read(file), start, end);
  const redefined = between(integrity, redefinedStart, end);
  assertEquals(undo(redefined, hunks), earlier.trim());
}

Deno.test("start_workout is the pain-check definition plus the future-day refusal and the workout-identity check only", async () => {
  const hunks: Hunks = [
    [
      "  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;\n  -- The same lock",
      "  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;\n  -- A workout is started on a day that has begun for the athlete, never on one still ahead.\n  if p_local_date > private.local_date_for(auth.uid()) then\n    raise exception 'cannot start a workout on a future day' using errcode='22023';\n  end if;\n  -- The same lock",
    ],
    [
      "  if exists (\n    select 1 from public.workout_sessions\n    where user_id=auth.uid() and planned_workout_id=p_planned_workout_id\n      and local_date=p_local_date and state='completed'\n  ) then",
      "  -- The same workout under any plan version: a Coach change, a block or a deload copies the workouts under\n  -- new ids, and a day already logged stays logged.\n  if exists (\n    select 1 from public.workout_sessions\n    where user_id=auth.uid()\n      and planned_workout_id = any(private.workout_identity_ids(auth.uid(), p_planned_workout_id))\n      and local_date=p_local_date and state='completed'\n  ) then",
    ],
  ];
  await pinned(
    "20261024060025_pain_checks.sql",
    "create or replace function public.start_workout(",
    "create or replace function public.start_workout(",
    "end $$;",
    hunks,
  );
});

Deno.test("get_my_workout_session is the stale-close definition plus the earlier-version completed session only", async () => {
  const hunks: Hunks = [
    [
      "  where user_id=auth.uid() and planned_workout_id=p_planned_workout_id\n    and state<>'abandoned'\n    and (state='in_progress' or local_date=p_local_date)\n",
      "  where user_id=auth.uid() and state<>'abandoned'\n    and (\n      (planned_workout_id=p_planned_workout_id and (state='in_progress' or local_date=p_local_date))\n      -- The day's finished session of the same workout under an earlier plan version.\n      or (state='completed' and local_date=p_local_date\n        and planned_workout_id = any(private.workout_identity_ids(auth.uid(), p_planned_workout_id)))\n    )\n",
    ],
  ];
  await pinned(
    "20261023150021_close_stale_workouts.sql",
    "create or replace function public.get_my_workout_session(",
    "create or replace function public.get_my_workout_session(",
    "end $$;",
    hunks,
  );
});

Deno.test("get_healthkit_completion_candidate is the per-date definition plus the workout-identity check only", async () => {
  const hunks: Hunks = [
    [
      "        and s.planned_workout_id = w.id\n",
      "        and s.planned_workout_id = any(private.workout_identity_ids(w.user_id, w.id))\n",
    ],
  ];
  await pinned(
    "20260718110000_healthkit_candidate_per_date.sql",
    "create or replace function public.get_healthkit_completion_candidate(",
    "create or replace function public.get_healthkit_completion_candidate(",
    "$$;",
    hunks,
  );
});

Deno.test("healthkit_auto_complete_workout is the train-redesign definition plus the workout-identity check only", async () => {
  const hunks: Hunks = [
    [
      "      and planned_workout_id = p_planned_workout_id\n      and local_date = p_local_date\n      and state = 'completed'\n",
      "      and planned_workout_id = any(private.workout_identity_ids(v_user_id, p_planned_workout_id))\n      and local_date = p_local_date\n      and state = 'completed'\n",
    ],
  ];
  await pinned(
    "20261003100000_train_redesign_data.sql",
    "create or replace function public.healthkit_auto_complete_workout(",
    "create or replace function public.healthkit_auto_complete_workout(",
    "end;\n$$;",
    hunks,
  );
});

Deno.test("day_adjustment_compute is the pain-check definition plus the workout-identity check for a day done only", async () => {
  const hunks: Hunks = [
    [
      "create function private.day_adjustment_compute(",
      "create or replace function private.day_adjustment_compute(",
    ],
    [
      "        and s.planned_workout_id = workout_id and s.local_date = p_date\n        and s.state = 'completed') then 'session_done'",
      "        and s.planned_workout_id = any(private.workout_identity_ids(p_user, workout_id))\n        and s.local_date = p_date and s.state = 'completed') then 'session_done'",
    ],
  ];
  await pinned(
    "20261024060025_pain_checks.sql",
    "create function private.day_adjustment_compute(p_user uuid, p_date date, p_joint boolean default true)",
    "create or replace function private.day_adjustment_compute(p_user uuid, p_date date, p_joint boolean default true)",
    "end $$;",
    hunks,
  );
});

Deno.test("unfinished_workouts is the unfinished-workouts definition plus the workout-identity check only", async () => {
  const hunks: Hunks = [
    [
      "create function private.unfinished_workouts(",
      "create or replace function private.unfinished_workouts(",
    ],
    [
      "        and c.planned_workout_id = s.planned_workout_id and c.local_date = s.local_date);",
      "        and c.planned_workout_id = any(private.workout_identity_ids(s.user_id, s.planned_workout_id))\n        and c.local_date = s.local_date);",
    ],
  ];
  await pinned(
    "20261024050011_unfinished_workouts.sql",
    "create function private.unfinished_workouts(",
    "create or replace function private.unfinished_workouts(",
    "$$;",
    hunks,
  );
});

Deno.test("get_my_training_hub 1.9 is the 1.8 definition plus the all-versions sessions, the athlete's local date and current_workout_id only", async () => {
  const hunks: Hunks = [
    [
      "), workouts as (\n  select w.*,",
      "), local_day as (\n  select private.local_date_for(auth.uid()) as today\n), workouts as (\n  select w.*,",
    ],
    [
      "), completed as (\n  select s.id,s.planned_workout_id,s.local_date,s.duration_seconds,\n    s.session_energy,s.session_effort,s.notes,s.completed_at,w.name,\n    s.completion_source,s.session_effort_source\n  from public.workout_sessions s\n  join workouts w on w.id=s.planned_workout_id\n  where s.user_id=auth.uid() and s.state='completed'\n    and s.local_date >= current_date-greatest(7,least(period_days,365))+1\n), progression as (",
      "), completed as (\n  -- Every finished session in the window, whichever plan version it was done under: a Coach change, a\n  -- block or a deload copies the workouts under new ids, and the sessions logged before stay done.\n  -- current_workout_id is the active version's workout with the same name and order, when it has one.\n  select s.id,s.planned_workout_id,s.local_date,s.duration_seconds,\n    s.session_energy,s.session_effort,s.notes,s.completed_at,w.name,\n    s.completion_source,s.session_effort_source,\n    (select aw.id from workouts aw where aw.workout_order=w.workout_order\n      and lower(btrim(aw.name))=lower(btrim(w.name)) limit 1) current_workout_id\n  from public.workout_sessions s\n  join public.planned_workouts w on w.id=s.planned_workout_id and w.user_id=s.user_id\n  where s.user_id=auth.uid() and s.state='completed'\n    and s.local_date >= (select today from local_day)-greatest(7,least(period_days,365))+1\n), progression as (",
    ],
    [
      "  where s.user_id=auth.uid() and s.state='completed' and es.completed\n    and s.local_date >= current_date-greatest(7,least(period_days,365))+1\n  group by",
      "  where s.user_id=auth.uid() and s.state='completed' and es.completed\n    and s.local_date >= (select today from local_day)-greatest(7,least(period_days,365))+1\n  group by",
    ],
    [
      "    and dcm.local_date=current_date\n",
      "    and dcm.local_date=(select today from local_day)\n",
    ],
    [
      "'schema_version','1.8','period_days'",
      "'schema_version','1.9','period_days'",
    ],
    [
      "  'local_today',private.local_date_for(auth.uid()),\n",
      "  'local_today',(select today from local_day),\n",
    ],
    [
      "  'today_workout',private.planned_workout_for_date(auth.uid(),current_date),\n",
      "  'today_workout',private.planned_workout_for_date(auth.uid(),(select today from local_day)),\n",
    ],
    [
      "    'id',id,'workout_id',planned_workout_id,'name',name,'local_date',local_date,\n",
      "    'id',id,'workout_id',planned_workout_id,'current_workout_id',current_workout_id,'name',name,'local_date',local_date,\n",
    ],
    [
      "  'daily_load',private.daily_load(auth.uid(),private.local_date_for(auth.uid())),\n",
      "  'daily_load',private.daily_load(auth.uid(),(select today from local_day)),\n",
    ],
  ];
  await pinned(
    "20261023140024_day_adjustments.sql",
    "create or replace function public.get_my_training_hub(",
    "create or replace function public.get_my_training_hub(",
    "$$;",
    hunks,
  );
});

Deno.test("a workout's identity is its name and order, across the athlete's own plan versions", () => {
  const helper = between(
    integrity,
    "create function private.workout_identity_ids(",
    "from public, anon, authenticated;",
  );
  assert(helper.includes("o.user_id = w.user_id and o.workout_order = w.workout_order"));
  assert(helper.includes("lower(btrim(o.name)) = lower(btrim(w.name))"));
  assert(helper.includes("w.id = p_workout and w.user_id = p_user"));
  assert(helper.includes("array[p_workout]"));
  assert(!helper.includes("plan_version_id"), "no version filter: every version counts");
  assert(helper.includes("set search_path = ''"));
  assert(!helper.includes("security definer"), "called from definer functions only");
});

Deno.test("the future-day refusal comes right after authentication, with the day-adjustment errcodes' neighbours", () => {
  const start = between(
    integrity,
    "create or replace function public.start_workout(",
    "end $$;",
  );
  const auth = start.indexOf("authentication required");
  const future = start.indexOf("p_local_date > private.local_date_for(auth.uid())");
  const lock = start.indexOf("pg_advisory_xact_lock");
  assert(auth > 0 && future > auth && lock > future);
  assert(start.includes("'cannot start a workout on a future day' using errcode='22023'"));
});

Deno.test("the hub never reads the database's current_date", () => {
  const hub = between(
    integrity,
    "create or replace function public.get_my_training_hub(",
    "$$;",
  );
  assert(!hub.includes("current_date"));
  assert(hub.includes("'schema_version','1.9'"));
  assert(
    !hub.includes("join workouts w on w.id=s.planned_workout_id"),
    "completed is not limited to the active version",
  );
});

Deno.test("the redefined functions keep their grants", () => {
  for (
    const grant of [
      "revoke all on function public.start_workout(uuid, date, text, uuid) from public, anon, authenticated;",
      "grant execute on function public.start_workout(uuid, date, text, uuid) to authenticated;",
      "revoke all on function public.get_my_workout_session(uuid, date) from public, anon, authenticated;",
      "grant execute on function public.get_my_workout_session(uuid, date) to authenticated;",
      "grant execute on function public.get_healthkit_completion_candidate(date) to authenticated;",
      "revoke all on function public.healthkit_auto_complete_workout(uuid, date) from public, anon;",
      "grant execute on function public.healthkit_auto_complete_workout(uuid, date) to authenticated;",
      "revoke all on function public.get_my_training_hub(integer) from public, anon, authenticated;",
      "grant execute on function public.get_my_training_hub(integer) to authenticated;",
    ]
  ) assert(integrity.includes(grant), grant);
});
