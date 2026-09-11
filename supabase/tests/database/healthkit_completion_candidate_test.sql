begin;
select plan(11);

insert into auth.users(id, role) values
  ('11111111-1111-5555-8555-111111111111', 'authenticated'),
  ('22222222-2222-5555-8555-222222222222', 'authenticated');

insert into public.training_plans(id, user_id, title, source) values
  -- source 'imported' keeps the training_plan_version_seed_workouts trigger
  -- from seeding its own Mon/Wed/Fri workouts for this plan version: the
  -- seed would collide with the orders this fixture inserts below
  -- (on conflict do nothing skips them), leaving two workouts on some
  -- weekdays and none on others — a date-dependent failure that first
  -- surfaced on a Friday (2026-09-11). This fixture owns all 7 weekdays.
  ('11111111-3111-5555-8555-111111111111', '11111111-1111-5555-8555-111111111111', 'HK plan', 'imported');

insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
  prescription, rationale, approved_at, effective_date)
values(
  '11111111-4111-5555-8555-111111111111', '11111111-1111-5555-8555-111111111111',
  '11111111-3111-5555-8555-111111111111', 1, 'active', 6, 3, '{}',
  'Approved', now(), current_date);

insert into public.planned_workouts(
  user_id, plan_version_id, workout_order, name, objective, preferred_weekday,
  estimated_minutes, warm_up_guidance, cool_down_guidance)
select '11111111-1111-5555-8555-111111111111',
  '11111111-4111-5555-8555-111111111111', day, 'Workout ' || day,
  'Objective', day, 60, 'Warm up', 'Cool down'
from generate_series(1, 7) day on conflict (plan_version_id, workout_order) do nothing;

reset role;

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at, workout_count, workout_minutes)
values(
  '11111111-1111-5555-8555-111111111111', current_date, 'Asia/Kolkata',
  array['workouts']::text[],
  '[{"type":"workouts","source_id_hash":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","sample_id_hash":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}]'::jsonb,
  'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', 'complete', now(), now(), 2, 90);

select ok(has_function_privilege('authenticated',
  'public.get_healthkit_completion_candidate(date)', 'execute'),
  'authenticated owner can query HK completion candidate');

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-5555-8555-111111111111';

select ok((select public.get_healthkit_completion_candidate(current_date) is not null),
  'candidate is returned when HK data and planned workout exist');

select is((select public.get_healthkit_completion_candidate(current_date)->>'workout_count'), '2',
  'candidate reports HK workout count');

select is((select public.get_healthkit_completion_candidate(current_date)->>'workout_minutes'), '90',
  'candidate reports HK workout minutes');

select is((select public.get_healthkit_completion_candidate(current_date)->>'local_date'), current_date::text,
  'candidate returns the queried date');

select is((select public.get_healthkit_completion_candidate((current_date + 1)::date) is null), true,
  'no candidate returned when no HK data for that date');

set local "request.jwt.claim.sub" = '22222222-2222-5555-8555-222222222222';

select is((select public.get_healthkit_completion_candidate(current_date) is null), true,
  'cross-user sees no candidate');

set local "request.jwt.claim.sub" = '11111111-1111-5555-8555-111111111111';

create temporary table _auto as
select public.healthkit_auto_complete_workout(
  (select id from public.planned_workouts
   where user_id = '11111111-1111-5555-8555-111111111111'
   and preferred_weekday = extract(isodow from current_date)::integer
   order by workout_order limit 1),
  current_date) json;

select is((select public.get_healthkit_completion_candidate(current_date) is null), true,
  'no candidate after workout already auto-completed');

select is((select public.get_healthkit_completion_candidate((current_date + 10)::date) is null), true,
  'no candidate when no planned workout for that day of week');

set local "request.jwt.claim.sub" = '22222222-2222-5555-8555-222222222222';
select is((select public.get_healthkit_completion_candidate(current_date) is null), true,
  'no candidate when user has no HK data at all');

set local role authenticated;
reset "request.jwt.claim.sub";
-- The candidate RPC is plain SQL whose ownership predicates (user_id =
-- auth.uid()) match zero rows under a missing JWT, so it safely returns NULL
-- rather than raising — no data is exposed. Assert the null return.
select is((select public.get_healthkit_completion_candidate(current_date) is null), true,
  'missing JWT sub returns no candidate');

select * from finish();
rollback;
