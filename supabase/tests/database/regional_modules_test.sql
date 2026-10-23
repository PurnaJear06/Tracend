begin;
select plan(37);

-- The athlete's optional country and the library regions it picks (migration
-- 20261023120044_regional_modules). Three athletes: A has an Indian time zone, B an en-GB locale,
-- C the defaults.

insert into auth.users(id, role) values
  ('e4000000-0000-4000-8000-000000000001', 'authenticated'),
  ('e4000000-0000-4000-8000-000000000002', 'authenticated'),
  ('e4000000-0000-4000-8000-000000000003', 'authenticated');
update public.user_accounts set timezone = 'Asia/Kolkata'
  where id = 'e4000000-0000-4000-8000-000000000001';
update public.user_accounts set locale = 'en-GB'
  where id = 'e4000000-0000-4000-8000-000000000002';

-- The column and who may touch it --------------------------------------------------------------

select has_column('public', 'user_accounts', 'country_code', 'accounts have an optional country');
select is((select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'user_accounts' and column_name = 'country_code'),
  'YES', 'it is optional');
select throws_ok(
  $$update public.user_accounts set country_code = 'aus' where id = 'e4000000-0000-4000-8000-000000000003'$$,
  '23514', null, 'only two capital letters are stored');
select ok(not has_column_privilege('authenticated', 'public.user_accounts', 'country_code', 'update'),
  'the app cannot write the column directly');
select ok(not has_column_privilege('authenticated', 'public.user_accounts', 'country_code', 'insert'),
  'nor insert it');
select ok(has_function_privilege('authenticated', 'public.get_my_country_v1()', 'execute'),
  'athletes read their country');
select ok(not has_function_privilege('anon', 'public.get_my_country_v1()', 'execute'),
  'signed-out callers cannot read it');
select ok(has_function_privilege('authenticated', 'public.set_my_country_v1(text)', 'execute'),
  'athletes set their country');
select ok(not has_function_privilege('anon', 'public.set_my_country_v1(text)', 'execute'),
  'signed-out callers cannot set it');
select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
    from pg_proc p where p.oid in (
      'public.get_my_country_v1()'::regprocedure, 'public.set_my_country_v1(text)'::regprocedure)),
  'both are security definer with an empty search path');

-- A reads and sets a country -------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'e4000000-0000-4000-8000-000000000001';

select is((select array_agg(k order by k) from jsonb_object_keys(public.get_my_country_v1()) k),
  array['country_code', 'schema_version'],
  'the read returns exactly the keys the app parses (add keys, never remove)');
select is(public.get_my_country_v1() ->> 'schema_version', '1.0', 'it carries a schema version');
select is(public.get_my_country_v1() -> 'country_code', 'null'::jsonb, 'no country is set at first');
select is(public.set_my_country_v1('au') ->> 'country_code', 'AU', 'a code is stored in capitals');
select is(public.get_my_country_v1() ->> 'country_code', 'AU', 'and read back');
select is(public.set_my_country_v1(' in ') ->> 'country_code', 'IN', 'spaces are trimmed');
select is(public.set_my_country_v1('ZZ') ->> 'schema_version', '1.0', 'the set carries a schema version');
select throws_ok($$select public.set_my_country_v1('AUS')$$, '22023', null,
  'a three-letter code is refused');
select throws_ok($$select public.set_my_country_v1('1A')$$, '22023', null,
  'a code with a digit is refused');
select is(public.get_my_country_v1() ->> 'country_code', 'ZZ', 'a refused code changes nothing');
select is(public.set_my_country_v1('') -> 'country_code', 'null'::jsonb, 'a blank code clears the choice');
select is(public.get_my_country_v1() -> 'country_code', 'null'::jsonb, 'and it reads as unset');
select lives_ok($$select public.set_my_country_v1()$$, 'clearing with no argument is fine');

-- B sets its own and cannot move A's
set local "request.jwt.claim.sub" = 'e4000000-0000-4000-8000-000000000002';
select is(public.set_my_country_v1('GB') ->> 'country_code', 'GB', 'another athlete sets theirs');

-- Signed out
set local "request.jwt.claim.sub" = '';
select throws_ok($$select public.get_my_country_v1()$$, '42501', null, 'reading needs a session');
select throws_ok($$select public.set_my_country_v1('IN')$$, '42501', null, 'setting needs a session');

reset role;
select is((select country_code from public.user_accounts where id = 'e4000000-0000-4000-8000-000000000001'),
  null, 'B setting a country did not touch A');

-- The regions an account maps to ---------------------------------------------------------------

create function pg_temp.regions(account uuid) returns text[]
language sql as $$
  select array_agg(r order by r collate "C") from unnest(private.library_regions_for_account(account)) r
$$;

select is(pg_temp.regions('e4000000-0000-4000-8000-000000000003'), array['global'],
  'with no country the default account sees global sources only');
select is(pg_temp.regions('e4000000-0000-4000-8000-000000000001'), array['IN', 'global'],
  'with no country an Indian time zone still adds IN');
update public.user_accounts set country_code = 'AU' where id = 'e4000000-0000-4000-8000-000000000001';
select is(pg_temp.regions('e4000000-0000-4000-8000-000000000001'), array['AU', 'global'],
  'a stored country replaces the time-zone guess');
update public.user_accounts set country_code = 'ZZ' where id = 'e4000000-0000-4000-8000-000000000001';
select is(pg_temp.regions('e4000000-0000-4000-8000-000000000001'), array['ZZ', 'global'],
  '"another country" is not guessed back into India from the time zone');
update public.user_accounts set country_code = 'US' where id = 'e4000000-0000-4000-8000-000000000002';
select is(pg_temp.regions('e4000000-0000-4000-8000-000000000002'), array['US', 'global'],
  'a stored country replaces the locale too');
update public.user_accounts set country_code = null where id = 'e4000000-0000-4000-8000-000000000002';
select is(pg_temp.regions('e4000000-0000-4000-8000-000000000002'), array['GB', 'global'],
  'clearing it returns to the locale');
select is(pg_temp.regions('e4000000-0000-4000-8000-0000000000ff'), array['global'],
  'an unknown account sees global sources only');

-- The search follows the stored country ----------------------------------------------------------

insert into private.library_sources (id, manifest_key, title, year, url, licence, region, topics, evidence_level, kind)
values
  ('e4000000-0000-4000-8000-0000000000a1', 'e4-test-au', 'Australian source', 2024,
    'https://example.test/au', 'proprietary', '{AU}', '{nutrition}', 'guideline', 'guideline'),
  ('e4000000-0000-4000-8000-0000000000a2', 'e4-test-in', 'Indian source', 2024,
    'https://example.test/in', 'proprietary', '{IN}', '{nutrition}', 'guideline', 'guideline');
insert into private.library_chunks (id, source_id, ordinal, section, body, token_count) values
  ('e4000000-0000-4000-8000-0000000000b1', 'e4000000-0000-4000-8000-0000000000a1', 0, 'Guidance',
    'Zorbaflexine intake guidance for Australian adults.', 8),
  ('e4000000-0000-4000-8000-0000000000b2', 'e4000000-0000-4000-8000-0000000000a2', 0, 'Guidance',
    'Zorbaflexine intake guidance for Indian adults.', 8);

-- A is in Australia (stored), B has the en-GB locale, C the defaults; A's time zone is Indian.
update public.user_accounts set country_code = 'AU' where id = 'e4000000-0000-4000-8000-000000000001';
select is((select array_agg(source_key order by source_key) from public.search_library_v3(
    'zorbaflexine', null, null, 8, null, 'e4000000-0000-4000-8000-000000000001')),
  array['e4-test-au'], 'an athlete who chose Australia sees the Australian source and not the Indian one');
update public.user_accounts set country_code = null where id = 'e4000000-0000-4000-8000-000000000001';
select is((select array_agg(source_key order by source_key) from public.search_library_v3(
    'zorbaflexine', null, null, 8, null, 'e4000000-0000-4000-8000-000000000001')),
  array['e4-test-in'], 'with no choice the Indian time zone still shows the Indian source only');
select is((select count(*) from public.search_library_v3(
    'zorbaflexine', null, null, 8, null, 'e4000000-0000-4000-8000-000000000003')),
  0::bigint, 'an athlete with no region sees neither');

select * from finish();
rollback;
