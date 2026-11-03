import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

// The training-counts migration redefines seven functions. Each must be its latest earlier definition plus
// the intended hunks and nothing else, so everything else it does is what the earlier migrations (and their
// pgTAP tests) already proved.
const read = (name: string) =>
  Deno.readTextFile(new URL(`../../../../migrations/${name}`, import.meta.url));
const counts = await read("20261102194352_training_counts.sql");

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
  return text;
}

async function pinned(
  file: string,
  start: string,
  redefinedStart: string,
  end: string,
  hunks: Hunks,
) {
  const earlier = between(await read(file), start, end);
  const redefined = between(counts, redefinedStart, end);
  assertEquals(undo(redefined, hunks), earlier);
}

Deno.test("progression_decision is its latest earlier definition plus the training-counts hunks only", async () => {
  const hunks: Hunks = [
    [
      "  v_rir_target integer := case when p_target_rpe is null then 2\n    else greatest(0, least(5, round(10 - p_target_rpe)::integer)) end;\n",
      "  -- The hard edge of the target's reps-left band (10 - RPE): RPE 7.5 is 2 to 3 reps left, so 2 or 3\n  -- is on target and only fewer than 2 is harder than planned (RPE 7: 3, RPE 8: 2, RPE 8.5: 1).\n  v_rir_target integer := case when p_target_rpe is null then 2\n    else greatest(0, least(5, floor(10 - p_target_rpe)::integer)) end;\n",
    ],
    [
      "  v_lower_load numeric;\nbegin\n",
      "  v_lower_load numeric;\n  v_followed_hold boolean := false;\nbegin\n",
    ],
    [
      "  v_reps := v_hold_reps;\n\n",
      "  v_reps := v_hold_reps;\n  -- Whether the session before the latest or the latest one followed a hold, as worked out from the\n  -- sessions before each, with what happened between them (a skipped or a pain-flagged performance,\n  -- carried on the later session as skipped_before and pain_before): repeating what a hold asked for\n  -- is not a stall, so then only fewer reps per set is.\n  if s3 is not null then\n    v_followed_hold := private.progression_decision(p_set_count, p_rep_min, p_rep_max,\n        p_target_rpe, p_step_kg,\n        coalesce((s2 ->> 'local_date')::date - (s3 ->> 'local_date')::date, 0),\n        coalesce((s2 ->> 'skipped_before')::boolean, false),\n        coalesce((s2 ->> 'pain_before')::boolean, false),\n        p_assisted, jsonb_build_array(s3)) ->> 'action' = 'hold'\n      or private.progression_decision(p_set_count, p_rep_min, p_rep_max,\n        p_target_rpe, p_step_kg,\n        coalesce((s1 ->> 'local_date')::date - (s2 ->> 'local_date')::date, 0),\n        coalesce((s1 ->> 'skipped_before')::boolean, false),\n        coalesce((s1 ->> 'pain_before')::boolean, false),\n        p_assisted, jsonb_build_array(s2, s3)) ->> 'action' = 'hold';\n  end if;\n\n",
    ],
    [
      "        and (s1 ->> 'total_reps')::integer * (s3 ->> 'sets')::integer\n          <= (s3 ->> 'total_reps')::integer * (s1 ->> 'sets')::integer then\n",
      "        and ((s1 ->> 'total_reps')::integer * (s3 ->> 'sets')::integer\n            < (s3 ->> 'total_reps')::integer * (s1 ->> 'sets')::integer\n          or (not v_followed_hold\n            and (s1 ->> 'total_reps')::integer * (s3 ->> 'sets')::integer\n              = (s3 ->> 'total_reps')::integer * (s1 ->> 'sets')::integer)) then\n",
    ],
  ];
  await pinned(
    "20261024060025_pain_checks.sql",
    "create or replace function private.progression_decision(",
    "create or replace function private.progression_decision(",
    "end $$;",
    hunks,
  );
});

Deno.test("next_session_targets is its latest earlier definition plus the training-counts hunks only", async () => {
  const hunks: Hunks = [
    [
      "), ranked as (\n  select s.*, row_number() over (partition by s.planned_exercise_id\n    order by s.local_date desc, s.completed_at desc) as rn\n  from marked s\n), recent as (",
      "), ranked as (\n  select s.*, row_number() over w as rn,\n    lead(s.local_date) over w as older_date, lead(s.completed_at) over w as older_completed_at\n  from marked s\n  window w as (partition by s.planned_exercise_id order by s.local_date desc, s.completed_at desc)\n), chained as (\n  -- What happened between a session and the one before it: a skipped performance, or one flagged for\n  -- pain even though no set was logged that day. progression_decision reads them when it works out\n  -- whether the earlier sessions followed a hold, so a hold for a skip or for pain is never counted\n  -- as a stall.\n  select r.*,\n    exists (select 1 from perf sk where sk.planned_exercise_id = r.planned_exercise_id\n      and sk.status = 'skipped'\n      and (sk.local_date, sk.completed_at) > (r.older_date, r.older_completed_at)\n      and (sk.local_date, sk.completed_at) < (r.local_date, r.completed_at)) as skipped_before,\n    exists (select 1 from perf pn where pn.planned_exercise_id = r.planned_exercise_id\n      and pn.pain_flag\n      and (pn.local_date, pn.completed_at) > (r.older_date, r.older_completed_at)\n      and (pn.local_date, pn.completed_at) < (r.local_date, r.completed_at)) as pain_before\n  from ranked r where r.rn <= 3\n), recent as (",
    ],
    [
      "      'sets_planned', r.sets_planned) order by r.rn) as sess\n  from ranked r where r.rn <= 3 group by r.planned_exercise_id",
      "      'sets_planned', r.sets_planned, 'skipped_before', r.skipped_before,\n      'pain_before', r.pain_before) order by r.rn) as sess\n  from chained r group by r.planned_exercise_id",
    ],
  ];
  await pinned(
    "20261024060325_deload_cardio_review_fixes.sql",
    "create or replace function private.next_session_targets(",
    "create or replace function private.next_session_targets(",
    "$$;",
    hunks,
  );
});

Deno.test("get_my_daily_brief is its latest earlier definition plus the training-counts hunks only", async () => {
  const hunks: Hunks = [
    [
      "        -- adherence); paused says which days a break covers.\n",
      "        -- adherence); paused says which days a break covers. A day before the athlete's first plan\n        -- began was never due either.\n",
    ],
    [
      "            and w.preferred_weekday = extract(isodow from d.day)::integer)\n",
      "            and w.preferred_weekday = extract(isodow from d.day)::integer\n            and d.day >= private.training_started_on(v_user_id))\n",
    ],
  ];
  await pinned(
    "20261101200000_coach_standing_state.sql",
    "create or replace function public.get_my_daily_brief(",
    "create or replace function public.get_my_daily_brief(",
    "\n$$;",
    hunks,
  );
});

Deno.test("get_my_training_hub is its latest earlier definition plus the training-counts hunks only", async () => {
  const hunks: Hunks = [
    [
      "), rest_sessions as (\n",
      "), started as (\n  select private.training_started_on(auth.uid()) as d\n), before_start as (\n  -- Planned sessions on days before the athlete's first plan began: never due and never missed, so\n  -- left out of adherence (a plan approved on a Thursday does not start the week behind).\n  select count(*)::integer as sessions\n  from (select g::date as d from generate_series(\n      ((select today from local_day)-greatest(7,least(period_days,365))+1)::timestamp,\n      (select today from local_day)::timestamp, interval '1 day') g) x\n  join workouts w on w.preferred_weekday=extract(isodow from x.d)::integer\n  where x.d < (select d from started)\n    and not exists (select 1 from completed c where c.local_date=x.d)\n), rest_sessions as (\n",
    ],
    [
      "  where private.is_rest_day(auth.uid(),x.d)\n",
      "  where private.is_rest_day(auth.uid(),x.d) and x.d >= (select d from started)\n",
    ],
    [
      "'schema_version','1.10'",
      "'schema_version','1.11'",
    ],
    [
      "  'local_today',(select today from local_day),\n",
      "  'local_today',(select today from local_day),\n  'training_started_on',(select d from started),\n",
    ],
    [
      "      - (select paused+unavailable from rest_sessions)),\n",
      "      - (select paused+unavailable from rest_sessions) - (select sessions from before_start)),\n",
    ],
  ];
  await pinned(
    "20261101200000_coach_standing_state.sql",
    "create or replace function public.get_my_training_hub(",
    "create or replace function public.get_my_training_hub(",
    "\n$$;",
    hunks,
  );
});

Deno.test("generate_weekly_progress_review is its latest earlier definition plus the training-counts hunks only", async () => {
  const hunks: Hunks = [
    [
      "create function private.generate_weekly_progress_review(",
      "create or replace function private.generate_weekly_progress_review(",
    ],
    [
      "  adherence_percent integer;\nbegin\n",
      "  adherence_percent integer;\n  has_plan boolean;\nbegin\n",
    ],
    [
      "  where user_id = job.user_id and status = 'active';\n",
      "  where user_id = job.user_id and status = 'active';\n  -- Days before the athlete's first plan began and days they chose not to train (a break, a\n  -- can't-train check-in) were never due: their planned sessions are left out, unless a session was\n  -- logged that day.\n  has_plan := planned_sessions > 0;\n  select greatest(0, planned_sessions - count(*)::integer) into planned_sessions\n  from generate_series(job.review_week::timestamp, week_end::timestamp, interval '1 day') g\n  join public.planned_workouts w on w.user_id = job.user_id\n    and w.preferred_weekday = extract(isodow from g)::integer\n  join public.training_plan_versions v on v.id = w.plan_version_id and v.user_id = w.user_id\n    and v.status = 'active'\n  where (g::date < private.training_started_on(job.user_id)\n      or private.is_rest_day(job.user_id, g::date))\n    and not exists (select 1 from public.workout_sessions s where s.user_id = job.user_id\n      and s.local_date = g::date and s.state = 'completed');\n",
    ],
    [
      "  if planned_sessions = 0 then\n    missing := array_append(missing, 'active_training_plan');\n    adherence_percent := 0;\n  else\n",
      "  if not has_plan then\n    missing := array_append(missing, 'active_training_plan');\n    adherence_percent := 0;\n  elsif planned_sessions = 0 then\n    -- Nothing was due this week (it fell before the plan began, or in a break), so there is no\n    -- percentage to report.\n    adherence_percent := null;\n  else\n",
    ],
    [
      "'weekly-deterministic-v1'",
      "'weekly-deterministic-v2'",
    ],
  ];
  await pinned(
    "20260702223000_phase_7_weekly_reviews.sql",
    "create function private.generate_weekly_progress_review(",
    "create or replace function private.generate_weekly_progress_review(",
    "\n$$;",
    hunks,
  );
});

Deno.test("get_coach_plan_state_v1 is its latest earlier definition plus the training-counts hunks only", async () => {
  const hunks: Hunks = [
    [
      "'schema_version', '1.3',",
      "'schema_version', '1.4',",
    ],
    [
      "    'weekday', extract(isodow from p_local_date)::integer,\n",
      "    'weekday', extract(isodow from p_local_date)::integer,\n    -- The first day of the athlete's first plan: a session on an earlier day was never due.\n    'training_started_on', private.training_started_on(p_user_id),\n",
    ],
  ];
  await pinned(
    "20261024050011_unfinished_workouts.sql",
    "create or replace function public.get_coach_plan_state_v1(",
    "create or replace function public.get_coach_plan_state_v1(",
    "\n$$;",
    hunks,
  );
});

Deno.test("healthkit_auto_complete_workout is its latest earlier definition plus the training-counts hunks only", async () => {
  const hunks: Hunks = [
    [
      "    raise exception 'authentication required';\n  end if;\n",
      "    raise exception 'authentication required';\n  end if;\n  -- The lock start_workout takes for the day: a second tap waits for the first and then finds its\n  -- session, so one workout is never completed twice for one day.\n  perform pg_advisory_xact_lock(hashtextextended(\n    'day_adjustment:' || v_user_id::text || coalesce(p_local_date::text, ''), 0));\n",
    ],
    [
      "  if exists (\n    select 1 from public.workout_sessions\n    where user_id = v_user_id\n",
      "  select id into v_session_id from public.workout_sessions\n    where user_id = v_user_id\n",
    ],
    [
      "      and state = 'completed'\n  ) then\n    return jsonb_build_object('session_id', null, 'replayed', true);\n  end if;\n",
      "      and state = 'completed'\n    order by completed_at limit 1;\n  if v_session_id is not null then\n    return jsonb_build_object('session_id', v_session_id, 'replayed', true);\n  end if;\n",
    ],
  ];
  await pinned(
    "20261024090000_training_day_integrity.sql",
    "create or replace function public.healthkit_auto_complete_workout(",
    "create or replace function public.healthkit_auto_complete_workout(",
    "\n$$;",
    hunks,
  );
});

Deno.test("the migration revokes the new helper from every client role", () => {
  assert(
    counts.includes(
      "revoke all on function private.training_started_on(uuid) from public, anon, authenticated;",
    ),
  );
});
