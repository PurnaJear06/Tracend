begin;
select plan(38);

insert into auth.users(id, role) values
  ('b6000000-0000-4000-8000-000000000001', 'authenticated'),
  ('b6000000-0000-4000-8000-000000000002', 'authenticated');

create temporary table r(name text primary key, j jsonb);
grant all on r to authenticated;

-- Shape ----------------------------------------------------------------------------------------

select has_table('public', 'onboarding_screenings', 'the screening table exists');
select is((select array_agg(column_name::text order by column_name) from information_schema.columns
    where table_schema = 'public' and table_name = 'onboarding_screenings'),
  array['cleared_by_professional', 'exercises_regularly', 'id', 'known_disease', 'outcome',
    'screened_at', 'symptoms', 'user_id'],
  'the table holds the answers, the outcome and the date');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.onboarding_screenings'::regclass), 'row-level security is on and forced');
select ok(not has_table_privilege('authenticated', 'public.onboarding_screenings', 'insert'),
  'clients cannot insert screenings directly');
select ok(not has_table_privilege('authenticated', 'public.onboarding_screenings', 'update'),
  'clients cannot update screenings directly');
select ok(not has_table_privilege('authenticated', 'public.onboarding_screenings', 'delete'),
  'clients cannot delete screenings directly');
select ok(has_table_privilege('authenticated', 'public.onboarding_screenings', 'select'),
  'clients read their own screenings');
select ok(not has_table_privilege('anon', 'public.onboarding_screenings', 'select'),
  'signed-out callers read nothing');
select ok(has_function_privilege('authenticated',
  'public.record_screening_v1(boolean, boolean, boolean, boolean)', 'execute'),
  'athletes record a screening');
select ok(not has_function_privilege('anon',
  'public.record_screening_v1(boolean, boolean, boolean, boolean)', 'execute'),
  'signed-out callers cannot record');
select ok(not has_function_privilege('authenticated',
  'private.screening_outcome(boolean, boolean, boolean, boolean)', 'execute'),
  'the outcome rule is private');
select ok((select prosecdef from pg_proc
    where oid = 'public.record_screening_v1(boolean, boolean, boolean, boolean)'::regprocedure),
  'recording is security definer');
select is((select proconfig from pg_proc
    where oid = 'public.record_screening_v1(boolean, boolean, boolean, boolean)'::regprocedure),
  array['search_path=""'], 'with an empty search path');

-- The rule: all 16 answer combinations -------------------------------------------------------------
-- Ordered by exercises regularly (yes first), known condition, symptoms, cleared (no first).

select is((select array_agg(private.screening_outcome(e, k, s, c) order by e desc, k, s, c)
    from (values (true), (false)) a(e), (values (true), (false)) b(k),
      (values (true), (false)) c1(s), (values (true), (false)) d(c)),
  array[
    -- active, no known condition: only a symptom stops the plan
    'cleared', 'cleared', 'see_professional', 'see_professional',
    -- active, known condition: moderate until cleared, cleared once cleared
    'moderate_until_cleared', 'cleared', 'see_professional', 'see_professional',
    -- inactive, no known condition
    'cleared', 'cleared', 'see_professional', 'see_professional',
    -- inactive, known condition: see a professional until cleared
    'see_professional', 'cleared', 'see_professional', 'see_professional'],
  'the rule maps every combination as the training-engine handoff describes');

-- A stored outcome must agree with its answers (written as the table owner) ------------------------

select throws_ok($$insert into public.onboarding_screenings(user_id, exercises_regularly,
    known_disease, symptoms, cleared_by_professional, outcome)
  values ('b6000000-0000-4000-8000-000000000001', true, true, false, false, 'cleared')$$,
  '23514', null, 'an outcome that disagrees with the answers is refused');
select throws_ok($$insert into public.onboarding_screenings(user_id, exercises_regularly,
    known_disease, symptoms, cleared_by_professional, outcome)
  values ('b6000000-0000-4000-8000-000000000001', true, false, false, false, 'unknown')$$,
  '23514', null, 'and so is an outcome the contract does not know');

-- A records a screening -----------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'b6000000-0000-4000-8000-000000000001';

select is((select count(*) from public.onboarding_screenings), 0::bigint, 'nothing is stored yet');

insert into r select 'first', public.record_screening_v1(true, true, false, false);
select is((select array_agg(k order by k) from jsonb_object_keys((select j from r where name = 'first')) k),
  array['outcome', 'schema_version', 'screened_at'],
  'the record answer has exactly its contract keys');
select is((select j ->> 'schema_version' from r where name = 'first'), '1.0', 'at schema version 1.0');
select is((select j ->> 'outcome' from r where name = 'first'), 'moderate_until_cleared',
  'active with a known condition and no clearance stays at moderate effort');
select ok((select (j ->> 'screened_at')::timestamptz from r where name = 'first') is not null,
  'and carries the date');
select is((select array[exercises_regularly::text, known_disease::text, symptoms::text,
    cleared_by_professional::text, outcome] from public.onboarding_screenings),
  array['true', 'true', 'false', 'false', 'moderate_until_cleared'],
  'the answers and the outcome are stored');

insert into r select 'again', public.record_screening_v1(true, true, false, false);
select is((select count(*) from public.onboarding_screenings), 1::bigint,
  'answering the same again adds no row');
select is((select j from r where name = 'again'), (select j from r where name = 'first'),
  'and returns the same screening');

insert into r select 'cleared', public.record_screening_v1(true, true, false, true);
select is((select j ->> 'outcome' from r where name = 'cleared'), 'cleared',
  'a professional clearance clears the athlete');
select is((select count(*) from public.onboarding_screenings), 2::bigint,
  'a changed answer adds a row and keeps the earlier one');

insert into r select 'symptom', public.record_screening_v1(true, false, true);
select is((select j ->> 'outcome' from r where name = 'symptom'), 'see_professional',
  'a current symptom means see a professional (the clearance answer defaults to no)');
select is((select outcome from public.onboarding_screenings order by screened_at desc, id desc limit 1),
  'see_professional', 'and the newest row is the current one');

select throws_ok($$select public.record_screening_v1(null, false, false)$$, '22023', null,
  'a missing answer is refused');
select throws_ok($$select public.record_screening_v1(true, false, false, null)$$, '22023', null,
  'including the clearance answer');

-- B sees none of it ---------------------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'b6000000-0000-4000-8000-000000000002';
select is((select count(*) from public.onboarding_screenings), 0::bigint,
  'another athlete sees none of the rows');
insert into r select 'other', public.record_screening_v1(false, false, false);
select is((select j ->> 'outcome' from r where name = 'other'), 'cleared',
  'inactive with nothing to report is cleared');
select is((select count(*) from public.onboarding_screenings), 1::bigint,
  'and sees only their own row');

set local "request.jwt.claim.sub" = '';
select throws_ok($$select public.record_screening_v1(true, false, false)$$, '42501', null,
  'a caller with no identity cannot record');

-- Audit and deletion --------------------------------------------------------------------------------

reset role;
select is((select count(*) from public.audit_events
    where user_id = 'b6000000-0000-4000-8000-000000000001'
      and action_code = 'onboarding_screening_recorded'),
  3::bigint, 'each new screening is audited once');
select is((select array_agg(metadata order by created_at, id) from public.audit_events
    where user_id = 'b6000000-0000-4000-8000-000000000002'
      and action_code = 'onboarding_screening_recorded'),
  array['{"screening_outcome":"cleared"}'::jsonb], 'with the outcome and no answers');

delete from auth.users where id = 'b6000000-0000-4000-8000-000000000001';
select is((select count(*) from public.onboarding_screenings
    where user_id = 'b6000000-0000-4000-8000-000000000001'),
  0::bigint, 'deleting the account deletes the screenings');
select is((select count(*) from public.onboarding_screenings), 1::bigint,
  'and leaves another athlete''s');

select * from finish();
rollback;
