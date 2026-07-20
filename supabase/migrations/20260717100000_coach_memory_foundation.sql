create table public.coach_narrative_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  phase text not null check (length(phase) between 1 and 80),
  headline text not null check (length(headline) between 1 and 500),
  since date not null,
  until date,
  cause_snapshot_ids uuid[] not null default '{}',
  superseded_by uuid references public.coach_narrative_entries(id) on delete set null,
  created_at timestamptz not null default now()
);

create index coach_narrative_entries_user_active
  on public.coach_narrative_entries(user_id, since desc)
  where until is null;

alter table public.coach_narrative_entries enable row level security;
alter table public.coach_narrative_entries force row level security;
create policy coach_narrative_entries_own_read on public.coach_narrative_entries
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.coach_narrative_entries from anon, authenticated;
grant select on public.coach_narrative_entries to authenticated;

create table public.user_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  category text not null check (category in ('training','food','schedule','communication','notification','lifestyle')),
  key text not null check (length(key) between 1 and 120),
  value text not null check (length(value) between 1 and 200),
  provenance text not null check (provenance in ('onboarding','chat_statement','repeated_signal','manual')),
  confirmed_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index user_preferences_owner_key_active
  on public.user_preferences(user_id, key)
  where superseded_at is null;

alter table public.user_preferences enable row level security;
alter table public.user_preferences force row level security;
create policy user_preferences_own_read on public.user_preferences
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.user_preferences from anon, authenticated;
grant select on public.user_preferences to authenticated;

create table public.coach_session_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  coaching_date date not null,
  summary text not null check (length(summary) between 1 and 400),
  thread_id uuid,
  key_snapshot_ids uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

create index coach_session_summaries_user_date
  on public.coach_session_summaries(user_id, coaching_date desc);

alter table public.coach_session_summaries enable row level security;
alter table public.coach_session_summaries force row level security;
create policy coach_session_summaries_own_read on public.coach_session_summaries
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.coach_session_summaries from anon, authenticated;
grant select on public.coach_session_summaries to authenticated;
