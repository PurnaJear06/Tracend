-- Meal slot status on the athlete's clock (2026-10-04).
--
-- get_my_nutrition_schedule judged each slot with current_date and localtime,
-- the database session clock (UTC on Supabase). For an athlete in IST a 13:30
-- lunch was due at 19:00 local, and between local midnight and 05:30 the
-- requested day read as tomorrow, so every slot was 'upcoming'. The same
-- status feeds get_my_daily_brief.next_meal.
--
-- Now the slot is judged against the request's time in user_accounts.timezone
-- (an unset or unknown zone reads as UTC, as private.local_date_for does).
-- Slot windows compare timestamps on the requested day, so a window no longer
-- wraps around midnight. The response shape and schema_version 1.0 are
-- unchanged.

create function private.nutrition_slot_status(
  slot_date date,
  slot_time time,
  window_minutes integer,
  is_optional boolean,
  is_logged boolean,
  local_now timestamp
) returns text language sql immutable set search_path = '' as $$
  select case
    when is_logged then 'logged'
    when slot_date > local_now::date then 'upcoming'
    when slot_date < local_now::date then 'skipped'
    when local_now < slot_date + slot_time - make_interval(mins => window_minutes)
      then 'upcoming'
    when local_now <= slot_date + slot_time + make_interval(mins => window_minutes)
      then 'due'
    when is_optional then 'optional'
    else 'skipped'
  end;
$$;
revoke all on function private.nutrition_slot_status(date, time, integer, boolean, boolean, timestamp)
  from public, anon, authenticated;

create or replace function public.get_my_nutrition_schedule(target_date date default current_date)
returns jsonb language sql security definer set search_path='' stable as $$
with active as (
  select * from public.nutrition_schedule_versions
  where user_id=auth.uid() and status='active' limit 1
), logged as (
  select nutrition_schedule_item_id,min(created_at) logged_at
  from public.meals where user_id=auth.uid() and local_date=target_date
    and status='confirmed' and nutrition_schedule_item_id is not null
  group by nutrition_schedule_item_id
), athlete_now as (
  select now() at time zone coalesce((
    select a.timezone from public.user_accounts a
    join pg_catalog.pg_timezone_names z on z.name=a.timezone
    where a.id=auth.uid()),'UTC') local_now
)
select jsonb_build_object(
  'schema_version','1.0','local_date',target_date,
  'version',(select jsonb_build_object('id',id,'version_number',version_number,
    'title',title,'effective_date',effective_date) from active),
  'items',coalesce((select jsonb_agg(jsonb_build_object(
    'id',i.id,'order',i.item_order,'slot_key',i.slot_key,'label',i.label,
    'local_time',to_char(i.local_time,'HH24:MI'),'window_minutes',i.window_minutes,
    'foods',i.foods,'optional',i.optional,'reminder_enabled',i.reminder_enabled,
    'status',private.nutrition_slot_status(target_date,i.local_time,i.window_minutes,
      i.optional,l.logged_at is not null,n.local_now)
  ) order by i.item_order)
  from public.nutrition_schedule_items i
  join active a on a.id=i.schedule_version_id
  cross join athlete_now n
  left join logged l on l.nutrition_schedule_item_id=i.id),'[]'::jsonb)
);
$$;
