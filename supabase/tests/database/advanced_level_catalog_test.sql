begin;
select no_plan();

-- The advanced level and four staple lifts (20261023100050_advanced_level_catalog.sql).

select ok(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
   from pg_enum e where e.enumtypid = 'public.experience_level'::regtype)
    = array['beginner', 'intermediate', 'advanced'],
  'the profile experience level already has an advanced value');

select lives_ok(
  $$update public.exercise_catalog set level = 'advanced' where slug = 'bodyweight-squat'$$,
  'the catalog accepts the advanced level');
select throws_ok(
  $$update public.exercise_catalog set level = 'expert' where slug = 'bodyweight-squat'$$,
  '23514',
  null,
  'and still refuses any other level');
select is(
  (select count(*) from pg_constraint
   where conrelid = 'public.exercise_catalog'::regclass and contype = 'c'
     and pg_get_constraintdef(oid) like '%level%'),
  1::bigint,
  'one level check remains');

select is(
  (select array_agg(slug order by slug) from public.exercise_catalog where level = 'advanced'
     and slug <> 'bodyweight-squat'),
  array['bulgarian-split-squat', 'close-grip-bench-press', 'incline-barbell-bench-press',
    'weighted-pull-up']::text[],
  'four staples are advanced-level rows');

select is(
  (select count(*) from public.exercise_catalog where status = 'active'),
  76::bigint,
  'the four new rows join the 72 that were there');

select is(
  (select (movement_pattern, primary_muscles, equipment_required, is_compound)::text
   from public.exercise_catalog where slug = 'weighted-pull-up'),
  '(vertical_pull,"{back,biceps}","{pull_up_bar,dumbbells}",t)',
  'the weighted pull-up is a vertical pull that needs a bar and a dumbbell');
select is(
  (select (movement_pattern, primary_muscles, equipment_required)::text
   from public.exercise_catalog where slug = 'close-grip-bench-press'),
  '(horizontal_push,"{chest,triceps}","{barbell,bench}")',
  'the close-grip bench press is a barbell horizontal push');
select is(
  (select (movement_pattern, primary_muscles, equipment_required)::text
   from public.exercise_catalog where slug = 'incline-barbell-bench-press'),
  '(horizontal_push,"{chest,shoulders}","{barbell,bench}")',
  'the incline barbell press trains the chest and front shoulders');
select is(
  (select (movement_pattern, primary_muscles, equipment_required)::text
   from public.exercise_catalog where slug = 'bulgarian-split-squat'),
  '(lunge,"{quads,glutes}","{dumbbells,bench}")',
  'the Bulgarian split squat is a loaded lunge with the rear foot on a bench');

select is(
  (select count(*) from public.exercise_catalog
   where slug in ('weighted-pull-up', 'close-grip-bench-press', 'incline-barbell-bench-press',
     'bulgarian-split-squat')
     and load_step_kg = 2.5 and exercise_role = 'variation'),
  4::bigint,
  'each staple steps by 2.5 kg and is a variation of the standard form');

select is(
  (select (knee_stress, back_stress, shoulder_stress)::text
   from public.exercise_catalog where slug = 'weighted-pull-up'),
  '(low,low,high)',
  'a weighted pull-up is rated harsher on the shoulder than the pull-up');
select is(
  (select knee_stress from public.exercise_catalog where slug = 'bulgarian-split-squat'),
  'high',
  'the Bulgarian split squat loads the knee through a deep single-leg bend');

select is(
  (select progressions from public.exercise_catalog where slug = 'pull-up'),
  array['weighted-pull-up']::text[],
  'the pull-up progresses to the weighted pull-up');
select ok(
  (select 'bulgarian-split-squat' = any(progressions) from public.exercise_catalog
   where slug = 'dumbbell-reverse-lunge')
  and (select 'close-grip-bench-press' = any(substitutes) from public.exercise_catalog
   where slug = 'barbell-bench-press'),
  'existing rows point at the new ones');
select is(
  (select count(*) from public.exercise_catalog c, unnest(c.regressions || c.progressions
     || c.substitutes) link
   where not exists (select 1 from public.exercise_catalog t where t.slug = link)),
  0::bigint,
  'every link still names a catalog exercise');
select is(
  (select count(*) from public.exercise_catalog c, unnest(c.substitutes) other
   join public.exercise_catalog o on o.slug = other
   where not (c.slug = any(o.substitutes))),
  0::bigint,
  'substitutes stay mutual');
select is(
  (select count(*) from public.exercise_catalog
   where knee_stress is null or back_stress is null or shoulder_stress is null),
  0::bigint,
  'every row, new ones included, has joint stress ratings');

-- Existing rows keep what they had: only links were added.
select is(
  (select (level, load_step_kg, exercise_role)::text
   from public.exercise_catalog where slug = 'pull-up'),
  '(intermediate,,)',
  'the pull-up keeps its level, has no load step and no role');
select is(
  (select (level, substitutes)::text from public.exercise_catalog where slug = 'barbell-bench-press'),
  '(beginner,"{dumbbell-bench-press,machine-chest-press,close-grip-bench-press,incline-barbell-bench-press}")',
  'the bench press keeps its level and its two earlier substitutes, then gains two');

-- Added load -----------------------------------------------------------------------------------------

select is(
  (select array_agg(slug order by slug) from public.exercise_catalog where added_load),
  array['weighted-pull-up']::text[],
  'only the weighted pull-up logs added load');
select is(
  (select array_agg(slug order by slug) from public.exercise_catalog
   where catalog_version = 'catalog-v2'),
  array['bulgarian-split-squat', 'close-grip-bench-press', 'incline-barbell-bench-press',
    'weighted-pull-up']::text[],
  'the four new rows carry catalog version v2');

-- Progression through next_session_targets ---------------------------------------------------------
-- One athlete: the bench press planned twice with different ranges (a heavy day, 6 to 9, and a light
-- day, 10 to 12), a weighted pull-up and a pull-up (6 to 8, bodyweight reps logged with no load),
-- and a curl planned twice with the same range.

insert into auth.users(id, role) values ('b4000000-0000-4000-8000-000000000001', 'authenticated');
-- These athletes answered the health check as cleared; a missing check is unscreened, never
-- cleared (20261102074318).
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms, outcome)
select u.id, true, false, false, 'cleared' from auth.users u
where not exists (select 1 from public.onboarding_screenings s where s.user_id = u.id);
insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level,
  training_days, session_minutes)
values ('b4000000-0000-4000-8000-000000000001', now(), true, 'advanced', array[1,2,4]::smallint[], 60);
insert into public.training_plans(id, user_id, title, source) values
  ('b4100000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000001', 'Advanced', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('b4200000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000001',
   'b4100000-0000-4000-8000-000000000001', 1, 'active', 6, 3, '{}', 'Approved', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('b4300000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000001',
   'b4200000-0000-4000-8000-000000000001', 1, 'Upper A', 'Heavy day', 1, 60, 'Warm up', 'Cool down'),
  ('b4300000-0000-4000-8000-000000000002', 'b4000000-0000-4000-8000-000000000001',
   'b4200000-0000-4000-8000-000000000001', 2, 'Upper B', 'Light day', 2, 60, 'Warm up', 'Cool down'),
  ('b4300000-0000-4000-8000-000000000003', 'b4000000-0000-4000-8000-000000000001',
   'b4200000-0000-4000-8000-000000000001', 3, 'Pull', 'Back', 4, 60, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug) values
  ('b4400000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000001',
   'b4300000-0000-4000-8000-000000000001', 1, 'Barbell bench press', 3, 6, 9, 120, 'barbell-bench-press'),
  ('b4400000-0000-4000-8000-000000000002', 'b4000000-0000-4000-8000-000000000001',
   'b4300000-0000-4000-8000-000000000002', 1, 'Barbell bench press', 3, 10, 12, 120, 'barbell-bench-press'),
  ('b4400000-0000-4000-8000-000000000003', 'b4000000-0000-4000-8000-000000000001',
   'b4300000-0000-4000-8000-000000000003', 1, 'Weighted pull-up', 3, 6, 8, 120, 'weighted-pull-up'),
  ('b4400000-0000-4000-8000-000000000004', 'b4000000-0000-4000-8000-000000000001',
   'b4300000-0000-4000-8000-000000000003', 2, 'Pull-up', 3, 6, 8, 120, 'pull-up'),
  ('b4400000-0000-4000-8000-000000000005', 'b4000000-0000-4000-8000-000000000001',
   'b4300000-0000-4000-8000-000000000001', 2, 'Dumbbell curl', 3, 8, 12, 75, 'dumbbell-curl'),
  ('b4400000-0000-4000-8000-000000000006', 'b4000000-0000-4000-8000-000000000001',
   'b4300000-0000-4000-8000-000000000002', 2, 'Dumbbell curl', 3, 8, 12, 75, 'dumbbell-curl');

create temporary table t4 as
  select private.local_date_for('b4000000-0000-4000-8000-000000000001') as today;

-- Sets are [reps, load_kg, reps_in_reserve]; an empty load is logged as no load.
create function pg_temp.log4(p_date date, p_workout uuid, p_exercises jsonb) returns void
language plpgsql as $$
declare sid uuid; ex jsonb; pid uuid; st jsonb; n integer;
begin
  insert into public.workout_sessions(user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  select 'b4000000-0000-4000-8000-000000000001', w.plan_version_id, w.id, p_date, 'UTC', 'completed',
    gen_random_uuid(), now() - (current_date - p_date) * interval '1 day', 3000, 8, 'athlete',
    'manual'
  from public.planned_workouts w where w.id = p_workout
  returning id into sid;
  for ex in select value from jsonb_array_elements(p_exercises) loop
    insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
      exercise_order, status, performance_kind)
    values ('b4000000-0000-4000-8000-000000000001', sid, (ex->>'planned')::uuid,
      (ex->>'order')::smallint, 'performed', 'prescribed')
    returning id into pid;
    n := 0;
    for st in select value from jsonb_array_elements(ex->'sets') loop
      n := n + 1;
      insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions,
        load_kg, rir, completed)
      values ('b4000000-0000-4000-8000-000000000001', pid, n, (st->>0)::smallint,
        nullif(st->>1, '')::numeric, nullif(st->>2, '')::smallint, true);
    end loop;
  end loop;
end $$;

-- Heavy day: bench 3 x 9 at 100 kg with two reps left, and curls.
select pg_temp.log4((select today - 4 from t4), 'b4300000-0000-4000-8000-000000000001',
  '[{"order":1,"planned":"b4400000-0000-4000-8000-000000000001","sets":[[9,100,2],[9,100,2],[9,100,2]]},
    {"order":2,"planned":"b4400000-0000-4000-8000-000000000005","sets":[[12,10,3],[12,10,3],[12,10,3]]}]');
-- The weighted pull-up and the pull-up: 3 x 8 with nothing added.
select pg_temp.log4((select today - 3 from t4), 'b4300000-0000-4000-8000-000000000003',
  '[{"order":1,"planned":"b4400000-0000-4000-8000-000000000003","sets":[[8,null,2],[8,null,2],[8,null,2]]},
    {"order":2,"planned":"b4400000-0000-4000-8000-000000000004","sets":[[8,null,2],[8,null,2],[8,null,2]]}]');

create function pg_temp.target4(p_id text) returns jsonb language sql as $$
  select t from jsonb_array_elements(private.next_session_targets('b4000000-0000-4000-8000-000000000001')) t
  where t->>'planned_exercise_id' = p_id
$$;

select is(pg_temp.target4('b4400000-0000-4000-8000-000000000001') - 'basis' - 'name' - 'exercise_key',
  '{"planned_exercise_id":"b4400000-0000-4000-8000-000000000001","action":"add_load","reason":"top_of_range","load_kg":102.5,"reps":6,"sets":3,"confidence":"high"}'::jsonb,
  'the heavy day progresses from its own session: 100 kg x 9 at the top of 6 to 9 adds one step');
select is(pg_temp.target4('b4400000-0000-4000-8000-000000000002'), null::jsonb,
  'the light day has no history of its own yet, so the heavy session sets no target for it');

-- Light day: bench 3 x 12 at 80 kg.
select pg_temp.log4((select today - 2 from t4), 'b4300000-0000-4000-8000-000000000002',
  '[{"order":1,"planned":"b4400000-0000-4000-8000-000000000002","sets":[[12,80,2],[12,80,2],[12,80,2]]}]');

select is(pg_temp.target4('b4400000-0000-4000-8000-000000000002') - 'basis' - 'name' - 'exercise_key',
  '{"planned_exercise_id":"b4400000-0000-4000-8000-000000000002","action":"add_load","reason":"top_of_range","load_kg":82.5,"reps":10,"sets":3,"confidence":"high"}'::jsonb,
  'the light day progresses from its own session');
select is(pg_temp.target4('b4400000-0000-4000-8000-000000000001') - 'basis' - 'name' - 'exercise_key',
  '{"planned_exercise_id":"b4400000-0000-4000-8000-000000000001","action":"add_load","reason":"top_of_range","load_kg":102.5,"reps":6,"sets":3,"confidence":"high"}'::jsonb,
  'and the later light session does not move the heavy day''s target');
select is(
  (select array[jsonb_array_length(pg_temp.target4('b4400000-0000-4000-8000-000000000001')->'basis'->'recent'),
    jsonb_array_length(pg_temp.target4('b4400000-0000-4000-8000-000000000002')->'basis'->'recent')]),
  array[1, 1],
  'each range keeps one session of history');

select is(pg_temp.target4('b4400000-0000-4000-8000-000000000003') - 'basis' - 'name' - 'exercise_key',
  '{"planned_exercise_id":"b4400000-0000-4000-8000-000000000003","action":"add_load","reason":"top_of_range","load_kg":2.5,"reps":6,"sets":3,"confidence":"high"}'::jsonb,
  'a weighted pull-up logged with no load adds its first 2.5 kg');
select is(pg_temp.target4('b4400000-0000-4000-8000-000000000003')->'basis'->'recent'->0->>'load_kg', '0',
  'having started from nothing added');
select is(pg_temp.target4('b4400000-0000-4000-8000-000000000004') - 'basis' - 'name' - 'exercise_key',
  '{"planned_exercise_id":"b4400000-0000-4000-8000-000000000004","action":"hold","reason":"top_no_step","load_kg":null,"reps":8,"sets":3,"confidence":"high"}'::jsonb,
  'a pull-up with no load still holds at the top of its range');

select is(pg_temp.target4('b4400000-0000-4000-8000-000000000005') - 'basis' - 'name' - 'exercise_key',
  '{"planned_exercise_id":"b4400000-0000-4000-8000-000000000005","action":"add_load","reason":"top_of_range","load_kg":12.5,"reps":8,"sets":3,"confidence":"high"}'::jsonb,
  'a lift planned twice with the same range, curls: progresses');
select is(
  pg_temp.target4('b4400000-0000-4000-8000-000000000006') - 'basis' - 'planned_exercise_id',
  pg_temp.target4('b4400000-0000-4000-8000-000000000005') - 'basis' - 'planned_exercise_id',
  'and both plan rows share the history, as before (no split by range)');

-- The coach plan state carries the level.
select is(public.get_coach_plan_state_v1('b4000000-0000-4000-8000-000000000001', current_date)
    ->>'experience', 'advanced', 'the Coach plan state reports the advanced level');
select is(public.get_coach_plan_state_v1('b4000000-0000-4000-8000-000000000001', current_date)
    ->>'schema_version', '1.3', 'in plan state 1.3');

-- The proposal inputs carry the planned exercise id, so a next-session adjustment matches the heavy
-- and the light day's target on their own rows and not on the shared slug.
select is(public.get_coach_proposal_inputs_v1('b4000000-0000-4000-8000-000000000001')
    ->>'schema_version', '1.1', 'the proposal inputs are 1.1');
select is(
  (select jsonb_agg(e->>'planned_exercise_id' order by w.ord)
   from jsonb_array_elements(
     public.get_coach_proposal_inputs_v1('b4000000-0000-4000-8000-000000000001') -> 'plan' -> 'workouts'
   ) with ordinality as w(workout, ord),
   jsonb_array_elements(w.workout -> 'exercises') e
   where e->>'slug' = 'barbell-bench-press'),
  '["b4400000-0000-4000-8000-000000000001","b4400000-0000-4000-8000-000000000002"]'::jsonb,
  'the heavy and the light bench each carry their own planned exercise id');

-- Athletes read the catalog and cannot change it: the only privilege they hold is select.
select ok(has_table_privilege('authenticated', 'public.exercise_catalog', 'select'),
  'athletes can read the catalog');
select ok(not has_table_privilege('authenticated', 'public.exercise_catalog', 'insert'),
  'athletes cannot add a catalog row');
select ok(not has_table_privilege('authenticated', 'public.exercise_catalog', 'update'),
  'athletes cannot change a catalog row');
select ok(not has_table_privilege('authenticated', 'public.exercise_catalog', 'delete'),
  'athletes cannot delete a catalog row');
select ok(not has_table_privilege('anon', 'public.exercise_catalog', 'select'),
  'and a signed-out caller cannot read it');
set local role authenticated;
select is(
  (select level from public.exercise_catalog where slug = 'bulgarian-split-squat'),
  'advanced',
  'athletes can read the new rows');
reset role;

select * from finish();
rollback;
