-- Pass 5 — reference parity (2026-09-08).
--
-- The Dart reference implementation (test/reference/recovery_reference.dart,
-- written from docs/ALGORITHMS.md, not from SQL) and the production SQL
-- (compute_user_baselines / compute_daily_metrics, migration
-- 20260907160000) must produce the same numbers on the same inputs. This
-- test seeds the shared oracle fixtures (test/reference/fixtures/*.json —
-- shipped into the container at /fixtures by scripts/test-db.sh) into the
-- database and asserts the SQL output matches the reference's pins.
--
-- Seeding pattern (the fixtures are client-side psql variables, so each
-- block does its own \set + seeding + assertions):
--   \set fixture_json `cat /fixtures/<name>.json`
--   select pg_temp.seed_fixture(:'fixture_json', '<user>');
--   select compute_daily_metrics assertions against the reference pins.
--
-- Rounding contract: the SQL emits z-scores rounded to 3 decimals, ACWR
-- and monotony to 2, sleep sub-scores to 1. The Dart side compares
-- unrounded values with epsilon 0.01; the pins here use the same epsilon
-- against the SQL-rounded output.

begin;
select plan(28);

-- The auth_user_create_account trigger auto-inserts the user_accounts
-- row on the auth.users insert — no explicit account insert needed (and
-- an explicit one would collide on id).
create function pg_temp.seed_user(v_user uuid) returns void language plpgsql as $$
begin
  insert into auth.users(id, role) values (v_user, 'authenticated');
end $$;

-- Sessions need the plan/version/workout FK chain.
create function pg_temp.seed_sessions(
  v_user uuid, v_fix jsonb
) returns void language plpgsql as $$
declare
  s jsonb;
  v_plan uuid := gen_random_uuid();
  version_id uuid := gen_random_uuid();
  workout_id uuid := gen_random_uuid();
begin
  if jsonb_array_length(v_fix->'sessions') = 0 then return; end if;

  insert into public.training_plans(id, user_id, title, source)
  values (v_plan, v_user, 'Parity plan', 'imported');
  insert into public.training_plan_versions(
    id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
    prescription, rationale, approved_at, effective_date)
  values (version_id, v_user, v_plan, 1, 'active', 8, 6, '{}',
    'Approved plan', now(), current_date - 30);
  insert into public.planned_workouts(
    id, user_id, plan_version_id, name, workout_order, preferred_weekday,
    objective, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (workout_id, v_user, version_id, 'Parity session', 1, 1, 'Load',
    60, 'Warm up', 'Cool down');

  for s in select value from jsonb_array_elements(v_fix->'sessions') loop
    insert into public.workout_sessions(
      user_id, plan_version_id, planned_workout_id, state, local_date, timezone,
      idempotency_key, session_effort, duration_seconds, logging_completeness,
      completed_at)
    values (v_user, version_id, workout_id, 'completed',
      (s->>'date')::date, 'Asia/Kolkata', gen_random_uuid(),
      (s->>'effort')::numeric, (s->>'duration_seconds')::int, 1.0, now());
  end loop;
end $$;

-- Health days. present_types is derived from the keys actually present
-- (array_remove of case-when nulls), which the parity assertions never
-- read — they read the computed columns.
create function pg_temp.seed_health(
  v_user uuid, v_fix jsonb
) returns void language plpgsql as $$
declare
  d jsonb;
  v_types text[];
begin
  for d in select value from jsonb_array_elements(v_fix->'health_days') loop
    v_types := array_remove(array[
      case when d ? 'hrv_ms' then 'hrv_sdnn' end,
      case when d ? 'resting_hr_bpm' then 'resting_heart_rate' end,
      case when d ? 'sleep_minutes' then 'sleep' end,
      case when d ? 'resp_rate_bpm' then 'resp_rate' end,
      case when d ? 'weight_kg' then 'weight' end
    ], null);

    insert into public.daily_health_summaries(
      user_id, local_date, timezone, present_types, source_refs,
      source_checksum, completeness, observed_through, last_synced_at,
      hrv_value_ms, hrv_metric, hrv_unit,
      resting_heart_rate_bpm, respiratory_rate_bpm,
      sleep_minutes, sleep_awake_minutes, sleep_deep_minutes, sleep_rem_minutes
    )
    values (
      v_user, (d->>'date')::date, 'Asia/Kolkata', v_types,
      '[]'::jsonb, md5(random()::text) || md5(random()::text),
      'partial', now(), now(),
      nullif(d->>'hrv_ms','')::numeric,
      case when d ? 'hrv_ms' then 'sdnn' end,
      case when d ? 'hrv_ms' then 'ms' end,
      nullif(d->>'resting_hr_bpm','')::numeric,
      nullif(d->>'resp_rate_bpm','')::numeric,
      nullif(d->>'sleep_minutes','')::int,
      nullif(d->>'sleep_awake_minutes','')::int,
      nullif(d->>'sleep_deep_minutes','')::int,
      nullif(d->>'sleep_rem_minutes','')::int
    );
  end loop;
end $$;

create function pg_temp.seed_weights(
  v_user uuid, v_fix jsonb
) returns void language plpgsql as $$
declare
  w jsonb;
begin
  for w in select value from jsonb_array_elements(v_fix->'weight_days') loop
    insert into public.body_measurements(user_id, measured_on, source, weight_kg)
    values (v_user, (w->>'date')::date, 'manual', (w->>'weight_kg')::numeric);
  end loop;
end $$;

-- Seed one fixture (user id per fixture; fixtures run in their own
-- transaction, so ids never collide across files).
create function pg_temp.seed_fixture(v_fix jsonb, v_user uuid)
returns void language plpgsql as $$
begin
  perform pg_temp.seed_user(v_user);
  perform pg_temp.seed_health(v_user, v_fix);
  perform pg_temp.seed_sessions(v_user, v_fix);
  perform pg_temp.seed_weights(v_user, v_fix);
end $$;

-- compute_daily_metrics is security definer; tests run as the local
-- postgres role via pg_prove (matching the recovery_honesty pattern of
-- set local role service_role for the few authenticated paths). These
-- direct function calls run as postgres, which the function allows.

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 1: owner_day_strain_only (the 2026-08-25 production day)
-- Reference pins: recovery 62, prev_strain_z -0.294, four health missing.
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/owner_day_strain_only.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0001-4001-8001-000000000001');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-0001-4001-8001-000000000001', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'recovery'),
  '62',
  '1: owner strain-only day — SQL recovery 62 matches the reference pin');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-0001-4001-8001-000000000001', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'prev_strain_z')::numeric,
  -0.294,
  '2: prev_strain_z -0.294 matches the reference (recovery_honesty anchor)');

select ok(
  public.compute_daily_metrics(
    '5a5a5a5a-0001-4001-8001-000000000001', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components'
    @> '["hrv_sdnn","resting_hr","sleep_minutes","resp_rate"]'::jsonb,
  '3: the four health components reported missing');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 2: zero_data
-- Reference pins: recovery null, all five missing, low confidence.
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/zero_data.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0002-4001-8002-000000000002');

select ok(
  (public.compute_daily_metrics(
    '5a5a5a5a-0002-4001-8002-000000000002', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'recovery') is null,
  '4: zero data — SQL recovery null, reference null');

select is(
  jsonb_array_length(public.compute_daily_metrics(
    '5a5a5a5a-0002-4001-8002-000000000002', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components'),
  5,
  '5: zero data — all five components missing');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 3: hrv_only_history
-- Reference pins: z > 0, recovery > 80, three health + strain missing.
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/hrv_only_history.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0003-4001-8003-000000000003');

select cmp_ok(
  (public.compute_daily_metrics(
    '5a5a5a5a-0003-4001-8003-000000000003', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z')::numeric,
  '>',
  0::numeric,
  '6: hrv_z positive — 62ms today vs ~44ms ln baseline');

select cmp_ok(
  (public.compute_daily_metrics(
    '5a5a5a5a-0003-4001-8003-000000000003', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'recovery')::numeric,
  '>=',
  80::numeric,
  '7: HRV-only day scores >= 80 — the dominant component sets the score');

select is(
  jsonb_array_length(public.compute_daily_metrics(
    '5a5a5a5a-0003-4001-8003-000000000003', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components'),
  4,
  '8: HRV usable — the other four components missing');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 4: hrv_cold_start_today_only
-- Reference pins: recovery null, hrv missing (cold baseline).
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/hrv_cold_start_today_only.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0004-4001-8004-000000000004');

select ok(
  (public.compute_daily_metrics(
    '5a5a5a5a-0004-4001-8004-000000000004', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'recovery') is null,
  '9: present value with cold baseline — recovery null (never at-baseline)');

select is(
  (select n_observations from public.user_baselines
   where user_id = '5a5a5a5a-0004-4001-8004-000000000004'
     and metric_name = 'hrv_sdnn_ms'),
  1,
  '10: cold baseline n_observations = 1 (below the 3-observation gate)');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 5: full_data_day
-- Reference pins: all four z-keys non-zero, high confidence, duration
-- from the 480 floor (6 sleep nights < 7).
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/full_data_day.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0005-4001-8005-000000000005');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-0005-4001-8005-000000000005', '2026-09-08'::date, 'Asia/Kolkata'
  )->>'data_confidence'),
  'high',
  '11: full data day — confidence high');

select ok(
  (public.compute_daily_metrics(
    '5a5a5a5a-0005-4001-8005-000000000005', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z') is not null,
  '12: full data day — hrv_z key present (old-client shape)');

select cmp_ok(
  abs((public.compute_daily_metrics(
    '5a5a5a5a-0005-4001-8005-000000000005', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score')::numeric - 86.5),
  '<',
  0.1::numeric,
  '13: 6 sleep nights — duration from the 480 floor (415/480 ≈ 86.5)');

select is(
  jsonb_array_length(public.compute_daily_metrics(
    '5a5a5a5a-0005-4001-8005-000000000005', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components'),
  1,
  '14: full health data + no training — only prev_strain missing');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 6: long_sleep_resp_day
-- Reference pins: duration from sleep EWMA (< 100), resp z non-zero.
-- ───────────────── 7 nights: personal baseline.
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/long_sleep_resp_day.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0006-4001-8006-000000000006');

select cmp_ok(
  (public.compute_daily_metrics(
    '5a5a5a5a-0006-4001-8006-000000000006', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score')::numeric,
  '<',
  100::numeric,
  '15: 7 nights — duration from the sleep EWMA (~522), under 100');

select cmp_ok(
  (public.compute_daily_metrics(
    '5a5a5a5a-0006-4001-8006-000000000006', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'resp_rate_z')::numeric,
  '<>',
  0::numeric,
  '16: resp z computed (all four health components live)');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 7: short_night_duration
-- Reference pins: duration ~57.5 (300/~522), quality < 70, debt non-null.
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/short_night_duration.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0007-4001-8007-000000000007');

select cmp_ok(
  abs((public.compute_daily_metrics(
    '5a5a5a5a-0007-4001-8007-000000000007', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score')::numeric - 57.4),
  '<',
  0.15::numeric,
  '17: short 300-min night — duration ~57.4 vs the ~522 baseline');

select cmp_ok(
  (public.compute_daily_metrics(
    '5a5a5a5a-0007-4001-8007-000000000007', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'sleep_quality')::numeric,
  '<',
  70::numeric,
  '18: short night — sleep quality below 70');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 8: sleep_subs_partial
-- Reference pins: efficiency+restorative missing, breakdown absent.
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/sleep_subs_partial.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0008-4001-8008-000000000008');

select ok(
  public.compute_daily_metrics(
    '5a5a5a5a-0008-4001-8008-000000000008', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown_missing'
    @> '["efficiency","restorative"]'::jsonb,
  '19: missing awake+stages reported in sleep_breakdown_missing');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-0008-4001-8008-000000000008', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'sleep_breakdown'),
  null,
  '20: incomplete sub-data — breakdown object absent for old clients');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 9: sleep_cold_floor_six_nights
-- Reference pin: duration 85.6 (411/480 — the population floor).
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/sleep_cold_floor_six_nights.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-0009-4001-8009-000000000009');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-0009-4001-8009-000000000009', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score')::numeric,
  85.6::numeric,
  '21: 6 nights — duration pinned to the 480 floor (411/480 = 85.6)');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 10: hrv_x3_scale_invariant
-- Reference pin: z identical to hrv_only_history (ln-domain invariance).
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/hrv_x3_scale_invariant.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-000a-4001-800a-00000000000a');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-000a-4001-800a-00000000000a', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z')::numeric,
  (public.compute_daily_metrics(
    '5a5a5a5a-0003-4001-8003-000000000003', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z')::numeric,
  '22: x3-scaled history — identical ln-domain z to the base history');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 11: out_of_band_today
-- Reference pins: hrv missing, hrv_z stays 0, recovery null.
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/out_of_band_today.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-000b-4001-800b-00000000000b');

select ok(
  public.compute_daily_metrics(
    '5a5a5a5a-000b-4001-800b-00000000000b', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'hrv_sdnn',
  '23: out-of-band today value (400ms) reported missing');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-000b-4001-800b-00000000000b', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'recovery'),
  null,
  '24: out-of-band today — no recovery fabricated');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 12: plausibility_rejections
-- Reference pin: fold n_observations = 6 (the 400ms history night rejected).
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/plausibility_rejections.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-000c-4001-800c-00000000000c');

-- The fold runs inside compute_daily_metrics — call it before reading
-- baselines (same pattern as the recovery_honesty out-of-band check).
select public.compute_daily_metrics(
  '5a5a5a5a-000c-4001-800c-00000000000c', '2026-09-08'::date, 'Asia/Kolkata');

select is(
  (select n_observations from public.user_baselines
   where user_id = '5a5a5a5a-000c-4001-800c-00000000000c'
     and metric_name = 'hrv_sdnn_ms'),
  6,
  '25: out-of-band history value rejected from the fold (6 of 7 counted)');

-- ─────────────────────────────────────────────────────────────────────────
-- Fixture 13: acwr_monotony_windows
-- Reference pins: ACWR 1.95, monotony 2.27 (user-D shape).
-- ─────────────────────────────────────────────────────────────────────────

\set fixture_json `cat /fixtures/acwr_monotony_windows.json`
select pg_temp.seed_fixture(:'fixture_json'::jsonb,
  '5a5a5a5a-000d-4001-800d-00000000000d');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-000d-4001-800d-00000000000d', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'acwr'),
  '1.95',
  '26: ACWR pinned 1.95 — zero-filled avg7 30.86 / avg28 15.86');

select is(
  (public.compute_daily_metrics(
    '5a5a5a5a-000d-4001-800d-00000000000d', '2026-09-08'::date, 'Asia/Kolkata'
  )->'scores'->>'training_monotony'),
  '2.27',
  '27: monotony pinned 2.27 — zero-filled acute week has variance');

-- ─────────────────────────────────────────────────────────────────────────
-- Cross-fixture invariant: recovery in range wherever non-null
-- ─────────────────────────────────────────────────────────────────────────

select ok(
  (select recovery_score between 0 and 100
   from public.daily_computed_metrics
   where user_id = '5a5a5a5a-0005-4001-8005-000000000005'
     and local_date = '2026-09-08'::date),
  '28: full-data persisted recovery within 0..100');

select * from finish();
rollback;
