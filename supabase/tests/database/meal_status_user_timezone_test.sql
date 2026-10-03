begin;
select plan(17);

-- Slot status on a fixed clock: an IST athlete -----------------------------------------------

select is(private.nutrition_slot_status('2026-10-05','13:30',60,false,false,'2026-10-05 13:45'),
  'due', 'a 13:30 lunch is due at 13:45 on the athlete''s clock');
select is(private.nutrition_slot_status('2026-10-05','13:30',60,false,false,'2026-10-05 12:00'),
  'upcoming', 'it is upcoming before its window opens');
select is(private.nutrition_slot_status('2026-10-05','13:30',60,false,false,'2026-10-05 14:31'),
  'skipped', 'it is skipped once its window closes');
select is(private.nutrition_slot_status('2026-10-05','22:00',60,true,false,'2026-10-05 23:01'),
  'optional', 'a closed optional slot stays optional');
select is(array[
    private.nutrition_slot_status('2026-10-04','08:00',60,false,false,'2026-10-05 02:00'),
    private.nutrition_slot_status('2026-10-05','08:00',60,false,false,'2026-10-05 02:00'),
    private.nutrition_slot_status('2026-10-06','08:00',60,false,false,'2026-10-05 02:00')],
  array['skipped','upcoming','upcoming'],
  'at 02:00 local (still the previous day in UTC) the athlete''s own date decides the day');
select is(array[
    private.nutrition_slot_status('2026-10-05','00:15',60,false,false,'2026-10-05 00:05'),
    private.nutrition_slot_status('2026-10-05','23:30',60,false,false,'2026-10-05 23:59')],
  array['due','due'],
  'a window that crosses midnight does not wrap around the day');
select is(private.nutrition_slot_status('2026-10-06','08:00',60,false,true,'2026-10-05 02:00'),
  'logged', 'a logged slot is logged whatever the clock says');
select ok(not has_function_privilege('authenticated',
  'private.nutrition_slot_status(date,time without time zone,integer,boolean,boolean,timestamp without time zone)',
  'execute'), 'clients cannot call the status helper directly');

-- Accounts in IST, in a zone on another date than UTC, and with an unknown zone --------------

insert into auth.users(id,role) values
 ('e8000000-0000-4000-8000-000000000001','authenticated'),
 ('e8000000-0000-4000-8000-000000000002','authenticated'),
 ('e8000000-0000-4000-8000-000000000003','authenticated');
update public.user_accounts set timezone='Asia/Kolkata'
where id='e8000000-0000-4000-8000-000000000001';
-- Niue (UTC-11) is on the previous date before 11:00 UTC, Kiritimati (UTC+14)
-- on the next date from 10:00 UTC.
update public.user_accounts set timezone=case
  when extract(hour from now() at time zone 'UTC')<10 then 'Pacific/Niue'
  else 'Pacific/Kiritimati' end
where id='e8000000-0000-4000-8000-000000000002';
update public.user_accounts set timezone='Mars/Olympus'
where id='e8000000-0000-4000-8000-000000000003';

create temporary table zone_day as
select a.id,(now() at time zone coalesce(z.name,'UTC'))::date local_date,
  now() at time zone coalesce(z.name,'UTC') local_now,
  (now() at time zone 'UTC')::date utc_date
from public.user_accounts a
left join pg_catalog.pg_timezone_names z on z.name=a.timezone
where a.id in ('e8000000-0000-4000-8000-000000000001',
  'e8000000-0000-4000-8000-000000000002','e8000000-0000-4000-8000-000000000003');

insert into public.nutrition_schedule_versions(
  id,user_id,version_number,status,title,rationale,approved_at,effective_date)
select ('e8100000-0000-4000-8000-00000000000'||right(id::text,1))::uuid,id,1,
  'active'::public.version_status,
  'Zone schedule','Reviewed schedule',now(),utc_date-1
from zone_day;
insert into public.nutrition_schedule_items(
  user_id,schedule_version_id,item_order,slot_key,label,local_time,window_minutes,foods,optional)
select d.id,('e8100000-0000-4000-8000-00000000000'||right(d.id::text,1))::uuid,
  s.item_order,s.slot_key,s.label,s.local_time,s.window_minutes,
  '[{"name":"Plan meal","quantity":"1 serving"}]'::jsonb,s.optional
from zone_day d cross join (values
  (1,'lunch','Lunch','13:30'::time,60,false),
  (2,'dinner','Dinner','20:00'::time,75,false),
  (3,'optional_curd','Optional curd','22:00'::time,60,true)
) s(item_order,slot_key,label,local_time,window_minutes,optional);

create temporary table expected as
select d.id,d.local_date,d.utc_date,
  jsonb_agg(private.nutrition_slot_status(d.local_date,i.local_time,i.window_minutes,
    i.optional,false,d.local_now) order by i.item_order) on_local_date,
  jsonb_agg(private.nutrition_slot_status(d.utc_date,i.local_time,i.window_minutes,
    i.optional,false,d.local_now) order by i.item_order) on_utc_date
from zone_day d
join public.nutrition_schedule_items i on i.user_id=d.id
group by d.id,d.local_date,d.utc_date;
grant select on expected to authenticated;

select isnt((select local_date from expected where id='e8000000-0000-4000-8000-000000000002'),
  (select utc_date from expected where id='e8000000-0000-4000-8000-000000000002'),
  'the far zone is on another date than UTC right now');

set local role authenticated;

set local "request.jwt.claim.sub"='e8000000-0000-4000-8000-000000000001';
select is(
  (select jsonb_agg(item->>'status' order by (item->>'order')::integer)
   from expected e,jsonb_array_elements(public.get_my_nutrition_schedule(e.local_date)->'items') item
   where e.id='e8000000-0000-4000-8000-000000000001'),
  (select on_local_date from expected where id='e8000000-0000-4000-8000-000000000001'),
  'an IST athlete''s slots are judged on IST time');
select is(
  (select jsonb_build_object(
     'schema_version',value->'schema_version',
     'item_keys',(select jsonb_agg(k order by k) from jsonb_object_keys(value->'items'->0) k))
   from expected e,public.get_my_nutrition_schedule(e.local_date) value
   where e.id='e8000000-0000-4000-8000-000000000001'),
  '{"schema_version":"1.0","item_keys":["foods","id","label","local_time","optional","order",
    "reminder_enabled","slot_key","status","window_minutes"]}'::jsonb,
  'the item shape and schema_version 1.0 are unchanged');

set local "request.jwt.claim.sub"='e8000000-0000-4000-8000-000000000002';
select is(
  (select jsonb_agg(item->>'status' order by (item->>'order')::integer)
   from expected e,jsonb_array_elements(public.get_my_nutrition_schedule(e.local_date)->'items') item
   where e.id='e8000000-0000-4000-8000-000000000002'),
  (select on_local_date from expected where id='e8000000-0000-4000-8000-000000000002'),
  'the athlete''s own date is today, judged on their time');
select is(
  (select jsonb_agg(item->>'status' order by (item->>'order')::integer)
   from expected e,jsonb_array_elements(public.get_my_nutrition_schedule(e.utc_date)->'items') item
   where e.id='e8000000-0000-4000-8000-000000000002'),
  (select case when utc_date<local_date then '["skipped","skipped","skipped"]'::jsonb
     else '["upcoming","upcoming","upcoming"]'::jsonb end
   from expected where id='e8000000-0000-4000-8000-000000000002'),
  'the UTC date is another day for this athlete');
select is(
  (select public.get_my_daily_brief(local_date)->'next_meal'
   from expected where id='e8000000-0000-4000-8000-000000000002'),
  coalesce((select item
   from expected e,jsonb_array_elements(public.get_my_nutrition_schedule(e.local_date)->'items') item
   where e.id='e8000000-0000-4000-8000-000000000002'
     and item->>'status' in ('due','upcoming','optional')
   order by (item->>'order')::integer limit 1),'null'::jsonb),
  'the daily brief''s next meal follows the athlete''s clock');
select is(
  (select public.get_my_daily_brief(utc_date)->'next_meal'->>'slot_key'
   from expected where id='e8000000-0000-4000-8000-000000000002'),
  (select case when utc_date<local_date then null else 'lunch' end
   from expected where id='e8000000-0000-4000-8000-000000000002'),
  'the brief for the UTC date has no next meal once that day has passed locally');

set local "request.jwt.claim.sub"='e8000000-0000-4000-8000-000000000003';
select is(
  (select jsonb_agg(item->>'status' order by (item->>'order')::integer)
   from expected e,jsonb_array_elements(public.get_my_nutrition_schedule(e.utc_date)->'items') item
   where e.id='e8000000-0000-4000-8000-000000000003'),
  (select on_utc_date from expected where id='e8000000-0000-4000-8000-000000000003'),
  'an unknown zone reads as UTC');
select is(
  (select local_date from expected where id='e8000000-0000-4000-8000-000000000003'),
  (select utc_date from expected where id='e8000000-0000-4000-8000-000000000003'),
  'and its local date is the UTC date');

select * from finish();
rollback;
