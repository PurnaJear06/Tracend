-- Phase 3: Coach Integration — Computed Scores → AI
--
-- 1. Replace check-in-based evidence codes in prepare_daily_coaching with
--    computed-score-based evidence from the feature engine.
-- 2. Add prepare_coach_chat_v6 wrapping v5 with computed_metrics section.

-- ============================================================
-- 1A: Enriched evidence codes in prepare_daily_coaching
-- ============================================================

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
  recovery_score integer; sleep_quality integer;
  acwr_val numeric; weight_trend numeric;
  adherence numeric; confidence text;
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

  -- Policy outcome (unchanged — pain-based + check-in presence)
  evidence := array['APPROVED_PLAN_ACTIVE'];
  if check_in.id is null then
    missing := array['recovery_check_in']; outcome := 'request_data';
    rules := array['CHECK_IN_REQUIRED'];
  elsif check_in.pain_severity >= 7 then
    evidence := evidence || array['CHECK_IN_SAFETY_ESCALATION']; outcome := 'escalate';
    rules := array['PAIN_SAFETY_THRESHOLD'];
  else
    outcome := 'maintain_only'; rules := array['INSUFFICIENT_CHANGE_EVIDENCE'];
  end if;
  if health.id is null then missing := missing || array['health_context'];
  else evidence := evidence || array['HEALTH_CONTEXT_AVAILABLE']; end if;

  -- Computed-score evidence codes (for AI context only, policy outcome unchanged)
  recovery_score := (metrics_jsonb->'scores'->>'recovery')::integer;
  sleep_quality := (metrics_jsonb->'scores'->>'sleep_quality')::integer;
  acwr_val := (metrics_jsonb->'scores'->>'acwr')::numeric;
  weight_trend := (metrics_jsonb->'scores'->>'weight_trend_7d_kg_per_day')::numeric;
  adherence := (metrics_jsonb->'scores'->>'macro_adherence_pct')::numeric;
  confidence := metrics_jsonb->>'data_confidence';

  -- Recovery evidence
  if recovery_score is not null and recovery_score >= 50 then
    evidence := evidence || array['RECOVERY_WITHIN_BASELINE'];
  elsif recovery_score is not null and recovery_score < 40 then
    evidence := evidence || array['RECOVERY_BELOW_BASELINE'];
  else
    evidence := evidence || array['CHECK_IN_RECOVERY_MIXED'];
  end if;

  -- Sleep quality evidence
  if sleep_quality is not null then
    if sleep_quality >= 50 then
      evidence := evidence || array['SLEEP_QUALITY_GOOD'];
    else
      evidence := evidence || array['SLEEP_QUALITY_POOR'];
    end if;
  end if;

  -- Training load evidence
  if acwr_val is not null then
    if acwr_val > 1.5 then
      evidence := evidence || array['TRAINING_LOAD_ELEVATED'];
    elsif acwr_val between 0.8 and 1.3 then
      evidence := evidence || array['TRAINING_LOAD_OPTIMAL'];
    end if;
  end if;

  -- Weight trend evidence
  if weight_trend is not null then
    if weight_trend < -0.1 then
      evidence := evidence || array['WEIGHT_TRENDING_DOWN'];
    elsif weight_trend > 0.1 then
      evidence := evidence || array['WEIGHT_TRENDING_UP'];
    else
      evidence := evidence || array['WEIGHT_STABLE'];
    end if;
  end if;

  -- Nutrition adherence evidence
  if adherence is not null then
    if adherence >= 80 then
      evidence := evidence || array['NUTRITION_ON_TRACK'];
    elsif adherence < 50 then
      evidence := evidence || array['NUTRITION_BEHIND'];
    end if;
  end if;

  -- Data confidence evidence
  if confidence is not null then
    if confidence = 'high' then
      evidence := evidence || array['DATA_CONFIDENCE_HIGH'];
    elsif confidence = 'low' or confidence = 'cold_start' then
      evidence := evidence || array['DATA_CONFIDENCE_LOW'];
    end if;
  end if;

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

revoke all on function public.prepare_daily_coaching(uuid,date,text,uuid)
  from public,anon,authenticated;
grant execute on function public.prepare_daily_coaching(uuid,date,text,uuid)
  to service_role;

-- ============================================================
-- 1B: prepare_coach_chat_v6 — wraps v5 with computed_metrics
-- ============================================================

create or replace function public.prepare_coach_chat_v6(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prepared jsonb; c jsonb;
  metrics_row public.daily_computed_metrics%rowtype;
  computed_metrics jsonb;
begin
  prepared := public.prepare_coach_chat_v5(target_user_id, target_thread_id,
    question, coaching_timezone, request_idempotency_key, context_kind);
  if coalesce((prepared->>'replayed')::boolean, false) then return prepared; end if;

  c := prepared->'context';

  select * into metrics_row from public.daily_computed_metrics
    where user_id = target_user_id
    order by computed_at desc limit 1;

  if metrics_row.id is not null then
    computed_metrics := jsonb_build_object(
      'recovery', jsonb_build_object(
        'score', metrics_row.recovery_score,
        'breakdown', metrics_row.scores_jsonb->'recovery_breakdown'),
      'sleep', case when metrics_row.sleep_quality_score is not null
        then jsonb_build_object('quality', metrics_row.sleep_quality_score,
          'debt_minutes', metrics_row.sleep_debt_minutes)
        else null end,
      'training_load', case when metrics_row.acwr is not null
        then jsonb_build_object('acwr', metrics_row.acwr,
          'monotony', metrics_row.training_monotony,
          'strain', metrics_row.daily_strain)
        else null end,
      'weight', case when metrics_row.weight_trend_7d_kg_per_day is not null
        then jsonb_build_object('trend_7d_kg_per_day', metrics_row.weight_trend_7d_kg_per_day,
          'trend_28d_kg_per_day', metrics_row.weight_trend_28d_kg_per_day)
        else null end,
      'nutrition', case when metrics_row.macro_adherence_pct is not null
        then jsonb_build_object('adherence_pct', metrics_row.macro_adherence_pct)
        else null end,
      'data_confidence', metrics_row.data_confidence,
      'computed_at', metrics_row.computed_at
    );
  else
    computed_metrics := jsonb_build_object('unavailable', true,
      'reason', 'Feature engine not yet computed for this user');
  end if;

  c := c || jsonb_build_object('computed_metrics', computed_metrics);

  return prepared || jsonb_build_object('context', c);
end $$;

grant execute on function public.prepare_coach_chat_v6(uuid,uuid,text,text,uuid,text)
  to service_role;

revoke all on function public.prepare_coach_chat_v6(uuid,uuid,text,text,uuid,text)
  from public, anon, authenticated;
