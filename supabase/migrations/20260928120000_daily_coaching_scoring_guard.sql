-- A scoring failure no longer blocks the day's first coach chat.
--
-- prepare_coach_chat creates the day's feature snapshot through
-- prepare_daily_coaching when none exists yet, and that function computed
-- scores without the guard prepare_coach_chat_v7 and the Today brief apply.
-- If the scoring engine raised, the first question of the day failed with a
-- 422, and so did every later one, because no snapshot was stored. Scoring is
-- now guarded here as well: the snapshot is stored with scores marked
-- unavailable and evidence keeps only non-score codes, so chat and
-- coach-decide stay available. Everything else is unchanged from
-- 20260927120000.

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

revoke all on function public.prepare_daily_coaching(uuid,date,text,uuid)
  from public,anon,authenticated;
grant execute on function public.prepare_daily_coaching(uuid,date,text,uuid)
  to service_role;
