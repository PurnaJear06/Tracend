-- Review of PR #203: the refresh branch of private.sync_starter_meal_schedule rewrote the foods on
-- the active starter schedule in place and left no trace, while creating that schedule writes a
-- `nutrition.schedule.activated` audit event. A refresh now writes `nutrition.schedule.refreshed`
-- with the same metadata. The function is otherwise the body from 20261102224851 unchanged.
-- Additive and forward-only; safe for the installed app and Edge Functions.

create or replace function private.sync_starter_meal_schedule()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  current_schedule public.nutrition_schedule_versions%rowtype;
  starter_items jsonb := private.starter_schedule_items(new.calories, new.protein_g);
  next_version integer;
  version_id uuid;
begin
  select * into current_schedule from public.nutrition_schedule_versions
    where user_id = new.user_id and status = 'active';
  if found then
    if current_schedule.starter then
      update public.nutrition_schedule_items i set foods = s.foods
        from jsonb_to_recordset(starter_items) as s(slot_key text, foods jsonb)
        where i.schedule_version_id = current_schedule.id and i.slot_key = s.slot_key;
      insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
      values (new.user_id, 'nutrition.schedule.refreshed', 'nutrition_schedule_version',
        current_schedule.id, 'succeeded', jsonb_build_object(
          'version_number', current_schedule.version_number, 'item_count', 4,
          'starter', true, 'nutrition_target_set_id', new.id));
    end if;
    return new;
  end if;

  select coalesce(max(version_number), 0) + 1 into next_version
    from public.nutrition_schedule_versions where user_id = new.user_id;
  insert into public.nutrition_schedule_versions(
    user_id, version_number, status, title, rationale, approved_at, effective_date, starter)
  values (new.user_id, next_version, 'active', 'Starting meal schedule',
    'Four meals spread across the day, with your approved calories and protein split between '
    || 'them. It is a starting point: log each meal when you actually eat it.',
    now(), private.local_date_for(new.user_id), true)
  returning id into version_id;
  insert into public.nutrition_schedule_items(
    user_id, schedule_version_id, item_order, slot_key, label, local_time, window_minutes, foods,
    optional, reminder_enabled)
  select new.user_id, version_id, e.ord::smallint, e.item ->> 'slot_key', e.item ->> 'label',
    (e.item ->> 'local_time')::time, (e.item ->> 'window_minutes')::smallint, e.item -> 'foods',
    (e.item ->> 'optional')::boolean, (e.item ->> 'reminder_enabled')::boolean
  from jsonb_array_elements(starter_items) with ordinality as e(item, ord);
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (new.user_id, 'nutrition.schedule.activated', 'nutrition_schedule_version', version_id,
    'succeeded', jsonb_build_object('version_number', next_version, 'item_count', 4,
      'starter', true, 'nutrition_target_set_id', new.id));
  return new;
end $$;
revoke all on function private.sync_starter_meal_schedule() from public, anon, authenticated;
