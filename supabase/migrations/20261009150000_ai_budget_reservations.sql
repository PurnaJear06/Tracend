-- AI budget reservations ----------------------------------------------------------------

-- A model call takes a place here before it runs and gives it back once its
-- usage is recorded (or no call was made). Open places count toward the
-- limits alongside recorded usage, so parallel calls cannot all pass a check
-- that only sees finished calls. A place that is never given back (the
-- function stopped mid-call) keeps counting at its ceiling: a crash can only
-- overcount, never undercount.
create table public.ai_budget_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  purpose text not null check (purpose in ('daily_coaching','coach_chat','meal_vision',
    'progress_vision','onboarding_plan','onboarding_questions')),
  reserved_cost_usd numeric(10,6) not null check (reserved_cost_usd > 0 and reserved_cost_usd <= 1),
  created_at timestamptz not null default now(),
  settled_at timestamptz
);
create index ai_budget_reservations_open on public.ai_budget_reservations(user_id, created_at)
  where settled_at is null;
create index ai_budget_reservations_month on public.ai_budget_reservations(created_at);
alter table public.ai_budget_reservations enable row level security;
alter table public.ai_budget_reservations force row level security;
revoke all on public.ai_budget_reservations from public, anon, authenticated;

-- The most one call of each purpose is expected to cost (COST_MODEL.md). An
-- open place counts at this amount.
create function private.ai_purpose_ceiling_usd(run_purpose text)
returns numeric language sql immutable set search_path = '' as $$
  select case run_purpose
    when 'coach_chat' then 0.02
    when 'daily_coaching' then 0.01
    when 'meal_vision' then 0.01
    when 'progress_vision' then 0.03
    when 'onboarding_plan' then 0.05
    when 'onboarding_questions' then 0.02
  end::numeric;
$$;
revoke all on function private.ai_purpose_ceiling_usd(text) from public, anon, authenticated;

-- One row: the spending stop across every account, changed from the SQL editor
-- (`update private.ai_budget_limits set global_monthly_usd = 20;`).
create table private.ai_budget_limits (
  singleton boolean primary key default true check (singleton),
  global_monthly_usd numeric(10,2) not null check (global_monthly_usd > 0 and global_monthly_usd <= 1000),
  updated_at timestamptz not null default now()
);
revoke all on private.ai_budget_limits from public, anon, authenticated, service_role;
insert into private.ai_budget_limits(global_monthly_usd) values (10);

-- This month's cost and today's requests for one athlete (null: every
-- athlete), recorded usage plus open reservations.
create function private.ai_usage_totals(target_user_id uuid)
returns table (monthly_cost numeric, today_requests bigint)
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(cost), 0), count(*) filter (where counted and created_at >= date_trunc('day', now()))
  from (
    select estimated_cost_usd cost, created_at, purpose in ('daily_coaching','coach_chat',
      'meal_vision','progress_vision','onboarding_plan','onboarding_questions') counted
    from public.model_runs
    where (target_user_id is null or user_id = target_user_id)
      and created_at >= date_trunc('month', now())
    union all
    select estimated_cost_usd, created_at, true from public.ai_usage_events
    where (target_user_id is null or user_id = target_user_id)
      and created_at >= date_trunc('month', now())
    union all
    select reserved_cost_usd, created_at, true from public.ai_budget_reservations
    where (target_user_id is null or user_id = target_user_id)
      and created_at >= date_trunc('month', now()) and settled_at is null
  ) usage;
$$;
revoke all on function private.ai_usage_totals(uuid) from public, anon, authenticated;

create function public.reserve_ai_budget(target_user_id uuid, run_purpose text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  athlete record;
  everyone record;
  reservation_id uuid;
  ceiling numeric := private.ai_purpose_ceiling_usd(run_purpose);
begin
  if ceiling is null then
    raise exception 'invalid purpose' using errcode = '22023';
  end if;
  -- One lock for every reservation: checks and inserts run one at a time, so
  -- the per-athlete and global totals are exact. Calls are seconds apart.
  perform pg_advisory_xact_lock(hashtextextended('tracend.ai_budget', 0));
  -- The new place counts too: a call is admitted only if its ceiling still
  -- fits under the stop, so the stop is never crossed.
  select * into athlete from private.ai_usage_totals(target_user_id);
  if athlete.monthly_cost + ceiling > 2 then
    raise exception 'monthly cost limit reached' using errcode = 'P0001';
  end if;
  if athlete.today_requests + 1 > 30 then
    raise exception 'daily rate limit reached' using errcode = 'P0001';
  end if;
  select * into everyone from private.ai_usage_totals(null);
  if everyone.monthly_cost + ceiling > (select global_monthly_usd from private.ai_budget_limits) then
    raise exception 'global monthly cost limit reached' using errcode = 'P0001';
  end if;
  insert into public.ai_budget_reservations(user_id, purpose, reserved_cost_usd)
  values (target_user_id, run_purpose, ceiling)
  returning id into reservation_id;
  return reservation_id;
end $$;
revoke all on function public.reserve_ai_budget(uuid, text) from public, anon, authenticated;
grant execute on function public.reserve_ai_budget(uuid, text) to service_role;

create function public.settle_ai_budget(reservation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.ai_budget_reservations set settled_at = now()
  where id = reservation_id and settled_at is null;
  delete from public.ai_budget_reservations where settled_at < now() - interval '40 days';
end $$;
revoke all on function public.settle_ai_budget(uuid) from public, anon, authenticated;
grant execute on function public.settle_ai_budget(uuid) to service_role;

-- Same rules, now including open reservations and the global stop. The
-- deployed functions keep calling this until their new versions (which
-- reserve) are live, one function at a time.
create or replace function public.assert_owner_ai_budget(target_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare athlete record; everyone record;
begin
  select * into athlete from private.ai_usage_totals(target_user_id);
  if athlete.monthly_cost>=2 then raise exception 'monthly cost limit reached' using errcode='P0001'; end if;
  if athlete.today_requests>=30 then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
  select * into everyone from private.ai_usage_totals(null);
  if everyone.monthly_cost>=(select global_monthly_usd from private.ai_budget_limits) then
    raise exception 'global monthly cost limit reached' using errcode='P0001';
  end if;
end $$;

create or replace function public.get_my_ai_budget_state()
returns jsonb language sql security definer set search_path='' stable as $$
select jsonb_build_object('schema_version','1.0','period','current_month',
  'estimated_cost_usd',monthly_cost,'warning_threshold_usd',1,'hard_stop_usd',2,
  'warning',monthly_cost>=1,'blocked',monthly_cost>=2,'today_requests',today_requests,
  'daily_limit',30)
from private.ai_usage_totals(auth.uid());
$$;

-- A failed Coach chat call records what it used ------------------------------------------

-- v1 stays for the deploy window; the new coach-chat calls v2.
create function public.persist_failed_coach_chat_run_v2(
  target_user_id uuid, snapshot_id uuid, policy_id uuid, request_idempotency_key uuid,
  run_latency_ms integer, error_code text, run_provider text, run_model text,
  failure_rules text[], run_input_units integer, run_output_units integer,
  run_estimated_cost_usd numeric
) returns uuid language plpgsql security definer set search_path = '' as $$
declare run_id uuid;
begin
  if run_input_units is null or run_input_units not between 0 and 10000000
    or run_output_units is null or run_output_units not between 0 and 1000000
    or run_estimated_cost_usd is null or run_estimated_cost_usd not between 0 and 100
  then raise exception 'invalid failure usage' using errcode = '22023'; end if;
  run_id := public.persist_failed_coach_chat_run(target_user_id, snapshot_id, policy_id,
    request_idempotency_key, run_latency_ms, error_code, run_provider, run_model, failure_rules);
  update public.model_runs
  set input_units = run_input_units, output_units = run_output_units,
    estimated_cost_usd = run_estimated_cost_usd
  where id = run_id and status = 'failed' and estimated_cost_usd = 0;
  return run_id;
end $$;
revoke all on function public.persist_failed_coach_chat_run_v2(uuid,uuid,uuid,uuid,integer,text,text,text,text[],integer,integer,numeric)
  from public, anon, authenticated;
grant execute on function public.persist_failed_coach_chat_run_v2(uuid,uuid,uuid,uuid,integer,text,text,text,text[],integer,integer,numeric)
  to service_role;
