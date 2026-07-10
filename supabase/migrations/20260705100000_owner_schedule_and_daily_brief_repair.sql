create or replace function public.get_my_daily_brief(target_date date default current_date)
returns jsonb language sql security definer set search_path='' stable as $$
with training as (select public.get_my_training_hub(28) value),
nutrition as (select public.get_my_nutrition_schedule(target_date) value),
next_meal as (
  select item from nutrition,jsonb_array_elements(value->'items') item
  where item->>'status' in ('due','upcoming','optional')
  order by (item->>'order')::integer limit 1
), latest_health as (
  select last_synced_at,present_types,completeness,local_date
  from public.daily_health_summaries
  where user_id=auth.uid()
    and local_date<=target_date
    and local_date>=target_date-31
  order by local_date desc,last_synced_at desc
  limit 1
)
select jsonb_build_object(
  'schema_version','1.0','local_date',target_date,
  'today_workout',(select value->'today_workout' from training),
  'next_meal',(select item from next_meal),
  'check_in',(select to_jsonb(c)-'user_id'-'note'-'idempotency_key'
    from public.daily_check_ins c where c.user_id=auth.uid()
      and c.local_date=target_date and c.superseded_at is null limit 1),
  'health',(select jsonb_build_object('local_date',local_date,
    'last_synced_at',last_synced_at,'present_types',present_types,
    'completeness',completeness) from latest_health),
  'nutrition',public.get_my_daily_nutrition(target_date),
  'latest_decision',(select jsonb_build_object('id',id,'final_decision',head_coach->>'final_decision',
    'reason',head_coach->>'reason','confidence',confidence,'created_at',created_at,
    'evidence',evidence,'missing_data',missing_data)
    from public.coach_decisions where user_id=auth.uid()
    order by created_at desc limit 1)
);
$$;

update public.nutrition_schedule_items
set foods = case slot_key
  when 'pre_workout' then
    '[{"name":"Water","quantity":"as needed"},{"name":"Labrada Super Charge","quantity":"1 scoop"},{"name":"Salt","quantity":"pinch optional"},{"name":"Heavy food","quantity":"avoid before training"}]'::jsonb
  when 'post_workout' then
    '[{"name":"Whole eggs","quantity":"2"},{"name":"Egg whites","quantity":"4"},{"name":"Banana","quantity":"1"},{"name":"Whey protein","quantity":"1 scoop when available; use with banana and 2 whole eggs"}]'::jsonb
  when 'lunch' then
    '[{"name":"Chicken or fish or prawns","quantity":"200 g cooked chicken OR 250 g fish OR 200 g prawns"},{"name":"Cooked rice","quantity":"150 g"},{"name":"Vegetables or salad","quantity":"1 serving"},{"name":"Cooking oil","quantity":"keep low, about 1 tsp"}]'::jsonb
  when 'snack' then
    '[{"name":"Curd or hung curd","quantity":"250 g"},{"name":"Roasted chana","quantity":"30 g"},{"name":"Alternative snack","quantity":"4 boiled eggs plus 1 fruit"}]'::jsonb
  when 'dinner' then
    '[{"name":"Protein choice","quantity":"200 g chicken OR 250 g fish OR 60 g dry soya chunks OR 4 eggs"},{"name":"Carb choice","quantity":"2 phulkas OR 120 g cooked rice"},{"name":"Vegetables or salad","quantity":"1 serving"},{"name":"Cooking oil","quantity":"keep low"}]'::jsonb
  when 'optional_curd' then
    '[{"name":"Curd","quantity":"100–150 g only if hungry"}]'::jsonb
  else foods
end
where slot_key in (
  'pre_workout','post_workout','lunch','snack','dinner','optional_curd'
)
and exists (
  select 1 from public.nutrition_schedule_versions v
  where v.id=nutrition_schedule_items.schedule_version_id
    and v.user_id=nutrition_schedule_items.user_id
    and v.status='active'
)
and (
  foods::text like '%Use confirmed plan quantity%'
  or foods::text like '%Use confirmed plan%'
  or foods::text like '%Pre-workout meal%'
  or foods::text like '%Post-workout meal%'
  or foods::text like '%Optional plan serving%'
);

insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
select user_id,'nutrition.schedule.placeholder_repaired',
  'nutrition_schedule_version',schedule_version_id,'succeeded',
  jsonb_build_object('schema_version','1.0','source','20260705100000')
from public.nutrition_schedule_items
where slot_key='pre_workout'
and foods @> '[{"name":"Labrada Super Charge","quantity":"1 scoop"}]'::jsonb
and exists (
  select 1 from public.nutrition_schedule_versions v
  where v.id=nutrition_schedule_items.schedule_version_id
    and v.user_id=nutrition_schedule_items.user_id
    and v.status='active'
)
on conflict do nothing;

revoke all on function public.get_my_daily_brief(date)
from public,anon,authenticated;
grant execute on function public.get_my_daily_brief(date) to authenticated;
