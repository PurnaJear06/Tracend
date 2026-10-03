begin;
select plan(8);

insert into auth.users(id, role) values
  ('a8000000-0000-4000-8000-000000000001', 'authenticated');
insert into public.training_plans(id, user_id, title, source) values
  ('a8100000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001',
   'Shoulders', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status,
  block_weeks, sessions_per_week, prescription, rationale, approved_at) values
  ('a8200000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001',
   'a8100000-0000-4000-8000-000000000001', 1, 'active', 16, 4, '{}', 'Approved',
   '2026-07-01 08:00:00+00');
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  ('a8300000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001',
   'a8200000-0000-4000-8000-000000000001', 1, 'Shoulder width', 'Delts', 6, 100,
   'Warm up', 'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds, exercise_slug) values
  ('a8400000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001',
   'a8300000-0000-4000-8000-000000000001', 1, 'Seated DB or Machine Shoulder Press',
   3, 6, 10, 120, null),
  ('a8400000-0000-4000-8000-000000000002', 'a8000000-0000-4000-8000-000000000001',
   'a8300000-0000-4000-8000-000000000001', 2, '  Cable   Lateral Raise ', 5, 12, 25, 60, null),
  ('a8400000-0000-4000-8000-000000000003', 'a8000000-0000-4000-8000-000000000001',
   'a8300000-0000-4000-8000-000000000001', 3, 'Face pull', 3, 12, 15, 60, 'face-pull');

insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, completed_at, duration_seconds, session_effort)
values ('a8500000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001',
  'a8200000-0000-4000-8000-000000000001', 'a8300000-0000-4000-8000-000000000001',
  '2026-09-26', 'UTC', 'completed', gen_random_uuid(), '2026-09-26 10:00:00+00', 3600, 8);
insert into public.exercise_performances(id, user_id, workout_session_id, planned_exercise_id,
  exercise_order, status, performance_kind, performed_name, substitution_reason) values
  ('a8600000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001',
   'a8500000-0000-4000-8000-000000000001', 'a8400000-0000-4000-8000-000000000002', 1,
   'performed', 'prescribed', 'Cable Lateral Raise', null),
  ('a8600000-0000-4000-8000-000000000002', 'a8000000-0000-4000-8000-000000000001',
   'a8500000-0000-4000-8000-000000000001', 'a8400000-0000-4000-8000-000000000002', 2,
   'performed', 'substituted', 'Machine lateral raise', 'Cable taken');

select is(
  (select count(*) from (
     select private.exercise_name_key(name) from public.exercise_catalog
     group by 1 having count(*) > 1) d),
  0::bigint,
  'every catalog name has its own key, so a name links to at most one exercise');

select is(private.link_planned_exercises_to_catalog(), 1,
  'one unlinked planned exercise matches a catalog name');

select is(
  (select exercise_slug from public.planned_exercises
   where id = 'a8400000-0000-4000-8000-000000000002'),
  'cable-lateral-raise',
  'case and spacing differences still match the catalog name');

select is(
  (select exercise_slug from public.planned_exercises
   where id = 'a8400000-0000-4000-8000-000000000001'),
  null,
  'a name that is not a catalog name stays unlinked');

select is(
  (select exercise_slug from public.planned_exercises
   where id = 'a8400000-0000-4000-8000-000000000003'),
  'face-pull',
  'an existing link is never changed');

select is(
  (select exercise_slug from public.exercise_performances
   where id = 'a8600000-0000-4000-8000-000000000001'),
  'cable-lateral-raise',
  'the prescribed performance takes the new link');

select is(
  (select exercise_slug from public.exercise_performances
   where id = 'a8600000-0000-4000-8000-000000000002'),
  null,
  'a substitution keeps no link');

select is(private.link_planned_exercises_to_catalog(), 0,
  'running it again links nothing new');

select * from finish();
rollback;
