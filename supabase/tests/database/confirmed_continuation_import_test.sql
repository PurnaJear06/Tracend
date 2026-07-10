begin;
select plan(17);

insert into auth.users(id,role) values
 ('b1111111-aaaa-4111-8111-111111111111','authenticated'),
 ('b2222222-bbbb-4222-8222-222222222222','authenticated');
insert into public.user_profiles(
 user_id,adult_attested_at,eligible,experience_level,height_cm,training_days,session_minutes)
values(
 'b1111111-aaaa-4111-8111-111111111111',now(),true,'beginner',null,
 array[1,2,3]::smallint[],60);
insert into public.training_plans(id,user_id,title,source) values
 ('b3111111-aaaa-4111-8111-111111111111','b1111111-aaaa-4111-8111-111111111111','Fixture plan','mock_ai');
insert into public.training_plan_versions(
 id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
 prescription,rationale,approved_at,effective_date)
values(
 'b4111111-aaaa-4111-8111-111111111111','b1111111-aaaa-4111-8111-111111111111',
 'b3111111-aaaa-4111-8111-111111111111',1,'active',4,3,'{}','Fixture',now(),current_date);
insert into public.nutrition_target_sets(
 id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
 rationale,approved_at,effective_date)
values(
 'b5111111-aaaa-4111-8111-111111111111','b1111111-aaaa-4111-8111-111111111111',
 1,'active',2600,174,319,70,'Fixture',now(),current_date);
insert into public.body_measurements(id,user_id,measured_on,source,weight_kg)
values(
 'b6111111-aaaa-4111-8111-111111111111','b1111111-aaaa-4111-8111-111111111111',
 current_date-1,'manual',60);

select ok(has_function_privilege(
 'service_role',
 'public.import_confirmed_continuation(uuid,jsonb,jsonb,jsonb,jsonb,jsonb,uuid[])',
 'execute'),'service role can run confirmed import');
select ok(not has_function_privilege(
 'authenticated',
 'public.import_confirmed_continuation(uuid,jsonb,jsonb,jsonb,jsonb,jsonb,uuid[])',
 'execute'),'mobile cannot invoke administrative import');

set local role service_role;
select lives_ok($$select public.import_confirmed_continuation(
 'b1111111-aaaa-4111-8111-111111111111',
 '{"experience_level":"advanced","height_cm":180,"training_days":[1,2,3,4,5,6],"session_minutes":60}',
 '{"goal_type":"fat_loss","details":{"source":"owner_confirmed"}}',
 '{"title":"Confirmed cut","block_weeks":16,"effective_date":"2026-06-03",
   "rationale":"Continue owner-confirmed training.","strategy":"preserve_confirmed_work",
   "weekly_structure":[{"workout_order":1,"name":"Push heavy","objective":"Chest priority",
   "preferred_weekday":1,"estimated_minutes":60,"warm_up_guidance":"Warm up progressively.",
   "cool_down_guidance":"Cool down comfortably.","exercises":[
   {"exercise_order":1,"name":"Main chest press","sets":3,"rep_min":6,"rep_max":10,
   "target_rpe":8,"rest_seconds":120,"notes":"Stop with one or two reps in reserve."}]}]}',
 '{"calories":1900,"protein_g":185,"carbohydrate_g":150,"fat_g":50,
   "effective_date":"2026-06-03","rationale":"Continue confirmed aggressive cut."}',
 '[{"measured_on":"2026-06-03","weight_kg":90},{"measured_on":"2026-07-04","weight_kg":86.2}]',
 array['b6111111-aaaa-4111-8111-111111111111']::uuid[])$$,
 'confirmed continuation import succeeds atomically');

select is((select experience_level::text from public.user_profiles
 where user_id='b1111111-aaaa-4111-8111-111111111111'),'advanced','experience is corrected');
select is((select height_cm from public.user_profiles
 where user_id='b1111111-aaaa-4111-8111-111111111111'),180::numeric,'height is stored canonically');
select is((select cardinality(training_days) from public.user_profiles
 where user_id='b1111111-aaaa-4111-8111-111111111111'),6,'six training days are stored');
select is((select count(*) from public.user_goals where user_id='b1111111-aaaa-4111-8111-111111111111' and status='active'),1::bigint,'one active goal remains');
select is((select count(*) from public.training_plan_versions where user_id='b1111111-aaaa-4111-8111-111111111111' and status='active'),1::bigint,'one active plan remains');
select is((select status::text from public.training_plan_versions where id='b4111111-aaaa-4111-8111-111111111111'),'superseded','fixture plan is retained as superseded');
select is((select p.source from public.training_plans p join public.training_plan_versions v
 on v.plan_id=p.id and v.user_id=p.user_id where p.user_id='b1111111-aaaa-4111-8111-111111111111'
 and v.status='active'),'imported','confirmed plan provenance is imported');
select is((select calories from public.nutrition_target_sets where user_id='b1111111-aaaa-4111-8111-111111111111' and status='active'),1900,'confirmed calories are active');
select is((select protein_g from public.nutrition_target_sets where user_id='b1111111-aaaa-4111-8111-111111111111' and status='active'),185,'confirmed protein midpoint is active');
select ok((select superseded_at is not null from public.body_measurements where id='b6111111-aaaa-4111-8111-111111111111'),'fixture measurement is explicitly superseded');
select is((select count(*) from public.body_measurements where user_id='b1111111-aaaa-4111-8111-111111111111' and superseded_at is null),2::bigint,'confirmed measurements replace fixture trend inputs');
select is((select count(*) from public.audit_events where user_id='b1111111-aaaa-4111-8111-111111111111' and action_code='owner.confirmed_context_imported'),1::bigint,'one sanitized import audit event is written');

set local role authenticated;
set local "request.jwt.claim.sub"='b1111111-aaaa-4111-8111-111111111111';
select is((public.get_my_progress_summary()->>'current_weight_kg')::numeric,86.2::numeric,'summary uses confirmed current weight');
select is((public.get_my_progress_summary()->>'weight_change_kg')::numeric,-3.8::numeric,'summary excludes superseded fixture weight');

select * from finish();
rollback;
