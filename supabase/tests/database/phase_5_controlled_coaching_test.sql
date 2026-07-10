begin;
select plan(20);

insert into auth.users(id,role) values
 ('11111111-aaaa-4111-8111-111111111111','authenticated'),
 ('22222222-bbbb-4222-8222-222222222222','authenticated');
insert into public.training_plans(id,user_id,title,source) values
 ('31111111-aaaa-4111-8111-111111111111','11111111-aaaa-4111-8111-111111111111','Owner plan','mock_ai');
insert into public.training_plan_versions(id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,prescription,rationale,approved_at,effective_date)
 values('41111111-aaaa-4111-8111-111111111111','11111111-aaaa-4111-8111-111111111111','31111111-aaaa-4111-8111-111111111111',1,'active',4,3,'{}','Approved fixture',now(),current_date);
insert into public.nutrition_target_sets(id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,rationale,approved_at,effective_date)
 values('51111111-aaaa-4111-8111-111111111111','11111111-aaaa-4111-8111-111111111111',1,'active',2200,150,240,70,'Approved fixture',now(),current_date);

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid=any(array[
 'public.policy_evaluations'::regclass,'public.model_runs'::regclass,'public.coach_decisions'::regclass])),
 'Phase 5 tables enable and force RLS');
select ok(not has_table_privilege('authenticated','public.coach_decisions','insert'),
 'mobile cannot persist decisions');
select ok(not has_function_privilege('authenticated','public.prepare_daily_coaching(uuid,date,text,uuid)','execute'),
 'mobile cannot prepare trusted snapshots');
select ok(has_function_privilege('service_role','public.prepare_daily_coaching(uuid,date,text,uuid)','execute'),
 'service role can prepare snapshots');
select ok(has_function_privilege('authenticated','public.get_my_ai_usage()','execute'),
 'authenticated owner can read sanitized usage');
select ok(not has_function_privilege('authenticated','public.persist_failed_coaching_run(uuid,uuid,uuid,uuid,integer,text)','execute'),
 'mobile cannot forge failed provider runs');

set local role service_role;
create temporary table prepared as select public.prepare_daily_coaching(
 '11111111-aaaa-4111-8111-111111111111','2026-07-02','Asia/Kolkata','61111111-aaaa-4111-8111-111111111111') value;
select is((select value->>'policy_outcome' from prepared),'request_data',
 'missing check-in deterministically requests data');
select is((select count(*) from public.feature_snapshots where trigger_kind='daily'),1::bigint,
 'daily feature snapshot is immutable and stored');
select is((select count(*) from public.policy_evaluations),1::bigint,
 'policy evaluation is stored');

create temporary table persisted as select public.persist_daily_coaching_result(
 '11111111-aaaa-4111-8111-111111111111',
 (select (value->>'feature_snapshot_id')::uuid from prepared),
 (select (value->>'policy_evaluation_id')::uuid from prepared),
 '61111111-aaaa-4111-8111-111111111111',
 '{"schema_version":"1.0","decision_kind":"daily","local_date":"2026-07-02",
   "training":{"action":"GATHER_DATA","summary":"Add a check-in.","today_adjustments":[]},
   "nutrition":{"action":"MAINTAIN_TARGETS","summary":"Keep approved targets.","today_adjustments":[]},
   "head_coach":{"final_decision":"Keep the approved plan.","reason":"Current recovery evidence is incomplete."},
   "evidence":[],"confidence":"low","missing_data":["recovery_check_in"],"risk_flags":[],"change_proposals":[]}'::jsonb,4) value;
select is((select count(*) from public.model_runs),1::bigint,'validated run is stored once');
select is((select count(*) from public.coach_decisions),1::bigint,'validated decision is stored once');
select is((select count(*) from public.audit_events where action_code='coach.decision.created'),1::bigint,
 'successful decision writes one sanitized audit event');
select lives_ok($$select public.persist_daily_coaching_result(
 '11111111-aaaa-4111-8111-111111111111',
 (select (value->>'feature_snapshot_id')::uuid from prepared),
 (select (value->>'policy_evaluation_id')::uuid from prepared),
 '61111111-aaaa-4111-8111-111111111111',
 '{"schema_version":"1.0","decision_kind":"daily","local_date":"2026-07-02",
 "training":{"action":"GATHER_DATA"},"nutrition":{},"head_coach":{},"evidence":[],
 "confidence":"low","missing_data":[],"risk_flags":[],"change_proposals":[]}'::jsonb,4)$$,
 'idempotent replay does not duplicate the decision');
select is((select count(*) from public.coach_decisions),1::bigint,'replay remains single');
select lives_ok($$select public.persist_failed_coaching_run(
 '11111111-aaaa-4111-8111-111111111111',
 (select (value->>'feature_snapshot_id')::uuid from prepared),
 (select (value->>'policy_evaluation_id')::uuid from prepared),
 '71111111-aaaa-4111-8111-111111111111',3,'provider_or_validation_failed')$$,
 'sanitized provider failure is recorded without a decision');
select is((select count(*) from public.audit_events where action_code='coach.model_run.failed'),1::bigint,
 'failed provider run writes one sanitized audit event');

set local role authenticated;
set local "request.jwt.claim.sub"='11111111-aaaa-4111-8111-111111111111';
select is((select count(*) from public.coach_decisions),1::bigint,'owner reads own decision');
select is((public.get_my_ai_usage()->>'successful_runs')::integer,1,'usage is owner-scoped and sanitized');
set local "request.jwt.claim.sub"='22222222-bbbb-4222-8222-222222222222';
select is((select count(*) from public.coach_decisions),0::bigint,'cross-user decision read is denied');
select is((public.get_my_ai_usage()->>'successful_runs')::integer,0,'cross-user usage is empty');

select * from finish();
rollback;
