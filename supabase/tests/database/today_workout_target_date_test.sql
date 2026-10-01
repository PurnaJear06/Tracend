begin;
select plan(9);

insert into auth.users(id,role) values
 ('a5000000-0000-4000-8000-000000000005','authenticated'),
 ('a6000000-0000-4000-8000-000000000006','authenticated'),
 ('a7000000-0000-4000-8000-000000000007','authenticated');
insert into public.training_plans(id,user_id,title,source) values
 ('b5000000-0000-4000-8000-000000000005','a5000000-0000-4000-8000-000000000005','Five day plan','user'),
 ('b6000000-0000-4000-8000-000000000006','a6000000-0000-4000-8000-000000000006','Six day plan','user'),
 ('b7000000-0000-4000-8000-000000000007','a7000000-0000-4000-8000-000000000007','Seven day plan','user');
insert into public.training_plan_versions(id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,prescription,rationale,approved_at,effective_date) values
 ('c5000000-0000-4000-8000-000000000005','a5000000-0000-4000-8000-000000000005','b5000000-0000-4000-8000-000000000005',1,'active',6,5,'{}','Five sessions',now(),current_date),
 ('c6000000-0000-4000-8000-000000000006','a6000000-0000-4000-8000-000000000006','b6000000-0000-4000-8000-000000000006',1,'active',6,6,'{}','Six sessions',now(),current_date),
 ('c7000000-0000-4000-8000-000000000007','a7000000-0000-4000-8000-000000000007','b7000000-0000-4000-8000-000000000007',1,'active',6,7,'{}','Seven sessions',now(),current_date);

select is(
  (select array_agg(preferred_weekday order by workout_order) from public.planned_workouts
   where user_id='a5000000-0000-4000-8000-000000000005'),
  array[1,2,3,5,6]::smallint[],
  'five sessions spread across the week instead of stacking on Sunday');
select is(
  (select count(distinct preferred_weekday) from public.planned_workouts
   where user_id='a6000000-0000-4000-8000-000000000006'),
  6::bigint,
  'six sessions use six different weekdays');
select is(
  (select count(*) from public.planned_workouts w
   where w.user_id in ('a5000000-0000-4000-8000-000000000005','a6000000-0000-4000-8000-000000000006','a7000000-0000-4000-8000-000000000007')
     and not exists (
       select 1 from public.planned_exercises e
       where e.planned_workout_id=w.id and e.exercise_order=1
         and e.display_name_snapshot = case w.name
           when 'Push day' then 'Incline dumbbell press'
           when 'Pull day' then 'Lat pulldown'
           when 'Leg day' then 'Leg press' end)),
  0::bigint,
  'every seeded workout name matches its exercises');
select ok(
  not has_function_privilege('authenticated','private.planned_workout_for_date(uuid,date)','execute'),
  'clients cannot call the workout lookup directly');

set local role authenticated;
set local "request.jwt.claim.sub"='a5000000-0000-4000-8000-000000000005';
select is(
  public.get_my_daily_brief('2026-10-05'::date)->'today_workout'->>'name',
  'Push day',
  'the brief returns the workout for the requested Monday');
select is(
  public.get_my_daily_brief('2026-10-08'::date)->'today_workout',
  'null'::jsonb,
  'a rest day in the requested week has no workout');

set local "request.jwt.claim.sub"='a7000000-0000-4000-8000-000000000007';
select is(
  (public.get_my_daily_brief(current_date + 1)->'today_workout'->>'weekday')::integer,
  extract(isodow from current_date + 1)::integer,
  'the brief follows target_date, not the server date');
select is(
  jsonb_array_length(public.get_my_daily_brief(current_date + 1)->'today_workout'->'exercises') > 0,
  true,
  'the brief workout carries its exercises');
select is(
  (public.get_my_training_hub(28)->'today_workout'->>'weekday')::integer,
  extract(isodow from current_date)::integer,
  'the training hub keeps using the server date for its own today_workout');

select * from finish();
rollback;
