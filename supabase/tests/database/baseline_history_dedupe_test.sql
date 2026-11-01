-- Baseline history dedupe (migration 20261102041737, pre-beta audit P1-1):
-- metric_baseline_history holds one row per user, metric and observation
-- day, matching the newest fold. Repeated recomputes (brief, Coach,
-- decision, the recompute of an earlier day) write nothing; a new day adds
-- its row; a revised day rewrites its row and the later rows it moved; a
-- day no longer observed loses its row; same-day weigh-ins are one row,
-- the latest entry. The trail never feeds back: baselines and the brief's
-- metrics are the same with or without it, and a trail rebuilt from
-- scratch is the same trail. Deleting an athlete with a long trail is one
-- indexed pass (no table references the history any more).

begin;
select plan(30);

insert into auth.users(id, role) values
  ('b1d00000-0000-4000-8000-00000000000a', 'authenticated'),
  ('b1d00000-0000-4000-8000-00000000000b', 'authenticated');

-- Ten days of HRV, sleep and breathing rate; resting HR through the day
-- before yesterday only (yesterday's is still missing).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, resting_heart_rate_bpm, sleep_minutes,
  respiratory_rate_bpm)
select 'b1d00000-0000-4000-8000-00000000000a', current_date - d, 'Asia/Kolkata',
  array['hrv_sdnn', 'resting_heart_rate', 'sleep'], '[]'::jsonb,
  md5(d::text) || md5(d::text), 'partial', now(), now(),
  40 + (d % 5) * 3, 'sdnn', 'ms',
  case when d >= 2 then 54 + (d % 4) end,
  380 + d * 5,
  14 + (d % 3) * 0.5
from generate_series(1, 10) as d;

-- Three weigh-in days. Six days ago: two entries made at the same moment
-- (the higher id is the later). Three days ago: two entries an hour apart.
insert into public.body_measurements(
  id, user_id, measured_on, source, weight_kg, created_at) values
  ('b1d00000-0000-4000-8000-0000000000e0', 'b1d00000-0000-4000-8000-00000000000a',
   current_date - 9, 'manual', 80.0, now()),
  ('b1d00000-0000-4000-8000-0000000000e2', 'b1d00000-0000-4000-8000-00000000000a',
   current_date - 6, 'manual', 80.2, now()),
  ('b1d00000-0000-4000-8000-0000000000e1', 'b1d00000-0000-4000-8000-00000000000a',
   current_date - 6, 'manual', 80.4, now()),
  ('b1d00000-0000-4000-8000-0000000000e4', 'b1d00000-0000-4000-8000-00000000000a',
   current_date - 3, 'manual', 81.0, now() - interval '1 hour'),
  ('b1d00000-0000-4000-8000-0000000000e3', 'b1d00000-0000-4000-8000-00000000000a',
   current_date - 3, 'manual', 80.6, now());

-- 1-4. The table's shape --------------------------------------------------

select col_is_unique('public', 'metric_baseline_history',
  array['user_id', 'metric_name', 'observation_date'],
  '1: one history row per user, metric and observation day');

select col_not_null('public', 'metric_baseline_history', 'observation_date',
  '2: every history row has its observation day');

select is(
  (select count(*)::int from pg_catalog.pg_constraint
   where contype = 'f'
     and confrelid = 'public.metric_baseline_history'::regclass),
  0,
  '3: no foreign key references metric_baseline_history (no self-reference)');

select is(
  (select count(*)::int from pg_catalog.pg_constraint c
   where c.contype = 'f'
     and c.conrelid = 'public.metric_baseline_history'::regclass
     and not exists (
       select 1 from pg_catalog.pg_index i
       where i.indrelid = c.conrelid
         and (i.indkey::int2[])[0:cardinality(c.conkey) - 1] @> c.conkey
         and (i.indkey::int2[])[0:cardinality(c.conkey) - 1] <@ c.conkey)),
  0,
  '4: every foreign key on the history leads an index (cascade deletes stay indexed)');

-- 5-8. The first compute writes one row per observation day ---------------

create temp table brief_before as
select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date - 1, 'Asia/Kolkata') as metrics;

select is(
  (select string_agg(metric_name || ':' || n, ',' order by metric_name)
   from (select metric_name, count(*) as n from public.metric_baseline_history
         where user_id = 'b1d00000-0000-4000-8000-00000000000a'
         group by metric_name) m),
  'hrv_sdnn_ms:10,resp_rate_bpm:10,resting_hr_bpm:9,sleep_minutes:10,weight_kg:3',
  '5: first compute writes one row per observation day for each metric');

select set_eq(
  $$select observation_date from public.metric_baseline_history
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'
      and metric_name = 'hrv_sdnn_ms'$$,
  $$select local_date from public.daily_health_summaries
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  '6: history rows carry the real observation days');

select is(
  (select string_agg((observation_date - current_date) || ':' || n_observations
                     || ':' || raw_value, ',' order by observation_date)
   from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000a'
     and metric_name = 'weight_kg'),
  '-9:1:80.00,-6:3:80.20,-3:5:80.60',
  '7: same-day weigh-ins are one row, the state after the latest entry (created_at, then id)');

select is(
  (select count(*)::int
   from public.user_baselines b
   join lateral (
     select h.n_observations, h.spread from public.metric_baseline_history h
     where h.user_id = b.user_id and h.metric_name = b.metric_name
     order by h.observation_date desc limit 1) last_row on true
   where b.user_id = 'b1d00000-0000-4000-8000-00000000000a'
     and last_row.n_observations = b.n_observations
     and last_row.spread = b.spread),
  5,
  '8: each trail ends at its baseline (same count and spread)');

create temp table history_before as
select h.*, h.ctid::text as tuple from public.metric_baseline_history h
where h.user_id = 'b1d00000-0000-4000-8000-00000000000a';

create temp table baselines_before as
select metric_name, baseline_value, spread, n_observations, confidence,
  last_observation_date
from public.user_baselines
where user_id = 'b1d00000-0000-4000-8000-00000000000a';

-- 9-11. Repeated recomputes write nothing ---------------------------------

select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date - 1, 'Asia/Kolkata');
select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date - 1, 'Asia/Kolkata');
select public.compute_user_baselines(
  'b1d00000-0000-4000-8000-00000000000a', current_date - 2);
select public.compute_user_baselines(
  'b1d00000-0000-4000-8000-00000000000a', current_date - 1);

select is(
  (select count(*)::int from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000a'),
  42,
  '9: repeated recomputes (brief, older day, direct) add no rows');

select set_eq(
  $$select id, ctid::text as tuple from public.metric_baseline_history
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  $$select id, tuple from history_before$$,
  '10: repeated recomputes rewrite no row (every tuple is where it was)');

select is(
  public.compute_daily_metrics(
    'b1d00000-0000-4000-8000-00000000000a', current_date - 1, 'Asia/Kolkata'),
  (select metrics from brief_before),
  '11: the brief''s metrics are unchanged by the repeats');

-- 12-15. The trail never feeds back -----------------------------------------

delete from public.metric_baseline_history
where user_id = 'b1d00000-0000-4000-8000-00000000000a';

select is(
  public.compute_daily_metrics(
    'b1d00000-0000-4000-8000-00000000000a', current_date - 1, 'Asia/Kolkata'),
  (select metrics from brief_before),
  '12: the brief''s metrics are the same with the trail cleared');

select set_eq(
  $$select metric_name, baseline_value, spread, n_observations, confidence,
      last_observation_date
    from public.user_baselines
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  $$select * from baselines_before$$,
  '13: baselines are the same with the trail cleared');

select set_eq(
  $$select metric_name, observation_date, baseline_value, spread, n_observations,
      raw_value, was_winsorized, was_outlier_rejected, lambda_used, engine_version
    from public.metric_baseline_history
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  $$select metric_name, observation_date, baseline_value, spread, n_observations,
      raw_value, was_winsorized, was_outlier_rejected, lambda_used, engine_version
    from history_before$$,
  '14: a trail rebuilt by one compute is the same trail');

select is(
  (select count(*)::int from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000a'
     and prior_baseline_id is not null),
  0,
  '15: prior_baseline_id is no longer written');

-- 16-20. A new day adds exactly its row ------------------------------------

drop table history_before;
create temp table history_before as
select h.id, h.metric_name, h.ctid::text as tuple from public.metric_baseline_history h
where h.user_id = 'b1d00000-0000-4000-8000-00000000000a';

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('c0', 32), 'partial', now(), now(),
   47.0, 'sdnn', 'ms');

select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');

select is(
  (select count(*)::int from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000a'),
  43,
  '16: a new observation adds exactly one row');

select is(
  (select metric_name || ':' || n_observations || ':' || raw_value
   from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000a'
     and observation_date = current_date),
  'hrv_sdnn_ms:11:47.00',
  '17: the new row is today''s HRV, the eleventh observation');

select ok(
  (select bool_and(h.ctid::text = b.tuple)
   from history_before b
   join public.metric_baseline_history h on h.id = b.id
   where b.metric_name <> 'hrv_sdnn_ms'),
  '18: the new HRV day leaves the other metrics'' rows untouched');

create temp table trail_now as
select metric_name, observation_date, baseline_value, spread, n_observations,
  raw_value, was_winsorized, was_outlier_rejected, lambda_used, engine_version
from public.metric_baseline_history
where user_id = 'b1d00000-0000-4000-8000-00000000000a';
delete from public.metric_baseline_history
where user_id = 'b1d00000-0000-4000-8000-00000000000a';
select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');
select set_eq(
  $$select metric_name, observation_date, baseline_value, spread, n_observations,
      raw_value, was_winsorized, was_outlier_rejected, lambda_used, engine_version
    from public.metric_baseline_history
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  $$select * from trail_now$$,
  '19: after the new day the trail is the trail a rebuild writes');
drop table trail_now;

drop table history_before;
create temp table history_before as
select h.id, h.metric_name, h.observation_date, h.ctid::text as tuple
from public.metric_baseline_history h
where h.user_id = 'b1d00000-0000-4000-8000-00000000000a';

select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');
select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date - 1, 'Asia/Kolkata');

select set_eq(
  $$select id, ctid::text as tuple from public.metric_baseline_history
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  $$select id, tuple from history_before$$,
  '20: today again and yesterday''s recompute write nothing');

-- 21. A revised reading today rewrites its day's row ------------------------

update public.daily_health_summaries set hrv_value_ms = 52.0
where user_id = 'b1d00000-0000-4000-8000-00000000000a'
  and local_date = current_date;

select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');

select is(
  (select count(*)::int || ':' || max(raw_value)
   from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000a'
     and observation_date = current_date),
  '1:52.00',
  '21: a revised reading rewrites its day''s row, still one row');

-- 22-23. A revised older day rewrites its row and every later row -----------

drop table history_before;
create temp table history_before as
select h.id, h.metric_name, h.observation_date, h.ctid::text as tuple
from public.metric_baseline_history h
where h.user_id = 'b1d00000-0000-4000-8000-00000000000a';

update public.daily_health_summaries set hrv_value_ms = 50.0
where user_id = 'b1d00000-0000-4000-8000-00000000000a'
  and local_date = current_date - 5;

select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');

select is(
  (select count(*)::int
   from history_before b
   join public.metric_baseline_history h on h.id = b.id
   where b.metric_name = 'hrv_sdnn_ms'
     and b.observation_date >= current_date - 5
     and h.ctid::text <> b.tuple
     and h.observation_date = b.observation_date),
  6,
  '22: revising five days ago rewrites that row and the five later HRV rows');

create temp table trail_now as
select metric_name, observation_date, baseline_value, spread, n_observations,
  raw_value, was_winsorized, was_outlier_rejected, lambda_used, engine_version
from public.metric_baseline_history
where user_id = 'b1d00000-0000-4000-8000-00000000000a';
delete from public.metric_baseline_history
where user_id = 'b1d00000-0000-4000-8000-00000000000a';
select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');
select set_eq(
  $$select metric_name, observation_date, baseline_value, spread, n_observations,
      raw_value, was_winsorized, was_outlier_rejected, lambda_used, engine_version
    from public.metric_baseline_history
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  $$select * from trail_now$$,
  '23: after the older revision no row is stale (the trail a rebuild writes)');
drop table trail_now;

-- 24-26. An observation that goes away takes its row with it ----------------

update public.daily_health_summaries
set hrv_value_ms = null, hrv_metric = null, hrv_unit = null,
    present_types = array['resting_heart_rate', 'sleep']
where user_id = 'b1d00000-0000-4000-8000-00000000000a'
  and local_date = current_date - 7;

select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');

select is(
  (select count(*)::int || ':' || count(*) filter (where observation_date = current_date - 7)
   from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000a'
     and metric_name = 'hrv_sdnn_ms'),
  '10:0',
  '24: a removed HRV reading removes its row');

create temp table trail_now as
select metric_name, observation_date, baseline_value, spread, n_observations,
  raw_value, was_winsorized, was_outlier_rejected, lambda_used, engine_version
from public.metric_baseline_history
where user_id = 'b1d00000-0000-4000-8000-00000000000a';
delete from public.metric_baseline_history
where user_id = 'b1d00000-0000-4000-8000-00000000000a';
select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');
select set_eq(
  $$select metric_name, observation_date, baseline_value, spread, n_observations,
      raw_value, was_winsorized, was_outlier_rejected, lambda_used, engine_version
    from public.metric_baseline_history
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  $$select * from trail_now$$,
  '25: after the removal the trail is the trail a rebuild writes');
drop table trail_now;

update public.daily_health_summaries set respiratory_rate_bpm = null
where user_id = 'b1d00000-0000-4000-8000-00000000000a'
  and local_date <= current_date - 3;

select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');

select is(
  (select count(*)::int from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000a'
     and metric_name = 'resp_rate_bpm'),
  0,
  '26: below three observations the metric has no fold and no trail');

-- 27. Still nothing written on repeats ----------------------------------------

drop table history_before;
create temp table history_before as
select h.id, h.ctid::text as tuple from public.metric_baseline_history h
where h.user_id = 'b1d00000-0000-4000-8000-00000000000a';

select public.compute_daily_metrics(
  'b1d00000-0000-4000-8000-00000000000a', current_date, 'Asia/Kolkata');
select public.compute_user_baselines(
  'b1d00000-0000-4000-8000-00000000000a', current_date - 2);

select set_eq(
  $$select id, ctid::text as tuple from public.metric_baseline_history
    where user_id = 'b1d00000-0000-4000-8000-00000000000a'$$,
  $$select id, tuple from history_before$$,
  '27: after all the changes, repeats still write nothing');

-- 28-30. Deleting an athlete with a long trail is linear ----------------------

-- About eight years of daily history for all seven metrics: 21,000 rows.
-- With the old self-reference each deleted row scanned the table again
-- (about 4.4e8 row visits); the indexed cascade is one pass.
insert into public.metric_baseline_history(
  user_id, metric_name, baseline_value, spread, n_observations,
  observation_date, raw_value, lambda_used, engine_version)
select 'b1d00000-0000-4000-8000-00000000000b', m, 50, 5, g,
  current_date - g, 50, 0.05, 'baseline-v2'
from unnest(array['hrv_sdnn_ms', 'resting_hr_bpm', 'sleep_minutes', 'weight_kg',
                  'resp_rate_bpm', 'hrv_sleep_ms', 'hrv_morning_ms']) as m,
     generate_series(1, 3000) as g;

select is(
  (select count(*)::int from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000b'),
  21000,
  '28: the long trail is in place');

set local statement_timeout = '30s';
select lives_ok(
  $$delete from auth.users where id = 'b1d00000-0000-4000-8000-00000000000b'$$,
  '29: deleting the athlete finishes well inside the timeout');
set local statement_timeout = 0;

select is(
  (select count(*)::int from public.metric_baseline_history
   where user_id = 'b1d00000-0000-4000-8000-00000000000b'),
  0,
  '30: the deleted athlete''s trail is gone');

select * from finish();
rollback;
