create extension if not exists pgtap with schema extensions;

create type public.unit_system as enum ('metric', 'imperial');
create type public.account_status as enum ('active', 'deletion_pending', 'deleted');
create type public.onboarding_state as enum ('not_started', 'in_progress', 'completed');

create table public.user_accounts (
  id uuid primary key references auth.users (id) on delete cascade,
  locale text not null default 'en' check (locale ~ '^[A-Za-z]{2,3}([_-][A-Za-z]{2})?$'),
  timezone text not null default 'UTC' check (length(timezone) between 1 and 64),
  unit_system public.unit_system not null default 'metric',
  account_status public.account_status not null default 'active',
  onboarding_state public.onboarding_state not null default 'not_started',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version integer not null default 1 check (row_version > 0)
);

comment on table public.user_accounts is
  'Application-owned account root keyed by the canonical Supabase Auth user ID.';

alter table public.user_accounts enable row level security;
alter table public.user_accounts force row level security;

create policy user_accounts_select_own
on public.user_accounts
for select
to authenticated
using (id = (select auth.uid()));

create policy user_accounts_insert_own
on public.user_accounts
for insert
to authenticated
with check (id = (select auth.uid()));

create policy user_accounts_update_own
on public.user_accounts
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

revoke all on public.user_accounts from anon;
revoke all on public.user_accounts from authenticated;
grant select on public.user_accounts to authenticated;
grant insert (id, locale, timezone, unit_system, onboarding_state)
on public.user_accounts to authenticated;
grant update (locale, timezone, unit_system, onboarding_state)
on public.user_accounts to authenticated;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create function private.set_updated_at_and_version()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = statement_timestamp();
  new.row_version = old.row_version + 1;
  return new;
end;
$$;

revoke all on function private.set_updated_at_and_version()
from public, anon, authenticated;

create trigger user_accounts_set_updated_at_and_version
before update on public.user_accounts
for each row
execute function private.set_updated_at_and_version();
