begin;
select plan(20);

insert into auth.users(id, role) values
  ('e3000000-0000-4000-8000-000000000001', 'authenticated'),
  ('e3000000-0000-4000-8000-000000000002', 'authenticated'),
  ('e3000000-0000-4000-8000-000000000003', 'authenticated'),
  ('e3000000-0000-4000-8000-000000000004', 'authenticated');

-- 1 has no record, 2 granted then withdrew, 3 holds a grant of an older notice version, 4 withdrew
-- and then granted again.
insert into public.consent_records(user_id, consent_type, notice_version, action, source, created_at) values
  ('e3000000-0000-4000-8000-000000000002', 'health_data', '2026-11-02', 'granted', 'ios_app', now() - interval '2 hours'),
  ('e3000000-0000-4000-8000-000000000002', 'health_data', '2026-11-02', 'withdrawn', 'ios_app', now() - interval '1 hour'),
  ('e3000000-0000-4000-8000-000000000003', 'health_data', '2026-07-01', 'granted', 'ios_app', now() - interval '1 hour'),
  ('e3000000-0000-4000-8000-000000000004', 'health_data', '2026-11-02', 'withdrawn', 'ios_app', now() - interval '2 hours'),
  ('e3000000-0000-4000-8000-000000000004', 'health_data', '2026-11-02', 'granted', 'ios_app', now() - interval '1 hour');

select ok(not has_function_privilege('authenticated', 'private.health_data_consent_granted(uuid)', 'execute'),
  'athletes cannot call the consent check');
select ok(not has_function_privilege('anon', 'private.health_data_consent_granted(uuid)', 'execute'),
  'signed-out callers cannot call the consent check');
select is(private.health_data_consent_granted('e3000000-0000-4000-8000-000000000001'), false, 'no record is not consent');
select is(private.health_data_consent_granted('e3000000-0000-4000-8000-000000000002'), false, 'a withdrawn grant is not consent');
select is(private.health_data_consent_granted('e3000000-0000-4000-8000-000000000003'), true, 'a grant of an older version counts');
select is(private.health_data_consent_granted('e3000000-0000-4000-8000-000000000004'), true, 'a later grant after a withdrawal counts');

-- health-sync (service role) ------------------------------------------------------------------
set local role service_role;
select throws_ok($$select public.persist_health_sync_v2('e3000000-0000-4000-8000-000000000001',
  'e3100000-0000-4000-8000-000000000001', current_date - 1, current_date, array['steps'],
  array['steps'], '[]'::jsonb, '[]'::jsonb)$$, 'P0403', 'health data consent required',
  'a sync without a record is refused');
select throws_ok($$select public.persist_health_sync_v2('e3000000-0000-4000-8000-000000000002',
  'e3100000-0000-4000-8000-000000000002', current_date - 1, current_date, array['steps'],
  array['steps'], '[]'::jsonb, '[]'::jsonb)$$, 'P0403', 'health data consent required',
  'a sync after withdrawal is refused');
select lives_ok($$select public.persist_health_sync_v2('e3000000-0000-4000-8000-000000000003',
  'e3100000-0000-4000-8000-000000000003', current_date - 1, current_date, array['steps'],
  array['steps'], '[]'::jsonb, '[]'::jsonb)$$, 'a sync with a grant of an older version is accepted');
select lives_ok($$select public.persist_health_sync_v2('e3000000-0000-4000-8000-000000000004',
  'e3100000-0000-4000-8000-000000000004', current_date - 1, current_date, array['steps'],
  array['steps'], '[]'::jsonb, '[]'::jsonb)$$, 'a sync after granting again is accepted');
reset role;
select is((select count(*) from public.health_sync_runs
  where user_id in ('e3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000002')),
  0::bigint, 'a refused sync leaves no run behind');

-- The athlete's own calls --------------------------------------------------------------------
create temporary table month(j jsonb);
insert into month values (jsonb_build_array(jsonb_build_object(
  'month', to_char(date_trunc('month', current_date) - interval '1 month', 'YYYY-MM-DD'),
  'workouts', 4, 'strength_workouts', 3, 'workout_minutes', 200, 'sleep_nights', 20,
  'sleep_minutes_avg', 420, 'weight_days', 2, 'weight_kg_avg', 80.5, 'data_days', 25,
  'first_data_date', to_char(date_trunc('month', current_date) - interval '1 month', 'YYYY-MM-DD'),
  'last_data_date', to_char(date_trunc('month', current_date) - interval '1 day', 'YYYY-MM-DD'))));
create temporary table night(j jsonb);
insert into night values (jsonb_build_array(jsonb_build_object(
  'local_date', (current_date - 1)::text, 'median_bpm', 52, 'lowest_bpm', 46, 'sample_count', 84,
  'asleep_minutes', 430, 'coverage', 0.81)));
create temporary table sets(j jsonb);
insert into sets values (jsonb_build_array(jsonb_build_object(
  'exercise_order', 1, 'set_number', 1, 'start_bpm', 110, 'peak_bpm', 150, 'end_bpm', 120,
  'coverage', 0.9, 'sample_count', 40, 'source', 'background')));
grant select on month, night, sets to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" = 'e3000000-0000-4000-8000-000000000001';
select throws_ok($$select public.save_health_history((select j from month))$$, 'P0403',
  'health data consent required', 'monthly totals without a record are refused');
select throws_ok($$select public.persist_sleeping_heart_rate_v1((select j from night))$$, 'P0403',
  'health data consent required', 'sleeping heart rate without a record is refused');
select throws_ok($$select public.persist_set_heart_rate_v1('e3200000-0000-4000-8000-000000000001',
  (select j from sets))$$, 'P0403', 'health data consent required',
  'set heart rate without a record is refused');

set local "request.jwt.claim.sub" = 'e3000000-0000-4000-8000-000000000002';
select throws_ok($$select public.save_health_history((select j from month))$$, 'P0403',
  'health data consent required', 'monthly totals after withdrawal are refused');
select throws_ok($$select public.persist_sleeping_heart_rate_v1((select j from night))$$, 'P0403',
  'health data consent required', 'sleeping heart rate after withdrawal is refused');
select throws_ok($$select public.persist_set_heart_rate_v1('e3200000-0000-4000-8000-000000000001',
  (select j from sets))$$, 'P0403', 'health data consent required',
  'set heart rate after withdrawal is refused');

set local "request.jwt.claim.sub" = 'e3000000-0000-4000-8000-000000000003';
select is(public.save_health_history((select j from month))->>'saved', '1',
  'monthly totals with a grant are saved');
select is(public.persist_sleeping_heart_rate_v1((select j from night))->>'saved', '1',
  'sleeping heart rate with a grant is saved');
select throws_ok($$select public.persist_set_heart_rate_v1('e3200000-0000-4000-8000-000000000001',
  (select j from sets))$$, 'P0002', 'session not found',
  'set heart rate with a grant passes the consent check');
reset role;

select * from finish();
rollback;
