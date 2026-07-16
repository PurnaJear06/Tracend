create or replace function public.persist_failed_coach_chat_run(
  target_user_id uuid,snapshot_id uuid,policy_id uuid,request_idempotency_key uuid,
  run_latency_ms integer,error_code text,run_provider text,run_model text
) returns uuid language plpgsql security definer set search_path='' as $$
declare run_id uuid;
begin
  if error_code is null or length(error_code) not between 1 and 80
    or run_provider not in ('mock','gemini','groq') or length(run_model) not between 1 and 120
  then raise exception 'invalid failure metadata' using errcode='22023'; end if;
  if not exists(select 1 from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id) then
    raise exception 'policy not found' using errcode='P0002';
  end if;
  select id into run_id from public.model_runs where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if run_id is not null then return run_id; end if;
  insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,provider,model,prompt_version,schema_version,status,validation_status,latency_ms,sanitized_error_code)
  values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'coach_chat',run_provider,run_model,'coach-chat-v1','1.0','failed','failed',run_latency_ms,error_code)
  returning id into run_id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(target_user_id,'coach.chat.model_run.failed','model_run',run_id,'rejected',jsonb_build_object('error_code',error_code,'schema_version','1.0','provider',run_provider,'model',run_model));
  return run_id;
end $$;

revoke all on function public.persist_failed_coach_chat_run(uuid,uuid,uuid,uuid,integer,text,text,text) from public;
grant execute on function public.persist_failed_coach_chat_run(uuid,uuid,uuid,uuid,integer,text,text,text) to service_role;
