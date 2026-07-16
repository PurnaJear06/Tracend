create or replace function public.prepare_coach_chat(
  target_user_id uuid,target_thread_id uuid,question text,
  coaching_timezone text,request_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare monthly_cost numeric; today_requests integer; existing_message uuid;
  prepared jsonb; schedule jsonb; context_payload jsonb; coaching_date date;
begin
  if target_user_id is null or not exists(select 1 from public.coach_threads
    where id=target_thread_id and user_id=target_user_id and status='active')
  then raise exception 'thread not found' using errcode='P0002'; end if;
  if length(trim(question)) not between 1 and 2000
    or length(coaching_timezone) not between 1 and 64
  then raise exception 'invalid chat request' using errcode='22023'; end if;
  select id into existing_message from public.coach_messages
  where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if existing_message is not null then
    return jsonb_build_object('replayed',true,'user_message_id',existing_message);
  end if;
  select coalesce(sum(estimated_cost_usd),0),
    count(*) filter(where purpose in ('daily_coaching','coach_chat')
      and created_at>=date_trunc('day',now()))
  into monthly_cost,today_requests from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=target_user_id and created_at>=date_trunc('month',now())
    union all
    select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=target_user_id and created_at>=date_trunc('month',now())
  ) all_usage;
  if monthly_cost>=5 then
    raise exception 'monthly cost limit reached' using errcode='P0001';
  end if;
  if today_requests>=30 then
    raise exception 'daily rate limit reached' using errcode='P0001';
  end if;
  select jsonb_build_object(
    'feature_snapshot_id',s.id,'policy_evaluation_id',p.id,
    'policy_outcome',p.outcome,
    'permitted_evidence',case p.outcome
      when 'escalate' then jsonb_build_array('APPROVED_PLAN_ACTIVE','CHECK_IN_SAFETY_ESCALATION','HEALTH_CONTEXT_AVAILABLE')
      when 'request_data' then jsonb_build_array('APPROVED_PLAN_ACTIVE','HEALTH_CONTEXT_AVAILABLE')
      else jsonb_build_array('APPROVED_PLAN_ACTIVE','RECOVERY_WITHIN_BASELINE','CHECK_IN_RECOVERY_MIXED','HEALTH_CONTEXT_AVAILABLE') end,
    'missing_data',to_jsonb(s.missing_data),
    'coaching_date',s.features->>'local_date') into prepared
  from public.feature_snapshots s join public.policy_evaluations p
    on p.feature_snapshot_id=s.id and p.user_id=s.user_id
  where s.user_id=target_user_id and s.trigger_kind='daily'
    and s.created_at>=date_trunc('day',now())
  order by s.created_at desc limit 1;
  if prepared is null then
    prepared:=public.prepare_daily_coaching(
      target_user_id,current_date,coaching_timezone,gen_random_uuid());
  end if;
  coaching_date:=coalesce((prepared->>'coaching_date')::date,current_date);
  select coalesce(jsonb_agg(jsonb_build_object(
    'slot_key',i.slot_key,'label',i.label,'local_time',to_char(i.local_time,'HH24:MI'),
    'foods',i.foods,'optional',i.optional) order by i.item_order),'[]'::jsonb)
  into schedule from public.nutrition_schedule_items i
  join public.nutrition_schedule_versions v on v.id=i.schedule_version_id
    and v.user_id=i.user_id
  where i.user_id=target_user_id and v.status='active';
  context_payload:=jsonb_build_object(
    'coaching_date',coaching_date,
    'profile_context',(select jsonb_build_object(
      'experience_level',experience_level,'height_cm',height_cm,
      'training_days',training_days,'session_minutes',session_minutes)
      from public.user_profiles where user_id=target_user_id),
    'active_goal',(select jsonb_build_object(
      'goal_type',goal_type,'priority',priority,'details',details)
      from public.user_goals where user_id=target_user_id and status='active'
      order by priority limit 1),
    'active_plan',(select jsonb_build_object('title',p.title,
      'version_number',v.version_number,'sessions_per_week',v.sessions_per_week,
      'rationale',v.rationale) from public.training_plan_versions v
      join public.training_plans p on p.id=v.plan_id and p.user_id=v.user_id
      where v.user_id=target_user_id and v.status='active' limit 1),
    'nutrition_targets',(select jsonb_build_object('calories',calories,
      'protein_g',protein_g,'carbohydrate_g',carbohydrate_g,'fat_g',fat_g)
      from public.nutrition_target_sets where user_id=target_user_id
      and status='active' limit 1),
    'nutrition_schedule',schedule,
    'confirmed_nutrition_history',(select coalesce(jsonb_agg(day_data order by local_date),'[]'::jsonb)
      from (select m.local_date,jsonb_build_object(
        'local_date',m.local_date,'confirmed_meals',count(distinct m.id),
        'calories',coalesce(sum(i.calories),0),'protein_g',coalesce(sum(i.protein_g),0),
        'carbohydrate_g',coalesce(sum(i.carbohydrate_g),0),'fat_g',coalesce(sum(i.fat_g),0)) day_data
        from public.meals m join public.meal_items i on i.meal_id=m.id and i.user_id=m.user_id
        where m.user_id=target_user_id and m.status='confirmed'
          and m.local_date between coaching_date-6 and coaching_date
        group by m.local_date order by m.local_date desc limit 7) nutrition_days),
    'latest_check_in',(select jsonb_build_object('local_date',local_date,
      'sleep_quality',sleep_quality,'energy',energy,'soreness',soreness,
      'hunger',hunger,'mood',mood,'pain_severity',pain_severity,
      'available_to_train',available_to_train)
      from public.daily_check_ins where user_id=target_user_id
      and superseded_at is null order by local_date desc limit 1),
    'healthkit_history',(select coalesce(jsonb_agg(day_data order by local_date),'[]'::jsonb)
      from (select local_date,jsonb_build_object(
        'local_date',local_date,'steps',steps,'active_energy_kcal',active_energy_kcal,
        'sleep_minutes',sleep_minutes,'workout_count',workout_count,
        'workout_minutes',workout_minutes,'weight_kg',weight_kg,
        'resting_heart_rate_bpm',resting_heart_rate_bpm,'hrv_sdnn_ms',hrv_value_ms,
        'present_types',present_types,'completeness',completeness) day_data
        from public.daily_health_summaries where user_id=target_user_id
          and local_date between coaching_date-6 and coaching_date
        order by local_date desc limit 7) health_days),
    'measurement_history',(select coalesce(jsonb_agg(measurement order by measured_on),'[]'::jsonb)
      from (select measured_on,jsonb_build_object(
        'measured_on',measured_on,'weight_kg',weight_kg,'waist_cm',waist_cm,
        'chest_cm',chest_cm,'hip_cm',hip_cm,'arm_cm',arm_cm,'thigh_cm',thigh_cm,
        'source',source) measurement
        from public.body_measurements where user_id=target_user_id
        order by measured_on desc,created_at desc limit 6) measurements),
    'latest_weekly_review',(select summary from public.progress_reviews
      where user_id=target_user_id order by review_week desc limit 1),
    'recent_execution',(select coalesce(jsonb_agg(row_data),'[]'::jsonb) from (
      select jsonb_build_object('local_date',s.local_date,'workout',w.name,
        'duration_seconds',s.duration_seconds,'effort',s.session_effort) row_data
      from public.workout_sessions s join public.planned_workouts w
        on w.id=s.planned_workout_id and w.user_id=s.user_id
      where s.user_id=target_user_id and s.state='completed'
      order by s.local_date desc limit 8) execution),
    'latest_decision',(select jsonb_build_object(
      'final_decision',head_coach->>'final_decision','reason',head_coach->>'reason',
      'evidence',evidence,'missing_data',missing_data,'confidence',confidence)
      from public.coach_decisions where user_id=target_user_id
      order by created_at desc limit 1),
    'recent_messages',(select coalesce(jsonb_agg(message order by created_at),'[]'::jsonb)
      from (select jsonb_build_object('role',role,'content',content) message,created_at
        from public.coach_messages where user_id=target_user_id
        and thread_id=target_thread_id order by created_at desc limit 20) recent),
    'permitted_evidence',prepared->'permitted_evidence',
    'missing_data',prepared->'missing_data');
  if length(context_payload::text)>18000 then
    raise exception 'chat context too large' using errcode='22023';
  end if;
  return jsonb_build_object('replayed',false,
    'feature_snapshot_id',prepared->>'feature_snapshot_id',
    'policy_evaluation_id',prepared->>'policy_evaluation_id',
    'policy_outcome',prepared->>'policy_outcome','context',context_payload,
    'budget_warning',monthly_cost>=3);
end $$;

revoke all on function public.prepare_coach_chat(uuid,uuid,text,text,uuid)
from public,anon,authenticated;
grant execute on function public.prepare_coach_chat(uuid,uuid,text,text,uuid)
to service_role;
