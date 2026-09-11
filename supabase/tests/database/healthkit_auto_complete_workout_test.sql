begin;
select plan(15);

insert into auth.users(id, role) values
  ('11111111-1111-4444-8444-111111111111', 'authenticated'),
  ('22222222-2222-4444-8444-222222222222', 'authenticated');

insert into public.training_plans(id, user_id, title, source) values
  -- source 'imported' keeps the training_plan_version_seed_workouts trigger
  -- from seeding its own Mon/Wed/Fri workouts for these plan versions: the
  -- seed would collide with the orders this fixture inserts below
  -- (on conflict do nothing skips them), leaving two workouts on some
  -- weekdays and none on others — a date-dependent failure that first
  -- surfaced on a Friday (2026-09-11). This fixture owns all 7 weekdays.
  ('11111111-3111-4444-8444-111111111111', '11111111-1111-4444-8444-111111111111', 'HK plan', 'imported'),
  ('22222222-3222-4444-8444-222222222222', '22222222-2222-4444-8444-222222222222', 'Other plan', 'imported');

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
from generate_series(1, 7) day on conflict (plan_version_id, workout_order) do nothing;

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
-- service_role holds PUBLIC execute (no explicit revoke exists), but the
-- runtime auth.uid() guard rejects service-role callers with 42501 — asserted
-- below via throws_ok instead of a static privilege check.


set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4444-8444-111111111111';

create temporary table result as
select public.healthkit_auto_complete_workout(
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   and preferred_weekday = extract(isodow from current_date)::integer
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
   and preferred_weekday = extract(isodow from current_date)::integer
   order by workout_order limit 1),
  current_date)->>'replayed'), 'true',
  'auto-complete is idempotent');

select is((select count(*) from public.workout_sessions
  where user_id = '11111111-1111-4444-8444-111111111111'), 1::bigint,
  'idempotent replay does not duplicate session');

select throws_ok(format($$select public.healthkit_auto_complete_workout(%L, %L)$$,
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   and preferred_weekday = extract(isodow from current_date)::integer
   order by workout_order limit 1),
  (current_date - 3)::text),
  'P0001', null, 'missing HealthKit data is rejected');

select throws_ok(format($$select public.healthkit_auto_complete_workout(%L, %L)$$,
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   and preferred_weekday <> extract(isodow from current_date)::integer
   order by workout_order limit 1),
  current_date),
  'P0001', null, 'workout not scheduled for this weekday is rejected');

set local "request.jwt.claim.sub" = '22222222-2222-4444-8444-222222222222';
select throws_ok(format($$select public.healthkit_auto_complete_workout(%L, %L)$$,
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   order by workout_order limit 1),
  current_date),
  'P0001', null, 'cross-user auto-complete is rejected');

set local "request.jwt.claim.sub" = '11111111-1111-4444-8444-111111111111';

select throws_ok($$select public.healthkit_auto_complete_workout(
  '00000000-0000-0000-0000-000000000000', current_date)$$,
  'P0001', null, 'nonexistent planned workout is rejected');

select is((select count(*) from public.workout_sessions
  where user_id = '11111111-1111-4444-8444-111111111111'), 1::bigint,
  'nonexistent workout does not create phantom sessions');

select is((select count(*) from public.workout_sessions
  where user_id = '22222222-2222-4444-8444-222222222222'), 0::bigint,
  'cross-user has no sessions');

-- 2026-09-09 repairs: runtime service-role guard (auth.uid() is null under
-- service_role, so the call must raise 42501) and the NULL-duration hole (a
-- weekday-correct planned workout but no HealthKit summary row for the date
-- must raise, never insert a completed session with NULL duration).
set local role service_role;
reset "request.jwt.claim.sub";

select throws_ok(format($$select public.healthkit_auto_complete_workout(%L, %L)$$,
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   and preferred_weekday = extract(isodow from current_date)::integer
   order by workout_order limit 1),
  current_date),
  'P0001', null, 'service role cannot auto-complete (auth.uid() null)');

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4444-8444-111111111111';

select throws_ok(format($$select public.healthkit_auto_complete_workout(%L, %L)$$,
  (select id from public.planned_workouts
   where user_id = '11111111-1111-4444-8444-111111111111'
   and preferred_weekday = extract(isodow from (current_date + 1))::integer
   order by workout_order limit 1),
  (current_date + 1)::date),
  'P0001', null, 'no HealthKit summary row for the date is rejected (never NULL-duration)');

select is((select count(*) from public.workout_sessions
  where user_id = '11111111-1111-4444-8444-111111111111'), 1::bigint,
  'rejected calls never create phantom sessions');

select * from finish();
rollback;
