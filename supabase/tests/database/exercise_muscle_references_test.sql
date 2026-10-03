begin;
select plan(8);

insert into auth.users(id, role) values
  ('a9000000-0000-4000-8000-000000000001', 'authenticated');
insert into public.training_plans(id, user_id, title, source) values
  ('a9100000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001',
   'Hypertrophy', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status,
  block_weeks, sessions_per_week, prescription, rationale, approved_at) values
  ('a9200000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001',
   'a9100000-0000-4000-8000-000000000001', 1, 'active', 16, 4, '{}', 'Approved',
   '2026-07-01 08:00:00+00');
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('a9300000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001',
   'a9200000-0000-4000-8000-000000000001', 1, 'Pull', 'Back', 3, 95, 'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug) values
  ('a9400000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001',
   'a9300000-0000-4000-8000-000000000001', 1, 'Reverse Pec Deck', 4, 15, 25, 60, null),
  ('a9400000-0000-4000-8000-000000000002', 'a9000000-0000-4000-8000-000000000001',
   'a9300000-0000-4000-8000-000000000001', 2, '  leg press — QUAD focus ', 3, 10, 12, 90, null),
  ('a9400000-0000-4000-8000-000000000003', 'a9000000-0000-4000-8000-000000000001',
   'a9300000-0000-4000-8000-000000000001', 3, 'Romanian Deadlift', 3, 8, 10, 120,
   'barbell-deadlift'),
  ('a9400000-0000-4000-8000-000000000004', 'a9000000-0000-4000-8000-000000000001',
   'a9300000-0000-4000-8000-000000000001', 4, 'Mystery press', 3, 8, 10, 90, null);

select is(
  (select count(*) from public.exercise_muscle_references
   where name_key <> private.exercise_name_key(name)),
  0::bigint,
  'every reviewed name is stored under its history key');

select is(
  (select count(*) from public.exercise_muscle_references r
   join public.exercise_catalog c
     on private.exercise_name_key(c.name) = r.name_key),
  0::bigint,
  'no reviewed name shadows a catalog name');

create temp table hub(body jsonb) on commit drop;
grant all on hub to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub" = 'a9000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select * from public.exercise_muscle_references$$,
  '42501',
  null,
  'athletes cannot read the reviewed list directly');

insert into hub select public.get_my_training_hub(28);
reset role;

create temp view hub_exercises as
  select e from hub, jsonb_array_elements(body->'workouts') w,
    jsonb_array_elements(w->'exercises') e;

select is(
  (select e->'primary_muscles' from hub_exercises where e->>'name' = 'Reverse Pec Deck'),
  '["shoulders"]'::jsonb,
  'an unlinked reviewed name gets its reviewed muscles');

select is(
  (select e->'primary_muscles' from hub_exercises
   where e->>'name' = '  leg press — QUAD focus '),
  '["quads", "glutes"]'::jsonb,
  'case and spacing still match the reviewed name');

select is(
  (select e->'primary_muscles' from hub_exercises where e->>'name' = 'Romanian Deadlift'),
  '["back", "hamstrings", "glutes"]'::jsonb,
  'a catalog link wins over the reviewed list');

select is(
  (select e->'primary_muscles' from hub_exercises where e->>'name' = 'Mystery press'),
  '[]'::jsonb,
  'a name on neither list has no muscles');

select is(
  (select e->>'exercise_slug' from hub_exercises where e->>'name' = 'Reverse Pec Deck'),
  null,
  'a reviewed name is not given a catalog slug');

select * from finish();
rollback;
