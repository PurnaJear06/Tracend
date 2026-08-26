begin;

-- Phase 4 Pipeline Fix v2 — compute on-the-fly (Noop pattern)
-- get_my_daily_brief no longer reads stale caches.  It calls
-- compute_daily_metrics fresh every time, which queries raw
-- data (workout_sessions, daily_health_summaries, etc.) directly.
-- get_my_training_hub switches from feature_snapshots to
-- daily_computed_metrics (populated by the fresh computation).

-- 1. get_my_daily_brief → always compute fresh
--    Was: STABLE SQL reading daily_computed_metrics cache.
--    Now: VOLATILE plpgsql calling compute_daily_metrics on-the-fly.
--    Response shape unchanged.  compute_daily_metrics still upserts
--    to daily_computed_metrics as a side-effect for other consumers.
-- ---------------------------------------------------------------------------
create or replace function public.get_my_daily_brief(
  target_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
volatile
as $$
declare
  v_user_id uuid := auth.uid();
  v_timezone text;
  v_metrics jsonb;
begin
  if v_user_id is null then
    return jsonb_build_object('schema_version', '1.1',
                              'local_date', target_date);
  end if;

  select coalesce(dhs.timezone, 'UTC') into v_timezone
  from public.daily_health_summaries dhs
  where dhs.user_id = v_user_id
    and dhs.source_scope = 'healthkit'
  order by dhs.local_date desc
  limit 1;

  begin
    v_metrics := public.compute_daily_metrics(
      v_user_id, target_date, v_timezone
    );
  exception when others then
    v_metrics := null;
  end;

  return jsonb_build_object(
    'schema_version', '1.1',
    'local_date', target_date,
    'today_workout', (
      select value->'today_workout'
      from (select public.get_my_training_hub(28) value) t
    ),
    'next_meal', (
      select item
      from (
        select public.get_my_nutrition_schedule(target_date) value
      ) n,
      jsonb_array_elements(value->'items') item
      where item->>'status' in ('due', 'upcoming', 'optional')
      order by (item->>'order')::integer
      limit 1
    ),
    'check_in', (
      select to_jsonb(c) - 'user_id' - 'note' - 'idempotency_key'
      from public.daily_check_ins c
      where c.user_id = v_user_id
        and c.local_date = target_date
        and c.superseded_at is null
      limit 1
    ),
    'health', (
      select jsonb_build_object(
        'local_date', d.local_date,
        'last_synced_at', d.last_synced_at,
        'present_types', d.present_types,
        'completeness', d.completeness
      )
      from public.daily_health_summaries d
      where d.user_id = v_user_id
        and d.local_date <= target_date
        and d.local_date >= target_date - 31
      order by d.local_date desc, d.last_synced_at desc
      limit 1
    ),
    'nutrition', public.get_my_daily_nutrition(target_date),
    'computed', v_metrics,
    'latest_decision', (
      select jsonb_build_object(
        'id', cd.id,
        'final_decision', cd.head_coach->>'final_decision',
        'reason', cd.head_coach->>'reason',
        'confidence', cd.confidence,
        'created_at', cd.created_at,
        'evidence', cd.evidence,
        'missing_data', cd.missing_data
      )
      from public.coach_decisions cd
      where cd.user_id = v_user_id
      order by cd.created_at desc
      limit 1
    )
  );
end;
$$;

-- 2. get_my_training_hub → read computed from daily_computed_metrics
--    Was: feature_snapshots (coaching point-in-time snapshot, stale).
--    Now: daily_computed_metrics (populated by compute_daily_metrics
--    on every get_my_daily_brief call, plus cron).
--    Only the latest_computed CTE changes; all other logic preserved.
-- ---------------------------------------------------------------------------
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
), latest_computed as (
  select dcm.scores_jsonb->'acwr' as acwr,
         dcm.scores_jsonb->'training_monotony' as monotony,
         dcm.scores_jsonb->'daily_strain' as today_strain
  from public.daily_computed_metrics dcm
  where dcm.user_id=auth.uid()
    and dcm.local_date=current_date
  order by dcm.computed_at desc
  limit 1
)
select jsonb_build_object(
  'schema_version','1.4','period_days',greatest(7,least(period_days,365)),
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
  'completed_day_set',coalesce(
    (select jsonb_agg(distinct local_date) from completed),'[]'::jsonb),
  'computed',(select jsonb_build_object(
    'acwr',acwr,'training_monotony',monotony,'today_strain',today_strain
  ) from latest_computed)
);
$$;

commit;
