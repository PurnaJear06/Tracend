-- Recovery honesty (Chunk 7): compute_daily_metrics must not fabricate.
--
-- Production evidence 2026-08-25: days with zero usable components scored
-- recovery 58 (sigmoid +0.2 optimism bias), days with missing sleep/resp
-- reported data_confidence 'high', and present values without a baseline
-- were counted as "at baseline" (z = 0) with full composite weight.
--
-- Required behavior under test:
--   1. Zero usable components            -> recovery NULL (never a number).
--   2. Present value, cold/zero baseline -> component excluded + reported
--      in recovery_breakdown.missing_components.
--   3. Missing today-values              -> reported in missing_components.
--   4. data_confidence counts missing health components
--      (0 -> high, 1-2 -> medium, 3-4 -> low); prev_strain is reported
--      missing but does not lower confidence on its own.
--   5. Full-data regression: z-keys stay non-null, recovery in 0..100.
--   6. duration_score uses the sleep baseline even when respiratory data is
--      present (previously the shared baseline record held the resp-rate
--      baseline, clipping duration to 100 on resp-present days).
--   7. Synthetic reproduction of the owner's 2026-08-25 day: strain is the
--      only usable component (z = -1.5/sqrt(26) ~ -0.294). The old formula
--      added a +0.2 optimism offset and reported 69; the honest formula maps
--      composite +0.294 to 62, lists the four health components missing, and
--      lowers confidence to 'low'.
--   8. prev_strain with an unusable spread (a single strain day -> stddev
--      NULL) is reported missing, never folded in at z = 0 with full weight.
--   9. duration_score reflects tonight's sleep duration against the personal
--      baseline (a short night scores low); the old 480/baseline form was
--      time-invariant and pinned at 100 for any baseline <= 480.

begin;
select plan(33);

insert into auth.users(id, role) values
  ('eeeeeeee-1111-4111-8111-111111111111', 'authenticated'), -- zero data
  ('ffffffff-2222-4222-8222-222222222222', 'authenticated'), -- hrv only
  ('99999999-3333-4333-8333-333333333333', 'authenticated'), -- cold baseline
  ('dddddddd-4444-4444-8444-444444444444', 'authenticated'), -- full data
  ('aaaaaaaa-5555-4555-8555-555555555555', 'authenticated'), -- long sleep + resp
  ('cccccccc-6666-4666-8666-666666666666', 'authenticated'), -- strain only
  ('bbbbbbbb-8888-4888-8888-888888888888', 'authenticated'), -- single strain day
  ('cccccccc-9999-4999-8999-999999999999', 'authenticated'); -- short night

-- User F: six days of HRV history (variance -> spread > 0), no other metrics.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('ffffffff-2222-4222-8222-222222222222', current_date-6, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('f0',32), 'partial', now(), now(),
   40.0, 'sdnn', 'ms'),
  ('ffffffff-2222-4222-8222-222222222222', current_date-5, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('f1',32), 'partial', now(), now(),
   42.0, 'sdnn', 'ms'),
  ('ffffffff-2222-4222-8222-222222222222', current_date-4, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('f2',32), 'partial', now(), now(),
   44.0, 'sdnn', 'ms'),
  ('ffffffff-2222-4222-8222-222222222222', current_date-3, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('f3',32), 'partial', now(), now(),
   46.0, 'sdnn', 'ms'),
  ('ffffffff-2222-4222-8222-222222222222', current_date-2, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('f4',32), 'partial', now(), now(),
   48.0, 'sdnn', 'ms'),
  ('ffffffff-2222-4222-8222-222222222222', current_date-1, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('f5',32), 'partial', now(), now(),
   44.0, 'sdnn', 'ms'),
  ('ffffffff-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('f6',32), 'partial', now(), now(),
   62.0, 'sdnn', 'ms');

-- User 9: HRV today but no history -> baseline cold (spread = 0).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('99999999-3333-4333-8333-333333333333', current_date, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('9a',32), 'partial', now(), now(),
   55.0, 'sdnn', 'ms');

-- User D: five days of full history plus a full today row.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit, resting_heart_rate_bpm, sleep_minutes,
  sleep_awake_minutes, sleep_deep_minutes, sleep_rem_minutes,
  sleep_light_minutes, respiratory_rate_bpm)
values
  ('dddddddd-4444-4444-8444-444444444444', current_date-5, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb, repeat('d0',32),
   'partial', now(), now(), 48.0, 'sdnn', 'ms', 56.0, 400, 30, 80, 90, 200, 14.0),
  ('dddddddd-4444-4444-8444-444444444444', current_date-4, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb, repeat('d1',32),
   'partial', now(), now(), 50.0, 'sdnn', 'ms', 54.0, 410, 25, 85, 95, 205, 14.5),
  ('dddddddd-4444-4444-8444-444444444444', current_date-3, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb, repeat('d2',32),
   'partial', now(), now(), 47.0, 'sdnn', 'ms', 57.0, 390, 35, 75, 85, 195, 15.0),
  ('dddddddd-4444-4444-8444-444444444444', current_date-2, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb, repeat('d3',32),
   'partial', now(), now(), 52.0, 'sdnn', 'ms', 55.0, 420, 20, 90, 100, 210, 14.0),
  ('dddddddd-4444-4444-8444-444444444444', current_date-1, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb, repeat('d4',32),
   'partial', now(), now(), 49.0, 'sdnn', 'ms', 56.0, 405, 28, 82, 92, 203, 14.5),
  ('dddddddd-4444-4444-8444-444444444444', current_date, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb, repeat('d5',32),
   'partial', now(), now(), 51.0, 'sdnn', 'ms', 55.0, 415, 25, 85, 95, 205, 14.0);

-- User G: sleep baseline above the 480-minute target AND respiratory data
-- present every day. duration_score must come from the sleep EWMA (~518 ->
-- ~97 tonight), not from the resp-rate baseline (~14 -> clipped 100).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  sleep_minutes, sleep_awake_minutes, sleep_deep_minutes, sleep_rem_minutes,
  sleep_light_minutes, respiratory_rate_bpm)
values
  ('aaaaaaaa-5555-4555-8555-555555555555', current_date-6, 'Asia/Kolkata',
   array['sleep','resp_rate'], '[]'::jsonb, repeat('a0',32),
   'partial', now(), now(), 520, 25, 95, 100, 300, 13.0),
  ('aaaaaaaa-5555-4555-8555-555555555555', current_date-5, 'Asia/Kolkata',
   array['sleep','resp_rate'], '[]'::jsonb, repeat('a1',32),
   'partial', now(), now(), 530, 20, 100, 105, 305, 14.0),
  ('aaaaaaaa-5555-4555-8555-555555555555', current_date-4, 'Asia/Kolkata',
   array['sleep','resp_rate'], '[]'::jsonb, repeat('a2',32),
   'partial', now(), now(), 515, 30, 90, 98, 297, 15.0),
  ('aaaaaaaa-5555-4555-8555-555555555555', current_date-3, 'Asia/Kolkata',
   array['sleep','resp_rate'], '[]'::jsonb, repeat('a3',32),
   'partial', now(), now(), 525, 22, 96, 102, 305, 13.5),
  ('aaaaaaaa-5555-4555-8555-555555555555', current_date-2, 'Asia/Kolkata',
   array['sleep','resp_rate'], '[]'::jsonb, repeat('a4',32),
   'partial', now(), now(), 510, 28, 92, 97, 293, 14.5),
  ('aaaaaaaa-5555-4555-8555-555555555555', current_date-1, 'Asia/Kolkata',
   array['sleep','resp_rate'], '[]'::jsonb, repeat('a5',32),
   'partial', now(), now(), 535, 18, 102, 106, 309, 14.0),
  ('aaaaaaaa-5555-4555-8555-555555555555', current_date, 'Asia/Kolkata',
   array['sleep','resp_rate'], '[]'::jsonb, repeat('a6',32),
   'partial', now(), now(), 500, 20, 90, 100, 290, 14.0);

-- User H: synthetic reproduction of the owner's 2026-08-25 day. No health
-- data at all; strain is the only usable component. Daily strain
-- (session_effort * duration_seconds / 600): six days at 10 inside the
-- 7-day window, plus older days at 24 and 8. That gives prev7 = 10,
-- avg28 = 11.5, stddev28 = sqrt(26), strain_z = -1.5/sqrt(26) ~ -0.294,
-- composite = +0.294 -> honest recovery 62. The old formula (composite +
-- 0.2 offset) reported 69 for exactly this shape.
insert into public.training_plans(id, user_id, title, source) values
  ('cccccccc-7777-4777-8777-777777777771',
   'cccccccc-6666-4666-8666-666666666666', 'Strain-only plan', 'imported');
insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
  prescription, rationale, approved_at, effective_date)
values
  ('cccccccc-7777-4777-8777-777777777772',
   'cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777771', 1, 'active', 8, 6, '{}',
   'Approved plan', now(), current_date - 30);
insert into public.planned_workouts(
  id, user_id, plan_version_id, name, workout_order, preferred_weekday,
  objective, estimated_minutes, warm_up_guidance, cool_down_guidance)
values
  ('cccccccc-7777-4777-8777-777777777773',
   'cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'Strain session', 1, 1, 'Load',
   60, 'Warm up', 'Cool down');
insert into public.workout_sessions(
  user_id, plan_version_id, planned_workout_id, state, local_date, timezone,
  idempotency_key, session_effort, duration_seconds, logging_completeness,
  completed_at)
values
  -- six recent days, strain 10 each (5.0 * 1200 / 600)
  ('cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'cccccccc-7777-4777-8777-777777777773',
   'completed', current_date-6, 'Asia/Kolkata', gen_random_uuid(),
   5.0, 1200, 1.0, now()),
  ('cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'cccccccc-7777-4777-8777-777777777773',
   'completed', current_date-5, 'Asia/Kolkata', gen_random_uuid(),
   5.0, 1200, 1.0, now()),
  ('cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'cccccccc-7777-4777-8777-777777777773',
   'completed', current_date-4, 'Asia/Kolkata', gen_random_uuid(),
   5.0, 1200, 1.0, now()),
  ('cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'cccccccc-7777-4777-8777-777777777773',
   'completed', current_date-3, 'Asia/Kolkata', gen_random_uuid(),
   5.0, 1200, 1.0, now()),
  ('cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'cccccccc-7777-4777-8777-777777777773',
   'completed', current_date-2, 'Asia/Kolkata', gen_random_uuid(),
   5.0, 1200, 1.0, now()),
  ('cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'cccccccc-7777-4777-8777-777777777773',
   'completed', current_date-1, 'Asia/Kolkata', gen_random_uuid(),
   5.0, 1200, 1.0, now()),
  -- older day, strain 24 (8.0 * 1800 / 600)
  ('cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'cccccccc-7777-4777-8777-777777777773',
   'completed', current_date-10, 'Asia/Kolkata', gen_random_uuid(),
   8.0, 1800, 1.0, now()),
  -- older day, strain 8 (8.0 * 600 / 600)
  ('cccccccc-6666-4666-8666-666666666666',
   'cccccccc-7777-4777-8777-777777777772', 'cccccccc-7777-4777-8777-777777777773',
   'completed', current_date-12, 'Asia/Kolkata', gen_random_uuid(),
   8.0, 600, 1.0, now());

-- User J: exactly one strain day in the window. prev_7d_strain_avg > 0 but
-- the 28-day stddev is NULL, so prev_strain must be reported missing and
-- recovery must stay null (no usable components at all).
insert into public.training_plans(id, user_id, title, source) values
  ('bbbbbbbb-7777-4777-8777-777777777771',
   'bbbbbbbb-8888-4888-8888-888888888888', 'Single-day plan', 'imported');
insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
  prescription, rationale, approved_at, effective_date)
values
  ('bbbbbbbb-7777-4777-8777-777777777772',
   'bbbbbbbb-8888-4888-8888-888888888888',
   'bbbbbbbb-7777-4777-8777-777777777771', 1, 'active', 8, 6, '{}',
   'Approved plan', now(), current_date - 30);
insert into public.planned_workouts(
  id, user_id, plan_version_id, name, workout_order, preferred_weekday,
  objective, estimated_minutes, warm_up_guidance, cool_down_guidance)
values
  ('bbbbbbbb-7777-4777-8777-777777777773',
   'bbbbbbbb-8888-4888-8888-888888888888',
   'bbbbbbbb-7777-4777-8777-777777777772', 'One-off session', 1, 1, 'Load',
   60, 'Warm up', 'Cool down');
insert into public.workout_sessions(
  user_id, plan_version_id, planned_workout_id, state, local_date, timezone,
  idempotency_key, session_effort, duration_seconds, logging_completeness,
  completed_at)
values
  ('bbbbbbbb-8888-4888-8888-888888888888',
   'bbbbbbbb-7777-4777-8777-777777777772', 'bbbbbbbb-7777-4777-8777-777777777773',
   'completed', current_date-1, 'Asia/Kolkata', gen_random_uuid(),
   5.0, 1200, 1.0, now());

-- User K: the same long-sleep baseline as user G (~522 min EWMA) but a short
-- 300-minute night tonight. duration_score must reflect tonight's duration
-- (~57), not the time-invariant 480/baseline (~92).
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  sleep_minutes, sleep_awake_minutes, sleep_deep_minutes, sleep_rem_minutes,
  sleep_light_minutes)
values
  ('cccccccc-9999-4999-8999-999999999999', current_date-6, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('b0',32),
   'partial', now(), now(), 520, 25, 95, 100, 300),
  ('cccccccc-9999-4999-8999-999999999999', current_date-5, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('b1',32),
   'partial', now(), now(), 530, 20, 100, 105, 305),
  ('cccccccc-9999-4999-8999-999999999999', current_date-4, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('b2',32),
   'partial', now(), now(), 515, 30, 90, 98, 297),
  ('cccccccc-9999-4999-8999-999999999999', current_date-3, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('b3',32),
   'partial', now(), now(), 525, 22, 96, 102, 305),
  ('cccccccc-9999-4999-8999-999999999999', current_date-2, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('b4',32),
   'partial', now(), now(), 510, 28, 92, 97, 293),
  ('cccccccc-9999-4999-8999-999999999999', current_date-1, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('b5',32),
   'partial', now(), now(), 535, 18, 102, 106, 309),
  ('cccccccc-9999-4999-8999-999999999999', current_date, 'Asia/Kolkata',
   array['sleep'], '[]'::jsonb, repeat('b6',32),
   'partial', now(), now(), 300, 20, 40, 30, 210);

set local role service_role;

-- ============================================================================
-- 1. Zero data -> no fabricated recovery
-- ============================================================================

select lives_ok(
  'select public.compute_daily_metrics('
  '''eeeeeeee-1111-4111-8111-111111111111'', current_date, ''UTC'')',
  '1: compute_daily_metrics runs for user with zero data'
);

select ok(
  (public.compute_daily_metrics(
    'eeeeeeee-1111-4111-8111-111111111111', current_date, 'UTC'
  )->'scores'->>'recovery') is null,
  '2: zero usable components -> recovery is null (no fabricated 58)'
);

select is(
  public.compute_daily_metrics(
    'eeeeeeee-1111-4111-8111-111111111111', current_date, 'UTC'
  )->>'data_confidence',
  'low',
  '3: zero data -> data_confidence low'
);

select is(
  jsonb_array_length(
    public.compute_daily_metrics(
      'eeeeeeee-1111-4111-8111-111111111111', current_date, 'UTC'
    )->'scores'->'recovery_breakdown'->'missing_components'),
  5,
  '4: zero data -> all five components reported missing'
);

select ok(
  (public.compute_daily_metrics(
    'eeeeeeee-1111-4111-8111-111111111111', current_date, 'UTC'
  )->'scores' ? 'recovery_breakdown'),
  '5: recovery_breakdown object still present for old clients'
);

select ok(
  (select recovery_score is null
   from public.daily_computed_metrics
   where user_id = 'eeeeeeee-1111-4111-8111-111111111111'
     and local_date = current_date),
  '6: persisted recovery_score is null for zero-data day'
);

-- ============================================================================
-- 2. HRV-only user: no dilution, honest missing list
-- ============================================================================

select cmp_ok(
  (public.compute_daily_metrics(
    'ffffffff-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery')::integer,
  '>=', 85,
  '7: hrv far above baseline -> high recovery, not diluted by missing parts'
);

select ok(
  public.compute_daily_metrics(
    'ffffffff-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'sleep_minutes',
  '8: missing sleep reported'
);

select ok(
  public.compute_daily_metrics(
    'ffffffff-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'resting_hr',
  '9: missing resting hr reported'
);

select ok(
  public.compute_daily_metrics(
    'ffffffff-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'resp_rate',
  '10: missing respiratory rate reported'
);

select ok(
  public.compute_daily_metrics(
    'ffffffff-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'prev_strain',
  '11: missing prior strain reported'
);

select ok(
  not (public.compute_daily_metrics(
    'ffffffff-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'hrv_sdnn'),
  '12: hrv with valid baseline not reported missing'
);

select is(
  public.compute_daily_metrics(
    'ffffffff-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata'
  )->>'data_confidence',
  'low',
  '13: three missing health components -> low confidence'
);

-- ============================================================================
-- 3. Present value without baseline -> excluded, not "at baseline"
-- ============================================================================

select ok(
  (public.compute_daily_metrics(
    '99999999-3333-4333-8333-333333333333', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery') is null,
  '14: present hrv with cold baseline -> no recovery fabricated'
);

select ok(
  public.compute_daily_metrics(
    '99999999-3333-4333-8333-333333333333', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'hrv_sdnn',
  '15: present value without usable baseline reported missing'
);

-- ============================================================================
-- 4. Full-data regression: shape preserved, confidence honest
-- ============================================================================

select cmp_ok(
  (public.compute_daily_metrics(
    'dddddddd-4444-4444-8444-444444444444', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery')::integer,
  '>=', 0,
  '16: full data -> recovery computed (lower bound)'
);

select cmp_ok(
  (public.compute_daily_metrics(
    'dddddddd-4444-4444-8444-444444444444', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery')::integer,
  '<=', 100,
  '17: full data -> recovery computed (upper bound)'
);

select ok(
  (public.compute_daily_metrics(
    'dddddddd-4444-4444-8444-444444444444', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z') is not null,
  '18: full data -> hrv_z key remains non-null for old clients'
);

select is(
  jsonb_array_length(
    public.compute_daily_metrics(
      'dddddddd-4444-4444-8444-444444444444', current_date, 'Asia/Kolkata'
    )->'scores'->'recovery_breakdown'->'missing_components'),
  1,
  '19: full health data, no logged training -> only prev_strain missing'
);

select is(
  public.compute_daily_metrics(
    'dddddddd-4444-4444-8444-444444444444', current_date, 'Asia/Kolkata'
  )->>'data_confidence',
  'high',
  '20: all four health components present -> high confidence'
);

select ok(
  (select recovery_score is not null
   from public.daily_computed_metrics
   where user_id = 'dddddddd-4444-4444-8444-444444444444'
     and local_date = current_date),
  '21: persisted recovery_score non-null for full-data day'
);

-- ============================================================================
-- 5. duration_score uses the sleep baseline on resp-present days
-- ============================================================================

select lives_ok(
  'select public.compute_daily_metrics('
  '''aaaaaaaa-5555-4555-8555-555555555555'', current_date, ''Asia/Kolkata'')',
  '22: compute_daily_metrics runs for long-sleep user with resp data'
);

select cmp_ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-5555-4555-8555-555555555555', current_date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score')::numeric,
  '<', 100::numeric,
  '23: resp present + sleep baseline > 480 -> duration_score from sleep EWMA, not clipped 100'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-5555-4555-8555-555555555555', current_date, 'Asia/Kolkata'
  )->'scores'->>'sleep_quality') is not null,
  '24: long-sleep user still gets a sleep_quality score'
);

-- ============================================================================
-- 6. Synthetic reproduction of the owner's strain-only day (69 -> 62)
-- ============================================================================

select lives_ok(
  'select public.compute_daily_metrics('
  '''cccccccc-6666-4666-8666-666666666666'', current_date, ''Asia/Kolkata'')',
  '25: compute_daily_metrics runs for the strain-only synthetic user'
);

select is(
  (public.compute_daily_metrics(
    'cccccccc-6666-4666-8666-666666666666', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery')::integer,
  62,
  '26: strain-only day scores 62 (composite +0.294, no offset), not the old 69'
);

select is(
  jsonb_array_length(
    public.compute_daily_metrics(
      'cccccccc-6666-4666-8666-666666666666', current_date, 'Asia/Kolkata'
    )->'scores'->'recovery_breakdown'->'missing_components'),
  4,
  '27: strain-only day reports exactly four missing components (prev_strain usable)'
);

select ok(
  public.compute_daily_metrics(
    'cccccccc-6666-4666-8666-666666666666', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components'
  @> '["hrv_sdnn","resting_hr","sleep_minutes","resp_rate"]'::jsonb,
  '28: all four health components reported missing by name'
);

select is(
  public.compute_daily_metrics(
    'cccccccc-6666-4666-8666-666666666666', current_date, 'Asia/Kolkata'
  )->>'data_confidence',
  'low',
  '29: four missing health components -> low confidence'
);

select cmp_ok(
  (public.compute_daily_metrics(
    'cccccccc-6666-4666-8666-666666666666', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'prev_strain_z')::numeric,
  '<', 0::numeric,
  '30: below-average recent strain yields a negative prev_strain_z'
);

-- ============================================================================
-- 7. prev_strain without a usable spread is missing, not z = 0
-- ============================================================================

select ok(
  (public.compute_daily_metrics(
    'bbbbbbbb-8888-4888-8888-888888888888', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery') is null,
  '31: single strain day (stddev NULL) -> no recovery fabricated'
);

select ok(
  public.compute_daily_metrics(
    'bbbbbbbb-8888-4888-8888-888888888888', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' ? 'prev_strain',
  '32: single strain day reported missing instead of joining at z = 0'
);

-- ============================================================================
-- 8. duration_score reflects tonight's sleep duration
-- ============================================================================

select cmp_ok(
  (public.compute_daily_metrics(
    'cccccccc-9999-4999-8999-999999999999', current_date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score')::numeric,
  '<', 70::numeric,
  '33: 300-min night against a ~522-min baseline scores low (old form gave ~92)'
);

select * from finish();
rollback;
