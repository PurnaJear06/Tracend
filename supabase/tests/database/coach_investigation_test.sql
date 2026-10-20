begin;
select no_plan();

-- Coach investigates first (migration 20261020100017_coach_investigation.sql): the index grows,
-- the workouts and recovery lookups return what they stored and did not return, three lookups take
-- a new filter, Coach's own replies are returned for the words, and the watch-out facts.

insert into auth.users(id, role) values
  ('a1030000-0000-4000-8000-000000000001', 'authenticated'),
  ('a1030000-0000-4000-8000-000000000002', 'authenticated');
insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level, training_days,
  session_minutes)
values ('a1030000-0000-4000-8000-000000000001', now(), true, 'intermediate', array[1,3,5]::smallint[], 60);

-- A plan with two sessions and a chest fly that is skipped twice running ------------------------

insert into public.training_plans(id, user_id, title, source) values
  ('a1130000-0000-4000-8000-000000000001', 'a1030000-0000-4000-8000-000000000001', 'Push pull', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('a1230000-0000-4000-8000-000000000001', 'a1030000-0000-4000-8000-000000000001',
   'a1130000-0000-4000-8000-000000000001', 3, 'active', 6, 2, '{}', 'Approved for the test', now(),
   current_date - 70);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('a1330000-0000-4000-8000-000000000001', 'a1030000-0000-4000-8000-000000000001',
   'a1230000-0000-4000-8000-000000000001', 1, 'Push day', 'Press', extract(isodow from current_date)::integer,
   50, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug) values
  ('a1430000-0000-4000-8000-000000000001', 'a1030000-0000-4000-8000-000000000001',
   'a1330000-0000-4000-8000-000000000001', 1, 'Barbell bench press', 3, 6, 8, 120, 'barbell-bench-press'),
  ('a1430000-0000-4000-8000-000000000002', 'a1030000-0000-4000-8000-000000000001',
   'a1330000-0000-4000-8000-000000000001', 2, 'Cable chest fly', 2, 10, 12, 60, 'cable-chest-fly');

-- A session with its performances: bench performed (a pain flag and a note on the last one),
-- the fly skipped after the first session, and a substitution in the last.
create function pg_temp.session(p_id text, p_date date, p_notes text) returns uuid language sql as $$
  insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source, notes)
  values (('a1530000-0000-4000-8000-' || p_id)::uuid, 'a1030000-0000-4000-8000-000000000001',
    'a1230000-0000-4000-8000-000000000001', 'a1330000-0000-4000-8000-000000000001', p_date, 'UTC',
    'completed', gen_random_uuid(), now() - (current_date - p_date) * interval '1 day', 3000, 8,
    'athlete', 'manual', p_notes)
  returning id;
$$;
create function pg_temp.perf(p_session uuid, p_planned text, p_order integer, p_status text,
  p_kind text, p_pain boolean, p_note text, p_name text, p_reason text, p_slug text)
returns uuid language sql as $$
  insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
    exercise_order, status, performance_kind, exercise_slug, pain_flag, note, performed_name,
    substitution_reason)
  values ('a1030000-0000-4000-8000-000000000001', p_session, ('a1430000-0000-4000-8000-' || p_planned)::uuid,
    p_order, p_status, p_kind, p_slug, p_pain, p_note, p_name, p_reason)
  returning id;
$$;
create function pg_temp.set_of(p_perf uuid, p_n integer, p_reps integer, p_kg numeric)
returns void language sql as $$
  insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
    rir, completed)
  values ('a1030000-0000-4000-8000-000000000001', p_perf, p_n, p_reps, p_kg, 2, true);
$$;

select pg_temp.set_of(pg_temp.perf(pg_temp.session('000000000001', current_date - 8, ''),
  '000000000001', 1, 'performed', 'prescribed', false, '', null, null, 'barbell-bench-press'), 1, 8, 70);
select pg_temp.set_of(pg_temp.perf(pg_temp.session('000000000002', current_date - 5, 'Felt flat today'),
  '000000000001', 1, 'performed', 'prescribed', false, '', null, null, 'barbell-bench-press'), 1, 8, 72.5);
select pg_temp.set_of(pg_temp.perf(pg_temp.session('000000000003', current_date - 2, 'Shoulder twinge'),
  '000000000001', 1, 'performed', 'prescribed', true, 'Right shoulder pinched', null, null,
  'barbell-bench-press'), 1, 8, 75);
-- The fly: performed in the first session, skipped in the next two (its streak is 2).
select pg_temp.perf('a1530000-0000-4000-8000-000000000001', '000000000002', 2, 'performed', 'prescribed',
  false, '', null, null, 'cable-chest-fly');
select pg_temp.perf('a1530000-0000-4000-8000-000000000002', '000000000002', 2, 'skipped', 'prescribed',
  false, '', null, null, 'cable-chest-fly');
select pg_temp.perf('a1530000-0000-4000-8000-000000000003', '000000000002', 2, 'skipped', 'prescribed',
  false, '', null, null, 'cable-chest-fly');
-- A substitution in the newest session.
select pg_temp.set_of(pg_temp.perf('a1530000-0000-4000-8000-000000000003', '000000000002', 3, 'performed',
  'substituted', false, '', 'Pec deck', 'Cable station was taken', null), 1, 12, 40);

-- An earlier version of the same plan, two months before, with an exercise the active plan dropped.
-- Its skipped curls are not a skip to raise, and the plan began when this version did.
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  ('a1230000-0000-4000-8000-000000000002', 'a1030000-0000-4000-8000-000000000001',
   'a1130000-0000-4000-8000-000000000001', 2, 'superseded', 6, 1, '{}', 'The first version', now(),
   current_date - 120);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('a1330000-0000-4000-8000-000000000002', 'a1030000-0000-4000-8000-000000000001',
   'a1230000-0000-4000-8000-000000000002', 1, 'Old arms', 'Curl', 2, 40, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug) values
  ('a1430000-0000-4000-8000-000000000010', 'a1030000-0000-4000-8000-000000000001',
   'a1330000-0000-4000-8000-000000000002', 1, 'Cable curl', 3, 8, 12, 60, 'cable-curl');
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
  session_effort_source, completion_source, notes) values
  ('a1530000-0000-4000-8000-000000000011', 'a1030000-0000-4000-8000-000000000001',
   'a1230000-0000-4000-8000-000000000002', 'a1330000-0000-4000-8000-000000000002',
   current_date - 12, 'UTC', 'completed', gen_random_uuid(), now() - interval '12 days', 2400, 6,
   'athlete', 'manual', ''),
  ('a1530000-0000-4000-8000-000000000012', 'a1030000-0000-4000-8000-000000000001',
   'a1230000-0000-4000-8000-000000000002', 'a1330000-0000-4000-8000-000000000002',
   current_date - 11, 'UTC', 'completed', gen_random_uuid(), now() - interval '11 days', 2400, 6,
   'athlete', 'manual', '');
select pg_temp.perf('a1530000-0000-4000-8000-000000000011', '000000000010', 1, 'skipped', 'prescribed',
  false, '', null, null, 'cable-curl');
select pg_temp.perf('a1530000-0000-4000-8000-000000000012', '000000000010', 1, 'skipped', 'prescribed',
  false, '', null, null, 'cable-curl');

-- Two sync runs: a completed one three days ago, and a failed one an hour ago that is not a sync.
insert into public.health_sync_runs(user_id, idempotency_key, requested_start, requested_end,
  requested_types, returned_types, accepted_count, rejected_count, status, completed_at) values
  ('a1030000-0000-4000-8000-000000000001', 'a1730000-0000-4000-8000-000000000001', current_date - 7,
   current_date, array['steps'], array['steps'], 8, 0, 'completed', now() - interval '3 days'),
  ('a1030000-0000-4000-8000-000000000001', 'a1730000-0000-4000-8000-000000000002', current_date - 7,
   current_date, array['steps'], array[]::text[], 0, 8, 'failed', now() - interval '1 hour');

-- Recovery, a check-in, a weigh-in and the sync ----------------------------------------------------

insert into public.daily_health_summaries(user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at, resting_heart_rate_bpm, sleep_minutes,
  respiratory_rate_bpm, sleep_deep_minutes, sleep_rem_minutes, sleep_light_minutes, sleep_awake_minutes,
  hrv_value_ms, hrv_metric, hrv_unit, hrv_sleep_ms, active_energy_kcal, workout_minutes)
values ('a1030000-0000-4000-8000-000000000001', current_date, 'UTC',
  array['resting_heart_rate','sleep','hrv_sdnn','resp_rate'], '[]'::jsonb, repeat('b', 64), 'partial', now(),
  now() - interval '3 days', 63, 355, 15.4, 50, 80, 205, 20, 41, 'sdnn', 'ms', 44, 520, 62);
insert into public.daily_computed_metrics(user_id, local_date, recovery_score, sleep_quality_score,
  data_confidence, scores_jsonb) values
  ('a1030000-0000-4000-8000-000000000001', current_date, 31, 44, 'medium',
   '{"recovery_breakdown":{"hrv_z":-1.4,"rhr_z":-0.3,"missing_components":["resp_rate"]}}');
insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key, sleep_quality,
  energy, soreness, hunger, mood, pain_severity, available_to_train, note) values
  ('a1030000-0000-4000-8000-000000000001', current_date, 'UTC', 1, gen_random_uuid(), 2, 2, 4, 3, 3, 3,
   true, '');
insert into public.body_measurements(user_id, measured_on, source, weight_kg) values
  ('a1030000-0000-4000-8000-000000000001', current_date - 20, 'manual', 80.5);

-- Workouts the watch recorded, a proposal, a daily decision, and a remembered conversation ------

insert into public.health_workout_references(user_id, sample_id_hash, source_id_hash, activity_type,
  started_at, ended_at, duration_seconds, energy_kcal, local_date) values
  ('a1030000-0000-4000-8000-000000000001', repeat('1', 64), repeat('2', 64), 'Running',
   now() - interval '30 days', now() - interval '30 days' + interval '40 minutes', 2400, 350.4,
   current_date - 30),
  ('a1030000-0000-4000-8000-000000000001', repeat('3', 64), repeat('2', 64), 'Cycling',
   now() - interval '3 days', now() - interval '3 days' + interval '1 hour', 3600, 500,
   current_date - 3);
insert into public.change_proposals(id, user_id, feature_snapshot_id, schema_version, proposed_training,
  proposed_nutrition, evidence, rationale, expected_benefit, downside, confidence, effective_date, expires_at,
  status, proposal_kind, proposal_payload, before_snapshot, after_snapshot, basis, source_message_id)
values ('a1030000-0000-4000-8000-0000000000c1', 'a1030000-0000-4000-8000-000000000001', null, '3.0',
  '{"proposal_kind": "nutrition_targets", "title": "Lower calories"}',
  '{"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60}', '[]', 'The weight is flat',
  'A steady loss', 'Hungrier', 'medium', current_date, now() + interval '3 days', 'accepted',
  'nutrition_targets',
  '{"nutrition": {"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60, "rationale": "Because"}}',
  '{}', '{}', '{}', null);
-- A decision's snapshot, policy and run rows are not the subject of this test.
set local session_replication_role = replica;
insert into public.coach_decisions(user_id, feature_snapshot_id, policy_evaluation_id, model_run_id,
  decision_kind, local_date, schema_version, training, nutrition, head_coach, evidence, confidence,
  risk_flags, valid_until) values
  ('a1030000-0000-4000-8000-000000000001', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
   'daily', current_date - 1, '1.0', '{"action":"ADJUST_TODAY","summary":"Reduce intensity"}',
   '{"action":"MAINTAIN_TARGETS"}', '{"final_decision":"Reduce training intensity today."}', '[]', 'high',
   array['elevated_load'], now() + interval '24 hours');
set local session_replication_role = origin;
insert into public.coach_threads(id, user_id, title, remember) values
  ('a1630000-0000-4000-8000-000000000001', 'a1030000-0000-4000-8000-000000000001', 'Open chat', true),
  ('a1630000-0000-4000-8000-000000000002', 'a1030000-0000-4000-8000-000000000001', 'Private chat', false);
insert into public.coach_messages(user_id, thread_id, role, content, answer_source) values
  ('a1030000-0000-4000-8000-000000000001', 'a1630000-0000-4000-8000-000000000001', 'user',
   'My shoulder hurts on bench', null),
  ('a1030000-0000-4000-8000-000000000001', 'a1630000-0000-4000-8000-000000000001', 'assistant',
   'Shoulder pain on bench can come from the grip; keep the load light', 'model'),
  ('a1030000-0000-4000-8000-000000000001', 'a1630000-0000-4000-8000-000000000001', 'assistant',
   'Data summary mentioning shoulder', 'data_summary'),
  ('a1030000-0000-4000-8000-000000000001', 'a1630000-0000-4000-8000-000000000002', 'assistant',
   'Private shoulder reply', 'model');

-- The watch's Running workout was proposed to two sessions: the athlete rejected the closer match
-- and a weaker one is still suggested. The Cycling workout matches nothing.
insert into public.workout_reconciliations(user_id, workout_session_id, health_workout_reference_id,
  status, confidence, overlap_seconds, duration_difference_seconds) values
  ('a1030000-0000-4000-8000-000000000001', 'a1530000-0000-4000-8000-000000000001',
   (select id from public.health_workout_references where sample_id_hash = repeat('1', 64)),
   'rejected', 0.9, 2000, 100),
  ('a1030000-0000-4000-8000-000000000001', 'a1530000-0000-4000-8000-000000000002',
   (select id from public.health_workout_references where sample_id_hash = repeat('1', 64)),
   'suggested', 0.5, 1000, 600);

-- Another athlete, 14 hours ahead of UTC: 20:00 UTC on 1 October is already 2 October for them.
update public.user_accounts set timezone = 'Pacific/Kiritimati'
where id = 'a1030000-0000-4000-8000-000000000002';
insert into public.coach_threads(id, user_id, title, remember) values
  ('a1630000-0000-4000-8000-000000000003', 'a1030000-0000-4000-8000-000000000002', 'Chat', true);
insert into public.coach_messages(user_id, thread_id, role, content, created_at) values
  ('a1030000-0000-4000-8000-000000000002', 'a1630000-0000-4000-8000-000000000003', 'user',
   'Kayak trip next week', timestamptz '2026-10-01 20:00:00+00'),
  ('a1030000-0000-4000-8000-000000000002', 'a1630000-0000-4000-8000-000000000003', 'assistant',
   'Kayak trips are fine', timestamptz '2026-10-01 20:05:00+00');

set local role service_role;

-- The index -------------------------------------------------------------------------------------

select is(public.get_coach_data_index_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->>'schema_version', '1.2', 'the index is version 1.2');
select is(public.get_coach_data_index_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'domains'->'watch_workouts', jsonb_build_object('first', current_date - 30, 'last', current_date - 3,
    'count', 2), 'the index covers the watch workouts');
select is(public.get_coach_data_index_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'domains'->'proposals'->>'count', '1', 'and the proposals');
select is(public.get_coach_data_index_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'domains'->'daily_decisions'->>'last', (current_date - 1)::text, 'and the daily decisions');
select is(public.get_coach_data_index_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'domains'->'past_messages'->>'count', '1', 'and the athlete''s words in remembered conversations only');
select is(public.get_coach_data_index_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'schedule'->>'version', '3', 'the schedule key is still there');
select is(public.get_coach_data_index_v1('a1030000-0000-4000-8000-000000000002', current_date)
    ->'domains'->'watch_workouts'->>'count', '0', 'another athlete has none');

-- Workouts: the notes ---------------------------------------------------------------------------

select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->>'schema_version', '1.1', 'workouts: version 1.1');
select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'sessions'->0->>'note', 'Shoulder twinge', 'the newest session''s note');
select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'sessions'->2->'note', 'null'::jsonb, 'a session with no note reports none');
select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'sessions'->0->'exercises'->0->>'note', 'Right shoulder pinched',
  'an exercise''s note');
select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'sessions'->0->'exercises'->0->>'pain', 'true', 'with its pain flag');
select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'sessions'->0->'exercises'->2->>'kind', 'substituted', 'a substitution says so');
select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'sessions'->0->'exercises'->2->>'substitution_reason',
  'Cable station was taken', 'and why');
select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'sessions'->0->'exercises'->2->>'planned_name', 'Cable chest fly',
  'and what it replaced');
select is(public.coach_lookup_workouts_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->'sessions'->0->'exercises'->0->'sets'->0->>'reps', '8', 'the sets are unchanged');

-- Recovery: what the watch stored ---------------------------------------------------------------

select is(public.coach_lookup_recovery_v1('a1030000-0000-4000-8000-000000000001', current_date - 7,
    current_date, null)->>'schema_version', '1.1', 'recovery: version 1.1');
select is((public.coach_lookup_recovery_v1('a1030000-0000-4000-8000-000000000001', current_date - 7,
    current_date, null)->'days'->0)->>'respiratory_rate_bpm', '15.40', 'the breathing rate');
select is((public.coach_lookup_recovery_v1('a1030000-0000-4000-8000-000000000001', current_date - 7,
    current_date, null)->'days'->0)->>'sleep_deep_minutes', '50', 'the sleep stages');
select is((public.coach_lookup_recovery_v1('a1030000-0000-4000-8000-000000000001', current_date - 7,
    current_date, null)->'days'->0)->>'hrv_sleep_ms', '44.00', 'the night HRV');
select is((public.coach_lookup_recovery_v1('a1030000-0000-4000-8000-000000000001', current_date - 7,
    current_date, null)->'days'->0)->>'recovery_score', '31', 'next to the recovery score');
select is((public.coach_lookup_recovery_v1('a1030000-0000-4000-8000-000000000001', current_date - 7,
    current_date, null)->'days'->0)->'hrv_morning_ms', 'null'::jsonb, 'a value not measured is null');

-- Plan history: proposals ----------------------------------------------------------------------

select is(public.coach_lookup_plan_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 90,
    current_date, 'Proposals')->>'filter', 'proposals', 'the filter names proposals, in any case');
select is((select array_agg(k order by k) from jsonb_object_keys(public.coach_lookup_plan_history_v1(
    'a1030000-0000-4000-8000-000000000001', current_date - 90, current_date, 'proposals')) k),
  array['filter', 'from', 'lookup', 'proposals', 'schema_version', 'to', 'truncated'],
  'proposals: complete key list');
select is(public.coach_lookup_plan_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 90,
    current_date, 'proposals')->'proposals'->0->>'status', 'accepted', 'the athlete''s answer');
select is(public.coach_lookup_plan_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 90,
    current_date, 'proposals')->'proposals'->0->>'rationale', 'The weight is flat', 'and why it was made');
select is(public.coach_lookup_plan_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 90,
    current_date, 'proposals')->'proposals'->0->>'title', 'Lower calories', 'with its title');
select is(jsonb_array_length(public.coach_lookup_plan_history_v1('a1030000-0000-4000-8000-000000000001',
    current_date - 90, current_date - 60, 'proposals')->'proposals'), 0, 'the range limits them');
select is(jsonb_array_length(public.coach_lookup_plan_history_v1('a1030000-0000-4000-8000-000000000002',
    current_date - 90, current_date, 'proposals')->'proposals'), 0, 'another athlete''s are not read');
select is(public.coach_lookup_plan_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 90,
    current_date, null)->>'schema_version', '1.2', 'without a filter it is the plan versions, version 1.2');

-- Health history: the watch's workouts --------------------------------------------------------

select is((select array_agg(k order by k) from jsonb_object_keys(public.coach_lookup_health_history_v1(
    'a1030000-0000-4000-8000-000000000001', current_date - 60, current_date, 'workouts')) k),
  array['filter', 'from', 'lookup', 'schema_version', 'to', 'truncated', 'workouts'],
  'watch workouts: complete key list');
select is(public.coach_lookup_health_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'workouts')->'workouts'->0->>'activity_type', 'Cycling', 'newest first');
select is(jsonb_array_length(public.coach_lookup_health_history_v1('a1030000-0000-4000-8000-000000000001',
    current_date - 60, current_date, 'workouts')->'workouts'), 2, 'older than 14 days included');
select is(public.coach_lookup_health_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'workouts')->'workouts'->1->>'minutes', '40', 'with its minutes');
select is(jsonb_array_length(public.coach_lookup_health_history_v1('a1030000-0000-4000-8000-000000000001',
    current_date - 60, current_date - 10, 'workouts')->'workouts'), 1, 'the range limits them');
select is(public.coach_lookup_health_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 400,
    current_date, null)->>'schema_version', '1.1', 'without the filter it is the monthly summary');
select is(public.coach_lookup_health_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'workouts')->'workouts'->1->>'reconciliation', 'suggested',
  'a candidate the athlete rejected is not the match while a suggestion stands');
select is(public.coach_lookup_health_history_v1('a1030000-0000-4000-8000-000000000001', current_date - 60,
    current_date, 'workouts')->'workouts'->0->'reconciliation', 'null'::jsonb,
  'and a workout nothing was proposed for matches nothing');

-- Weekly reviews: the daily decisions ---------------------------------------------------------

select is(public.coach_lookup_weekly_reviews_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, 'decisions')->>'filter', 'decisions', 'the filter names the decisions');
select is(public.coach_lookup_weekly_reviews_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, 'decisions')->'decisions'->0->>'training_action', 'ADJUST_TODAY', 'the training action');
select is(public.coach_lookup_weekly_reviews_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, 'decisions')->'decisions'->0->>'decision', 'Reduce training intensity today.',
  'and the decision');
select is(public.coach_lookup_weekly_reviews_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, 'decisions')->'decisions'->0->'risk_flags', '["elevated_load"]'::jsonb, 'and its flags');
select is(jsonb_array_length(public.coach_lookup_weekly_reviews_v1('a1030000-0000-4000-8000-000000000002',
    current_date - 30, current_date, 'decisions')->'decisions'), 0, 'another athlete''s are not read');
select is(public.coach_lookup_weekly_reviews_v1('a1030000-0000-4000-8000-000000000001', current_date - 30,
    current_date, null)->>'schema_version', '1.1', 'without the filter it is the weekly reviews');

-- Past messages: Coach's own replies ----------------------------------------------------------

select is((select array_agg(k order by k) from jsonb_object_keys(public.coach_lookup_past_messages_v1(
    'a1030000-0000-4000-8000-000000000001', current_date - 30, current_date, 'shoulder')) k),
  array['coach_replies', 'from', 'lookup', 'messages', 'schema_version', 'to', 'truncated'],
  'past messages: complete key list');
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1030000-0000-4000-8000-000000000001',
    current_date - 30, current_date, 'shoulder')->'messages'), 1,
  'the athlete''s words are returned as before');
select is((select array_agg(m ->> 'content') from jsonb_array_elements(public.coach_lookup_past_messages_v1(
    'a1030000-0000-4000-8000-000000000001', current_date - 30, current_date, 'shoulder')->'coach_replies') m),
  array['Shoulder pain on bench can come from the grip; keep the load light'],
  'Coach''s own earlier reply is returned, not a data summary and not one from a conversation that is not remembered');
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1030000-0000-4000-8000-000000000002',
    current_date - 30, current_date, 'shoulder')->'coach_replies'), 0, 'another athlete''s are not read');

-- Days are the athlete's local days: the index, the lookup range and the dates all agree.
select is(public.get_coach_data_index_v1('a1030000-0000-4000-8000-000000000002', current_date)
    ->'domains'->'past_messages', '{"first":"2026-10-02","last":"2026-10-02","count":1}'::jsonb,
  'the index dates a message by the athlete''s own day');
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1030000-0000-4000-8000-000000000002',
    date '2026-10-02', date '2026-10-02', 'kayak')->'messages'), 1,
  'a range of just that local day finds it');
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1030000-0000-4000-8000-000000000002',
    date '2026-10-01', date '2026-10-01', 'kayak')->'messages'), 0, 'and the UTC day does not');
select is(public.coach_lookup_past_messages_v1('a1030000-0000-4000-8000-000000000002',
    date '2026-10-02', date '2026-10-02', 'kayak')->'coach_replies'->0->>'local_date', '2026-10-02',
  'Coach''s reply is dated the same way');
select is(public.coach_lookup_past_messages_v1('a1030000-0000-4000-8000-000000000001',
    current_date - 30, current_date, 'shoulder')->'messages'->0->>'local_date', current_date::text,
  'an athlete on UTC keeps the UTC day');

-- The watch-out facts -------------------------------------------------------------------------

select is((select array_agg(k order by k) from jsonb_object_keys(public.get_coach_watch_outs_v1(
    'a1030000-0000-4000-8000-000000000001', current_date)) k),
  array['check_in', 'health_sync', 'local_date', 'metrics', 'pain_flags', 'plan', 'schema_version',
    'skipped', 'sleep', 'weigh_in'], 'the watch-out facts have exactly these keys');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'sleep', jsonb_build_object('local_date', current_date, 'minutes', 355), 'the newest night');
select is((public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'metrics')->>'recovery_score', '31', 'the recovery score');
select is((public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'metrics')->>'sleep_quality_score', '44', 'the sleep quality score');
select is((public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'metrics')->>'hrv_z', '-1.4', 'the engine''s HRV z-score');
select is((public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'metrics')->'missing_components', '["resp_rate"]'::jsonb, 'with the components it could not use');
select is((public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'check_in')->>'pain_severity', '3', 'the check-in''s pain');
select is(jsonb_array_length(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001',
    current_date)->'pain_flags'), 1, 'one exercise flagged for pain');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'pain_flags'->0->>'name', 'Barbell bench press', 'which one');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'pain_flags'->0->>'local_date', (current_date - 2)::text, 'and when');
select is(jsonb_array_length(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001',
    current_date)->'skipped'), 1, 'one exercise skipped in a row: the dropped exercise''s skips are not raised');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'skipped'->0->>'name', 'Cable chest fly', 'the fly');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'skipped'->0->>'sessions', '2', 'skipped in its last two sessions');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'skipped'->0->>'last_date', (current_date - 2)::text, 'last on this date');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'weigh_in'->>'local_date', (current_date - 20)::text, 'the newest weigh-in');
select is((public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'health_sync'->>'at')::timestamptz,
  (select completed_at from public.health_sync_runs
    where idempotency_key = 'a1730000-0000-4000-8000-000000000001'),
  'the newest successful Apple Health sync, as a moment: a completed run, not a later failed one and not a summary written earlier');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'health_sync'->>'local_date', (current_date - 3)::text, 'and its local day');
select is((public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->>'as_of')::timestamptz, now(), 'with the database''s own now, for elapsed-time rules');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date)
    ->'plan', jsonb_build_object('version', 3, 'starts_on', current_date - 120, 'block_weeks', 6,
    'ends_on', null), 'the plan''s number, when it began (its first version, not this one) and block length');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000001', current_date - 3)
    ->'pain_flags', '[]'::jsonb, 'a date before the flag has none');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000002', current_date)
    ->'skipped', '[]'::jsonb, 'an athlete with no sessions skipped nothing');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000002', current_date)
    ->'weigh_in', 'null'::jsonb, 'has no weigh-in');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000002', current_date)
    ->'health_sync', 'null'::jsonb, 'and no sync');
select is(public.get_coach_watch_outs_v1('a1030000-0000-4000-8000-000000000002', current_date)
    ->'plan', 'null'::jsonb, 'and no plan');

-- Access ---------------------------------------------------------------------------------------

reset role;
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (p.proname like 'coach\_lookup\_%\_v1'
      or p.proname in ('get_coach_plan_state_v1', 'get_coach_nutrition_state_v1',
        'get_coach_data_index_v1', 'get_coach_watch_outs_v1'))
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
      and p.prosecdef), 15::bigint,
  'fifteen functions, the new one included: each is SECURITY DEFINER and only the service role calls it');
select is(has_function_privilege('anon', 'private.coach_lookup_proposals(uuid,date,date)', 'execute'),
  false, 'anon cannot run the proposals helper');
select is(has_function_privilege('authenticated', 'private.coach_lookup_proposals(uuid,date,date)',
  'execute'), false, 'nor can an authenticated user');

select * from finish();
rollback;
