begin;
select no_plan();

-- Training counts (20261102194352): the effort band's hard edge, holds that are not stalls, the first day
-- of training in every planned count, and one Apple Health completion a day.

-- 1. Progression -------------------------------------------------------------------------------------------

-- A session summary as private.next_session_targets builds it (latest first in the array).
create function pg_temp.sess(p_load numeric, p_reps integer[], p_min_rir integer, p_date date default null)
returns jsonb language sql as $$
  select jsonb_build_object('local_date', p_date, 'load_kg', p_load, 'sets', cardinality(p_reps),
    'min_reps', (select min(r) from unnest(p_reps) r), 'total_reps', (select sum(r) from unnest(p_reps) r),
    'min_rir', p_min_rir, 'effort_known', true, 'pain', false, 'adjusted', false, 'sets_planned', null)
$$;

-- A beginner squat: 3 sets of 8 to 12, 2.5 kg step, three days since the last session.
create function pg_temp.squat(p_rpe numeric, p_sessions jsonb)
returns jsonb language sql as $$
  select private.progression_decision(3, 8, 12, p_rpe, 2.5, 3, false, false, false, p_sessions)
$$;

-- The band edges: logging the hard edge of the band is on target, one rep fewer is harder than planned.
select is(pg_temp.squat(7, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 3))) ->> 'action', 'add_reps',
  'RPE 7 (3 reps left): 3 left is on target');
select is(pg_temp.squat(7, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 2))) ->> 'reason', 'effort',
  'RPE 7: 2 left is harder than planned and holds');
select is(pg_temp.squat(7.5, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 3))) ->> 'action', 'add_reps',
  'RPE 7.5 (2 to 3 reps left): 3 left is on target');
select is(pg_temp.squat(7.5, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 2))) ->> 'action', 'add_reps',
  'RPE 7.5: 2 left is on target too');
select is(pg_temp.squat(7.5, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 1))) ->> 'reason', 'effort',
  'RPE 7.5: 1 left is harder than planned and holds');
select is(pg_temp.squat(8, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 2))) ->> 'action', 'add_reps',
  'RPE 8 (2 reps left): 2 left is on target');
select is(pg_temp.squat(8, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 1))) ->> 'reason', 'effort',
  'RPE 8: 1 left holds');
select is(pg_temp.squat(8.5, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 1))) ->> 'action', 'add_reps',
  'RPE 8.5 (1 to 2 reps left): 1 left is on target');
select is(pg_temp.squat(8.5, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 0))) ->> 'reason', 'effort',
  'RPE 8.5: none left holds');

-- The squat at RPE 7.5, 2 reps left every session, doing what each target asks: reps rise, then the load.
select is(pg_temp.squat(7.5, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 2, '2026-10-05'))),
  '{"action":"add_reps","reason":"within_range","load_kg":60,"reps":11,"sets":3,"confidence":"high"}'::jsonb,
  'squat 60 kg x 10 with 2 reps left: one more rep, not a hold');
select is(pg_temp.squat(7.5, jsonb_build_array(pg_temp.sess(60, '{11,11,11}', 2, '2026-10-08'),
    pg_temp.sess(60, '{10,10,10}', 2, '2026-10-05'))) ->> 'reps', '12',
  'then 11 earns 12');
select is(pg_temp.squat(7.5, jsonb_build_array(pg_temp.sess(60, '{12,12,12}', 2, '2026-10-12'),
    pg_temp.sess(60, '{11,11,11}', 2, '2026-10-08'), pg_temp.sess(60, '{10,10,10}', 2, '2026-10-05'))),
  '{"action":"add_load","reason":"top_of_range","load_kg":62.5,"reps":8,"sets":3,"confidence":"high"}'::jsonb,
  'and 12 on every set earns 62.5 kg: the load never drops to 57.5 kg x 8');

-- Holds are not stalls: RPE 7 logged at 2 reps left holds, and repeating the held reps is what was asked.
select is(pg_temp.squat(7, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 2, '2026-10-12'),
    pg_temp.sess(60, '{10,10,10}', 2, '2026-10-08'), pg_temp.sess(60, '{10,10,10}', 2, '2026-10-05'))),
  '{"action":"hold","reason":"effort","load_kg":60,"reps":10,"sets":3,"confidence":"high"}'::jsonb,
  'three held sessions at the same reps hold again: no stall, no cut');
select is(pg_temp.squat(7, jsonb_build_array(pg_temp.sess(60, '{9,9,9}', 2, '2026-10-12'),
    pg_temp.sess(60, '{10,10,10}', 2, '2026-10-08'), pg_temp.sess(60, '{10,10,10}', 2, '2026-10-05'))),
  '{"action":"lower","reason":"stall","load_kg":57.5,"reps":8,"sets":3,"confidence":"high"}'::jsonb,
  'after holds, fewer reps per set than three sessions ago is still a stall');
select is(pg_temp.squat(7.5, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 2, '2026-10-12'),
    pg_temp.sess(60, '{10,10,10}', 1, '2026-10-08'), pg_temp.sess(60, '{10,10,10}', 2, '2026-10-05'))) ->> 'action',
  'add_reps', 'a session that followed one held for effort is not counted toward a stall');
select is(pg_temp.squat(7.5, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 2, '2026-10-12'),
    pg_temp.sess(60, '{10,10,10}', 2, '2026-10-08'), pg_temp.sess(60, '{10,10,10}', 2, '2026-10-05'))) ->> 'reason',
  'stall', 'while two sessions asked for one more rep and given none are a stall');
select is(pg_temp.squat(7, jsonb_build_array(pg_temp.sess(60, '{10,10,10}', 3, '2026-10-26'),
    pg_temp.sess(60, '{10,10,10}', 3, '2026-10-12'), pg_temp.sess(60, '{10,10,10}', 3, '2026-10-05'))) ->> 'action',
  'add_reps', 'a session after 14 days away followed a hold too, worked out from the dates');

-- 2. The first day of training -------------------------------------------------------------------------

insert into auth.users(id, role) values
  ('c0000000-0000-4000-8000-0000000000a1', 'authenticated'),
  ('c0000000-0000-4000-8000-0000000000b2', 'authenticated'),
  ('c0000000-0000-4000-8000-0000000000c3', 'authenticated'),
  ('c0000000-0000-4000-8000-0000000000d4', 'authenticated');
update public.user_accounts set onboarding_state = 'completed', timezone = 'UTC'
where id::text like 'c0000000-0000-4000-8000-0000000000%';

create temporary table t as select private.local_date_for('c0000000-0000-4000-8000-0000000000a1') as today;
grant select on t to authenticated;

-- A plan with a workout every day ('imported' keeps the seed trigger out). Its effective date and status are
-- the caller's.
create function pg_temp.plan(uid uuid, v uuid, version integer, status public.version_status, starts date)
returns void language plpgsql as $$
declare pl uuid := gen_random_uuid();
begin
  insert into public.training_plans(id, user_id, title, source) values (pl, uid, 'Daily', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, uid, pl, version, status, 6, 7, '{}', 'Approved', now(), starts);
  insert into public.planned_workouts(user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  select uid, v, d, 'Day ' || d, 'Train', d, 40, 'Warm up', 'Cool down' from generate_series(1, 7) d;
end $$;

-- A: the plan began three days ago; yesterday's session is logged and today is a can't-train day.
select pg_temp.plan('c0000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-0000000000a1', 1,
  'active', (select today - 3 from t));
insert into public.workout_sessions(user_id, plan_version_id, planned_workout_id, local_date, timezone, state,
  idempotency_key, completed_at, duration_seconds, session_effort, session_effort_source, completion_source)
select w.user_id, w.plan_version_id, w.id, (select today - 1 from t), 'UTC', 'completed', gen_random_uuid(),
  now() - interval '1 day', 3000, 7, 'athlete', 'manual'
from public.planned_workouts w
where w.plan_version_id = 'c1000000-0000-4000-8000-0000000000a1'
  and w.preferred_weekday = extract(isodow from (select today - 1 from t))::integer;
insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key,
  sleep_quality, energy, soreness, hunger, mood, pain_severity, available_to_train)
values ('c0000000-0000-4000-8000-0000000000a1', (select today from t), 'UTC', 1, gen_random_uuid(),
  5, 5, 1, 3, 5, 0, false);

-- B: a first plan ten days ago, superseded by a Coach change that began yesterday.
select pg_temp.plan('c0000000-0000-4000-8000-0000000000b2', 'c1000000-0000-4000-8000-0000000000b2', 1,
  'superseded', (select today - 10 from t));
select pg_temp.plan('c0000000-0000-4000-8000-0000000000b2', 'c2000000-0000-4000-8000-0000000000b2', 2,
  'active', (select today - 1 from t));

-- C: the plan begins today.
select pg_temp.plan('c0000000-0000-4000-8000-0000000000c3', 'c1000000-0000-4000-8000-0000000000c3', 1,
  'active', (select today from t));

select is(private.training_started_on('c0000000-0000-4000-8000-0000000000a1'), (select today - 3 from t),
  'training starts on the plan''s effective date');
select is(private.training_started_on('c0000000-0000-4000-8000-0000000000b2'), (select today - 10 from t),
  'a later version keeps the first plan''s start, so the days before the change stay due');
select is(private.training_started_on('c0000000-0000-4000-8000-0000000000d4'), null::date,
  'no plan, no start');
select ok(not has_function_privilege('authenticated', 'private.training_started_on(uuid)', 'execute'),
  'clients cannot call the helper');

create temporary table r (who text, j jsonb);
grant insert, select on r to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub" = 'c0000000-0000-4000-8000-0000000000a1';
insert into r select 'a_brief', public.get_my_daily_brief((select today from t));
insert into r select 'a_hub', public.get_my_training_hub(28);
set local "request.jwt.claim.sub" = 'c0000000-0000-4000-8000-0000000000b2';
insert into r select 'b_hub', public.get_my_training_hub(28);
reset role;

select is((select j ->> 'schema_version' from r where who = 'a_brief'), '1.9', 'the brief''s shape is unchanged');
select is((select count(*) from r, jsonb_array_elements(j -> 'week') day
    where who = 'a_brief' and (day ->> 'local_date')::date < (select today - 3 from t)
      and (day ->> 'planned')::boolean), 0::bigint,
  'no day of the week before the plan began is planned');
select is((select count(*) from r, jsonb_array_elements(j -> 'week') day
    where who = 'a_brief' and (day ->> 'local_date')::date between (select today - 3 from t) and (select today - 1 from t)
      and not (day ->> 'planned')::boolean), 0::bigint,
  'the days since it began are planned');
select is((select (day ->> 'planned')::boolean from r, jsonb_array_elements(j -> 'week') day
    where who = 'a_brief' and (day ->> 'local_date')::date = (select today from t)), false,
  'and today''s can''t-train day is not, as before');

select is((select j ->> 'schema_version' from r where who = 'a_hub'), '1.11', 'hub 1.11');
select is((select j ->> 'training_started_on' from r where who = 'a_hub'), (select (today - 3)::text from t),
  'the hub reports the first day of training');
select is((select array[j -> 'adherence' ->> 'completed_sessions', j -> 'adherence' ->> 'planned_sessions',
      j -> 'adherence' ->> 'unavailable_sessions'] from r where who = 'a_hub'),
  array['1', '3', '1'],
  '28 days of a daily plan begun 3 days ago: 4 days since it began, less today''s can''t-train day, 1 done');
select is((select array[j ->> 'training_started_on', j -> 'adherence' ->> 'planned_sessions']
    from r where who = 'b_hub'), array[(select (today - 10)::text from t), '11'],
  'after a Coach change, the days since the first plan began are still planned');

-- The weekly review of this week for A and of last week for C.
create temporary table m as select today - (extract(isodow from today)::integer - 1) as monday from t;
select private.generate_weekly_progress_review(private.enqueue_weekly_review_job(
  'c0000000-0000-4000-8000-0000000000a1', (select monday from m)));
select private.generate_weekly_progress_review(private.enqueue_weekly_review_job(
  'c0000000-0000-4000-8000-0000000000c3', (select monday - 7 from m)));
select is((select (summary -> 'training' ->> 'planned_sessions')::integer from public.progress_reviews
    where user_id = 'c0000000-0000-4000-8000-0000000000a1'),
  7 - least(7, greatest(0, (select today - 3 from t) - (select monday from m))) - 1,
  'the week''s review plans only the days since the plan began, less the can''t-train day');
select is((select summary -> 'training' from public.progress_reviews
    where user_id = 'c0000000-0000-4000-8000-0000000000c3'),
  '{"planned_sessions":0,"completed_workouts":0,"completed_sets":0,"adherence_percent":100}'::jsonb,
  'a week wholly before the plan had nothing due: nothing was missed');
select is((select summary -> 'missing_data' ? 'active_training_plan' from public.progress_reviews
    where user_id = 'c0000000-0000-4000-8000-0000000000c3'), false,
  'and it is not reported as a missing plan');
select is((select f.feature_engine_version from public.feature_snapshots f
    join public.progress_reviews p on p.feature_snapshot_id = f.id
    where p.user_id = 'c0000000-0000-4000-8000-0000000000c3'), 'weekly-deterministic-v2',
  'the snapshot names the new formula');

select is(public.get_coach_plan_state_v1('c0000000-0000-4000-8000-0000000000a1', (select today from t))
    ->> 'schema_version', '1.4', 'Coach plan state 1.4');
select is(public.get_coach_plan_state_v1('c0000000-0000-4000-8000-0000000000b2', (select today from t))
    ->> 'training_started_on', (select (today - 10)::text from t), 'carries the first day of training');

-- 3. One Apple Health completion a day ------------------------------------------------------------------

insert into public.daily_health_summaries(user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at, workout_count, workout_minutes)
values ('c0000000-0000-4000-8000-0000000000c3', (select today from t), 'UTC', array['workouts']::text[],
  '[{"type":"workouts","source_id_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sample_id_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]'::jsonb,
  repeat('c', 64), 'complete', now(), now(), 1, 45);
create function pg_temp.mark_complete() returns jsonb language sql as $$
  select public.healthkit_auto_complete_workout((select w.id from public.planned_workouts w
    where w.plan_version_id = 'c1000000-0000-4000-8000-0000000000c3'
      and w.preferred_weekday = extract(isodow from (select today from t))::integer), (select today from t))
$$;
create temporary table hk (n integer, j jsonb);
grant insert, select on hk to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub" = 'c0000000-0000-4000-8000-0000000000c3';
insert into hk select 1, pg_temp.mark_complete();
insert into hk select 2, pg_temp.mark_complete();
reset role;
select is((select j ->> 'replayed' from hk where n = 2), 'true', 'a second Mark complete replays');
select is((select j ->> 'session_id' from hk where n = 2), (select j ->> 'session_id' from hk where n = 1),
  'and returns the session the first one saved');
select is((select count(*) from public.workout_sessions
    where user_id = 'c0000000-0000-4000-8000-0000000000c3' and state = 'completed'), 1::bigint,
  'one completed session for the day');
select ok((select p.prosrc like '%pg_advisory_xact_lock(hashtextextended(%''day_adjustment:'' || v_user_id::text%'
    from pg_proc p where p.oid = 'public.healthkit_auto_complete_workout(uuid,date)'::regprocedure),
  'it takes start_workout''s day lock, so two taps at once never both insert');

select * from finish();
rollback;
