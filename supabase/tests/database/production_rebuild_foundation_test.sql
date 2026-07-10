begin;
select plan(26);

insert into auth.users(id,role) values
 ('aaaaaaaa-1111-4111-8111-111111111111','authenticated'),
 ('bbbbbbbb-2222-4222-8222-222222222222','authenticated');
insert into public.training_plans(id,user_id,title,source) values
 ('aaaaaaaa-3111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111','Owner approved split','imported');
insert into public.training_plan_versions(
 id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
 prescription,rationale,approved_at,effective_date)
values(
 'aaaaaaaa-4111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
 'aaaaaaaa-3111-4111-8111-111111111111',1,'active',8,6,'{}',
 'Owner approved plan',now(),current_date);
insert into public.planned_workouts(
 user_id,plan_version_id,workout_order,name,objective,preferred_weekday,
 estimated_minutes,warm_up_guidance,cool_down_guidance)
select 'aaaaaaaa-1111-4111-8111-111111111111',
 'aaaaaaaa-4111-4111-8111-111111111111',day,'Workout '||day,
 'Approved objective',day,60,'Warm up progressively','Complete planned cardio'
from generate_series(1,6) day;
insert into public.nutrition_target_sets(
 id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
 rationale,approved_at,effective_date)
values(
 'aaaaaaaa-5111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
 1,'active',2400,170,280,70,'Owner approved targets',now(),current_date);

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
 where oid=any(array['public.coach_threads'::regclass,
 'public.coach_messages'::regclass,'public.nutrition_schedule_versions'::regclass,
 'public.nutrition_schedule_items'::regclass,'public.ai_usage_events'::regclass])),
 'production rebuild tables enable and force RLS');
select ok(not has_table_privilege('authenticated','public.coach_messages','insert'),
 'mobile cannot forge assistant messages');
select ok(has_function_privilege('authenticated','public.get_my_training_hub(integer)','execute'),
 'authenticated owner can read training hub');
select ok(not has_function_privilege('authenticated',
 'public.persist_coach_chat_result(uuid,uuid,text,uuid,uuid,uuid,jsonb,integer,text,text,integer,integer,numeric)','execute'),
 'mobile cannot persist model output');
select ok(has_function_privilege('authenticated',
 'public.create_meal_photo_draft(date,text,text,uuid,text,text,integer,text)','execute'),
 'authenticated owner may register a purpose-bound meal draft');
select ok(not has_function_privilege('authenticated',
 'public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text)','execute'),
 'mobile cannot forge meal vision candidates');
select ok(has_function_privilege('service_role',
 'public.record_ai_usage_event(uuid,text,text,text,integer,integer,numeric,integer)','execute'),
 'service boundary records sanitized vision usage');

set local role authenticated;
set local "request.jwt.claim.sub"='aaaaaaaa-1111-4111-8111-111111111111';
create temporary table thread_result as
 select public.create_coach_thread('Training questions') id;
grant select on thread_result to service_role;
select ok((select id is not null from thread_result),'owner creates a chat thread');
select is((select count(*) from public.coach_threads),1::bigint,
 'owner reads the created thread');
create temporary table schedule_result as select public.activate_my_nutrition_schedule(
 'Owner schedule','Reviewed schedule',current_date,
 '[{"slot_key":"pre_workout","label":"Pre-workout","local_time":"07:45","foods":[{"name":"Oats","quantity":"60 g"}]},
   {"slot_key":"post_workout","label":"Post-workout","local_time":"10:00","foods":[{"name":"Meal","quantity":"1 serving"}]}]'::jsonb) id;
select is((select count(*) from public.nutrition_schedule_versions where status='active'),1::bigint,
 'exactly one active meal schedule exists');
select is(jsonb_array_length(public.get_my_nutrition_schedule(current_date)->'items'),2,
 'active schedule returns ordered items');
select is(jsonb_array_length(public.get_my_training_hub(28)->'workouts'),6,
 'training hub returns the full approved split');
select ok(public.get_my_daily_brief(current_date)?'next_meal',
 'daily brief includes the next scheduled meal');
reset role;
insert into public.daily_health_summaries(
 user_id,local_date,timezone,present_types,source_refs,source_checksum,
 completeness,observed_through,last_synced_at,steps)
values(
 'aaaaaaaa-1111-4111-8111-111111111111',current_date-2,'Asia/Kolkata',
 array['steps']::text[],'[]'::jsonb,repeat('a',64),'partial',now(),now(),9000);
set local role authenticated;
set local "request.jwt.claim.sub"='aaaaaaaa-1111-4111-8111-111111111111';
select is((public.get_my_daily_brief(current_date)->'health'->>'local_date')::date,
 current_date-2,'daily brief uses latest recent HealthKit summary when today is empty');
select is((public.get_my_training_hub(28)->'today_workout'),'null'::jsonb,
 'Sunday or unassigned days do not fall back to the first workout in the database');
select is((public.get_my_ai_budget_state()->>'hard_stop_usd')::numeric,5::numeric,
 'budget state exposes the five dollar hard stop');
select is(
 (select foods->0->>'quantity' from public.nutrition_schedule_items
  where slot_key='pre_workout' and user_id='aaaaaaaa-1111-4111-8111-111111111111'
  order by created_at desc limit 1),
 '60 g',
 'manually activated schedules keep their reviewed planned quantities');

set local role service_role;
create temporary table chat_prepared as select public.prepare_coach_chat(
 'aaaaaaaa-1111-4111-8111-111111111111',(select id from thread_result),
 'What should I focus on?','Asia/Kolkata',
 'aaaaaaaa-6111-4111-8111-111111111111') value;
select is((select value->>'replayed' from chat_prepared),'false',
 'new coach request prepares bounded context');
select lives_ok($$select public.persist_coach_chat_result(
 'aaaaaaaa-1111-4111-8111-111111111111',(select id from thread_result),
 'What should I focus on?','aaaaaaaa-6111-4111-8111-111111111111',
 (select (value->>'feature_snapshot_id')::uuid from chat_prepared),
 (select (value->>'policy_evaluation_id')::uuid from chat_prepared),
 '{"answer":"Keep the approved plan.","evidence":[],"missing_data":[],"safety_state":"allowed","suggested_follow_ups":[]}'::jsonb,
 12,'mock','deterministic-chat-fallback-v1',0,0,0)$$,
 'validated chat result persists atomically');
select is((select count(*) from public.coach_messages),2::bigint,
 'one user and one assistant message are stored');
select is((select count(*) from public.model_runs where purpose='coach_chat'),1::bigint,
 'chat usage is recorded without raw prompt telemetry');
select throws_ok($$select public.record_ai_usage_event(
 'aaaaaaaa-1111-4111-8111-111111111111','meal_vision','gemini',
 'gemini-3.1-flash-lite',1,1,0,1)$$,
 '22023','invalid usage event','Flash-Lite usage fails closed');

set local role authenticated;
set local "request.jwt.claim.sub"='bbbbbbbb-2222-4222-8222-222222222222';
select is((select count(*) from public.coach_threads),0::bigint,
 'cross-user thread reads are denied');
select is((select count(*) from public.coach_messages),0::bigint,
 'cross-user message reads are denied');
select is(jsonb_array_length(public.get_my_training_hub(28)->'workouts'),0,
 'cross-user training hub cannot expose another plan');
select throws_ok(
 $$select public.delete_coach_thread((select id from thread_result))$$,
 'P0002','thread not found','cross-user thread deletion is denied');

select * from finish();
rollback;
