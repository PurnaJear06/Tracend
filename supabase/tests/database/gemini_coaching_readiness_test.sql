begin;
select plan(11);

insert into auth.users(id,role) values
 ('a1111111-aaaa-4111-8111-111111111111','authenticated');
insert into public.training_plans(id,user_id,title,source) values
 ('a3111111-aaaa-4111-8111-111111111111','a1111111-aaaa-4111-8111-111111111111','Owner plan','mock_ai');
insert into public.training_plan_versions(
 id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
 prescription,rationale,approved_at,effective_date)
values(
 'a4111111-aaaa-4111-8111-111111111111','a1111111-aaaa-4111-8111-111111111111',
 'a3111111-aaaa-4111-8111-111111111111',1,'active',4,3,'{}','Approved fixture',
 now(),current_date);
insert into public.nutrition_target_sets(
 id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
 rationale,approved_at,effective_date)
values(
 'a5111111-aaaa-4111-8111-111111111111','a1111111-aaaa-4111-8111-111111111111',
 1,'active',2200,150,240,70,'Approved fixture',now(),current_date);

select ok(
 has_function_privilege(
   'service_role',
   'public.persist_daily_coaching_result_v2(uuid,uuid,uuid,uuid,jsonb,integer,text,text,integer,integer,numeric)',
   'execute'),
 'service role can persist provider-aware coaching');
select ok(
 not has_function_privilege(
   'authenticated',
   'public.persist_daily_coaching_result_v2(uuid,uuid,uuid,uuid,jsonb,integer,text,text,integer,integer,numeric)',
   'execute'),
 'mobile cannot persist provider-aware coaching');
select ok(
 not has_function_privilege(
   'authenticated',
   'public.persist_failed_coaching_run_v2(uuid,uuid,uuid,uuid,integer,text,text,text)',
   'execute'),
 'mobile cannot forge provider-aware failures');

set local role service_role;
create temporary table prepared as select public.prepare_daily_coaching(
 'a1111111-aaaa-4111-8111-111111111111','2026-07-03','Asia/Kolkata',
 'a6111111-aaaa-4111-8111-111111111111') value;

select lives_ok($$select public.persist_daily_coaching_result_v2(
 'a1111111-aaaa-4111-8111-111111111111',
 (select (value->>'feature_snapshot_id')::uuid from prepared),
 (select (value->>'policy_evaluation_id')::uuid from prepared),
 'a6111111-aaaa-4111-8111-111111111111',
 '{"schema_version":"1.0","decision_kind":"daily","local_date":"2026-07-03",
   "training":{"action":"GATHER_DATA","summary":"Add a check-in.","today_adjustments":[]},
   "nutrition":{"action":"MAINTAIN_TARGETS","summary":"Keep approved targets.","today_adjustments":[]},
   "head_coach":{"final_decision":"Keep the approved plan.","reason":"Recovery evidence is incomplete."},
   "evidence":[],"confidence":"low","missing_data":["recovery_check_in"],
   "risk_flags":[],"change_proposals":[]}'::jsonb,
 125,'gemini','synthetic-model',320,84,0.000123)$$,
 'validated Gemini metadata is stored with a decision');
select is((select provider from public.model_runs limit 1),'gemini',
 'provider is persisted');
select is((select model from public.model_runs limit 1),'synthetic-model',
 'model is persisted');
select is((select input_units from public.model_runs limit 1),320,
 'input usage is persisted');
select is((select output_units from public.model_runs limit 1),84,
 'output usage is persisted');
select is((select estimated_cost_usd from public.model_runs limit 1),0.000123::numeric,
 'estimated cost is persisted');
select throws_ok($$select public.persist_failed_coaching_run_v2(
 'a1111111-aaaa-4111-8111-111111111111',
 (select (value->>'feature_snapshot_id')::uuid from prepared),
 (select (value->>'policy_evaluation_id')::uuid from prepared),
 'a7111111-aaaa-4111-8111-111111111111',3,
 'provider_or_validation_failed','unknown','model')$$,
 '22023','invalid failure metadata','unknown providers are rejected');
select throws_ok($$select public.persist_daily_coaching_result_v2(
 'a1111111-aaaa-4111-8111-111111111111',
 (select (value->>'feature_snapshot_id')::uuid from prepared),
 (select (value->>'policy_evaluation_id')::uuid from prepared),
 'a8111111-aaaa-4111-8111-111111111111','{}'::jsonb,1,
 'gemini','model',-1,0,0)$$,
 '22023','invalid provider metadata','negative usage is rejected');

select * from finish();
rollback;
