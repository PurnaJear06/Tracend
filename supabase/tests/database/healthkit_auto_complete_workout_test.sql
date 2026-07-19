begin;
select plan(16);

insert into auth.users(id, role) values
  ('11111111-1111-4444-8444-111111111111', 'authenticated'),
  ('22222222-2222-4444-8444-222222222222', 'authenticated');

insert into public.training_plans(id, user_id, title, source) values
  ('11111111-3111-4444-8444-111111111111', '11111111-1111-4444-8444-111111111111', 'HK plan', 'user'),
  ('22222222-3222-4444-8444-222222222222', '22222222-2222-4444-8444-222222222222', 'Other plan', 'user');

insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
  prescription, rationale, approved_at, effective_date)
values(
  '11111111-4111-4444-8444-111111111111', '11111111-1111-4444-8444-111111111111',
  '11111111-3111-4444-8444-111111111111', 1, 'active', 6, 3, '{}',
  'Approved', now(), current_date),
(
  '22222222-4222-4444-8444-222222222222', '22222222-2222-4444-8444-222222222222',
  '22222222-3222-4444-8444-222222222222', 1, 'active', 6, 3, '{}',
  'Approved', now(), current_date);

insert into public.planned_workouts(
  user_id, plan_version_id, workout_order, name, objective, preferred_weekday,
  estimated_minutes, warm_up_guidance, cool_down_guidance)
select '11111111-1111-4444-8444-111111111111',
  '11111111-4111-4444-8444-111111111111', day, 'Workout ' || day,
  'Objective', day, 60, 'Warm up', 'Cool down'
from generate_series(1, 6) day;

reset role;

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at, workout_count, workout_minutes)
values(
  '11111111-1111-4444-8444-111111111111', current_date, 'Asia/Kolkata',
  array['workouts']::text[],
  '[{"type":"workouts","source_id_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sample_id_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]'::jsonb,
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'complete', now(), now(), 1, 45);

select ok(has_function_privilege('authenticated',
  'public.healthkit_auto_complete_workout(uuid,date)', 'execute'),
  'authenticated owner may auto-complete HealthKit workout');
select ok(not has_function_privilege('service_role',
  'public.healthkit_auto_complete_workout(uuid,date)', 'execute'),
  'service_role may not auto-complete a workout');

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4444-8444-111111111111';

create temporary table result as
select public.healthkit_auto_complete_workout(
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   and preferred_weekday = extract(dow from current_date)::int
   order by workout_order limit 1),
  current_date) json;

select ok((select json->>'session_id' is not null from result),
  'auto-complete returns a session id');

select is((select state::text from public.workout_sessions
  where id = (select (json->>'session_id')::uuid from result)), 'completed',
  'session is completed');

select is((select count(*) from public.audit_events
  where action_code = 'workout.auto_completed'), 1::bigint,
  'auto-complete writes an audit event');

select is((select public.healthkit_auto_complete_workout(
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   and preferred_weekday = extract(dow from current_date)::int
   order by workout_order limit 1),
  current_date)->>'replayed'), 'true',
  'auto-complete is idempotent');

select is((select count(*) from public.workout_sessions
  where user_id = '11111111-1111-4444-8444-111111111111'), 1::bigint,
  'idempotent replay does not duplicate session');

select throws_ok(format($$select public.healthkit_auto_complete_workout(%L, %L)$$,
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   and preferred_weekday = extract(dow from current_date)::int
   order by workout_order limit 1),
  (current_date - 3)::text),
  'P0002', null, 'missing HealthKit data is rejected');

select throws_ok(format($$select public.healthkit_auto_complete_workout(%L, %L)$$,
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   order by workout_order offset 1 limit 1),
  current_date),
  'P0002', null, 'workout not matching HK weekday is rejected');

set local "request.jwt.claim.sub" = '22222222-2222-4444-8444-222222222222';
select throws_ok(format($$select public.healthkit_auto_complete_workout(%L, %L)$$,
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   order by workout_order limit 1),
  current_date),
  'P0002', null, 'cross-user auto-complete is rejected');

set local "request.jwt.claim.sub" = '11111111-1111-4444-8444-111111111111';

select throws_ok($$select public.healthkit_auto_complete_workout(
  '00000000-0000-0000-0000-000000000000', current_date)$$,
  'P0002', null, 'nonexistent planned workout is rejected');

select is((select count(*) from public.workout_sessions
  where user_id = '11111111-1111-4444-8444-111111111111'), 1::bigint,
  'nonexistent workout does not create phantom sessions');

select is((select count(*) from public.workout_sessions
  where user_id = '22222222-2222-4444-8444-222222222222'), 0::bigint,
  'cross-user has no sessions');

select * from finish();
rollback;
