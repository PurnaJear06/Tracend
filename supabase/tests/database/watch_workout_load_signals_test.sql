-- Watch-workout prompt and load signals (chunk C4, migration 20261023120034_watch_workout_load_signals.sql).
--
-- Under test: get_my_watch_workout_status_v1 (the app's read: the last three finished workouts and
-- the sets a Watch workout tracked) and get_workout_load_inputs_v1 (the engine's read, service role
-- only: finished workouts with the rest and heart-rate summary of each tracked set, and no load,
-- repetitions or reps in reserve). Complete key lists, what is counted and left out, the window and
-- the caps, isolation between athletes and the grants.
begin;
select plan(53);

insert into auth.users(id, role) values
  ('c4400000-0000-4000-8000-000000000001', 'authenticated'),
  ('c4400000-0000-4000-8000-000000000002', 'authenticated');

insert into public.training_plans(id, user_id, title, source) values
  ('c4410000-0000-4000-8000-000000000001', 'c4400000-0000-4000-8000-000000000001', 'Signals', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('c4420000-0000-4000-8000-000000000001', 'c4400000-0000-4000-8000-000000000001',
   'c4410000-0000-4000-8000-000000000001', 1, 'active', 6, 2, '{}', 'Approved', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('c4430000-0000-4000-8000-000000000001', 'c4400000-0000-4000-8000-000000000001',
   'c4420000-0000-4000-8000-000000000001', 1, 'Upper', 'Press', 1, 50, 'Warm up', 'Cool down'),
  ('c4430000-0000-4000-8000-000000000002', 'c4400000-0000-4000-8000-000000000001',
   'c4420000-0000-4000-8000-000000000001', 2, 'Lower', 'Squat', 3, 50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds) values
  ('c4440000-0000-4000-8000-000000000001', 'c4400000-0000-4000-8000-000000000001',
   'c4430000-0000-4000-8000-000000000001', 1, 'Press', 5, 6, 8, 90),
  ('c4440000-0000-4000-8000-000000000002', 'c4400000-0000-4000-8000-000000000001',
   'c4430000-0000-4000-8000-000000000002', 1, 'Squat', 3, 6, 8, 120);

create temporary table flow(name text primary key, id uuid);
grant all on flow to authenticated;

-- One set of the draft: number, finished or not, and the rest taken before it (null leaves it out).
create function pg_temp.s(number integer, done boolean, rest integer default null)
returns jsonb language sql as $$
  select jsonb_build_object('number', number, 'repetitions', '8', 'load_kg', '60', 'rir', 2,
    'completed', done) || case when rest is null then '{}'::jsonb
    else jsonb_build_object('rest_before_seconds', rest) end;
$$;

-- A heart-rate summary for exercise 1, set `number`; extra keys override the defaults.
create function pg_temp.hr(number integer, extra jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object('exercise_order', 1, 'set_number', number, 'start_bpm', 112,
    'peak_bpm', 148, 'end_bpm', 141, 'drop_30s_bpm', 14, 'drop_60s_bpm', 27, 'coverage', 0.92,
    'sample_count', 41, 'source', 'watch_workout') || extra;
$$;

-- Starts a workout of the Upper day `days_ago` days back, logs `sets` and finishes it.
create function pg_temp.finished(days_ago integer, sets jsonb)
returns uuid language plpgsql as $$
declare session_id uuid;
begin
  session_id := public.start_workout('c4430000-0000-4000-8000-000000000001',
    current_date - days_ago, 'UTC', gen_random_uuid());
  perform public.sync_workout_draft(session_id, 1, jsonb_build_object('exercises',
    jsonb_build_array(jsonb_build_object('order', 1, 'status', 'performed', 'sets', sets))));
  perform public.complete_workout_v2(session_id, 1, 2400, 7, null);
  return session_id;
end $$;

-- Grants and shape -------------------------------------------------------------------------------

select ok(has_function_privilege('authenticated', 'public.get_my_watch_workout_status_v1(date)', 'execute'),
  'athletes read their own Watch workout status');
select ok(not has_function_privilege('anon', 'public.get_my_watch_workout_status_v1(date)', 'execute'),
  'signed-out callers cannot');
select ok(has_function_privilege('service_role', 'public.get_workout_load_inputs_v1(uuid, date)', 'execute'),
  'the service role reads any athlete''s load inputs for the engine');
select ok(not has_function_privilege('authenticated', 'public.get_workout_load_inputs_v1(uuid, date)', 'execute'),
  'athletes cannot read another athlete''s load inputs');
select ok(not has_function_privilege('anon', 'public.get_workout_load_inputs_v1(uuid, date)', 'execute'),
  'signed-out callers cannot either');
select ok(not has_function_privilege('authenticated', 'private.watch_workout_status(uuid, date)', 'execute'),
  'the status query is private');
select ok(not has_function_privilege('authenticated', 'private.workout_load_inputs(uuid, date)', 'execute'),
  'the load inputs query is private');
select ok((select prosecdef from pg_proc where oid = 'public.get_my_watch_workout_status_v1(date)'::regprocedure),
  'the status read is security definer and filters on auth.uid()');
select is((select proconfig from pg_proc where oid = 'public.get_my_watch_workout_status_v1(date)'::regprocedure),
  array['search_path=""'], 'with an empty search path');
select is((select proconfig from pg_proc where oid = 'public.get_workout_load_inputs_v1(uuid, date)'::regprocedure),
  array['search_path=""'], 'and so is the engine''s read');

-- A logs workouts ---------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c4400000-0000-4000-8000-000000000001';

-- Three days ago: five finished sets, all with readings, then the fifth set is undone and the
-- workout finished with four. The undone set keeps its stored readings.
insert into flow select 's1', public.start_workout('c4430000-0000-4000-8000-000000000001',
  current_date - 3, 'UTC', gen_random_uuid());
select public.sync_workout_draft((select id from flow where name = 's1'), 1,
  jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object('order', 1, 'status',
    'performed', 'sets', jsonb_build_array(pg_temp.s(1, true), pg_temp.s(2, true, 90),
      pg_temp.s(3, true, 90), pg_temp.s(4, true, 90), pg_temp.s(5, true, 90))))));
select public.persist_set_heart_rate_v1((select id from flow where name = 's1'),
  jsonb_build_array(pg_temp.hr(1), pg_temp.hr(2, '{"start_bpm":120}'), pg_temp.hr(3), pg_temp.hr(5)));
select public.sync_workout_draft((select id from flow where name = 's1'), 2,
  jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object('order', 1, 'status',
    'performed', 'sets', jsonb_build_array(pg_temp.s(5, false))))));
select public.complete_workout_v2((select id from flow where name = 's1'), 2, 2400, 7, null);
select is((select count(*) from public.exercise_set_heart_rate h
    join public.exercise_sets x on x.id = h.exercise_set_id and x.set_number = 5 and not x.completed),
  1::bigint, 'the undone set still has its stored readings');

-- Yesterday: two finished sets, one with sparse readings and one with too little coverage.
insert into flow select 's2', pg_temp.finished(1, jsonb_build_array(
  pg_temp.s(1, true), pg_temp.s(2, true, 45)));
select public.persist_set_heart_rate_v1((select id from flow where name = 's2'),
  jsonb_build_array(pg_temp.hr(1, '{"source":"background"}'), pg_temp.hr(2, '{"coverage":0.4}')));

-- Five days ago: one finished set, no heart rate.
insert into flow select 's3', pg_temp.finished(5, jsonb_build_array(pg_temp.s(1, true)));

-- Six days ago: three finished sets, the first tracked with exactly half the coverage.
insert into flow select 's7', pg_temp.finished(6, jsonb_build_array(
  pg_temp.s(1, true), pg_temp.s(2, true, 60), pg_temp.s(3, true, 60)));
select public.persist_set_heart_rate_v1((select id from flow where name = 's7'),
  jsonb_build_array(pg_temp.hr(1, '{"coverage":0.5}')));

-- Thirty days ago: out of the window.
insert into flow select 's8', pg_temp.finished(30, jsonb_build_array(pg_temp.s(1, true)));
select public.persist_set_heart_rate_v1((select id from flow where name = 's8'),
  jsonb_build_array(pg_temp.hr(1)));

-- Eighteen older workouts, so the cap on workouts shows.
select pg_temp.finished(d, jsonb_build_array(pg_temp.s(1, true))) from generate_series(8, 25) d;

-- Left out: a discarded workout, a workout still under way, and one marked complete from Apple Health.
insert into flow select 's5', public.start_workout('c4430000-0000-4000-8000-000000000001',
  current_date - 4, 'UTC', gen_random_uuid());
select public.abandon_workout((select id from flow where name = 's5'));
insert into flow select 's4', public.start_workout('c4430000-0000-4000-8000-000000000001',
  current_date - 2, 'UTC', gen_random_uuid());
select public.sync_workout_draft((select id from flow where name = 's4'), 1,
  jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object('order', 1, 'status',
    'performed', 'sets', jsonb_build_array(pg_temp.s(1, true))))));
insert into flow select 's9', public.start_workout('c4430000-0000-4000-8000-000000000002',
  current_date - 2, 'UTC', gen_random_uuid());
reset role;
update public.workout_sessions set state = 'completed', completed_at = now(),
  completion_source = 'healthkit' where id = (select id from flow where name = 's9');
set local role authenticated;
set local "request.jwt.claim.sub" = 'c4400000-0000-4000-8000-000000000001';

-- The app's status ---------------------------------------------------------------------------------

select is((select array_agg(k order by k) from jsonb_object_keys(public.get_my_watch_workout_status_v1()) k),
  array['as_of', 'recent_sessions', 'schema_version'], 'the status has its complete key list');
select is(public.get_my_watch_workout_status_v1()->>'schema_version', '1.0', 'and its schema version');
select is(public.get_my_watch_workout_status_v1()->>'as_of', current_date::text,
  'it defaults to today');
select is(jsonb_array_length(public.get_my_watch_workout_status_v1()->'recent_sessions'), 3,
  'it lists the last three finished workouts');
select is((select array_agg(r->>'local_date' order by ord)
    from jsonb_array_elements(public.get_my_watch_workout_status_v1()->'recent_sessions')
      with ordinality t(r, ord)),
  array[(current_date - 1)::text, (current_date - 3)::text, (current_date - 5)::text],
  'newest first, leaving out the discarded, the open and the Apple Health one');
select is((select array_agg(k order by k) from jsonb_object_keys(
    public.get_my_watch_workout_status_v1()->'recent_sessions'->0) k),
  array['completed_sets', 'local_date', 'watch_sets'], 'each has its complete key list');
select is(public.get_my_watch_workout_status_v1()->'recent_sessions'->0->>'completed_sets', '2',
  'yesterday''s workout finished two sets');
select is(public.get_my_watch_workout_status_v1()->'recent_sessions'->0->>'watch_sets', '0',
  'and no Watch workout tracked them: sparse readings and thin coverage do not count');
select is(public.get_my_watch_workout_status_v1()->'recent_sessions'->1->>'completed_sets', '4',
  'the workout before finished four sets');
select is(public.get_my_watch_workout_status_v1()->'recent_sessions'->1->>'watch_sets', '3',
  'three tracked; the undone fifth set''s readings do not count');
select is(public.get_my_watch_workout_status_v1()->'recent_sessions'->2->>'watch_sets', '0',
  'a workout with no readings has none');

select is((select array_agg(r->>'local_date' order by ord)
    from jsonb_array_elements(public.get_my_watch_workout_status_v1(current_date - 2)->'recent_sessions')
      with ordinality t(r, ord)),
  array[(current_date - 3)::text, (current_date - 5)::text, (current_date - 6)::text],
  'asked for two days ago, it counts from then and 28 days back');
select is(public.get_my_watch_workout_status_v1(current_date - 2)->'recent_sessions'->2->>'watch_sets', '1',
  'half the coverage is enough to count');
select throws_ok($$select public.get_my_watch_workout_status_v1(current_date + 3)$$, '22023', null,
  'a date more than two days ahead is refused');
select throws_ok($$select public.get_my_watch_workout_status_v1(current_date - 3)$$, '22023', null,
  'and one more than two days back');

-- Another athlete sees none of it --------------------------------------------------------------------

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = 'c4400000-0000-4000-8000-000000000002';
select is(public.get_my_watch_workout_status_v1(),
  jsonb_build_object('schema_version', '1.0', 'as_of', current_date, 'recent_sessions', '[]'::jsonb),
  'another athlete''s status is empty');
set local "request.jwt.claim.sub" = '';
select throws_ok($$select public.get_my_watch_workout_status_v1()$$, '42501', null,
  'a caller with no identity cannot read');

-- The engine's inputs (service role) -------------------------------------------------------------------

reset role;
set local role service_role;

select is((select array_agg(k order by k) from jsonb_object_keys(
    public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)) k),
  array['as_of', 'schema_version', 'sessions'], 'the inputs have their complete key list');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->>'schema_version',
  '1.0', 'and their schema version');
select is(jsonb_array_length(public.get_workout_load_inputs_v1(
    'c4400000-0000-4000-8000-000000000001', current_date)->'sessions'), 12,
  'at most the newest 12 finished workouts of the last 28 days');
select is((select array_agg(r->>'local_date' order by ord) from jsonb_array_elements(
      public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions')
      with ordinality t(r, ord) where ord <= 5),
  array[(current_date - 1)::text, (current_date - 3)::text, (current_date - 5)::text,
    (current_date - 6)::text, (current_date - 8)::text],
  'newest first, without the discarded, the open or the Apple Health workout');
select is((select r->>'local_date' from jsonb_array_elements(
      public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions')
      with ordinality t(r, ord) where ord = 12),
  (current_date - 15)::text, 'and stopping at the twelfth');
select is((select array_agg(k order by k) from jsonb_object_keys(
    public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->0) k),
  array['completed_sets', 'local_date', 'sets'], 'each workout has its complete key list');
select is((select array_agg(k order by k) from jsonb_object_keys(
    public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->1->'sets'->0) k),
  array['coverage', 'drop_30s_bpm', 'drop_60s_bpm', 'end_bpm', 'exercise_order', 'peak_bpm',
    'rest_before_seconds', 'sample_count', 'set_number', 'source', 'start_bpm'],
  'each set has its complete key list');
select ok(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)::text
    !~ '(load_kg|repetitions|"rir"|"rpe")',
  'no load, repetitions or reps in reserve are returned');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->0->>'completed_sets',
  '2', 'yesterday''s workout finished two sets');
select is(jsonb_array_length(public.get_workout_load_inputs_v1(
    'c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->0->'sets'), 2,
  'and both have a summary, whatever their source or coverage');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->1->>'completed_sets',
  '4', 'the workout before finished four sets');
select is(jsonb_array_length(public.get_workout_load_inputs_v1(
    'c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->1->'sets'), 3,
  'three have a summary: the undone fifth set is left out');
select is((select array_agg(s->>'set_number' order by ord) from jsonb_array_elements(
      public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->1->'sets')
      with ordinality t(s, ord)),
  array['1', '2', '3'], 'in set order');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->1->'sets'->0->'rest_before_seconds',
  'null'::jsonb, 'the first set has no rest, said as null');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->1->'sets'->1->>'rest_before_seconds',
  '90', 'the second set''s rest is the one taken');
select is((public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->1->'sets'->1)
    - 'rest_before_seconds',
  jsonb_build_object('exercise_order', 1, 'set_number', 2, 'start_bpm', 120, 'peak_bpm', 148,
    'end_bpm', 141, 'drop_30s_bpm', 14, 'drop_60s_bpm', 27, 'coverage', 0.92, 'sample_count', 41,
    'source', 'watch_workout'),
  'with its heart-rate summary as saved');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->2->'sets',
  '[]'::jsonb, 'a workout with no readings lists no sets');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions'->2->>'completed_sets',
  '1', 'but still says how many sets it finished');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date - 2)->'sessions'->0->>'local_date',
  (current_date - 3)::text, 'asked for two days ago, it starts from then');
select is((select count(*) from jsonb_array_elements(
      public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions') r
    where r->>'local_date' = (current_date - 30)::text), 0::bigint,
  'a workout from 30 days ago is outside the window');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000002', current_date),
  jsonb_build_object('schema_version', '1.0', 'as_of', current_date, 'sessions', '[]'::jsonb),
  'another athlete''s inputs are empty');
select throws_ok($$select public.get_workout_load_inputs_v1(null, current_date)$$, '22023', null,
  'it needs an athlete');
select throws_ok($$select public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', null)$$,
  '22023', null, 'and a date');

select is((select count(*) from jsonb_array_elements(
      public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date)->'sessions') r
    where (r->>'completed_sets')::integer = 0), 0::bigint,
  'no listed workout is empty');
select is(public.get_workout_load_inputs_v1('c4400000-0000-4000-8000-000000000001', current_date - 2)
    ->'sessions'->2->'sets'->0->>'coverage', '0.500',
  'a set with exactly half the coverage is listed with it');

select * from finish();
rollback;
