begin;

-- Phase 4 Pipeline Fix: fresh computed metrics, default effort for
-- auto-completed sessions, backfill + recompute.

-- 1. Backfill existing session_effort for completed workouts that were
--    auto-completed from HealthKit (currently NULL → invisible to ACWR)
-- ---------------------------------------------------------------------------
update public.workout_sessions
  set session_effort = 5
  where session_effort is null
    and state = 'completed';

-- 2. Recompute stale daily_computed_metrics rows for dates that have
--    backfilled sessions (last 28 days).  Overwrites existing rows via
--    the ON CONFLICT upsert inside compute_daily_metrics.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  tz text;
begin
  for r in
    select distinct ws.user_id, ws.local_date
    from public.workout_sessions ws
    join public.daily_health_summaries dhs
      on dhs.user_id = ws.user_id
      and dhs.local_date = ws.local_date
    where ws.state = 'completed'
      and ws.local_date >= current_date - 28
      and exists(select 1 from public.user_accounts ua where ua.id = ws.user_id)
  loop
    select coalesce(dhs.timezone, 'UTC') into tz
    from public.daily_health_summaries dhs
    where dhs.user_id = r.user_id
      and dhs.local_date = r.local_date
      and dhs.source_scope = 'healthkit'
    limit 1;

    begin
      perform public.compute_daily_metrics(r.user_id, r.local_date, tz);
    exception when others then
      null;
    end;
  end loop;
end $$;

-- 3. recompute_stale_metrics → also process today (was: only yesterday)
-- ---------------------------------------------------------------------------
create or replace function public.recompute_stale_metrics()
returns integer language plpgsql security definer set search_path = '' as $$
declare
  stale record;
  processed integer := 0;
begin
  for stale in
    select dhs.user_id, dhs.local_date, dhs.timezone
    from public.daily_health_summaries dhs
    left join public.daily_computed_metrics dcm
      on dcm.user_id = dhs.user_id
      and dcm.local_date = dhs.local_date
    where dhs.source_scope = 'healthkit'
      and dhs.local_date in (current_date, current_date - 1)
      and dcm.id is null
      and exists(select 1 from public.user_accounts ua where ua.id = dhs.user_id)
    limit 100
  loop
    begin
      perform public.compute_daily_metrics(
        stale.user_id,
        stale.local_date,
        coalesce(stale.timezone, 'UTC')
      );
      processed := processed + 1;
    exception when others then
      null;
    end;
  end loop;

  return processed;
end $$;

-- 4. get_my_daily_brief → read computed from daily_computed_metrics
--    (was: feature_snapshots, a point-in-time coaching snapshot)
-- ---------------------------------------------------------------------------
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
), latest_computed as (
  select baseline_snapshot_jsonb as baselines,
         scores_jsonb as scores,
         data_confidence
  from public.daily_computed_metrics
  where user_id=auth.uid()
    and local_date=target_date
  order by local_date desc limit 1
)
select jsonb_build_object(
  'schema_version','1.1','local_date',target_date,
  'today_workout',(select value->'today_workout' from training),
  'next_meal',(select item from next_meal),
  'check_in',(select to_jsonb(c)-'user_id'-'note'-'idempotency_key'
    from public.daily_check_ins c where c.user_id=auth.uid()
      and c.local_date=target_date and c.superseded_at is null limit 1),
  'health',(select jsonb_build_object('local_date',local_date,
    'last_synced_at',last_synced_at,'present_types',present_types,
    'completeness',completeness) from latest_health),
  'nutrition',public.get_my_daily_nutrition(target_date),
  'computed',(select jsonb_build_object(
    'baselines',baselines,'scores',scores,
    'data_confidence',data_confidence) from latest_computed),
  'latest_decision',(select jsonb_build_object('id',id,'final_decision',head_coach->>'final_decision',
    'reason',head_coach->>'reason','confidence',confidence,'created_at',created_at,
    'evidence',evidence,'missing_data',missing_data)
    from public.coach_decisions where user_id=auth.uid()
    order by created_at desc limit 1)
);
$$;

-- 5. healthkit_auto_complete_workout → add session_effort=5 (moderate)
--    so future auto-completed sessions contribute to strain / ACWR
-- ---------------------------------------------------------------------------
create or replace function public.healthkit_auto_complete_workout(
  p_planned_workout_id uuid,
  p_local_date date
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid;
  v_plan_version_id uuid;
  v_duration_seconds integer;
  v_session_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select v.id into v_plan_version_id
  from public.planned_workouts w
  join public.training_plan_versions v
    on v.id = w.plan_version_id and v.user_id = w.user_id
  where w.id = p_planned_workout_id
    and w.user_id = v_user_id
    and v.status = 'active';

  if v_plan_version_id is null then
    raise exception 'planned workout not found or not in active plan';
  end if;

  if exists (
    select 1 from public.workout_sessions
    where user_id = v_user_id
      and planned_workout_id = p_planned_workout_id
      and local_date = p_local_date
      and state = 'completed'
  ) then
    return jsonb_build_object('session_id', null, 'replayed', true);
  end if;

  select coalesce(workout_minutes, 0) * 60 into v_duration_seconds
  from public.daily_health_summaries
  where user_id = v_user_id
    and local_date = p_local_date
    and source_scope = 'healthkit'
  limit 1;

  if v_duration_seconds = 0 then
    raise exception 'no HealthKit workout data available for this date';
  end if;

  insert into public.workout_sessions (
    user_id, plan_version_id, planned_workout_id,
    local_date, timezone, state, idempotency_key,
    started_at, completed_at, actual_started_at, actual_ended_at,
    duration_seconds, session_effort, notes
  ) values (
    v_user_id, v_plan_version_id, p_planned_workout_id,
    p_local_date, 'UTC', 'completed',
    gen_random_uuid(),
    now() - make_interval(secs := v_duration_seconds), now(),
    now() - make_interval(secs := v_duration_seconds), now(),
    v_duration_seconds,
    5,
    'Marked complete from Apple Health evidence'
  )
  returning id into v_session_id;

  insert into public.audit_events (
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    v_user_id, 'workout.auto_completed',
    'workout_session', v_session_id, 'succeeded',
    jsonb_build_object(
      'source', 'healthkit',
      'planned_workout_id', p_planned_workout_id,
      'local_date', p_local_date,
      'duration_seconds', v_duration_seconds,
      'effort', 5
    )
  );

  return jsonb_build_object(
    'session_id', v_session_id,
    'replayed', false,
    'effort', 5
  );
end;
$$;

commit;
