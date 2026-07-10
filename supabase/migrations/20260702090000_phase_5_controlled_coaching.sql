create type public.policy_outcome as enum (
  'allow', 'maintain_only', 'daily_adjustment_only', 'request_data', 'escalate'
);
create type public.model_run_status as enum ('succeeded', 'failed');

alter table public.feature_snapshots drop constraint feature_snapshots_trigger_kind_check;
alter table public.feature_snapshots add constraint feature_snapshots_trigger_kind_check
  check (trigger_kind in ('onboarding', 'daily'));

create table public.policy_evaluations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  feature_snapshot_id uuid not null,
  policy_version text not null check (policy_version = 'daily-v1'),
  outcome public.policy_outcome not null,
  rule_codes text[] not null default '{}',
  permitted_actions text[] not null default '{}',
  prohibited_actions text[] not null default '{}',
  created_at timestamptz not null default now(),
  foreign key (feature_snapshot_id, user_id)
    references public.feature_snapshots(id, user_id),
  unique (id, user_id)
);

create table public.model_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  feature_snapshot_id uuid not null,
  policy_evaluation_id uuid not null,
  idempotency_key uuid not null,
  purpose text not null check (purpose = 'daily_coaching'),
  provider text not null check (provider = 'mock'),
  model text not null check (model = 'deterministic-mock-v1'),
  prompt_version text not null check (prompt_version = 'daily-v1'),
  schema_version text not null check (schema_version = '1.0'),
  status public.model_run_status not null,
  validation_status text not null check (validation_status in ('passed', 'failed')),
  input_units integer not null default 0 check (input_units >= 0),
  output_units integer not null default 0 check (output_units >= 0),
  estimated_cost_usd numeric(10,6) not null default 0 check (estimated_cost_usd >= 0),
  latency_ms integer not null check (latency_ms between 0 and 120000),
  sanitized_error_code text check (
    sanitized_error_code is null or length(sanitized_error_code) between 1 and 80
  ),
  created_at timestamptz not null default now(),
  foreign key (feature_snapshot_id, user_id)
    references public.feature_snapshots(id, user_id),
  foreign key (policy_evaluation_id, user_id)
    references public.policy_evaluations(id, user_id),
  unique (user_id, idempotency_key),
  unique (id, user_id)
);

create table public.coach_decisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  feature_snapshot_id uuid not null,
  policy_evaluation_id uuid not null,
  model_run_id uuid not null,
  decision_kind text not null check (decision_kind = 'daily'),
  local_date date not null,
  schema_version text not null check (schema_version = '1.0'),
  training jsonb not null check (jsonb_typeof(training) = 'object'),
  nutrition jsonb not null check (jsonb_typeof(nutrition) = 'object'),
  head_coach jsonb not null check (jsonb_typeof(head_coach) = 'object'),
  evidence jsonb not null check (jsonb_typeof(evidence) = 'array'),
  confidence text not null check (confidence in ('low', 'medium', 'high')),
  missing_data text[] not null default '{}',
  risk_flags text[] not null default '{}',
  valid_until timestamptz not null,
  created_at timestamptz not null default now(),
  foreign key (feature_snapshot_id, user_id)
    references public.feature_snapshots(id, user_id),
  foreign key (policy_evaluation_id, user_id)
    references public.policy_evaluations(id, user_id),
  foreign key (model_run_id, user_id) references public.model_runs(id, user_id),
  unique (model_run_id),
  unique (id, user_id)
);

create index policy_evaluations_user_created on public.policy_evaluations(user_id, created_at desc);
create index model_runs_user_created on public.model_runs(user_id, created_at desc);
create index coach_decisions_user_date on public.coach_decisions(user_id, local_date desc, created_at desc);

alter table public.policy_evaluations enable row level security;
alter table public.policy_evaluations force row level security;
alter table public.model_runs enable row level security;
alter table public.model_runs force row level security;
alter table public.coach_decisions enable row level security;
alter table public.coach_decisions force row level security;

create policy policy_evaluations_own_read on public.policy_evaluations
for select to authenticated using (user_id = (select auth.uid()));
create policy model_runs_own_read on public.model_runs
for select to authenticated using (user_id = (select auth.uid()));
create policy coach_decisions_own_read on public.coach_decisions
for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.policy_evaluations, public.model_runs, public.coach_decisions
from anon, authenticated;
grant select on public.policy_evaluations, public.model_runs, public.coach_decisions
to authenticated;

create function public.prepare_daily_coaching(
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
  snapshot_hash text;
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
  snapshot_hash := encode(extensions.digest(convert_to(snapshot_features::text,'UTF8'),'sha256'),'hex');
  insert into public.feature_snapshots(user_id,trigger_kind,schema_version,feature_engine_version,features,coverage,missing_data,data_hash)
    values(target_user_id,'daily','1.0','daily-v1',snapshot_features,
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

create function public.persist_daily_coaching_result(
  target_user_id uuid, snapshot_id uuid, policy_id uuid,
  request_idempotency_key uuid, decision_payload jsonb, run_latency_ms integer
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare run_id uuid; decision_id uuid; policy public.policy_evaluations%rowtype;
begin
  select * into policy from public.policy_evaluations
    where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id;
  if not found then raise exception 'policy not found' using errcode='P0002'; end if;
  if jsonb_typeof(decision_payload) <> 'object'
    or decision_payload->>'schema_version' <> '1.0'
    or decision_payload->>'decision_kind' <> 'daily'
    or jsonb_array_length(decision_payload->'change_proposals') <> 0
  then raise exception 'invalid decision' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(decision_payload->'evidence') e
    where not (e->>'code'=any(
      case when policy.outcome='escalate' then array['APPROVED_PLAN_ACTIVE','CHECK_IN_SAFETY_ESCALATION','HEALTH_CONTEXT_AVAILABLE']
      when policy.outcome='request_data' then array['APPROVED_PLAN_ACTIVE','HEALTH_CONTEXT_AVAILABLE']
      else array['APPROVED_PLAN_ACTIVE','RECOVERY_WITHIN_BASELINE','CHECK_IN_RECOVERY_MIXED','HEALTH_CONTEXT_AVAILABLE'] end)))
  then raise exception 'unsupported evidence' using errcode='22023'; end if;
  insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,provider,model,prompt_version,schema_version,status,validation_status,latency_ms)
    values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'daily_coaching','mock','deterministic-mock-v1','daily-v1','1.0','succeeded','passed',run_latency_ms)
    on conflict(user_id,idempotency_key) do update set idempotency_key=excluded.idempotency_key returning id into run_id;
  select id into decision_id from public.coach_decisions where model_run_id=run_id;
  if decision_id is null then
    insert into public.coach_decisions(user_id,feature_snapshot_id,policy_evaluation_id,model_run_id,decision_kind,local_date,schema_version,training,nutrition,head_coach,evidence,confidence,missing_data,risk_flags,valid_until)
    values(target_user_id,snapshot_id,policy_id,run_id,'daily',(decision_payload->>'local_date')::date,'1.0',decision_payload->'training',decision_payload->'nutrition',decision_payload->'head_coach',decision_payload->'evidence',decision_payload->>'confidence',
      array(select jsonb_array_elements_text(decision_payload->'missing_data')),
      array(select jsonb_array_elements_text(decision_payload->'risk_flags')),now()+interval '24 hours') returning id into decision_id;
    insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
      values(target_user_id,'coach.decision.created','coach_decision',decision_id,
        'succeeded',jsonb_build_object('policy_outcome',policy.outcome,'schema_version','1.0'));
  end if;
  return jsonb_build_object('decision_id',decision_id,'model_run_id',run_id,'replayed',false);
end $$;

create function public.get_my_ai_usage()
returns jsonb language sql security definer set search_path='' stable as $$
  select jsonb_build_object('period','current_month','successful_runs',count(*) filter(where status='succeeded'),
    'failed_runs',count(*) filter(where status='failed'),'estimated_cost_usd',coalesce(sum(estimated_cost_usd),0))
  from public.model_runs where user_id=auth.uid() and created_at>=date_trunc('month',now());
$$;

create function public.persist_failed_coaching_run(
  target_user_id uuid, snapshot_id uuid, policy_id uuid,
  request_idempotency_key uuid, run_latency_ms integer,
  error_code text
)
returns uuid language plpgsql security definer set search_path='' as $$
declare run_id uuid;
begin
  if error_code is null or length(error_code) not between 1 and 80
  then raise exception 'invalid error code' using errcode='22023'; end if;
  if not exists(select 1 from public.policy_evaluations where id=policy_id
    and user_id=target_user_id and feature_snapshot_id=snapshot_id)
  then raise exception 'policy not found' using errcode='P0002'; end if;
  select id into run_id from public.model_runs
    where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if run_id is not null then return run_id; end if;
  insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,
    idempotency_key,purpose,provider,model,prompt_version,schema_version,status,
    validation_status,latency_ms,sanitized_error_code)
  values(target_user_id,snapshot_id,policy_id,request_idempotency_key,
    'daily_coaching','mock','deterministic-mock-v1','daily-v1','1.0','failed',
    'failed',run_latency_ms,error_code)
  returning id into run_id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
    values(target_user_id,'coach.model_run.failed','model_run',run_id,'rejected',
      jsonb_build_object('error_code',error_code,'schema_version','1.0'));
  return run_id;
end $$;

revoke all on function public.prepare_daily_coaching(uuid,date,text,uuid),
  public.persist_daily_coaching_result(uuid,uuid,uuid,uuid,jsonb,integer),
  public.persist_failed_coaching_run(uuid,uuid,uuid,uuid,integer,text)
  from public,anon,authenticated;
grant execute on function public.prepare_daily_coaching(uuid,date,text,uuid),
  public.persist_daily_coaching_result(uuid,uuid,uuid,uuid,jsonb,integer),
  public.persist_failed_coaching_run(uuid,uuid,uuid,uuid,integer,text)
  to service_role;
revoke all on function public.get_my_ai_usage() from public,anon,authenticated;
grant execute on function public.get_my_ai_usage() to authenticated;
