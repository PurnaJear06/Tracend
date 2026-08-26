-- persist_daily_coaching_result_v2 validates cited evidence against a narrow per-outcome whitelist
-- (2-4 codes), while prepare_daily_coaching permits up to 17 computed-score evidence codes and the
-- DeepSeek prompt teaches all 17. Any decision citing a permitted-but-unlisted code (e.g.
-- DATA_CONFIDENCE_LOW, TRAINING_LOAD_OPTIMAL, WEIGHT_STABLE) was rejected with 'unsupported
-- evidence' (22023) -> 422 decision_rejected, so no live daily decision has ever persisted.
-- The deterministic engine's permitted_evidence output is the source of truth for legitimate codes;
-- persist now accepts the full 17-code set for every outcome and still rejects fabricated codes.
-- Additive: CREATE OR REPLACE preserves signatures, ownership, and grants.

create or replace function public.persist_daily_coaching_result_v2(
  target_user_id uuid,snapshot_id uuid,policy_id uuid,request_idempotency_key uuid,
  decision_payload jsonb,run_latency_ms integer,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric
) returns jsonb language plpgsql security definer set search_path='' as $$
declare run_id uuid; decision_id uuid; policy public.policy_evaluations%rowtype;
begin
  select * into policy from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id;
  if not found then raise exception 'policy not found' using errcode='P0002'; end if;
  if run_provider not in ('mock','gemini','groq','deepseek') or length(run_model) not between 1 and 120
    or run_input_units not between 0 and 1000000 or run_output_units not between 0 and 100000
    or run_estimated_cost_usd < 0 or run_estimated_cost_usd > 100
  then raise exception 'invalid provider metadata' using errcode='22023'; end if;
  if jsonb_typeof(decision_payload)<>'object' or decision_payload->>'schema_version'<>'1.0'
    or decision_payload->>'decision_kind'<>'daily' or jsonb_array_length(decision_payload->'change_proposals')<>0
  then raise exception 'invalid decision' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(decision_payload->'evidence') e where not (e->>'code'=any(array[
    'APPROVED_PLAN_ACTIVE','CHECK_IN_SAFETY_ESCALATION','HEALTH_CONTEXT_AVAILABLE',
    'RECOVERY_WITHIN_BASELINE','RECOVERY_BELOW_BASELINE','CHECK_IN_RECOVERY_MIXED',
    'SLEEP_QUALITY_GOOD','SLEEP_QUALITY_POOR',
    'TRAINING_LOAD_OPTIMAL','TRAINING_LOAD_ELEVATED',
    'WEIGHT_TRENDING_DOWN','WEIGHT_TRENDING_UP','WEIGHT_STABLE',
    'NUTRITION_ON_TRACK','NUTRITION_BEHIND',
    'DATA_CONFIDENCE_HIGH','DATA_CONFIDENCE_LOW'])))
  then raise exception 'unsupported evidence' using errcode='22023'; end if;
  insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,provider,model,prompt_version,schema_version,status,validation_status,input_units,output_units,estimated_cost_usd,latency_ms)
  values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'daily_coaching',run_provider,run_model,'daily-v1','1.0','succeeded','passed',run_input_units,run_output_units,run_estimated_cost_usd,run_latency_ms)
  on conflict(user_id,idempotency_key) do update set idempotency_key=excluded.idempotency_key returning id into run_id;
  select id into decision_id from public.coach_decisions where model_run_id=run_id;
  if decision_id is null then
    insert into public.coach_decisions(user_id,feature_snapshot_id,policy_evaluation_id,model_run_id,decision_kind,local_date,schema_version,training,nutrition,head_coach,evidence,confidence,missing_data,risk_flags,valid_until)
    values(target_user_id,snapshot_id,policy_id,run_id,'daily',(decision_payload->>'local_date')::date,'1.0',decision_payload->'training',decision_payload->'nutrition',decision_payload->'head_coach',decision_payload->'evidence',decision_payload->>'confidence',array(select jsonb_array_elements_text(decision_payload->'missing_data')),array(select jsonb_array_elements_text(decision_payload->'risk_flags')),now()+interval '24 hours') returning id into decision_id;
    insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
    values(target_user_id,'coach.decision.created','coach_decision',decision_id,'succeeded',jsonb_build_object('policy_outcome',policy.outcome,'schema_version','1.0','provider',run_provider,'model',run_model));
  end if;
  return jsonb_build_object('decision_id',decision_id,'model_run_id',run_id,'replayed',false);
end $$;
