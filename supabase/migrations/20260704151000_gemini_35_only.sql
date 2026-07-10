alter table public.ai_usage_events
  drop constraint ai_usage_events_model_check;

alter table public.ai_usage_events
  add constraint ai_usage_events_model_check
  check (model = 'gemini-3.5-flash');

create or replace function public.record_ai_usage_event(
  target_user_id uuid,run_purpose text,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,
  run_estimated_cost_usd numeric,run_latency_ms integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare event_id uuid;
begin
  if run_purpose not in ('meal_vision','progress_vision')
    or run_provider<>'gemini'
    or run_model<>'gemini-3.5-flash'
  then raise exception 'invalid usage event' using errcode='22023'; end if;
  insert into public.ai_usage_events(
    user_id,purpose,provider,model,input_units,output_units,
    estimated_cost_usd,latency_ms)
  values(target_user_id,run_purpose,run_provider,run_model,run_input_units,
    run_output_units,run_estimated_cost_usd,run_latency_ms)
  returning id into event_id;
  return event_id;
end $$;

create or replace function public.persist_meal_photo_candidates(
  target_user_id uuid,target_meal_id uuid,candidates jsonb,
  run_provider text,run_model text
) returns integer language plpgsql security definer set search_path='' as $$
declare meal public.meals%rowtype; item jsonb; item_count integer:=0;
begin
  select * into meal from public.meals where id=target_meal_id
    and user_id=target_user_id for update;
  if not found then raise exception 'meal not found' using errcode='P0002'; end if;
  if meal.source<>'photo_analysis' or meal.status<>'draft'
    or jsonb_typeof(candidates)<>'array'
    or jsonb_array_length(candidates) not between 1 and 20
    or run_provider<>'gemini' or run_model<>'gemini-3.5-flash'
  then raise exception 'invalid meal analysis' using errcode='22023'; end if;
  delete from public.meal_analysis_candidates where meal_id=target_meal_id;
  for item in select value from jsonb_array_elements(candidates) loop
    item_count:=item_count+1;
    insert into public.meal_analysis_candidates(
      user_id,meal_id,candidate_order,food_label,serving_label,calories,
      protein_g,carbohydrate_g,fat_g,confidence)
    values(target_user_id,target_meal_id,item_count,item->>'name',item->>'serving_label',
      (item->>'calories')::numeric,(item->>'protein_g')::numeric,
      (item->>'carbohydrate_g')::numeric,(item->>'fat_g')::numeric,
      item->>'confidence');
  end loop;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(target_user_id,'meal.photo.candidates_created','meal',target_meal_id,
    'succeeded',jsonb_build_object('candidate_count',item_count,
      'provider',run_provider,'model',run_model));
  return item_count;
end $$;

revoke all on function public.record_ai_usage_event(
  uuid,text,text,text,integer,integer,numeric,integer),
  public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text)
from public,anon,authenticated;

grant execute on function public.record_ai_usage_event(
  uuid,text,text,text,integer,integer,numeric,integer),
  public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text)
to service_role;
