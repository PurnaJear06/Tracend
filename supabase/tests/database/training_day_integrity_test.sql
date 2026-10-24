begin;
select no_plan();

-- Training-day integrity (QA audit group A).
--   H1    a session logged under an older plan version stays done: the hub shows it, start_workout
--         refuses a second one, and Apple Health neither offers nor creates another.
--   M-A1  start_workout refuses a day that has not begun for the athlete.
--   L-A1  the hub reads the athlete's local date, not the database's current_date.
-- The zone for the L-A1 and M-A1 athlete is chosen so its local date differs from the database's UTC
-- date at whatever time this runs: Kiritimati (UTC+14) is a day ahead from 10:00 UTC, and Etc/GMT+12
-- (UTC-12) a day behind until 12:00 UTC, so one of the two always differs.

insert into auth.users(id, role) values
  ('e1000000-0000-4000-8000-000000000001', 'authenticated'),
  ('e1000000-0000-4000-8000-000000000002', 'authenticated'),
  ('e1000000-0000-4000-8000-000000000003', 'authenticated');
update public.user_accounts set timezone = case
    when (statement_timestamp() at time zone 'Pacific/Kiritimati')::date
      <> (statement_timestamp() at time zone 'UTC')::date then 'Pacific/Kiritimati'
    else 'Etc/GMT+12' end
  where id = 'e1000000-0000-4000-8000-000000000003';

create temporary table t as
  select private.local_date_for('e1000000-0000-4000-8000-000000000001') as today,
         private.local_date_for('e1000000-0000-4000-8000-000000000003') as far_today,
         (statement_timestamp() at time zone 'UTC')::date as utc_today;
grant select on t to authenticated;
create temporary table ids(name text primary key, id uuid);
grant select on ids to authenticated;

-- Source 'imported' keeps the seed trigger from adding its own workouts.
insert into public.training_plans(id, user_id, title, source) values
  ('e1100000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'Strength', 'imported'),
  ('e1100000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000002', 'Strength', 'imported'),
  ('e1100000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000003', 'Strength', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('e1200000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001',
   'e1100000-0000-4000-8000-000000000001', 1, 'active', 6, 2, '{}', 'Approved', now(), current_date - 30),
  ('e1200000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000002',
   'e1100000-0000-4000-8000-000000000002', 1, 'active', 6, 2, '{}', 'Approved', now(), current_date - 30),
  ('e1200000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000003',
   'e1100000-0000-4000-8000-000000000003', 1, 'active', 6, 7, '{}', 'Approved', now(), current_date - 30);

-- Athletes 1 and 2: Upper A on the athlete's weekday today, Upper B on the next.
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
select src.wid, src.uid, src.vid, src.ord, src.wname, 'Press',
  ((extract(isodow from private.local_date_for(src.uid))::integer - 1 + src.shift) % 7) + 1,
  50, 'Warm up', 'Cool down'
from (values
  ('e1300000-0000-4000-8000-000000000001'::uuid, 'e1000000-0000-4000-8000-000000000001'::uuid,
   'e1200000-0000-4000-8000-000000000001'::uuid, 1::smallint, 'Upper A', 0),
  ('e1300000-0000-4000-8000-000000000002'::uuid, 'e1000000-0000-4000-8000-000000000001'::uuid,
   'e1200000-0000-4000-8000-000000000001'::uuid, 2::smallint, 'Upper B', 1),
  ('e1300000-0000-4000-8000-000000000003'::uuid, 'e1000000-0000-4000-8000-000000000002'::uuid,
   'e1200000-0000-4000-8000-000000000002'::uuid, 1::smallint, 'Upper A', 0)
) as src(wid, uid, vid, ord, wname, shift);
insert into public.planned_exercises(user_id, planned_workout_id, exercise_order, display_name_snapshot,
  set_count, rep_min, rep_max, rest_seconds, exercise_slug)
select w.user_id, w.id, 1, 'Barbell bench press', 3, 5, 8, 120, 'barbell-bench-press'
from public.planned_workouts w where w.user_id in ('e1000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000002');

-- Athlete 3 trains every weekday, so there is always a workout on the local day.
insert into public.planned_workouts(user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
select 'e1000000-0000-4000-8000-000000000003', 'e1200000-0000-4000-8000-000000000003', day,
  'Day ' || day, 'Train', day, 45, 'Warm up', 'Cool down'
from generate_series(1, 7) day;

-- Athlete 1 logged Upper A today under plan version 1.
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
  session_effort_source, completion_source)
values ('e1400000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001',
  'e1200000-0000-4000-8000-000000000001', 'e1300000-0000-4000-8000-000000000001',
  (select today from t), 'UTC', 'completed', gen_random_uuid(), now(), 3000, 8, 'athlete', 'manual');

-- Apple Health saw a workout today for athletes 1 and 2.
insert into public.daily_health_summaries(user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at, workout_count, workout_minutes)
select u.id, private.local_date_for(u.id), 'UTC', array['workouts']::text[],
  '[{"type":"workouts","source_id_hash":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","sample_id_hash":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}]'::jsonb,
  repeat('f', 64), 'complete', now(), now(), 1, 60
from (values ('e1000000-0000-4000-8000-000000000001'::uuid),
  ('e1000000-0000-4000-8000-000000000002'::uuid)) as u(id);

-- Athlete 2 has the same plan and the same Apple Health workout, and logged nothing: the control.

-- The plan version changes the way a Coach change, a block restore or a deload changes it: the workouts
-- are copied under new ids (private.clone_plan_version, the copy those paths use).
select private.clone_plan_version('e1200000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000001', null, 'A Coach change');
select private.clone_plan_version('e1200000-0000-4000-8000-000000000002',
  'e1000000-0000-4000-8000-000000000002', null, 'A Coach change');
insert into ids
select 'a1_' || w.name, w.id from public.planned_workouts w
join public.training_plan_versions v on v.id = w.plan_version_id and v.status = 'active'
where w.user_id = 'e1000000-0000-4000-8000-000000000001';
insert into ids
select 'a2_' || w.name, w.id from public.planned_workouts w
join public.training_plan_versions v on v.id = w.plan_version_id and v.status = 'active'
where w.user_id = 'e1000000-0000-4000-8000-000000000002';

select ok((select id from ids where name = 'a1_Upper A') <> 'e1300000-0000-4000-8000-000000000001'::uuid,
  'the copy has new workout ids, as the Coach paths make them');
select is((select count(*) from public.training_plan_versions
  where user_id = 'e1000000-0000-4000-8000-000000000001' and status = 'active'), 1::bigint,
  'and exactly one active version');

-- The identity helper -----------------------------------------------------------------------------

select is((select cardinality(private.workout_identity_ids('e1000000-0000-4000-8000-000000000001',
  (select id from ids where name = 'a1_Upper A')))), 2,
  'a workout and its copy share an identity');
select ok('e1300000-0000-4000-8000-000000000001'::uuid = any(private.workout_identity_ids(
  'e1000000-0000-4000-8000-000000000001', (select id from ids where name = 'a1_Upper A'))),
  'the identity reaches back to the older version');
select ok(not ('e1300000-0000-4000-8000-000000000002'::uuid = any(private.workout_identity_ids(
  'e1000000-0000-4000-8000-000000000001', (select id from ids where name = 'a1_Upper A')))),
  'another workout of the plan is another identity');
select ok(not ('e1300000-0000-4000-8000-000000000003'::uuid = any(private.workout_identity_ids(
  'e1000000-0000-4000-8000-000000000001', (select id from ids where name = 'a1_Upper A')))),
  'and another athlete''s workout of the same name is not shared');
select is(private.workout_identity_ids('e1000000-0000-4000-8000-000000000001',
  'ffffffff-ffff-4fff-8fff-ffffffffffff'), array['ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid],
  'an unknown workout is its own identity');
select ok(not has_function_privilege('authenticated', 'private.workout_identity_ids(uuid,uuid)', 'execute'),
  'the helper is not callable by the app');

-- H1: the hub keeps the day done ------------------------------------------------------------------

create temporary table hub(who text primary key, j jsonb);
grant all on hub to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" = 'e1000000-0000-4000-8000-000000000001';
insert into hub select 'a1', public.get_my_training_hub(28);

select is((select j->>'schema_version' from hub where who = 'a1'), '1.9', 'hub schema 1.9');
select is((select j->'completed_day_set' from hub where who = 'a1'), to_jsonb(array[(select today from t)]),
  'the day logged under version 1 is done under version 2');
select is((select jsonb_array_length(j->'recent_sessions') from hub where who = 'a1'), 1,
  'the session is in the history');
select is((select j->'recent_sessions'->0->>'workout_id' from hub where who = 'a1'),
  'e1300000-0000-4000-8000-000000000001', 'still pointing at the workout it was logged under');
select is((select j->'recent_sessions'->0->>'current_workout_id' from hub where who = 'a1'),
  (select id::text from ids where name = 'a1_Upper A'),
  'and at the active version''s copy of it');
select is((select j->'recent_sessions'->0->>'name' from hub where who = 'a1'), 'Upper A',
  'with the workout''s name');
select is((select j->'adherence'->>'completed_sessions' from hub where who = 'a1'), '1',
  'the week''s count keeps it');
select is((select j->'workouts'->0->>'id' from hub where who = 'a1'),
  (select id::text from ids where name = 'a1_Upper A'), 'the hub lists the active version''s workouts');

-- A session of a workout the active plan no longer has is still a done session.
reset role;
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
values ('e1300000-0000-4000-8000-000000000009', 'e1000000-0000-4000-8000-000000000001',
  'e1200000-0000-4000-8000-000000000001', 3, 'Retired', 'Press', 7, 50, 'Warm up', 'Cool down');
insert into public.workout_sessions(user_id, plan_version_id, planned_workout_id, local_date, timezone,
  state, idempotency_key, completed_at, duration_seconds, session_effort, session_effort_source,
  completion_source)
values ('e1000000-0000-4000-8000-000000000001', 'e1200000-0000-4000-8000-000000000001',
  'e1300000-0000-4000-8000-000000000009', (select today from t) - 2, 'UTC', 'completed',
  gen_random_uuid(), now() - interval '2 days', 3000, 8, 'athlete', 'manual');
set local role authenticated;
set local "request.jwt.claim.sub" = 'e1000000-0000-4000-8000-000000000001';
delete from hub where who = 'a1';
insert into hub select 'a1', public.get_my_training_hub(28);
select is((select jsonb_array_length(j->'recent_sessions') from hub where who = 'a1'), 2,
  'a session of a workout the active plan has no copy of is still listed');
select is((select j->'recent_sessions'->1->>'current_workout_id' from hub where who = 'a1'), null,
  'with no current workout');
select ok((select j->'completed_day_set' from hub where who = 'a1') @> to_jsonb(array[(select today from t) - 2]),
  'and its day is done');

-- H1: starting the same workout again is refused --------------------------------------------------

select throws_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select id from ids where name = 'a1_Upper A'), (select today from t)),
  '55000', 'workout already completed for this coaching day',
  'the copy of a workout done today cannot be started today');
select is(public.get_my_workout_session((select id from ids where name = 'a1_Upper A'),
  (select today from t))->>'session_id', 'e1400000-0000-4000-8000-000000000001',
  'the session read finds the finished session of the older version');
select lives_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select id from ids where name = 'a1_Upper B'), (select today from t)),
  'a different workout of the plan can');
select lives_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select id from ids where name = 'a1_Upper A'), (select today from t) - 1),
  'and the same workout on another day can');

-- H1: Apple Health ----------------------------------------------------------------------------------

select ok(public.get_healthkit_completion_candidate((select today from t)) is null,
  'Apple Health offers nothing for a day already logged under the older version');
select is((public.healthkit_auto_complete_workout((select id from ids where name = 'a1_Upper A'),
  (select today from t)))->>'replayed', 'true',
  'and auto-completing the copy replays instead of logging a second session');
select is((select count(*) from public.workout_sessions s
  where s.state = 'completed' and s.local_date = (select today from t)), 1::bigint,
  'one completed session that day');

-- The control: nothing was logged, so Apple Health offers the day and completes it once.
set local "request.jwt.claim.sub" = 'e1000000-0000-4000-8000-000000000002';
select is(public.get_healthkit_completion_candidate((select today from t))->>'planned_workout_id',
  (select id::text from ids where name = 'a2_Upper A'), 'with nothing logged, Apple Health offers the day');
select is((public.healthkit_auto_complete_workout((select id from ids where name = 'a2_Upper A'),
  (select today from t)))->>'replayed', 'false', 'and completes it');
select ok(public.get_healthkit_completion_candidate((select today from t)) is null,
  'once');
select throws_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select id from ids where name = 'a2_Upper A'), (select today from t)),
  '55000', 'workout already completed for this coaching day', 'and then it cannot be started');

-- M-A1 and L-A1 --------------------------------------------------------------------------------------

reset role;
-- Two stored days: the athlete's local today and the database's UTC today, with different load ratios.
insert into public.daily_computed_metrics(user_id, local_date, data_confidence, scores_jsonb)
values ('e1000000-0000-4000-8000-000000000003', (select far_today from t), 'high',
    '{"acwr": 1.11, "training_monotony": 1.2, "daily_strain": 33}'::jsonb),
  ('e1000000-0000-4000-8000-000000000003', (select utc_today from t), 'high',
    '{"acwr": 9.99, "training_monotony": 9.9, "daily_strain": 99}'::jsonb);
-- One session on each side of the 28-day window's edge: local today - 27 is inside, - 28 is outside.
insert into public.workout_sessions(user_id, plan_version_id, planned_workout_id, local_date, timezone,
  state, idempotency_key, completed_at, duration_seconds, session_effort, session_effort_source,
  completion_source)
select 'e1000000-0000-4000-8000-000000000003', 'e1200000-0000-4000-8000-000000000003', w.id,
  (select far_today from t) - e.d, 'UTC', 'completed', gen_random_uuid(), now(), 3000, 8, 'athlete', 'manual'
from (values (27, 1), (28, 2)) as e(d, o)
join public.planned_workouts w on w.user_id = 'e1000000-0000-4000-8000-000000000003'
  and w.workout_order = e.o;

set local role authenticated;
set local "request.jwt.claim.sub" = 'e1000000-0000-4000-8000-000000000003';
insert into hub select 'far', public.get_my_training_hub(28);

select isnt((select far_today from t), (select utc_today from t),
  'the athlete''s local date differs from the database''s date');
select is((select j->>'local_today' from hub where who = 'far'), (select far_today::text from t),
  'the hub reports the local date');
select is((select j->'daily_load'->27->>'local_date' from hub where who = 'far'), (select far_today::text from t),
  'its 28 days end on it');
select is((select (j->'today_workout'->>'weekday')::integer from hub where who = 'far'),
  extract(isodow from (select far_today from t))::integer,
  'today''s workout is the local weekday''s');
select is((select (j->'computed'->>'acwr')::numeric from hub where who = 'far'), 1.11,
  'the load numbers are the local day''s, not the database date''s');
select is((select jsonb_array_length(j->'recent_sessions') from hub where who = 'far'), 1,
  'the 28-day window starts 27 days before the local date: one session in, one out');
select is((select j->'recent_sessions'->0->>'local_date' from hub where who = 'far'),
  ((select far_today from t) - 27)::text, 'the one inside the window');

select throws_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select w.id from public.planned_workouts w where w.user_id = 'e1000000-0000-4000-8000-000000000003'
    and w.preferred_weekday = extract(isodow from (select far_today from t) + 1)::integer),
  (select far_today from t) + 1),
  '22023', 'cannot start a workout on a future day', 'a day that has not begun cannot be started');
select throws_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select w.id from public.planned_workouts w where w.user_id = 'e1000000-0000-4000-8000-000000000003'
    and w.preferred_weekday = extract(isodow from (select far_today from t) + 30)::integer),
  (select far_today from t) + 30),
  '22023', 'cannot start a workout on a future day', 'nor one far ahead');
select lives_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select w.id from public.planned_workouts w where w.user_id = 'e1000000-0000-4000-8000-000000000003'
    and w.preferred_weekday = extract(isodow from (select far_today from t))::integer),
  (select far_today from t)),
  'the athlete''s own today can, whatever the database''s date is');
select lives_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select w.id from public.planned_workouts w where w.user_id = 'e1000000-0000-4000-8000-000000000003'
    and w.preferred_weekday = extract(isodow from (select far_today from t) - 2)::integer),
  (select far_today from t) - 2),
  'and an earlier day can');


-- ---------------------------------------------------------------------------------------------------
-- Review round 1: the in-progress identity, the weekday rule, another day's workout, and the edges.
-- ---------------------------------------------------------------------------------------------------

reset role;
insert into auth.users(id, role)
select ('e1000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'authenticated'
from generate_series(4, 16) n;

create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('e1000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid
$$;
create temporary table sv(name text primary key, id uuid, j jsonb);
grant all on sv to authenticated;

-- Athlete n: Upper A today (order 1) and Lower A tomorrow (order 2), each with a bench press.
create function pg_temp.mkplan(n integer) returns void language plpgsql as $$
declare
  uid uuid := pg_temp.u(n);
  pl uuid := gen_random_uuid(); v uuid := gen_random_uuid();
  w1 uuid := gen_random_uuid(); w2 uuid := gen_random_uuid();
  d integer := extract(isodow from private.local_date_for(uid))::integer;
begin
  insert into public.user_profiles(user_id, experience_level, equipment)
  values (uid, 'intermediate', array['dumbbells', 'barbell', 'bench', 'cables', 'machines']);
  insert into public.training_plans(id, user_id, title, source) values (pl, uid, 'Plan', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, uid, pl, 1, 'active', 6, 2, '{}', 'Approved', now(), current_date - 30);
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (w1, uid, v, 1, 'Upper A', 'Press', d, 50, 'Warm up', 'Cool down'),
    (w2, uid, v, 2, 'Lower A', 'Squat', (d % 7) + 1, 50, 'Warm up', 'Cool down');
  insert into public.planned_exercises(user_id, planned_workout_id, exercise_order, display_name_snapshot,
    set_count, rep_min, rep_max, rest_seconds, exercise_slug)
  select uid, x, 1, 'Barbell bench press', 3, 5, 8, 120, 'barbell-bench-press' from unnest(array[w1, w2]) x;
  insert into sv(name, id) values ('p' || n || '_v1', v), ('p' || n || '_Upper A_v1', w1),
    ('p' || n || '_Lower A_v1', w2);
end $$;

-- The plan copied under new ids, as a Coach change does.
create function pg_temp.clone(n integer) returns void language plpgsql as $$
declare uid uuid := pg_temp.u(n); v2 uuid;
begin
  v2 := private.clone_plan_version((select id from sv where name = 'p' || n || '_v1'), uid, null, 'A Coach change');
  insert into sv(name, id) values ('p' || n || '_v2', v2);
  insert into sv(name, id)
  select 'p' || n || '_' || w.name || '_v2', w.id from public.planned_workouts w where w.plan_version_id = v2;
end $$;

-- A session of athlete n's workout w (version ver) p_ago days back, with p_sets completed bench sets.
create function pg_temp.log_session(n integer, ver text, w text, p_ago integer, p_state text, p_sets integer default 0)
returns uuid language plpgsql as $$
declare
  uid uuid := pg_temp.u(n); sid uuid := gen_random_uuid(); pid uuid;
  wid uuid := (select id from sv where name = 'p' || n || '_' || w || '_' || ver);
  vid uuid := (select id from sv where name = 'p' || n || '_' || ver);
begin
  insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date, timezone,
    state, idempotency_key, completed_at, duration_seconds, session_effort, session_effort_source,
    completion_source)
  values (sid, uid, vid, wid, private.local_date_for(uid) - p_ago, 'UTC', p_state, gen_random_uuid(),
    case when p_state = 'completed' then now() end, case when p_state = 'completed' then 3000 end,
    case when p_state = 'completed' then 8 end, case when p_state = 'completed' then 'athlete' end,
    case when p_state = 'completed' then 'manual' end);
  if p_sets > 0 then
    insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id, exercise_order,
      status, performance_kind)
    select uid, sid, e.id, 1, 'performed', 'prescribed' from public.planned_exercises e
    where e.planned_workout_id = wid returning id into pid;
    insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg, completed)
    select uid, pid, g, 8, 60, true from generate_series(1, p_sets) g;
  end if;
  return sid;
end $$;

create function pg_temp.today(n integer) returns date language sql security definer as $$
  select private.local_date_for(pg_temp.u(n))
$$;
create function pg_temp.unavailable(n integer, d date) returns text language sql as $$
  select private.day_adjustment_compute(pg_temp.u(n), d, true) -> 'payload' ->> 'unavailable_reason'
$$;
create function pg_temp.as_user(n integer) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', pg_temp.u(n)::text, true); end $$;

-- M1: a session in progress under version 1 is the day's session under version 2 ----------------------

select pg_temp.mkplan(4);
set local role authenticated;
select pg_temp.as_user(4);
insert into sv(name, id) select 's4_first', public.start_workout((select id from sv where name = 'p4_Upper A_v1'),
  pg_temp.today(4), 'UTC', gen_random_uuid());
reset role;
select pg_temp.clone(4);
set local role authenticated;
select pg_temp.as_user(4);
insert into sv(name, id) select 's4_second', public.start_workout((select id from sv where name = 'p4_Upper A_v2'),
  pg_temp.today(4), 'UTC', gen_random_uuid());
select is((select id from sv where name = 's4_second'), (select id from sv where name = 's4_first'),
  'starting the copy of a workout in progress returns the session in progress');
select is((select count(*) from public.workout_sessions where state = 'in_progress'), 1::bigint,
  'and no second session starts');
select is(public.get_my_workout_session((select id from sv where name = 'p4_Upper A_v2'), pg_temp.today(4))
  ->> 'session_id', (select id::text from sv where name = 's4_first'), 'the copy reads the same session');
reset role;
select is(pg_temp.unavailable(4, pg_temp.today(4)), 'session_started',
  'and the readiness card is not offered again for a workout already started');

-- L7: the day done under version 1 is done for the readiness card ---------------------------------------

select pg_temp.mkplan(5);
select pg_temp.log_session(5, 'v1', 'Upper A', 0, 'completed', 3);
select pg_temp.clone(5);
select is(pg_temp.unavailable(5, pg_temp.today(5)), 'session_done',
  'a workout done under version 1 reads as done for the copy''s day');

-- L7: the unfinished list --------------------------------------------------------------------------------

select pg_temp.mkplan(6);
select pg_temp.clone(6);
insert into sv(name, id) values ('s6_up', pg_temp.log_session(6, 'v1', 'Upper A', 3, 'abandoned', 2)),
  ('s6_low', pg_temp.log_session(6, 'v1', 'Lower A', 2, 'abandoned', 2));
insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
select pg_temp.u(6), 'workout.abandoned', 'workout_session', id, 'succeeded', '{"reason": "stale"}'::jsonb
from sv where name in ('s6_up', 's6_low');
select is((select count(*) from private.unfinished_workouts(pg_temp.u(6), pg_temp.today(6))), 2::bigint,
  'two stopped sessions are unfinished');
select pg_temp.log_session(6, 'v2', 'Upper A', 3, 'completed', 3);
select is((select array_agg(workout_name) from private.unfinished_workouts(pg_temp.u(6), pg_temp.today(6))),
  array['Lower A'], 'the one the athlete finished that day under the copy is no longer unfinished');

-- L7: a renamed workout, and the same name at another place in the plan, are other workouts -------------

select pg_temp.mkplan(7);
select pg_temp.log_session(7, 'v1', 'Upper A', 0, 'completed', 3);
select pg_temp.clone(7);
update public.planned_workouts set name = 'Upper Alpha' where id = (select id from sv where name = 'p7_Upper A_v2');
select is(cardinality(private.workout_identity_ids(pg_temp.u(7), (select id from sv where name = 'p7_Upper A_v2'))), 1,
  'a renamed workout shares no identity with its older copy');
select pg_temp.mkplan(8);
select pg_temp.log_session(8, 'v1', 'Upper A', 0, 'completed', 3);
select pg_temp.clone(8);
update public.planned_workouts set workout_order = 3 where id = (select id from sv where name = 'p8_Upper A_v2');
select is(cardinality(private.workout_identity_ids(pg_temp.u(8), (select id from sv where name = 'p8_Upper A_v2'))), 1,
  'the same name at another place in the plan is another workout');
set local role authenticated;
select pg_temp.as_user(7);
select lives_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select id from sv where name = 'p7_Upper A_v2'), pg_temp.today(7)), 'so a renamed workout can be started');
select pg_temp.as_user(8);
select lives_ok(format($q$select public.start_workout(%L, %L, 'UTC', gen_random_uuid())$q$,
  (select id from sv where name = 'p8_Upper A_v2'), pg_temp.today(8)), 'and so can the same name elsewhere in the plan');
reset role;

-- M2: one weekday rule ---------------------------------------------------------------------------------

create function pg_temp.bare(n integer, p_days smallint[], p_count integer) returns void language plpgsql as $$
declare
  uid uuid := pg_temp.u(n); pl uuid := gen_random_uuid(); v uuid := gen_random_uuid();
begin
  insert into public.user_profiles(user_id, experience_level, training_days)
  values (uid, 'intermediate', coalesce(p_days, '{}'::smallint[]));
  insert into public.training_plans(id, user_id, title, source) values (pl, uid, 'Plan', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, uid, pl, 1, 'active', 6, p_count, '{}', 'Approved', now(), current_date - 30);
  insert into sv(name, id) values ('p' || n || '_v1', v);
  -- A Coach structure whose workouts carry no weekday.
  perform private.coach_insert_workouts(uid, v, (select jsonb_agg(jsonb_build_object(
      'workout_order', g, 'name', 'W' || g, 'objective', 'Train', 'preferred_weekday', null::text,
      'estimated_minutes', 45, 'warm_up_guidance', 'Warm up', 'cool_down_guidance', 'Cool down',
      'exercises', jsonb_build_array(jsonb_build_object('exercise_order', 1, 'slug', null::text, 'name', 'Squat',
        'sets', 3, 'rep_min', 5, 'rep_max', 8, 'target_rpe', 8, 'rest_seconds', 120, 'start_load_kg', null::numeric))))
    from generate_series(1, p_count) g));
end $$;
create function pg_temp.days(n integer) returns smallint[] language sql as $$
  select array_agg(w.preferred_weekday order by w.workout_order) from public.planned_workouts w
  where w.plan_version_id = (select id from sv where name = 'p' || n || '_v1')
$$;

select pg_temp.bare(9, null, 3);
select is(pg_temp.days(9), array[1, 3, 5]::smallint[], 'a structure with no weekdays and no profile days is spread');
select pg_temp.bare(10, array[2, 4, 6]::smallint[], 3);
select is(pg_temp.days(10), array[2, 4, 6]::smallint[], 'the profile''s days when they are as many as the workouts');
select pg_temp.bare(11, array[2, 5]::smallint[], 3);
select is(pg_temp.days(11), array[1, 3, 5]::smallint[], 'the spread when they are not');
select pg_temp.bare(12, null, 1);
select is(pg_temp.days(12), array[1]::smallint[], 'a lone workout gets Monday');
select pg_temp.bare(13, null, 4);
select is(pg_temp.days(13), array[1, 2, 4, 5]::smallint[], 'four workouts: Monday, Tuesday, Thursday, Friday');

-- Server readers agree with those days: a training day is a workout, the others rest.
create temporary table mon as
  select (current_date + ((8 - extract(isodow from current_date)::integer) % 7)) as d;
select is((private.planned_workout_for_date(pg_temp.u(9), (select d from mon)) ->> 'name'), 'W1', 'Monday: the first workout');
select is((private.planned_workout_for_date(pg_temp.u(9), (select d + 2 from mon)) ->> 'name'), 'W2', 'Wednesday: the second');
select is((private.planned_workout_for_date(pg_temp.u(9), (select d + 4 from mon)) ->> 'name'), 'W3', 'Friday: the third');
select ok(private.planned_workout_for_date(pg_temp.u(9), (select d + 1 from mon)) is null, 'Tuesday: rest');
select isnt(pg_temp.unavailable(9, (select d from mon)), 'rest_day', 'a training day is not a rest day for the readiness card');
select is(pg_temp.unavailable(9, (select d + 1 from mon)), 'rest_day', 'and the others are');

-- Existing versions: the same rule fills a version whose workouts have none, and leaves others alone.
select pg_temp.mkplan(14);
update public.planned_workouts set preferred_weekday = null
where plan_version_id = (select id from sv where name = 'p14_v1');
select private.fill_workout_weekdays((select id from sv where name = 'p14_v1'));
select is(pg_temp.days(14), array[1, 4]::smallint[], 'a version with none is filled in plan order (two workouts: Monday, Thursday)');
update public.planned_workouts set preferred_weekday = 6 where id = (select id from sv where name = 'p14_Lower A_v1');
update public.planned_workouts set preferred_weekday = null where id = (select id from sv where name = 'p14_Upper A_v1');
select private.fill_workout_weekdays((select id from sv where name = 'p14_v1'));
select ok(pg_temp.days(14) is not distinct from array[null, 6]::smallint[], 'and a version with some weekdays is left as it is');

-- M3: another day's workout started today keeps the joint rules ----------------------------------------

create function pg_temp.legs(n integer) returns void language plpgsql as $$
declare
  uid uuid := pg_temp.u(n); pl uuid := gen_random_uuid(); v uuid := gen_random_uuid();
  w1 uuid := gen_random_uuid(); w2 uuid := gen_random_uuid();
  d integer := extract(isodow from private.local_date_for(uid))::integer;
begin
  insert into public.user_profiles(user_id, experience_level, equipment)
  values (uid, 'intermediate', array['dumbbells', 'barbell', 'bench', 'cables', 'machines']);
  insert into public.training_plans(id, user_id, title, source) values (pl, uid, 'Plan', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, uid, pl, 1, 'active', 6, 2, '{}', 'Approved', now(), current_date - 30);
  -- Legs is today's workout; Legs B is the next day's.
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (w1, uid, v, 1, 'Legs', 'Squat', d, 50, 'Warm up', 'Cool down'),
    (w2, uid, v, 2, 'Legs B', 'Squat', (d % 7) + 1, 50, 'Warm up', 'Cool down');
  insert into public.planned_exercises(user_id, planned_workout_id, exercise_order, display_name_snapshot,
    set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
  select uid, x, o, nm, 3, 8, 12, 8, 60, slug
  from unnest(array[w1, w2]) x,
    (values (1, 'Barbell bench press', 'barbell-bench-press'), (2, 'Leg extension', 'leg-extension')) as e(o, nm, slug);
  insert into sv(name, id) values ('p' || n || '_today', w1), ('p' || n || '_next', w2);
  -- A knee held on a clinician flag yesterday.
  insert into public.pain_reports(user_id, local_date, source, area, severity, red_flags,
    cleared_by_clinician, outcome, created_at)
  values (uid, private.local_date_for(uid) - 1, 'workout', 'knee', 3, array['locks_gives_way'], false,
    private.pain_outcome(3, array['locks_gives_way']), clock_timestamp() - interval '1 day');
end $$;
create function pg_temp.sets_of(p_session uuid) returns bigint[] language sql as $$
  select array_agg((select count(*) from public.exercise_sets s where s.exercise_performance_id = p.id)
    order by p.exercise_order)
  from public.exercise_performances p where p.workout_session_id = p_session
$$;

select pg_temp.legs(15);
select pg_temp.legs(16);
set local role authenticated;
select pg_temp.as_user(15);
insert into sv(name, id) select 's15', public.start_workout((select id from sv where name = 'p15_next'),
  pg_temp.today(15), 'UTC', gen_random_uuid());
select is(pg_temp.sets_of((select id from sv where name = 's15')), array[3::bigint, 0],
  'tomorrow''s workout started today leaves out what the held knee leaves out');
select is((select p.status from public.exercise_performances p where p.workout_session_id =
    (select id from sv where name = 's15') and p.exercise_order = 2), 'unknown', 'which is not inferred as skipped');
select pg_temp.as_user(16);
insert into sv(name, id) select 's16', public.start_workout((select id from sv where name = 'p16_today'),
  pg_temp.today(16), 'UTC', gen_random_uuid());
select is(pg_temp.sets_of((select id from sv where name = 's16')), array[3::bigint, 3],
  'the day''s own workout is built as written: the readiness card is where its joint changes are answered');
reset role;

select * from finish();
rollback;
