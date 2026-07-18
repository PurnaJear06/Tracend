create or replace function public.get_my_training_hub(period_days integer default 28)
returns jsonb language sql security definer set search_path='' stable as $$
with active_version as (
  select v.id,v.plan_id,v.version_number,v.block_weeks,v.sessions_per_week,
    v.rationale,p.title
  from public.training_plan_versions v
  join public.training_plans p on p.id=v.plan_id and p.user_id=v.user_id
  where v.user_id=auth.uid() and v.status='active'
  limit 1
), workouts as (
  select w.*,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'order',e.exercise_order,'name',e.display_name_snapshot,
      'set_count',e.set_count,'rep_min',e.rep_min,'rep_max',e.rep_max,
      'target_rpe',e.target_rpe,'rest_seconds',e.rest_seconds,'notes',e.notes
    ) order by e.exercise_order)
    from public.planned_exercises e
    where e.planned_workout_id=w.id and e.user_id=auth.uid()),'[]'::jsonb) exercises
  from public.planned_workouts w join active_version v on v.id=w.plan_version_id
  where w.user_id=auth.uid()
), completed as (
  select s.id,s.planned_workout_id,s.local_date,s.duration_seconds,
    s.session_energy,s.session_effort,s.notes,s.completed_at,w.name
  from public.workout_sessions s
  join workouts w on w.id=s.planned_workout_id
  where s.user_id=auth.uid() and s.state='completed'
    and s.local_date >= current_date-greatest(7,least(period_days,365))+1
), progression as (
  select e.display_name_snapshot exercise,
    count(distinct s.id)::integer sessions,
    max(es.load_kg) filter(where es.completed) best_load_kg,
    max(es.repetitions) filter(where es.completed) best_repetitions,
    max(s.local_date) latest_date
  from public.workout_sessions s
  join public.exercise_performances ep on ep.workout_session_id=s.id
    and ep.user_id=s.user_id and ep.status='performed'
  join public.planned_exercises e on e.id=ep.planned_exercise_id
    and e.user_id=ep.user_id
  join public.exercise_sets es on es.exercise_performance_id=ep.id
    and es.user_id=ep.user_id
  where s.user_id=auth.uid() and s.state='completed' and es.completed
    and s.local_date >= current_date-greatest(7,least(period_days,365))+1
  group by e.display_name_snapshot
), healthkit_candidate as (
  select w.id as planned_workout_id, w.name as planned_workout_name,
    h.workout_count, h.workout_minutes, current_date as local_date
  from workouts w
  join public.daily_health_summaries h
    on h.user_id = auth.uid()
    and h.local_date = current_date
    and h.source_scope = 'healthkit'
    and h.workout_count > 0
  where not exists (
    select 1 from public.workout_sessions s
    where s.user_id = auth.uid()
      and s.planned_workout_id = w.id
      and s.local_date = current_date
      and s.state = 'completed'
  )
  and w.preferred_weekday = extract(isodow from current_date)::integer
  limit 1
)
select jsonb_build_object(
  'schema_version','1.1','period_days',greatest(7,least(period_days,365)),
  'active_plan',(select jsonb_build_object(
    'id',id,'plan_id',plan_id,'title',title,'version_number',version_number,
    'block_weeks',block_weeks,'sessions_per_week',sessions_per_week,
    'rationale',rationale) from active_version),
  'workouts',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'order',workout_order,'weekday',preferred_weekday,'name',name,
    'objective',objective,'estimated_minutes',estimated_minutes,
    'warm_up',warm_up_guidance,'cooldown_cardio',cool_down_guidance,
    'exercises',exercises) order by workout_order) from workouts),'[]'::jsonb),
  'today_workout',(select jsonb_build_object(
    'id',id,'weekday',preferred_weekday,'name',name,'objective',objective,
    'estimated_minutes',estimated_minutes,'warm_up',warm_up_guidance,
    'cooldown_cardio',cool_down_guidance,'exercises',exercises)
    from workouts where preferred_weekday=extract(isodow from current_date)::integer limit 1),
  'recent_sessions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'workout_id',planned_workout_id,'name',name,'local_date',local_date,
    'duration_seconds',duration_seconds,'effort',session_effort,'energy',session_energy
  ) order by local_date desc) from (select * from completed order by local_date desc limit 12) r),'[]'::jsonb),
  'adherence',jsonb_build_object(
    'completed_sessions',(select count(*) from completed),
    'planned_sessions',coalesce((select sessions_per_week from active_version),0)
      * greatest(1,ceil(greatest(7,least(period_days,365))/7.0)::integer)),
  'progression',coalesce((select jsonb_agg(jsonb_build_object(
    'exercise',exercise,'sessions',sessions,'best_load_kg',best_load_kg,
    'best_repetitions',best_repetitions,'latest_date',latest_date
  ) order by latest_date desc) from progression),'[]'::jsonb),
  'healthkit_completion_candidate',(select jsonb_build_object(
    'planned_workout_id',planned_workout_id,
    'planned_workout_name',planned_workout_name,
    'workout_count',workout_count,
    'workout_minutes',workout_minutes,
    'local_date',local_date
  ) from healthkit_candidate)
);
$$;

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
    duration_seconds, notes
  ) values (
    v_user_id, v_plan_version_id, p_planned_workout_id,
    p_local_date, 'UTC', 'completed',
    gen_random_uuid(),
    now() - make_interval(secs := v_duration_seconds), now(),
    now() - make_interval(secs := v_duration_seconds), now(),
    v_duration_seconds,
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
      'duration_seconds', v_duration_seconds
    )
  );

  return jsonb_build_object(
    'session_id', v_session_id,
    'replayed', false
  );
end;
$$;

grant execute on function public.healthkit_auto_complete_workout(uuid, date) to authenticated;
