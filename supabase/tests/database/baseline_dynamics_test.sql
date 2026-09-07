-- Pass 3 — Baseline dynamics (migration 20260907160000).
--
-- Required behavior under test:
--   3a. Spread as a 21-day-half-life EWMA with per-metric floors:
--       1. Identical-value histories are floored (spread = floor, never
--          0) so z stays finite and scoreable.
--       2. The floor is per metric (helper pinned for all five).
--       3. A varied history exceeds its floor (the EWMA tracks real
--          noise above it).
--   3b. Staleness:
--       4. last_observation_date stamps the TRUE newest observation date
--          (not the compute target_date) — the 08-26-data-on-09-07-sync
--          case reads as 08-26.
--       5. The brief carries additive per-metric last_obs_date + age_days
--          (age 0 = today); never-observed metrics report null, not 0 —
--          the anti-masquerade rule.
--       6. The cold-start row stamps the floor spread and the true
--          single-observation date.
--       7. The brief reports schema 1.5.
--   Regression guards:
--       8. ln-domain scale invariance survives (x3-scaled HRV histories
--          yield identical z) — the spread EWMA must not break the
--          property Pass 2 introduced.

begin;
select plan(14);

-- auth.users inserts auto-create user_accounts via trigger.
insert into auth.users(id, role) values
  ('ab31a000-0001-4001-8001-0000000000b1', 'authenticated'),
  ('ab31a000-0002-4001-8001-0000000000b2', 'authenticated'),
  ('ab31a000-0003-4001-8001-0000000000b3', 'authenticated'),
  ('ab31a000-0004-4001-8001-0000000000b4', 'authenticated'),
  ('ab31a000-0005-4001-8001-0000000000b5', 'authenticated');

-- User 1: 6 nights of sleep with real variance (fold runs).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at,
  sleep_minutes)
select
  'ab31a000-0001-4001-8001-0000000000b1',
  current_date - g, 'Asia/Kolkata', array['sleep'], '[]'::jsonb,
  repeat(md5(g::text), 2), 'partial', now(), now(),
  420.0 + (g * 17)
from generate_series(1, 6) g;

-- User 2: identical values every night (spread would be 0 without a
-- floor; the floor must hold).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at,
  sleep_minutes)
select
  'ab31a000-0002-4001-8001-0000000000b2',
  current_date - g, 'Asia/Kolkata', array['sleep'], '[]'::jsonb,
  repeat(md5(g::text), 2), 'partial', now(), now(),
  440.0
from generate_series(1, 6) g;

-- User 3: HRV x1; User 4: HRV x3 (scale-invariance pair, 6 nights each).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
select
  'ab31a000-0003-4001-8001-0000000000b3',
  current_date - g, 'Asia/Kolkata', array['hrv_sdnn'], '[]'::jsonb,
  repeat(md5(g::text), 2), 'partial', now(), now(),
  40.0 + (g * 3), 'sdnn', 'ms'
from generate_series(1, 6) g;
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
select
  'ab31a000-0004-4001-8001-0000000000b4',
  current_date - g, 'Asia/Kolkata', array['hrv_sdnn'], '[]'::jsonb,
  repeat(md5(g::text), 2), 'partial', now(), now(),
  (40.0 + (g * 3)) * 3, 'sdnn', 'ms'
from generate_series(1, 6) g;

-- Fold all four (postgres superuser; compute is revoked from
-- authenticated — the future_date_guard_test pattern).
select public.compute_user_baselines(
  'ab31a000-0001-4001-8001-0000000000b1', current_date);
select public.compute_user_baselines(
  'ab31a000-0002-4001-8001-0000000000b2', current_date);
select public.compute_user_baselines(
  'ab31a000-0003-4001-8001-0000000000b3', current_date);
select public.compute_user_baselines(
  'ab31a000-0004-4001-8001-0000000000b4', current_date);

-- 1. Identical-value history floors the spread (never 0): a 0 spread
--    would make z infinite/unusable — the floor keeps it scoreable.
select is(
  (select spread from public.user_baselines
   where user_id = 'ab31a000-0002-4001-8001-0000000000b2'
     and metric_name = 'sleep_minutes'),
  15.0,
  '1: identical nights floor sleep spread at 15 (never 0)');

-- 2. The floor helper is pinned per metric.
select is(
  public.baseline_floor_spread('hrv_sdnn_ms'),
  0.05,
  '2: hrv floor is the ln-domain 0.05');
select is(
  public.baseline_floor_spread('sleep_minutes'),
  15.0,
  '3: sleep floor is 15 minutes');
select is(
  public.baseline_floor_spread('resting_hr_bpm'),
  2.0,
  '4: rhr floor is 2 bpm');
select is(
  public.baseline_floor_spread('resp_rate_bpm'),
  0.5,
  '5: resp floor is 0.5 bpm');
select is(
  public.baseline_floor_spread('weight_kg'),
  0.5,
  '6: weight floor is 0.5 kg');

-- 7. A varied history tracks above the floor (the EWMA sees real noise).
select ok(
  (select spread from public.user_baselines
   where user_id = 'ab31a000-0003-4001-8001-0000000000b3'
     and metric_name = 'hrv_sdnn_ms') > 0.05,
  '7: varied hrv spread exceeds its ln floor');

-- 8. last_observation_date is the TRUE newest observation (current_date-1
--    here: nights at current_date-1..-6; the compute target is
--    current_date — a wrong implementation stamps current_date).
select is(
  (select last_observation_date from public.user_baselines
   where user_id = 'ab31a000-0001-4001-8001-0000000000b1'
     and metric_name = 'sleep_minutes'),
  current_date - 1,
  '8: last_observation_date stamps the true newest night, not target_date');

-- User 5: a single-night history (cold start) at current_date - 9 — the
-- brief must report the TRUE stale age, not today.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at,
  sleep_minutes)
values
  ('ab31a000-0005-4001-8001-0000000000b5', current_date - 9,
   'Asia/Kolkata', array['sleep'], '[]'::jsonb,
   repeat('0a',32), 'partial', now(), now(), 430);
select public.compute_user_baselines(
  'ab31a000-0005-4001-8001-0000000000b5', current_date);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'ab31a000-0005-4001-8001-0000000000b5';

-- 9. Brief schema 1.5 with additive staleness fields per metric.
select is(
  public.get_my_daily_brief(current_date)->>'schema_version',
  '1.5',
  '9: brief schema_version is 1.5');
select is(
  (public.get_my_daily_brief(current_date)->'computed'->'baselines'
    ->'sleep_minutes'->>'age_days')::integer,
  9,
  '10: cold-start sleep baseline reports age_days 9 (true night, not today)');
select is(
  (public.get_my_daily_brief(current_date)->'computed'->'baselines'
    ->'sleep_minutes'->>'last_obs_date')::date,
  current_date - 9,
  '11: brief carries last_obs_date of the only observation');
select is(
  (public.get_my_daily_brief(current_date)->'computed'->'baselines'
    ->'sleep_minutes'->>'spread')::numeric,
  15.0,
  '12: cold-start spread is the floor (no variance to track yet)');
select is(
  public.get_my_daily_brief(current_date)->'computed'->'baselines'
    ->'resting_hr_bpm'->>'age_days',
  null,
  '13: never-observed metric reports null age_days, not 0');

-- 14. ln-domain scale invariance survives the spread EWMA: x3-scaled
--     histories must yield the identical hrv z (the spread tracks in the
--     ln domain, so a constant scale factor cancels).
reset role;
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('ab31a000-0003-4001-8001-0000000000b3', current_date,
   'Asia/Kolkata', array['hrv_sdnn'], '[]'::jsonb,
   repeat('b1',32), 'partial', now(), now(), 41.0, 'sdnn', 'ms'),
  ('ab31a000-0004-4001-8001-0000000000b4', current_date,
   'Asia/Kolkata', array['hrv_sdnn'], '[]'::jsonb,
   repeat('b2',32), 'partial', now(), now(), 123.0, 'sdnn', 'ms');
select is(
  (public.compute_daily_metrics(
    'ab31a000-0003-4001-8001-0000000000b3', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z'),
  (public.compute_daily_metrics(
    'ab31a000-0004-4001-8001-0000000000b4', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z'),
  '14: x3-scaled histories still yield the identical ln-domain z');

select finish();
rollback;
