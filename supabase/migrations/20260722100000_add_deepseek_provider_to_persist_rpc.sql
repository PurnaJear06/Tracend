create or replace function public.persist_coach_chat_result(
  target_user_id uuid,target_thread_id uuid,question text,request_idempotency_key uuid,snapshot_id uuid,policy_id uuid,
  answer_payload jsonb,run_latency_ms integer,run_provider text,run_model text,run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric
) returns jsonb language plpgsql security definer set search_path='' as $$
declare user_message_id uuid; assistant_message_id uuid; run_id uuid;
begin
  if not exists(select 1 from public.coach_threads where id=target_thread_id and user_id=target_user_id and status='active') then raise exception 'thread not found' using errcode='P0002'; end if;
  if not exists(select 1 from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id) then raise exception 'policy not found' using errcode='P0002'; end if;
  if jsonb_typeof(answer_payload)<>'object' or length(answer_payload->>'answer') not between 1 and 12000
    or jsonb_typeof(answer_payload->'evidence')<>'array' or jsonb_typeof(answer_payload->'missing_data')<>'array'
    or answer_payload->>'safety_state' not in ('allowed','limited','refused','unavailable')
    or run_provider not in ('mock','gemini','groq','deepseek') or length(run_model) not between 1 and 120
    or run_input_units not between 0 and 1000000 or run_output_units not between 0 and 100000 or run_estimated_cost_usd not between 0 and 100
  then raise exception 'invalid chat result' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(answer_payload->'evidence') e where not (e ? 'code' and e ? 'label' and e ? 'source')) then raise exception 'invalid evidence' using errcode='22023'; end if;
  insert into public.coach_messages(user_id,thread_id,role,content,idempotency_key) values(target_user_id,target_thread_id,'user',trim(question),request_idempotency_key)
  on conflict(user_id,idempotency_key) where idempotency_key is not null do update set idempotency_key=excluded.idempotency_key returning id into user_message_id;
  select id into run_id from public.model_runs where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if run_id is null then
    insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,provider,model,prompt_version,schema_version,status,validation_status,input_units,output_units,estimated_cost_usd,latency_ms)
    values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'coach_chat',run_provider,run_model,'coach-chat-v1','1.0','succeeded','passed',run_input_units,run_output_units,run_estimated_cost_usd,run_latency_ms) returning id into run_id;
    insert into public.coach_messages(user_id,thread_id,role,content,evidence,missing_data,safety_state) values(target_user_id,target_thread_id,'assistant',answer_payload->>'answer',answer_payload->'evidence',array(select jsonb_array_elements_text(answer_payload->'missing_data')),answer_payload->>'safety_state') returning id into assistant_message_id;
    update public.coach_threads set last_message_at=now(),updated_at=now(),title=case when title='New conversation' then left(trim(question),80) else title end where id=target_thread_id and user_id=target_user_id;
  else
    select id into assistant_message_id from public.coach_messages where user_id=target_user_id and thread_id=target_thread_id and role='assistant' and created_at>=(select created_at from public.model_runs where id=run_id) order by created_at limit 1;
  end if;
  return jsonb_build_object('user_message_id',user_message_id,'assistant_message_id',assistant_message_id,'model_run_id',run_id);
end $$;
