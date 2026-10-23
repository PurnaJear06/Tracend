begin;
select plan(46);

-- A trains; B is another athlete. Sessions are inserted the way the app left them months ago.
insert into auth.users(id, role) values
  ('d1300000-0000-4000-8000-000000000001', 'authenticated'),
  ('d1300000-0000-4000-8000-000000000002', 'authenticated');

-- Source 'imported' keeps the seed trigger from adding its own workouts.
insert into public.training_plans(id, user_id, title, source) values
  ('d1310000-0000-4000-8000-000000000001', 'd1300000-0000-4000-8000-000000000001', 'Legs', 'imported'),
  ('d1310000-0000-4000-8000-000000000002', 'd1300000-0000-4000-8000-000000000002', 'Other', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('d1320000-0000-4000-8000-000000000001', 'd1300000-0000-4000-8000-000000000001',
   'd1310000-0000-4000-8000-000000000001', 1, 'active', 6, 3, '{}', 'Approved', now(), current_date),
  ('d1320000-0000-4000-8000-000000000002', 'd1300000-0000-4000-8000-000000000002',
   'd1310000-0000-4000-8000-000000000002', 1, 'active', 6, 1, '{}', 'Approved', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('d1330000-0000-4000-8000-000000000001', 'd1300000-0000-4000-8000-000000000001',
   'd1320000-0000-4000-8000-000000000001', 1, 'Legs B', 'Squat', 1, 50, 'Warm up', 'Cool down'),
  ('d1330000-0000-4000-8000-000000000002', 'd1300000-0000-4000-8000-000000000001',
   'd1320000-0000-4000-8000-000000000001', 2, 'Upper', 'Press', 2, 50, 'Warm up', 'Cool down'),
  ('d1330000-0000-4000-8000-000000000003', 'd1300000-0000-4000-8000-000000000001',
   'd1320000-0000-4000-8000-000000000001', 3, 'Pull', 'Row', 3, 50, 'Warm up', 'Cool down'),
  ('d1330000-0000-4000-8000-000000000004', 'd1300000-0000-4000-8000-000000000002',
   'd1320000-0000-4000-8000-000000000002', 1, 'Any', 'Train', 1, 50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds) values
  ('d1340000-0000-4000-8000-000000000001', 'd1300000-0000-4000-8000-000000000001',
   'd1330000-0000-4000-8000-000000000001', 1, 'Back squat', 2, 5, 8, 120);

create temporary table t as
  select private.local_date_for('d1300000-0000-4000-8000-000000000001') today;
grant select on t to authenticated;
create temporary table flow(name text primary key, id uuid);
create temporary table h(name text primary key, j jsonb);
grant all on flow, h to authenticated;

-- Legs B: left in_progress 98 days ago after one set was logged.
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at)
select 'd1350000-0000-4000-8000-000000000001', 'd1300000-0000-4000-8000-000000000001',
  'd1320000-0000-4000-8000-000000000001', 'd1330000-0000-4000-8000-000000000001',
  today - 98, 'UTC', 'in_progress', 'd1360000-0000-4000-8000-000000000001',
  now() - interval '98 days', now() - interval '98 days' from t;
insert into public.exercise_performances(id, user_id, workout_session_id, planned_exercise_id,
  exercise_order, status, performance_kind, performed_name) values
  ('d1370000-0000-4000-8000-000000000001', 'd1300000-0000-4000-8000-000000000001',
   'd1350000-0000-4000-8000-000000000001', 'd1340000-0000-4000-8000-000000000001', 1, 'performed',
   'prescribed', 'Back squat');
insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
  completed) values
  ('d1300000-0000-4000-8000-000000000001', 'd1370000-0000-4000-8000-000000000001', 1, 5, 100, true),
  ('d1300000-0000-4000-8000-000000000001', 'd1370000-0000-4000-8000-000000000001', 2, null, null, false);

-- Upper: started 1 hour ago under yesterday's date (a workout that crossed midnight).
-- Pull: started 5 hours ago today (the app was killed and is reopened).
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at)
select 'd1350000-0000-4000-8000-000000000002', 'd1300000-0000-4000-8000-000000000001',
  'd1320000-0000-4000-8000-000000000001', 'd1330000-0000-4000-8000-000000000002',
  today - 1, 'UTC', 'in_progress', 'd1360000-0000-4000-8000-000000000002',
  now() - interval '1 hour', now() - interval '1 hour' from t;
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at)
select 'd1350000-0000-4000-8000-000000000003', 'd1300000-0000-4000-8000-000000000001',
  'd1320000-0000-4000-8000-000000000001', 'd1330000-0000-4000-8000-000000000003',
  today, 'UTC', 'in_progress', 'd1360000-0000-4000-8000-000000000003',
  now() - interval '5 hours', now() - interval '5 hours' from t;

-- Finished and discarded sessions of earlier days stay as they are.
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at, completed_at, updated_at)
select 'd1350000-0000-4000-8000-000000000004', 'd1300000-0000-4000-8000-000000000001',
  'd1320000-0000-4000-8000-000000000001', 'd1330000-0000-4000-8000-000000000002',
  today - 30, 'UTC', 'completed', 'd1360000-0000-4000-8000-000000000004',
  now() - interval '30 days', now() - interval '30 days', now() - interval '29 days',
  now() - interval '29 days' from t;
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at, completed_at, updated_at)
select 'd1350000-0000-4000-8000-000000000005', 'd1300000-0000-4000-8000-000000000001',
  'd1320000-0000-4000-8000-000000000001', 'd1330000-0000-4000-8000-000000000002',
  today - 10, 'UTC', 'abandoned', 'd1360000-0000-4000-8000-000000000005',
  now() - interval '10 days', now() - interval '10 days', null,
  now() - interval '10 days' from t;

-- B left a workout open 5 days ago.
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at)
select 'd1350000-0000-4000-8000-000000000006', 'd1300000-0000-4000-8000-000000000002',
  'd1320000-0000-4000-8000-000000000002', 'd1330000-0000-4000-8000-000000000004',
  today - 5, 'UTC', 'in_progress', 'd1360000-0000-4000-8000-000000000006',
  now() - interval '5 days', now() - interval '5 days' from t;

-- Surface -------------------------------------------------------------------------------------

select has_function('private', 'abandon_stale_workouts', array['uuid'], 'the stale rule exists');
select ok(not has_function_privilege('authenticated', 'private.abandon_stale_workouts(uuid)', 'execute'),
  'and no API role can run it');
select ok(not has_function_privilege('anon', 'public.get_my_workout_session(uuid,date)', 'execute'),
  'anon cannot read a session');
select ok(has_function_privilege('authenticated', 'public.get_my_workout_session(uuid,date)', 'execute'),
  'the athlete can');
select is((select schedule from cron.job where jobname = 'tracend-abandon-stale-workouts'),
  '17 * * * *', 'an hourly job closes stale workouts for everyone');

-- Opening today's workout -------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1300000-0000-4000-8000-000000000001';

select is(public.get_my_workout_session('d1330000-0000-4000-8000-000000000001',
    (select today from t)), null, 'a session from months ago is not resumed today');
insert into flow select 'today', public.start_workout('d1330000-0000-4000-8000-000000000001',
  (select today from t), 'UTC', 'd1360000-0000-4000-8000-000000000010');
insert into h select 'legs', public.get_my_workout_session('d1330000-0000-4000-8000-000000000001',
  (select today from t));
insert into h select 'pull', public.get_my_workout_session('d1330000-0000-4000-8000-000000000003',
  (select today from t));
insert into h select 'upper', public.get_my_workout_session('d1330000-0000-4000-8000-000000000002',
  (select today from t));

reset role;

-- The old session -------------------------------------------------------------------------------

select is((select state::text from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000001'), 'abandoned',
  'the old session ends abandoned');
select is((select local_date from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000001'), (select today - 98 from t),
  'on its own date');
select is((select actual_ended_at from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000001'), null, 'with no invented end time');
select is((select count(*) from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id
    where p.workout_session_id = 'd1350000-0000-4000-8000-000000000001' and s.completed),
  1::bigint, 'its logged set is intact');
select is((select count(*) from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id
    where p.workout_session_id = 'd1350000-0000-4000-8000-000000000001'),
  2::bigint, 'with all its rows');
select is((select s.load_kg from public.exercise_sets s
    where s.exercise_performance_id = 'd1370000-0000-4000-8000-000000000001' and s.set_number = 1),
  100::numeric, 'and its values');
select is((select metadata from public.audit_events
    where target_id = 'd1350000-0000-4000-8000-000000000001' and action_code = 'workout.abandoned'),
  jsonb_build_object('reason', 'stale', 'completed_sets', 1,
    'local_date', (select today - 98 from t)), 'the close is audited with its set count');
select is((select count(*) from public.audit_events where action_code = 'workout.abandoned'),
  1::bigint, 'and only that one');

-- Today's session -------------------------------------------------------------------------------

select isnt((select id from flow where name = 'today'), 'd1350000-0000-4000-8000-000000000001'::uuid,
  'starting today creates a new session');
select is((select local_date from public.workout_sessions
    where id = (select id from flow where name = 'today')), (select today from t),
  'on today''s date');
select is((select state::text from public.workout_sessions
    where id = (select id from flow where name = 'today')), 'in_progress', 'which is open');
select is((select count(*) from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id
    where p.workout_session_id = (select id from flow where name = 'today') and s.completed),
  0::bigint, 'with none of the old sets');
select is((select count(*) from public.exercise_performances
    where workout_session_id = 'd1350000-0000-4000-8000-000000000001'),
  1::bigint, 'and the old sets stay with the old session');

-- Resuming ------------------------------------------------------------------------------------

select is((select j->>'session_id' from h where name = 'pull'), 'd1350000-0000-4000-8000-000000000003',
  'a workout opened again the same day resumes');
select is((select j->>'state' from h where name = 'pull'), 'in_progress', 'still in progress');
select is((select j->>'session_id' from h where name = 'upper'), 'd1350000-0000-4000-8000-000000000002',
  'a workout that crossed midnight and is under three hours old resumes');
select is((select count(*) from public.workout_sessions
    where id in ('d1350000-0000-4000-8000-000000000002', 'd1350000-0000-4000-8000-000000000003')
      and state = 'in_progress'), 2::bigint, 'neither was closed');
select is((select j->>'session_id' from h where name = 'legs'), (select id::text from flow where name = 'today'),
  'reading Legs B again returns today''s session');
select is((select (j->>'actual_started_at')::timestamptz > now() - interval '3 hours' from h where name = 'legs'),
  true, 'which began just now, so its timer starts from zero');

-- Other days and other athletes ----------------------------------------------------------------

select is((select state::text from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000004'), 'completed', 'a finished session is untouched');
select is((select updated_at from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000005'), now() - interval '10 days',
  'and so is an earlier discard');
select is((select state::text from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000006'), 'in_progress',
  'another athlete''s session is not closed by A opening a workout');
select is(private.abandon_stale_workouts(), 1, 'the hourly job closes it');
select is((select state::text from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000006'), 'abandoned', 'as abandoned');
select is(private.abandon_stale_workouts(), 0, 'and a second run closes nothing');
select is(private.abandon_stale_workouts('d1300000-0000-4000-8000-000000000001'), 0,
  'nor does a run for one athlete');

-- A workout finished offline -------------------------------------------------------------------

-- Offline: logged at 23:30 yesterday, still unsent when the hourly job runs.
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('d1330000-0000-4000-8000-000000000005', 'd1300000-0000-4000-8000-000000000001',
   'd1320000-0000-4000-8000-000000000001', 5, 'Offline', 'Row', 5, 50, 'Warm up', 'Cool down'),
  ('d1330000-0000-4000-8000-000000000006', 'd1300000-0000-4000-8000-000000000001',
   'd1320000-0000-4000-8000-000000000001', 6, 'Discarded', 'Row', 6, 50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds) values
  ('d1340000-0000-4000-8000-000000000005', 'd1300000-0000-4000-8000-000000000001',
   'd1330000-0000-4000-8000-000000000005', 1, 'Row', 2, 8, 10, 90);
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at)
select 'd1350000-0000-4000-8000-000000000007', 'd1300000-0000-4000-8000-000000000001',
  'd1320000-0000-4000-8000-000000000001', 'd1330000-0000-4000-8000-000000000005',
  today - 1, 'UTC', 'in_progress', 'd1360000-0000-4000-8000-000000000007',
  now() - interval '26 hours', now() - interval '26 hours' from t;
insert into public.exercise_performances(id, user_id, workout_session_id, planned_exercise_id,
  exercise_order, status, performance_kind, performed_name) values
  ('d1370000-0000-4000-8000-000000000007', 'd1300000-0000-4000-8000-000000000001',
   'd1350000-0000-4000-8000-000000000007', 'd1340000-0000-4000-8000-000000000005', 1, 'unknown',
   'prescribed', 'Row');
insert into public.exercise_sets(user_id, exercise_performance_id, set_number) values
  ('d1300000-0000-4000-8000-000000000001', 'd1370000-0000-4000-8000-000000000007', 1),
  ('d1300000-0000-4000-8000-000000000001', 'd1370000-0000-4000-8000-000000000007', 2);
-- A workout the athlete discarded herself.
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key)
select 'd1350000-0000-4000-8000-000000000008', 'd1300000-0000-4000-8000-000000000001',
  'd1320000-0000-4000-8000-000000000001', 'd1330000-0000-4000-8000-000000000006',
  today, 'UTC', 'in_progress', 'd1360000-0000-4000-8000-000000000008' from t;

select is(private.abandon_stale_workouts('d1300000-0000-4000-8000-000000000001'), 1,
  'the job closes an offline workout before its finish arrives');
select is((select state::text from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000007'), 'abandoned', 'as abandoned');

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1300000-0000-4000-8000-000000000001';

select is(public.sync_workout_draft('d1350000-0000-4000-8000-000000000007', 1,
    jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object('order', 1,
      'status', 'unknown', 'sets', jsonb_build_array(jsonb_build_object('number', 1,
        'repetitions', '8', 'load_kg', '60', 'rpe', '8', 'completed', true))))))->>'replayed',
  'false', 'the athlete''s unsent sets are accepted into it');
select is(public.complete_workout_v2('d1350000-0000-4000-8000-000000000007', 1, 2400, 7,
    'sent a day late')->>'replayed', 'false', 'and so is her finish');

select is(public.abandon_workout('d1350000-0000-4000-8000-000000000008')->>'replayed', 'false',
  'a workout she discards herself is discarded');
select throws_ok($$select public.sync_workout_draft('d1350000-0000-4000-8000-000000000008', 1,
    '{"exercises":[]}'::jsonb)$$, '55000', null, 'and takes no more sets');
select throws_ok($$select public.complete_workout_v2('d1350000-0000-4000-8000-000000000008', 1, 600, 5,
    '')$$, '55000', null, 'and is not finished');

reset role;

select is((select state::text from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000007'), 'completed', 'the late finish completes it');
select is((select local_date from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000007'), (select today - 1 from t),
  'on its own date');
select is((select actual_ended_at - actual_started_at from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000007'), interval '2400 seconds',
  'its end is its own start plus its own duration, not the day it was sent');
select is((select duration_seconds from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000007'), 2400, 'with that duration');
select is((select load_kg from public.exercise_sets
    where exercise_performance_id = 'd1370000-0000-4000-8000-000000000007' and set_number = 1 and completed),
  60::numeric, 'and its set');
select is((select count(*) from public.audit_events
    where target_id = 'd1350000-0000-4000-8000-000000000007' and action_code = 'workout.completed'),
  1::bigint, 'the completion is audited');
select is((select state::text from public.workout_sessions
    where id = 'd1350000-0000-4000-8000-000000000008'), 'abandoned', 'the self-discarded one stays discarded');

select * from finish();
rollback;
