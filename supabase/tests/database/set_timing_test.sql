begin;
select plan(63);

-- A logs a workout with set timing; B is another athlete.
insert into auth.users(id, role) values
  ('c1300000-0000-4000-8000-000000000001', 'authenticated'),
  ('c1300000-0000-4000-8000-000000000002', 'authenticated');

-- Source 'imported' keeps the seed trigger from adding its own workouts.
insert into public.training_plans(id, user_id, title, source) values
  ('c1310000-0000-4000-8000-000000000001', 'c1300000-0000-4000-8000-000000000001', 'Timing', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('c1320000-0000-4000-8000-000000000001', 'c1300000-0000-4000-8000-000000000001',
   'c1310000-0000-4000-8000-000000000001', 1, 'active', 6, 2, '{}', 'Approved', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('c1330000-0000-4000-8000-000000000001', 'c1300000-0000-4000-8000-000000000001',
   'c1320000-0000-4000-8000-000000000001', 1, 'Upper', 'Press', 1, 50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds) values
  ('c1340000-0000-4000-8000-000000000001', 'c1300000-0000-4000-8000-000000000001',
   'c1330000-0000-4000-8000-000000000001', 1, 'Timing press', 2, 6, 8, 90);

create temporary table flow(name text primary key, id uuid);
create temporary table h(j jsonb);
grant all on flow, h to authenticated;

-- Syncs exercise 1 with the given sets at the given revision.
create function pg_temp.sync_sets(revision integer, sets jsonb)
returns jsonb language sql as $$
  select public.sync_workout_draft((select id from flow where name = 'a'), revision,
    jsonb_build_object('exercises', jsonb_build_array(
      jsonb_build_object('order', 1, 'status', 'unknown', 'sets', sets))));
$$;

-- One set of exercise 1 as stored.
create function pg_temp.stored_set(wanted integer)
returns public.exercise_sets language sql as $$
  select s.* from public.exercise_sets s
  join public.exercise_performances p on p.id = s.exercise_performance_id
  where p.workout_session_id = (select id from flow where name = 'a') and s.set_number = wanted;
$$;

-- Columns --------------------------------------------------------------------------------------

select has_column('public', 'exercise_sets', 'started_at', 'sets record when they started');
select col_type_is('public', 'exercise_sets', 'started_at', 'timestamp with time zone',
  'started_at is a timestamptz');
select col_is_null('public', 'exercise_sets', 'started_at', 'started_at is nullable');
select col_type_is('public', 'exercise_sets', 'completed_at', 'timestamp with time zone',
  'completed_at is a timestamptz');
select col_is_null('public', 'exercise_sets', 'completed_at', 'completed_at is nullable');
select col_type_is('public', 'exercise_sets', 'rest_before_seconds', 'integer',
  'rest_before_seconds is an integer');
select col_is_null('public', 'exercise_sets', 'rest_before_seconds', 'rest_before_seconds is nullable');
select col_type_is('public', 'exercise_sets', 'rir', 'smallint', 'rir is a smallint');
select col_is_null('public', 'exercise_sets', 'rir', 'rir is nullable');
select col_type_is('public', 'exercise_sets', 'timing_source', 'text', 'timing_source is text');
select col_is_null('public', 'exercise_sets', 'timing_source', 'timing_source is nullable');
select ok(not has_table_privilege('authenticated', 'public.exercise_sets', 'update'),
  'clients still change sets only through the sync RPC');

-- Draft sync -----------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c1300000-0000-4000-8000-000000000001';

insert into flow select 'a', public.start_workout('c1330000-0000-4000-8000-000000000001',
  current_date, 'UTC', 'c1350000-0000-4000-8000-000000000001');

select is(pg_temp.sync_sets(1, jsonb_build_array(jsonb_build_object(
    'number', 1, 'repetitions', '8', 'load_kg', '60', 'rpe', '8', 'completed', true,
    'started_at', to_jsonb(now() - interval '2 minutes'),
    'completed_at', to_jsonb(now() - interval '1 minute'),
    'rest_before_seconds', 95, 'rir', 2, 'timing_source', 'app')))->>'replayed',
  'false', 'a draft with set timing syncs');
select is((select array[started_at, completed_at] from pg_temp.stored_set(1)),
  array[now() - interval '2 minutes', now() - interval '1 minute'], 'start and end are stored');
select is((select array[rest_before_seconds, rir::integer] from pg_temp.stored_set(1)),
  array[95, 2], 'the rest taken and the reps left are stored');
select is((select timing_source from pg_temp.stored_set(1)), 'app', 'and who timed it');
select is((select array[repetitions::numeric, load_kg, rpe] from pg_temp.stored_set(1)),
  array[8, 60, 8]::numeric[], 'the existing fields sync as before');

-- An installed build (build 340) sends none of the new keys.
select is(pg_temp.sync_sets(2, '[{"number":1,"repetitions":"9","load_kg":"60","completed":true}]')
    ->>'replayed', 'false', 'a draft from an older build syncs');
select is((select array[started_at, completed_at] from pg_temp.stored_set(1)),
  array[now() - interval '2 minutes', now() - interval '1 minute'],
  'an older build keeps the stored times');
select is((select array[rest_before_seconds, rir::integer] from pg_temp.stored_set(1)),
  array[95, 2], 'and the stored rest and reps left');
select is((select timing_source from pg_temp.stored_set(1)), 'app', 'and the timing source');
select is((select array[repetitions::numeric, rpe] from pg_temp.stored_set(1)),
  array[9, null]::numeric[], 'the existing fields keep their rule: written as sent, blank when absent');

select is(pg_temp.sync_sets(2, '[{"number":1,"rir":0}]')->>'replayed', 'true',
  'a stale revision is a replay');
select is((select rir::integer from pg_temp.stored_set(1)), 2, 'and changes nothing');

select is(pg_temp.sync_sets(3, '[{"number":1,"completed":false,"completed_at":null,"rir":null}]')
    ->>'replayed', 'false', 'an un-ticked set syncs');
select is((select array[completed_at::text, rir::text] from pg_temp.stored_set(1)),
  array[null, null], 'an explicit null clears a value');
select is((select started_at from pg_temp.stored_set(1)), now() - interval '2 minutes',
  'a missing key still keeps its value');

-- Invalid values are refused with 22023 and change nothing.
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"rir":6}]')$$, '22023', null,
  'reps left above 5 is refused');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"rir":-1}]')$$, '22023', null,
  'negative reps left is refused');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"rir":2.5}]')$$, '22023', null,
  'reps left is a whole number');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"rir":"2"}]')$$, '22023', null,
  'reps left is a number, not text');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"rest_before_seconds":-1}]')$$,
  '22023', null, 'negative rest is refused');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"rest_before_seconds":3601}]')$$,
  '22023', null, 'rest over an hour is refused');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"timing_source":"phone"}]')$$,
  '22023', null, 'an unknown timing source is refused');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"timing_source":1}]')$$,
  '22023', null, 'a timing source is text');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"started_at":"yesterday"}]')$$,
  '22023', null, 'a time that is not ISO 8601 is refused');
select throws_ok($$select pg_temp.sync_sets(4, jsonb_build_array(jsonb_build_object('number', 1,
    'started_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'))))$$,
  '22023', null, 'a time without a time zone is refused');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"started_at":"2026-02-30T10:00:00Z"}]')$$,
  '22023', null, 'a date that does not exist is refused');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":1,"started_at":1760000000}]')$$,
  '22023', null, 'a time is a string');
select throws_ok($$select pg_temp.sync_sets(4, jsonb_build_array(jsonb_build_object('number', 1,
    'completed_at', to_jsonb(now() + interval '11 minutes'))))$$,
  '22023', null, 'a time more than 10 minutes in the future is refused');
select throws_ok($$select pg_temp.sync_sets(4, jsonb_build_array(jsonb_build_object('number', 1,
    'started_at', to_jsonb(now() - interval '11 minutes'))))$$,
  '22023', null, 'a time more than 10 minutes before the workout started is refused');
select throws_ok($$select pg_temp.sync_sets(4, jsonb_build_array(jsonb_build_object('number', 1,
    'completed_at', to_jsonb(now() - interval '3 minutes'))))$$,
  '22023', null, 'an end before the stored start is refused');
select throws_ok($$select pg_temp.sync_sets(4, jsonb_build_array(jsonb_build_object('number', 2,
    'started_at', to_jsonb(now()), 'completed_at', to_jsonb(now() - interval '1 second'))))$$,
  '22023', null, 'an end before the start in the same draft is refused');
select throws_ok($$select pg_temp.sync_sets(4, '[{"number":3,"rir":1}]')$$, '22023', null,
  'an unknown set is refused');
select is((select array[rir::text, rest_before_seconds::text, timing_source]
    from pg_temp.stored_set(1)), array[null, '95', 'app'], 'refused drafts changed nothing');

select is(pg_temp.sync_sets(4, jsonb_build_array(
    jsonb_build_object('number', 1, 'repetitions', '8', 'load_kg', '60', 'rpe', '8',
      'completed', true, 'started_at', to_jsonb(now() - interval '5 minutes'),
      'completed_at', to_jsonb(now() - interval '4 minutes'), 'rir', 2),
    jsonb_build_object('number', 2, 'repetitions', '7', 'load_kg', '60', 'rpe', '9',
      'completed', true, 'started_at', to_jsonb(now() + interval '4 minutes'),
      'completed_at', to_jsonb(now() + interval '5 minutes'), 'rest_before_seconds', 480,
      'rir', 1, 'timing_source', 'watch')))->>'replayed',
  'false', 'a phone clock a few minutes off either way is accepted');

-- Ownership -------------------------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'c1300000-0000-4000-8000-000000000002';
select throws_ok($$select pg_temp.sync_sets(5, '[{"number":1,"rir":0}]')$$, 'P0002', null,
  'another athlete cannot sync the workout');
select is(public.get_my_workout_session('c1330000-0000-4000-8000-000000000001', current_date),
  null, 'or read it');
select is((select count(*) from public.exercise_sets), 0::bigint, 'or see its sets');

-- Reads -----------------------------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'c1300000-0000-4000-8000-000000000001';
select is((select rir::integer from pg_temp.stored_set(1)), 2, 'the owner''s set is unchanged');

insert into h select public.get_my_workout_session('c1330000-0000-4000-8000-000000000001',
  current_date);
select is((select j->>'schema_version' from h), '1.1', 'workout session schema 1.1');
select is((select array_agg(k order by k) from h, jsonb_object_keys(j->'exercises'->0->'sets'->1) k),
  array['completed', 'completed_at', 'load_kg', 'number', 'repetitions', 'rest_before_seconds', 'rir',
    'rpe', 'started_at', 'timing_source'], 'each set carries the complete key list');
select is((select (j->'exercises'->0->'sets'->1) - 'started_at' - 'completed_at' from h),
  '{"number":2,"repetitions":7,"load_kg":60,"rpe":9.0,"completed":true,"rest_before_seconds":480,"rir":1,"timing_source":"watch"}'::jsonb,
  'and its values');
select is((select (j->'exercises'->0->'sets'->1->>'started_at')::timestamptz from h),
  now() + interval '4 minutes', 'with its start time');

select is(public.complete_workout_v2((select id from flow where name = 'a'), 4, 1800, 7, null)
    ->>'replayed', 'false', 'the workout completes');
delete from h;
insert into h select public.get_my_exercise_history(array['Timing press']);
select is((select j->>'schema_version' from h), '1.1', 'history schema 1.1');
select is((select array_agg(k order by k) from h,
    jsonb_object_keys(j->'exercises'->0->'last_session'->'sets'->0) k),
  array['completed_at', 'load_kg', 'repetitions', 'rest_before_seconds', 'rir', 'rpe', 'set_number',
    'started_at', 'timing_source'], 'last time''s sets carry the complete key list');
select is((select (j->'exercises'->0->'last_session'->'sets'->1)
    - 'started_at' - 'completed_at' from h),
  '{"set_number":2,"load_kg":60,"repetitions":7,"rpe":9.0,"rir":1,"rest_before_seconds":480,"timing_source":"watch"}'::jsonb,
  'with the reps left, rest and timing source of each set');
select is((select (j->'exercises'->0->'last_session'->'sets'->0->>'completed_at')::timestamptz from h),
  now() - interval '4 minutes', 'and its times');

-- The table holds the same rules for any writer.
reset role;
select throws_ok($$update public.exercise_sets set rir = 6
    where id = (select id from pg_temp.stored_set(1))$$, '23514', null,
  'the table refuses reps left above 5');
select throws_ok($$update public.exercise_sets set rest_before_seconds = 3601
    where id = (select id from pg_temp.stored_set(1))$$, '23514', null,
  'the table refuses rest over an hour');
select throws_ok($$update public.exercise_sets set timing_source = 'phone'
    where id = (select id from pg_temp.stored_set(1))$$, '23514', null,
  'the table refuses an unknown timing source');
select throws_ok($$update public.exercise_sets set completed_at = started_at - interval '1 second'
    where id = (select id from pg_temp.stored_set(1))$$, '23514', null,
  'the table refuses an end before the start');

select * from finish();
rollback;
