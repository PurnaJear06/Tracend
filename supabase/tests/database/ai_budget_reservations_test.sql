begin;
select plan(18);

insert into auth.users(id, role) values
  ('d1000000-0000-4000-8000-000000000001', 'authenticated'),
  ('d1000000-0000-4000-8000-000000000002', 'authenticated'),
  ('d1000000-0000-4000-8000-000000000003', 'authenticated');

select ok(not has_function_privilege('authenticated', 'public.reserve_ai_budget(uuid,text)', 'execute'),
  'clients cannot reserve budget');
select ok(not has_function_privilege('authenticated', 'public.settle_ai_budget(uuid)', 'execute'),
  'clients cannot settle budget');
select ok(not has_table_privilege('authenticated', 'public.ai_budget_reservations', 'select'),
  'clients cannot read reservations');

set local role service_role;
create temporary table held as
select public.reserve_ai_budget('d1000000-0000-4000-8000-000000000001', 'meal_vision') id;
select is((select reserved_cost_usd from public.ai_budget_reservations where id = (select id from held)),
  0.010000::numeric(10,6), 'a reservation holds its purpose ceiling');
select throws_ok($$select public.reserve_ai_budget('d1000000-0000-4000-8000-000000000001', 'unknown')$$,
  '22023', null, 'an unknown purpose is refused');

-- Open reservations count toward the day's requests.
reset role;
insert into public.ai_budget_reservations(user_id, purpose, reserved_cost_usd)
select 'd1000000-0000-4000-8000-000000000001', 'coach_chat', 0.02 from generate_series(1, 29);
set local role service_role;
select throws_ok($$select public.reserve_ai_budget('d1000000-0000-4000-8000-000000000001', 'coach_chat')$$,
  'P0001', 'daily rate limit reached', 'open reservations count toward the daily limit');
select throws_ok($$select public.assert_owner_ai_budget('d1000000-0000-4000-8000-000000000001')$$,
  'P0001', 'daily rate limit reached', 'the older check counts open reservations too');

select lives_ok(format($$select public.settle_ai_budget(%L)$$, (select id from held)),
  'a reservation settles');
select lives_ok(format($$select public.settle_ai_budget(%L)$$, (select id from held)),
  'settling twice is harmless');
select is((select settled_at is not null from public.ai_budget_reservations where id = (select id from held)),
  true, 'the settled reservation no longer counts');
select lives_ok($$select public.reserve_ai_budget('d1000000-0000-4000-8000-000000000001', 'coach_chat')$$,
  'a settled place frees the limit');

-- Monthly cost: open places count at their ceiling.
reset role;
insert into public.ai_usage_events(user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
values ('d1000000-0000-4000-8000-000000000002', 'meal_vision', 'groq', 'qwen/qwen3.8-27b', 1, 1, 1.99, 1);
insert into public.ai_budget_reservations(user_id, purpose, reserved_cost_usd)
values ('d1000000-0000-4000-8000-000000000002', 'meal_vision', 0.01);
set local role service_role;
select throws_ok($$select public.reserve_ai_budget('d1000000-0000-4000-8000-000000000002', 'meal_vision')$$,
  'P0001', 'monthly cost limit reached', 'an open reservation counts toward the monthly stop');

-- A place whose ceiling would cross the stop is refused.
reset role;
insert into public.ai_usage_events(user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
values ('d1000000-0000-4000-8000-000000000003', 'meal_vision', 'groq', 'qwen/qwen3.8-27b', 1, 1, 1.995, 1);
set local role service_role;
select throws_ok($$select public.reserve_ai_budget('d1000000-0000-4000-8000-000000000003', 'meal_vision')$$,
  'P0001', 'monthly cost limit reached', 'a call that could cross the monthly stop is refused');
reset role;
delete from public.ai_usage_events where user_id = 'd1000000-0000-4000-8000-000000000003';

-- Global stop.
reset role;
update private.ai_budget_limits set global_monthly_usd = 2.5;
delete from public.ai_budget_reservations where user_id = 'd1000000-0000-4000-8000-000000000002';
update public.ai_usage_events set estimated_cost_usd = 1.0
where user_id = 'd1000000-0000-4000-8000-000000000002';
insert into public.ai_usage_events(user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
values ('d1000000-0000-4000-8000-000000000001', 'meal_vision', 'groq', 'qwen/qwen3.8-27b', 1, 1, 1.5, 1);
set local role service_role;
select throws_ok($$select public.reserve_ai_budget('d1000000-0000-4000-8000-000000000002', 'meal_vision')$$,
  'P0001', 'global monthly cost limit reached', 'the stop across all accounts applies');
select throws_ok($$select public.assert_owner_ai_budget('d1000000-0000-4000-8000-000000000002')$$,
  'P0001', 'global monthly cost limit reached', 'the older check applies the global stop too');
reset role;

-- The athlete's own view.
set local role authenticated;
set local "request.jwt.claim.sub" = 'd1000000-0000-4000-8000-000000000002';
select is((public.get_my_ai_budget_state()->>'schema_version'), '1.0', 'the budget state is versioned');
select is((public.get_my_ai_budget_state()->>'estimated_cost_usd')::numeric, 1.0::numeric,
  'the budget state shows recorded usage');
reset role;

select ok(has_function_privilege('service_role',
  'public.persist_failed_coach_chat_run_v2(uuid,uuid,uuid,uuid,integer,text,text,text,text[],integer,integer,numeric)',
  'execute'), 'the service role records failed Coach usage');

select * from finish();
rollback;
