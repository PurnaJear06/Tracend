alter type public.consent_type add value if not exists 'notifications';

create table public.notification_preferences (
  user_id uuid primary key references public.user_accounts(id) on delete cascade,
  daily_check_in boolean not null default false,
  weekly_review boolean not null default false,
  authorization_status text not null check (
    authorization_status in (
      'not_determined', 'denied', 'authorized', 'provisional', 'ephemeral', 'unknown'
    )
  ),
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force row level security;
create policy notification_preferences_own_read
on public.notification_preferences for select to authenticated
using (user_id = (select auth.uid()));

revoke all on public.notification_preferences from anon, authenticated;
grant select on public.notification_preferences to authenticated;

create function public.save_my_notification_preferences(
  daily_check_in_enabled boolean,
  weekly_review_enabled boolean,
  ios_authorization_status text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  consent_action public.consent_action;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if ios_authorization_status not in (
    'not_determined', 'denied', 'authorized', 'provisional', 'ephemeral', 'unknown'
  ) then
    raise exception 'invalid authorization status' using errcode = '22023';
  end if;
  if (daily_check_in_enabled or weekly_review_enabled)
    and ios_authorization_status not in ('authorized', 'provisional', 'ephemeral')
  then
    raise exception 'notification permission required' using errcode = '22023';
  end if;

  insert into public.notification_preferences(
    user_id, daily_check_in, weekly_review, authorization_status
  ) values (
    auth.uid(), daily_check_in_enabled, weekly_review_enabled,
    ios_authorization_status
  )
  on conflict(user_id) do update
    set daily_check_in = excluded.daily_check_in,
        weekly_review = excluded.weekly_review,
        authorization_status = excluded.authorization_status,
        updated_at = now();

  consent_action := case
    when daily_check_in_enabled or weekly_review_enabled
      then 'granted'::public.consent_action
    else 'withdrawn'::public.consent_action
  end;
  insert into public.consent_records(
    user_id, consent_type, notice_version, action, source
  ) values (
    auth.uid(), 'notifications', 'notifications-v1', consent_action, 'ios_app'
  );
end
$$;

revoke all on function public.save_my_notification_preferences(boolean, boolean, text)
from public, anon, authenticated, service_role;
grant execute on function public.save_my_notification_preferences(boolean, boolean, text)
to authenticated;
