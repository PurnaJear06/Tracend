begin;
select plan(22);

insert into auth.users(id,role) values
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','authenticated'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','authenticated');
insert into public.training_plans(id,user_id,title,source) values
 ('c1000000-0000-4000-8000-000000000001','cccccccc-cccc-4ccc-8ccc-cccccccccccc','Owner plan','user'),
 ('d1000000-0000-4000-8000-000000000001','dddddddd-dddd-4ddd-8ddd-dddddddddddd','Other plan','user');
insert into public.training_plan_versions(id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,prescription,rationale,approved_at,effective_date) values
 ('c2000000-0000-4000-8000-000000000002','cccccccc-cccc-4ccc-8ccc-cccccccccccc','c1000000-0000-4000-8000-000000000001',1,'active',6,3,'{}','Approved owner plan',now(),current_date),
 ('d2000000-0000-4000-8000-000000000002','dddddddd-dddd-4ddd-8ddd-dddddddddddd','d1000000-0000-4000-8000-000000000001',1,'active',6,3,'{}','Approved other plan',now(),current_date);

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid=any(array[
 'public.planned_workouts'::regclass,'public.planned_exercises'::regclass,'public.workout_sessions'::regclass,
 'public.exercise_performances'::regclass,'public.exercise_sets'::regclass,'public.workout_amendments'::regclass,'public.daily_check_ins'::regclass])),
 'all Phase 3 user tables enable and force RLS');
select is((select count(*) from public.planned_workouts where user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'),3::bigint,'active plan creates the prescribed session count');
select is((select count(*) from public.planned_exercises pe join public.planned_workouts pw on pw.id=pe.planned_workout_id where pw.user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'),10::bigint,'approved workouts contain ordered exercise prescriptions');
select ok(not has_table_privilege('anon','public.workout_sessions','select'),'anonymous cannot read workout sessions');
select ok(not has_table_privilege('authenticated','public.exercise_sets','insert'),'clients cannot bypass workout sync RPC');
select ok(has_function_privilege('authenticated','public.start_workout(uuid,date,text,uuid)','execute'),'authenticated users can start workouts through RPC');

set local role authenticated;
set local "request.jwt.claim.sub"='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
select is((select count(*) from public.planned_workouts),3::bigint,'owner reads only own approved workouts');
select throws_ok($$select public.start_workout((select id from public.planned_workouts where user_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd' limit 1),current_date,'Asia/Kolkata','c3000000-0000-4000-8000-000000000003')$$,'P0002',null,'cross-user workout cannot start');
select lives_ok($$select public.start_workout((select id from public.planned_workouts where user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' order by workout_order limit 1),current_date,'Asia/Kolkata','c3000000-0000-4000-8000-000000000003')$$,'owner can start approved workout');
select is((select count(*) from public.workout_sessions),1::bigint,'owner sees one in-progress session');
select is((select count(*) from public.exercise_sets),12::bigint,'start creates each prescribed set exactly once');
select lives_ok($$select public.start_workout((select id from public.planned_workouts where user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' order by workout_order limit 1),current_date,'Asia/Kolkata','c3000000-0000-4000-8000-000000000003')$$,'start retry is idempotent');
select is((select count(*) from public.exercise_sets),12::bigint,'start retry does not duplicate sets');
select lives_ok($$select public.sync_workout_draft((select id from public.workout_sessions),1,'{"exercises":[{"order":1,"pain_flag":false,"sets":[{"number":1,"repetitions":10,"load_kg":20,"rpe":8,"completed":true}]}]}'::jsonb)$$,'draft sync accepts bounded set data');
select is((select count(*) from public.exercise_sets where completed),1::bigint,'synced set is persisted once');
select is((select public.sync_workout_draft((select id from public.workout_sessions),1,'{"exercises":[]}'::jsonb)->>'replayed'),'true','same revision replays safely');
select lives_ok($$select public.complete_workout((select id from public.workout_sessions),1,1800,4::smallint,8::numeric,'Normal session')$$,'workout completion is transactional');
select is((select state::text from public.workout_sessions),'completed','completed workout becomes immutable');
select throws_ok($$select public.sync_workout_draft((select id from public.workout_sessions),2,'{"exercises":[]}'::jsonb)$$,'55000',null,'completed workout rejects normal edits');
select lives_ok($$select public.save_daily_check_in(current_date,'Asia/Kolkata','c4000000-0000-4000-8000-000000000004','{"sleep_quality":4,"energy":4,"soreness":2,"hunger":3,"mood":4,"pain_severity":0,"available_to_train":true}'::jsonb)$$,'bounded daily check-in is saved');
select is((select count(*) from public.daily_check_ins),1::bigint,'owner sees only their check-in');
select is((select count(*) from public.audit_events where action_code='workout.completed'),1::bigint,'completion creates one audit event');

select * from finish();
rollback;
