-- Phase 2 AI spending stops (migration code 17) -------------------------------------------

-- Owner decision 2026-10-16: USD 3 per athlete per month and a USD 50 stop across every
-- account (the global value is to be confirmed at cutover). Until now the per-athlete
-- stop was the literal 2 inside four functions; it moves into the one row that already
-- holds the global stop, so the owner changes either from the SQL editor:
--   update private.ai_budget_limits set per_person_monthly_usd = 3, updated_at = now();
--   update private.ai_budget_limits set global_monthly_usd = 50, updated_at = now();
-- The 30 calls a day per athlete stay as they are. No per-feature setting is needed:
-- each call's ceiling comes from its gateway route and the model price table.
--
-- Additive: one new column with a default of the old value, then the same four functions
-- with the same signatures, grants and error messages. The deployed Edge Functions and
-- the installed app keep working unchanged; `get_my_ai_budget_state` keeps every field
-- and only the values of `warning_threshold_usd`, `hard_stop_usd`, `warning` and
-- `blocked` follow the new limit.
alter table private.ai_budget_limits
  add column per_person_monthly_usd numeric(10,2) not null default 2
  check (per_person_monthly_usd > 0 and per_person_monthly_usd <= 1000);

update private.ai_budget_limits
set per_person_monthly_usd = 3, global_monthly_usd = 50, updated_at = now();

-- From 20261009150000.
create or replace function public.reserve_ai_budget(target_user_id uuid, run_purpose text)
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
  perform pg_advisory_xact_lock(hashtextextended('tracend.ai_budget', 0));
  select * into athlete from private.ai_usage_totals(target_user_id);
  if athlete.monthly_cost + ceiling > (select per_person_monthly_usd from private.ai_budget_limits) then
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

-- From 20261015120011.
create or replace function public.reserve_ai_budget_v2(
  target_user_id uuid, run_purpose text, ceiling_usd numeric
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  athlete record;
  everyone record;
  reservation_id uuid;
  stored_purpose text := private.ai_budget_purpose(run_purpose);
  ceiling numeric;
begin
  if stored_purpose is null then
    raise exception 'invalid purpose' using errcode = '22023';
  end if;
  if ceiling_usd is null or ceiling_usd < 0.001 or ceiling_usd > 0.50 then
    raise exception 'invalid ceiling' using errcode = '22023';
  end if;
  ceiling := ceil(ceiling_usd * 1000000) / 1000000;
  perform pg_advisory_xact_lock(hashtextextended('tracend.ai_budget', 0));
  select * into athlete from private.ai_usage_totals(target_user_id);
  if athlete.monthly_cost + ceiling > (select per_person_monthly_usd from private.ai_budget_limits) then
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
  values (target_user_id, stored_purpose, ceiling)
  returning id into reservation_id;
  return reservation_id;
end $$;

-- From 20261009150000.
create or replace function public.assert_owner_ai_budget(target_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare athlete record; everyone record;
begin
  select * into athlete from private.ai_usage_totals(target_user_id);
  if athlete.monthly_cost >= (select per_person_monthly_usd from private.ai_budget_limits) then
    raise exception 'monthly cost limit reached' using errcode='P0001';
  end if;
  if athlete.today_requests>=30 then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
  select * into everyone from private.ai_usage_totals(null);
  if everyone.monthly_cost>=(select global_monthly_usd from private.ai_budget_limits) then
    raise exception 'global monthly cost limit reached' using errcode='P0001';
  end if;
end $$;

-- From 20261009150000. The warning is half the stop, as before (USD 1 of 2).
create or replace function public.get_my_ai_budget_state()
returns jsonb language sql security definer set search_path='' stable as $$
select jsonb_build_object('schema_version','1.0','period','current_month',
  'estimated_cost_usd',totals.monthly_cost,
  'warning_threshold_usd',lim.per_person_monthly_usd / 2,
  'hard_stop_usd',lim.per_person_monthly_usd,
  'warning',totals.monthly_cost >= lim.per_person_monthly_usd / 2,
  'blocked',totals.monthly_cost >= lim.per_person_monthly_usd,
  'today_requests',totals.today_requests,
  'daily_limit',30)
from private.ai_usage_totals(auth.uid()) totals, private.ai_budget_limits lim;
$$;

-- Notices always name their vendor (migration code 17, part 2) ------------------------------

-- The provider column was added in 20261015120011 without a backfill, so every notice
-- published before it has provider null, and the old DeepSeek and Groq paths treat "null or
-- matching" as naming their vendor. A notice naming Anthropic published through a
-- four-argument publisher would also be null and would pass that rule. Two changes close it:
-- every existing row gets its vendor, and the four-argument publishers stop publishing.

-- The vendor a legacy notice named, from what the athlete read: its label and, for photo
-- notices, its model. Exactly one known company must be found; anything else raises, so
-- nothing is guessed.
create function private.notice_vendor_from_label(vendor_label text, vendor_model text)
returns text language plpgsql immutable set search_path = '' as $$
declare
  readable text := lower(coalesce(vendor_label, '') || ' ' || coalesce(vendor_model, ''));
  vendors_found text[] := array[]::text[];
begin
  if readable like '%deepseek%' then vendors_found := array_append(vendors_found, 'deepseek'::text); end if;
  if readable like '%groq%' or readable like '%qwen%' then vendors_found := array_append(vendors_found, 'groq'::text); end if;
  if readable like '%gemini%' or readable like '%google%' then vendors_found := array_append(vendors_found, 'gemini'::text); end if;
  if readable like '%anthropic%' or readable like '%claude%' then vendors_found := array_append(vendors_found, 'anthropic'::text); end if;
  if cardinality(vendors_found) <> 1 then
    raise exception 'cannot tell which vendor the notice named (label %, model %)',
      vendor_label, vendor_model using errcode = '22023';
  end if;
  return vendors_found[1];
end $$;
revoke all on function private.notice_vendor_from_label(text, text)
from public, anon, authenticated, service_role;

update public.ai_consent_notices
set provider = private.notice_vendor_from_label(provider_label, null)
where provider is null;

update public.photo_ai_notices
set provider = private.notice_vendor_from_label(provider_label, model)
where provider is null;

update public.meal_photo_ai_notices
set provider = private.notice_vendor_from_label(provider_label, model)
where provider is null;

-- Same signatures, argument names and (no) grants; they now refuse. The meal photo publisher
-- has only a five-argument form already.
create or replace function private.publish_ai_notice(
  notice_version text, notice_provider_label text, notice_purposes text[], notice_body text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'publish_ai_notice with four arguments no longer publishes: use private.publish_ai_notice(version, provider, provider_label, purposes, body)'
    using errcode = '22023';
end $$;

create or replace function private.publish_photo_ai_notice(
  notice_version text, notice_provider_label text, notice_model text, notice_body text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'publish_photo_ai_notice with four arguments no longer publishes: use private.publish_photo_ai_notice(version, provider, provider_label, model, body)'
    using errcode = '22023';
end $$;
