create or replace function public.get_my_progress_summary()
returns jsonb language sql security definer set search_path='' stable as $$
with ordered as (
  select measured_on,weight_kg,waist_cm,
   row_number() over(order by measured_on,created_at) ascending_rank,
   row_number() over(order by measured_on desc,created_at desc) descending_rank
  from public.body_measurements where user_id=auth.uid()
), stats as (
 select count(distinct measured_on)::integer observation_days
 from public.body_measurements where user_id=auth.uid()
), valueset as (
 select stats.observation_days observation_count,
  max(weight_kg) filter(where descending_rank=1) current_weight_kg,
  max(weight_kg) filter(where ascending_rank=1) first_weight_kg,
  max(waist_cm) filter(where descending_rank=1) current_waist_cm,
  max(waist_cm) filter(where ascending_rank=1 and waist_cm is not null) first_waist_cm,
  min(measured_on) first_date,max(measured_on) latest_date
 from stats left join ordered on true group by stats.observation_days
)
select jsonb_build_object(
 'schema_version','1.0','observation_count',coalesce(observation_count,0),
 'current_weight_kg',current_weight_kg,
 'weight_change_kg',case when observation_count>=2 then current_weight_kg-first_weight_kg end,
 'current_waist_cm',current_waist_cm,
 'waist_change_cm',case when observation_count>=2 and current_waist_cm is not null and first_waist_cm is not null then current_waist_cm-first_waist_cm end,
 'first_date',first_date,'latest_date',latest_date,
 'trend_status',case when coalesce(observation_count,0)<2 then 'not_enough_data' else 'available' end,
 'weekly_review_status',case when coalesce(observation_count,0)<2 then 'gather_data' else 'ready' end)
from valueset;
$$;

revoke all on function public.get_my_progress_summary() from public,anon,authenticated;
grant execute on function public.get_my_progress_summary() to authenticated;
