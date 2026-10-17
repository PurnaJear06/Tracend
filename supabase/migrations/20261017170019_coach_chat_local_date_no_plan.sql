-- Coach chat: the athlete's own date, one budget gate, and chat without a plan
-- (coaching platform chunk A9, migration code 19).
--
-- 1. The base prepare_coach_chat (under every chat layer, v2 to v8) built its context for
--    the UTC date: it asked prepare_daily_coaching for current_date and reused the day's
--    snapshot by UTC day. An athlete in India saw yesterday's meals and check-in from 00:00
--    to 05:30 local; one in the Americas saw an empty "today" every evening. It now uses
--    private.local_date_for (the account time zone, UTC when unset) and picks the snapshot
--    by its own local_date.
-- 2. The same function kept a second budget gate: USD 5 a month and 30 requests a day, in
--    literals. coach-chat reserves a place through reserve_ai_budget(_v2) before it prepares
--    anything, and that gate reads private.ai_budget_limits (USD 3 per athlete, owner
--    decision 2026-10-16). The literals are gone: that reservation is the only gate. The
--    budget_warning the app shows now follows the same limits row, from 80% of the stop (it was
--    the literal USD 3). get_my_ai_budget_state is redefined at the end with the same 80%
--    (owner decision, coaching platform A9; it was half the stop), so the chat context and
--    the Usage screen agree.
-- 3. prepare_daily_coaching raised 'approved plan required', so an athlete with no active
--    plan and nutrition target (including the see_professional screening outcome, which
--    builds none) could not chat at all. Its body moves to
--    private.prepare_daily_coaching_core, with for_chat: a chat turn does not need a plan
--    and is not counted by the daily decision's own 30-a-day limit (the reservation
--    already counted it). public.prepare_daily_coaching delegates with for_chat false, so
--    coach-decide behaves exactly as before. The chat context gains plan_status (whether
--    there is an active plan and nutrition target, why not, and the newest screening
--    outcome and date), and the plan is not offered as evidence the Coach may cite.
--
-- prepare_coach_chat_v8 and build_coach_athlete_context are not touched. prepare_coach_chat_v7
-- is copied from 20260927120000 with one change: it drops APPROVED_PLAN_ACTIVE from the
-- permitted evidence when plan_status says there is no active plan.

create function private.prepare_daily_coaching_core(
  target_user_id uuid,
  coaching_date date,
  coaching_timezone text,
  request_idempotency_key uuid,
  for_chat boolean
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
  if not for_chat and (select count(*) from public.model_runs where user_id=target_user_id and provider<>'mock'
      and created_at >= date_trunc('day',now())) >= 30
  then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
  select id into plan_id from public.training_plan_versions
    where user_id=target_user_id and status='active' limit 1;
  select id into target_id from public.nutrition_target_sets
    where user_id=target_user_id and status='active' limit 1;
  if not for_chat and (plan_id is null or target_id is null)
  then raise exception 'approved plan required' using errcode='22023'; end if;
  select * into check_in from public.daily_check_ins
    where user_id=target_user_id and local_date=coaching_date and superseded_at is null;
  select * into health from public.daily_health_summaries
    where user_id=target_user_id and local_date=coaching_date and source_scope='healthkit';

  begin
    metrics_jsonb := public.compute_daily_metrics(target_user_id, coaching_date, coaching_timezone);
  exception when others then
    metrics_jsonb := null;
  end;
  eligibility_jsonb := public.evaluate_change_eligibility(target_user_id, coaching_date);

  if check_in.id is null then
    missing := array['recovery_check_in']; outcome := 'request_data';
    rules := array['CHECK_IN_REQUIRED'];
  elsif check_in.pain_severity >= 7 then
    outcome := 'escalate'; rules := array['PAIN_SAFETY_THRESHOLD'];
  else
    outcome := 'maintain_only'; rules := array['INSUFFICIENT_CHANGE_EVIDENCE'];
  end if;
  if health.id is null then missing := missing || array['health_context']; end if;

  evidence := public.derive_daily_coaching_evidence(
    metrics_jsonb,
    check_in.id is not null,
    check_in.pain_severity,
    health.id is not null
  );

  snapshot_features := jsonb_build_object(
    'local_date',coaching_date,'timezone',coaching_timezone,
    'active_plan_version_id',plan_id,'active_nutrition_target_id',target_id,
    'check_in',case when check_in.id is null then null else jsonb_build_object(
      'sleep_quality',check_in.sleep_quality,'energy',check_in.energy,
      'soreness',check_in.soreness,'hunger',check_in.hunger,'mood',check_in.mood,
      'pain_severity',check_in.pain_severity,'available_to_train',check_in.available_to_train) end,
    'health_present_types',coalesce(to_jsonb(health.present_types),'[]'::jsonb)
  );

  snapshot_features := snapshot_features ||
    coalesce(metrics_jsonb, jsonb_build_object('scores_unavailable', true));
  snapshot_features := snapshot_features || jsonb_build_object('eligibility', eligibility_jsonb);

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

revoke all on function private.prepare_daily_coaching_core(uuid,date,text,uuid,boolean)
  from public, anon, authenticated;

create or replace function public.prepare_daily_coaching(
  target_user_id uuid,
  coaching_date date,
  coaching_timezone text,
  request_idempotency_key uuid
)
returns jsonb language sql security definer set search_path = '' as $$
  select private.prepare_daily_coaching_core(
    target_user_id, coaching_date, coaching_timezone, request_idempotency_key, false);
$$;

revoke all on function public.prepare_daily_coaching(uuid,date,text,uuid)
  from public,anon,authenticated;
grant execute on function public.prepare_daily_coaching(uuid,date,text,uuid)
  to service_role;

create or replace function public.prepare_coach_chat(
  target_user_id uuid,target_thread_id uuid,question text,
  coaching_timezone text,request_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare existing_message uuid;
  prepared jsonb; schedule jsonb; context_payload jsonb; coaching_date date;
  message_limit integer; local_day date; has_plan boolean; has_target boolean;
  screening_outcome text; screened_on text;
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
  local_day:=private.local_date_for(target_user_id);
  has_plan:=exists(select 1 from public.training_plan_versions
    where user_id=target_user_id and status='active');
  has_target:=exists(select 1 from public.nutrition_target_sets
    where user_id=target_user_id and status='active');
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
    and s.features->>'local_date'=local_day::text
    and (s.features->>'active_plan_version_id' is not null
      and s.features->>'active_nutrition_target_id' is not null)=(has_plan and has_target)
  order by s.created_at desc limit 1;
  if prepared is null then
    prepared:=private.prepare_daily_coaching_core(
      target_user_id,local_day,coaching_timezone,gen_random_uuid(),true);
  end if;
  if not (has_plan and has_target) then
    prepared:=jsonb_set(prepared,'{permitted_evidence}',
      (prepared->'permitted_evidence')-'APPROVED_PLAN_ACTIVE'::text);
  end if;
  coaching_date:=coalesce((prepared->>'coaching_date')::date,local_day);
  select s.outcome,to_char(s.screened_at at time zone 'UTC','YYYY-MM-DD')
  into screening_outcome,screened_on
  from public.onboarding_screenings s where s.user_id=target_user_id
  order by s.screened_at desc,s.id desc limit 1;
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
    'plan_status',jsonb_build_object(
      'has_active_plan',has_plan,'has_nutrition_target',has_target,
      'reason',case when has_plan and has_target then null
        when screening_outcome='see_professional' then 'see_professional'
        else 'no_approved_plan' end,
      'screening_outcome',screening_outcome,'screened_on',screened_on),
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
    'permitted_evidence',prepared->'permitted_evidence',
    'missing_data',prepared->'missing_data');
  foreach message_limit in array array[20,10,4,0] loop
    context_payload:=context_payload||jsonb_build_object('recent_messages',
      (select coalesce(jsonb_agg(message order by created_at,turn_rank),'[]'::jsonb)
       from (select jsonb_build_object('role',m.role,'content',m.content) message,m.created_at,
           case m.role when 'user' then 0 else 1 end turn_rank
         from public.coach_messages m where m.user_id=target_user_id
           and m.thread_id=target_thread_id
           and m.answer_source is distinct from 'data_summary'
         order by m.created_at desc,turn_rank desc limit message_limit) recent));
    exit when length(context_payload::text)<=18000;
  end loop;
  if length(context_payload::text)>18000 then
    raise exception 'chat context too large' using errcode='22023';
  end if;
  return jsonb_build_object('replayed',false,
    'feature_snapshot_id',prepared->>'feature_snapshot_id',
    'policy_evaluation_id',prepared->>'policy_evaluation_id',
    'policy_outcome',prepared->>'policy_outcome','context',context_payload,
    'budget_warning',(select t.monthly_cost>=l.per_person_monthly_usd*0.8
      from private.ai_usage_totals(target_user_id) t,private.ai_budget_limits l));
end $$;

revoke all on function public.prepare_coach_chat(uuid,uuid,text,text,uuid)
from public,anon,authenticated;
grant execute on function public.prepare_coach_chat(uuid,uuid,text,text,uuid)
to service_role;

create or replace function public.prepare_coach_chat_v7(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prepared jsonb; c jsonb; coaching_date date;
  metrics_jsonb jsonb; scores_jsonb jsonb; computed_metrics jsonb;
  evidence text[]; missing text[];
  check_in public.daily_check_ins%rowtype;
  has_health boolean;
  has_plan boolean;
begin
  prepared := public.prepare_coach_chat_v5(target_user_id, target_thread_id,
    question, coaching_timezone, request_idempotency_key, context_kind);
  if coalesce((prepared->>'replayed')::boolean, false) then return prepared; end if;

  c := prepared->'context';
  coaching_date := coalesce((c->>'coaching_date')::date, current_date);

  select * into check_in from public.daily_check_ins
    where user_id=target_user_id and local_date=coaching_date and superseded_at is null;
  select exists(select 1 from public.daily_health_summaries
    where user_id=target_user_id and local_date=coaching_date and source_scope='healthkit')
    into has_health;

  -- Same guard as get_my_daily_brief: a scoring failure must degrade chat to
  -- "scores unavailable", never make the whole conversation unavailable.
  begin
    metrics_jsonb := public.compute_daily_metrics(target_user_id, coaching_date, coaching_timezone);
    evidence := public.derive_daily_coaching_evidence(
      metrics_jsonb,
      check_in.id is not null,
      check_in.pain_severity,
      has_health
    );
  exception when others then
    metrics_jsonb := null;
    evidence := public.derive_daily_coaching_evidence(
      null,
      check_in.id is not null,
      check_in.pain_severity,
      has_health
    );
  end;
  -- derive_daily_coaching_evidence starts from the approved plan; an athlete
  -- without one must not be told the Coach may cite it.
  has_plan := coalesce((c->'plan_status'->>'has_active_plan')::boolean, true);
  if not has_plan then evidence := array_remove(evidence, 'APPROVED_PLAN_ACTIVE'); end if;
  scores_jsonb := metrics_jsonb->'scores';

  select coalesce(array_agg(value), '{}') into missing
  from jsonb_array_elements_text(coalesce(c->'missing_data','[]'::jsonb)) value
  where value not in ('health_context','recovery_check_in');
  if check_in.id is null then missing := missing || array['recovery_check_in']; end if;
  if not has_health then missing := missing || array['health_context']; end if;

  computed_metrics := case when metrics_jsonb is null then jsonb_build_object(
    'local_date', coaching_date,
    'unavailable', true,
    'reason', 'computed scores unavailable for this date')
  else jsonb_build_object(
    'local_date', coaching_date,
    'recovery', jsonb_build_object(
      'score', scores_jsonb->'recovery',
      'breakdown', scores_jsonb->'recovery_breakdown'),
    'sleep', jsonb_build_object(
      'quality', scores_jsonb->'sleep_quality',
      'debt_minutes', scores_jsonb->'sleep_debt_minutes'),
    'training_load', jsonb_build_object(
      'acwr', scores_jsonb->'acwr',
      'monotony', scores_jsonb->'training_monotony',
      'strain', scores_jsonb->'daily_strain'),
    'weight', jsonb_build_object(
      'trend_7d_kg_per_day', scores_jsonb->'weight_trend_7d_kg_per_day',
      'trend_28d_kg_per_day', scores_jsonb->'weight_trend_28d_kg_per_day'),
    'nutrition', jsonb_build_object(
      'adherence_pct', scores_jsonb->'macro_adherence_pct'),
    'data_confidence', metrics_jsonb->'data_confidence'
  ) end;

  c := c || jsonb_build_object(
    'schema_version', '7.0',
    'permitted_evidence', to_jsonb(evidence),
    'missing_data', to_jsonb(missing),
    'computed_metrics', computed_metrics
  );

  return prepared || jsonb_build_object('context', c);
end $$;

revoke all on function public.prepare_coach_chat_v7(uuid,uuid,text,text,uuid,text)
  from public, anon, authenticated;
grant execute on function public.prepare_coach_chat_v7(uuid,uuid,text,text,uuid,text)
  to service_role;

-- From 20261016004017: the warning moves from half the stop to 80% of it, and nothing else
-- changes (same signature, grants and fields).
create or replace function public.get_my_ai_budget_state()
returns jsonb language sql security definer set search_path='' stable as $$
select jsonb_build_object('schema_version','1.0','period','current_month',
  'estimated_cost_usd',totals.monthly_cost,
  'warning_threshold_usd',lim.per_person_monthly_usd * 0.8,
  'hard_stop_usd',lim.per_person_monthly_usd,
  'warning',totals.monthly_cost >= lim.per_person_monthly_usd * 0.8,
  'blocked',totals.monthly_cost >= lim.per_person_monthly_usd,
  'today_requests',totals.today_requests,
  'daily_limit',30)
from private.ai_usage_totals(auth.uid()) totals, private.ai_budget_limits lim;
$$;
