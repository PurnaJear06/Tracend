-- The AI notice becomes server data the owner can rewrite, tracked per purpose.
--
-- Athletes agree to a named provider for named purposes. The owner switches
-- providers, so the notice text lives here instead of in the app. A switch is
-- published with private.publish_ai_notice: one transaction inserts the new
-- notice and makes it current for its purposes.
--
-- Consent counts for a purpose only when the athlete's newest ai_coaching
-- record grants exactly the notice that is current for that purpose. A grant
-- of an older notice stops counting the moment a newer one is published.
--
-- Initial state, so nothing changes for the owner or installed builds:
--   ai-coaching-v1 (today's app text) is current for coach_chat and
--   daily_coaching. ai-coaching-v2 adds the starting plan built from onboarding
--   answers and is current for onboarding_plan only. After the app that renders
--   server notices is installed, the owner publishes v2 (or newer) for every
--   purpose and accepts it once.

create table public.ai_consent_notices (
  version text primary key check (version ~ '^[a-z0-9][a-z0-9.-]{0,31}$'),
  provider_label text not null check (length(provider_label) between 1 and 80),
  purposes text[] not null check (
    cardinality(purposes) between 1 and 3
    and purposes <@ array['coach_chat','daily_coaching','onboarding_plan']::text[]
  ),
  body text not null check (length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create table public.ai_notice_current (
  purpose text primary key check (purpose in ('coach_chat','daily_coaching','onboarding_plan')),
  version text not null references public.ai_consent_notices(version),
  updated_at timestamptz not null default now()
);

alter table public.ai_consent_notices enable row level security;
alter table public.ai_consent_notices force row level security;
alter table public.ai_notice_current enable row level security;
alter table public.ai_notice_current force row level security;
create policy ai_consent_notices_read on public.ai_consent_notices
  for select to authenticated using (true);
create policy ai_notice_current_read on public.ai_notice_current
  for select to authenticated using (true);
revoke all on public.ai_consent_notices, public.ai_notice_current from public, anon, authenticated;
grant select on public.ai_consent_notices, public.ai_notice_current to authenticated;

-- Publishes a notice and makes it current for each of its purposes, atomically.
-- Run by the owner from the SQL editor; published notices are never edited.
create function private.publish_ai_notice(
  notice_version text, notice_provider_label text, notice_purposes text[], notice_body text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.ai_consent_notices(version, provider_label, purposes, body)
  values (notice_version, notice_provider_label, notice_purposes, notice_body);
  insert into public.ai_notice_current(purpose, version)
  select purpose, notice_version from unnest(notice_purposes) purpose
  on conflict (purpose) do update set version = excluded.version, updated_at = now();
end $$;
revoke all on function private.publish_ai_notice(text, text, text[], text)
from public, anon, authenticated;

select private.publish_ai_notice(
  'ai-coaching-v1',
  'DeepSeek',
  array['coach_chat','daily_coaching'],
  'The Coach chat and your daily decision are written by an AI model. To write them, Tracend '
  'sends DeepSeek your training plan and workout logs, check-ins, Apple Health summaries (sleep, '
  'heart rate, HRV, steps and workouts), meals and nutrition targets, body measurements, goals '
  'and preferences, and the messages you send the Coach. Your name, email address and photos '
  'are not sent.' || E'\n\n' ||
  'DeepSeek is run by Hangzhou DeepSeek Artificial Intelligence Co., Ltd. and processes this '
  'data on servers in China. Its terms, not Tracend''s, decide how long it keeps requests.'
  || E'\n\n' ||
  'Without AI coaching, your plan, logging, Apple Health sync and progress keep working; the '
  'Coach chat and AI daily decisions stay off. You can change this at any time in Account.'
);

select private.publish_ai_notice(
  'ai-coaching-v2',
  'DeepSeek',
  array['onboarding_plan'],
  'Your starting plan, the Coach chat and your daily decision are written by an AI model. To '
  'write your starting plan, Tracend sends DeepSeek your onboarding answers: goal, age, sex, '
  'height, weight, daily activity, training days and session length, equipment, limitations, '
  'diet notes and, if you have one, your current plan. For the Coach chat and daily decision it '
  'sends your training plan and workout logs, check-ins, Apple Health summaries (sleep, heart '
  'rate, HRV, steps and workouts), meals and nutrition targets, body measurements, goals and '
  'preferences, and the messages you send the Coach. Your name, email address and photos are '
  'not sent.' || E'\n\n' ||
  'DeepSeek is run by Hangzhou DeepSeek Artificial Intelligence Co., Ltd. and processes this '
  'data on servers in China. Its terms, not Tracend''s, decide how long it keeps requests.'
  || E'\n\n' ||
  'Tracend checks every AI plan against its safety ranges, and nothing starts until you approve '
  'it. Without AI coaching, Tracend builds your starting plan with its own rules, and your plan, '
  'logging, Apple Health sync and progress keep working; the Coach chat and AI daily decisions '
  'stay off. You can change this at any time in Account.'
);

-- Consent for one purpose: the newest ai_coaching record grants the notice
-- that is current for that purpose.
create function public.has_ai_coaching_consent(target_user_id uuid, consent_purpose text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select record.action = 'granted' and record.notice_version = (
      select current.version from public.ai_notice_current current
      where current.purpose = consent_purpose
    )
    from public.consent_records record
    where record.user_id = target_user_id and record.consent_type = 'ai_coaching'
    order by record.created_at desc, record.id desc
    limit 1
  ), false);
$$;
revoke all on function public.has_ai_coaching_consent(uuid, text) from public, anon, authenticated;
grant execute on function public.has_ai_coaching_consent(uuid, text) to service_role;

-- The one-argument form, used by coach-chat and coach-decide, now follows the
-- notice current for the Coach chat instead of a hard-coded version.
create or replace function public.has_ai_coaching_consent(target_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_ai_coaching_consent(target_user_id, 'coach_chat');
$$;

-- The notice the app shows and records: the one current for the most purposes
-- (newest first on a tie), with the purposes it covers.
create function public.get_current_ai_notice()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'version', notice.version,
    'provider_label', notice.provider_label,
    'body', notice.body,
    'purposes', (
      select coalesce(jsonb_agg(current.purpose order by current.purpose), '[]'::jsonb)
      from public.ai_notice_current current where current.version = notice.version
    )
  )
  from public.ai_consent_notices notice
  join public.ai_notice_current current on current.version = notice.version
  group by notice.version, notice.provider_label, notice.body, notice.created_at
  order by count(*) desc, notice.created_at desc
  limit 1;
$$;
revoke all on function public.get_current_ai_notice() from public, anon, authenticated;
grant execute on function public.get_current_ai_notice() to authenticated;
