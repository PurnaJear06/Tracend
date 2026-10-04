-- Recovery modes (2026-10-04, migration 20261004160000).
--
-- Under test:
--   1. persist_health_sync stores the night and morning HRV averages.
--   2. A night or morning HRV value never arrives without the day's HRV.
--   3. A morning estimate scores the morning HRV against mornings only, takes
--      yesterday's resting HR, and counts the check-in.
--   4. It settles at 12:00 local time: before noon recovery_settled is false,
--      from noon (or on a past day) it is true. A night is settled at once.
--   5. A watch-on night ignores the check-in and the morning readings.
--   6. Today's resting HR (revised by Apple through the day) moves neither
--      the score nor its baseline (review P1).
--   7. Breathing from a nap never makes a night (review P2).
--   8. A recomputed day stamps the scoring version (review P2).

begin;
select plan(18);

insert into auth.users(id, role) values
  ('a7000000-0001-4001-8001-000000000001', 'authenticated'),
  ('a7000000-0002-4001-8001-000000000002', 'authenticated'),
  ('a7000000-0003-4001-8001-000000000003', 'authenticated'),
  ('a7000000-0004-4001-8001-000000000004', 'authenticated');

set local role service_role;

-- 1. The sync stores both averages.
select lives_ok($$
  select public.persist_health_sync(
    'a7000000-0001-4001-8001-000000000001',
    'a7100000-0000-4000-8000-000000000001',
    '2026-10-03', '2026-10-04',
    array['hrv_sdnn'], array['hrv_sdnn'],
    '[{
      "local_date":"2026-10-04",
      "timezone":"Asia/Kolkata",
      "hrv_value_ms":44.5,
      "hrv_metric":"sdnn",
      "hrv_unit":"ms",
      "hrv_sleep_ms":52.25,
      "hrv_morning_ms":39.5,
      "present_types":["hrv_sdnn"],
      "source_refs":[{
        "type":"hrv_sdnn",
        "source_id_hash":"1111111111111111111111111111111111111111111111111111111111111111",
        "sample_id_hash":"2222222222222222222222222222222222222222222222222222222222222222"
      }],
      "source_checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "completeness":"complete",
      "observed_through":"2026-10-04T06:00:00Z"
    }]'::jsonb
  )
$$, '1: the sync accepts night and morning HRV');

select is(
  (select array[hrv_value_ms, hrv_sleep_ms, hrv_morning_ms]
   from public.daily_health_summaries
   where user_id = 'a7000000-0001-4001-8001-000000000001'),
  array[44.5, 52.25, 39.5]::numeric[],
  '1b: the day, night and morning HRV are stored as sent');

-- 2. Never without the day's HRV.
select throws_ok($$
  insert into public.daily_health_summaries(
    user_id, local_date, timezone, present_types, source_refs, source_checksum,
    completeness, observed_through, steps, hrv_sleep_ms)
  values ('a7000000-0001-4001-8001-000000000001', '2026-10-01', 'Asia/Kolkata',
    array['steps'], '[]'::jsonb, repeat('b', 64), 'partial', now(), 100, 50)
$$, '23514', null, '2: night HRV without the day''s HRV is rejected');

-- 3-4. User 2: five mornings (40-44 ms, resting HR 60-62) and three earlier
-- nights at 70 ms that must not touch the morning baseline. Today: 41 ms in
-- the morning, no night, a neutral-to-good check-in.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, hrv_sleep_ms, hrv_morning_ms,
  resting_heart_rate_bpm)
select 'a7000000-0002-4001-8001-000000000002', current_date - d, 'Asia/Kolkata',
  array['hrv_sdnn', 'resting_heart_rate'], '[]'::jsonb,
  md5(d::text) || md5(d::text), 'partial', now(), now(),
  v, 'sdnn', 'ms', night, v, rhr
from (values
  (8, 70.0, 70.0, 61.0), (7, 70.0, 70.0, 60.0), (6, 70.0, 70.0, 62.0),
  (5, 40.0, null, 61.0), (4, 44.0, null, 60.0), (3, 42.0, null, 62.0),
  (2, 43.0, null, 61.0), (1, 41.0, null, 60.0)
) s(d, v, night, rhr);

update public.daily_health_summaries
set hrv_morning_ms = null
where user_id = 'a7000000-0002-4001-8001-000000000002'
  and hrv_sleep_ms is not null;

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, hrv_morning_ms)
values ('a7000000-0002-4001-8001-000000000002', current_date, 'Asia/Kolkata',
  array['hrv_sdnn'], '[]'::jsonb, repeat('c', 64), 'partial', now(), now(),
  41.0, 'sdnn', 'ms', 41.0);

insert into public.daily_check_ins(
  user_id, local_date, timezone, revision, idempotency_key,
  sleep_quality, energy, soreness, hunger, mood, available_to_train)
values ('a7000000-0002-4001-8001-000000000002', current_date, 'Asia/Kolkata',
  1, gen_random_uuid(), 4, 4, 2, 3, 4, true);

create temp table morning on commit drop as
select public.compute_daily_metrics(
  'a7000000-0002-4001-8001-000000000002', current_date - 0, 'UTC') as m;

select is((select m->'scores'->>'recovery_mode' from morning), 'morning',
  '3: no night recorded -> a morning estimate');

select is(
  (select n_observations from public.user_baselines
   where user_id = 'a7000000-0002-4001-8001-000000000002'
     and metric_name = 'hrv_morning_ms'),
  6,
  '3b: the morning baseline folds the six mornings, never the 70 ms nights');

select is(
  (select (m->'today_raw'->>'resting_hr_scored_bpm')::numeric from morning),
  60.0,
  '3c: resting HR is yesterday''s final value (60), not today''s');

select is(
  (select (m->'scores'->'recovery_breakdown'->>'check_in_z')::numeric from morning),
  1.0,
  '3d: check-in z = mean(4, 4, 6 - 2, 4) - 3 = 1.0');

select is((select m->>'data_confidence' from morning), 'medium',
  '3e: a morning estimate with a morning reading is medium confidence');

select is(
  (select m->'scores'->'recovery_breakdown'->'weights' from morning),
  '{"hrv_sdnn": 40, "resting_hr": 20, "sleep_minutes": 10, "resp_rate": 0,
    "prev_strain": 5, "check_in": 25}'::jsonb,
  '3f: morning weights are published with the breakdown');

-- 4. Noon: pick a fixed-offset zone where it is still morning, and one where
-- it is afternoon, and score that zone's local today.
create temp table zones on commit drop as
select
  (select z from (
    select 'Etc/GMT' || case when n >= 0 then '+' else '' end || n as z
    from generate_series(-12, 12) n) a
   where extract(hour from now() at time zone z) between 1 and 10
   limit 1) as before_noon,
  (select z from (
    select 'Etc/GMT' || case when n >= 0 then '+' else '' end || n as z
    from generate_series(-12, 12) n) a
   where extract(hour from now() at time zone z) between 13 and 22
   limit 1) as after_noon;

select is(
  (select public.compute_daily_metrics(
     'a7000000-0002-4001-8001-000000000002',
     (now() at time zone before_noon)::date, before_noon)
     ->'scores'->>'recovery_settled'
   from zones),
  'false',
  '4: before 12:00 local the morning estimate is still settling');

select is(
  (select public.compute_daily_metrics(
     'a7000000-0002-4001-8001-000000000002',
     (now() at time zone after_noon)::date, after_noon)
     ->'scores'->>'recovery_settled'
   from zones),
  'true',
  '4b: from 12:00 local it is settled');

select is(
  public.compute_daily_metrics(
    'a7000000-0002-4001-8001-000000000002', current_date - 3, 'UTC')
    ->'scores'->>'recovery_settled',
  'true',
  '4c: a past day is settled');

-- 5. User 3: the same history, but today the watch was worn asleep. A poor
-- check-in and a low morning reading must not count.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, hrv_sleep_ms, hrv_morning_ms,
  resting_heart_rate_bpm)
select 'a7000000-0003-4001-8001-000000000003', local_date, timezone,
  present_types, source_refs, source_checksum, completeness,
  observed_through, last_synced_at, hrv_value_ms, hrv_metric, hrv_unit,
  hrv_sleep_ms, hrv_morning_ms, resting_heart_rate_bpm
from public.daily_health_summaries
where user_id = 'a7000000-0002-4001-8001-000000000002'
  and local_date < current_date;

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, hrv_sleep_ms, hrv_morning_ms,
  sleep_minutes)
values ('a7000000-0003-4001-8001-000000000003', current_date, 'Asia/Kolkata',
  array['hrv_sdnn', 'sleep'], '[]'::jsonb, repeat('d', 64), 'partial', now(),
  now(), 50.0, 'sdnn', 'ms', 70.0, 30.0, 450);

insert into public.daily_check_ins(
  user_id, local_date, timezone, revision, idempotency_key,
  sleep_quality, energy, soreness, hunger, mood, available_to_train)
values ('a7000000-0003-4001-8001-000000000003', current_date, 'Asia/Kolkata',
  1, gen_random_uuid(), 1, 1, 5, 3, 1, true);

create temp table night on commit drop as
select public.compute_daily_metrics(
  'a7000000-0003-4001-8001-000000000003', current_date - 0, 'UTC') as m;

select is(
  (select array[m->'scores'->>'recovery_mode',
                m->'scores'->>'recovery_settled',
                m->'scores'->'recovery_breakdown'->>'check_in_z']
   from night),
  array['night', 'true', '0.000'],
  '5: a watch-on night scores from the night, settled, check-in unused');

select ok(
  (select abs((m->'scores'->'recovery_breakdown'->>'hrv_z')::numeric) < 0.5
     and (m->'today_raw'->>'hrv_scored_ms')::numeric = 70.0
   from night),
  '5b: 70 ms tonight sits at the 70 ms night baseline, not far above the mornings');

-- 6. User 2 again: Apple writes a resting HR for today after noon.
create temp table before_rhr on commit drop as
select public.compute_daily_metrics(
  'a7000000-0002-4001-8001-000000000002', current_date - 0, 'UTC') as m;

update public.daily_health_summaries
set resting_heart_rate_bpm = 95,
    present_types = array['hrv_sdnn', 'resting_heart_rate']
where user_id = 'a7000000-0002-4001-8001-000000000002'
  and local_date = current_date;

select is(
  (select array[m->'scores'->>'recovery',
                m->'scores'->'recovery_breakdown'->>'rhr_z']
   from (select public.compute_daily_metrics(
     'a7000000-0002-4001-8001-000000000002', current_date - 0, 'UTC') as m) a),
  (select array[m->'scores'->>'recovery',
                m->'scores'->'recovery_breakdown'->>'rhr_z']
   from before_rhr),
  '6: a 95 bpm resting HR written today moves neither the score nor the baseline');

-- 7. User 4: no night HRV, a 40-minute nap with a breathing reading (as
-- older app builds sent it), a morning reading and history to compare.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, hrv_morning_ms, respiratory_rate_bpm,
  sleep_minutes)
select 'a7000000-0004-4001-8001-000000000004', current_date - d, 'Asia/Kolkata',
  array['hrv_sdnn', 'resp_rate', 'sleep'], '[]'::jsonb,
  md5('n' || d::text) || md5('n' || d::text), 'partial', now(), now(),
  40 + d, 'sdnn', 'ms', 40 + d, 14 + d * 0.2, 40
from generate_series(0, 4) d;

create temp table nap on commit drop as
select public.compute_daily_metrics(
  'a7000000-0004-4001-8001-000000000004', current_date - 0, 'UTC') as m;

select is((select m->'scores'->>'recovery_mode' from nap), 'morning',
  '7: breathing from a 40-minute nap is not a night');

select ok(
  (select m->'scores'->'recovery_breakdown'->'missing_components' ? 'resp_rate'
   from nap),
  '7b: the nap''s breathing rate does not count in the morning estimate');

-- 8. A day first stored by an older scoring version is restamped.
insert into public.daily_computed_metrics(
  user_id, local_date, data_confidence, schema_version)
values ('a7000000-0004-4001-8001-000000000004', current_date - 2, 'low', '2.2');

select public.compute_daily_metrics(
  'a7000000-0004-4001-8001-000000000004', current_date - 2, 'UTC');

select is(
  (select schema_version from public.daily_computed_metrics
   where user_id = 'a7000000-0004-4001-8001-000000000004'
     and local_date = current_date - 2),
  '2.3',
  '8: a recomputed day carries the scoring version that computed it');

select * from finish();
rollback;
