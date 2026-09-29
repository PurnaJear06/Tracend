-- Meal photos move to Groq qwen/qwen3.8-27b, the named successor of
-- qwen/qwen3.6-27b (shut down by Groq on 2026-09-14). The old model stays
-- accepted so existing rows and the currently deployed function remain valid.
--
-- The owner AI budget keeps its money limits (USD 1 warning, USD 2 hard stop)
-- and raises the daily request count from 10 to 30: at 10, a day's meal photos
-- used up the allowance for the Coach. The USD 2 monthly stop still bounds
-- spend.
alter table public.ai_usage_events drop constraint ai_usage_events_model_check;
alter table public.ai_usage_events add constraint ai_usage_events_model_check
  check (model in ('gemini-3.5-flash','qwen/qwen3.6-27b','qwen/qwen3.8-27b','deepseek-v4-flash'));

create or replace function public.record_ai_usage_event(
  target_user_id uuid,run_purpose text,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric,run_latency_ms integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare event_id uuid;
begin
  if run_purpose not in ('meal_vision','progress_vision') or
    not ((run_provider='gemini' and run_model='gemini-3.5-flash') or
      (run_provider='groq' and run_model in ('qwen/qwen3.6-27b','qwen/qwen3.8-27b')))
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
    not ((run_provider='gemini' and run_model='gemini-3.5-flash') or
      (run_provider='groq' and run_model in ('qwen/qwen3.6-27b','qwen/qwen3.8-27b')))
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

create or replace function public.assert_owner_ai_budget(target_user_id uuid)
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
  if today_requests>=30 then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
end $$;

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
  'blocked',monthly_cost>=2,'today_requests',today_requests,'daily_limit',30)
from usage;
$$;
