-- Time-bounded owner test: Groq Qwen is server-only and never bypasses validation or confirmation.
alter table public.model_runs drop constraint model_runs_provider_check;
alter table public.model_runs add constraint model_runs_provider_check
  check (provider in ('mock','gemini','groq'));
alter table public.ai_usage_events drop constraint ai_usage_events_provider_check;
alter table public.ai_usage_events add constraint ai_usage_events_provider_check
  check (provider in ('gemini','groq'));
alter table public.ai_usage_events drop constraint ai_usage_events_model_check;
alter table public.ai_usage_events add constraint ai_usage_events_model_check
  check (model in ('gemini-3.5-flash','qwen/qwen3.6-27b'));

create or replace function public.get_my_ai_budget_state()
returns jsonb language sql security definer set search_path='' stable as $$
with usage as (
  select coalesce(sum(estimated_cost_usd),0) monthly_cost,
    count(*) filter(where purpose in ('daily_coaching','coach_chat','meal_vision')
      and created_at>=date_trunc('day',now())) today_requests
  from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=auth.uid() and created_at>=date_trunc('month',now())
    union all
    select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=auth.uid() and created_at>=date_trunc('month',now())
  ) all_usage
)
select jsonb_build_object('period','current_month','estimated_cost_usd',monthly_cost,
  'warning_threshold_usd',1,'hard_stop_usd',2,'warning',monthly_cost>=1,
  'blocked',monthly_cost>=2,'today_requests',today_requests,'daily_limit',10)
from usage;
$$;

create function public.assert_owner_ai_budget(target_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare monthly_cost numeric; today_requests integer;
begin
  select coalesce(sum(estimated_cost_usd),0), count(*) filter(where purpose in
    ('daily_coaching','coach_chat','meal_vision') and created_at>=date_trunc('day',now()))
  into monthly_cost,today_requests from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=target_user_id and created_at>=date_trunc('month',now())
    union all select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=target_user_id and created_at>=date_trunc('month',now())
  ) usage;
  if monthly_cost>=2 then raise exception 'monthly cost limit reached' using errcode='P0001'; end if;
  if today_requests>=10 then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
end $$;

create or replace function public.record_ai_usage_event(
  target_user_id uuid,run_purpose text,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric,run_latency_ms integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare event_id uuid;
begin
  if run_purpose not in ('meal_vision','progress_vision') or
    not ((run_provider='gemini' and run_model='gemini-3.5-flash') or
      (run_provider='groq' and run_model='qwen/qwen3.6-27b'))
  then raise exception 'invalid usage event' using errcode='22023'; end if;
  insert into public.ai_usage_events(user_id,purpose,provider,model,input_units,output_units,estimated_cost_usd,latency_ms)
  values(target_user_id,run_purpose,run_provider,run_model,run_input_units,run_output_units,run_estimated_cost_usd,run_latency_ms)
  returning id into event_id; return event_id;
end $$;

create or replace function public.persist_meal_photo_candidates(
  target_user_id uuid,target_meal_id uuid,candidates jsonb,run_provider text,run_model text
) returns integer language plpgsql security definer set search_path='' as $$
declare meal public.meals%rowtype; item jsonb; item_count integer:=0;
begin
  select * into meal from public.meals where id=target_meal_id and user_id=target_user_id for update;
  if not found then raise exception 'meal not found' using errcode='P0002'; end if;
  if meal.source<>'photo_analysis' or meal.status<>'draft' or jsonb_typeof(candidates)<>'array'
    or jsonb_array_length(candidates) not between 1 and 20 or
    not ((run_provider='gemini' and run_model='gemini-3.5-flash') or (run_provider='groq' and run_model='qwen/qwen3.6-27b'))
  then raise exception 'invalid meal analysis' using errcode='22023'; end if;
  delete from public.meal_analysis_candidates where meal_id=target_meal_id;
  for item in select value from jsonb_array_elements(candidates) loop
    item_count:=item_count+1;
    insert into public.meal_analysis_candidates(user_id,meal_id,candidate_order,food_label,serving_label,calories,protein_g,carbohydrate_g,fat_g,confidence)
    values(target_user_id,target_meal_id,item_count,item->>'name',item->>'serving_label',(item->>'calories')::numeric,(item->>'protein_g')::numeric,(item->>'carbohydrate_g')::numeric,(item->>'fat_g')::numeric,item->>'confidence');
  end loop;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(target_user_id,'meal.photo.candidates_created','meal',target_meal_id,'succeeded',jsonb_build_object('candidate_count',item_count,'provider',run_provider,'model',run_model));
  return item_count;
end $$;

revoke all on function public.assert_owner_ai_budget(uuid) from public,anon,authenticated;
grant execute on function public.assert_owner_ai_budget(uuid) to service_role;

create or replace function public.persist_daily_coaching_result_v2(
  target_user_id uuid,snapshot_id uuid,policy_id uuid,request_idempotency_key uuid,
  decision_payload jsonb,run_latency_ms integer,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric
) returns jsonb language plpgsql security definer set search_path='' as $$
declare run_id uuid; decision_id uuid; policy public.policy_evaluations%rowtype;
begin
  select * into policy from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id;
  if not found then raise exception 'policy not found' using errcode='P0002'; end if;
  if run_provider not in ('mock','gemini','groq') or length(run_model) not between 1 and 120
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
  if error_code is null or length(error_code) not between 1 and 80 or run_provider not in ('mock','gemini','groq') or length(run_model) not between 1 and 120 then raise exception 'invalid failure metadata' using errcode='22023'; end if;
  if not exists(select 1 from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id) then raise exception 'policy not found' using errcode='P0002'; end if;
  select id into run_id from public.model_runs where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if run_id is not null then return run_id; end if;
  insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,provider,model,prompt_version,schema_version,status,validation_status,latency_ms,sanitized_error_code)
  values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'daily_coaching',run_provider,run_model,'daily-v1','1.0','failed','failed',run_latency_ms,error_code) returning id into run_id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata) values(target_user_id,'coach.model_run.failed','model_run',run_id,'rejected',jsonb_build_object('error_code',error_code,'schema_version','1.0','provider',run_provider,'model',run_model));
  return run_id;
end $$;

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
    or run_provider not in ('mock','gemini','groq') or length(run_model) not between 1 and 120
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
