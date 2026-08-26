begin;
select plan(11);

insert into auth.users(id,role) values
  ('e1111111-aaaa-4111-8111-111111111111','authenticated');

insert into public.training_plans(id,user_id,title,source) values
  ('e3111111-aaaa-4111-8111-111111111111','e1111111-aaaa-4111-8111-111111111111','Owner plan','mock_ai');
insert into public.training_plan_versions(
  id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
  prescription,rationale,approved_at,effective_date)
values(
  'e4111111-aaaa-4111-8111-111111111111','e1111111-aaaa-4111-8111-111111111111',
  'e3111111-aaaa-4111-8111-111111111111',1,'active',4,3,'{}','Approved fixture',
  now(),current_date);
insert into public.nutrition_target_sets(
  id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
  rationale,approved_at,effective_date)
values(
  'e5111111-aaaa-4111-8111-111111111111','e1111111-aaaa-4111-8111-111111111111',
  1,'active',2200,150,240,70,'Approved fixture',now(),current_date);

insert into public.daily_check_ins(
  user_id,local_date,timezone,revision,idempotency_key,
  sleep_quality,energy,soreness,hunger,mood,pain_severity,available_to_train,note)
values
  ('e1111111-aaaa-4111-8111-111111111111',current_date,'Asia/Kolkata',1,gen_random_uuid(),
   3,4,2,3,4,1,true,''),
  ('e1111111-aaaa-4111-8111-111111111111',current_date-1,'Asia/Kolkata',1,gen_random_uuid(),
   2,2,4,3,2,8,false,'');

set local role service_role;

-- maintain_only scenario: check-in present, low pain
create temporary table prep_maintain as select public.prepare_daily_coaching(
  'e1111111-aaaa-4111-8111-111111111111',current_date,'Asia/Kolkata',
  'e6111111-aaaa-4111-8111-111111111111') value;
select is((select value->>'policy_outcome' from prep_maintain),'maintain_only',
  'low-pain check-in yields maintain_only outcome');

-- All 17 evidence codes the deterministic engine can permit must persist.
select lives_ok($$select public.persist_daily_coaching_result_v2(
  'e1111111-aaaa-4111-8111-111111111111',
  (select (value->>'feature_snapshot_id')::uuid from prep_maintain),
  (select (value->>'policy_evaluation_id')::uuid from prep_maintain),
  'e6111111-aaaa-4111-8111-111111111111',
  ('{"schema_version":"1.0","decision_kind":"daily","local_date":"'||current_date||'",
    "training":{"action":"PROCEED_AS_PLANNED","summary":"Proceed.","today_adjustments":[]},
    "nutrition":{"action":"MAINTAIN_TARGETS","summary":"Maintain.","today_adjustments":[]},
    "head_coach":{"final_decision":"Keep the approved plan.","reason":"Full evidence set."},
    "evidence":[
      {"code":"APPROVED_PLAN_ACTIVE","label":"Approved plan active","source":"policy_evaluation"},
      {"code":"CHECK_IN_SAFETY_ESCALATION","label":"Safety escalation","source":"feature_snapshot"},
      {"code":"HEALTH_CONTEXT_AVAILABLE","label":"Health context","source":"feature_snapshot"},
      {"code":"RECOVERY_WITHIN_BASELINE","label":"Recovery within baseline","source":"feature_snapshot"},
      {"code":"RECOVERY_BELOW_BASELINE","label":"Recovery below baseline","source":"feature_snapshot"},
      {"code":"CHECK_IN_RECOVERY_MIXED","label":"Mixed recovery","source":"feature_snapshot"},
      {"code":"SLEEP_QUALITY_GOOD","label":"Sleep good","source":"feature_snapshot"},
      {"code":"SLEEP_QUALITY_POOR","label":"Sleep poor","source":"feature_snapshot"},
      {"code":"TRAINING_LOAD_OPTIMAL","label":"Load optimal","source":"feature_snapshot"},
      {"code":"TRAINING_LOAD_ELEVATED","label":"Load elevated","source":"feature_snapshot"},
      {"code":"WEIGHT_TRENDING_DOWN","label":"Weight trending down","source":"feature_snapshot"},
      {"code":"WEIGHT_TRENDING_UP","label":"Weight trending up","source":"feature_snapshot"},
      {"code":"WEIGHT_STABLE","label":"Weight stable","source":"feature_snapshot"},
      {"code":"NUTRITION_ON_TRACK","label":"Nutrition on track","source":"feature_snapshot"},
      {"code":"NUTRITION_BEHIND","label":"Nutrition behind","source":"feature_snapshot"},
      {"code":"DATA_CONFIDENCE_HIGH","label":"Confidence high","source":"feature_snapshot"},
      {"code":"DATA_CONFIDENCE_LOW","label":"Confidence low","source":"feature_snapshot"}],
    "confidence":"low","missing_data":[],"risk_flags":[],"change_proposals":[]}')::jsonb,
  125,'deepseek','synthetic-model',320,84,0.000123)$$,
  'all 17 permitted evidence codes persist under maintain_only');

select is((select jsonb_array_length(evidence) from public.coach_decisions
  where user_id='e1111111-aaaa-4111-8111-111111111111' and local_date=current_date),17,
  'decision stores the full 17-code evidence array');
select is((select status from public.model_runs
  where user_id='e1111111-aaaa-4111-8111-111111111111' and idempotency_key='e6111111-aaaa-4111-8111-111111111111'),
  'succeeded','model run is marked succeeded');
select is((select provider from public.model_runs
  where user_id='e1111111-aaaa-4111-8111-111111111111' and idempotency_key='e6111111-aaaa-4111-8111-111111111111'),
  'deepseek','provider is persisted');
select ok(exists(select 1 from public.audit_events
  where user_id='e1111111-aaaa-4111-8111-111111111111' and action_code='coach.decision.created'),
  'audit event records decision creation');

-- Fabricated codes outside the engine's 17-code set must still be rejected.
select throws_ok($$select public.persist_daily_coaching_result_v2(
  'e1111111-aaaa-4111-8111-111111111111',
  (select (value->>'feature_snapshot_id')::uuid from prep_maintain),
  (select (value->>'policy_evaluation_id')::uuid from prep_maintain),
  'e7111111-aaaa-4111-8111-111111111111',
  ('{"schema_version":"1.0","decision_kind":"daily","local_date":"'||current_date||'",
    "training":{"action":"PROCEED_AS_PLANNED","summary":"Proceed.","today_adjustments":[]},
    "nutrition":{"action":"MAINTAIN_TARGETS","summary":"Maintain.","today_adjustments":[]},
    "head_coach":{"final_decision":"Keep the approved plan.","reason":"Fabricated evidence."},
    "evidence":[{"code":"FABRICATED_EVIDENCE_CODE","label":"Fabricated","source":"feature_snapshot"}],
    "confidence":"low","missing_data":[],"risk_flags":[],"change_proposals":[]}')::jsonb,
  125,'deepseek','synthetic-model',320,84,0.000123)$$,
  '22023','unsupported evidence','fabricated evidence codes are still rejected');

-- escalate scenario: high-pain check-in
create temporary table prep_escalate as select public.prepare_daily_coaching(
  'e1111111-aaaa-4111-8111-111111111111',current_date-1,'Asia/Kolkata',
  'e8111111-aaaa-4111-8111-111111111111') value;
select is((select value->>'policy_outcome' from prep_escalate),'escalate',
  'high-pain check-in yields escalate outcome');

-- Codes the old narrow escalate whitelist rejected must now persist.
select lives_ok($$select public.persist_daily_coaching_result_v2(
  'e1111111-aaaa-4111-8111-111111111111',
  (select (value->>'feature_snapshot_id')::uuid from prep_escalate),
  (select (value->>'policy_evaluation_id')::uuid from prep_escalate),
  'e8111111-aaaa-4111-8111-111111111111',
  ('{"schema_version":"1.0","decision_kind":"daily","local_date":"'||(current_date-1)||'",
    "training":{"action":"ESCALATE","summary":"Escalate.","today_adjustments":[]},
    "nutrition":{"action":"ESCALATE","summary":"Escalate.","today_adjustments":[]},
    "head_coach":{"final_decision":"Escalate for safety.","reason":"High pain reported."},
    "evidence":[
      {"code":"CHECK_IN_SAFETY_ESCALATION","label":"Safety escalation","source":"feature_snapshot"},
      {"code":"DATA_CONFIDENCE_LOW","label":"Confidence low","source":"feature_snapshot"},
      {"code":"SLEEP_QUALITY_POOR","label":"Sleep poor","source":"feature_snapshot"}],
    "confidence":"low","missing_data":[],"risk_flags":[],"change_proposals":[]}')::jsonb,
  125,'deepseek','synthetic-model',320,84,0.000123)$$,
  'computed-score codes persist under escalate outcome');

-- request_data scenario: no check-in
create temporary table prep_request as select public.prepare_daily_coaching(
  'e1111111-aaaa-4111-8111-111111111111',current_date-2,'Asia/Kolkata',
  'e9111111-aaaa-4111-8111-111111111111') value;
select is((select value->>'policy_outcome' from prep_request),'request_data',
  'missing check-in yields request_data outcome');

-- Codes the old narrow request_data whitelist rejected must now persist.
select lives_ok($$select public.persist_daily_coaching_result_v2(
  'e1111111-aaaa-4111-8111-111111111111',
  (select (value->>'feature_snapshot_id')::uuid from prep_request),
  (select (value->>'policy_evaluation_id')::uuid from prep_request),
  'e9111111-aaaa-4111-8111-111111111111',
  ('{"schema_version":"1.0","decision_kind":"daily","local_date":"'||(current_date-2)||'",
    "training":{"action":"GATHER_DATA","summary":"Add a check-in.","today_adjustments":[]},
    "nutrition":{"action":"MAINTAIN_TARGETS","summary":"Maintain.","today_adjustments":[]},
    "head_coach":{"final_decision":"Gather missing data.","reason":"No check-in yet."},
    "evidence":[
      {"code":"APPROVED_PLAN_ACTIVE","label":"Approved plan active","source":"policy_evaluation"},
      {"code":"DATA_CONFIDENCE_LOW","label":"Confidence low","source":"feature_snapshot"},
      {"code":"TRAINING_LOAD_ELEVATED","label":"Load elevated","source":"feature_snapshot"}],
    "confidence":"low","missing_data":["recovery_check_in"],"risk_flags":[],"change_proposals":[]}')::jsonb,
  125,'deepseek','synthetic-model',320,84,0.000123)$$,
  'computed-score codes persist under request_data outcome');

select * from finish();
rollback;
