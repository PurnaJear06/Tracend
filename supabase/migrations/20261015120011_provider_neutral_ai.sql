-- Provider-neutral AI data (coaching platform program, chunk A1) -------------------------
--
-- The AI gateway (Contract 1) can route each feature to Claude. In the
-- database a provider is the vendor that receives the athlete's data
-- (`anthropic`, `deepseek`, `groq`, `gemini`, and `mock` where it already
-- existed), never the API shape used to reach it: a notice that names DeepSeek
-- must not cover a route to Groq. Every SQL place that names the providers a
-- run, a usage row or a notice may carry now accepts `anthropic` next to
-- today's names. Nothing accepted today is refused, so the deployed Edge
-- Functions and the installed app keep working unchanged:
--
--   * check constraints: model_runs.provider, ai_usage_events.provider and
--     ai_usage_events.model, meal_photo_ai_notices.provider;
--   * service-role RPCs, each redefined from its latest version with only the
--     provider list changed: persist_coach_chat_result,
--     persist_daily_coaching_result_v2, persist_failed_coaching_run_v2,
--     persist_failed_coach_chat_run (persist_failed_coach_chat_run_v2 calls
--     it), record_ai_usage_event and persist_meal_photo_candidates.
--
-- Model names stay pinned for the old vision vendors. A Claude run carries the
-- model its route names, so for `anthropic` any well-formed model id is
-- accepted (letters, digits and . _ : / -, at most 100).
--
-- None of the program's frozen functions holds a provider list, so none is
-- redefined here.
--
-- Notices gain a machine-readable vendor so the gateway can refuse a call to
-- a vendor the athlete's notice does not name. Old notices keep a null
-- provider (never edited); the new publish overloads set it.
--
-- New: get_ai_consent_v2 (grant, vendor and version of a purpose's current
-- notice) and reserve_ai_budget_v2 (the per-call ceiling comes from the route).
-- has_ai_coaching_consent and reserve_ai_budget are unchanged.

-- Table checks ---------------------------------------------------------------------------

alter table public.model_runs drop constraint model_runs_provider_check;
alter table public.model_runs add constraint model_runs_provider_check
  check (provider in ('mock','gemini','groq','deepseek','anthropic'));

alter table public.ai_usage_events drop constraint ai_usage_events_provider_check;
alter table public.ai_usage_events add constraint ai_usage_events_provider_check
  check (provider in ('gemini','groq','deepseek','anthropic'));

alter table public.ai_usage_events drop constraint ai_usage_events_model_check;
alter table public.ai_usage_events add constraint ai_usage_events_model_check check (
  (purpose not in ('onboarding_plan','onboarding_questions') and model in
    ('gemini-3.5-flash','qwen/qwen3.6-27b','qwen/qwen3.8-27b','deepseek-v4-flash'))
  or (purpose in ('onboarding_plan','onboarding_questions') and length(model) between 1 and 100)
  or (provider = 'anthropic'
    and model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$')
);

-- Notices --------------------------------------------------------------------------------

alter table public.meal_photo_ai_notices drop constraint meal_photo_ai_notices_provider_check;
alter table public.meal_photo_ai_notices add constraint meal_photo_ai_notices_provider_check
  check (provider in ('deepseek','groq','gemini','anthropic'));

-- Null on every notice published before this migration: they are never edited.
alter table public.ai_consent_notices add column provider text
  constraint ai_consent_notices_provider_check
  check (provider in ('deepseek','groq','gemini','anthropic'));

alter table public.photo_ai_notices add column provider text
  constraint photo_ai_notices_provider_check
  check (provider in ('deepseek','groq','gemini','anthropic'));

-- The four-argument publishers keep working (provider null). These name it.
create function private.publish_ai_notice(
  notice_version text, notice_provider text, notice_provider_label text,
  notice_purposes text[], notice_body text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if notice_provider is null then
    raise exception 'provider required' using errcode = '22023';
  end if;
  insert into public.ai_consent_notices(version, provider, provider_label, purposes, body)
  values (notice_version, notice_provider, notice_provider_label, notice_purposes, notice_body);
  insert into public.ai_notice_current(purpose, version)
  select purpose, notice_version from unnest(notice_purposes) purpose
  on conflict (purpose) do update set version = excluded.version, updated_at = now();
end $$;
revoke all on function private.publish_ai_notice(text, text, text, text[], text)
from public, anon, authenticated;

create function private.publish_photo_ai_notice(
  notice_version text, notice_provider text, notice_provider_label text, notice_model text,
  notice_body text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if notice_provider is null then
    raise exception 'provider required' using errcode = '22023';
  end if;
  insert into public.photo_ai_notices(version, provider, provider_label, model, body)
  values (notice_version, notice_provider, notice_provider_label, notice_model, notice_body);
end $$;
revoke all on function private.publish_photo_ai_notice(text, text, text, text, text)
from public, anon, authenticated;

-- Consent v2 -----------------------------------------------------------------------------

-- What the gateway checks before sending anything: whether the athlete grants
-- the notice current for the purpose, and which provider and version that
-- notice names. Purposes are the gateway's features (Contract 1) plus today's
-- names; each maps to the notice that covers it:
--   coach_chat, library_context        -> ai_coaching notice for coach_chat
--   daily_coaching, daily_decision     -> ai_coaching notice for daily_coaching
--   onboarding_plan, onboarding_questions -> ai_coaching notice for onboarding_plan
--   meal_vision                        -> meal photo notice (meal_photo_ai)
--   physique_vision, progress_vision   -> progress photo notice (progress_photo_ai)
-- `provider` (the vendor) is null when the current notice predates vendor
-- names; the gateway then refuses (consent_provider_mismatch) until a notice
-- naming the route's vendor is published and granted.
create function public.get_ai_consent_v2(target_user_id uuid, consent_purpose text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  coaching_purpose text;
  current_version text;
  current_provider text;
  is_granted boolean;
begin
  coaching_purpose := case consent_purpose
    when 'coach_chat' then 'coach_chat'
    when 'library_context' then 'coach_chat'
    when 'daily_coaching' then 'daily_coaching'
    when 'daily_decision' then 'daily_coaching'
    when 'onboarding_plan' then 'onboarding_plan'
    when 'onboarding_questions' then 'onboarding_plan'
  end;
  if coaching_purpose is not null then
    select notice.version, notice.provider into current_version, current_provider
    from public.ai_notice_current current
    join public.ai_consent_notices notice on notice.version = current.version
    where current.purpose = coaching_purpose;
    is_granted := public.has_ai_coaching_consent(target_user_id, coaching_purpose);
  elsif consent_purpose = 'meal_vision' then
    select notice.version, notice.provider into current_version, current_provider
    from private.current_meal_photo_ai_notice() notice;
    is_granted := public.has_meal_photo_ai_consent(target_user_id);
  elsif consent_purpose in ('physique_vision','progress_vision') then
    select notice.version, notice.provider into current_version, current_provider
    from private.current_photo_ai_notice() notice;
    is_granted := public.has_photo_ai_consent(target_user_id);
  else
    raise exception 'invalid purpose' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'schema_version', '1.0',
    'granted', coalesce(is_granted, false),
    'provider', current_provider,
    'notice_version', current_version);
end $$;
revoke all on function public.get_ai_consent_v2(uuid, text) from public, anon, authenticated;
grant execute on function public.get_ai_consent_v2(uuid, text) to service_role;

-- Budget v2 ------------------------------------------------------------------------------

-- The purpose a reservation is stored under. Today's names stand for
-- themselves; the gateway's feature names map onto them, so the reservation
-- table, the usage tables and their limits are unchanged.
create function private.ai_budget_purpose(run_purpose text)
returns text language sql immutable set search_path = '' as $$
  select case run_purpose
    when 'coach_chat' then 'coach_chat'
    when 'library_context' then 'coach_chat'
    when 'daily_coaching' then 'daily_coaching'
    when 'daily_decision' then 'daily_coaching'
    when 'meal_vision' then 'meal_vision'
    when 'progress_vision' then 'progress_vision'
    when 'physique_vision' then 'progress_vision'
    when 'onboarding_plan' then 'onboarding_plan'
    when 'onboarding_questions' then 'onboarding_questions'
  end;
$$;
revoke all on function private.ai_budget_purpose(text) from public, anon, authenticated;

-- reserve_ai_budget with the per-call ceiling from the caller's route: above
-- zero and at most USD 0.50, rounded up to the reservation's six decimals so a
-- place never counts less than asked. The athlete's USD 2 month and 30 calls a
-- day, and private.ai_budget_limits for every account, apply as before.
create function public.reserve_ai_budget_v2(
  target_user_id uuid, run_purpose text, ceiling_usd numeric
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  athlete record;
  everyone record;
  reservation_id uuid;
  stored_purpose text := private.ai_budget_purpose(run_purpose);
  ceiling numeric;
begin
  if stored_purpose is null then
    raise exception 'invalid purpose' using errcode = '22023';
  end if;
  if ceiling_usd is null or ceiling_usd <= 0 or ceiling_usd > 0.50 then
    raise exception 'invalid ceiling' using errcode = '22023';
  end if;
  ceiling := ceil(ceiling_usd * 1000000) / 1000000;
  perform pg_advisory_xact_lock(hashtextextended('tracend.ai_budget', 0));
  select * into athlete from private.ai_usage_totals(target_user_id);
  if athlete.monthly_cost + ceiling > 2 then
    raise exception 'monthly cost limit reached' using errcode = 'P0001';
  end if;
  if athlete.today_requests + 1 > 30 then
    raise exception 'daily rate limit reached' using errcode = 'P0001';
  end if;
  select * into everyone from private.ai_usage_totals(null);
  if everyone.monthly_cost + ceiling > (select global_monthly_usd from private.ai_budget_limits) then
    raise exception 'global monthly cost limit reached' using errcode = 'P0001';
  end if;
  insert into public.ai_budget_reservations(user_id, purpose, reserved_cost_usd)
  values (target_user_id, stored_purpose, ceiling)
  returning id into reservation_id;
  return reservation_id;
end $$;
revoke all on function public.reserve_ai_budget_v2(uuid, text, numeric) from public, anon, authenticated;
grant execute on function public.reserve_ai_budget_v2(uuid, text, numeric) to service_role;

-- Persist RPCs (latest bodies; only the provider lists change) ---------------------------

-- From 20260722100000.
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
    or run_provider not in ('mock','gemini','groq','deepseek','anthropic') or length(run_model) not between 1 and 120
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

-- From 20260826120000.
create or replace function public.persist_daily_coaching_result_v2(
  target_user_id uuid,snapshot_id uuid,policy_id uuid,request_idempotency_key uuid,
  decision_payload jsonb,run_latency_ms integer,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric
) returns jsonb language plpgsql security definer set search_path='' as $$
declare run_id uuid; decision_id uuid; policy public.policy_evaluations%rowtype;
begin
  select * into policy from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id;
  if not found then raise exception 'policy not found' using errcode='P0002'; end if;
  if run_provider not in ('mock','gemini','groq','deepseek','anthropic') or length(run_model) not between 1 and 120
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

-- From 20260825000000.
create or replace function public.persist_failed_coaching_run_v2(
  target_user_id uuid,snapshot_id uuid,policy_id uuid,request_idempotency_key uuid,
  run_latency_ms integer,error_code text,run_provider text,run_model text
) returns uuid language plpgsql security definer set search_path='' as $$
declare run_id uuid;
begin
  if error_code is null or length(error_code) not between 1 and 80 or run_provider not in ('mock','gemini','groq','deepseek','anthropic') or length(run_model) not between 1 and 120 then raise exception 'invalid failure metadata' using errcode='22023'; end if;
  if not exists(select 1 from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id) then raise exception 'policy not found' using errcode='P0002'; end if;
  select id into run_id from public.model_runs where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if run_id is not null then return run_id; end if;
  insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,provider,model,prompt_version,schema_version,status,validation_status,latency_ms,sanitized_error_code)
  values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'daily_coaching',run_provider,run_model,'daily-v1','1.0','failed','failed',run_latency_ms,error_code) returning id into run_id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata) values(target_user_id,'coach.model_run.failed','model_run',run_id,'rejected',jsonb_build_object('error_code',error_code,'schema_version','1.0','provider',run_provider,'model',run_model));
  return run_id;
end $$;

-- From 20260927230000 (same nine-argument signature, so grants are kept).
create or replace function public.persist_failed_coach_chat_run(
  target_user_id uuid, snapshot_id uuid, policy_id uuid, request_idempotency_key uuid,
  run_latency_ms integer, error_code text, run_provider text, run_model text,
  failure_rules text[] default '{}'::text[]
) returns uuid language plpgsql security definer set search_path = '' as $$
declare run_id uuid;
begin
  if error_code is null or length(error_code) not between 1 and 80
    or run_provider not in ('mock','gemini','groq','deepseek','anthropic')
    or run_model is null or length(run_model) not between 1 and 120
    or failure_rules is null or cardinality(failure_rules) > 4
    or exists(select 1 from unnest(failure_rules) as r(rule_name) where r.rule_name !~ '^[a-z_]{1,64}$')
  then raise exception 'invalid failure metadata' using errcode = '22023'; end if;
  if not exists(select 1 from public.policy_evaluations
    where id = policy_id and user_id = target_user_id and feature_snapshot_id = snapshot_id) then
    raise exception 'policy not found' using errcode = 'P0002';
  end if;
  select id into run_id from public.model_runs
  where user_id = target_user_id and idempotency_key = request_idempotency_key;
  if run_id is not null then return run_id; end if;
  insert into public.model_runs(user_id, feature_snapshot_id, policy_evaluation_id, idempotency_key,
    purpose, provider, model, prompt_version, schema_version, status, validation_status,
    latency_ms, sanitized_error_code)
  values(target_user_id, snapshot_id, policy_id, request_idempotency_key,
    'coach_chat', run_provider, run_model, 'coach-chat-v1', '1.0', 'failed', 'failed',
    run_latency_ms, error_code)
  returning id into run_id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values(target_user_id, 'coach.chat.model_run.failed', 'model_run', run_id, 'rejected',
    jsonb_build_object('error_code', error_code, 'schema_version', '1.0',
      'provider', run_provider, 'model', run_model, 'rules', to_jsonb(failure_rules)));
  return run_id;
end $$;

-- From 20261002110000. Vision keeps its pinned pairs for the old providers.
create or replace function public.record_ai_usage_event(
  target_user_id uuid,run_purpose text,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric,run_latency_ms integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare event_id uuid;
begin
  if run_purpose in ('onboarding_plan','onboarding_questions') then
    if run_provider not in ('deepseek','groq','gemini','anthropic')
      or length(run_model) not between 1 and 100
    then raise exception 'invalid usage event' using errcode='22023'; end if;
  elsif run_purpose not in ('meal_vision','progress_vision') or
    not ((run_provider='gemini' and run_model='gemini-3.5-flash') or
      (run_provider='groq' and run_model in ('qwen/qwen3.6-27b','qwen/qwen3.8-27b')) or
      (run_provider = 'anthropic'
        and run_model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$'))
  then raise exception 'invalid usage event' using errcode='22023'; end if;
  insert into public.ai_usage_events(user_id,purpose,provider,model,input_units,output_units,estimated_cost_usd,latency_ms)
  values(target_user_id,run_purpose,run_provider,run_model,run_input_units,run_output_units,run_estimated_cost_usd,run_latency_ms)
  returning id into event_id; return event_id;
end $$;

-- From 20260929140000.
create or replace function public.persist_meal_photo_candidates(
  target_user_id uuid,target_meal_id uuid,candidates jsonb,run_provider text,run_model text
) returns integer language plpgsql security definer set search_path='' as $$
declare meal public.meals%rowtype; item jsonb; item_count integer:=0;
begin
  select * into meal from public.meals where id=target_meal_id and user_id=target_user_id for update;
  if not found then raise exception 'meal not found' using errcode='P0002'; end if;
  if meal.source<>'photo_analysis' or meal.status<>'draft' or jsonb_typeof(candidates)<>'array'
    or jsonb_array_length(candidates) not between 1 and 20 or
    not ((run_provider='gemini' and run_model='gemini-3.5-flash') or
      (run_provider='groq' and run_model in ('qwen/qwen3.6-27b','qwen/qwen3.8-27b')) or
      (run_provider = 'anthropic'
        and run_model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$'))
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
