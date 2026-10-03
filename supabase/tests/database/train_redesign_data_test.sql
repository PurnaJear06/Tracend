begin;
select plan(65);

-- A: history, hub and the completion flows. B: another athlete (ownership and
-- Apple Health completion). C: day-level load.
insert into auth.users(id, role) values
  ('a7000000-0000-4000-8000-000000000001', 'authenticated'),
  ('a7000000-0000-4000-8000-000000000002', 'authenticated'),
  ('a7000000-0000-4000-8000-000000000003', 'authenticated');
update public.user_accounts set timezone = 'Asia/Kolkata'
  where id = 'a7000000-0000-4000-8000-000000000001';

-- Source 'imported' keeps the seed trigger from adding its own workouts.
insert into public.training_plans(id, user_id, title, source) values
  ('a7100000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000001', 'Strength', 'imported'),
  ('a7100000-0000-4000-8000-000000000002', 'a7000000-0000-4000-8000-000000000002', 'Other', 'imported'),
  ('a7100000-0000-4000-8000-000000000003', 'a7000000-0000-4000-8000-000000000003', 'Load', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('a7200000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000001',
   'a7100000-0000-4000-8000-000000000001', 1, 'active', 6, 2,
   '{"progression":"Add 2.5 kg once every set reaches the top of its range."}',
   'Approved', '2026-09-15 20:00:00+00', null),
  ('a7200000-0000-4000-8000-000000000002', 'a7000000-0000-4000-8000-000000000002',
   'a7100000-0000-4000-8000-000000000002', 1, 'active', 6, 7, '{}', 'Approved', now(), current_date),
  ('a7200000-0000-4000-8000-000000000003', 'a7000000-0000-4000-8000-000000000003',
   'a7100000-0000-4000-8000-000000000003', 1, 'active', 6, 1, '{}', 'Approved', now(), current_date);

insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('a7300000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000001',
   'a7200000-0000-4000-8000-000000000001', 1, 'Upper A', 'Press', 1, 50, 'Warm up', 'Cool down'),
  ('a7300000-0000-4000-8000-000000000002', 'a7000000-0000-4000-8000-000000000001',
   'a7200000-0000-4000-8000-000000000001', 2, 'Upper B', 'Press', 4, 50, 'Warm up', 'Cool down'),
  ('a7300000-0000-4000-8000-000000000003', 'a7000000-0000-4000-8000-000000000003',
   'a7200000-0000-4000-8000-000000000003', 1, 'Any', 'Train', 1, 50, 'Warm up', 'Cool down');
insert into public.planned_workouts(user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
select 'a7000000-0000-4000-8000-000000000002', 'a7200000-0000-4000-8000-000000000002', day,
  'Day ' || day, 'Train', day, 45, 'Warm up', 'Cool down'
from generate_series(1, 7) day;

insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug) values
  ('a7400000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000001',
   'a7300000-0000-4000-8000-000000000001', 1, 'Barbell bench press', 3, 5, 8, 120, 'barbell-bench-press'),
  ('a7400000-0000-4000-8000-000000000002', 'a7000000-0000-4000-8000-000000000001',
   'a7300000-0000-4000-8000-000000000001', 2, 'Cable fly', 2, 10, 12, 60, null),
  ('a7400000-0000-4000-8000-000000000003', 'a7000000-0000-4000-8000-000000000001',
   'a7300000-0000-4000-8000-000000000001', 3, 'Push-up', 2, 10, 20, 60, 'push-up'),
  ('a7400000-0000-4000-8000-000000000005', 'a7000000-0000-4000-8000-000000000001',
   'a7300000-0000-4000-8000-000000000001', 4, 'Assisted pull-up', 2, 6, 10, 90, 'assisted-pull-up'),
  ('a7400000-0000-4000-8000-000000000004', 'a7000000-0000-4000-8000-000000000001',
   'a7300000-0000-4000-8000-000000000002', 1, 'Barbell bench press', 1, 5, 8, 120, 'barbell-bench-press');

create temporary table t as
  select private.local_date_for('a7000000-0000-4000-8000-000000000001') a_today,
         private.local_date_for('a7000000-0000-4000-8000-000000000003') c_today;
grant select on t to authenticated;
-- Results are captured here; the athlete role cannot create tables.
create temporary table h(j jsonb);
create temporary table hub(j jsonb);
create temporary table flow(name text primary key, id uuid);
grant all on h, hub, flow to authenticated;

-- A logged session: sets are [reps, load_kg, completed (default true)].
create function pg_temp.log_session(p_user uuid, p_workout uuid, p_date date,
  p_state public.workout_session_state, p_effort numeric, p_effort_source text,
  p_minutes integer, p_exercises jsonb)
returns uuid language plpgsql as $$
declare sid uuid; ex jsonb; pid uuid; st jsonb; n integer;
begin
  insert into public.workout_sessions(user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  select p_user, w.plan_version_id, p_workout, p_date, 'UTC', p_state, gen_random_uuid(),
    case when p_state = 'completed' then now() - (current_date - p_date) * interval '1 day' end,
    p_minutes * 60, p_effort,
    case when p_state = 'completed' then p_effort_source end,
    case when p_state = 'completed' then 'manual' end
  from public.planned_workouts w where w.id = p_workout
  returning id into sid;
  for ex in select value from jsonb_array_elements(p_exercises) loop
    insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
      exercise_order, status, performance_kind, performed_name)
    values (p_user, sid, nullif(ex->>'planned', '')::uuid, (ex->>'order')::smallint, 'performed',
      coalesce(ex->>'kind', 'prescribed'), ex->>'name')
    returning id into pid;
    n := 0;
    for st in select value from jsonb_array_elements(ex->'sets') loop
      n := n + 1;
      insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions,
        load_kg, completed)
      values (p_user, pid, n, (st->>0)::smallint, nullif(st->>1, '')::numeric,
        coalesce((st->>2)::boolean, true));
    end loop;
  end loop;
  return sid;
end $$;

-- Exercise identity ---------------------------------------------------------------------

select pg_temp.log_session('a7000000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000001', (select a_today - 25 from t), 'completed', 8,
  'legacy_default', 50,
  '[{"order":1,"kind":"extra","name":"Barbell  Bench press","sets":[[10,57.5]]}]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000001', (select a_today - 20 from t), 'completed', 8,
  'legacy_default', 50,
  '[{"order":1,"planned":"a7400000-0000-4000-8000-000000000001","sets":[[8,60],[6,62.5],[6,62.5]]},
    {"order":2,"planned":"a7400000-0000-4000-8000-000000000002","sets":[[12,15]]},
    {"order":3,"planned":"a7400000-0000-4000-8000-000000000003","sets":[[15,null],[12,null]]}]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000001', (select a_today - 15 from t), 'completed', 8,
  'legacy_default', 30,
  '[{"order":4,"planned":"a7400000-0000-4000-8000-000000000005","sets":[[8,60],[6,40],[10,null]]}]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000001', (select a_today - 10 from t), 'completed', 8,
  'legacy_default', 50,
  '[{"order":1,"planned":"a7400000-0000-4000-8000-000000000001","sets":[[8,62.5],[5,65],[5,70,false]]},
    {"order":3,"planned":"a7400000-0000-4000-8000-000000000003","sets":[[18,null]]}]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000001', (select a_today - 5 from t), 'completed', 8,
  'legacy_default', 50,
  '[{"order":1,"planned":"a7400000-0000-4000-8000-000000000001","sets":[[5,65]]}]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000001', (select a_today - 2 from t), 'abandoned', null,
  null, 20, '[{"order":1,"planned":"a7400000-0000-4000-8000-000000000001","sets":[[3,90]]}]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000001',
  'a7300000-0000-4000-8000-000000000001', (select a_today - 1 from t), 'in_progress', null,
  null, 20, '[{"order":1,"planned":"a7400000-0000-4000-8000-000000000001","sets":[[1,100]]}]');

select is((select count(*) from public.exercise_performances
    where user_id = 'a7000000-0000-4000-8000-000000000001' and exercise_slug = 'barbell-bench-press'),
  5::bigint, 'a prescribed performance carries its catalog slug');
select is((select exercise_slug from public.exercise_performances
    where user_id = 'a7000000-0000-4000-8000-000000000001' and performance_kind = 'extra'),
  null, 'an extra exercise has no slug');
select is((select exercise_slug from public.exercise_performances
    where planned_exercise_id = 'a7400000-0000-4000-8000-000000000002' limit 1),
  null, 'an exercise without a catalog entry has no slug');
update public.exercise_performances set performance_kind = 'substituted',
    performed_name = 'Dumbbell press', substitution_reason = 'Bench taken'
  where workout_session_id = (select id from public.workout_sessions
    where user_id = 'a7000000-0000-4000-8000-000000000001' and state = 'in_progress');
select is((select exercise_slug from public.exercise_performances
    where performance_kind = 'substituted'), null, 'a substitution drops the slug');

-- Exercise history ------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'a7000000-0000-4000-8000-000000000001';

insert into h select public.get_my_exercise_history(
  array['barbell-bench-press', 'push-up', 'Cable fly', 'Nothing logged', 'assisted-pull-up']);

select is((select j->>'schema_version' from h), '1.0', 'history schema 1.0');
select is((select j->>'sessions_limit' from h), '8', 'eight sessions by default');
select is((select e->>'kind' from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'barbell-bench-press'), 'load', 'a loaded lift is ranked by load');
select is((select e->'best_set' from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'barbell-bench-press'),
  jsonb_build_object('kind', 'load', 'load_kg', 65.00, 'repetitions', 5,
    'local_date', (select a_today - 10 from t)),
  'the best set is the heaviest; a tie goes to the earliest date; uncompleted sets never count');
select is((select e->'last_session'->>'local_date' from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'barbell-bench-press'), (select (a_today - 5)::text from t),
  'last time is the latest completed session, not a discarded or open one');
select is((select jsonb_array_length(e->'top_sets') from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'barbell-bench-press'), 4,
  'one heaviest set per completed session, including an older unslugged one by catalog name');
select is((select e->'top_sets'->2 from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'barbell-bench-press'),
  jsonb_build_object('local_date', (select a_today - 20 from t), 'load_kg', 62.50, 'repetitions', 6),
  'top sets run newest first');
select is((select (e->'best_set') - 'local_date' from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'push-up'),
  '{"kind":"reps","load_kg":null,"repetitions":18}'::jsonb,
  'a bodyweight exercise is ranked by reps');
select is((select e->'best_set'->>'load_kg' from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'Cable fly'), '15.00', 'an exercise without a slug is found by name');
select is((select e->>'kind' from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'assisted-pull-up'), 'assistance',
  'an assisted exercise is ranked by assistance');
select is((select (e->'best_set') - 'local_date' from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'assisted-pull-up'),
  '{"kind":"assistance","load_kg":40.00,"repetitions":6}'::jsonb,
  'less assistance is the better set; a set without a logged assistance is not ranked');
select is((select e - 'key' from h, jsonb_array_elements(j->'exercises') e
    where e->>'key' = 'Nothing logged'),
  '{"kind":null,"best_set":null,"top_sets":[],"last_session":null}'::jsonb,
  'an exercise with no history says so');
select is(jsonb_array_length(public.get_my_exercise_history(array['barbell-bench-press'], 1)
    ->'exercises'->0->'top_sets'), 1, 'the session count is honoured');
select is(public.get_my_exercise_history(array['push-up'], 99)->>'sessions_limit', '12',
  'the session count is capped at 12');
select is(public.get_my_exercise_history(array['push-up'], 0)->>'sessions_limit', '1',
  'and raised to at least 1');
select is(jsonb_array_length(public.get_my_exercise_history(array['push-up', ' push-up '])->'exercises'),
  1, 'repeated keys are answered once');
select throws_ok($$select public.get_my_exercise_history(array[]::text[])$$, '22023', null,
  'at least one key');
select throws_ok($$select public.get_my_exercise_history(null)$$, '22023', null, 'keys are required');
select throws_ok($$select public.get_my_exercise_history(
    (select array_agg('key ' || n) from generate_series(1, 21) n))$$, '22023', null,
  'at most 20 keys');
select throws_ok($$select public.get_my_exercise_history(array[repeat('x', 121)])$$, '22023', null,
  'a key is at most 120 characters');
select throws_ok($$select public.get_my_exercise_history(array['   '])$$, '22023', null,
  'a blank key is refused');

set local "request.jwt.claim.sub" = 'a7000000-0000-4000-8000-000000000002';
select is(public.get_my_exercise_history(array['barbell-bench-press'])->'exercises'->0->>'kind',
  null, 'another athlete sees none of it');

-- Training hub 1.6 ------------------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'a7000000-0000-4000-8000-000000000001';
insert into hub select public.get_my_training_hub(28);
select is((select j->>'schema_version' from hub), '1.6', 'hub schema 1.6');
select is((select j->'active_plan'->>'effective_date' from hub), '2026-09-16',
  'without an effective date the plan starts on the local day it was approved');
select is((select j->'active_plan'->>'approved_on' from hub), '2026-09-16',
  'the approval day is the athlete''s local date');
select is((select j->'active_plan'->>'progression_rule' from hub),
  'Add 2.5 kg once every set reaches the top of its range.', 'the progression rule is reported');
select is((select j->'workouts'->0->'exercises'->0->'primary_muscles' from hub),
  '["chest", "triceps"]'::jsonb, 'a catalog exercise reports its muscles');
select is((select j->'workouts'->0->'exercises'->1->'primary_muscles' from hub), '[]'::jsonb,
  'an unlinked exercise reports none, never a guess');
select is((select j->'workouts'->0->'exercises'->0->>'exercise_slug' from hub),
  'barbell-bench-press', 'and its slug');
select is((select j->'recent_sessions'->0->>'completion_source' from hub), 'manual',
  'recent sessions report how they were completed');
select is((select j->'recent_sessions'->0->>'effort_source' from hub), 'legacy_default',
  'and where the effort came from');
select is((select jsonb_array_length(j->'daily_load') from hub), 28, '28 days of load');
select is((select j->'daily_load'->27->>'local_date' from hub), (select a_today::text from t),
  'ending on the athlete''s local today');
select is((select j->>'local_today' from hub), (select a_today::text from t),
  'which the hub reports');

-- Completion provenance ---------------------------------------------------------------------------

insert into flow select 'v1', public.start_workout('a7300000-0000-4000-8000-000000000002',
  (select a_today from t), 'Asia/Kolkata', gen_random_uuid());
select is((select exercise_slug from public.exercise_performances
    where workout_session_id = (select id from flow where name = 'v1')),
  'barbell-bench-press', 'starting a workout records each exercise''s slug');
select public.sync_workout_draft((select id from flow where name = 'v1'), 1,
  '{"exercises":[{"order":1,"status":"performed","sets":[{"number":1,"repetitions":5,"load_kg":60,"completed":true}]}]}');
select is(public.complete_workout((select id from flow where name = 'v1'), 1, 2400, 3::smallint, 8, '')
    ->>'replayed', 'false', 'an installed build still completes a workout');
select is((select array[completion_source, session_effort_source] from public.workout_sessions
    where id = (select id from flow where name = 'v1')), array['manual', 'legacy_default'],
  'its fixed effort is recorded as the default it is');

insert into flow select 'v2', public.start_workout('a7300000-0000-4000-8000-000000000002',
  (select a_today - 3 from t), 'Asia/Kolkata', gen_random_uuid());
select public.sync_workout_draft((select id from flow where name = 'v2'), 1,
  '{"exercises":[{"order":1,"status":"performed","sets":[{"number":1,"repetitions":6,"load_kg":60,"completed":true}]}]}');
select throws_ok($$select public.complete_workout_v2((select id from flow where name = 'v2'), 1, 2400, 0, '')$$,
  '22023', null, 'session effort starts at 1');
select throws_ok($$select public.complete_workout_v2((select id from flow where name = 'v2'), 1, 2400, 7.5, '')$$,
  '22023', null, 'session effort is a whole number');
select throws_ok($$select public.complete_workout_v2((select id from flow where name = 'v2'), 1, 2400, null, '')$$,
  '22023', null, 'session effort is required');
select is(public.complete_workout_v2((select id from flow where name = 'v2'), 1, 2400, 7, null)
    - 'session_id' - 'logging_completeness',
  '{"schema_version":"1.0","completed_sets":1,"total_sets":1,"replayed":false}'::jsonb,
  'the athlete''s own effort completes the workout without an energy rating');
select is((select array[completion_source, session_effort_source, session_effort::text,
    coalesce(session_energy::text, 'none')] from public.workout_sessions
    where id = (select id from flow where name = 'v2')),
  array['manual', 'athlete', '7.0', 'none'], 'and is recorded as the athlete''s');
select is(public.complete_workout_v2((select id from flow where name = 'v2'), 1, 2400, 9, '')->>'replayed',
  'true', 'finishing twice changes nothing');
select is((select session_effort from public.workout_sessions
    where id = (select id from flow where name = 'v2')), 7.0, 'the first rating stands');

-- Discard ---------------------------------------------------------------------------------------------

insert into flow select 'discard', public.start_workout('a7300000-0000-4000-8000-000000000002',
  (select a_today - 4 from t), 'Asia/Kolkata', gen_random_uuid());
select is(public.abandon_workout((select id from flow where name = 'discard'))->>'replayed', 'false',
  'an open workout is discarded');
select is((select state::text from public.workout_sessions
    where id = (select id from flow where name = 'discard')), 'abandoned', 'and marked abandoned');
select is(public.abandon_workout((select id from flow where name = 'discard'))->>'replayed', 'true',
  'discarding twice is a replay');
select throws_ok($$select public.abandon_workout((select id from flow where name = 'v1'))$$,
  '22023', null, 'a completed workout cannot be discarded');
select throws_ok($$select public.complete_workout_v2((select id from flow where name = 'discard'), 1, 600, 5, '')$$,
  '55000', null, 'a discarded workout cannot be finished');
select is(public.get_my_workout_session('a7300000-0000-4000-8000-000000000002',
    (select a_today - 4 from t)), null, 'a discarded workout is not resumed');
select is(public.get_my_workout_session('a7300000-0000-4000-8000-000000000002',
    (select a_today - 3 from t))->>'session_effort_source', 'athlete',
  'the session reports where its effort came from');
set local "request.jwt.claim.sub" = 'a7000000-0000-4000-8000-000000000002';
select throws_ok($$select public.abandon_workout((select id from flow where name = 'v1'))$$,
  'P0002', null, 'another athlete''s workout is not found');
reset role;
select is((select count(*) from public.audit_events
    where action_code = 'workout.abandoned' and target_id = (select id from flow where name = 'discard')),
  1::bigint, 'discarding is audited once');

-- Apple Health completion ---------------------------------------------------------------------------------

insert into public.daily_health_summaries(user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at, workout_count, workout_minutes)
values ('a7000000-0000-4000-8000-000000000002', current_date, 'UTC', array['workouts']::text[],
  '[{"type":"workouts","source_id_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sample_id_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]'::jsonb,
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'complete', now(), now(), 1, 45);
set local role authenticated;
set local "request.jwt.claim.sub" = 'a7000000-0000-4000-8000-000000000002';
select public.healthkit_auto_complete_workout((select id from public.planned_workouts
    where user_id = 'a7000000-0000-4000-8000-000000000002'
      and preferred_weekday = extract(isodow from current_date)::integer), current_date);
select is((select array[completion_source, session_effort_source] from public.workout_sessions
    where user_id = 'a7000000-0000-4000-8000-000000000002'), array['healthkit', 'healthkit_default'],
  'an Apple Health completion records its source and default effort');
reset role;

-- Day-level load ------------------------------------------------------------------------------------------

-- C: nine effort-reported days before today (effort 10, so strain equals
-- minutes), a mixed day, a default-effort day, and today at 30.
select pg_temp.log_session('a7000000-0000-4000-8000-000000000003', 'a7300000-0000-4000-8000-000000000003',
  (select c_today - d.ago from t), 'completed', 10, 'athlete', d.minutes, '[]')
from (values (1, 50), (2, 10), (3, 20), (4, 30), (5, 40), (6, 60), (7, 70), (8, 80), (9, 90)) d(ago, minutes);
select pg_temp.log_session('a7000000-0000-4000-8000-000000000003', 'a7300000-0000-4000-8000-000000000003',
  (select c_today - 11 from t), 'completed', 6, 'athlete', 30, '[]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000003', 'a7300000-0000-4000-8000-000000000003',
  (select c_today - 11 from t), 'completed', 8, 'legacy_default', 40, '[]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000003', 'a7300000-0000-4000-8000-000000000003',
  (select c_today - 12 from t), 'completed', 8, 'legacy_default', 50, '[]');
select pg_temp.log_session('a7000000-0000-4000-8000-000000000003', 'a7300000-0000-4000-8000-000000000003',
  (select c_today from t), 'completed', 10, 'athlete', 30, '[]');

create temporary table dl as
  select (e->>'local_date')::date d, e from jsonb_array_elements(
    private.daily_load('a7000000-0000-4000-8000-000000000003', (select c_today from t))) e;

select is((select e - 'local_date' from dl where d = (select c_today from t)),
  '{"recorded":true,"strain":30.0,"minutes":30,"sessions":1,"effort_reported":true,"level":"easy","reference":"personal"}'::jsonb,
  'a day equal to the 33rd percentile of the last 28 days is easy (ties go lower)');
select is((select array[e->>'level', e->>'reference'] from dl where d = (select c_today - 1 from t)),
  array['moderate', 'personal'], 'a day between the 33rd and 67th percentiles is moderate');
select is((select array[e->>'level', e->>'reference'] from dl where d = (select c_today - 2 from t)),
  array['easy', 'fixed'], 'a light day with fewer than 8 reference days uses the fixed cut-offs');
select is((select array[e->>'level', e->>'reference'] from dl where d = (select c_today - 9 from t)),
  array['hard', 'fixed'], 'and a heavy one is hard');
select is((select e - 'local_date' from dl where d = (select c_today - 10 from t)),
  '{"recorded":false,"strain":0,"minutes":0,"sessions":0,"effort_reported":false,"level":"rest","reference":"fixed"}'::jsonb,
  'a day without training is a rest day');
select is((select array[e->>'effort_reported', coalesce(e->>'level', 'none')] from dl
    where d = (select c_today - 11 from t)), array['false', 'none'],
  'one default effort on a day means its level is unknown');
select is((select (e->>'strain')::numeric from dl where d = (select c_today - 11 from t)),
  (select round((public.compute_daily_metrics('a7000000-0000-4000-8000-000000000003',
    (select c_today - 11 from t), 'UTC')->'scores'->>'daily_strain')::numeric, 1)),
  'day strain matches compute_daily_metrics');

select finish();
rollback;
