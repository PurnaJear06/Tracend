begin;
select no_plan();

-- B3: next-session targets from logged sets, and training hub 1.7.
-- Part 1 tests the pure decision with synthetic sessions; part 2 logs real sets and reads the hub.

-- A session summary as private.next_session_targets builds it (latest first in the array).
create function pg_temp.sess(p_load numeric, p_sets integer, p_min_reps integer, p_total integer,
  p_min_rir integer default 2, p_known boolean default true, p_pain boolean default false)
returns jsonb language sql as $$
  select jsonb_build_object('load_kg', p_load, 'sets', p_sets, 'min_reps', p_min_reps,
    'total_reps', p_total, 'min_rir', p_min_rir, 'effort_known', p_known, 'pain', p_pain)
$$;

-- 3 sets of 6 to 8 at RPE 8 (two reps in reserve), 2.5 kg step, 3 days since the last session.
create function pg_temp.decide(p_sessions jsonb, p_gap integer default 3,
  p_skipped boolean default false, p_step numeric default 2.5, p_pain_since boolean default false,
  p_assisted boolean default false)
returns jsonb language sql as $$
  select private.progression_decision(3, 6, 8, 8, p_step, p_gap, p_skipped, p_pain_since,
    p_assisted, p_sessions)
$$;

select is(pg_temp.decide('[]'::jsonb), null, 'no logged session, no target');

select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24, 2))),
  '{"action":"add_load","reason":"top_of_range","load_kg":82.5,"reps":6,"sets":3,"confidence":"high"}'::jsonb,
  'every set at the top with two reps left: one step up, reps restart at the bottom');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24, 1)))->>'reason', 'effort',
  'a set with one rep left (below the planned two) holds the load');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24, 1)))->>'load_kg', '80',
  'and the target stays at the logged load');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 6, 19)))->>'reps', '7',
  'within the range the weakest set adds one rep');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 6, 19)))->>'action', 'add_reps',
  'and the action says so');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 7, 22)))->>'reps', '8',
  'reps stop at the top of the range');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 2, 8, 16)))->>'reason', 'incomplete',
  'fewer sets than planned holds');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 2, 8, 16)))->>'action', 'hold',
  'incomplete is a hold');

-- Below the range once holds; twice at the same load lowers one step.
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 4, 15)))->>'action', 'hold',
  'once below the range holds');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 4, 15)))->>'reps', '6',
  'and aims for the bottom of the range');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 4, 15), pg_temp.sess(80, 3, 5, 16))),
  '{"action":"lower","reason":"below_range","load_kg":77.5,"reps":6,"sets":3,"confidence":"high"}'::jsonb,
  'twice below the range at one load lowers one step');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 4, 15), pg_temp.sess(75, 3, 5, 16)))->>'action',
  'hold', 'a lighter load in between is not the same stall');

-- A stall: three sessions at one load without more total reps.
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 6, 18), pg_temp.sess(80, 3, 6, 18),
    pg_temp.sess(80, 3, 6, 19))),
  '{"action":"lower","reason":"stall","load_kg":77.5,"reps":6,"sets":3,"confidence":"high"}'::jsonb,
  'three sessions without progress lower one step');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 6, 18), pg_temp.sess(80, 3, 6, 18),
    pg_temp.sess(80, 3, 6, 17)))->>'action', 'add_reps',
  'three sessions that improved keep adding reps');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 6, 18), pg_temp.sess(80, 3, 6, 18)))->>'action',
  'add_reps', 'two sessions are not yet a stall');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 6, 18), pg_temp.sess(80, 3, 6, 18),
    pg_temp.sess(80, 3, 6, 19)), 3, false, null)->>'action', 'hold',
  'a stalled exercise without a load step holds');

-- Time away, a skipped session and pain.
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24)), 13)->>'action', 'add_load',
  '13 days away still progresses');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24)), 14),
  '{"action":"hold","reason":"away","load_kg":80,"reps":8,"sets":3,"confidence":"high"}'::jsonb,
  '14 days away holds at the last logged result');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24)), 28)->>'load_kg', '77.5',
  '28 days away lowers one step');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24)), 28, false, null)->>'action', 'hold',
  '28 days away without a load step holds');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24)), 3, true)->>'reason', 'skipped',
  'a skipped session after the last logged one holds');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24, 2, true, true)))->>'reason', 'pain',
  'a pain flag holds');

select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24)), 3, false, 2.5, true),
  '{"action":"hold","reason":"pain","load_kg":80,"reps":8,"sets":3,"confidence":"high"}'::jsonb,
  'pain flagged on a later performance holds, however good the last logged session was');

-- Assisted exercises: the load is machine help, so less is harder and 0 is unassisted.
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(20, 3, 8, 24)), 3, false, 5, false, true),
  '{"action":"add_load","reason":"top_of_range","load_kg":15,"reps":6,"sets":3,"confidence":"high"}'::jsonb,
  'assisted, every set at the top: one step less help');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(2.5, 3, 8, 24)), 3, false, 5, false, true)->>'load_kg',
  '0', 'less help never goes below zero');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(0, 3, 8, 24)), 3, false, 5, false, true),
  '{"action":"hold","reason":"top_no_step","load_kg":0,"reps":8,"sets":3,"confidence":"high"}'::jsonb,
  'an unassisted exercise has no less help to give: the load stays 0');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(20, 3, 4, 15), pg_temp.sess(20, 3, 5, 16)), 3,
    false, 5, false, true)->>'load_kg', '25', 'twice below the range adds one step of help');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(0, 3, 4, 15), pg_temp.sess(0, 3, 5, 16)), 3,
    false, 5, false, true)->>'load_kg', '5', 'and an unassisted lifter can be given help');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(20, 3, 8, 24)), 28, false, 5, false, true)->>'load_kg',
  '25', '28 days away adds one step of help');
select is((
  select count(*) from generate_series(1, 12) reps, generate_series(1, 4) sets,
    unnest(array[null, 0, 1, 2, 3, 5]::integer[]) rir, generate_series(0, 30, 7) gap,
    unnest(array[true, false]) skipped, unnest(array[true, false]) pain
  where (pg_temp.decide(jsonb_build_array(pg_temp.sess(20, sets, reps, reps * sets, rir)),
          gap, skipped, 5, pain, true)->>'load_kg')::numeric not between 15 and 25
), 0::bigint, 'assisted help moves by at most one step either way');

-- Steps, bodyweight, unknown effort.
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24)), 3, false, null),
  '{"action":"hold","reason":"top_no_step","load_kg":80,"reps":8,"sets":3,"confidence":"high"}'::jsonb,
  'at the top without a load step the target stays at the top reps');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(null, 3, 8, 24)))->>'action', 'hold',
  'a bodyweight exercise never gets a load');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(null, 3, 6, 19)))->>'load_kg', null,
  'and its target has no load');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24, null, false)))->>'confidence', 'low',
  'effort that was not logged lowers confidence');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(80, 3, 8, 24, null, false)))->>'action', 'add_load',
  'and does not block progress by itself');
select is(pg_temp.decide(jsonb_build_array(pg_temp.sess(2.5, 3, 6, 19)), 28)->>'load_kg', '2.5',
  'a lowering never reaches zero load');

-- However the history looks, the load never rises by more than one step.
select is((
  select count(*) from generate_series(1, 12) reps, generate_series(1, 4) sets,
    unnest(array[null, 0, 1, 2, 3, 5]::integer[]) rir, generate_series(0, 30, 7) gap,
    unnest(array[true, false]) skipped
  where (pg_temp.decide(jsonb_build_array(pg_temp.sess(80, sets, reps, reps * sets, rir)),
          gap, skipped)->>'load_kg')::numeric > 82.5
), 0::bigint, 'the load never rises by more than the step');
select is((
  select count(*) from generate_series(1, 12) reps, generate_series(1, 4) sets, generate_series(0, 30, 7) gap
  where (pg_temp.decide(jsonb_build_array(pg_temp.sess(80, sets, reps, reps * sets)), gap)->>'reps')::integer
    not between 6 and 8
), 0::bigint, 'the target reps always sit inside the plan''s range');

-- Part 2: real logged sets through the hub -------------------------------------------------

insert into auth.users(id, role) values
  ('b3000000-0000-4000-8000-000000000001', 'authenticated'),
  ('b3000000-0000-4000-8000-000000000002', 'authenticated');
insert into public.training_plans(id, user_id, title, source) values
  ('b3100000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'Strength', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('b3200000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001',
   'b3100000-0000-4000-8000-000000000001', 1, 'active', 6, 2, '{}', 'Approved', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('b3300000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001',
   'b3200000-0000-4000-8000-000000000001', 1, 'Upper A', 'Press', 1, 50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug) values
  ('b3400000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001',
   'b3300000-0000-4000-8000-000000000001', 1, 'Barbell bench press', 3, 5, 8, 120, 'barbell-bench-press'),
  ('b3400000-0000-4000-8000-000000000002', 'b3000000-0000-4000-8000-000000000001',
   'b3300000-0000-4000-8000-000000000001', 2, 'Cable fly', 2, 10, 12, 60, null),
  ('b3400000-0000-4000-8000-000000000003', 'b3000000-0000-4000-8000-000000000001',
   'b3300000-0000-4000-8000-000000000001', 3, 'Push-up', 2, 10, 20, 60, 'push-up'),
  ('b3400000-0000-4000-8000-000000000004', 'b3000000-0000-4000-8000-000000000001',
   'b3300000-0000-4000-8000-000000000001', 4, 'Assisted pull-up', 2, 6, 10, 90, 'assisted-pull-up'),
  ('b3400000-0000-4000-8000-000000000005', 'b3000000-0000-4000-8000-000000000001',
   'b3300000-0000-4000-8000-000000000001', 5, 'Assisted chin-up', 2, 6, 8, 90, null),
  ('b3400000-0000-4000-8000-000000000006', 'b3000000-0000-4000-8000-000000000001',
   'b3300000-0000-4000-8000-000000000001', 6, 'Dumbbell curl', 3, 8, 12, 60, 'dumbbell-curl');

create temporary table t as
  select private.local_date_for('b3000000-0000-4000-8000-000000000001') as today;
grant select on t to authenticated;
create temporary table hub(j jsonb);
grant all on hub to authenticated;

-- Sets are [reps, load_kg, reps_in_reserve, completed (default true)].
create function pg_temp.log_session(p_date date, p_state public.workout_session_state,
  p_exercises jsonb) returns uuid language plpgsql as $$
declare sid uuid; ex jsonb; pid uuid; st jsonb; n integer;
begin
  insert into public.workout_sessions(user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  select 'b3000000-0000-4000-8000-000000000001', w.plan_version_id, w.id, p_date, 'UTC', p_state,
    gen_random_uuid(),
    case when p_state = 'completed' then now() - (current_date - p_date) * interval '1 day' end,
    3000, 8, case when p_state = 'completed' then 'athlete' end,
    case when p_state = 'completed' then 'manual' end
  from public.planned_workouts w where w.id = 'b3300000-0000-4000-8000-000000000001'
  returning id into sid;
  for ex in select value from jsonb_array_elements(p_exercises) loop
    insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
      exercise_order, status, performance_kind, pain_flag)
    values ('b3000000-0000-4000-8000-000000000001', sid, (ex->>'planned')::uuid,
      (ex->>'order')::smallint, 'performed', 'prescribed', coalesce((ex->>'pain')::boolean, false))
    returning id into pid;
    n := 0;
    for st in select value from jsonb_array_elements(ex->'sets') loop
      n := n + 1;
      insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions,
        load_kg, rir, completed)
      values ('b3000000-0000-4000-8000-000000000001', pid, n, (st->>0)::smallint,
        nullif(st->>1, '')::numeric, nullif(st->>2, '')::smallint, coalesce((st->>3)::boolean, true));
    end loop;
  end loop;
  return sid;
end $$;

-- An older session, then the latest: bench 3 x 8 at 60 kg with three reps left, a lighter back-off
-- set and an unticked heavier set (neither counts); the fly without reps in reserve logged.
select pg_temp.log_session((select today - 14 from t), 'completed',
  '[{"order":1,"planned":"b3400000-0000-4000-8000-000000000001","sets":[[8,57.5,3],[7,57.5,3],[6,57.5,2]]}]');
select pg_temp.log_session((select today - 7 from t), 'completed',
  '[{"order":1,"planned":"b3400000-0000-4000-8000-000000000001",
     "sets":[[8,60,3],[8,60,3],[8,60,3],[12,40,4],[5,70,0,false]]},
    {"order":2,"planned":"b3400000-0000-4000-8000-000000000002","sets":[[10,15],[10,15]]},
    {"order":4,"planned":"b3400000-0000-4000-8000-000000000004","sets":[[10,20],[10,15],[10,15]]},
    {"order":5,"planned":"b3400000-0000-4000-8000-000000000005","sets":[[8,0],[8,0]]}]');
-- Curls went well, then a later session flagged pain on them without logging a set.
select pg_temp.log_session((select today - 8 from t), 'completed',
  '[{"order":6,"planned":"b3400000-0000-4000-8000-000000000006","sets":[[12,10,3],[12,10,3],[12,10,3]]}]');
select pg_temp.log_session((select today - 3 from t), 'completed',
  '[{"order":6,"planned":"b3400000-0000-4000-8000-000000000006","pain":true,"sets":[]}]');
-- A session still in progress does not count.
select pg_temp.log_session((select today from t), 'in_progress',
  '[{"order":1,"planned":"b3400000-0000-4000-8000-000000000001","sets":[[8,100,0]]}]');

set local role authenticated;
set local "request.jwt.claim.sub" = 'b3000000-0000-4000-8000-000000000001';
insert into hub select public.get_my_training_hub(28);
reset role;

select is((select j->>'schema_version' from hub), '1.7', 'hub schema 1.7');
select is((select array(select k from jsonb_object_keys(j) k order by k collate "C") from hub),
  array['active_plan', 'adherence', 'completed_day_set', 'computed', 'daily_load', 'local_today',
    'next_targets', 'period_days', 'progression', 'recent_sessions', 'schema_version',
    'today_workout', 'workouts'],
  'the hub keeps every 1.6 key and adds next_targets');
select is((select array(select k from jsonb_object_keys(j->'workouts'->0->'exercises'->0) k
    order by k collate "C") from hub),
  array['exercise_slug', 'id', 'name', 'notes', 'order', 'primary_muscles', 'rep_max', 'rep_min',
    'rest_seconds', 'set_count', 'target_load_kg', 'target_rpe'],
  'an exercise keeps its 1.6 keys');
select is((select array(select k from jsonb_object_keys(j->'next_targets'->0) k order by k collate "C")
    from hub),
  array['action', 'basis', 'confidence', 'exercise_key', 'load_kg', 'name', 'planned_exercise_id',
    'reason', 'reps', 'sets'],
  'a target reports exactly these keys');
select is((select jsonb_array_length(j->'next_targets') from hub), 5,
  'an exercise without logged sets gets no target (the plan''s prescription stands)');
select is((select j->'next_targets'->0->>'name' from hub), 'Barbell bench press',
  'targets follow the plan order');
select is((select (j->'next_targets'->0) - 'basis' - 'planned_exercise_id' from hub),
  '{"name":"Barbell bench press","exercise_key":"barbell-bench-press","action":"add_load",
    "reason":"top_of_range","load_kg":62.5,"reps":5,"sets":3,"confidence":"high"}'::jsonb,
  'bench: every set at 8 with three reps left, so +2.5 kg and back to the bottom of the range');
select is((select j->'next_targets'->0->'basis'->>'last_date' from hub), (select (today - 7)::text from t),
  'built from the latest completed session, not the one in progress');
select is((select jsonb_array_length(j->'next_targets'->0->'basis'->'recent') from hub), 2,
  'with the earlier session behind it');
select is((select j->'next_targets'->0->'basis'->'recent'->0->>'sets' from hub), '3',
  'the back-off set and the unticked set are not working sets');
select is((select (j->'next_targets'->1) - 'basis' - 'planned_exercise_id' from hub),
  '{"name":"Cable fly","exercise_key":"cable fly","action":"add_reps","reason":"within_range",
    "load_kg":15,"reps":11,"sets":2,"confidence":"low"}'::jsonb,
  'fly without reps in reserve: one more rep, lower confidence');
select is((select (j->'next_targets'->2) - 'basis' - 'planned_exercise_id' from hub),
  '{"name":"Assisted pull-up","exercise_key":"assisted-pull-up","action":"add_load",
    "reason":"top_of_range","load_kg":10,"reps":6,"sets":2,"confidence":"low"}'::jsonb,
  'assisted pull-up: mixed help, the least help (15 kg) is the working load, so one step less');
select is((select (j->'next_targets'->3) - 'basis' - 'planned_exercise_id' from hub),
  '{"name":"Assisted chin-up","exercise_key":"assisted chin-up","action":"hold","reason":"top_no_step",
    "load_kg":0,"reps":8,"sets":2,"confidence":"low"}'::jsonb,
  'an unassisted set is a real load of 0, not a missing one');
select is((select (j->'next_targets'->4) - 'basis' - 'planned_exercise_id' from hub),
  '{"name":"Dumbbell curl","exercise_key":"dumbbell-curl","action":"hold","reason":"pain",
    "load_kg":10,"reps":12,"sets":3,"confidence":"high"}'::jsonb,
  'a later pain flag with no sets holds the earlier successful curls');
select is((select j->'next_targets'->0->>'planned_exercise_id' from hub),
  'b3400000-0000-4000-8000-000000000001', 'a target names its planned exercise');
select is((select j->'workouts'->0->'exercises'->0->>'target_load_kg' from hub), null,
  'the plan''s own prescription is untouched');

-- The service-role summary matches the hub, and nobody else can call it.
select is(public.get_progression_summary_v1('b3000000-0000-4000-8000-000000000001')->'targets',
  (select j->'next_targets' from hub), 'the Coach summary reports the same targets');
select is(public.get_progression_summary_v1('b3000000-0000-4000-8000-000000000001')->>'schema_version',
  '1.0', 'with its own schema version');
select is(public.get_progression_summary_v1('b3000000-0000-4000-8000-000000000002')->'targets',
  '[]'::jsonb, 'an athlete without a plan has no targets');
select ok(has_function_privilege('service_role', 'public.get_progression_summary_v1(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_progression_summary_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_progression_summary_v1(uuid)', 'execute'),
  'only the service role reads the Coach summary');
select ok(not has_function_privilege('authenticated', 'private.next_session_targets(uuid)', 'execute')
  and not has_function_privilege('anon', 'private.next_session_targets(uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'private.progression_decision(integer, integer, integer, numeric, numeric, integer, boolean, boolean, boolean, jsonb)',
    'execute'),
  'the target functions are private');

select * from finish();
rollback;
