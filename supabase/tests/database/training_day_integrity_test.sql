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

select * from finish();
rollback;
