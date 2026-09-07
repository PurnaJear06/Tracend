-- Pass 2 — math honesty (migration 20260907120000).
--
-- Required behavior under test, by review item:
--   2a. HRV folds and z-scores in ln(ms): the stored baseline is
--       exp()able back into the observed range, the spread is on the ln
--       scale, and two users whose HRV histories differ only by a
--       constant factor x3 get the SAME z-score — the scale-invariance
--       the raw-ms z never had.
--   2b. ACWR null until >= 14 strain days in the 28-day calendar window
--       (zero-filled rest days); monotony needs only >= 4 acute strain
--       days and stddev > 0. Identical daily loads (the production
--       monotony-5.57 symptom) yield monotony null; ACWR on a full
--       16-day window is the pinned 1.75 for all-load-5 vs rest days.
--   2c. Sleep sub-scores: a missing sub-input (awake minutes, deep/rem
--       stages) drops that sub-score, the composite renormalizes, the
--       breakdown object is absent (shipped clients require every key),
--       and sleep_breakdown_missing names what dropped.
--   2d. Below 7 nights of sleep history the duration score uses the
--       480-minute population floor; at >= 7 nights it uses the personal
--       EWMA (tonight 411 vs baseline ~448 scores ~92, not the ~86 the
--       floor would give).
--   2e. Plausibility bands: out-of-band observations are rejected from
--       the fold (n_observations counts only in-band values) and an
--       out-of-band value TODAY is reported missing, never z-scored.

begin;
select plan(26);

insert into auth.users(id, role) values
  ('a11ce000-0001-4001-8001-000000000001', 'authenticated'),
  ('a11ce000-0002-4001-8001-000000000002', 'authenticated'),
  ('a11ce000-0003-4001-8001-000000000003', 'authenticated'),
  ('a11ce000-0004-4001-8001-000000000004', 'authenticated'),
  ('a11ce000-0005-4001-8001-000000000005', 'authenticated'),
  ('a11ce000-0006-4001-8001-000000000006', 'authenticated'),
  ('a11ce000-0007-4001-8001-000000000007', 'authenticated'),
  ('a11ce000-0008-4001-8001-000000000008', 'authenticated'),
  ('a11ce000-0009-4001-8001-000000000009', 'authenticated'),
  ('a11ce000-000a-4001-8001-00000000000a', 'authenticated'),
  ('a11ce000-000b-4001-8001-00000000000b', 'authenticated'),
  ('a11ce000-000c-4001-8001-00000000000c', 'authenticated'),
  ('a11ce000-000d-4001-8001-00000000000d', 'authenticated');

-- User A: HRV history 48-53 plus today 55 (all in the 5-250 band).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('a11ce000-0001-4001-8001-000000000001', current_date-6, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('01',32), 'partial', now(), now(),
   50.0, 'sdnn', 'ms'),
  ('a11ce000-0001-4001-8001-000000000001', current_date-5, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('02',32), 'partial', now(), now(),
   52.0, 'sdnn', 'ms'),
  ('a11ce000-0001-4001-8001-000000000001', current_date-4, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('03',32), 'partial', now(), now(),
   48.0, 'sdnn', 'ms'),
  ('a11ce000-0001-4001-8001-000000000001', current_date-3, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('04',32), 'partial', now(), now(),
   50.0, 'sdnn', 'ms'),
  ('a11ce000-0001-4001-8001-000000000001', current_date-2, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('05',32), 'partial', now(), now(),
   53.0, 'sdnn', 'ms'),
  ('a11ce000-0001-4001-8001-000000000001', current_date-1, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('06',32), 'partial', now(), now(),
   49.0, 'sdnn', 'ms'),
  ('a11ce000-0001-4001-8001-000000000001', current_date, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('07',32), 'partial', now(), now(),
   55.0, 'sdnn', 'ms');

-- User B: exactly user A's history x3 (in-band for both). ln-domain z
-- must equal user A's; the raw-ms z would differ by the scale factor.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('a11ce000-0002-4001-8001-000000000002', current_date-6, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('08',32), 'partial', now(), now(),
   150.0, 'sdnn', 'ms'),
  ('a11ce000-0002-4001-8001-000000000002', current_date-5, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('09',32), 'partial', now(), now(),
   156.0, 'sdnn', 'ms'),
  ('a11ce000-0002-4001-8001-000000000002', current_date-4, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('0a',32), 'partial', now(), now(),
   144.0, 'sdnn', 'ms'),
  ('a11ce000-0002-4001-8001-000000000002', current_date-3, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('0b',32), 'partial', now(), now(),
   150.0, 'sdnn', 'ms'),
  ('a11ce000-0002-4001-8001-000000000002', current_date-2, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('0c',32), 'partial', now(), now(),
   159.0, 'sdnn', 'ms'),
  ('a11ce000-0002-4001-8001-000000000002', current_date-1, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('0d',32), 'partial', now(), now(),
   147.0, 'sdnn', 'ms'),
  ('a11ce000-0002-4001-8001-000000000002', current_date, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('0e',32), 'partial', now(), now(),
   165.0, 'sdnn', 'ms');

-- Strain helpers: one plan + one planned workout per user, then sessions
-- on distinct dates. strain = effort * minutes / 10.
create function pg_temp.seed_plan(v_user uuid) returns void language plpgsql as $$
declare
  v_plan uuid := gen_random_uuid();
  v_version uuid := gen_random_uuid();
  v_workout uuid := gen_random_uuid();
begin
  insert into public.training_plans(id, user_id, title, source)
  values (v_plan, v_user, 'Math honesty plan', 'imported');
  insert into public.training_plan_versions(
    id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
    prescription, rationale, approved_at, effective_date)
  values (v_version, v_user, v_plan, 1, 'active', 8, 6, '{}',
    'Approved plan', now(), current_date - 30);
  insert into public.planned_workouts(
    id, user_id, plan_version_id, name, workout_order, preferred_weekday,
    objective, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (v_workout, v_user, v_version, 'Session', 1, 1, 'Load',
    60, 'Warm up', 'Cool down');
end $$;

create function pg_temp.add_session(
  v_user uuid, v_date date, v_effort numeric, v_minutes int
) returns void language plpgsql as $$
begin
  insert into public.workout_sessions(
    user_id, plan_version_id, planned_workout_id, state, local_date, timezone,
    idempotency_key, session_effort, duration_seconds, logging_completeness,
    completed_at)
  select v_user, pw.plan_version_id, pw.id, 'completed', v_date, 'Asia/Kolkata',
    gen_random_uuid(), v_effort, v_minutes * 60, 1.0, now()
  from public.planned_workouts pw
  where pw.user_id = v_user limit 1;
end $$;

-- 2b users. C: 6 strain days (thin chronic window) + a rest day today.
-- D: 15 strain days, varied load (8 at strain 24, then 7 at strain 36).
-- E: identical load on every acute day -6..current_date — the only way
-- the zero-filled acute week has zero variance.
select pg_temp.seed_plan('a11ce000-0003-4001-8001-000000000003');
select pg_temp.add_session('a11ce000-0003-4001-8001-000000000003', current_date-6, 4, 60);
select pg_temp.add_session('a11ce000-0003-4001-8001-000000000003', current_date-5, 4, 60);
select pg_temp.add_session('a11ce000-0003-4001-8001-000000000003', current_date-4, 4, 60);
select pg_temp.add_session('a11ce000-0003-4001-8001-000000000003', current_date-3, 4, 60);
select pg_temp.add_session('a11ce000-0003-4001-8001-000000000003', current_date-2, 4, 60);
select pg_temp.add_session('a11ce000-0003-4001-8001-000000000003', current_date-1, 4, 60);

select pg_temp.seed_plan('a11ce000-0004-4001-8001-000000000004');
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-15, 4, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-14, 4, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-13, 4, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-12, 4, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-11, 4, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-10, 4, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-9, 4, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-8, 4, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-7, 6, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-6, 6, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-5, 6, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-4, 6, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-3, 6, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-2, 6, 60);
select pg_temp.add_session('a11ce000-0004-4001-8001-000000000004', current_date-1, 6, 60);

select pg_temp.seed_plan('a11ce000-0005-4001-8001-000000000005');
select pg_temp.add_session('a11ce000-0005-4001-8001-000000000005', current_date-6, 5, 60);
select pg_temp.add_session('a11ce000-0005-4001-8001-000000000005', current_date-5, 5, 60);
select pg_temp.add_session('a11ce000-0005-4001-8001-000000000005', current_date-4, 5, 60);
select pg_temp.add_session('a11ce000-0005-4001-8001-000000000005', current_date-3, 5, 60);
select pg_temp.add_session('a11ce000-0005-4001-8001-000000000005', current_date-2, 5, 60);
select pg_temp.add_session('a11ce000-0005-4001-8001-000000000005', current_date-1, 5, 60);
select pg_temp.add_session('a11ce000-0005-4001-8001-000000000005', current_date, 5, 60);

-- 2c/2d users. G: full sub-data 7 nights (all sub-scores present).
-- H: sleep present, awake/deep/rem absent every night. I: 6 nights only
-- (personal-baseline floor test needs >= 7 nights, so 6 exercises the
-- population floor).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  sleep_minutes, sleep_awake_minutes, sleep_deep_minutes, sleep_rem_minutes)
values
  ('a11ce000-0007-4001-8001-000000000007', current_date-6, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('21',32), 'partial', now(), now(),
   450, 30, 90, 100),
  ('a11ce000-0007-4001-8001-000000000007', current_date-5, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('22',32), 'partial', now(), now(),
   460, 25, 95, 105),
  ('a11ce000-0007-4001-8001-000000000007', current_date-4, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('23',32), 'partial', now(), now(),
   440, 35, 85, 95),
  ('a11ce000-0007-4001-8001-000000000007', current_date-3, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('24',32), 'partial', now(), now(),
   455, 28, 92, 102),
  ('a11ce000-0007-4001-8001-000000000007', current_date-2, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('25',32), 'partial', now(), now(),
   465, 22, 97, 107),
  ('a11ce000-0007-4001-8001-000000000007', current_date-1, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('26',32), 'partial', now(), now(),
   445, 32, 88, 98),
  ('a11ce000-0007-4001-8001-000000000007', current_date, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('27',32), 'partial', now(), now(),
   411, 20, 80, 90);

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at, sleep_minutes)
values
  ('a11ce000-0008-4001-8001-000000000008', current_date-6, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('28',32), 'partial', now(), now(), 450),
  ('a11ce000-0008-4001-8001-000000000008', current_date-5, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('29',32), 'partial', now(), now(), 460),
  ('a11ce000-0008-4001-8001-000000000008', current_date-4, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('2a',32), 'partial', now(), now(), 440),
  ('a11ce000-0008-4001-8001-000000000008', current_date-3, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('2b',32), 'partial', now(), now(), 455),
  ('a11ce000-0008-4001-8001-000000000008', current_date-2, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('2c',32), 'partial', now(), now(), 465),
  ('a11ce000-0008-4001-8001-000000000008', current_date-1, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('2d',32), 'partial', now(), now(), 445),
  ('a11ce000-0008-4001-8001-000000000008', current_date, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('2e',32), 'partial', now(), now(), 411);

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  sleep_minutes, sleep_awake_minutes, sleep_deep_minutes, sleep_rem_minutes)
values
  ('a11ce000-0009-4001-8001-000000000009', current_date-5, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('2f',32), 'partial', now(), now(),
   450, 30, 90, 100),
  ('a11ce000-0009-4001-8001-000000000009', current_date-4, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('30',32), 'partial', now(), now(),
   460, 25, 95, 105),
  ('a11ce000-0009-4001-8001-000000000009', current_date-3, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('31',32), 'partial', now(), now(),
   440, 35, 85, 95),
  ('a11ce000-0009-4001-8001-000000000009', current_date-2, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('32',32), 'partial', now(), now(),
   455, 28, 92, 102),
  ('a11ce000-0009-4001-8001-000000000009', current_date-1, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('33',32), 'partial', now(), now(),
   465, 22, 97, 107),
  ('a11ce000-0009-4001-8001-000000000009', current_date, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('34',32), 'partial', now(), now(),
   411, 20, 80, 90);

-- 2e users. J: HRV 400ms today (out of band, above 250) with a valid
-- in-band history -> rejected at compute, reported missing. K: RHR 200
-- today (band 30-120) -> same. L: six in-band history nights plus one
-- 400ms night in history -> fold counts 6, not 7. M: weight 340 kg in
-- body_measurements history (band 30-300) -> fold ignores it.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('a11ce000-000a-4001-8001-00000000000a', current_date-6, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('35',32), 'partial', now(), now(),
   50.0, 'sdnn', 'ms'),
  ('a11ce000-000a-4001-8001-00000000000a', current_date-5, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('36',32), 'partial', now(), now(),
   52.0, 'sdnn', 'ms'),
  ('a11ce000-000a-4001-8001-00000000000a', current_date-4, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('37',32), 'partial', now(), now(),
   48.0, 'sdnn', 'ms'),
  ('a11ce000-000a-4001-8001-00000000000a', current_date-3, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('38',32), 'partial', now(), now(),
   50.0, 'sdnn', 'ms'),
  ('a11ce000-000a-4001-8001-00000000000a', current_date-2, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('39',32), 'partial', now(), now(),
   53.0, 'sdnn', 'ms'),
  ('a11ce000-000a-4001-8001-00000000000a', current_date-1, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('3a',32), 'partial', now(), now(),
   49.0, 'sdnn', 'ms'),
  ('a11ce000-000a-4001-8001-00000000000a', current_date, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('3b',32), 'partial', now(), now(),
   400.0, 'sdnn', 'ms');

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  resting_heart_rate_bpm)
values
  ('a11ce000-000b-4001-8001-00000000000b', current_date-6, 'Asia/Kolkata',
   array['resting_heart_rate'], '[]'::jsonb, repeat('3c',32),
   'partial', now(), now(), 55.0),
  ('a11ce000-000b-4001-8001-00000000000b', current_date-5, 'Asia/Kolkata',
   array['resting_heart_rate'], '[]'::jsonb, repeat('3d',32),
   'partial', now(), now(), 56.0),
  ('a11ce000-000b-4001-8001-00000000000b', current_date-4, 'Asia/Kolkata',
   array['resting_heart_rate'], '[]'::jsonb, repeat('3e',32),
   'partial', now(), now(), 54.0),
  ('a11ce000-000b-4001-8001-00000000000b', current_date-3, 'Asia/Kolkata',
   array['resting_heart_rate'], '[]'::jsonb, repeat('3f',32),
   'partial', now(), now(), 57.0),
  ('a11ce000-000b-4001-8001-00000000000b', current_date-2, 'Asia/Kolkata',
   array['resting_heart_rate'], '[]'::jsonb, repeat('40',32),
   'partial', now(), now(), 55.0),
  ('a11ce000-000b-4001-8001-00000000000b', current_date-1, 'Asia/Kolkata',
   array['resting_heart_rate'], '[]'::jsonb, repeat('41',32),
   'partial', now(), now(), 56.0),
  ('a11ce000-000b-4001-8001-00000000000b', current_date, 'Asia/Kolkata',
   array['resting_heart_rate'], '[]'::jsonb, repeat('42',32),
   'partial', now(), now(), 200.0);

insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('a11ce000-000c-4001-8001-00000000000c', current_date-6, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('43',32), 'partial', now(), now(),
   50.0, 'sdnn', 'ms'),
  ('a11ce000-000c-4001-8001-00000000000c', current_date-5, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('44',32), 'partial', now(), now(),
   52.0, 'sdnn', 'ms'),
  ('a11ce000-000c-4001-8001-00000000000c', current_date-4, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('45',32), 'partial', now(), now(),
   48.0, 'sdnn', 'ms'),
  ('a11ce000-000c-4001-8001-00000000000c', current_date-3, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('46',32), 'partial', now(), now(),
   50.0, 'sdnn', 'ms'),
  ('a11ce000-000c-4001-8001-00000000000c', current_date-2, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('47',32), 'partial', now(), now(),
   400.0, 'sdnn', 'ms'),
  ('a11ce000-000c-4001-8001-00000000000c', current_date-1, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('48',32), 'partial', now(), now(),
   53.0, 'sdnn', 'ms'),
  ('a11ce000-000c-4001-8001-00000000000c', current_date, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('49',32), 'partial', now(), now(),
   49.0, 'sdnn', 'ms');

insert into public.body_measurements(
  user_id, measured_on, source, weight_kg)
values
  ('a11ce000-000d-4001-8001-00000000000d', current_date-6, 'manual', 80.0),
  ('a11ce000-000d-4001-8001-00000000000d', current_date-5, 'manual', 80.5),
  ('a11ce000-000d-4001-8001-00000000000d', current_date-4, 'manual', 340.0),
  ('a11ce000-000d-4001-8001-00000000000d', current_date-3, 'manual', 80.2);

set local role service_role;

-- ============================================================================
-- 2a. ln-domain HRV
-- ============================================================================

-- Fold user A once so the baseline assertions read a folded state.
select public.compute_daily_metrics(
  'a11ce000-0001-4001-8001-000000000001', current_date, 'Asia/Kolkata');

select ok(
  (select exp(baseline_value) from public.user_baselines
   where user_id = 'a11ce000-0001-4001-8001-000000000001'
     and metric_name = 'hrv_sdnn_ms') between 45.0 and 60.0,
  '1: hrv ln baseline exp()s back into the observed range');

select cmp_ok(
  (select spread from public.user_baselines
   where user_id = 'a11ce000-0001-4001-8001-000000000001'
     and metric_name = 'hrv_sdnn_ms'),
  '<', 1.0,
  '2: hrv spread is on the ln scale (< 1), not the ms scale');

select is(
  (public.compute_daily_metrics(
    'a11ce000-0001-4001-8001-000000000001', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z'),
  (public.compute_daily_metrics(
    'a11ce000-0002-4001-8001-000000000002', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z'),
  '3: hrv x3-scaled history yields the identical ln-domain z');

select cmp_ok(
  (public.compute_daily_metrics(
    'a11ce000-0001-4001-8001-000000000001', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z')::numeric,
  '>', 0::numeric,
  '4: 55ms against a ~50ms baseline is a positive z');

-- ============================================================================
-- 2b. ACWR/monotony gates
-- ============================================================================

select is(
  public.compute_daily_metrics(
    'a11ce000-0003-4001-8001-000000000003', current_date, 'Asia/Kolkata'
  )->'scores'->>'acwr',
  null,
  '5: 6 strain days (< 14 chronic) -> ACWR null, not 1.0');

select is(
  public.compute_daily_metrics(
    'a11ce000-0005-4001-8001-000000000005', current_date, 'Asia/Kolkata'
  )->'scores'->>'training_monotony',
  null,
  '6: identical acute loads (stddev 0) -> monotony null');

select is(
  public.compute_daily_metrics(
    'a11ce000-0003-4001-8001-000000000003', current_date, 'Asia/Kolkata'
  )->'scores'->>'training_monotony',
  '2.27',
  '7: 6 identical sessions + today rest -> zero-filled week has variance -> monotony 2.27');

-- User F (15 strain days: 8 at strain 24, 7 at strain 36). The zero-filled
-- calendar acute week (-6..0) holds six 36s and today's rest 0: avg7 =
-- 216/7 = 30.857; the chronic window holds 8x24 + 7x36 + 15 rest days:
-- avg28 = 444/28 = 15.857 -> ACWR = 1.95.
select cmp_ok(
  (public.compute_daily_metrics(
    'a11ce000-0004-4001-8001-000000000004', current_date, 'Asia/Kolkata'
  )->'scores'->>'acwr')::numeric,
  '>', 1.0,
  '8: 15 varied strain days -> ACWR computed above 1');

select cmp_ok(
  (public.compute_daily_metrics(
    'a11ce000-0004-4001-8001-000000000004', current_date, 'Asia/Kolkata'
  )->'scores'->>'training_monotony')::numeric,
  '>', 0::numeric,
  '9: varied strain week -> monotony computed');

select is(
  public.compute_daily_metrics(
    'a11ce000-0004-4001-8001-000000000004', current_date, 'Asia/Kolkata'
  )->'scores'->>'acwr',
  '1.95',
  '10: ACWR value pinned: zero-filled avg7=30.86 / avg28=15.86 -> 1.95');

-- ============================================================================
-- 2c. Sleep sub-score honesty (user H: awake/deep/rem absent)
-- ============================================================================

select ok(
  public.compute_daily_metrics(
    'a11ce000-0008-4001-8001-000000000008', current_date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown_missing'
    @> '["efficiency","restorative"]'::jsonb,
  '11: missing awake+stages reported in sleep_breakdown_missing');

select is(
  public.compute_daily_metrics(
    'a11ce000-0008-4001-8001-000000000008', current_date, 'Asia/Kolkata'
  )->'scores'->>'sleep_breakdown',
  null,
  '12: incomplete sub-data -> sleep_breakdown object absent for old clients');

select ok(
  (public.compute_daily_metrics(
    'a11ce000-0008-4001-8001-000000000008', current_date, 'Asia/Kolkata'
  )->'scores'->>'sleep_quality')::numeric between 0 and 100,
  '13: renormalized duration+consistency composite still scores 0-100');

select ok(
  (public.compute_daily_metrics(
    'a11ce000-0007-4001-8001-000000000007', current_date, 'Asia/Kolkata'
  )->'scores'->>'sleep_quality')::numeric between 0 and 100,
  '14: full sub-data composite scores 0-100');

select is(
  public.compute_daily_metrics(
    'a11ce000-0007-4001-8001-000000000007', current_date, 'Asia/Kolkata'
  )->'scores'->>'sleep_breakdown_missing',
  '[]',
  '15: full sub-data -> nothing missing');

-- ============================================================================
-- 2d. Cold-start floor (user I: 6 nights vs user G: 7 nights)
-- ============================================================================

select is(
  (public.compute_daily_metrics(
    'a11ce000-0009-4001-8001-000000000009', current_date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score'),
  '85.6',
  '16: 6 nights of history -> duration vs 480 population floor (411/480)');

select ok(
  (public.compute_daily_metrics(
    'a11ce000-0007-4001-8001-000000000007', current_date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score')::numeric between 85.0 and 95.0,
  '17: 7 nights -> duration vs personal EWMA (~449), not the floor');

-- ============================================================================
-- 2e. Plausibility bands
-- ============================================================================

select ok(
  public.compute_daily_metrics(
    'a11ce000-000a-4001-8001-00000000000a', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'hrv_sdnn',
  '18: out-of-band hrv today (400ms) reported missing');

select is(
  public.compute_daily_metrics(
    'a11ce000-000a-4001-8001-00000000000a', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z',
  '0.000',
  '19: out-of-band hrv today never z-scored (key stays 0 for old clients)');

select ok(
  public.compute_daily_metrics(
    'a11ce000-000b-4001-8001-00000000000b', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'resting_hr',
  '20: out-of-band rhr today (200bpm) reported missing');

select public.compute_daily_metrics(
  'a11ce000-000c-4001-8001-00000000000c', current_date, 'Asia/Kolkata');
select public.compute_daily_metrics(
  'a11ce000-000d-4001-8001-00000000000d', current_date, 'Asia/Kolkata');

select is(
  (select n_observations from public.user_baselines
   where user_id = 'a11ce000-000c-4001-8001-00000000000c'
     and metric_name = 'hrv_sdnn_ms'),
  6,
  '21: out-of-band history value (400ms) rejected from the fold (6 of 7 counted)');

select is(
  (select n_observations from public.user_baselines
   where user_id = 'a11ce000-000d-4001-8001-00000000000d'
     and metric_name = 'weight_kg'),
  3,
  '22: out-of-band weight (340kg) rejected from the fold (3 of 4 counted)');

-- ============================================================================
-- Version + no-regression
-- ============================================================================

select is(
  (select schema_version from public.daily_computed_metrics
   where user_id = 'a11ce000-0001-4001-8001-000000000001'
     and local_date = current_date),
  '2.2',
  '23: persisted schema_version is 2.2');

select is(
  (select distinct engine_version from public.metric_baseline_history
   where user_id = 'a11ce000-0001-4001-8001-000000000001'
     and metric_name = 'hrv_sdnn_ms'),
  'baseline-v2',
  '24: baseline history rows record engine baseline-v2');

select ok(
  (select min(raw_value) from public.metric_baseline_history
   where user_id = 'a11ce000-0001-4001-8001-000000000001'
     and metric_name = 'hrv_sdnn_ms') between 45 and 60,
  '25: history raw_value keeps the raw ms observation, not ln');

select ok(
  (public.compute_daily_metrics(
    'a11ce000-0001-4001-8001-000000000001', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery')::integer between 80 and 100,
  '26: full-data regression: 55ms vs ~50ms ln baseline scores high (z ~ 2.1)');

select * from finish();
rollback;

