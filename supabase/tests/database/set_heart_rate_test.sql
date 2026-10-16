begin;
select plan(52);

-- A logs a workout with two completed sets; B is another athlete.
insert into auth.users(id, role) values
  ('c2300000-0000-4000-8000-000000000001', 'authenticated'),
  ('c2300000-0000-4000-8000-000000000002', 'authenticated');

insert into public.training_plans(id, user_id, title, source) values
  ('c2310000-0000-4000-8000-000000000001', 'c2300000-0000-4000-8000-000000000001', 'Heart', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('c2320000-0000-4000-8000-000000000001', 'c2300000-0000-4000-8000-000000000001',
   'c2310000-0000-4000-8000-000000000001', 1, 'active', 6, 2, '{}', 'Approved', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('c2330000-0000-4000-8000-000000000001', 'c2300000-0000-4000-8000-000000000001',
   'c2320000-0000-4000-8000-000000000001', 1, 'Upper', 'Press', 1, 50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds) values
  ('c2340000-0000-4000-8000-000000000001', 'c2300000-0000-4000-8000-000000000001',
   'c2330000-0000-4000-8000-000000000001', 1, 'Heart press', 3, 6, 8, 90);

create temporary table flow(name text primary key, id uuid);
create temporary table h(j jsonb);
grant all on flow, h to authenticated;

-- One summary object for exercise 1, set `number`; extra keys override the defaults.
create function pg_temp.summary(number integer, extra jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object('exercise_order', 1, 'set_number', number, 'start_bpm', 110,
    'peak_bpm', 148, 'end_bpm', 140, 'drop_30s_bpm', 12, 'drop_60s_bpm', 25, 'coverage', 0.92,
    'sample_count', 41, 'source', 'watch_workout') || extra;
$$;

create function pg_temp.save(summaries jsonb)
returns jsonb language sql as $$
  select public.persist_set_heart_rate_v1((select id from flow where name = 'a'), summaries);
$$;

-- Shape ----------------------------------------------------------------------------------------

select has_table('public', 'exercise_set_heart_rate', 'the summary table exists');
select is((select array_agg(column_name::text order by column_name) from information_schema.columns
    where table_schema = 'public' and table_name = 'exercise_set_heart_rate'),
  array['coverage', 'created_at', 'drop_30s_bpm', 'drop_60s_bpm', 'end_bpm', 'exercise_set_id',
    'peak_bpm', 'sample_count', 'source', 'start_bpm', 'updated_at', 'user_id'],
  'the table holds summaries only: no raw samples');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.exercise_set_heart_rate'::regclass), 'row-level security is on and forced');
select ok(not has_table_privilege('authenticated', 'public.exercise_set_heart_rate', 'insert'),
  'clients cannot insert summaries directly');
select ok(not has_table_privilege('authenticated', 'public.exercise_set_heart_rate', 'update'),
  'clients cannot update summaries directly');
select ok(not has_table_privilege('authenticated', 'public.exercise_set_heart_rate', 'delete'),
  'clients cannot delete summaries directly');
select ok(has_table_privilege('authenticated', 'public.exercise_set_heart_rate', 'select'),
  'clients read their own summaries');
select ok(not has_table_privilege('anon', 'public.exercise_set_heart_rate', 'select'),
  'signed-out callers read nothing');

-- Grants ---------------------------------------------------------------------------------------

select ok(has_function_privilege('authenticated',
  'public.persist_set_heart_rate_v1(uuid, jsonb)', 'execute'), 'athletes save summaries');
select ok(not has_function_privilege('anon',
  'public.persist_set_heart_rate_v1(uuid, jsonb)', 'execute'), 'signed-out callers cannot save');
select ok(has_function_privilege('authenticated',
  'public.get_my_set_heart_rate_v1(uuid)', 'execute'), 'athletes read summaries');
select ok(not has_function_privilege('anon',
  'public.get_my_set_heart_rate_v1(uuid)', 'execute'), 'signed-out callers cannot read');
select ok(not has_function_privilege('authenticated',
  'private.set_heart_rate_value(jsonb, numeric, numeric, text, boolean, boolean)', 'execute'),
  'the value check is private');
select ok((select prosecdef from pg_proc where oid = 'public.persist_set_heart_rate_v1(uuid, jsonb)'::regprocedure),
  'saving is security definer');
select is((select proconfig from pg_proc where oid = 'public.persist_set_heart_rate_v1(uuid, jsonb)'::regprocedure),
  array['search_path=""'], 'with an empty search path');

-- A logs two completed sets and one open set -----------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c2300000-0000-4000-8000-000000000001';

insert into flow select 'a', public.start_workout('c2330000-0000-4000-8000-000000000001',
  current_date, 'UTC', 'c2350000-0000-4000-8000-000000000001');
select public.sync_workout_draft((select id from flow where name = 'a'), 1,
  jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object(
    'order', 1, 'status', 'performed', 'sets', jsonb_build_array(
      jsonb_build_object('number', 1, 'repetitions', '8', 'load_kg', '60', 'completed', true),
      jsonb_build_object('number', 2, 'repetitions', '8', 'load_kg', '60', 'completed', true),
      jsonb_build_object('number', 3, 'completed', false))))));

-- Saving ---------------------------------------------------------------------------------------

select is(pg_temp.save(jsonb_build_array(pg_temp.summary(1), pg_temp.summary(2)))
    - 'session_id', '{"schema_version":"1.0","saved":2}'::jsonb, 'two sets are saved');
select is((select count(*) from public.exercise_set_heart_rate), 2::bigint, 'one row per set');
select is((select array[start_bpm, peak_bpm, end_bpm, drop_30s_bpm, drop_60s_bpm, sample_count]::integer[]
    from public.exercise_set_heart_rate h
    join public.exercise_sets s on s.id = h.exercise_set_id where s.set_number = 1),
  array[110, 148, 140, 12, 25, 41], 'with every value');
select is((select array[coverage::text, source] from public.exercise_set_heart_rate h
    join public.exercise_sets s on s.id = h.exercise_set_id where s.set_number = 1),
  array['0.920', 'watch_workout'], 'and the coverage and source');

select is(pg_temp.save(jsonb_build_array(pg_temp.summary(1,
    '{"peak_bpm":150,"coverage":1,"sample_count":55,"source":"background"}')))->>'saved', '1',
  'saving a set again is accepted');
select is((select count(*) from public.exercise_set_heart_rate), 2::bigint, 'and replaces its row');
select is((select array[peak_bpm::text, coverage::text, sample_count::text, source]
    from public.exercise_set_heart_rate h
    join public.exercise_sets s on s.id = h.exercise_set_id where s.set_number = 1),
  array['150', '1.000', '55', 'background'], 'with the newer values');

select lives_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(2,
    '{"start_bpm":null,"end_bpm":null,"drop_30s_bpm":null,"drop_60s_bpm":null}')))$$,
  'a set with only a peak is saved');
select is((select array[start_bpm, end_bpm, drop_30s_bpm, drop_60s_bpm]::text[]
    from public.exercise_set_heart_rate h
    join public.exercise_sets s on s.id = h.exercise_set_id where s.set_number = 2),
  array[null, null, null, null]::text[], 'and the missing values stay empty');
select lives_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(2,
    '{"drop_30s_bpm":-4}')))$$, 'a heart rate that rose is saved as a negative drop');

-- Invalid values -------------------------------------------------------------------------------

select throws_ok($$select pg_temp.save('{"a":1}')$$, '22023', null, 'summaries must be a list');
select throws_ok($$select pg_temp.save('[]')$$, '22023', null, 'and not empty');
select throws_ok($$select pg_temp.save('[1]')$$, '22023', null, 'each summary is an object');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"peak_bpm":300}')))$$,
  '22023', null, 'a heart rate above 250 is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"start_bpm":20}')))$$,
  '22023', null, 'and one below 30');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"start_bpm":110.5}')))$$,
  '22023', null, 'and a fraction of a beat');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"start_bpm":"110"}')))$$,
  '22023', null, 'and a string');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"coverage":1.5}')))$$,
  '22023', null, 'coverage above 1 is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"coverage":null}')))$$,
  '22023', null, 'and a missing coverage');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"sample_count":0}')))$$,
  '22023', null, 'a set with no samples is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"source":"phone"}')))$$,
  '22023', null, 'an unknown source is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"peak_bpm":100}')))$$,
  '22023', null, 'a peak below the start or the end is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"drop_60s_bpm":500}')))$$,
  '22023', null, 'a drop beyond 220 is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(9)))$$, '22023', null,
  'a set that does not exist is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(3)))$$, '22023', null,
  'and so is a set that was not finished');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1, '{"exercise_order":7}')))$$,
  '22023', null, 'and an exercise that does not exist');
select throws_ok($$select public.persist_set_heart_rate_v1('c2360000-0000-4000-8000-000000000001',
    jsonb_build_array(pg_temp.summary(1)))$$, 'P0002', null, 'an unknown workout is refused');
select is((select peak_bpm from public.exercise_set_heart_rate h
    join public.exercise_sets s on s.id = h.exercise_set_id where s.set_number = 1),
  150::smallint, 'a refused batch changes nothing');

-- Reading --------------------------------------------------------------------------------------

insert into h select public.get_my_set_heart_rate_v1((select id from flow where name = 'a'));
select is((select array_agg(k order by k) from h, jsonb_object_keys(j) k),
  array['schema_version', 'session_id', 'sets'], 'the read has the complete top-level key list');
select is((select array_agg(k order by k) from h, jsonb_object_keys(j->'sets'->0) k),
  array['coverage', 'drop_30s_bpm', 'drop_60s_bpm', 'end_bpm', 'exercise_order', 'peak_bpm',
    'sample_count', 'set_number', 'source', 'start_bpm'], 'and the complete key list for a set');
select is((select j->>'schema_version' from h), '1.0', 'schema 1.0');
select is((select array_agg((e->>'set_number')::integer order by (e->>'set_number')::integer)
    from h, jsonb_array_elements(j->'sets') e), array[1, 2], 'sets come back by number');

-- Another athlete ------------------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'c2300000-0000-4000-8000-000000000002';
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1)))$$, 'P0002', null,
  'another athlete cannot save to this workout');
select is((select count(*) from public.exercise_set_heart_rate), 0::bigint,
  'another athlete sees none of the rows');
select is(public.get_my_set_heart_rate_v1((select id from flow where name = 'a'))->'sets',
  '[]'::jsonb, 'and the read returns nothing for this workout');

set local "request.jwt.claim.sub" = '';
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.summary(1)))$$, '42501', null,
  'a caller with no identity cannot save');

-- Deleting the account removes the summaries ------------------------------------------------------

reset role;
delete from auth.users where id = 'c2300000-0000-4000-8000-000000000001';
select is((select count(*) from public.exercise_set_heart_rate), 0::bigint,
  'deleting the account deletes the summaries');

select * from finish();
rollback;
