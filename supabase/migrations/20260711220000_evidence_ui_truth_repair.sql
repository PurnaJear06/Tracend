-- Prevent repeated reconciliation prompts and make same-day measurements amendments.

create or replace function public.get_my_workout_reconciliation_candidates()
returns jsonb language sql security invoker set search_path='' stable as $$
with ranked as (
  select r.id,r.status,r.confidence,r.duration_difference_seconds,r.created_at,
    r.workout_session_id,h.activity_type,h.duration_seconds,h.started_at,
    w.name workout_name,s.local_date,
    row_number() over(partition by r.workout_session_id order by
      case r.status when 'conflict' then 0 else 1 end,r.confidence desc,
      r.duration_difference_seconds,r.created_at) candidate_rank
  from public.workout_reconciliations r
  join public.health_workout_references h on h.id=r.health_workout_reference_id and h.user_id=r.user_id
  join public.workout_sessions s on s.id=r.workout_session_id and s.user_id=r.user_id
  join public.planned_workouts w on w.id=s.planned_workout_id and w.user_id=s.user_id
  where r.user_id=auth.uid() and r.status in ('suggested','conflict')
    and not exists(select 1 from public.workout_reconciliations accepted
      where accepted.user_id=r.user_id and accepted.workout_session_id=r.workout_session_id
        and accepted.status='confirmed')
)
select coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'status',status,'confidence',confidence,
  'duration_difference_seconds',duration_difference_seconds,
  'activity_type',activity_type,'health_duration_seconds',duration_seconds,
  'workout_name',workout_name,'local_date',local_date,'started_at',started_at
) order by local_date desc,created_at desc),'[]'::jsonb)
from ranked where candidate_rank=1;
$$;

create or replace function public.respond_workout_reconciliation(p_reconciliation_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path='' as $$
declare target public.workout_reconciliations%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into target from public.workout_reconciliations
    where id=p_reconciliation_id and user_id=auth.uid() for update;
  if not found then raise exception 'reconciliation not found' using errcode='P0002'; end if;
  if target.status=(case when p_accept then 'confirmed' else 'rejected' end) then return; end if;
  if p_accept then
    update public.workout_reconciliations set status='rejected',confirmed_at=null
    where user_id=auth.uid() and workout_session_id=target.workout_session_id
      and id<>target.id and status in ('suggested','conflict');
  end if;
  update public.workout_reconciliations set
    status=case when p_accept then 'confirmed' else 'rejected' end,
    confirmed_at=case when p_accept then now() else null end where id=target.id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),case when p_accept then 'workout.reconciliation_confirmed' else 'workout.reconciliation_rejected' end,
    'workout_reconciliation',target.id,'succeeded',jsonb_build_object('competing_candidates_closed',p_accept));
end $$;

create or replace function public.save_body_measurement(
  measurement_date date, weight_kg numeric, waist_cm numeric default null,
  chest_cm numeric default null, hip_cm numeric default null,
  arm_cm numeric default null, thigh_cm numeric default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare measurement_id uuid; previous_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select id into previous_id from public.body_measurements
    where user_id=auth.uid() and measured_on=measurement_date and source='manual'
      and superseded_at is null order by created_at desc limit 1 for update;
  if previous_id is not null then
    update public.body_measurements set superseded_at=now()
      where user_id=auth.uid() and measured_on=measurement_date and source='manual'
        and superseded_at is null;
  end if;
  insert into public.body_measurements(user_id,measured_on,source,weight_kg,waist_cm,chest_cm,hip_cm,arm_cm,thigh_cm,amended_from_id)
  values(auth.uid(),measurement_date,'manual',weight_kg,waist_cm,chest_cm,hip_cm,arm_cm,thigh_cm,previous_id)
  returning id into measurement_id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),case when previous_id is null then 'progress.measurement.recorded' else 'progress.measurement.corrected' end,
    'body_measurement',measurement_id,'succeeded',jsonb_build_object('amended',previous_id is not null));
  return measurement_id;
end $$;

create or replace function public.get_my_progress_summary()
returns jsonb language sql security definer set search_path='' stable as $$
with current_rows as (
  select * from public.body_measurements where user_id=auth.uid() and superseded_at is null
), ordered as (
  select measured_on,weight_kg,waist_cm,
    row_number() over(order by measured_on,created_at) ascending_rank,
    row_number() over(order by measured_on desc,created_at desc) descending_rank
  from current_rows
), stats as (select count(distinct measured_on)::integer observation_days from current_rows),
valueset as (
  select stats.observation_days observation_count,
    max(weight_kg) filter(where descending_rank=1) current_weight_kg,
    max(weight_kg) filter(where ascending_rank=1) first_weight_kg,
    max(waist_cm) filter(where descending_rank=1) current_waist_cm,
    max(waist_cm) filter(where ascending_rank=1 and waist_cm is not null) first_waist_cm,
    min(measured_on) first_date,max(measured_on) latest_date
  from stats left join ordered on true group by stats.observation_days
)
select jsonb_build_object('schema_version','1.1','observation_count',coalesce(observation_count,0),
  'current_weight_kg',current_weight_kg,
  'weight_change_kg',case when observation_count>=2 then current_weight_kg-first_weight_kg end,
  'current_waist_cm',current_waist_cm,
  'waist_change_cm',case when observation_count>=2 and current_waist_cm is not null and first_waist_cm is not null then current_waist_cm-first_waist_cm end,
  'first_date',first_date,'latest_date',latest_date,
  'trend_status',case when coalesce(observation_count,0)<2 then 'not_enough_data' else 'available' end,
  'weekly_review_status',case when coalesce(observation_count,0)<2 then 'gather_data' else 'ready' end)
from valueset;
$$;

revoke all on function public.get_my_workout_reconciliation_candidates() from public,anon,authenticated;
grant execute on function public.get_my_workout_reconciliation_candidates() to authenticated;
