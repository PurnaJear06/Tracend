begin;
select no_plan();

-- B4-1: the same-day readiness adjustment. Real athletes with a plan, a check-in, sleep and a recovery
-- score; the answers; the staleness rule; the safety day; start_workout; B3 reading an adjusted
-- session; privacy. The pure rules are swept in readiness_sweep_test.sql.

insert into auth.users(id, role) values
  ('b4000000-0000-4000-8000-000000000001', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000002', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000003', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000004', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000005', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000006', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000007', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000008', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000009', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000010', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000011', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000012', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000013', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000014', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000015', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000016', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000017', 'authenticated'),
  ('b4000000-0000-4000-8000-000000000018', 'authenticated');

create temporary table t as
  select private.local_date_for('b4000000-0000-4000-8000-000000000001') as today;
grant select on t to authenticated;
create temporary table r(name text, j jsonb);
grant all on r to authenticated;
create temporary table wk(uid uuid primary key, version_id uuid, workout_id uuid,
  e1 uuid, e2 uuid, e3 uuid);
grant select on wk to authenticated;

-- An athlete with one workout today (or shifted by days): bench 4 x 5-8 at RPE 8, fly 3 x 10-12
-- at RPE 8, curl 2 x 8-12 with no RPE.
create function pg_temp.make_athlete(p_uid uuid, p_shift integer default 0)
returns void language plpgsql as $$
declare
  pl uuid := gen_random_uuid(); v uuid := gen_random_uuid(); w uuid := gen_random_uuid();
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  wd integer := ((extract(isodow from private.local_date_for(p_uid))::integer - 1 + p_shift) % 7) + 1;
begin
  insert into public.training_plans(id, user_id, title, source) values (pl, p_uid, 'Strength', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, p_uid, pl, 1, 'active', 6, 1, '{}', 'Approved', now(), current_date);
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (w, p_uid, v, 1, 'Lower A', 'Press', wd, 50, 'Warm up', 'Cool down');
  insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
    display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
  values (a, p_uid, w, 1, 'Barbell bench press', 4, 5, 8, 8, 120, 'barbell-bench-press'),
    (b, p_uid, w, 2, 'Cable fly', 3, 10, 12, 8, 60, null),
    (c, p_uid, w, 3, 'Dumbbell curl', 2, 8, 12, null, 60, 'dumbbell-curl');
  insert into wk values (p_uid, v, w, a, b, c);
end $$;

-- A completed session a week ago: bench 4 x 8 at 60 kg with three reps left (B3: add a step, so
-- 62.5 kg x 5) and fly 3 x 10 at 15 kg without reps in reserve (B3: one more rep, 11).
create function pg_temp.seed_history(p_uid uuid) returns void language plpgsql as $$
declare sid uuid := gen_random_uuid(); pid uuid; d date := private.local_date_for(p_uid) - 7;
begin
  insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  select sid, p_uid, k.version_id, k.workout_id, d, 'UTC', 'completed', gen_random_uuid(),
    now() - interval '7 days', 3000, 8, 'athlete', 'manual' from wk k where k.uid = p_uid;
  insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
    exercise_order, status, performance_kind)
  select p_uid, sid, k.e1, 1, 'performed', 'prescribed' from wk k where k.uid = p_uid
  returning id into pid;
  insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
    rir, completed)
  select p_uid, pid, n, 8, 60, 3, true from generate_series(1, 4) n;
  insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
    exercise_order, status, performance_kind)
  select p_uid, sid, k.e2, 2, 'performed', 'prescribed' from wk k where k.uid = p_uid
  returning id into pid;
  insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
    completed)
  select p_uid, pid, n, 10, 15, true from generate_series(1, 3) n;
end $$;

-- The current check-in for today (the earlier one is superseded).
create function pg_temp.check_in(p_uid uuid, p_sleep integer, p_energy integer, p_sore integer,
  p_mood integer, p_pain integer, p_available boolean default true) returns void language plpgsql as $$
declare d date := private.local_date_for(p_uid); rev integer;
begin
  select coalesce(max(revision), 0) + 1 into rev from public.daily_check_ins
  where user_id = p_uid and local_date = d;
  update public.daily_check_ins set superseded_at = now()
  where user_id = p_uid and local_date = d and superseded_at is null;
  insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key,
    sleep_quality, energy, soreness, hunger, mood, pain_severity, available_to_train)
  values (p_uid, d, 'UTC', rev, gen_random_uuid(), p_sleep, p_energy, p_sore, 3, p_mood, p_pain,
    p_available);
end $$;

-- Today's stored recovery score (null: scored but no score).
create function pg_temp.metrics(p_uid uuid, p_score integer, p_confidence text,
  p_mode text default 'night') returns void language plpgsql as $$
declare d date := private.local_date_for(p_uid);
begin
  delete from public.daily_computed_metrics where user_id = p_uid and local_date = d;
  insert into public.daily_computed_metrics(user_id, local_date, recovery_score, data_confidence,
    scores_jsonb)
  values (p_uid, d, p_score, p_confidence, jsonb_build_object('recovery_mode', p_mode));
end $$;

-- Last night's sleep minutes (null removes the day's summary).
create function pg_temp.sleep(p_uid uuid, p_minutes integer) returns void language plpgsql as $$
declare d date := private.local_date_for(p_uid);
begin
  delete from public.daily_health_summaries where user_id = p_uid and local_date = d;
  if p_minutes is not null then
    insert into public.daily_health_summaries(user_id, local_date, timezone, present_types,
      source_refs, source_checksum, completeness, observed_through, sleep_minutes)
    values (p_uid, d, 'UTC', array['sleep'], '[]'::jsonb, repeat('a', 64), 'partial', now(),
      p_minutes);
  end if;
end $$;

-- A completed session p_days ago: bench 4 x p_reps at 60 kg with one rep left, and optionally the
-- fly 3 x 10 at 15 kg.
create function pg_temp.log_bench(p_uid uuid, p_days integer, p_reps integer, p_fly boolean default false)
returns void language plpgsql as $$
declare sid uuid := gen_random_uuid(); pid uuid; d date := private.local_date_for(p_uid) - p_days;
begin
  insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  select sid, p_uid, k.version_id, k.workout_id, d, 'UTC', 'completed', gen_random_uuid(),
    now() - p_days * interval '1 day', 3000, 8, 'athlete', 'manual' from wk k where k.uid = p_uid;
  insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
    exercise_order, status, performance_kind)
  select p_uid, sid, k.e1, 1, 'performed', 'prescribed' from wk k where k.uid = p_uid
  returning id into pid;
  insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
    rir, completed)
  select p_uid, pid, n, p_reps, 60, 1, true from generate_series(1, 4) n;
  if p_fly then
    insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
      exercise_order, status, performance_kind)
    select p_uid, sid, k.e2, 2, 'performed', 'prescribed' from wk k where k.uid = p_uid
    returning id into pid;
    insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
      completed)
    select p_uid, pid, n, 10, 15, true from generate_series(1, 3) n;
  end if;
end $$;

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid, true);
end $$;

select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000001');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000001');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000001', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000004', 1);
select pg_temp.metrics('b4000000-0000-4000-8000-000000000004', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000005');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000005');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000005', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000006');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000006');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000006', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000007');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000007', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000008');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000008');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000008', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000009');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000009');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000009', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000010');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000010', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000011');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000011');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000011', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000012');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000012');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000012', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000013');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000013');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000013', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000014');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000015');
select pg_temp.log_bench('b4000000-0000-4000-8000-000000000015', 14, 4);
select pg_temp.log_bench('b4000000-0000-4000-8000-000000000015', 7, 4, true);
select pg_temp.metrics('b4000000-0000-4000-8000-000000000015', null, 'low');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000016');
select pg_temp.seed_history('b4000000-0000-4000-8000-000000000016');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000016', 60, 'high');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000017');
select pg_temp.make_athlete('b4000000-0000-4000-8000-000000000018');

-- Shape and privileges ----------------------------------------------------------------------------

select has_table('public', 'day_adjustments', 'the answers table exists');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.day_adjustments'::regclass), 'row-level security is on and forced');
select ok(has_table_privilege('authenticated', 'public.day_adjustments', 'select')
  and not has_table_privilege('authenticated', 'public.day_adjustments', 'insert')
  and not has_table_privilege('authenticated', 'public.day_adjustments', 'update')
  and not has_table_privilege('authenticated', 'public.day_adjustments', 'delete')
  and not has_table_privilege('anon', 'public.day_adjustments', 'select'),
  'athletes read their answers and cannot write them; signed-out callers read nothing');
select ok(has_function_privilege('authenticated', 'public.get_my_day_adjustment_v1(date, boolean)', 'execute')
  and has_function_privilege('authenticated',
    'public.respond_to_day_adjustment_v1(date, boolean, text, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.get_my_day_adjustment_v1(date, boolean)', 'execute')
  and not has_function_privilege('anon',
    'public.respond_to_day_adjustment_v1(date, boolean, text, boolean)', 'execute'),
  'athletes call the two functions; signed-out callers cannot');
select ok((select bool_and(prosecdef and proconfig = array['search_path=""']) from pg_proc
    where oid in ('public.get_my_day_adjustment_v1(date, boolean)'::regprocedure,
      'public.respond_to_day_adjustment_v1(date, boolean, text, boolean)'::regprocedure)),
  'both are security definer with an empty search path');
select ok(not has_function_privilege('authenticated', 'private.readiness_rules()', 'execute')
  and not has_function_privilege('authenticated', 'private.readiness_rank(text, text)', 'execute')
  and not has_function_privilege('authenticated',
    'private.readiness_assessment(boolean, integer, integer, integer, integer, integer, boolean, integer, integer, text, text, boolean, boolean)',
    'execute')
  and not has_function_privilege('authenticated',
    'private.day_adjustment_changes(uuid, uuid, text, jsonb)', 'execute')
  and not has_function_privilege('authenticated',
    'private.day_adjustment_explanation(text, text, text[], text, jsonb, boolean, text)', 'execute')
  and not has_function_privilege('authenticated',
    'private.day_adjustment_compute(uuid, date, boolean)', 'execute')
  and not has_function_privilege('authenticated',
    'private.day_adjustment_stands(public.day_adjustments, jsonb)', 'execute')
  and not has_function_privilege('authenticated',
    'private.day_adjustment_present(public.day_adjustments, jsonb, boolean, jsonb)', 'execute')
  and not has_function_privilege('authenticated',
    'private.day_adjustment_refresh_metrics(uuid, date)', 'execute')
  and not has_table_privilege('authenticated', 'private.day_adjustment_metric_attempts', 'select')
  and not has_table_privilege('anon', 'private.day_adjustment_metric_attempts', 'select'),
  'the rules and helpers are private');
select ok(has_function_privilege('authenticated', 'public.start_workout(uuid, date, text, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.start_workout(uuid, date, text, uuid)', 'execute'),
  'start_workout keeps its grants');

-- Table constraints ---------------------------------------------------------------------------------

select throws_ok($$insert into public.day_adjustments(user_id, local_date, planned_workout_id,
    plan_version_id, rules_version, band, kind, origin, rules_kind, triggers, changes, inputs, inputs_hash, status)
  select uid, current_date, workout_id, version_id, 'readiness-v1', 'amber', 'swap_to_easy_cardio',
    'proposed', 'none', '{}', '[]', '{}', repeat('a', 64), 'accepted'
  from wk where uid = 'b4000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'an easy-cardio answer must carry its cardio object');
select throws_ok($$insert into public.day_adjustments(user_id, local_date, planned_workout_id,
    plan_version_id, rules_version, band, kind, origin, rules_kind, triggers, changes, inputs, inputs_hash, status)
  select uid, current_date, workout_id, version_id, 'readiness-v1', 'amber', 'reduce_sets',
    'proposed', 'none', array['made_up'], '[]', '{}', repeat('a', 64), 'accepted'
  from wk where uid = 'b4000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'a trigger the rules do not know is refused');
select throws_ok($$insert into public.day_adjustments(user_id, local_date, planned_workout_id,
    plan_version_id, rules_version, band, kind, origin, rules_kind, triggers, changes, inputs, inputs_hash, status)
  select uid, current_date, workout_id, version_id, 'readiness-v1', 'amber', 'none',
    'proposed', 'none', '{}', '[]', '{}', repeat('a', 64), 'accepted'
  from wk where uid = 'b4000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'an answer always has a kind');
select throws_ok($$insert into public.day_adjustments(user_id, local_date, planned_workout_id,
    plan_version_id, rules_version, band, kind, origin, rules_kind, triggers, changes, inputs, inputs_hash, status)
  select uid, current_date, workout_id, version_id, 'readiness-v1', 'amber', 'hold_load',
    'proposed', 'none', '{}', '{}', '{}', repeat('a', 64), 'accepted'
  from wk where uid = 'b4000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'changes is a list');

-- Nothing proposed without a plan or a check-in -------------------------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000003');
insert into r select 'no_plan', public.get_my_day_adjustment_v1((select today from t));
select is((select j ->> 'unavailable_reason' from r where name = 'no_plan'), 'no_plan',
  'an athlete without a plan has nothing to adjust');
select is((select j ->> 'explanation' from r where name = 'no_plan'),
  'You have no active plan to adjust.', 'and the words say so');
select is((select array[j ->> 'kind', j ->> 'status', j ->> 'available'] from r where name = 'no_plan'),
  array['none', 'none', 'false'], 'no kind, no status, not available');
select is((select j -> 'planned_workout_id' from r where name = 'no_plan'), 'null'::jsonb,
  'and no workout');

select pg_temp.as_user('b4000000-0000-4000-8000-000000000001');
insert into r select 'no_check_in', public.get_my_day_adjustment_v1((select today from t));
select is((select array(select k from jsonb_object_keys(j) k order by k collate "C")
    from r where name = 'no_check_in'),
  array['answered_at', 'available', 'band', 'cardio', 'changes', 'confidence', 'exercise_joint_options',
    'explanation', 'joint_states', 'kind', 'local_date', 'missing', 'options', 'origin',
    'planned_workout_id', 'previous_answer', 'rules_version', 'safety_route', 'schema_version',
    'sets_total_from', 'sets_total_to', 'signals', 'status', 'triggers', 'unavailable_reason',
    'workout_name'],
  'the answer has exactly the contract keys: the 1.0 keys and the two B5-1 added');
select is((select j ->> 'schema_version' from r where name = 'no_check_in'), '1.1', 'at schema version 1.1');
select is((select j ->> 'local_date' from r where name = 'no_check_in'), (select today::text from t),
  'for the athlete''s own today');
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'status', j ->> 'available'] from r
    where name = 'no_check_in'),
  array['unknown', 'none', 'none', 'true'], 'without a check-in the band is unknown and nothing is proposed');
select is((select j -> 'triggers' from r where name = 'no_check_in'), '["no_check_in"]'::jsonb,
  'the one trigger is the missing check-in');
select is((select j -> 'confidence' from r where name = 'no_check_in'), 'null'::jsonb,
  'an unknown band has no confidence');
select is((select j -> 'missing' from r where name = 'no_check_in'), '["sleep", "recovery"]'::jsonb,
  'without Apple Health both signals are missing');
select is((select j ->> 'explanation' from r where name = 'no_check_in'),
  'Check in to see if today''s session needs adjusting.', 'the card asks for a check-in');
select is((select array(select o ->> 'kind' from jsonb_array_elements(j -> 'options') o)
    from r where name = 'no_check_in'),
  array['hold_load', 'reduce_sets', 'swap_to_easy_cardio'],
  'the athlete may still choose any adjustment that would change today''s session');
select is((select array[j ->> 'workout_name', j ->> 'sets_total_from', j ->> 'sets_total_to']
    from r where name = 'no_check_in'),
  array['Lower A', '9', '9'], 'with today''s workout and its set total');

-- Only today can be read ------------------------------------------------------------------------------

select throws_ok($$select public.get_my_day_adjustment_v1(private.local_date_for(auth.uid()) - 1)$$,
  '22023', null, 'yesterday is refused');
select throws_ok($$select public.get_my_day_adjustment_v1(private.local_date_for(auth.uid()) + 1)$$,
  '22023', null, 'and so is tomorrow');
select throws_ok($$select public.get_my_day_adjustment_v1(null)$$, '22023', null, 'and no date');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()) + 1, true)$$,
  '22023', null, 'answers are for today only too');
select pg_temp.as_user('');
select throws_ok($$select public.get_my_day_adjustment_v1(current_date)$$, '42501', null,
  'a caller with no identity cannot read');
select throws_ok($$select public.respond_to_day_adjustment_v1(current_date, true)$$, '42501', null,
  'or answer');
select pg_temp.as_user('b4000000-0000-4000-8000-000000000001');

-- The recovery score alone adjusts nothing (D9) -------------------------------------------------------

select pg_temp.metrics('b4000000-0000-4000-8000-000000000001', 20, 'high');
insert into r select 'low_no_check_in', public.get_my_day_adjustment_v1((select today from t));
select is((select j -> 'triggers' from r where name = 'low_no_check_in'),
  '["no_check_in", "recovery_low"]'::jsonb, 'a low recovery without a check-in is reported');
select is((select j ->> 'kind' from r where name = 'low_no_check_in'), 'none',
  'and proposes nothing');
select is((select j ->> 'explanation' from r where name = 'low_no_check_in'),
  'Your recovery reads low. Check in and Tracend will say whether to adjust today.',
  'it asks for a check-in');
select is((select j -> 'signals' from r where name = 'low_no_check_in'),
  '{"recovery_score": 20, "recovery_confidence": "high", "recovery_mode": "night",
    "recovery_low": true, "sleep_minutes": null}'::jsonb,
  'and tells the athlete what the score shows');

-- The contract fixture day_adjustment_v1_0_unknown.json is what this day returns, key for key: schema 1.1
-- only adds keys (joint_states, exercise_joint_options), so every 1.0 value is unchanged.
select is((select j - 'schema_version' - 'joint_states' - 'exercise_joint_options'
    from r where name = 'low_no_check_in'),
  replace(replace(replace(replace(replace($fx${"schema_version": "1.0", "local_date": "2026-10-24", "band": "unknown", "triggers": ["no_check_in", "recovery_low"], "kind": "none", "changes": [], "explanation": "Your recovery reads low. Check in and Tracend will say whether to adjust today.", "status": "none", "available": true, "unavailable_reason": null, "safety_route": null, "confidence": null, "missing": ["sleep"], "cardio": null, "planned_workout_id": "b4200000-0000-4000-8000-000000000001", "workout_name": "Lower A", "sets_total_from": 9, "sets_total_to": 9, "previous_answer": null, "answered_at": null, "rules_version": "readiness-v1", "origin": null, "options": [{"kind": "hold_load", "explanation": "Keep last time's weights instead of adding more.", "sets_total_to": 9, "changes": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "sets_from": 4, "sets_to": 4, "load_note": "Keep last time's 60 kg", "load_kg_from": 62.5, "load_kg_to": 60, "reps_from": 5, "reps_to": 8, "rpe_to": null}, {"exercise_order": 2, "planned_exercise_id": "b4400000-0000-4000-8000-000000000002", "name": "Cable fly", "sets_from": 3, "sets_to": 3, "load_note": null, "load_kg_from": 15, "load_kg_to": 15, "reps_from": 11, "reps_to": 10, "rpe_to": null}], "cardio": null}, {"kind": "reduce_sets", "explanation": "One set fewer on 2 exercises and last time's weights.", "sets_total_to": 7, "changes": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "sets_from": 4, "sets_to": 3, "load_note": "Keep last time's 60 kg", "load_kg_from": 62.5, "load_kg_to": 60, "reps_from": 5, "reps_to": 8, "rpe_to": 7}, {"exercise_order": 2, "planned_exercise_id": "b4400000-0000-4000-8000-000000000002", "name": "Cable fly", "sets_from": 3, "sets_to": 2, "load_note": null, "load_kg_from": 15, "load_kg_to": 15, "reps_from": 11, "reps_to": 10, "rpe_to": 7}], "cardio": null}, {"kind": "swap_to_easy_cardio", "explanation": "Try 20 to 30 minutes of easy walking, cycling or swimming at a pace you can talk through. It keeps you moving without adding strain.", "sets_total_to": 0, "changes": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "sets_from": 4, "sets_to": 0, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": null}, {"exercise_order": 2, "planned_exercise_id": "b4400000-0000-4000-8000-000000000002", "name": "Cable fly", "sets_from": 3, "sets_to": 0, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": null}, {"exercise_order": 3, "planned_exercise_id": "b4400000-0000-4000-8000-000000000003", "name": "Dumbbell curl", "sets_from": 2, "sets_to": 0, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": null}], "cardio": {"minutes_min": 20, "minutes_max": 30, "effort": "easy", "talk_test": true, "vigorous_allowed": false}}], "signals": {"recovery_score": 20, "recovery_confidence": "high", "recovery_mode": "night", "recovery_low": true, "sleep_minutes": null}}$fx$,
    'b4200000-0000-4000-8000-000000000001', (select workout_id::text from wk
      where uid = 'b4000000-0000-4000-8000-000000000001')),
    'b4400000-0000-4000-8000-000000000001', (select e1::text from wk
      where uid = 'b4000000-0000-4000-8000-000000000001')),
    'b4400000-0000-4000-8000-000000000002', (select e2::text from wk
      where uid = 'b4000000-0000-4000-8000-000000000001')),
    'b4400000-0000-4000-8000-000000000003', (select e3::text from wk
      where uid = 'b4000000-0000-4000-8000-000000000001')),
    '2026-10-24', (select today::text from t))::jsonb - 'schema_version',
  'the fixture the app parses is the real answer, key for key');

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 3, 3, 3, 3, 0);
insert into r select 'low_good_check_in', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'status'] from r where name = 'low_good_check_in'),
  array['green', 'none', 'none'], 'a low recovery next to a good check-in stays green and proposes nothing');
select is((select j -> 'triggers' from r where name = 'low_good_check_in'), '["recovery_low"]'::jsonb,
  'the low recovery is still reported');
select is((select j ->> 'explanation' from r where name = 'low_good_check_in'),
  'Your recovery reads low, but your check-in looks fine. You can train as planned or choose a lighter session.',
  'with words that offer the choice');
select is((select array(select o ->> 'explanation' from jsonb_array_elements(j -> 'options') o)
    from r where name = 'no_check_in'),
  array['Keep last time''s weights instead of adding more.',
    'One set fewer on 2 exercises and last time''s weights.',
    'Try 20 to 30 minutes of easy walking, cycling or swimming at a pace you can talk through. It keeps you moving without adding strain.'],
  'the sentence of a choice depends on the kind alone, not on whether the athlete has checked in');
select is((select jsonb_array_length(j -> 'options') from r where name = 'low_good_check_in'), 3,
  'and the three adjustments the athlete may choose');
select is((select j -> 'confidence' from r where name = 'low_good_check_in'), '"medium"'::jsonb,
  'the recovery score alone gives medium confidence');

-- Each source of points -----------------------------------------------------------------------------------

select pg_temp.metrics('b4000000-0000-4000-8000-000000000001', 60, 'high');
select pg_temp.sleep('b4000000-0000-4000-8000-000000000001', 300);
insert into r select 'short_sleep', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind'] from r where name = 'short_sleep'),
  array['amber', 'hold_load'], 'under six hours of sleep is one point: hold the loads');
select is((select j -> 'triggers' from r where name = 'short_sleep'), '["sleep_short"]'::jsonb,
  'for that one reason');
select is((select j -> 'confidence' from r where name = 'short_sleep'), '"high"'::jsonb,
  'with a check-in, sleep and a night recovery at high confidence the result is high confidence');
select is((select j ->> 'explanation' from r where name = 'short_sleep'),
  'You slept under 6 hours. Keep last time''s weights instead of adding more.',
  'the sentence is composed from the trigger and the kind');
select is((select j -> 'changes' from r where name = 'short_sleep'),
  jsonb_build_array(
    jsonb_build_object('exercise_order', 1, 'planned_exercise_id', (select e1 from wk
      where uid = 'b4000000-0000-4000-8000-000000000001'), 'name', 'Barbell bench press',
      'sets_from', 4, 'sets_to', 4, 'load_note', 'Keep last time''s 60 kg', 'load_kg_from', 62.5,
      'load_kg_to', 60, 'reps_from', 5, 'reps_to', 8, 'rpe_to', null),
    jsonb_build_object('exercise_order', 2, 'planned_exercise_id', (select e2 from wk
      where uid = 'b4000000-0000-4000-8000-000000000001'), 'name', 'Cable fly',
      'sets_from', 3, 'sets_to', 3, 'load_note', null, 'load_kg_from', 15,
      'load_kg_to', 15, 'reps_from', 11, 'reps_to', 10, 'rpe_to', null)),
  'holding the load: the bench keeps last time''s 60 kg instead of 62.5, the fly repeats 10 reps '
  'instead of 11, and the curl, with no history, is left alone');
select is((select j ->> 'sets_total_to' from r where name = 'short_sleep'), '9',
  'no set is removed');

select pg_temp.sleep('b4000000-0000-4000-8000-000000000001', 0);
insert into r select 'no_sleep', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', (j -> 'missing')::text] from r where name = 'no_sleep'),
  array['none', '["sleep"]'], 'zero minutes means no sleep was recorded: no trigger, and it is missing');
select pg_temp.sleep('b4000000-0000-4000-8000-000000000001', null);

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 2, 3, 4, 3, 0);
insert into r select 'reduce', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'status'] from r where name = 'reduce'),
  array['amber', 'reduce_sets', 'proposed'], 'poor sleep and soreness are two points: one set fewer');
select is((select j -> 'triggers' from r where name = 'reduce'), '["sleep_poor", "sore"]'::jsonb,
  'for these reasons');
select is((select j ->> 'explanation' from r where name = 'reduce'),
  'You slept poorly and you''re sore. One set fewer on 2 exercises and last time''s weights.',
  'in words');
select is((select array[j ->> 'sets_total_from', j ->> 'sets_total_to'] from r where name = 'reduce'),
  array['9', '7'], 'the bench and the fly lose a set; the two-set curl keeps both');
select is((select jsonb_array_length(j -> 'changes') from r where name = 'reduce'), 2,
  'only exercises that change are listed');
select is((select j -> 'changes' -> 0 from r where name = 'reduce'),
  jsonb_build_object('exercise_order', 1, 'planned_exercise_id', (select e1 from wk
      where uid = 'b4000000-0000-4000-8000-000000000001'), 'name', 'Barbell bench press',
      'sets_from', 4, 'sets_to', 3, 'load_note', 'Keep last time''s 60 kg', 'load_kg_from', 62.5,
      'load_kg_to', 60, 'reps_from', 5, 'reps_to', 8, 'rpe_to', 7),
  'the bench: one set fewer, effort one point lower, last time''s load');
select is((select (j -> 'changes' -> 1 ->> 'rpe_to')::numeric from r where name = 'reduce'), 7.0,
  'and so is the fly');
select is((select j -> 'confidence' from r where name = 'reduce'), '"medium"'::jsonb,
  'a recovery score without sleep is medium confidence');
select is((select j -> 'missing' from r where name = 'reduce'), '["sleep"]'::jsonb,
  'sleep is the missing signal');

select pg_temp.metrics('b4000000-0000-4000-8000-000000000001', 20, 'high');
insert into r select 'reduce_low', public.get_my_day_adjustment_v1((select today from t));
select is((select j -> 'triggers' from r where name = 'reduce_low'),
  '["sleep_poor", "sore", "recovery_low"]'::jsonb,
  'next to a point from the check-in, a low recovery adds its own');
select is((select j ->> 'kind' from r where name = 'reduce_low'), 'reduce_sets', 'three points is still one set fewer');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000001', 20, 'low');
insert into r select 'reduce_low_conf', public.get_my_day_adjustment_v1((select today from t));
select is((select j -> 'triggers' from r where name = 'reduce_low_conf'), '["sleep_poor", "sore"]'::jsonb,
  'a recovery score at low confidence counts for nothing');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000001', 60, 'high');

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 1, 1, 3, 3, 0);
insert into r select 'cardio', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind'] from r where name = 'cardio'),
  array['red', 'swap_to_easy_cardio'], 'four points swap the session for easy cardio');
select is((select j -> 'cardio' from r where name = 'cardio'),
  '{"minutes_min": 20, "minutes_max": 30, "effort": "easy", "talk_test": true, "vigorous_allowed": false}'::jsonb,
  'with a short, easy, talk-test dose');
select is((select array[j ->> 'sets_total_from', j ->> 'sets_total_to'] from r where name = 'cardio'),
  array['9', '0'], 'and no sets');
select is((select j ->> 'explanation' from r where name = 'cardio'),
  'You slept very poorly and your energy is very low. Try 20 to 30 minutes of easy walking, cycling or swimming at a pace you can talk through. It keeps you moving without adding strain.',
  'in words');
select is((select array(select c ->> 'sets_to' from jsonb_array_elements(j -> 'changes') c)
    from r where name = 'cardio'), array['0', '0', '0'], 'every exercise goes to zero sets');

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 3, 3, 3, 3, 2);
insert into r select 'mild_pain', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'explanation'] from r where name = 'mild_pain'),
  array['green', 'none', 'Your check-in looks fine. Train as planned. Keep any pain at 3 or below, and stop if it builds from set to set.'],
  'pain of 1 to 3 is a note, not a point');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 3, 3, 3, 3, 5);
insert into r select 'moderate_pain', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', (j -> 'triggers')::text] from r where name = 'moderate_pain'),
  array['reduce_sets', '["pain_moderate"]'], 'pain of 4 to 6 is two points');

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 1, 3, 3, 3, 0, false);
insert into r select 'cannot_train', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', (j -> 'triggers')::text, j ->> 'explanation']
    from r where name = 'cannot_train'),
  array['amber', 'none', '["not_available", "sleep_very_poor"]',
    'Rest day: you said you can''t train today.'],
  'an athlete who cannot train gets no adjustment');
select is((select jsonb_array_length(j -> 'options') from r where name = 'cannot_train'), 0,
  'and no choices');

-- Pain of 7 or more routes out -------------------------------------------------------------------------

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 3, 3, 3, 3, 8);
insert into r select 'pain', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'status', j ->> 'safety_route'] from r
    where name = 'pain'),
  array['red', 'none', 'none', 'pain_referral'], 'pain of 8 gives no training change and a safety route');
select is((select j -> 'triggers' from r where name = 'pain'), '["pain_severe"]'::jsonb, 'with its reason');
select is((select j -> 'changes' from r where name = 'pain'), '[]'::jsonb, 'no changes');
select is((select j -> 'options' from r where name = 'pain'), '[]'::jsonb, 'and nothing to choose');
select is((select j ->> 'explanation' from r where name = 'pain'),
  'Pain of 7 or more is too high to train through. Rest the area and see a doctor or physio before you train it again.',
  'the words refer the athlete on');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), true)$$,
  '22023', null, 'accepting on a safety day is refused');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), false)$$,
  '22023', null, 'and so is declining');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), true, 'hold_load')$$,
  '22023', null, 'and choosing');

-- Answering: accept, undo, choose ---------------------------------------------------------------------

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 2, 3, 4, 3, 0);
select pg_temp.sleep('b4000000-0000-4000-8000-000000000001', null);
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), true, 'bogus')$$,
  '22023', null, 'a kind that is not offered is refused');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), null)$$,
  '22023', null, 'and so is a missing answer');

insert into r select 'accepted', public.respond_to_day_adjustment_v1((select today from t), true);
select is((select array[j ->> 'status', j ->> 'kind', j ->> 'origin'] from r where name = 'accepted'),
  array['accepted', 'reduce_sets', 'proposed'], 'one tap accepts the kind the rules proposed');
select is((select array[j ->> 'sets_total_from', j ->> 'sets_total_to'] from r where name = 'accepted'),
  array['9', '7'], 'the accepted session has 7 of 9 sets');
select ok((select (j ->> 'answered_at') is not null from r where name = 'accepted'), 'with the time of the answer');
select is((select count(*) from public.day_adjustments
    where user_id = 'b4000000-0000-4000-8000-000000000001'), 1::bigint, 'one answer is stored');
select is((select array[kind, status, origin, band, rules_version, (triggers)::text]
    from public.day_adjustments where user_id = 'b4000000-0000-4000-8000-000000000001'),
  array['reduce_sets', 'accepted', 'proposed', 'amber', 'readiness-v1', '{sleep_poor,sore}'],
  'with the kind, the band and the reasons');
select is((select inputs - 'check_in_id' - 'check_in_revision' from public.day_adjustments
    where user_id = 'b4000000-0000-4000-8000-000000000001'),
  '{"screening": "cleared", "sleep_minutes": null, "recovery_mode": "night", "recovery_score": 60,
    "data_confidence": "high", "joint_states": []}'::jsonb,
  'and the values the rules read');
select is((select a.inputs ->> 'check_in_id' from public.day_adjustments a
    where a.user_id = 'b4000000-0000-4000-8000-000000000001'),
  (select c.id::text from public.daily_check_ins c
    where c.user_id = 'b4000000-0000-4000-8000-000000000001' and c.superseded_at is null),
  'including the check-in they read');
select is((select inputs_hash from public.day_adjustments
    where user_id = 'b4000000-0000-4000-8000-000000000001'),
  (select encode(sha256(convert_to(inputs::text, 'UTF8')), 'hex') from public.day_adjustments
    where user_id = 'b4000000-0000-4000-8000-000000000001'), 'hashed');
select is((select metadata from public.audit_events
    where user_id = 'b4000000-0000-4000-8000-000000000001' and action_code = 'day_adjustment_answered'),
  '{"kind": "reduce_sets", "band": "amber", "origin": "proposed", "accepted": true,
    "rules_version": "readiness-v1"}'::jsonb,
  'the audit event carries codes and no check-in values');

insert into r select 'read_back', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'status', j ->> 'kind', j ->> 'origin', j ->> 'sets_total_to']
    from r where name = 'read_back'), array['accepted', 'reduce_sets', 'proposed', '7'],
  'reading again shows the stored answer');
select is((select j ->> 'explanation' from r where name = 'read_back'),
  'You slept poorly and you''re sore. One set fewer on 2 exercises and last time''s weights.',
  'in the same words');

insert into r select 'again', public.respond_to_day_adjustment_v1((select today from t), true);
select is((select count(*) from public.day_adjustments
    where user_id = 'b4000000-0000-4000-8000-000000000001'), 1::bigint,
  'accepting again is not a new answer');
select is((select count(*) from public.audit_events
    where user_id = 'b4000000-0000-4000-8000-000000000001' and action_code = 'day_adjustment_answered'),
  1::bigint, 'and is not audited again');

insert into r select 'declined', public.respond_to_day_adjustment_v1((select today from t), false);
select is((select array[j ->> 'status', j ->> 'kind'] from r where name = 'declined'),
  array['declined', 'reduce_sets'], 'Undo declines the accepted answer');
select is((select array[count(*)::text, count(*) filter (where superseded_at is null)::text]
    from public.day_adjustments where user_id = 'b4000000-0000-4000-8000-000000000001'),
  array['2', '1'], 'the first answer is kept and superseded');

insert into r select 'chosen', public.respond_to_day_adjustment_v1((select today from t), true, 'hold_load');
select is((select array[j ->> 'status', j ->> 'kind', j ->> 'origin'] from r where name = 'chosen'),
  array['accepted', 'hold_load', 'chosen'], 'the athlete may choose another kind themselves');
select is((select j ->> 'explanation' from r where name = 'chosen'),
  'Keep last time''s weights instead of adding more.', 'with words for the choice');
select is((select jsonb_array_length(j -> 'changes') from r where name = 'chosen'), 2,
  'and the changes of that kind');
insert into r select 'chosen_undo', public.respond_to_day_adjustment_v1((select today from t), false);
select is((select array[j ->> 'status', j ->> 'kind'] from r where name = 'chosen_undo'),
  array['declined', 'hold_load'], 'Undo works on a chosen answer');
insert into r select 'chosen_swap', public.respond_to_day_adjustment_v1((select today from t), true,
  'swap_to_easy_cardio');
select is((select array[j ->> 'kind', j ->> 'sets_total_to', (j -> 'cardio' ->> 'minutes_max')]
    from r where name = 'chosen_swap'), array['swap_to_easy_cardio', '0', '30'],
  'easy cardio can be chosen, with its cardio dose');
insert into r select 'back_to_proposed', public.respond_to_day_adjustment_v1((select today from t), true);
select is((select array[j ->> 'kind', j ->> 'origin'] from r where name = 'back_to_proposed'),
  array['reduce_sets', 'proposed'], 'and the proposed kind can be taken again');

-- A worse check-in asks again; a better one does not undo the answer ------------------------------------

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 1, 1, 3, 3, 0);
insert into r select 'worse', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'status', j ->> 'kind'] from r where name = 'worse'),
  array['proposed', 'swap_to_easy_cardio'], 'a worse check-in proposes the stricter kind again');
select is((select (j -> 'previous_answer') - 'answered_at' from r where name = 'worse'),
  '{"kind": "reduce_sets", "status": "accepted", "reason": "check_in"}'::jsonb,
  'and names the answer it replaces and why');

select pg_temp.check_in('b4000000-0000-4000-8000-000000000001', 3, 3, 3, 3, 0);
insert into r select 'better', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'status', j ->> 'kind', j ->> 'band'] from r where name = 'better'),
  array['accepted', 'reduce_sets', 'green'],
  'a better check-in leaves the answer standing, with today''s band');

-- Starting the workout ---------------------------------------------------------------------------------

select is((select count(*) from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id
    join public.workout_sessions w on w.id = p.workout_session_id
    where w.user_id = 'b4000000-0000-4000-8000-000000000001' and w.state = 'in_progress'),
  0::bigint, 'nothing is started yet');
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000001'),
  (select today from t), 'UTC', 'b4100000-0000-4000-8000-000000000001');
select is((select array_agg(c order by o) from (
    select p.exercise_order o, count(s.id) c from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    left join public.exercise_sets s on s.exercise_performance_id = p.id
    where w.idempotency_key = 'b4100000-0000-4000-8000-000000000001' group by p.exercise_order) x),
  array[3::bigint, 2, 2], 'the session is built with the adjusted set counts');
select ok((select w.day_adjustment_id = a.id from public.workout_sessions w, public.day_adjustments a
    where w.idempotency_key = 'b4100000-0000-4000-8000-000000000001' and a.superseded_at is null
      and a.user_id = w.user_id), 'and remembers the answer it was started under');
insert into r select 'started', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'available', j ->> 'unavailable_reason', j ->> 'status', j ->> 'kind']
    from r where name = 'started'), array['false', 'session_started', 'accepted', 'reduce_sets'],
  'once started the answer is shown but cannot change');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), false)$$,
  '55000', null, 'a started session cannot be answered');

-- A session done under the answer never lowers a load (B3) ----------------------------------------------

update public.exercise_sets s set repetitions = 8, load_kg = 60, rir = 3, completed = true
from public.exercise_performances p, public.workout_sessions w
where s.exercise_performance_id = p.id and p.workout_session_id = w.id
  and w.idempotency_key = 'b4100000-0000-4000-8000-000000000001' and p.exercise_order = 1;
update public.workout_sessions set state = 'completed', completed_at = now(), duration_seconds = 3000,
  session_effort = 7, session_effort_source = 'athlete', completion_source = 'manual'
where idempotency_key = 'b4100000-0000-4000-8000-000000000001';
select is((select tg ->> 'action' from jsonb_array_elements(
    private.next_session_targets('b4000000-0000-4000-8000-000000000001')) tg
    where tg ->> 'name' = 'Barbell bench press'), 'add_load',
  'three good sets of an adjusted three-set session are a complete session: the load goes up');
select is((select (tg -> 'basis' -> 'recent' -> 0) - 'local_date' from jsonb_array_elements(
    private.next_session_targets('b4000000-0000-4000-8000-000000000001')) tg
    where tg ->> 'name' = 'Barbell bench press'),
  '{"pain": false, "sets": 3, "load_kg": 60, "min_rir": 3, "min_reps": 8, "adjusted": true,
    "total_reps": 24, "effort_known": true, "sets_planned": 3}'::jsonb,
  'the session is marked adjusted with its planned set count');
select is((select tg ->> 'action' from jsonb_array_elements(
    private.next_session_targets('b4000000-0000-4000-8000-000000000001')) tg
    where tg ->> 'name' = 'Cable fly'), 'add_reps',
  'the fly, logged in the earlier session, is unchanged');
insert into r select 'done', public.get_my_day_adjustment_v1((select today from t));
select is((select j ->> 'unavailable_reason' from r where name = 'done'), 'session_done',
  'a finished session is done');

-- Easy cardio and held loads link the session; the plan''s sets stand -------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000006');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000006', 2, 3, 3, 3, 0);
select pg_temp.check_in('b4000000-0000-4000-8000-000000000006', 1, 1, 3, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), true, 'hold_load');
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000006'),
  (select today from t), 'UTC', 'b4100000-0000-4000-8000-000000000006');
select is((select array_agg(c order by o) from (
    select p.exercise_order o, count(s.id) c from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    left join public.exercise_sets s on s.exercise_performance_id = p.id
    where w.idempotency_key = 'b4100000-0000-4000-8000-000000000006' group by p.exercise_order) x),
  array[4::bigint, 3, 2], 'holding loads keeps the plan''s sets');
select ok((select day_adjustment_id is not null from public.workout_sessions
    where idempotency_key = 'b4100000-0000-4000-8000-000000000006'), 'and links the answer');

select pg_temp.as_user('b4000000-0000-4000-8000-000000000007');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000007', 1, 1, 3, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), true);
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000007'),
  (select today from t), 'UTC', 'b4100000-0000-4000-8000-000000000007');
select is((select array_agg(c order by o) from (
    select p.exercise_order o, count(s.id) c from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    left join public.exercise_sets s on s.exercise_performance_id = p.id
    where w.idempotency_key = 'b4100000-0000-4000-8000-000000000007' group by p.exercise_order) x),
  array[4::bigint, 3, 2], 'starting the strength workout on an easy-cardio day is allowed: the plan''s sets');
select ok((select day_adjustment_id is not null from public.workout_sessions
    where idempotency_key = 'b4100000-0000-4000-8000-000000000007'), 'with the answer linked');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000007', 3, 3, 3, 3, 9);
insert into r select 'safety_started', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', j ->> 'unavailable_reason', j ->> 'kind', j ->> 'status',
    j ->> 'explanation', jsonb_array_length(j -> 'options')::text, j ->> 'band'] from r
    where name = 'safety_started'),
  array['pain_referral', 'session_started', 'none', 'none',
    'Pain of 7 or more is too high to train through. Rest the area and see a doctor or physio before you train it again.',
    '0', 'red'],
  'pain of 9 after the session started carries the referral and none of the stored answer');
select is((select j - 'local_date' - 'planned_workout_id' - 'signals' - 'sets_total_from'
    - 'sets_total_to' - 'workout_name' - 'confidence' - 'missing' - 'schema_version' - 'joint_states'
    - 'exercise_joint_options' from r where name = 'safety_started'),
  ($fx${   "schema_version": "1.0",   "local_date": "2026-10-24",   "band": "red",   "triggers": [     "pain_severe"   ],   "kind": "none",   "changes": [],   "explanation": "Pain of 7 or more is too high to train through. Rest the area and see a doctor or physio before you train it again.",   "status": "none",   "available": false,   "unavailable_reason": "session_started",   "safety_route": "pain_referral",   "confidence": "medium",   "missing": [     "sleep"   ],   "cardio": null,   "planned_workout_id": "b4200000-0000-4000-8000-000000000001",   "workout_name": "Lower A",   "sets_total_from": 9,   "sets_total_to": 9,   "previous_answer": null,   "answered_at": null,   "rules_version": "readiness-v1",   "origin": null,   "options": [],   "signals": {     "recovery_score": 60,     "recovery_confidence": "high",     "recovery_mode": "night",     "recovery_low": false,     "sleep_minutes": null   } }$fx$::jsonb - 'local_date' - 'planned_workout_id' - 'signals' - 'sets_total_from'
    - 'sets_total_to' - 'workout_name' - 'confidence' - 'missing' - 'schema_version'),
  'the contract fixture day_adjustment_v1_0_safety_started.json is the real answer, key for key');

select pg_temp.as_user('b4000000-0000-4000-8000-000000000008');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000008', 2, 3, 4, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), false);
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000008'),
  (select today from t), 'UTC', 'b4100000-0000-4000-8000-000000000008');
select is((select array_agg(c order by o) from (
    select p.exercise_order o, count(s.id) c from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    left join public.exercise_sets s on s.exercise_performance_id = p.id
    where w.idempotency_key = 'b4100000-0000-4000-8000-000000000008' group by p.exercise_order) x),
  array[4::bigint, 3, 2], 'a declined answer changes nothing');
select ok((select day_adjustment_id is null from public.workout_sessions
    where idempotency_key = 'b4100000-0000-4000-8000-000000000008'), 'and is not linked');

select pg_temp.as_user('b4000000-0000-4000-8000-000000000009');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000009', 2, 3, 4, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), true);
select pg_temp.check_in('b4000000-0000-4000-8000-000000000009', 3, 3, 3, 3, 9);
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000009'),
  (select today from t), 'UTC', 'b4100000-0000-4000-8000-000000000009');
select is((select array_agg(c order by o) from (
    select p.exercise_order o, count(s.id) c from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    left join public.exercise_sets s on s.exercise_performance_id = p.id
    where w.idempotency_key = 'b4100000-0000-4000-8000-000000000009' group by p.exercise_order) x),
  array[3::bigint, 2, 2],
  'an accepted answer is applied as given, even when the check-in has worsened since (pain of 9)');
select ok((select day_adjustment_id is not null from public.workout_sessions
    where idempotency_key = 'b4100000-0000-4000-8000-000000000009'), 'and linked');

-- Rest day, coach-adjusted day, safety on a rest day -------------------------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000004');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000004', 1, 1, 3, 3, 0);
insert into r select 'rest', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'available', j ->> 'unavailable_reason', j ->> 'kind', j ->> 'band']
    from r where name = 'rest'), array['false', 'rest_day', 'none', 'red'],
  'a rest day has nothing to adjust');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), true)$$,
  '55000', null, 'and cannot be answered');
select is((select j ->> 'explanation' from r where name = 'rest'),
  'No session is planned today. Nothing in your plan changes.',
  'and says so, rather than asking for a check-in');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000004', 3, 3, 3, 3, 9);
insert into r select 'rest_pain', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'unavailable_reason', j ->> 'safety_route'] from r where name = 'rest_pain'),
  array['rest_day', 'pain_referral'], 'pain of 9 routes out even on a rest day');

select pg_temp.as_user('b4000000-0000-4000-8000-000000000010');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000010', 1, 1, 3, 3, 0);
update public.training_plan_versions set block_kind = 'next_session',
  ends_on = (select today from t), restores_version_id = id
where user_id = 'b4000000-0000-4000-8000-000000000010';
insert into r select 'coach', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'unavailable_reason', j ->> 'kind', j ->> 'explanation'] from r where name = 'coach'),
  array['coach_adjusted', 'none', 'Coach already adjusted today''s session.'],
  'a session Coach already adjusted for today is not adjusted twice');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), true)$$,
  '55000', null, 'and cannot be answered');

-- At most 20 answers a day --------------------------------------------------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000005');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000005', 3, 3, 3, 3, 0);
select is((select count(x.answer) from (select public.respond_to_day_adjustment_v1(
      (select today from t), i % 2 = 1, 'hold_load') as answer from generate_series(1, 19) i) x),
  19::bigint, 'nineteen answers are taken');
select public.respond_to_day_adjustment_v1((select today from t), true, 'reduce_sets');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), true, 'hold_load')$$,
  'P0001', null, 'the twenty-first is refused');
select is((select j ->> 'status' from (select public.respond_to_day_adjustment_v1(
      private.local_date_for(auth.uid()), false) j) x), 'declined',
  'but Undo of the standing accepted answer is never refused');
select is((select count(*) from public.day_adjustments where user_id = 'b4000000-0000-4000-8000-000000000005'),
  21::bigint, 'it is the twenty-first row');

-- The accepted answer is applied as given, after a worse check-in (P1) ------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000011');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000011', 2, 3, 4, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), true);
select pg_temp.check_in('b4000000-0000-4000-8000-000000000011', 1, 1, 3, 3, 0);
insert into r select 'worse11', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'status', j ->> 'kind'] from r where name = 'worse11'),
  array['proposed', 'swap_to_easy_cardio'], 'the worse check-in asks again');
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000011'),
  (select today from t), 'UTC', 'b4100000-0000-4000-8000-000000000011');
select is((select array_agg(c order by o) from (
    select p.exercise_order o, count(s.id) c from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    left join public.exercise_sets s on s.exercise_performance_id = p.id
    where w.idempotency_key = 'b4100000-0000-4000-8000-000000000011' group by p.exercise_order) x),
  array[3::bigint, 2, 2], 'but starting still gives the lighter session the athlete accepted');
select ok((select day_adjustment_id is not null from public.workout_sessions
    where idempotency_key = 'b4100000-0000-4000-8000-000000000011'), 'linked to it');

-- A start for another date gets the plan as written (P2) --------------------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000012');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000012', 2, 3, 4, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), true);
-- An accepted answer left on the same weekday two weeks ago, as a stale row would be.
insert into public.day_adjustments(user_id, local_date, planned_workout_id, plan_version_id,
  rules_version, band, kind, origin, rules_kind, triggers, changes, cardio, inputs, inputs_hash, status)
select user_id, local_date - 14, planned_workout_id, plan_version_id, rules_version, band, kind, origin,
  rules_kind, triggers, changes, cardio, inputs, inputs_hash, status from public.day_adjustments
where user_id = 'b4000000-0000-4000-8000-000000000012' and superseded_at is null;
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000012'),
  (select today - 14 from t), 'UTC', 'b4100000-0000-4000-8000-000000000012');
select is((select array_agg(c order by o) from (
    select p.exercise_order o, count(s.id) c from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    left join public.exercise_sets s on s.exercise_performance_id = p.id
    where w.idempotency_key = 'b4100000-0000-4000-8000-000000000012' group by p.exercise_order) x),
  array[4::bigint, 3, 2], 'a start backdated to a day that has an accepted answer gets the plan as written');
select ok((select day_adjustment_id is null from public.workout_sessions
    where idempotency_key = 'b4100000-0000-4000-8000-000000000012'), 'and is not linked to today''s answer');

-- A choice made with no check-in speaks for its kind (O1) ------------------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000013');
insert into r select 'before13', public.get_my_day_adjustment_v1((select today from t));
insert into r select 'chose13', public.respond_to_day_adjustment_v1((select today from t), true, 'hold_load');
select is((select array[j ->> 'band', j ->> 'status', j ->> 'kind', j ->> 'origin', j ->> 'explanation']
    from r where name = 'chose13'),
  array['unknown', 'accepted', 'hold_load', 'chosen', 'Keep last time''s weights instead of adding more.'],
  'it keeps today''s band (unknown) and the sentence of the kind');
select is((select j -> 'triggers' from r where name = 'chose13'), '["no_check_in"]'::jsonb,
  'and today''s reasons');
insert into r select 'read13', public.get_my_day_adjustment_v1((select today from t));
select is((select j ->> 'explanation' from r where name = 'read13'),
  'Keep last time''s weights instead of adding more.', 'reading it back gives the same words');

-- Respond and start take the same lock (P1) -------------------------------------------------------------

select ok((select prosrc like '%pg_advisory_xact_lock(hashtextextended(%day_adjustment:%auth.uid()%'
    from pg_proc where oid = 'public.start_workout(uuid, date, text, uuid)'::regprocedure)
  and (select prosrc like '%pg_advisory_xact_lock(hashtextextended(''day_adjustment:'' || uid::text || today::text, 0))%'
    from pg_proc where oid = 'public.respond_to_day_adjustment_v1(date, boolean, text, boolean)'::regprocedure),
  'both functions take the user-and-day advisory lock');
select pg_temp.as_user('b4000000-0000-4000-8000-000000000014');
select ok(not exists (select 1 from pg_locks where locktype = 'advisory' and pid = pg_backend_pid()
    and ((classid::bigint << 32) | objid::bigint) = hashtextextended(
      'day_adjustment:' || 'b4000000-0000-4000-8000-000000000014' || (select today::text from t), 0)),
  'the lock is not held before the start');
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000014'),
  (select today from t), 'UTC', 'b4100000-0000-4000-8000-000000000014');
select ok(exists (select 1 from pg_locks where locktype = 'advisory' and pid = pg_backend_pid()
    and ((classid::bigint << 32) | objid::bigint) = hashtextextended(
      'day_adjustment:' || 'b4000000-0000-4000-8000-000000000014' || (select today::text from t), 0)),
  'starting a workout takes the athlete''s lock for the day');

-- An exercise the answer left alone is judged as ever (P2) -------------------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000015');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000015', 2, 3, 3, 3, 0);
insert into r select 'p15', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', (j -> 'changes' -> 0 ->> 'name'), jsonb_array_length(j -> 'changes')::text]
    from r where name = 'p15'), array['hold_load', 'Cable fly', '1'],
  'only the fly is held: the bench has failed twice and B3 is lowering it');
select public.respond_to_day_adjustment_v1((select today from t), true);
select public.start_workout((select workout_id from wk where uid = 'b4000000-0000-4000-8000-000000000015'),
  (select today from t), 'UTC', 'b4100000-0000-4000-8000-000000000015');
update public.exercise_sets s set repetitions = case p.exercise_order when 1 then 4 else 10 end,
  load_kg = case p.exercise_order when 1 then 60 else 15 end, rir = 1, completed = true
from public.exercise_performances p, public.workout_sessions w
where s.exercise_performance_id = p.id and p.workout_session_id = w.id
  and w.idempotency_key = 'b4100000-0000-4000-8000-000000000015' and p.exercise_order in (1, 2);
update public.workout_sessions set state = 'completed', completed_at = now(), duration_seconds = 3000,
  session_effort = 8, session_effort_source = 'athlete', completion_source = 'manual'
where idempotency_key = 'b4100000-0000-4000-8000-000000000015';
select is((select tg ->> 'action' from jsonb_array_elements(
    private.next_session_targets('b4000000-0000-4000-8000-000000000015')) tg
    where tg ->> 'name' = 'Barbell bench press'), 'lower',
  'the bench, not in the answer, still lowers after a second session below the range');
select is((select array[(tg -> 'basis' -> 'recent' -> 0 ->> 'adjusted'),
      (tg -> 'basis' -> 'recent' -> 0 ->> 'sets_planned')] from jsonb_array_elements(
    private.next_session_targets('b4000000-0000-4000-8000-000000000015')) tg
    where tg ->> 'name' = 'Barbell bench press'), array['false', null],
  'its session is not marked adjusted');
select is((select array[(tg -> 'basis' -> 'recent' -> 0 ->> 'adjusted'),
      (tg -> 'basis' -> 'recent' -> 0 ->> 'sets_planned')] from jsonb_array_elements(
    private.next_session_targets('b4000000-0000-4000-8000-000000000015')) tg
    where tg ->> 'name' = 'Cable fly'), array['true', '3'],
  'while the fly, which the answer held, is');

-- New data asks again for its own reason (P3) ----------------------------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000016');
select pg_temp.check_in('b4000000-0000-4000-8000-000000000016', 2, 3, 3, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), true);
select pg_temp.sleep('b4000000-0000-4000-8000-000000000016', 300);
insert into r select 'new16', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'status', j ->> 'kind', (j -> 'previous_answer' ->> 'reason'),
      (j -> 'previous_answer' ->> 'kind')] from r where name = 'new16'),
  array['proposed', 'reduce_sets', 'new_data', 'hold_load'],
  'sleep that arrives after the answer asks again and says it is new data, not a new check-in');

-- Scores are made again for new Health data, and not retried at once after an attempt (P3) ----------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000017');
select is((select count(*) from public.daily_computed_metrics where user_id = 'b4000000-0000-4000-8000-000000000017'),
  0::bigint, 'no scores yet');
insert into private.day_adjustment_metric_attempts(user_id, local_date, attempted_at, failed)
values ('b4000000-0000-4000-8000-000000000017', (select today from t), now(), true);
select public.get_my_day_adjustment_v1((select today from t));
select is((select count(*) from public.daily_computed_metrics where user_id = 'b4000000-0000-4000-8000-000000000017'),
  0::bigint, 'a failed attempt a minute ago is not retried on this read');
update private.day_adjustment_metric_attempts set attempted_at = now() - interval '11 minutes'
where user_id = 'b4000000-0000-4000-8000-000000000017';
select public.get_my_day_adjustment_v1((select today from t));
select is((select count(*) from public.daily_computed_metrics where user_id = 'b4000000-0000-4000-8000-000000000017'),
  1::bigint, 'after the wait it is tried again and the scores exist');
select is((select failed from private.day_adjustment_metric_attempts
    where user_id = 'b4000000-0000-4000-8000-000000000017'), false, 'and the attempt is recorded as made');
update public.daily_computed_metrics set computed_at = now() - interval '2 hours'
where user_id = 'b4000000-0000-4000-8000-000000000017';
update private.day_adjustment_metric_attempts set attempted_at = now() - interval '11 minutes'
where user_id = 'b4000000-0000-4000-8000-000000000017';
select pg_temp.sleep('b4000000-0000-4000-8000-000000000017', 400);
select public.get_my_day_adjustment_v1((select today from t));
select ok((select computed_at > now() - interval '1 minute' from public.daily_computed_metrics
    where user_id = 'b4000000-0000-4000-8000-000000000017'),
  'Health data that arrived after the scores makes them again');

-- A score made before a check-in is made again after it ------------------------------------------------

select pg_temp.as_user('b4000000-0000-4000-8000-000000000018');
select pg_temp.metrics('b4000000-0000-4000-8000-000000000018', 60, 'high');
update public.daily_computed_metrics set computed_at = now() - interval '1 hour'
where user_id = 'b4000000-0000-4000-8000-000000000018';
select pg_temp.check_in('b4000000-0000-4000-8000-000000000018', 1, 1, 3, 3, 0);
update public.daily_check_ins set created_at = now() - interval '30 minutes'
where user_id = 'b4000000-0000-4000-8000-000000000018' and superseded_at is null;
insert into r select 'fresh18', public.get_my_day_adjustment_v1((select today from t));
select ok((select (j -> 'signals' ->> 'recovery_score') is distinct from '60' from r where name = 'fresh18')
  and (select (j -> 'signals' ->> 'recovery_score')::integer is not distinct from m.recovery_score
    from r, public.daily_computed_metrics m where r.name = 'fresh18'
      and m.user_id = 'b4000000-0000-4000-8000-000000000018')
  and (select computed_at > now() - interval '1 minute' from public.daily_computed_metrics
    where user_id = 'b4000000-0000-4000-8000-000000000018'),
  'a check-in saved after the score was made gets a new score, not the old one');

-- Even right after an attempt: the check-in is newer than it.
select pg_temp.metrics('b4000000-0000-4000-8000-000000000018', 60, 'high');
update public.daily_computed_metrics set computed_at = now() - interval '1 hour'
where user_id = 'b4000000-0000-4000-8000-000000000018';
update private.day_adjustment_metric_attempts set attempted_at = now() - interval '5 minutes'
where user_id = 'b4000000-0000-4000-8000-000000000018';
update public.daily_check_ins set created_at = now() - interval '1 minute'
where user_id = 'b4000000-0000-4000-8000-000000000018' and superseded_at is null;
insert into r select 'bypass18', public.get_my_day_adjustment_v1((select today from t));
select ok((select (j -> 'signals' ->> 'recovery_score') is distinct from '60' from r where name = 'bypass18'),
  'a check-in newer than the last attempt is never throttled');

-- Otherwise the attempt limit holds.
select pg_temp.metrics('b4000000-0000-4000-8000-000000000018', 60, 'high');
update public.daily_computed_metrics set computed_at = now() - interval '1 hour'
where user_id = 'b4000000-0000-4000-8000-000000000018';
update private.day_adjustment_metric_attempts set attempted_at = now() - interval '1 minute'
where user_id = 'b4000000-0000-4000-8000-000000000018';
update public.daily_check_ins set created_at = now() - interval '30 minutes'
where user_id = 'b4000000-0000-4000-8000-000000000018' and superseded_at is null;
insert into r select 'held18', public.get_my_day_adjustment_v1((select today from t));
select is((select j -> 'signals' ->> 'recovery_score' from r where name = 'held18'), '60',
  'with nothing newer than the last attempt, the score is not made again within the limit');

-- A workout finished after the score also makes it stale.
select pg_temp.metrics('b4000000-0000-4000-8000-000000000018', 60, 'high');
update public.daily_computed_metrics set computed_at = now() - interval '1 hour'
where user_id = 'b4000000-0000-4000-8000-000000000018';
update private.day_adjustment_metric_attempts set attempted_at = now() - interval '11 minutes'
where user_id = 'b4000000-0000-4000-8000-000000000018';
update public.daily_check_ins set created_at = now() - interval '2 hours'
where user_id = 'b4000000-0000-4000-8000-000000000018' and superseded_at is null;
select pg_temp.log_bench('b4000000-0000-4000-8000-000000000018', 0, 8);
update public.workout_sessions set completed_at = now() - interval '5 minutes'
where user_id = 'b4000000-0000-4000-8000-000000000018';
insert into r select 'workout18', public.get_my_day_adjustment_v1((select today from t));
select ok((select (j -> 'signals' ->> 'recovery_score') is distinct from '60' from r where name = 'workout18'),
  'a workout finished after the score was made makes it again');

-- A body-weight or unassisted hold reads as such, not as 0 kg (P3) ---------------------------------------

insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
select 'b4300000-0000-4000-8000-000000000001', uid, workout_id, 4, 'Assisted pull-up', 3, 6, 10, 8, 90,
  'assisted-pull-up' from wk where uid = 'b4000000-0000-4000-8000-000000000010';
select is((select c -> 'changes' -> 0 ->> 'load_note' from (select private.day_adjustment_changes(
    'b4000000-0000-4000-8000-000000000010', (select workout_id from wk
      where uid = 'b4000000-0000-4000-8000-000000000010'), 'hold_load',
    jsonb_build_array(jsonb_build_object('planned_exercise_id', 'b4300000-0000-4000-8000-000000000001',
      'action', 'add_load', 'load_kg', 2.5, 'reps', 6, 'basis', jsonb_build_object('recent',
        jsonb_build_array(jsonb_build_object('load_kg', 0, 'min_reps', 10)))))) c) x),
  'Keep last time''s unassisted reps', 'an assisted exercise done unassisted');
select is((select c -> 'changes' -> 0 ->> 'load_note' from (select private.day_adjustment_changes(
    'b4000000-0000-4000-8000-000000000010', (select workout_id from wk
      where uid = 'b4000000-0000-4000-8000-000000000010'), 'hold_load',
    jsonb_build_array(jsonb_build_object('planned_exercise_id', (select e1 from wk
        where uid = 'b4000000-0000-4000-8000-000000000010'),
      'action', 'add_load', 'load_kg', 2.5, 'reps', 5, 'basis', jsonb_build_object('recent',
        jsonb_build_array(jsonb_build_object('load_kg', 0, 'min_reps', 8)))))) c) x),
  'Keep last time''s body weight', 'and an added-load exercise with no load added');

-- Privacy -----------------------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'b4000000-0000-4000-8000-000000000002';
select is((select count(*) from public.day_adjustments), 0::bigint, 'another athlete sees no answers');
set local "request.jwt.claim.sub" = 'b4000000-0000-4000-8000-000000000001';
select ok((select count(*) from public.day_adjustments) > 0
  and (select bool_and(user_id = 'b4000000-0000-4000-8000-000000000001') from public.day_adjustments),
  'an athlete sees only their own');
reset role;

select throws_ok($$update public.workout_sessions set day_adjustment_id = (
    select id from public.day_adjustments where user_id = 'b4000000-0000-4000-8000-000000000006' limit 1)
  where idempotency_key = 'b4100000-0000-4000-8000-000000000001'$$,
  '23503', null, 'a session cannot link another athlete''s answer');

delete from auth.users where id = 'b4000000-0000-4000-8000-000000000001';
select is((select count(*) from public.day_adjustments
    where user_id = 'b4000000-0000-4000-8000-000000000001'), 0::bigint,
  'deleting the account deletes the answers');
select is((select count(*) from public.workout_sessions
    where user_id = 'b4000000-0000-4000-8000-000000000001'), 0::bigint, 'and the sessions that pointed at them');
select ok((select count(*) from public.day_adjustments
    where user_id = 'b4000000-0000-4000-8000-000000000006') > 0, 'and leaves another athlete''s');

select * from finish();
rollback;
