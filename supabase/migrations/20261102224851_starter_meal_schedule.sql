-- Pre-beta audit (origin/main 4421da9), new-user finding 7: a new athlete never had a meal
-- schedule. Schedules were seeded once, in 20260704150000, for the accounts that existed then, and
-- the only function that could create one (activate_my_nutrition_schedule) had no caller. Today's
-- Fuel rail said "No meal plan is set for today" for ever and Coach's "What is my next meal?" had
-- nothing to answer from. Additive and forward-only; every change is safe for the installed app.
--
-- 1. Approving nutrition targets (an onboarding approval or an approved Coach change) now gives
--    an athlete who has no active meal schedule a starting one: breakfast, lunch, a snack and
--    dinner, with the approved calories and protein split between them. The times are local clock
--    times (the schedule is judged on the athlete's own clock), reminders are off, and the snack
--    is optional. The version is marked `starter`.
-- 2. While the active schedule is still the starter, a newly approved target refreshes the
--    amounts in place, so a meal already logged against a slot keeps it. A schedule that is not
--    the starter (the owner's confirmed schedule) is never touched.
-- 3. `breakfast` joins the slot names the table accepts (a widening; nothing narrows).
-- 4. activate_my_nutrition_schedule is dropped. It let an athlete replace their schedule from raw
--    JSON without a proposal and approval, and nothing in the app, the Edge Functions or the tests
--    calls it. A change path for the schedule needs its own approval flow.
--
-- No existing account is backfilled: a read of production before this migration found every
-- account that has approved targets already has an active schedule.

-- 1. The starter marker and the new slot name -------------------------------------------------

alter table public.nutrition_schedule_versions
  add column starter boolean not null default false;

alter table public.nutrition_schedule_items
  drop constraint nutrition_schedule_items_slot_key_check;
alter table public.nutrition_schedule_items
  add constraint nutrition_schedule_items_slot_key_check check (slot_key in (
    'breakfast','pre_workout','post_workout','lunch','snack','dinner','optional_curd'
  ));

-- 2. The starting schedule for a set of targets ------------------------------------------------

-- Four slots. Each takes a share of the day's calories (to the nearest 10) and protein (to the
-- nearest 5 g); the amounts are the approved targets split, not a prescription of foods.
create function private.starter_schedule_items(target_calories integer, target_protein_g integer)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_agg(jsonb_build_object(
    'slot_key', s.slot_key,
    'label', s.label,
    'local_time', s.local_time,
    'window_minutes', 60,
    'foods', jsonb_build_array(jsonb_build_object(
      'name', 'Meal target',
      'quantity', 'about ' || (round(target_calories * s.share / 10) * 10)::integer::text
        || ' kcal and ' || (round(target_protein_g * s.share / 5) * 5)::integer::text
        || ' g protein')),
    'optional', s.optional,
    'reminder_enabled', false) order by s.item_order)
  from (values
    (1, 'breakfast', 'Breakfast', '08:00', 0.25, false),
    (2, 'lunch', 'Lunch', '13:00', 0.30, false),
    (3, 'snack', 'Snack', '16:30', 0.15, true),
    (4, 'dinner', 'Dinner', '19:30', 0.30, false)
  ) s(item_order, slot_key, label, local_time, share, optional);
$$;
revoke all on function private.starter_schedule_items(integer, integer)
  from public, anon, authenticated;

create function private.sync_starter_meal_schedule()
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

-- Only approved targets (they carry the proposal that was approved) start or refresh a schedule.
create trigger nutrition_target_sets_starter_schedule
  after insert or update of status on public.nutrition_target_sets
  for each row
  when (new.status = 'active' and new.source_proposal_id is not null)
  execute function private.sync_starter_meal_schedule();

-- 3. No more schedule replacement from raw JSON --------------------------------------------------

drop function public.activate_my_nutrition_schedule(text, text, date, jsonb);
