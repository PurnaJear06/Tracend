-- DeepSeek is the active coach provider (COACH_MODEL_PROVIDER=deepseek). The two daily-coaching
-- persistence RPCs still whitelist only ('mock','gemini','groq'), so live DeepSeek runs were rejected
-- with 'invalid provider metadata' (22023). persist_coach_chat_result was already patched in
-- 20260722100000; this brings the daily-coaching RPCs in line. Table CHECK constraints already accept
-- deepseek (20260722150000). Additive: CREATE OR REPLACE preserves signatures, ownership, and grants.

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
  if exists(select 1 from jsonb_array_elements(decision_payload->'evidence') e where not (e->>'code'=any(
    case when policy.outcome='escalate' then array['APPROVED_PLAN_ACTIVE','CHECK_IN_SAFETY_ESCALATION','HEALTH_CONTEXT_AVAILABLE']
    when policy.outcome='request_data' then array['APPROVED_PLAN_ACTIVE','HEALTH_CONTEXT_AVAILABLE']
    else array['APPROVED_PLAN_ACTIVE','RECOVERY_WITHIN_BASELINE','CHECK_IN_RECOVERY_MIXED','HEALTH_CONTEXT_AVAILABLE'] end)))
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

create or replace function public.persist_failed_coaching_run_v2(
  target_user_id uuid,snapshot_id uuid,policy_id uuid,request_idempotency_key uuid,
  run_latency_ms integer,error_code text,run_provider text,run_model text
) returns uuid language plpgsql security definer set search_path='' as $$
declare run_id uuid;
begin
  if error_code is null or length(error_code) not between 1 and 80 or run_provider not in ('mock','gemini','groq','deepseek') or length(run_model) not between 1 and 120 then raise exception 'invalid failure metadata' using errcode='22023'; end if;
  if not exists(select 1 from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id) then raise exception 'policy not found' using errcode='P0002'; end if;
  select id into run_id from public.model_runs where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if run_id is not null then return run_id; end if;
  insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,provider,model,prompt_version,schema_version,status,validation_status,latency_ms,sanitized_error_code)
  values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'daily_coaching',run_provider,run_model,'daily-v1','1.0','failed','failed',run_latency_ms,error_code) returning id into run_id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata) values(target_user_id,'coach.model_run.failed','model_run',run_id,'rejected',jsonb_build_object('error_code',error_code,'schema_version','1.0','provider',run_provider,'model',run_model));
  return run_id;
end $$;
