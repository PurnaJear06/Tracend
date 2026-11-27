begin;
select plan(133);

-- Cycle data access (migrations 20261127141837 and 20261127142651): the consent type, the tables'
-- privileges and row-level security, every gate of the six functions, the Apple Health merge, the
-- answer's key set (test/contract/fixtures/my_cycle_v1_0_*.json), "Delete my cycle data" and
-- account deletion. The engine's rules are in cycle_engine_test.sql.

insert into auth.users(id, role) values
  ('c2000000-0000-4000-8000-000000000001', 'authenticated'),
  ('c2000000-0000-4000-8000-000000000002', 'authenticated'),
  ('c2000000-0000-4000-8000-000000000003', 'authenticated'),
  ('c2000000-0000-4000-8000-000000000004', 'authenticated');

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid, true);
end $$;

create function pg_temp.today() returns date language sql as $$
  select private.local_date_for('c2000000-0000-4000-8000-000000000001');
$$;

create function pg_temp.keys(p_value jsonb) returns text[] language sql as $$
  select array_agg(k order by k) from jsonb_object_keys(p_value) k;
$$;

create function pg_temp.audits(p_uid text, p_action text) returns bigint language sql as $$
  select count(*) from public.audit_events
  where user_id = p_uid::uuid and action_code = p_action;
$$;

-- The consent type and the shape ----------------------------------------------------------------------

select ok('cycle_data' = any (enum_range(null::public.consent_type)::text[]),
  'cycle_data is a consent type');
select has_table('public', 'cycle_settings', 'the cycle settings table exists');
select has_table('public', 'cycle_day_logs', 'the cycle day table exists');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.cycle_settings'::regclass), 'cycle_settings: row-level security on and forced');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.cycle_day_logs'::regclass), 'cycle_day_logs: row-level security on and forced');
select ok(has_table_privilege('authenticated', 'public.cycle_settings', 'select')
  and not has_table_privilege('authenticated', 'public.cycle_settings', 'insert')
  and not has_table_privilege('authenticated', 'public.cycle_settings', 'update')
  and not has_table_privilege('authenticated', 'public.cycle_settings', 'delete'),
  'athletes read their cycle settings and cannot write them directly');
select ok(has_table_privilege('authenticated', 'public.cycle_day_logs', 'select')
  and not has_table_privilege('authenticated', 'public.cycle_day_logs', 'insert')
  and not has_table_privilege('authenticated', 'public.cycle_day_logs', 'update')
  and not has_table_privilege('authenticated', 'public.cycle_day_logs', 'delete'),
  'athletes read their cycle days and cannot write them directly');
select ok(not has_table_privilege('anon', 'public.cycle_settings', 'select')
  and not has_table_privilege('anon', 'public.cycle_settings', 'insert')
  and not has_table_privilege('anon', 'public.cycle_settings', 'update')
  and not has_table_privilege('anon', 'public.cycle_settings', 'delete')
  and not has_table_privilege('anon', 'public.cycle_day_logs', 'select')
  and not has_table_privilege('anon', 'public.cycle_day_logs', 'insert')
  and not has_table_privilege('anon', 'public.cycle_day_logs', 'update')
  and not has_table_privilege('anon', 'public.cycle_day_logs', 'delete'),
  'signed-out callers have no access to either table');

select ok(has_function_privilege('authenticated', 'public.get_my_cycle_v1()', 'execute')
  and has_function_privilege('authenticated',
    'public.set_my_cycle_settings_v1(boolean, text, integer, boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.log_cycle_day_v1(date, text, text, boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.import_cycle_days_v1(date, date, jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.delete_my_cycle_data_v1()', 'execute'),
  'athletes can call their five cycle functions');
select ok(not has_function_privilege('anon', 'public.get_my_cycle_v1()', 'execute')
  and not has_function_privilege('anon',
    'public.set_my_cycle_settings_v1(boolean, text, integer, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.log_cycle_day_v1(date, text, text, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.import_cycle_days_v1(date, date, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.delete_my_cycle_data_v1()', 'execute')
  and not has_function_privilege('anon', 'public.coach_cycle_state_v1(uuid, date)', 'execute'),
  'signed-out callers can call none of the cycle functions');
select ok(not has_function_privilege('authenticated', 'public.coach_cycle_state_v1(uuid, date)', 'execute'),
  'athletes cannot call Coach''s cycle read');
select ok(has_function_privilege('service_role', 'public.coach_cycle_state_v1(uuid, date)', 'execute'),
  'the service role can call Coach''s cycle read');
select ok(not has_function_privilege('service_role', 'public.get_my_cycle_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.delete_my_cycle_data_v1()', 'execute'),
  'the athlete functions are not granted to the service role');
select is((select count(*) from pg_proc p
    where p.oid in ('private.cycle_data_consent_granted(uuid)'::regprocedure,
      'private.cycle_median(integer[])'::regprocedure,
      'private.cycle_state(uuid, date)'::regprocedure,
      'private.cycle_answer(uuid, date, date, date)'::regprocedure)
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute')
        or has_function_privilege('service_role', p.oid, 'execute'))),
  0::bigint, 'no API role can call the private cycle helpers');
select is((select count(*) from pg_proc p
    where p.oid in ('public.get_my_cycle_v1()'::regprocedure,
      'public.set_my_cycle_settings_v1(boolean, text, integer, boolean)'::regprocedure,
      'public.log_cycle_day_v1(date, text, text, boolean)'::regprocedure,
      'public.import_cycle_days_v1(date, date, jsonb)'::regprocedure,
      'public.delete_my_cycle_data_v1()'::regprocedure,
      'public.coach_cycle_state_v1(uuid, date)'::regprocedure,
      'private.cycle_data_consent_granted(uuid)'::regprocedure,
      'private.cycle_state(uuid, date)'::regprocedure,
      'private.cycle_answer(uuid, date, date, date)'::regprocedure)
      and p.prosecdef and p.proconfig = array['search_path=""']),
  9::bigint, 'every cycle function is security definer with an empty search path');

-- The table's own constraints -------------------------------------------------------------------------
select throws_ok($$insert into public.cycle_settings(user_id, tracking_enabled)
  values ('c2000000-0000-4000-8000-000000000004', true)$$, '23514', null,
  'tracking needs a status');
select throws_ok($$insert into public.cycle_settings(user_id, typical_cycle_days)
  values ('c2000000-0000-4000-8000-000000000004', 14)$$, '23514', null,
  'a usual length under 15 days is refused');
select throws_ok($$insert into public.cycle_settings(user_id, apple_health_enabled)
  values ('c2000000-0000-4000-8000-000000000004', true)$$, '23514', null,
  'Apple Health reading needs tracking on');
select throws_ok($$insert into public.cycle_day_logs(user_id, local_date, flow, is_start, source)
  values ('c2000000-0000-4000-8000-000000000004', '2026-03-01', 'spotting', true, 'manual')$$,
  '23514', null, 'spotting cannot start a period');
select throws_ok($$insert into public.cycle_day_logs(user_id, local_date, flow, source)
  values ('c2000000-0000-4000-8000-000000000004', '2026-03-01', null, 'apple_health')$$,
  '23514', null, 'an Apple Health day always has a flow');
select throws_ok($$insert into public.cycle_day_logs(user_id, local_date, flow, source)
  values ('c2000000-0000-4000-8000-000000000004', '2026-03-01', 'gushing', 'manual')$$,
  '23514', null, 'a flow outside the list is refused');

-- Signed out --------------------------------------------------------------------------------------------
select pg_temp.as_user('');
select throws_ok($$select public.get_my_cycle_v1()$$, '42501', 'authentication required',
  'reading needs a signed-in athlete');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, false)$$, '42501',
  'authentication required', 'so do the settings');
select throws_ok($$select public.log_cycle_day_v1(current_date, 'light', null, false)$$, '42501',
  'authentication required', 'logging a day');
select throws_ok($$select public.import_cycle_days_v1(current_date - 1, current_date, '[]')$$, '42501',
  'authentication required', 'importing from Apple Health');
select throws_ok($$select public.delete_my_cycle_data_v1()$$, '42501', 'authentication required',
  'and deleting');

-- Never set up -------------------------------------------------------------------------------------------
select pg_temp.as_user('c2000000-0000-4000-8000-000000000001');
select is(public.get_my_cycle_v1(),
  '{"schema_version":"1.0","tracking_enabled":false,"status":null,"typical_cycle_days":null,
    "apple_health_enabled":false,"state":{"cycle_day":null,"period_day":null,"phase":null,
    "confidence":null,"expected_from":null,"expected_to":null,"late_days":null,
    "no_period_long":false,"weight_water_window":false},"recent_days":[],"cycles":[]}'::jsonb,
  'an athlete who never set it up gets exactly the off answer (my_cycle_v1_0_off.json)');

-- Settings: bad input and consent ----------------------------------------------------------------------
select throws_ok($$select public.set_my_cycle_settings_v1(null, 'regular', 28, false)$$, '22023', null,
  'tracking must be on or off');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, null)$$, '22023', null,
  'Apple Health must be on or off');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'pregnant', 28, false)$$, '22023',
  'unknown cycle status', 'a status outside the four is refused');
select throws_ok($$select public.set_my_cycle_settings_v1(true, null, 28, false)$$, '22023',
  'tracking needs a cycle status', 'tracking on needs a status');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 14, false)$$, '22023',
  'a cycle length is 15 to 60 days', 'a usual length under 15 days is refused');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 61, false)$$, '22023',
  'a cycle length is 15 to 60 days', 'a usual length over 60 days is refused');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, false)$$, 'P0403',
  'cycle_consent_required', 'turning tracking on without the cycle data consent is refused');
select is((select count(*) from public.cycle_settings
    where user_id = 'c2000000-0000-4000-8000-000000000001'), 0::bigint, 'and stores nothing');

insert into public.consent_records(user_id, consent_type, notice_version, action, source, created_at) values
  ('c2000000-0000-4000-8000-000000000001', 'cycle_data', '2026-11-27', 'granted', 'ios_app',
   now() - interval '1 hour');
select is(private.cycle_data_consent_granted('c2000000-0000-4000-8000-000000000001'), true,
  'a grant is consent');
select is(private.cycle_data_consent_granted('c2000000-0000-4000-8000-000000000002'), false,
  'no record is not consent');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, true)$$, 'P0403',
  'health_consent_required', 'reading Apple Health also needs the health data consent');

select lives_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, false)$$,
  'with the consent she can turn tracking on');
select is((select tracking_enabled_at is not null from public.cycle_settings
    where user_id = 'c2000000-0000-4000-8000-000000000001'), true,
  'turning tracking on records when');
select is(pg_temp.audits('c2000000-0000-4000-8000-000000000001', 'cycle.settings.changed'), 1::bigint,
  'the change leaves one audit event');
select is((select metadata from public.audit_events
    where user_id = 'c2000000-0000-4000-8000-000000000001' and action_code = 'cycle.settings.changed'),
  '{"schema_version":"1.0","changed":["tracking_enabled","status","typical_cycle_days"]}'::jsonb,
  'naming the changed fields only, never their values');
select lives_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, false)$$,
  'saving the same settings again is fine');
select is(pg_temp.audits('c2000000-0000-4000-8000-000000000001', 'cycle.settings.changed'), 1::bigint,
  'and leaves no audit event');

update public.user_accounts set account_status = 'deletion_pending'
  where id = 'c2000000-0000-4000-8000-000000000001';
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'irregular', 28, false)$$, '42501',
  'active account required', 'an account being deleted cannot change its settings');
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today(), 'light', null, false)$$, '42501',
  'active account required', 'or log a day');
update public.user_accounts set account_status = 'active'
  where id = 'c2000000-0000-4000-8000-000000000001';

-- Logging ------------------------------------------------------------------------------------------------
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today() - 401, 'light', null, false)$$,
  '22023', null, 'a day more than 400 days ago is refused');
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today() + 2, 'light', null, false)$$,
  '22023', null, 'a day after tomorrow is refused');
select throws_ok($$select public.log_cycle_day_v1(null, 'light', null, false)$$, '22023', null,
  'a day is required');
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today(), 'gushing', null, false)$$, '22023',
  'unknown flow', 'a flow outside the list is refused');
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today(), 'light', 'severe', false)$$, '22023',
  'unknown cramps', 'cramps outside the list are refused');
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today(), 'spotting', null, true)$$, '22023',
  'a period starts with bleeding', 'spotting cannot start a period');
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today(), null, null, true)$$, '22023',
  'a period starts with bleeding', 'neither can a day without bleeding');

select lives_ok($$select public.log_cycle_day_v1(pg_temp.today() - 3, 'medium', 'mild', true)$$,
  'she logs the first day of her period');
select lives_ok($$select public.log_cycle_day_v1(pg_temp.today() - 2, 'heavy', null, false)$$,
  'and the next day');
select lives_ok($$select public.log_cycle_day_v1(pg_temp.today() - 400, null, 'mild', null)$$,
  '400 days ago is accepted, cramps without bleeding are fine and a null start flag means no');
select lives_ok($$select public.log_cycle_day_v1(pg_temp.today() + 1, 'light', null, false)$$,
  'tomorrow is accepted (her phone may be a day ahead)');
select is((select is_start from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and local_date = pg_temp.today() - 400),
  false, 'the null start flag was stored as false');
select is(pg_temp.audits('c2000000-0000-4000-8000-000000000001', 'cycle.settings.changed'), 1::bigint,
  'logging leaves no audit event');

create temporary table answer as select public.get_my_cycle_v1() as body;
select is(pg_temp.keys((select body from answer)),
  array['apple_health_enabled', 'cycles', 'recent_days', 'schema_version', 'state', 'status',
    'tracking_enabled', 'typical_cycle_days'],
  'the answer carries exactly the contract keys (test/contract/fixtures/my_cycle_v1_0_regular.json)');
select is(pg_temp.keys((select body -> 'state' from answer)),
  array['confidence', 'cycle_day', 'expected_from', 'expected_to', 'late_days', 'no_period_long',
    'period_day', 'phase', 'weight_water_window'],
  'its state carries exactly the fixture''s state keys');
select is(pg_temp.keys((select body -> 'recent_days' -> 0 from answer)),
  array['cramps', 'flow', 'is_start', 'local_date', 'source'],
  'each recent day carries exactly the fixture''s day keys');
select is(pg_temp.keys((select body -> 'cycles' -> 0 from answer)),
  array['length_days', 'start_date', 'used'],
  'each cycle carries exactly the fixture''s cycle keys');
select is((select body ->> 'schema_version' from answer), '1.0', 'schema version 1.0');
select is((select jsonb_path_query_array(body -> 'recent_days', '$[*].local_date') from answer),
  jsonb_build_array(pg_temp.today() - 3, pg_temp.today() - 2, pg_temp.today() + 1),
  'recent days are the last 60 days and tomorrow, oldest first (400 days ago is not one of them)');
select is((select body -> 'recent_days' -> 0 from answer),
  jsonb_build_object('local_date', pg_temp.today() - 3, 'flow', 'medium', 'cramps', 'mild',
    'is_start', true, 'source', 'manual'), 'a logged day comes back as she logged it');
select is((select body -> 'state' ->> 'cycle_day' from answer), '4', 'today is cycle day 4');
select is((select body -> 'state' ->> 'period_day' from answer), '4',
  'and period day 4 (the period may still be going two days after the last bleeding day)');
select is((select body -> 'cycles' from answer),
  jsonb_build_array(jsonb_build_object('start_date', pg_temp.today() - 3, 'length_days', null,
    'used', false)), 'one cycle so far');

select lives_ok($$select public.log_cycle_day_v1(pg_temp.today() - 2, 'light', 'strong', false)$$,
  'logging a day again replaces it');
select is((select flow || '/' || cramps from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and local_date = pg_temp.today() - 2),
  'light/strong', 'with the new answer');
select is((select count(*) from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and local_date = pg_temp.today() - 2),
  1::bigint, 'and keeps one row per day');

-- Coach's read ---------------------------------------------------------------------------------------
select is(jsonb_path_query_array(public.coach_cycle_state_v1('c2000000-0000-4000-8000-000000000001',
    pg_temp.today()) -> 'recent_days', '$[*].local_date'),
  jsonb_build_array(pg_temp.today() - 3, pg_temp.today() - 2),
  'Coach reads the 14 days ending the coaching date');
select is(pg_temp.keys(public.coach_cycle_state_v1('c2000000-0000-4000-8000-000000000001',
    pg_temp.today())), pg_temp.keys((select body from answer)), 'in the same shape as the athlete');
select is(public.coach_cycle_state_v1('c2000000-0000-4000-8000-000000000001', pg_temp.today() - 4)
    -> 'state' -> 'cycle_day', 'null'::jsonb,
  'on an earlier date the days after it are not read');
select throws_ok($$select public.coach_cycle_state_v1(null, current_date)$$, '22023', null,
  'Coach''s read needs an athlete');
select throws_ok($$select public.coach_cycle_state_v1('c2000000-0000-4000-8000-000000000001', null)$$,
  '22023', null, 'and a date');

-- Apple Health ------------------------------------------------------------------------------------------
create temporary table days(j jsonb);
insert into days values (jsonb_build_array(
  jsonb_build_object('local_date', pg_temp.today() - 3, 'flow', 'light', 'is_start', false),
  jsonb_build_object('local_date', pg_temp.today() - 6, 'flow', 'medium', 'is_start', true),
  jsonb_build_object('local_date', pg_temp.today() - 7, 'flow', 'light', 'is_start', false)));

select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 10, pg_temp.today(),
  (select j from days))$$, 'P0403', 'apple_health_off', 'importing needs Apple Health reading on');

insert into public.consent_records(user_id, consent_type, notice_version, action, source, created_at) values
  ('c2000000-0000-4000-8000-000000000001', 'health_data', '2026-11-27', 'granted', 'ios_app',
   now() - interval '1 hour');
select lives_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, true)$$,
  'with both consents she turns Apple Health reading on');
select is((select count(*) from public.audit_events
    where user_id = 'c2000000-0000-4000-8000-000000000001' and action_code = 'cycle.settings.changed'
      and metadata -> 'changed' = '["apple_health_enabled"]'::jsonb),
  1::bigint, 'the audit event names only the Apple Health field');

select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 10, pg_temp.today() + 2, '[]')$$,
  '22023', null, 'a window ending after tomorrow is refused');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 401, pg_temp.today(), '[]')$$,
  '22023', null, 'a window over 400 days is refused');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today(), pg_temp.today() - 1, '[]')$$,
  '22023', null, 'a window that ends before it starts is refused');
select throws_ok($$select public.import_cycle_days_v1(null, pg_temp.today(), '[]')$$,
  '22023', null, 'a window needs a start');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(), '{}')$$,
  '22023', null, 'days must be a list');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(),
  jsonb_build_array(jsonb_build_object('local_date', pg_temp.today(), 'flow', 'light')))$$,
  '22023', null, 'a day without a start flag is refused');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(),
  jsonb_build_array(jsonb_build_object('local_date', pg_temp.today(), 'flow', 'light',
    'is_start', false, 'cramps', 'mild')))$$,
  '22023', null, 'a day with any other field is refused');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(),
  jsonb_build_array(jsonb_build_object('local_date', pg_temp.today() - 2, 'flow', 'light',
    'is_start', false)))$$,
  '22023', null, 'a day outside the window is refused');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(),
  jsonb_build_array(jsonb_build_object('local_date', pg_temp.today(), 'flow', 'spotting',
    'is_start', false)))$$,
  '22023', null, 'spotting is not an Apple Health flow');
select throws_ok($$select public.import_cycle_days_v1('2026-02-01', '2026-03-01',
  '[{"local_date":"2026-02-30","flow":"light","is_start":false}]')$$,
  '22023', null, 'a date that does not exist is refused');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(),
  jsonb_build_array('2026-03-01'))$$, '22023', null, 'a day must be an object');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(),
  jsonb_build_array(
    jsonb_build_object('local_date', pg_temp.today(), 'flow', 'light', 'is_start', false),
    jsonb_build_object('local_date', pg_temp.today(), 'flow', 'heavy', 'is_start', false)))$$,
  '22023', 'a day appears twice', 'the same day twice is refused');

select is(public.import_cycle_days_v1(pg_temp.today() - 10, pg_temp.today(), (select j from days)),
  '{"schema_version":"1.0","imported":2,"removed":0}'::jsonb,
  'the import writes the two days she did not log herself');
select is((select flow || '/' || source from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and local_date = pg_temp.today() - 3),
  'medium/manual', 'her own day is not overwritten by Apple Health');
select is((select cramps is null and is_start from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and local_date = pg_temp.today() - 6),
  true, 'an Apple Health day keeps the start flag and has no cramps');

select is(public.import_cycle_days_v1(pg_temp.today() - 10, pg_temp.today(), (select j from days)),
  '{"schema_version":"1.0","imported":0,"removed":0}'::jsonb, 'the same import again changes nothing');
select is(public.import_cycle_days_v1(pg_temp.today() - 10, pg_temp.today(),
    jsonb_build_array(jsonb_build_object('local_date', pg_temp.today() - 6, 'flow', 'heavy',
      'is_start', true))),
  '{"schema_version":"1.0","imported":1,"removed":1}'::jsonb,
  'the window is the truth: a changed day is updated and a missing one removed');
select is((select count(*) from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and local_date = pg_temp.today() - 7),
  0::bigint, 'the removed day is gone');
select is((select count(*) from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and source = 'manual'),
  4::bigint, 'and no manual day was touched');

-- A manual "no bleeding" day blocks Apple Health; a manual write replaces an Apple Health day.
select lives_ok($$select public.log_cycle_day_v1(pg_temp.today() - 8, null, null, false)$$,
  'she says there was no bleeding 8 days ago');
select is(public.import_cycle_days_v1(pg_temp.today() - 10, pg_temp.today(),
    jsonb_build_array(
      jsonb_build_object('local_date', pg_temp.today() - 6, 'flow', 'heavy', 'is_start', true),
      jsonb_build_object('local_date', pg_temp.today() - 8, 'flow', 'heavy', 'is_start', false))),
  '{"schema_version":"1.0","imported":0,"removed":0}'::jsonb,
  'Apple Health cannot bring back a day she cleared');
select is((select flow is null and source = 'manual' from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and local_date = pg_temp.today() - 8),
  true, 'the cleared day stays cleared');
select lives_ok($$select public.log_cycle_day_v1(pg_temp.today() - 6, 'medium', null, true)$$,
  'she corrects the Apple Health day');
select is(public.import_cycle_days_v1(pg_temp.today() - 10, pg_temp.today(), '[]'),
  '{"schema_version":"1.0","imported":0,"removed":0}'::jsonb,
  'an empty window removes no manual day');
select is((select source from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001' and local_date = pg_temp.today() - 6),
  'manual', 'the corrected day is hers now');

-- Turning tracking off -------------------------------------------------------------------------------
select lives_ok($$select public.set_my_cycle_settings_v1(false, 'regular', 28, true)$$,
  'she turns tracking off');
select is((select tracking_enabled or apple_health_enabled from public.cycle_settings
    where user_id = 'c2000000-0000-4000-8000-000000000001'), false,
  'tracking off turns Apple Health reading off too');
select is((select count(*) from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001'), 6::bigint, 'and keeps her logged days');
select is(public.get_my_cycle_v1() -> 'recent_days', '[]'::jsonb, 'which are not shown while it is off');
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today(), 'light', null, false)$$, 'P0403',
  'cycle_tracking_off', 'logging needs tracking on');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(), '[]')$$,
  'P0403', 'cycle_tracking_off', 'so does importing');
update public.cycle_settings set tracking_enabled_at = '2026-01-01 00:00:00+00'
  where user_id = 'c2000000-0000-4000-8000-000000000001';
select lives_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, true)$$,
  'she turns it on again');
select is((select tracking_enabled_at = now() from public.cycle_settings
    where user_id = 'c2000000-0000-4000-8000-000000000001'), true,
  'turning it on again restarts the tracking time');

-- Withdrawn consents -----------------------------------------------------------------------------------
insert into public.consent_records(user_id, consent_type, notice_version, action, source, created_at) values
  ('c2000000-0000-4000-8000-000000000001', 'health_data', '2026-11-27', 'withdrawn', 'ios_app',
   now() + interval '1 minute');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(), '[]')$$,
  'P0403', 'health_consent_required', 'importing needs the health data consent too');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, true)$$, 'P0403',
  'health_consent_required', 'and so does keeping Apple Health reading on');
select lives_ok($$select public.log_cycle_day_v1(pg_temp.today(), 'light', null, false)$$,
  'logging by hand needs only the cycle data consent');

-- An athlete with tracking on and Apple Health on but no cycle data consent (for example a record
-- written before a withdrawal) cannot log or import.
insert into public.consent_records(user_id, consent_type, notice_version, action, source) values
  ('c2000000-0000-4000-8000-000000000003', 'health_data', '2026-11-27', 'granted', 'ios_app');
insert into public.cycle_settings(user_id, tracking_enabled, status, apple_health_enabled,
  tracking_enabled_at)
values ('c2000000-0000-4000-8000-000000000003', true, 'irregular', true, now());
select pg_temp.as_user('c2000000-0000-4000-8000-000000000003');
select throws_ok($$select public.log_cycle_day_v1(pg_temp.today(), 'light', null, false)$$, 'P0403',
  'cycle_consent_required', 'logging without the cycle data consent is refused');
select throws_ok($$select public.import_cycle_days_v1(pg_temp.today() - 1, pg_temp.today(), '[]')$$,
  'P0403', 'cycle_consent_required', 'importing without it is refused');

-- Row-level security -------------------------------------------------------------------------------
select pg_temp.as_user('c2000000-0000-4000-8000-000000000002');
set local role authenticated;
select is((select count(*) from public.cycle_day_logs), 0::bigint,
  'another athlete sees none of these days');
select is((select count(*) from public.cycle_settings), 0::bigint, 'or these settings');
reset role;
select pg_temp.as_user('c2000000-0000-4000-8000-000000000001');
set local role authenticated;
select is((select count(*) from public.cycle_day_logs), 7::bigint, 'the athlete sees her own days');
select is((select count(*) from public.cycle_settings), 1::bigint, 'and her own settings');
reset role;

-- "Delete my cycle data" -------------------------------------------------------------------------------
select is(public.delete_my_cycle_data_v1(),
  '{"schema_version":"1.0","tracking_enabled":false,"status":null,"typical_cycle_days":null,
    "apple_health_enabled":false,"state":{"cycle_day":null,"period_day":null,"phase":null,
    "confidence":null,"expected_from":null,"expected_to":null,"late_days":null,
    "no_period_long":false,"weight_water_window":false},"recent_days":[],"cycles":[]}'::jsonb,
  'deleting answers with the off answer');
select is(public.get_my_cycle_v1() -> 'tracking_enabled', 'false'::jsonb, 'tracking is off');
select is((select count(*) from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000001'), 0::bigint, 'every logged day is gone');
select is((select count(*) from public.cycle_settings
    where user_id = 'c2000000-0000-4000-8000-000000000001'), 0::bigint, 'so are her cycle answers');
select is((select action::text || '/' || notice_version from public.consent_records
    where user_id = 'c2000000-0000-4000-8000-000000000001' and consent_type = 'cycle_data'
    order by created_at desc limit 1),
  'withdrawn/2026-11-27', 'the withdrawal of the cycle data consent is recorded');
select is(private.cycle_data_consent_granted('c2000000-0000-4000-8000-000000000001'), false,
  'so the consent no longer holds');
select is((select metadata from public.audit_events
    where user_id = 'c2000000-0000-4000-8000-000000000001' and action_code = 'cycle.data.deleted'),
  '{"schema_version":"1.0"}'::jsonb, 'one audit event, with no values');
select is((select count(*) from public.audit_events
    where user_id = 'c2000000-0000-4000-8000-000000000001' and action_code like 'cycle.%'
      and (metadata::text like '%regular%' or metadata::text like '%medium%'
        or metadata::text like '%heavy%' or metadata::text like '%light%')),
  0::bigint, 'no cycle audit event carries a status or a flow');
select throws_ok($$select public.set_my_cycle_settings_v1(true, 'regular', 28, false)$$, 'P0403',
  'cycle_consent_required', 'turning tracking on again asks for the consent again');

-- Deleting the account --------------------------------------------------------------------------------
insert into public.cycle_settings(user_id, tracking_enabled, status, tracking_enabled_at)
values ('c2000000-0000-4000-8000-000000000002', true, 'regular', now());
insert into public.cycle_day_logs(user_id, local_date, flow, source)
values ('c2000000-0000-4000-8000-000000000002', '2026-03-01', 'medium', 'manual');
select lives_ok($$delete from auth.users where id = 'c2000000-0000-4000-8000-000000000002'$$,
  'the account can be deleted');
select is((select count(*) from public.cycle_settings
    where user_id = 'c2000000-0000-4000-8000-000000000002')
  + (select count(*) from public.cycle_day_logs
    where user_id = 'c2000000-0000-4000-8000-000000000002'), 0::bigint,
  'and its cycle settings and days go with it');

select * from finish();
rollback;
