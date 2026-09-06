-- Future-date guard (migration 20260906140000, review P0 #3):
-- compute_daily_metrics must never fold baselines through, or persist a
-- daily_computed_metrics row for, a date that cannot have begun anywhere on
-- Earth (target_date > current_date + 1; max civil offset is UTC+14, so
-- current_date + 1 is the latest possible local "today"). The brief for a
-- future day stays read-only: recovery null, z-keys zero for shipped
-- clients, every component reported missing, existing baselines returned
-- without being refreshed, data_confidence low. current_date + 1 itself
-- stays fully computable so users ahead of UTC keep their local today.

begin;
select plan(10);

insert into auth.users(id, role) values
  ('abababab-1212-4121-8121-121212121212', 'authenticated');

-- Six days of HRV history with variance plus a today row: enough for a
-- real baseline (spread > 0), so a leaked fold would be observable.
insert into public.daily_health_summaries(
  user_id, local_date, timezone, present_types, source_refs, source_checksum,
  completeness, observed_through, last_synced_at,
  hrv_value_ms, hrv_metric, hrv_unit)
values
  ('abababab-1212-4121-8121-121212121212', current_date-6, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('a0',32), 'partial', now(), now(),
   40.0, 'sdnn', 'ms'),
  ('abababab-1212-4121-8121-121212121212', current_date-5, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('a1',32), 'partial', now(), now(),
   42.0, 'sdnn', 'ms'),
  ('abababab-1212-4121-8121-121212121212', current_date-4, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('a2',32), 'partial', now(), now(),
   44.0, 'sdnn', 'ms'),
  ('abababab-1212-4121-8121-121212121212', current_date-3, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('a3',32), 'partial', now(), now(),
   46.0, 'sdnn', 'ms'),
  ('abababab-1212-4121-8121-121212121212', current_date-2, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('a4',32), 'partial', now(), now(),
   48.0, 'sdnn', 'ms'),
  ('abababab-1212-4121-8121-121212121212', current_date-1, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('a5',32), 'partial', now(), now(),
   44.0, 'sdnn', 'ms'),
  ('abababab-1212-4121-8121-121212121212', current_date, 'Asia/Kolkata',
   array['hrv_sdnn'], '[]'::jsonb, repeat('a6',32), 'partial', now(), now(),
   51.0, 'sdnn', 'ms');

-- 1. Guard does not over-trigger: today's compute still persists a row.
select public.compute_daily_metrics(
  'abababab-1212-4121-8121-121212121212', current_date, 'Asia/Kolkata');
select is(
  (select count(*)::int from public.daily_computed_metrics
   where user_id = 'abababab-1212-4121-8121-121212121212'
     and local_date = current_date),
  1,
  '1: today''s compute still upserts the row');

-- 2. A future compute (+3) persists nothing.
select public.compute_daily_metrics(
  'abababab-1212-4121-8121-121212121212', current_date + 3, 'Asia/Kolkata');
select is(
  (select count(*)::int from public.daily_computed_metrics
   where user_id = 'abababab-1212-4121-8121-121212121212'
     and local_date > current_date + 1),
  0,
  '2: future compute (+3) persists no row');

-- 3. The future brief reports recovery null (never a fabricated number).
select ok(
  (public.compute_daily_metrics(
    'abababab-1212-4121-8121-121212121212', current_date + 3, 'Asia/Kolkata'
  )->'scores'->>'recovery') is null,
  '3: future brief recovery is null');

-- 4. All five z-keys stay present and zero for shipped clients.
select is(
  public.compute_daily_metrics(
    'abababab-1212-4121-8121-121212121212', current_date + 3, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z',
  '0',
  '4: future brief keeps z-keys at 0');

-- 5. Every component is reported missing for the future day.
select ok(
  public.compute_daily_metrics(
    'abababab-1212-4121-8121-121212121212', current_date + 3, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->'missing_components' @>
    '["hrv_sdnn","resting_hr","sleep_minutes","resp_rate","prev_strain"]'::jsonb,
  '5: future brief lists all components missing');

-- 6. Existing baselines are still returned (read-only, not refreshed).
select ok(
  public.compute_daily_metrics(
    'abababab-1212-4121-8121-121212121212', current_date + 3, 'Asia/Kolkata'
  )->'baselines' ? 'hrv_sdnn_ms',
  '6: future brief returns stored baselines unrefreshed');

-- 7. A future day has no data, so confidence is honestly low.
select is(
  public.compute_daily_metrics(
    'abababab-1212-4121-8121-121212121212', current_date + 3, 'Asia/Kolkata'
  )->>'data_confidence',
  'low',
  '7: future brief data_confidence is low');

-- 8. The baseline fold never ran past current_date (a leaked fold would
--    have written last_observation_date = current_date + 3).
select is(
  (select max(last_observation_date) from public.user_baselines
   where user_id = 'abababab-1212-4121-8121-121212121212'),
  current_date,
  '8: baselines never folded past current_date');

-- 9. The future asks added no metric_baseline_history rows (the today ask
--    wrote exactly one history row per observed value: 7 values, 7 rows).
select is(
  (select count(*)::int from public.metric_baseline_history
   where user_id = 'abababab-1212-4121-8121-121212121212'),
  7,
  '9: future asks write no baseline history rows');

-- 10. Boundary: current_date + 1 is the latest possible local "today"
--     (UTC+14 users), so it must stay fully computable.
select public.compute_daily_metrics(
  'abababab-1212-4121-8121-121212121212', current_date + 1, 'Asia/Kolkata');
select is(
  (select count(*)::int from public.daily_computed_metrics
   where user_id = 'abababab-1212-4121-8121-121212121212'
     and local_date = current_date + 1),
  1,
  '10: current_date + 1 still computes and persists');

select * from finish();
rollback;
