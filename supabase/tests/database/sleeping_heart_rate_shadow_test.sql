-- Sleeping heart rate stays in shadow mode (program decision D10, chunk C3).
--
-- Proof that nothing scores it:
--   1. an athlete's recovery score, readiness inputs and baselines are identical before and after
--      eight nights of sleeping heart rate are stored (extreme values included);
--   2. no function in public or private other than the one that saves nights mentions the table,
--      so no score, brief, baseline or Coach context can read it, and no view does either.
-- Moving it into the score is a later reviewed change that must update this test.
begin;
select plan(8);

insert into auth.users(id, role) values ('c3400000-0000-4000-8000-000000000001', 'authenticated');

-- A morning estimate (as recovery_modes_test.sql, user 2): eight days of HRV and resting heart
-- rate, today's morning HRV and a check-in.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, hrv_sleep_ms, hrv_morning_ms,
  resting_heart_rate_bpm)
select 'c3400000-0000-4000-8000-000000000001', current_date - d, 'UTC',
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
where user_id = 'c3400000-0000-4000-8000-000000000001' and hrv_sleep_ms is not null;

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, hrv_morning_ms)
values ('c3400000-0000-4000-8000-000000000001', current_date, 'UTC',
  array['hrv_sdnn'], '[]'::jsonb, repeat('c', 64), 'partial', now(), now(),
  41.0, 'sdnn', 'ms', 41.0);

insert into public.daily_check_ins(
  user_id, local_date, timezone, revision, idempotency_key,
  sleep_quality, energy, soreness, hunger, mood, available_to_train)
values ('c3400000-0000-4000-8000-000000000001', current_date, 'UTC',
  1, gen_random_uuid(), 4, 4, 2, 3, 4, true);

set local role service_role;

create temp table before_nights on commit drop as
select public.compute_daily_metrics(
  'c3400000-0000-4000-8000-000000000001', current_date, 'UTC') as m;
create temp table baselines_before on commit drop as
select metric_name, baseline_value, spread, n_observations
from public.user_baselines where user_id = 'c3400000-0000-4000-8000-000000000001';

select isnt((select (m->'scores'->>'recovery')::integer from before_nights), null,
  'the athlete has a recovery score to compare');

-- Eight nights of sleeping heart rate, far from the resting values above.
reset role;
insert into public.sleeping_heart_rate_nights(
  user_id, local_date, median_bpm, lowest_bpm, sample_count, asleep_minutes, coverage)
select 'c3400000-0000-4000-8000-000000000001', current_date - d, 31 + d, 30 + d, 120, 450, 0.9
from generate_series(0, 7) d;

set local role service_role;
create temp table after_nights on commit drop as
select public.compute_daily_metrics(
  'c3400000-0000-4000-8000-000000000001', current_date, 'UTC') as m;

select is((select m->'scores' from after_nights), (select m->'scores' from before_nights),
  'the recovery score and its breakdown are unchanged by stored sleeping heart rate');
select is((select m->'today_raw' from after_nights), (select m->'today_raw' from before_nights),
  'and so are the raw values behind it');
select is((select jsonb_agg(to_jsonb(b) order by b.metric_name) from (
    select metric_name, baseline_value, spread, n_observations
    from public.user_baselines where user_id = 'c3400000-0000-4000-8000-000000000001') b),
  (select jsonb_agg(to_jsonb(b) order by b.metric_name) from baselines_before b),
  'and so are the baselines');

reset role;
select is((select count(*) from public.sleeping_heart_rate_nights
    where user_id = 'c3400000-0000-4000-8000-000000000001'), 8::bigint,
  'the nights were stored while the score was computed');

select is((select array_agg(p.proname::text order by p.proname) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prosrc ilike '%sleeping_heart_rate%'),
  array['persist_sleeping_heart_rate_v1'],
  'only the save function mentions the table: no score, brief, baseline or Coach read can');
select is((select count(*) from pg_views
    where schemaname in ('public', 'private') and definition ilike '%sleeping_heart_rate%'),
  0::bigint, 'and no view does');
select is((select count(*) from pg_depend d
    join pg_rewrite r on r.oid = d.objid and d.classid = 'pg_rewrite'::regclass
    where d.refobjid = 'public.sleeping_heart_rate_nights'::regclass),
  0::bigint, 'and no rule or materialized view depends on it');

select * from finish();
rollback;
