begin;
select plan(13);

-- One athlete: a five-session plan (Mon, Tue, Wed, Fri, Sat) that took
-- effect on Monday 21 September 2026. The brief is read for Wednesday
-- 7 October, in the plan's third week.
insert into auth.users(id,role) values
 ('a8100000-0000-4000-8000-000000000081','authenticated'),
 ('a8200000-0000-4000-8000-000000000082','authenticated');
insert into public.training_plans(id,user_id,title,source) values
 ('b8100000-0000-4000-8000-000000000081','a8100000-0000-4000-8000-000000000081','Strength foundation','user');
insert into public.training_plan_versions(id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,prescription,rationale,approved_at,effective_date) values
 ('c8100000-0000-4000-8000-000000000081','a8100000-0000-4000-8000-000000000081','b8100000-0000-4000-8000-000000000081',1,'active',20,5,'{}','Five sessions',now(),'2026-09-21');

insert into public.daily_computed_metrics(user_id,local_date,recovery_score,data_confidence) values
 ('a8100000-0000-4000-8000-000000000081','2026-10-05',64,'medium'),
 ('a8100000-0000-4000-8000-000000000081','2026-10-06',49,'medium');

-- Monday's session is completed; today's (Wednesday) is in progress with
-- two of its first exercise's sets ticked.
insert into public.workout_sessions(id,user_id,plan_version_id,planned_workout_id,local_date,timezone,state,idempotency_key,completed_at)
select 'd8100000-0000-4000-8000-000000000081','a8100000-0000-4000-8000-000000000081',
       'c8100000-0000-4000-8000-000000000081',w.id,'2026-10-05','UTC','completed',
       'e8100000-0000-4000-8000-000000000081',now()
from public.planned_workouts w
where w.user_id='a8100000-0000-4000-8000-000000000081' and w.preferred_weekday=1;
insert into public.workout_sessions(id,user_id,plan_version_id,planned_workout_id,local_date,timezone,state,idempotency_key)
select 'd8200000-0000-4000-8000-000000000082','a8100000-0000-4000-8000-000000000081',
       'c8100000-0000-4000-8000-000000000081',w.id,'2026-10-07','UTC','in_progress',
       'e8200000-0000-4000-8000-000000000082'
from public.planned_workouts w
where w.user_id='a8100000-0000-4000-8000-000000000081' and w.preferred_weekday=3;
insert into public.exercise_performances(id,user_id,workout_session_id,planned_exercise_id,exercise_order)
select 'f8200000-0000-4000-8000-000000000082','a8100000-0000-4000-8000-000000000081',
       'd8200000-0000-4000-8000-000000000082',e.id,1
from public.planned_exercises e
join public.planned_workouts w on w.id=e.planned_workout_id
where w.user_id='a8100000-0000-4000-8000-000000000081' and w.preferred_weekday=3
  and e.exercise_order=1;
insert into public.exercise_sets(user_id,exercise_performance_id,set_number,repetitions,load_kg,completed) values
 ('a8100000-0000-4000-8000-000000000081','f8200000-0000-4000-8000-000000000082',1,8,60,true),
 ('a8100000-0000-4000-8000-000000000081','f8200000-0000-4000-8000-000000000082',2,8,60,true),
 ('a8100000-0000-4000-8000-000000000081','f8200000-0000-4000-8000-000000000082',3,null,null,false);

set local role authenticated;
set local "request.jwt.claim.sub"='a8100000-0000-4000-8000-000000000081';

select is(public.get_my_daily_brief('2026-10-07')->>'schema_version','1.7',
  'brief schema 1.7');
select is(public.get_my_daily_brief('2026-10-07')->'plan'->>'title','Strength foundation',
  'the plan carries its title');
select is((public.get_my_daily_brief('2026-10-07')->'plan'->>'week_number')::integer,3,
  'the week number counts from the effective date');
select is((public.get_my_daily_brief('2026-10-07')->'plan'->>'block_weeks')::integer,20,
  'the plan carries its block length');
select is(jsonb_array_length(public.get_my_daily_brief('2026-10-07')->'week'),7,
  'the week has seven days');
select is(public.get_my_daily_brief('2026-10-07')->'week'->0->>'local_date','2026-10-05',
  'the week starts on Monday');
select is((public.get_my_daily_brief('2026-10-07')->'week'->0->>'recovery')::integer,64,
  'a day carries its stored recovery');
select is(public.get_my_daily_brief('2026-10-07')->'week'->0->'trained','true'::jsonb,
  'a completed session marks the day trained');
select is(public.get_my_daily_brief('2026-10-07')->'week'->3->'planned','false'::jsonb,
  'Thursday has no workout in this plan');
select is((public.get_my_daily_brief('2026-10-07')->>'recovery_previous')::integer,49,
  'yesterday''s recovery is reported');
select is(public.get_my_daily_brief('2026-10-07')->'today_session'->>'state','in_progress',
  'today''s session state is reported');
select is((public.get_my_daily_brief('2026-10-07')->'today_session'->'exercises'->0->>'completed_sets')::integer,2,
  'only ticked sets count as completed');

set local "request.jwt.claim.sub"='a8200000-0000-4000-8000-000000000082';
select is(public.get_my_daily_brief('2026-10-07')->'plan','null'::jsonb,
  'an athlete without a plan gets no plan, and nothing is invented');

select * from finish();
rollback;
