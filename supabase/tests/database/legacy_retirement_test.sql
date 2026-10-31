begin;
select plan(23);

insert into auth.users(id, role) values
  ('c3100000-0000-4000-8000-000000000001', 'authenticated'),
  ('c3100000-0000-4000-8000-000000000002', 'authenticated');

-- The first-generation onboarding approval and the fixture-meal and preference functions are
-- closed to the app roles. (Checked by privilege, not by calling them as a forbidden role.)
select ok(not has_function_privilege('authenticated',
  'public.respond_to_onboarding_proposal(uuid, public.proposal_response_action)', 'execute'),
  'the first-generation approval is closed to the app');
select ok(not has_function_privilege('anon',
  'public.respond_to_onboarding_proposal(uuid, public.proposal_response_action)', 'execute'),
  'and to anon');
select ok(has_function_privilege('authenticated',
  'public.respond_to_onboarding_proposal_v2(uuid, public.proposal_response_action, text)', 'execute'),
  'the current approval stays open');
select ok(not has_function_privilege('authenticated',
  'public.create_fixture_meal(date, text, text, uuid)', 'execute'),
  'create_fixture_meal is closed to the app');
select ok(not has_function_privilege('anon',
  'public.create_fixture_meal(date, text, text, uuid)', 'execute'),
  'create_fixture_meal is closed to anon');
select ok(not has_function_privilege('authenticated',
  'public.confirm_fixture_meal(uuid, uuid[])', 'execute'),
  'confirm_fixture_meal is closed to the app');
select ok(not has_function_privilege('authenticated',
  'public.confirm_fixture_meal_v2(uuid, jsonb)', 'execute'),
  'confirm_fixture_meal_v2 is closed to the app');
select ok(not has_function_privilege('anon',
  'public.confirm_fixture_meal_v2(uuid, jsonb)', 'execute'),
  'confirm_fixture_meal_v2 is closed to anon');
select ok(not has_function_privilege('authenticated',
  'public.persist_coach_preference(uuid, text, text, text, text)', 'execute'),
  'persist_coach_preference is closed to the app');
select ok(not has_function_privilege('anon',
  'public.persist_coach_preference(uuid, text, text, text, text)', 'execute'),
  'persist_coach_preference is closed to anon');
select ok(has_function_privilege('service_role',
  'public.persist_coach_preference(uuid, text, text, text, text)', 'execute'),
  'the service role keeps persist_coach_preference');
select ok(has_function_privilege('authenticated', 'public.confirm_analyzed_meal(uuid, jsonb)', 'execute'),
  'meal confirmation stays open through confirm_analyzed_meal');

-- The app role can no longer write the onboarding state; other account columns are unchanged
-- (the time zone is written through a function, not a column grant).
select ok(not has_column_privilege('authenticated', 'public.user_accounts', 'onboarding_state', 'update'),
  'the app cannot update onboarding_state');
select ok(not has_column_privilege('authenticated', 'public.user_accounts', 'onboarding_state', 'insert'),
  'or insert it');
select ok(has_column_privilege('authenticated', 'public.user_accounts', 'unit_system', 'update'),
  'but still updates the unit system');
select ok(has_column_privilege('authenticated', 'public.user_accounts', 'onboarding_state', 'select'),
  'and reads the onboarding state');

-- The first draft moves the account to in_progress; a finished onboarding is never reopened.
select is((select onboarding_state::text from public.user_accounts
  where id = 'c3100000-0000-4000-8000-000000000001'), 'not_started', 'a new account has not started');
insert into public.onboarding_drafts(user_id, path, current_section, payload)
values ('c3100000-0000-4000-8000-000000000001', 'beginner', 'goal', '{}'::jsonb);
select is((select onboarding_state::text from public.user_accounts
  where id = 'c3100000-0000-4000-8000-000000000001'), 'in_progress', 'the first draft starts onboarding');
update public.user_accounts set onboarding_state = 'completed'
where id = 'c3100000-0000-4000-8000-000000000001';
update public.onboarding_drafts set current_section = 'plan'
where user_id = 'c3100000-0000-4000-8000-000000000001';
select is((select onboarding_state::text from public.user_accounts
  where id = 'c3100000-0000-4000-8000-000000000001'), 'completed', 'a later save does not reopen it');
select ok(not has_function_privilege('authenticated', 'private.mark_onboarding_started()', 'execute'),
  'the trigger function is private');

-- schema_version on the meal totals.
select ok(has_function_privilege('authenticated', 'public.get_my_daily_nutrition(date)', 'execute'),
  'the daily nutrition read stays open');
set local role authenticated;
set local "request.jwt.claim.sub" = 'c3100000-0000-4000-8000-000000000002';
select is(public.get_my_daily_nutrition('2026-10-31') ->> 'schema_version', '1.0',
  'the daily nutrition read carries a schema version');
select is(public.get_my_daily_nutrition('2026-10-31') ->> 'confirmed_meals', '0',
  'and keeps its fields');
reset role;

select * from finish();
rollback;
