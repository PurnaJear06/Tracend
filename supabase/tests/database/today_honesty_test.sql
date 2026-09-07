-- Pass 2.5 — Today-screen honesty (migration 20260907140000).
--
-- Required behavior under test:
--   1. get_my_daily_brief reports schema_version 1.4.
--   2. computed.today_raw carries today's measured values verbatim from
--      daily_health_summaries (HRV, RHR, sleep minutes, resp rate) plus
--      the computed daily strain — a passthrough, never derived.
--   3. A day with no health row reports today_raw with every measured
--      key null — absent is absent, never zero.
--   4. The future-date guard payload also carries the today_raw key (all
--      null, including daily_strain) so brief-shape consumers never see
--      a missing key.
--
-- The brief is security definer and calls compute_daily_metrics itself,
-- so tests 1-7 drive it as authenticated with a jwt claim — the same path
-- production traffic takes. compute_daily_metrics is revoked from
-- authenticated, so the guard-payload test calls it directly as postgres
-- (the future_date_guard_test pattern). set local persists to the outer
-- transaction's end, so the role switches are sequenced deliberately.

begin;
select plan(9);

-- auth.users inserts auto-create the matching public.user_accounts row
-- via the auth_user_create_account trigger, so no explicit account insert
-- is needed (and would violate the unique constraint).
insert into auth.users(id, role) values
  ('a11ce000-0001-4001-8001-0000000000f1', 'authenticated'),
  ('a11ce000-0002-4001-8001-0000000000f2', 'authenticated'),
  ('a11ce000-0003-4001-8001-0000000000f3', 'authenticated');

-- Owner-shaped day: HRV + RHR + sleep present, resp absent (watch not
-- worn overnight), one completed session with effort.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, resting_heart_rate_bpm,
  sleep_minutes)
values
  ('a11ce000-0001-4001-8001-0000000000f1', current_date, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'], '[]'::jsonb,
   repeat('01',32), 'partial', now(), now(),
   38.0, 'sdnn', 'ms', 58.0, 430);

-- Prior nights so the baselines exist (HRV ln-domain fold needs values
-- with spread: 81/62/55 ms).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs,
  source_checksum, completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, resting_heart_rate_bpm,
  sleep_minutes)
values
  ('a11ce000-0001-4001-8001-0000000000f1', current_date-1, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'], '[]'::jsonb,
   repeat('02',32), 'partial', now(), now(),
   81.0, 'sdnn', 'ms', 57.0, 455),
  ('a11ce000-0001-4001-8001-0000000000f1', current_date-2, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'], '[]'::jsonb,
   repeat('03',32), 'partial', now(), now(),
   62.0, 'sdnn', 'ms', 56.0, 448),
  ('a11ce000-0001-4001-8001-0000000000f1', current_date-3, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'], '[]'::jsonb,
   repeat('04',32), 'partial', now(), now(),
   55.0, 'sdnn', 'ms', 55.0, 442);

-- A plan + today's completed session: 7 effort * 3600s / 600 = strain 42.
create function pg_temp.seed_today_session() returns void language plpgsql as $$
declare
  v_plan uuid := gen_random_uuid();
  v_version uuid := gen_random_uuid();
  v_workout uuid := gen_random_uuid();
  v_user uuid := 'a11ce000-0001-4001-8001-0000000000f1';
begin
  insert into public.training_plans(id, user_id, title, source)
  values (v_plan, v_user, 'Today honesty plan', 'imported');
  insert into public.training_plan_versions(
    id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v_version, v_user, v_plan, 1, 'active', 8, 6, '{}',
    'Approved plan', now(), current_date - 30);
  insert into public.planned_workouts(
    id, user_id, plan_version_id, name, workout_order, preferred_weekday,
    objective, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (v_workout, v_user, v_version, 'Session', 1, 1, 'Load',
    60, 'Warm up', 'Cool down');
  insert into public.workout_sessions(
    user_id, plan_version_id, planned_workout_id, state, local_date,
    timezone, idempotency_key, session_effort, duration_seconds,
    logging_completeness, completed_at)
  values (v_user, v_version, v_workout, 'completed', current_date,
    'Asia/Kolkata', gen_random_uuid(), 7, 3600, 1.0, now());
end $$;
select pg_temp.seed_today_session();

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a11ce000-0001-4001-8001-0000000000f1';

-- 1. Brief reports schema 1.4 (full payload, not the null-user early
--    return, which reports the same version).
select is(
  public.get_my_daily_brief(current_date)->>'schema_version',
  '1.4',
  'brief schema_version is 1.4'
);

-- 2. today_raw passes today's measured HRV through verbatim.
select is(
  (public.get_my_daily_brief(current_date)->'computed'->'today_raw'
    ->>'hrv_ms')::numeric,
  38.0,
  'today_raw.hrv_ms passes the measured 38.0 ms through'
);

-- 3. RHR passthrough.
select is(
  (public.get_my_daily_brief(current_date)->'computed'->'today_raw'
    ->>'resting_hr_bpm')::numeric,
  58.0,
  'today_raw.resting_hr_bpm passes the measured 58.0 bpm through'
);

-- 4. Sleep passthrough (integer minutes).
select is(
  (public.get_my_daily_brief(current_date)->'computed'->'today_raw'
    ->>'sleep_minutes')::integer,
  430,
  'today_raw.sleep_minutes passes the measured 430 min through'
);

-- 5. Resp absent today -> null, never zero.
select is(
  public.get_my_daily_brief(current_date)->'computed'->'today_raw'
    ->>'resp_rate_bpm',
  null,
  'today_raw.resp_rate_bpm is null when the watch was not worn (not 0)'
);

-- 6. daily_strain passthrough: 7 effort * 3600s / 600 = 42.
select is(
  (public.get_my_daily_brief(current_date)->'computed'->'today_raw'
    ->>'daily_strain')::numeric,
  42.0,
  'today_raw.daily_strain carries the computed strain (7*3600/600)'
);

-- 7. No health row at all -> every measured today_raw key null.
set local "request.jwt.claim.sub" =
  'a11ce000-0002-4001-8001-0000000000f2';
select is(
  public.get_my_daily_brief(current_date)->'computed'->'today_raw'
    ->>'hrv_ms',
  null,
  'a day with no health row carries null measured values (hrv representative)'
);

-- 8-9. Future-date guard payload keeps the today_raw key (all null,
-- including daily_strain — the main path coalesces strain to 0, so a null
-- here proves the guard payload is the one under test). compute is
-- revoked from authenticated, so this runs as postgres.
reset role;
select is(
  public.compute_daily_metrics(
    'a11ce000-0003-4001-8001-0000000000f3', current_date + 3,
    'Asia/Kolkata')->'today_raw'->>'hrv_ms',
  null,
  'future-date guard payload carries today_raw with null measured values'
);
select is(
  public.compute_daily_metrics(
    'a11ce000-0003-4001-8001-0000000000f3', current_date + 3,
    'Asia/Kolkata')->'today_raw'->>'daily_strain',
  null,
  'future-date guard payload nulls daily_strain (main path coalesces to 0)'
);

select finish();
rollback;
