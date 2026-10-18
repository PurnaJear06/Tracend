begin;
select no_plan();

-- A10: complete logging days, change eligibility, the Coach baseline RPCs, the ten lookups and
-- the turn trace columns (migration 20261018100020_coach_data_lookups.sql).

insert into auth.users(id, role) values
  ('a1000000-0000-4000-8000-000000000001', 'authenticated'),
  ('a1000000-0000-4000-8000-000000000002', 'authenticated');
insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level, training_days,
  session_minutes)
values ('a1000000-0000-4000-8000-000000000001', now(), true, 'intermediate', array[1,3,5]::smallint[], 60);
update public.user_profiles
set daily_activity = 'some_standing', equipment = array['dumbbells', 'bench'],
  avoid_patterns = array['hinge']
where user_id = 'a1000000-0000-4000-8000-000000000001';

-- The plan: today's workout (the weekday of today) and the next day's.
insert into public.training_plans(id, user_id, title, source) values
  ('a1100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'Push pull', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('a1200000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001',
   'a1100000-0000-4000-8000-000000000001', 1, 'active', 6, 2, '{}', 'Approved for the test', now(),
   current_date - 60);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('a1300000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001',
   'a1200000-0000-4000-8000-000000000001', 1, 'Push day', 'Press', extract(isodow from current_date)::integer,
   50, 'Warm up', 'Cool down'),
  ('a1300000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001',
   'a1200000-0000-4000-8000-000000000001', 2, 'Pull day', 'Row',
   (extract(isodow from current_date)::integer % 7) + 1, 50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug, target_load_kg) values
  ('a1400000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001',
   'a1300000-0000-4000-8000-000000000001', 1, 'Barbell bench press', 3, 6, 8, 120, 'barbell-bench-press', 60),
  ('a1400000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001',
   'a1300000-0000-4000-8000-000000000001', 2, 'Cable chest fly', 2, 10, 12, 60, 'cable-chest-fly', null),
  ('a1400000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000001',
   'a1300000-0000-4000-8000-000000000002', 1, 'Barbell row', 3, 6, 8, 90, 'barbell-row', null);

-- Sets are [reps, load_kg, reps_in_reserve].
create function pg_temp.log_session(p_date date, p_exercises jsonb) returns uuid language plpgsql as $$
declare sid uuid; ex jsonb; pid uuid; st jsonb; n integer;
begin
  insert into public.workout_sessions(user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  select 'a1000000-0000-4000-8000-000000000001', w.plan_version_id, w.id, p_date, 'UTC', 'completed',
    gen_random_uuid(), now() - (current_date - p_date) * interval '1 day', 3000, 8, 'athlete', 'manual'
  from public.planned_workouts w where w.id = 'a1300000-0000-4000-8000-000000000001'
  returning id into sid;
  for ex in select value from jsonb_array_elements(p_exercises) loop
    insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
      exercise_order, status, performance_kind, exercise_slug)
    values ('a1000000-0000-4000-8000-000000000001', sid, (ex->>'planned')::uuid,
      (ex->>'order')::smallint, 'performed', 'prescribed', ex->>'slug')
    returning id into pid;
    n := 0;
    for st in select value from jsonb_array_elements(ex->'sets') loop
      n := n + 1;
      insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions,
        load_kg, rir, completed)
      values ('a1000000-0000-4000-8000-000000000001', pid, n, (st->>0)::smallint,
        (st->>1)::numeric, nullif(st->>2, '')::smallint, true);
    end loop;
  end loop;
  return sid;
end $$;

select pg_temp.log_session(current_date - 40,
  '[{"order":1,"planned":"a1400000-0000-4000-8000-000000000001","slug":"barbell-bench-press","sets":[[8,70,3],[8,70,3],[7,70,2]]}]');
select pg_temp.log_session(current_date - 5,
  '[{"order":1,"planned":"a1400000-0000-4000-8000-000000000001","slug":"barbell-bench-press","sets":[[8,75,3],[8,75,3],[8,75,3]]}]');

-- Nutrition: an active 2,000 kcal target. Day -1: 3 small meals (complete by meals, 1,500 kcal).
-- Day -2: 2 meals, 1,500 kcal (75% of the target, complete). Day -3: 1 meal, 200 kcal (partial).
-- Today: 1 meal, 300 kcal (partial), logged from the schedule, a photo estimate.
insert into public.nutrition_target_sets(id, user_id, version_number, status, calories, protein_g,
  carbohydrate_g, fat_g, rationale, approved_at, effective_date) values
  ('a1500000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 1, 'active', 2000,
   150, 220, 65, 'Target for the test', now(), current_date - 60);
insert into public.nutrition_schedule_versions(id, user_id, version_number, status, title, rationale,
  approved_at, effective_date) values
  ('a1600000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 1, 'active',
   'Schedule', 'For the test', now(), current_date - 60);
insert into public.nutrition_schedule_items(id, user_id, schedule_version_id, item_order, slot_key, label,
  local_time, foods) values
  ('a1700000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001',
   'a1600000-0000-4000-8000-000000000001', 1, 'pre_workout', 'Pre-workout', '07:45',
   '[{"name":"Banana","quantity":"1"}]'),
  ('a1700000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001',
   'a1600000-0000-4000-8000-000000000001', 2, 'lunch', 'Lunch', '13:00',
   '[{"name":"Rice","quantity":"200 g"}]');
create function pg_temp.meal(p_id text, p_date date, p_type text, p_source public.meal_source,
  p_kcal numeric, p_slot uuid default null) returns void language sql as $$
  with m as (
    insert into public.meals(id, user_id, local_date, timezone, meal_type, source, status,
      idempotency_key, confirmed_at, nutrition_schedule_item_id)
    values (('a1800000-0000-4000-8000-' || p_id)::uuid, 'a1000000-0000-4000-8000-000000000001', p_date,
      'UTC', p_type, p_source, 'confirmed', gen_random_uuid(), now(), p_slot)
    returning id)
  insert into public.meal_items(user_id, meal_id, name_snapshot, serving_label, calories, protein_g,
    carbohydrate_g, fat_g, confirmed_at)
  select 'a1000000-0000-4000-8000-000000000001', m.id, 'Food', '1 serving', p_kcal, 20, 50, 10, now()
  from m;
$$;
select pg_temp.meal('000000000001', current_date - 1, 'breakfast', 'manual', 500);
select pg_temp.meal('000000000002', current_date - 1, 'lunch', 'manual', 500);
select pg_temp.meal('000000000003', current_date - 1, 'dinner', 'photo_analysis', 500);
select pg_temp.meal('000000000004', current_date - 2, 'lunch', 'manual', 750);
select pg_temp.meal('000000000005', current_date - 2, 'dinner', 'manual', 750);
select pg_temp.meal('000000000006', current_date - 3, 'snack', 'manual', 200);
select pg_temp.meal('000000000007', current_date, 'breakfast', 'manual', 300,
  'a1700000-0000-4000-8000-000000000001');

-- Complete logging days ---------------------------------------------------------------------

select is((select array_agg(local_date - current_date order by local_date)
    from private.nutrition_day_totals('a1000000-0000-4000-8000-000000000001', current_date - 7, current_date)
    where complete),
  array[-2, -1], 'complete days: three meals, or 70% of the target');
select is((select array_agg(local_date - current_date order by local_date)
    from private.nutrition_day_totals('a1000000-0000-4000-8000-000000000001', current_date - 7, current_date)
    where not complete),
  array[-3, 0], 'a day with one small meal is partial, never a deficit');
select is((select calories from private.nutrition_day_totals('a1000000-0000-4000-8000-000000000001',
    current_date - 1, current_date - 1)), 1500::numeric, 'a day sums its meal items');
select is(private.nutrition_complete_day_rules(), '{"min_meals":3,"min_target_share":0.7}'::jsonb,
  'the rule numbers live in one place');
select is((select count(*) from private.nutrition_day_totals('a1000000-0000-4000-8000-000000000002',
    current_date - 7, current_date)), 0::bigint, 'another athlete has no days');

-- Change eligibility averages complete days only ------------------------------------------------

select is(public.evaluate_change_eligibility('a1000000-0000-4000-8000-000000000001', current_date)
    ->'nutrition_change'->>'complete_days', '2', 'eligibility counts the complete days');
select ok(public.evaluate_change_eligibility('a1000000-0000-4000-8000-000000000001', current_date)
    ->'nutrition_change'->>'detail' like '%75% adherence over 2 complete logging days (need 80%)%',
  'adherence is 75%: the two complete days (1,500 of 2,000), not diluted by the partial ones');
select is(public.evaluate_change_eligibility('a1000000-0000-4000-8000-000000000001', current_date)
    ->'nutrition_change'->>'eligible', 'false', 'and the gate stays closed on that evidence');
select is(public.evaluate_change_eligibility('a1000000-0000-4000-8000-000000000001', current_date)
    ->>'eligibility_version', 'eligibility-v2', 'the formula changed, so the version is v2');
select is(public.evaluate_change_eligibility('a1000000-0000-4000-8000-000000000002', current_date)
    ->'nutrition_change'->>'complete_days', '0', 'an athlete with no meals has no complete days');

-- The baseline ----------------------------------------------------------------------------------

select is((select array(select k from jsonb_object_keys(
    public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date)) k order by k collate "C")),
  array['avoid_patterns', 'completed_this_week', 'equipment', 'local_date', 'plan', 'progression',
    'recent_completed', 'schema_version', 'sessions', 'weekday'], 'the plan state reports exactly these keys');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->>'schema_version', '1.1', 'with a schema version');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'equipment', '["dumbbells","bench"]'::jsonb, 'equipment from the intake');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'avoid_patterns', '["hinge"]'::jsonb, 'and the movements to avoid');
select is(jsonb_array_length(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001',
    current_date)->'sessions'), 2, 'every planned session');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'sessions'->0->'exercises'->0->>'slug', 'barbell-bench-press', 'with its exercises and slugs');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'sessions'->0->'exercises'->0->>'load_kg', '60.00', 'and the plan load');
select is((public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'progression'->'targets'->0)->>'name', 'Barbell bench press', 'the next targets come with it');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'progression'->'targets'->0->'basis'->>'last_date', (current_date - 5)::text,
  'and the last logged session');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000002', current_date)->'plan',
  'null'::jsonb, 'an athlete without a plan has none');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000002', current_date)->'equipment',
  'null'::jsonb, 'and no equipment answer');

select is((select array(select k from jsonb_object_keys(
    public.get_coach_nutrition_state_v1('a1000000-0000-4000-8000-000000000001', current_date)) k order by k collate "C")),
  array['days', 'eaten_today', 'local_date', 'rules', 'schedule', 'schema_version', 'sources', 'target'],
  'the nutrition state reports exactly these keys');
select is((select array_agg((d->>'local_date')::date - current_date order by (d->>'local_date')::date)
    from jsonb_array_elements(public.get_coach_nutrition_state_v1(
      'a1000000-0000-4000-8000-000000000001', current_date)->'days') d where (d->>'complete')::boolean),
  array[-2, -1], 'the week''s complete days');
select is(public.get_coach_nutrition_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'schedule'->0->>'logged', 'true', 'the slot logged from the schedule is marked logged');
select is(public.get_coach_nutrition_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'schedule'->1->>'logged', 'false', 'the other is not');
select is(public.get_coach_nutrition_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'schedule'->1->'foods'->0->>'name', 'Rice', 'and still shows its planned foods');
select is(jsonb_array_length(public.get_coach_nutrition_state_v1('a1000000-0000-4000-8000-000000000001',
    current_date)->'eaten_today'), 1, 'what was eaten today');
select is(public.get_coach_nutrition_state_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'sources', '{"window_days":14,"meals":7,"photo_estimate":1,"from_schedule":1,"typed_in":5}'::jsonb,
  'where the meals came from');

select is((select array(select k from jsonb_object_keys(
    public.get_coach_data_index_v1('a1000000-0000-4000-8000-000000000001', current_date)->'domains') k
    order by k collate "C")),
  array['body', 'check_ins', 'goals', 'health_history', 'meals', 'plan_history', 'recovery',
    'weekly_reviews', 'workouts'], 'the index covers every kind of record');
select is(public.get_coach_data_index_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'domains'->'workouts', jsonb_build_object('first', current_date - 40, 'last', current_date - 5,
    'count', 2), 'with first and last date and a count');
select is(public.get_coach_data_index_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'domains'->'meals'->>'count', '4', 'meals count days');

-- More records for the lookups ---------------------------------------------------------------------

insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key, sleep_quality,
  energy, soreness, hunger, mood, pain_severity, available_to_train, note) values
  ('a1000000-0000-4000-8000-000000000001', current_date - 1, 'UTC', 1, gen_random_uuid(), 4, 4, 2, 3, 5, 0,
   true, repeat('n', 400));
insert into public.body_measurements(user_id, measured_on, source, weight_kg, waist_cm) values
  ('a1000000-0000-4000-8000-000000000001', current_date - 30, 'manual', 82.0, 90),
  ('a1000000-0000-4000-8000-000000000001', current_date - 2, 'manual', 80.5, 88);
insert into public.daily_health_summaries(user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at, resting_heart_rate_bpm, sleep_minutes)
values ('a1000000-0000-4000-8000-000000000001', current_date - 1, 'UTC', array['resting_heart_rate','sleep'],
  '[]'::jsonb, repeat('b', 64), 'partial', now(), now(), 57, 410);
insert into public.user_goals(user_id, goal_type, status, details, activated_at) values
  ('a1000000-0000-4000-8000-000000000001', 'fat_loss', 'active',
   '{"target_weight_kg": 76, "current_weight_kg": 86.2}', now() - interval '60 days');
insert into public.progress_reviews(user_id, review_week, schema_version, summary) values
  ('a1000000-0000-4000-8000-000000000001', current_date - 7, '1.0',
   '{"outcome_code":"week_observed","training":{"planned_sessions":2,"completed_workouts":1,"completed_sets":9,"adherence_percent":50},"recovery":{"check_in_days":3},"nutrition":{"confirmed_days":4},"next_focus_code":"continue_approved_plan","missing_data":[]}');
insert into public.health_history_months(user_id, month, workouts, strength_workouts, workout_minutes,
  sleep_nights, sleep_minutes_avg, weight_days, weight_kg_avg, data_days) values
  ('a1000000-0000-4000-8000-000000000001', date_trunc('month', current_date - 100)::date, 12, 8, 700, 20,
   420, 4, 84.2, 25);

-- The lookups --------------------------------------------------------------------------------------

create function pg_temp.keys(j jsonb) returns text[] language sql as
  $$ select array(select k from jsonb_object_keys(j) k order by k collate "C") $$;

select is(pg_temp.keys(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, null)),
  array['from', 'lookup', 'schema_version', 'sessions', 'to', 'truncated'], 'workouts: complete key list');
select is(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, null)->>'schema_version', '1.0', 'with a schema version');
select is((public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, null)->'sessions'->0->>'local_date')::date, current_date - 5, 'newest session first');
select is(jsonb_array_length(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, null)->'sessions'), 2, 'both sessions in the range');
select is(jsonb_array_length(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 10, current_date, null)->'sessions'), 1, 'the range limits them');
select is(pg_temp.keys(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, null)->'sessions'->0->'exercises'->0->'sets'->0),
  array['done', 'drop_60s_bpm', 'load_kg', 'peak_bpm', 'reps', 'rir', 'rpe'], 'a set reports these keys');
select is(jsonb_array_length(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, 'fly')->'sessions'), 0, 'a filter keeps only matching sessions');
select is(jsonb_array_length(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, 'BENCH')->'sessions'), 2, 'a filter matches names without case');
select is(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000001', current_date - 2000,
    current_date, null)->>'from', (current_date - 399)::text, 'a range is cut to 400 days');
select is(jsonb_array_length(public.coach_lookup_workouts_v1('a1000000-0000-4000-8000-000000000002',
    current_date - 60, current_date, null)->'sessions'), 0, 'another athlete''s sessions are not read');

select is(pg_temp.keys(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, 'bench')),
  array['from', 'lookup', 'next_targets', 'planned', 'schema_version', 'sessions', 'to', 'truncated'],
  'exercise history: complete key list');
select is((select array_agg(s->>'top_load_kg' order by s->>'local_date')
    from jsonb_array_elements(public.coach_lookup_exercise_history_v1(
      'a1000000-0000-4000-8000-000000000001', current_date - 60, current_date, 'bench')->'sessions') s),
  array['70.00', '75.00'], 'a row per session, oldest first');
select is(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'bench')->'sessions'->1->>'e1rm_kg', '95.0', 'estimated one-rep max (Epley)');
select is(jsonb_array_length(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, 'barbell-bench-press')->'next_targets'), 1,
  'the next target comes with the history');
select is(jsonb_array_length(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, 'bench')->'planned'), 1, 'and the plan''s prescription');
select throws_ok($$select public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, null)$$, '22023', 'exercise filter required', 'the exercise is required');

select is(pg_temp.keys(public.coach_lookup_meals_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 7, current_date, null)),
  array['days', 'from', 'lookup', 'meals', 'rules', 'schema_version', 'target_kcal', 'to', 'truncated'],
  'meals: complete key list');
select is((select count(*) from jsonb_array_elements(public.coach_lookup_meals_v1(
    'a1000000-0000-4000-8000-000000000001', current_date - 7, current_date, null)->'days') d
    where (d->>'complete')::boolean), 2::bigint, 'days carry complete or partial');
select is(jsonb_array_length(public.coach_lookup_meals_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 7, current_date, 'dinner')->'meals'), 2, 'a meal-type filter');

select is(pg_temp.keys(public.coach_lookup_body_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 60, current_date, null)),
  array['from', 'lookup', 'measurements', 'schema_version', 'to', 'truncated', 'weights'], 'body: key list');
select is(public.coach_lookup_body_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, null)->'weights'->0->>'kg', '80.50', 'newest weight first');

select is(pg_temp.keys(public.coach_lookup_check_ins_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 14, current_date, null)),
  array['check_ins', 'from', 'lookup', 'schema_version', 'to', 'truncated'], 'check-ins: key list');
select is(length(public.coach_lookup_check_ins_v1('a1000000-0000-4000-8000-000000000001', current_date - 14,
    current_date, null)->'check_ins'->0->>'note'), 300, 'a note is cut to 300 characters');

select is(pg_temp.keys(public.coach_lookup_recovery_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 14, current_date, null)),
  array['days', 'from', 'lookup', 'schema_version', 'to', 'truncated'], 'recovery: key list');
select is(public.coach_lookup_recovery_v1('a1000000-0000-4000-8000-000000000001', current_date - 14,
    current_date, null)->'days'->0->>'sleep_minutes', '410', 'sleep from the watch summary');

select is(pg_temp.keys(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 90, current_date, null)),
  array['from', 'lookup', 'nutrition', 'schema_version', 'to', 'training', 'truncated'], 'plan history: key list');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 90,
    current_date, null)->'training'->0->'sessions'->0->>'name', 'Push day', 'a version lists its sessions');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 90,
    current_date, null)->'nutrition'->0->>'rationale', 'Target for the test', 'and the target''s reason');

select is(pg_temp.keys(public.coach_lookup_goals_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 90, current_date, null)),
  array['from', 'goals', 'lookup', 'schema_version', 'screenings', 'to', 'truncated'], 'goals: key list');
select is(public.coach_lookup_goals_v1('a1000000-0000-4000-8000-000000000001', current_date - 90,
    current_date, null)->'goals'->0->'target'->>'weight_kg', '76', 'the target is read from the goal');
select ok(not (public.coach_lookup_goals_v1('a1000000-0000-4000-8000-000000000001', current_date - 90,
    current_date, null)::text like '%86.2%'), 'a stale start weight in the goal details is not returned');

select is(pg_temp.keys(public.coach_lookup_weekly_reviews_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 30, current_date, null)),
  array['from', 'lookup', 'reviews', 'schema_version', 'to', 'truncated'], 'weekly reviews: key list');
select is(public.coach_lookup_weekly_reviews_v1('a1000000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'reviews'->0->>'outcome_code', 'week_observed', 'a review reports its outcome');

select is(pg_temp.keys(public.coach_lookup_health_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 400, current_date, null)),
  array['from', 'lookup', 'months', 'schema_version', 'to', 'truncated'], 'health history: key list');
select is(public.coach_lookup_health_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 400,
    current_date, null)->'months'->0->>'workouts', '12', 'a month reports its workouts');

-- Review fixes: assisted history, the body index, goals truncation ------------------------------

-- An assisted exercise logs machine help as its load: the top set is the least help.
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug) values
  ('a1400000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000001',
   'a1300000-0000-4000-8000-000000000002', 2, 'Assisted pull-up', 3, 6, 10, 90, 'assisted-pull-up');
select pg_temp.log_session(current_date - 3,
  '[{"order":1,"planned":"a1400000-0000-4000-8000-000000000004","slug":"assisted-pull-up","sets":[[8,20,2],[8,15,2],[6,15,1]]}]');
select is(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'assisted')->'sessions'->0->>'top_load_kg', '15.00', 'assisted: the top set is the least help');
select is(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'assisted')->'sessions'->0->>'top_reps', '8', 'with its reps (the best of the sets at that help)');
select is(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'assisted')->'sessions'->0->>'e1rm_kg', null, 'and has no one-rep max');
select is(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'assisted')->'sessions'->0->>'assisted', 'true', 'the row says assisted');
select is(public.coach_lookup_exercise_history_v1('a1000000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'bench')->'sessions'->0->>'assisted', 'false', 'a loaded exercise is not assisted');

-- The body index counts the same readings as the body lookup: an amended reading is replaced by its
-- amendment, and a HealthKit weight counts only on a date with no body measurement.
insert into public.body_measurements(id, user_id, measured_on, source, weight_kg) values
  ('a1c00000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', current_date - 10, 'manual', 79.0);
insert into public.body_measurements(user_id, measured_on, source, weight_kg, amended_from_id) values
  ('a1000000-0000-4000-8000-000000000001', current_date - 10, 'manual', 79.4,
   'a1c00000-0000-4000-8000-000000000001');
insert into public.daily_health_summaries(user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at, weight_kg) values
  ('a1000000-0000-4000-8000-000000000001', current_date - 10, 'UTC', array['weight'], '[]'::jsonb,
   repeat('c', 64), 'partial', now(), now(), 79.1),
  ('a1000000-0000-4000-8000-000000000001', current_date - 20, 'UTC', array['weight'], '[]'::jsonb,
   repeat('d', 64), 'partial', now(), now(), 80.0);
select is(public.get_coach_data_index_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'domains'->'body', jsonb_build_object('first', current_date - 30, 'last', current_date - 2,
    'count', 4), 'body index: dates of manual readings (amendment replaces its original) plus a HealthKit-only date');
select is((select count(*) from jsonb_array_elements(public.coach_lookup_body_v1(
    'a1000000-0000-4000-8000-000000000001', current_date - 60, current_date, null)->'weights') w),
  4::bigint, 'and the body lookup lists the same four readings');
select is((select w->>'kg' from jsonb_array_elements(public.coach_lookup_body_v1(
    'a1000000-0000-4000-8000-000000000001', current_date - 60, current_date, null)->'weights') w
    where w->>'date' = (current_date - 10)::text), '79.40', 'with the amended value, not the original or the watch');

-- A list capped at 10 says so.
insert into public.user_goals(user_id, goal_type, status, details, created_at)
select 'a1000000-0000-4000-8000-000000000001', 'strength', 'superseded', '{}', now() - n * interval '1 minute'
from generate_series(1, 11) n;
select is(public.coach_lookup_goals_v1('a1000000-0000-4000-8000-000000000001', current_date - 90,
    current_date, null)->>'truncated', 'true', 'goals: more than 10 rows set truncated');
select is(jsonb_array_length(public.coach_lookup_goals_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 90, current_date, null)->'goals'), 10, 'and only 10 are shown');
select is(public.coach_lookup_goals_v1('a1000000-0000-4000-8000-000000000002', current_date - 90,
    current_date, null)->>'truncated', 'false', 'a short list is not truncated');

-- A finished session carries its workout's identity, so it can be matched after a plan change.
select is((select array(select k from jsonb_object_keys(public.get_coach_plan_state_v1(
      'a1000000-0000-4000-8000-000000000001', current_date - 5)->'completed_this_week'->0) k
    order by k collate "C")),
  array['local_date', 'name', 'order', 'planned_workout_id', 'weekday'],
  'a finished session reports its workout''s name, day and order');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date - 5)
    ->'completed_this_week'->0->>'name', 'Push day', 'by name');

-- Coach sees the next seven days (migration 20261018190042_coach_schedule.sql). Yesterday's and
-- today's finished sessions are reported whatever the calendar week, with the sets they were
-- planned with.
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date - 4)
    ->'recent_completed'->0->>'name', 'Push day', 'a session finished yesterday is reported');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date - 4)
    ->'recent_completed'->0->'exercises'->0, '{"slug":"barbell-bench-press","sets":3}'::jsonb,
  'with its exercises and planned sets');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date - 5)
    ->'recent_completed'->0->>'local_date', (current_date - 5)::text, 'and one finished today');
select is(jsonb_array_length(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001',
    current_date)->'recent_completed'), 0, 'nothing finished yesterday or today is an empty list');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000002', current_date)
    ->'recent_completed', '[]'::jsonb, 'an athlete without a plan has none');

-- The index says which weekdays the plan covers and from when.
select is(public.get_coach_data_index_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->>'schema_version', '1.1', 'the index has a schema version');
select is(public.get_coach_data_index_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'schedule'->>'starts_on', (current_date - 60)::text, 'the schedule starts when the plan took effect');
select is(public.get_coach_data_index_v1('a1000000-0000-4000-8000-000000000001', current_date)
    ->'schedule'->'weekdays', (select jsonb_agg(d order by d) from unnest(array[
      extract(isodow from current_date)::integer,
      (extract(isodow from current_date)::integer % 7) + 1]) d), 'on the weekdays of its sessions');
select is(public.get_coach_data_index_v1('a1000000-0000-4000-8000-000000000002', current_date)
    ->'schedule', 'null'::jsonb, 'an athlete without a plan has no schedule');

-- The plan laid over a range of dates, past and ahead: the filter "schedule" of plan_history.
select is(pg_temp.keys(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 7, current_date + 7, 'schedule')),
  array['days', 'filter', 'from', 'lookup', 'plan', 'schema_version', 'sessions', 'to', 'today',
    'truncated'], 'schedule: key list');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 7, current_date + 7, ' Schedule ')->>'filter', 'schedule',
  'the filter is read without case or spaces');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 7, current_date + 7, 'schedule')->>'today',
  private.local_date_for('a1000000-0000-4000-8000-000000000001')::text, 'with the athlete''s own today');
select is((select count(*) from jsonb_array_elements(public.coach_lookup_plan_history_v1(
    'a1000000-0000-4000-8000-000000000001', current_date - 7, current_date + 7, 'schedule')->'days') d
    where jsonb_array_length(d->'planned') > 0), 5::bigint,
  'three Push days and two Pull days fall in a range of 15 days, behind and ahead');
select is((select count(*) from jsonb_array_elements(public.coach_lookup_plan_history_v1(
    'a1000000-0000-4000-8000-000000000001', current_date, current_date + 14, 'schedule')->'days') d
    where d->>'date' > current_date::text and jsonb_array_length(d->'planned') = 1), 4::bigint,
  'a range ahead lists the planned sessions of future dates');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 5, current_date - 5, 'schedule')->'days'->0->'done'->0->>'name', 'Push day',
  'a finished session is listed on its date');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 5, current_date - 5, 'schedule')->'days'->0->'done'->0->'exercises'->0->>'slug',
  'barbell-bench-press', 'with the exercises it was planned with');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 90, current_date - 70, 'schedule')->'days', '[]'::jsonb,
  'before the plan took effect and with nothing logged, no day is listed');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000002',
    current_date, current_date + 6, 'schedule')->'days', '[]'::jsonb,
  'an athlete without a plan has no days');
-- The schedule lookup stops 90 days after the athlete's own today, whatever range was asked.
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date, current_date + 400, 'schedule')->>'to',
  (private.local_date_for('a1000000-0000-4000-8000-000000000001') + 90)::text,
  'the range ends 90 days after today');
select is((select count(*) from jsonb_array_elements(public.coach_lookup_plan_history_v1(
    'a1000000-0000-4000-8000-000000000001', current_date, current_date + 400, 'schedule')->'days') d
    where (d->>'date')::date > private.local_date_for('a1000000-0000-4000-8000-000000000001') + 90),
  0::bigint, 'and no day lies beyond it');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date + 200, current_date + 300, 'schedule')->'days', '[]'::jsonb,
  'a range wholly past the horizon lists nothing');

-- A finished session reports the sets the athlete logged, not the sets it was planned with (the
-- plan says 3 sets of bench press; 2 were logged).
select pg_temp.log_session(current_date - 3,
  '[{"order":1,"planned":"a1400000-0000-4000-8000-000000000001","slug":"barbell-bench-press","sets":[[8,75,3],[8,75,3]]}]');
select is(public.get_coach_plan_state_v1('a1000000-0000-4000-8000-000000000001', current_date - 2)
    ->'recent_completed'->0->'exercises'->0, '{"slug":"barbell-bench-press","sets":2}'::jsonb,
  'the logged sets are reported');
select is(public.coach_lookup_plan_history_v1('a1000000-0000-4000-8000-000000000001',
    current_date - 3, current_date - 3, 'schedule')->'days'->0->'done'->0->'exercises'->0,
  '{"slug":"barbell-bench-press","sets":2}'::jsonb, 'and so does the schedule lookup');

-- The private helpers are not callable by the app's roles.
select is(has_function_privilege('anon', 'private.coach_plan_schedule(uuid,date,date)', 'execute'),
  false, 'anon cannot run the schedule helper');
select is(has_function_privilege('authenticated', 'private.coach_plan_schedule(uuid,date,date)',
  'execute'), false, 'nor can an authenticated user');
select is(has_function_privilege('anon', 'private.coach_session_exercises(uuid,uuid)', 'execute'),
  false, 'anon cannot read a session''s exercises through the helper');
select is(has_function_privilege('authenticated', 'private.coach_session_exercises(uuid,uuid)',
  'execute'), false, 'nor can an authenticated user');

-- Dates of records are the athlete's local days, not UTC days: 20:00 UTC on 1 October is already
-- 2 October at UTC+14, so a range of just that local day finds it.
update public.user_accounts set timezone = 'Pacific/Kiritimati'
where id = 'a1000000-0000-4000-8000-000000000002';
select is(private.local_day('a1000000-0000-4000-8000-000000000002', timestamptz '2026-10-01 20:00:00+00'),
  date '2026-10-02', 'local_day uses the account time zone');
select is(private.local_day('a1000000-0000-4000-8000-000000000001', timestamptz '2026-10-01 20:00:00+00'),
  date '2026-10-01', 'and UTC when the account has the default');
insert into public.user_goals(user_id, goal_type, status, details, created_at) values
  ('a1000000-0000-4000-8000-000000000002', 'strength', 'superseded', '{}', timestamptz '2026-10-01 20:00:00+00');
select is(public.coach_lookup_goals_v1('a1000000-0000-4000-8000-000000000002', date '2026-10-02',
    date '2026-10-02', null)->'goals'->0->>'created_on', '2026-10-02',
  'a goal created at 20:00 UTC is found on the athlete''s next local day');
select is(jsonb_array_length(public.coach_lookup_goals_v1('a1000000-0000-4000-8000-000000000002',
    date '2026-10-01', date '2026-10-01', null)->'goals'), 0, 'and not on the UTC day');

-- Access --------------------------------------------------------------------------------------------

select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (p.proname like 'coach\_lookup\_%\_v1'
      or p.proname in ('get_coach_plan_state_v1', 'get_coach_nutrition_state_v1', 'get_coach_data_index_v1'))),
  14::bigint, 'fourteen functions: eleven lookups (past_messages is A10 part 2) and three baseline reads');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (p.proname like 'coach\_lookup\_%\_v1'
      or p.proname in ('get_coach_plan_state_v1', 'get_coach_nutrition_state_v1', 'get_coach_data_index_v1'))
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
      and p.prosecdef), 14::bigint, 'each is SECURITY DEFINER and only the service role calls it');
select ok(not has_function_privilege('authenticated',
    'private.nutrition_day_totals(uuid, date, date)', 'execute'), 'the day totals are private');

-- The turn trace --------------------------------------------------------------------------------------

insert into public.coach_threads(id, user_id, title, status) values
  ('a1a00000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'Chat', 'active');
insert into public.coach_messages(id, user_id, thread_id, role, content) values
  ('a1b00000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001',
   'a1a00000-0000-4000-8000-000000000001', 'assistant', 'A reply');
select lives_ok($$update public.coach_messages set guard_faults = array['rule:numbers_not_grounded:2',
    'fallback:provider_response_invalid'], lookups = array['exercise_history:14']
    where id = 'a1b00000-0000-4000-8000-000000000001'$$, 'rule names, a fallback code and lookup counts store');
select throws_ok($$update public.coach_messages set guard_faults = array['Not a rule name!']
    where id = 'a1b00000-0000-4000-8000-000000000001'$$, '23514', null,
  'content-like text cannot be stored in the trace');
select throws_ok($$update public.coach_messages set lookups = array(select 'x' || n from generate_series(1, 13) n)
    where id = 'a1b00000-0000-4000-8000-000000000001'$$, '23514', null, 'the trace is bounded');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
select is((select count(*) from public.coach_messages where guard_faults is not null), 0::bigint,
  'another athlete cannot read the trace');
select throws_ok($$update public.coach_messages set guard_faults = array['x']$$, '42501', null,
  'and nobody writes it from the app');
reset role;

select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'coach_lookup_physique_v1'),
  'there is no physique lookup: that data reaches the Coach provider only under an accepted notice');

select * from finish();
rollback;
