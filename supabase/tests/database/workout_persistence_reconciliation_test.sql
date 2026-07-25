begin;
select plan(23);

insert into auth.users(id, role) values
  ('11111111-1111-6666-8666-111111111111', 'authenticated'),
  ('22222222-2222-6666-8666-222222222222', 'authenticated');

insert into public.training_plans(id, user_id, title, source) values
  ('11111111-3111-6666-8666-111111111111', '11111111-1111-6666-8666-111111111111', 'Plan', 'user');

insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
  prescription, rationale, approved_at, effective_date)
values(
  '11111111-4111-6666-8666-111111111111', '11111111-1111-6666-8666-111111111111',
  '11111111-3111-6666-8666-111111111111', 1, 'active', 6, 3, '{}',
  'Approved', now(), current_date);

insert into public.planned_workouts(
  user_id, plan_version_id, workout_order, name, objective, preferred_weekday,
  estimated_minutes, warm_up_guidance, cool_down_guidance)
values(
  '11111111-1111-6666-8666-111111111111', '11111111-4111-6666-8666-111111111111',
  1, 'Strength Day', 'Objective', 1, 60, 'Warm up', 'Cool down') on conflict (plan_version_id, workout_order) do nothing;

insert into public.planned_exercises(
  user_id, planned_workout_id, exercise_order, display_name_snapshot,
  set_count, rep_min, rep_max, target_rpe, rest_seconds, notes)
values(
  '11111111-1111-6666-8666-111111111111',
  (select id from public.planned_workouts
   where user_id = '11111111-1111-6666-8666-111111111111' limit 1),
  1, 'Bench Press', 3, 6, 10, 8, 120, '') on conflict (planned_workout_id, exercise_order) do nothing;

select ok(has_function_privilege('service_role',
  'public.persist_health_workouts(uuid,jsonb)', 'execute'),
  'service_role can persist health workouts');
select ok(not has_function_privilege('authenticated',
  'public.persist_health_workouts(uuid,jsonb)', 'execute'),
  'authenticated cannot call health workout persistence');

set local role service_role;
select lives_ok(format($$select public.persist_health_workouts(
  '11111111-1111-6666-8666-111111111111',
  '[{"sample_id_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","source_id_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","activity_type":"TraditionalStrengthTraining","started_at":"%s","ended_at":"%s","duration_seconds":3600,"energy_kcal":300,"local_date":"%s"}]'::jsonb
)$$, (now() - interval '2 hours')::text, (now() - interval '1 hour')::text, current_date::text),
  'persist_health_workouts accepts validated workout payload');

select is((select count(*) from public.health_workout_references
  where user_id = '11111111-1111-6666-8666-111111111111'), 1::bigint,
  'health workout reference is persisted');

select lives_ok(format($$select public.persist_health_workouts(
  '11111111-1111-6666-8666-111111111111',
  '[{"sample_id_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","source_id_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","activity_type":"TraditionalStrengthTraining","started_at":"%s","ended_at":"%s","duration_seconds":3600,"energy_kcal":300,"local_date":"%s"}]'::jsonb
)$$, (now() - interval '2 hours')::text, (now() - interval '1 hour')::text, current_date::text),
  're-persist same workout idempotent');

select is((select count(*) from public.health_workout_references
  where user_id = '11111111-1111-6666-8666-111111111111'), 1::bigint,
  'duplicate payload does not duplicate health references');

select throws_ok($$select public.persist_health_workouts(
  '11111111-1111-6666-8666-111111111111',
  '[]'::jsonb
)$$, '22023', null, 'empty payload is rejected');

select throws_ok($$select public.persist_health_workouts(
  '00000000-0000-0000-0000-000000000000',
  '[{"sample_id_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","source_id_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","activity_type":"Run","started_at":"2026-01-01T00:00:00Z","ended_at":"2026-01-01T01:00:00Z","duration_seconds":3600,"energy_kcal":300,"local_date":"2026-01-01"}]'::jsonb
)$$, '23503', null, 'nonexistent user is rejected');

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-6666-8666-111111111111';

select is(jsonb_array_length(public.get_my_workout_reconciliation_candidates()), 0::bigint,
  'no reconciliation candidates without completed session');

set local role service_role;

insert into public.workout_sessions(
  id, user_id, planned_workout_id, plan_version_id, idempotency_key,
  state, started_at, local_date, timezone, actual_started_at,
  actual_ended_at, logging_completeness)
values(
  '11111111-5111-6666-8666-111111111111', '11111111-1111-6666-8666-111111111111',
  (select id from public.planned_workouts
   where user_id = '11111111-1111-6666-8666-111111111111' limit 1),
  '11111111-4111-6666-8666-111111111111', gen_random_uuid(),
  'completed', now() - interval '3 hours', current_date, 'Asia/Kolkata',
  now() - interval '3 hours', now() - interval '2 hours 55 min', 1);

insert into public.workout_reconciliations(
  id, user_id, workout_session_id, health_workout_reference_id,
  status, confidence, overlap_seconds, duration_difference_seconds)
values(
  '11111111-6111-6666-8666-111111111111', '11111111-1111-6666-8666-111111111111',
  '11111111-5111-6666-8666-111111111111',
  (select id from public.health_workout_references
   where user_id = '11111111-1111-6666-8666-111111111111' limit 1),
  'suggested', 0.85, 3000, 600);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-6666-8666-111111111111';

select is((select jsonb_array_length(jsonb_agg(t)) from public.get_my_workout_reconciliation_candidates() t), 1::bigint,
  'reconciliation candidate is returned');

select is((select public.get_my_workout_reconciliation_candidates()->0->>'status'), 'suggested',
  'candidate shows correct status');

select lives_ok(format(
  $$select public.respond_workout_reconciliation(
    '11111111-6111-6666-8666-111111111111', true)$$),
  'accepting reconciliation is safe');

select is((select count(*) from public.audit_events
  where action_code = 'workout.reconciliation_confirmed'), 1::bigint,
  'reconciliation confirmation writes audit event');

set local "request.jwt.claim.sub" = '22222222-2222-6666-8666-222222222222';

select is((select jsonb_array_length(public.get_my_workout_reconciliation_candidates())), 0::bigint,
  'cross-user sees no reconciliation candidates');

select throws_ok($$select public.respond_workout_reconciliation(
  '11111111-6111-6666-8666-111111111111', false)$$,
  'P0002', null, 'cross-user cannot respond to reconciliation');

set local "request.jwt.claim.sub" = '11111111-1111-6666-8666-111111111111';

select throws_ok($$select public.respond_workout_reconciliation(
  '00000000-0000-0000-0000-000000000000', true)$$,
  'P0002', null, 'nonexistent reconciliation is rejected');

select ok(has_function_privilege('authenticated',
  'public.get_my_workout_repair_candidates()', 'execute'),
  'authenticated can query repair candidates');

select ok(has_function_privilege('authenticated',
  'public.get_my_workout_reconciliation_candidates()', 'execute'),
  'authenticated can query reconciliation candidates');

select * from finish();
rollback;
