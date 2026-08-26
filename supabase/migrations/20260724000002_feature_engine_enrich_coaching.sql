alter table public.feature_snapshots
  drop constraint feature_snapshots_schema_version_check;
alter table public.feature_snapshots
  add constraint feature_snapshots_schema_version_check
    check (schema_version in ('1.0', '2.0'));

alter table public.policy_evaluations
  drop constraint policy_evaluations_policy_version_check;
alter table public.policy_evaluations
  add constraint policy_evaluations_policy_version_check
    check (policy_version in ('daily-v1', 'eligibility-v1'));

create or replace function public.prepare_daily_coaching(
  target_user_id uuid,
  coaching_date date,
  coaching_timezone text,
  request_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  snapshot_id uuid; policy_id uuid; existing_run public.model_runs%rowtype;
  check_in public.daily_check_ins%rowtype; health public.daily_health_summaries%rowtype;
  plan_id uuid; target_id uuid; snapshot_features jsonb; evidence text[] := '{}';
  missing text[] := '{}'; outcome public.policy_outcome; rules text[] := '{}';
  snapshot_hash text; metrics_jsonb jsonb; eligibility_jsonb jsonb;
begin
  if target_user_id is null or not exists(select 1 from public.user_accounts where id=target_user_id)
  then raise exception 'account not found' using errcode='P0002'; end if;
  if length(coaching_timezone) not between 1 and 64
  then raise exception 'invalid timezone' using errcode='22023'; end if;
  select * into existing_run from public.model_runs
    where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if found then
    return jsonb_build_object('replayed',true,'model_run_id',existing_run.id);
  end if;
  if (select count(*) from public.model_runs where user_id=target_user_id and created_at >= date_trunc('day',now())) >= 10
  then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
  select id into plan_id from public.training_plan_versions
    where user_id=target_user_id and status='active' limit 1;
  select id into target_id from public.nutrition_target_sets
    where user_id=target_user_id and status='active' limit 1;
  if plan_id is null or target_id is null
  then raise exception 'approved plan required' using errcode='22023'; end if;
  select * into check_in from public.daily_check_ins
    where user_id=target_user_id and local_date=coaching_date and superseded_at is null;
  select * into health from public.daily_health_summaries
    where user_id=target_user_id and local_date=coaching_date and source_scope='healthkit';

  metrics_jsonb := public.compute_daily_metrics(target_user_id, coaching_date, coaching_timezone);
  eligibility_jsonb := public.evaluate_change_eligibility(target_user_id, coaching_date);

  evidence := array['APPROVED_PLAN_ACTIVE'];
  if check_in.id is null then
    missing := array['recovery_check_in']; outcome := 'request_data';
    rules := array['CHECK_IN_REQUIRED'];
  elsif check_in.pain_severity >= 7 then
    evidence := evidence || array['CHECK_IN_SAFETY_ESCALATION']; outcome := 'escalate';
    rules := array['PAIN_SAFETY_THRESHOLD'];
  else
    outcome := 'maintain_only'; rules := array['INSUFFICIENT_CHANGE_EVIDENCE'];
    if check_in.energy >= 3 and check_in.soreness <= 3 and check_in.pain_severity <= 2 then
      evidence := evidence || array['RECOVERY_WITHIN_BASELINE'];
    else
      evidence := evidence || array['CHECK_IN_RECOVERY_MIXED'];
    end if;
  end if;
  if health.id is null then missing := missing || array['health_context'];
  else evidence := evidence || array['HEALTH_CONTEXT_AVAILABLE']; end if;

  snapshot_features := jsonb_build_object(
    'local_date',coaching_date,'timezone',coaching_timezone,
    'active_plan_version_id',plan_id,'active_nutrition_target_id',target_id,
    'check_in',case when check_in.id is null then null else jsonb_build_object(
      'sleep_quality',check_in.sleep_quality,'energy',check_in.energy,
      'soreness',check_in.soreness,'hunger',check_in.hunger,'mood',check_in.mood,
      'pain_severity',check_in.pain_severity,'available_to_train',check_in.available_to_train) end,
    'health_present_types',coalesce(to_jsonb(health.present_types),'[]'::jsonb)
  );

  snapshot_features := snapshot_features || metrics_jsonb;
  snapshot_features := snapshot_features || jsonb_build_object(
    'eligibility', eligibility_jsonb
  );

  snapshot_hash := encode(extensions.digest(convert_to(snapshot_features::text,'UTF8'),'sha256'),'hex');
  insert into public.feature_snapshots(user_id,trigger_kind,schema_version,feature_engine_version,features,coverage,missing_data,data_hash)
    values(target_user_id,'daily','2.0','daily-v2',snapshot_features,
      jsonb_build_object('check_in',check_in.id is not null,'health',health.id is not null),missing,snapshot_hash)
    on conflict(user_id,data_hash) do update set data_hash=excluded.data_hash returning id into snapshot_id;
  insert into public.policy_evaluations(user_id,feature_snapshot_id,policy_version,outcome,rule_codes,permitted_actions,prohibited_actions)
    values(target_user_id,snapshot_id,'daily-v1',outcome,rules,
      case outcome when 'escalate' then array['ESCALATE'] when 'request_data' then array['GATHER_DATA','MAINTAIN_TARGETS'] else array['PROCEED_AS_PLANNED','GATHER_DATA','MAINTAIN_TARGETS'] end,
      array['PERSISTENT_CHANGE']) returning id into policy_id;
  return jsonb_build_object('replayed',false,'feature_snapshot_id',snapshot_id,
    'policy_evaluation_id',policy_id,'policy_outcome',outcome,
    'permitted_evidence',evidence,'missing_data',missing);
end $$;

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
  select features->'baselines' as baselines,
         features->'scores' as scores,
         features->'data_confidence' as data_confidence
  from public.feature_snapshots
  where user_id=auth.uid()
    and trigger_kind='daily'
    and feature_engine_version='daily-v2'
    and (features->>'local_date')::date = target_date
  order by created_at desc limit 1
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
  select features->'scores'->'acwr' as acwr,
         features->'scores'->'training_monotony' as monotony,
         features->'scores'->'daily_strain' as today_strain
  from public.feature_snapshots
  where user_id=auth.uid()
    and trigger_kind='daily'
    and feature_engine_version='daily-v2'
    and (features->>'local_date')::date = current_date
  order by created_at desc limit 1
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

select cron.schedule(
  'tracend-recompute-daily-metrics',
  '0 6 * * *',
  'select public.recompute_stale_metrics()'
);

revoke all on function public.prepare_daily_coaching(uuid,date,text,uuid)
  from public,anon,authenticated;
grant execute on function public.prepare_daily_coaching(uuid,date,text,uuid)
  to service_role;

revoke all on function public.get_my_daily_brief(date)
  from public,anon,authenticated;
grant execute on function public.get_my_daily_brief(date)
  to authenticated;

revoke all on function public.get_my_training_hub(integer)
  from public,anon,authenticated;
grant execute on function public.get_my_training_hub(integer)
  to authenticated;
