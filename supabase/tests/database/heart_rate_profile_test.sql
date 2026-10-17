-- Heart-rate profile (chunk C3, migration 20261017110233_heart_rate_profile.sql).
--
-- Under test: sleeping_heart_rate_nights (RLS, grants, no raw samples), persist_sleeping_heart_rate_v1
-- (validation, upsert, isolation), get_my_heart_rate_inputs_v1 and get_heart_rate_inputs_v1 (complete
-- key lists, what is included and left out, the service-role-only grant) and account deletion.
begin;
select plan(72);

insert into auth.users(id, role) values
  ('c3300000-0000-4000-8000-000000000001', 'authenticated'),
  ('c3300000-0000-4000-8000-000000000002', 'authenticated');

insert into public.user_profiles(user_id, birth_year)
values ('c3300000-0000-4000-8000-000000000001', 1990);

-- A: resting heart rate on three recent days, one reading outside 30 to 120, one 20 days ago.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum, completeness,
  observed_through, last_synced_at, resting_heart_rate_bpm)
select 'c3300000-0000-4000-8000-000000000001', current_date - d, 'UTC',
  array['resting_heart_rate'], '[]'::jsonb, md5(d::text) || md5(d::text), 'partial', now(), now(), rhr
from (values (1, 58.0), (2, 60.0), (3, 150.0), (20, 52.0)) s(d, rhr);

insert into public.training_plans(id, user_id, title, source) values
  ('c3310000-0000-4000-8000-000000000001', 'c3300000-0000-4000-8000-000000000001', 'Heart', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('c3320000-0000-4000-8000-000000000001', 'c3300000-0000-4000-8000-000000000001',
   'c3310000-0000-4000-8000-000000000001', 1, 'active', 6, 2, '{}', 'Approved', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('c3330000-0000-4000-8000-000000000001', 'c3300000-0000-4000-8000-000000000001',
   'c3320000-0000-4000-8000-000000000001', 1, 'Upper', 'Press', 1, 50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds) values
  ('c3340000-0000-4000-8000-000000000001', 'c3300000-0000-4000-8000-000000000001',
   'c3330000-0000-4000-8000-000000000001', 1, 'Heart press', 3, 6, 8, 90);

create temporary table flow(name text primary key, id uuid);
create temporary table h(j jsonb);
grant all on flow, h to authenticated;

create function pg_temp.night(day_offset integer, extra jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object('local_date', (current_date - day_offset)::text, 'median_bpm', 52,
    'lowest_bpm', 46, 'sample_count', 84, 'asleep_minutes', 430, 'coverage', 0.81) || extra;
$$;
create function pg_temp.save(nights jsonb) returns jsonb language sql as $$
  select public.persist_sleeping_heart_rate_v1(nights);
$$;
create function pg_temp.summary(number integer, peak integer, extra jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object('exercise_order', 1, 'set_number', number, 'start_bpm', 110,
    'peak_bpm', peak, 'end_bpm', 108, 'drop_30s_bpm', 12, 'drop_60s_bpm', 25, 'coverage', 0.92,
    'sample_count', 41, 'source', 'watch_workout') || extra;
$$;

-- Shape ----------------------------------------------------------------------------------------

select has_table('public', 'sleeping_heart_rate_nights', 'the shadow table exists');
select is((select array_agg(column_name::text order by column_name) from information_schema.columns
    where table_schema = 'public' and table_name = 'sleeping_heart_rate_nights'),
  array['asleep_minutes', 'coverage', 'created_at', 'local_date', 'lowest_bpm', 'median_bpm',
    'sample_count', 'updated_at', 'user_id'],
  'the table holds one derived row per night: no raw samples');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.sleeping_heart_rate_nights'::regclass), 'row-level security is on and forced');
select ok(not has_table_privilege('authenticated', 'public.sleeping_heart_rate_nights', 'insert'),
  'clients cannot insert nights directly');
select ok(not has_table_privilege('authenticated', 'public.sleeping_heart_rate_nights', 'update'),
  'clients cannot update nights directly');
select ok(not has_table_privilege('authenticated', 'public.sleeping_heart_rate_nights', 'delete'),
  'clients cannot delete nights directly');
select ok(has_table_privilege('authenticated', 'public.sleeping_heart_rate_nights', 'select'),
  'clients read their own nights');
select ok(not has_table_privilege('anon', 'public.sleeping_heart_rate_nights', 'select'),
  'signed-out callers read nothing');
select ok(obj_description('public.sleeping_heart_rate_nights'::regclass, 'pg_class') like 'SHADOW MODE (D10)%',
  'the table says it is in shadow mode');

-- Grants ---------------------------------------------------------------------------------------

select ok(has_function_privilege('authenticated', 'public.persist_sleeping_heart_rate_v1(jsonb)', 'execute'),
  'athletes save nights');
select ok(not has_function_privilege('anon', 'public.persist_sleeping_heart_rate_v1(jsonb)', 'execute'),
  'signed-out callers cannot save');
select ok(has_function_privilege('authenticated', 'public.get_my_heart_rate_inputs_v1(date)', 'execute'),
  'athletes read their own inputs');
select ok(not has_function_privilege('anon', 'public.get_my_heart_rate_inputs_v1(date)', 'execute'),
  'signed-out callers cannot read inputs');
select ok(has_function_privilege('service_role', 'public.get_heart_rate_inputs_v1(uuid, date)', 'execute'),
  'the service role reads any athlete''s inputs for the Coach');
select ok(not has_function_privilege('authenticated', 'public.get_heart_rate_inputs_v1(uuid, date)', 'execute'),
  'athletes cannot read another athlete''s inputs');
select ok(not has_function_privilege('anon', 'public.get_heart_rate_inputs_v1(uuid, date)', 'execute'),
  'signed-out callers cannot either');
select ok(not has_function_privilege('authenticated', 'private.heart_rate_inputs(uuid, date)', 'execute'),
  'the inputs query is private');
select is((select proconfig from pg_proc where oid = 'public.persist_sleeping_heart_rate_v1(jsonb)'::regprocedure),
  array['search_path=""'], 'saving has an empty search path');
select ok((select prosecdef from pg_proc where oid = 'public.get_my_heart_rate_inputs_v1(date)'::regprocedure),
  'the inputs read is security definer and filters on auth.uid()');

-- A logs one workout with three finished sets and saves their summaries ---------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c3300000-0000-4000-8000-000000000001';

insert into flow select 'a', public.start_workout('c3330000-0000-4000-8000-000000000001',
  current_date, 'UTC', 'c3350000-0000-4000-8000-000000000001');
select public.sync_workout_draft((select id from flow where name = 'a'), 1,
  jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object(
    'order', 1, 'status', 'performed', 'sets', jsonb_build_array(
      jsonb_build_object('number', 1, 'repetitions', '8', 'load_kg', '60', 'completed', true),
      jsonb_build_object('number', 2, 'repetitions', '8', 'load_kg', '60', 'completed', true),
      jsonb_build_object('number', 3, 'repetitions', '8', 'load_kg', '60', 'completed', true))))));
select public.persist_set_heart_rate_v1((select id from flow where name = 'a'),
  jsonb_build_array(pg_temp.summary(1, 150), pg_temp.summary(2, 160), pg_temp.summary(3, 140)));

-- Sleeping heart rate: saving --------------------------------------------------------------------

select is(pg_temp.save(jsonb_build_array(pg_temp.night(1), pg_temp.night(2))),
  '{"schema_version":"1.0","saved":2}'::jsonb, 'two nights are saved');
select is((select count(*) from public.sleeping_heart_rate_nights), 2::bigint, 'one row per night');
select is((select array[median_bpm, lowest_bpm, sample_count, asleep_minutes]::integer[]
    from public.sleeping_heart_rate_nights where local_date = current_date - 1),
  array[52, 46, 84, 430], 'with every value');
select is((select coverage::text from public.sleeping_heart_rate_nights where local_date = current_date - 1),
  '0.810', 'and the coverage');
select is(pg_temp.save(jsonb_build_array(pg_temp.night(1,
    '{"median_bpm":55,"lowest_bpm":50,"sample_count":90,"coverage":0.9}')))->>'saved', '1',
  'a night read again is accepted');
select is((select count(*) from public.sleeping_heart_rate_nights), 2::bigint, 'and replaces its row');
select is((select array[median_bpm, lowest_bpm, sample_count]::integer[]
    from public.sleeping_heart_rate_nights where local_date = current_date - 1),
  array[55, 50, 90], 'with the newer values');

select throws_ok($$select pg_temp.save('{"a":1}')$$, '22023', null, 'nights must be a list');
select throws_ok($$select pg_temp.save('[]')$$, '22023', null, 'and not empty');
select throws_ok($$select pg_temp.save((select jsonb_agg(pg_temp.night(n)) from generate_series(1, 15) n))$$,
  '22023', null, 'and at most 14 nights');
select throws_ok($$select pg_temp.save('[1]')$$, '22023', null, 'each night is an object');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1, '{"local_date":"yesterday"}')))$$,
  '22023', null, 'a date must be a date');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1, '{"local_date":"2026-13-45"}')))$$,
  '22023', null, 'a real one');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(-5)))$$,
  '22023', null, 'a night in the future is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(500)))$$,
  '22023', null, 'and one from over a year ago');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1, '{"median_bpm":20}')))$$,
  '22023', null, 'a median below 30 is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1, '{"median_bpm":52.5}')))$$,
  '22023', null, 'and a fraction of a beat');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1, '{"lowest_bpm":60}')))$$,
  '22023', null, 'a lowest above the median is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1, '{"coverage":1.5}')))$$,
  '22023', null, 'coverage above 1 is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1, '{"sample_count":0}')))$$,
  '22023', null, 'a night with no readings is refused');
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1, '{"asleep_minutes":null}')))$$,
  '22023', null, 'and one with no sleep length');
select is((select median_bpm from public.sleeping_heart_rate_nights where local_date = current_date - 2),
  52::smallint, 'a refused batch changes nothing');

-- Inputs: the athlete's own -----------------------------------------------------------------------

insert into h select public.get_my_heart_rate_inputs_v1();
select is((select array_agg(k order by k) from h, jsonb_object_keys(j) k),
  array['as_of', 'birth_year', 'peak_candidates', 'resting', 'schema_version', 'sets'],
  'the inputs have the complete top-level key list (and no sleeping heart rate)');
select is((select j->>'schema_version' from h), '1.0', 'schema 1.0');
select is((select j->>'as_of' from h), current_date::text, 'as of today by default');
select is((select (j->>'birth_year')::integer from h), 1990, 'with the birth year');
select is((select array_agg(k order by k) from h, jsonb_object_keys(j->'sets'->0) k),
  array['coverage', 'drop_30s_bpm', 'drop_60s_bpm', 'end_bpm', 'local_date', 'peak_bpm',
    'sample_count', 'source', 'start_bpm'], 'a set row has the complete key list');
select is((select array_agg(k order by k) from h, jsonb_object_keys(j->'peak_candidates'->0) k),
  array['coverage', 'drop_30s_bpm', 'drop_60s_bpm', 'end_bpm', 'local_date', 'peak_bpm',
    'sample_count', 'source', 'start_bpm'], 'and so does a peak candidate');
select is((select array_agg(k order by k) from h, jsonb_object_keys(j->'resting'->0) k),
  array['bpm', 'local_date'], 'a resting row has the complete key list');
select is((select jsonb_array_length(j->'resting') from h), 2,
  'resting holds the last 14 days only, between 30 and 120');
select is((select array_agg((e->>'bpm')::numeric order by e->>'local_date') from h, jsonb_array_elements(j->'resting') e),
  array[60.0, 58.0], 'oldest first');
select is((select jsonb_array_length(j->'sets') from h), 3, 'three sets');
select is((select jsonb_array_length(j->'peak_candidates') from h), 3, 'and three peak candidates');
select is((select array_agg((e->>'peak_bpm')::integer order by ord) from h,
    jsonb_array_elements(j->'peak_candidates') with ordinality t(e, ord)),
  array[160, 150, 140], 'the highest peak comes first');
select is((select j->'sets'->0->>'local_date' from h), current_date::text, 'sets carry the workout''s local date');
select is((select j->'sets'->0->>'source' from h), 'watch_workout', 'and their source');
select throws_ok($$select public.get_my_heart_rate_inputs_v1(current_date + 5)$$, '22023', null,
  'a date far from today is refused');

-- A discarded workout drops out of the inputs ----------------------------------------------------

select public.abandon_workout((select id from flow where name = 'a'));
select is(public.get_my_heart_rate_inputs_v1()->'sets', '[]'::jsonb, 'a discarded workout adds no sets');
select is(public.get_my_heart_rate_inputs_v1()->'peak_candidates', '[]'::jsonb, 'and no peaks');

-- Trust is applied before the limit on peak candidates --------------------------------------------
-- A has no trusted peak but ten untrusted higher ones (5 with few readings, 5 poorly covered), one
-- trusted peak above the age ceiling (born 1990: 183 + 20 = 203) and one valid lower one.

insert into flow select 'b', public.start_workout('c3330000-0000-4000-8000-000000000001',
  current_date, 'UTC', 'c3350000-0000-4000-8000-000000000002');
select public.sync_workout_draft((select id from flow where name = 'b'), 1,
  jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object(
    'order', 1, 'status', 'performed', 'sets', (
      select jsonb_agg(jsonb_build_object('number', n, 'repetitions', '8', 'load_kg', '60', 'completed', true)
        order by n) from generate_series(1, 12) n)))));
select public.persist_set_heart_rate_v1((select id from flow where name = 'b'), (
  select jsonb_agg(case
      when n <= 5 then pg_temp.summary(n, 200 + n, '{"sample_count":5}')
      when n <= 10 then pg_temp.summary(n, 200 + n, '{"coverage":0.4}')
      when n = 11 then pg_temp.summary(n, 210)
      else pg_temp.summary(n, 190) end order by n)
  from generate_series(1, 12) n));

select is((select jsonb_array_length(public.get_my_heart_rate_inputs_v1()->'peak_candidates')), 1,
  'only the trusted peak within the age ceiling is a candidate');
select is((select (public.get_my_heart_rate_inputs_v1()->'peak_candidates'->0->>'peak_bpm')::integer), 190,
  'a valid lower peak is not crowded out by ten untrusted higher ones');
select is((select jsonb_array_length(public.get_my_heart_rate_inputs_v1()->'sets')), 12,
  'while the recovery sets are not filtered by trust');

-- Another athlete --------------------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'c3300000-0000-4000-8000-000000000002';
select is((select count(*) from public.sleeping_heart_rate_nights), 0::bigint, 'another athlete sees none of the nights');
select is(public.get_my_heart_rate_inputs_v1(),
  jsonb_build_object('schema_version', '1.0', 'as_of', current_date, 'birth_year', null,
    'resting', '[]'::jsonb, 'sets', '[]'::jsonb, 'peak_candidates', '[]'::jsonb),
  'and their own inputs are empty, with a null birth year');
select is(pg_temp.save(jsonb_build_array(pg_temp.night(1)))->>'saved', '1', 'they save a night of their own');
select is((select count(*) from public.sleeping_heart_rate_nights), 1::bigint, 'and see only that one');

set local "request.jwt.claim.sub" = '';
select throws_ok($$select pg_temp.save(jsonb_build_array(pg_temp.night(1)))$$, '42501', null,
  'a caller with no identity cannot save');
select throws_ok($$select public.get_my_heart_rate_inputs_v1()$$, '42501', null,
  'or read');

-- The Coach's read (service role) ----------------------------------------------------------------

reset role;
set local role service_role;
select is((select array_agg(k order by k) from jsonb_object_keys(
    public.get_heart_rate_inputs_v1('c3300000-0000-4000-8000-000000000001', current_date)) k),
  array['as_of', 'birth_year', 'peak_candidates', 'resting', 'schema_version', 'sets'],
  'the Coach''s read has the same complete key list');
select is(public.get_heart_rate_inputs_v1('c3300000-0000-4000-8000-000000000001', current_date)->'birth_year',
  '1990'::jsonb, 'for the athlete asked about');
select throws_ok($$select public.get_heart_rate_inputs_v1(null, current_date)$$, '22023', null,
  'it needs an athlete');

-- Deleting the account removes the nights --------------------------------------------------------

reset role;
delete from auth.users where id = 'c3300000-0000-4000-8000-000000000002';
select is((select count(*) from public.sleeping_heart_rate_nights
    where user_id = 'c3300000-0000-4000-8000-000000000002'), 0::bigint,
  'deleting the account deletes the nights');
select is((select count(*) from public.sleeping_heart_rate_nights), 2::bigint,
  'and leaves the other athlete''s nights');

select * from finish();
rollback;
