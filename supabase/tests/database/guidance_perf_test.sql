begin;
select plan(29);

-- Guidance performance: the zone check no longer reads the whole pg_timezone_names view on every call.
-- The new check must answer exactly as the view does, for every name and for the names the table lacks.

insert into auth.users(id, role) values
  ('b5500000-0000-4000-8000-000000000001', 'authenticated'),
  ('b5500000-0000-4000-8000-000000000002', 'authenticated');
-- These athletes answered the health check as cleared; a missing check is unscreened, never
-- cleared (20261102074318).
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms, outcome)
select u.id, true, false, false, 'cleared' from auth.users u
where not exists (select 1 from public.onboarding_screenings s where s.user_id = u.id);

-- 1. The table is the view ----------------------------------------------------------------------------
select is((select count(*) from private.timezone_names), (select count(*) from pg_catalog.pg_timezone_names),
  'the table has as many names as the view');
select is_empty($$select name from private.timezone_names except select name from pg_catalog.pg_timezone_names$$,
  'every name in the table is in the view');
select is_empty($$select name from pg_catalog.pg_timezone_names except select name from private.timezone_names$$,
  'every name in the view is in the table');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'private.timezone_names'::regclass),
  'the table has forced row level security');
select ok(not has_table_privilege('authenticated', 'private.timezone_names', 'select')
  and not has_table_privilege('anon', 'private.timezone_names', 'select'),
  'no API role can read the table');
select ok(not has_function_privilege('authenticated', 'private.known_timezone(text)', 'execute')
  and not has_function_privilege('anon', 'private.known_timezone(text)', 'execute'),
  'no API role can run the check');

-- 2. The check answers as the view does -----------------------------------------------------------------
select is((select bool_and(private.known_timezone(name)) from private.timezone_names), true,
  'every name the view lists is known');
select is(private.known_timezone('Asia/Kolkata'), true, 'a canonical name is known');
select is(private.known_timezone('Pacific/Kiritimati'), true, 'a +14 zone is known');
select is(private.known_timezone('Mars/Olympus'), false, 'an unknown name is not known');
select is(private.known_timezone(''), false, 'an empty name is not known');
select is(private.known_timezone(null), false, 'null is not known');
select is(private.known_timezone('asia/kolkata'),
  exists (select 1 from pg_catalog.pg_timezone_names z where z.name = 'asia/kolkata'),
  'a case variant is answered as the view answers it');
select is(private.known_timezone('IST'),
  exists (select 1 from pg_catalog.pg_timezone_names z where z.name = 'IST'),
  'an abbreviation is answered as the view answers it');
select is(private.known_timezone('EST5EDT'),
  exists (select 1 from pg_catalog.pg_timezone_names z where z.name = 'EST5EDT'),
  'a POSIX-style name is answered as the view answers it');
-- A name added to the tz database after the table was filled is found through the view.
delete from private.timezone_names where name = 'Europe/Paris';
select is(private.known_timezone('Europe/Paris'), true,
  'a name missing from the table is still known through the view');

-- A name the table holds but the server can no longer use (a tz update removed it) is not known, and
-- the check does not raise: the readers fall back to UTC.
insert into private.timezone_names (name) values ('Mars/Olympus');
select lives_ok($$select private.known_timezone('Mars/Olympus')$$,
  'a table name the server cannot use does not raise');
select is(private.known_timezone('Mars/Olympus'), false,
  'a table name the server cannot use is not known');
update public.user_accounts set timezone = 'Mars/Olympus' where id = 'b5500000-0000-4000-8000-000000000001';
select is(private.local_day_of('b5500000-0000-4000-8000-000000000001', timestamptz '2026-10-30 23:30+00'),
  date '2026-10-30', 'a table name the server cannot use reads as UTC for a moment');
delete from private.timezone_names where name = 'Mars/Olympus';

-- 3. The readers give what they gave ----------------------------------------------------------------------
update public.user_accounts set timezone = 'Pacific/Kiritimati' where id = 'b5500000-0000-4000-8000-000000000001';
select is(private.local_date_for('b5500000-0000-4000-8000-000000000001'),
  (statement_timestamp() at time zone 'Pacific/Kiritimati')::date, 'local_date_for reads the stored zone');
select is(private.local_day_of('b5500000-0000-4000-8000-000000000001', timestamptz '2026-10-30 12:00+00'),
  date '2026-10-31', 'local_day_of reads the stored zone');
select is(private.local_day('b5500000-0000-4000-8000-000000000001', timestamptz '2026-10-30 12:00+00'),
  date '2026-10-31', 'local_day reads the stored zone');
select is(private.user_timezone('b5500000-0000-4000-8000-000000000001'), 'Pacific/Kiritimati',
  'user_timezone gives the stored zone');

update public.user_accounts set timezone = 'Mars/Olympus' where id = 'b5500000-0000-4000-8000-000000000002';
select is(private.local_date_for('b5500000-0000-4000-8000-000000000002'),
  (statement_timestamp() at time zone 'UTC')::date, 'an unknown zone reads as UTC for the date');
select is(private.local_day_of('b5500000-0000-4000-8000-000000000002', timestamptz '2026-10-30 23:30+00'),
  date '2026-10-30', 'an unknown zone reads as UTC for a moment');
select is(private.local_day('b5500000-0000-4000-8000-000000000002', timestamptz '2026-10-30 23:30+00'),
  date '2026-10-30', 'an unknown zone reads as UTC for a coach lookup moment');
select is(private.user_timezone('b5500000-0000-4000-8000-000000000002'), 'UTC', 'an unknown zone gives UTC');

-- 4. The guidance does not care about the zone path --------------------------------------------------------
select is(private.deload_signals('b5500000-0000-4000-8000-000000000002', date '2026-10-30'),
  (select private.deload_signals('b5500000-0000-4000-8000-000000000001', date '2026-10-30')),
  'deload_signals runs with an unknown zone and gives what a known zone gives for an athlete with no plan');
select lives_ok($$select private.training_guidance('b5500000-0000-4000-8000-000000000002', date '2026-10-30')$$,
  'the guidance reads for an athlete whose stored zone is unknown');

select * from finish();
rollback;
