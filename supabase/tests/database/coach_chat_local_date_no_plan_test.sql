begin;
select plan(34);

-- Coach chat uses the athlete's own date, has one budget gate, and works without a plan
-- (migration 20261017170019).
--
-- Time cannot be set in a test, so the local date is checked in two zones 25 hours apart
-- (UTC+14 and UTC-11): at any moment at least one of them is on a different calendar day
-- from UTC, and each must get the date in its own zone, never current_date.

insert into auth.users(id, role) values
  ('a9000000-0000-4000-8000-000000000001', 'authenticated'),
  ('a9000000-0000-4000-8000-000000000002', 'authenticated'),
  ('a9000000-0000-4000-8000-000000000003', 'authenticated'),
  ('a9000000-0000-4000-8000-000000000004', 'authenticated');

update public.user_accounts set timezone = 'Pacific/Kiritimati'
  where id = 'a9000000-0000-4000-8000-000000000001';
update public.user_accounts set timezone = 'Pacific/Pago_Pago'
  where id = 'a9000000-0000-4000-8000-000000000002';

-- Athletes 1 and 4 have an approved plan and nutrition target; 2 and 3 have none.
insert into public.training_plans(id, user_id, title, source)
select ('a9100000-0000-4000-8000-00000000000' || n)::uuid,
  ('a9000000-0000-4000-8000-00000000000' || n)::uuid, 'A9 plan', 'imported'
from unnest(array[1, 4]) n;
insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
  prescription, rationale, approved_at, effective_date)
select ('a9200000-0000-4000-8000-00000000000' || n)::uuid,
  ('a9000000-0000-4000-8000-00000000000' || n)::uuid,
  ('a9100000-0000-4000-8000-00000000000' || n)::uuid,
  1, 'active', 4, 3, '{}', 'Approved fixture', now(), current_date
from unnest(array[1, 4]) n;
insert into public.nutrition_target_sets(
  id, user_id, version_number, status, calories, protein_g, carbohydrate_g, fat_g,
  rationale, approved_at, effective_date)
select ('a9300000-0000-4000-8000-00000000000' || n)::uuid,
  ('a9000000-0000-4000-8000-00000000000' || n)::uuid,
  1, 'active', 2200, 150, 240, 70, 'Approved fixture', now(), current_date
from unnest(array[1, 4]) n;
insert into public.coach_threads(id, user_id, title, status)
select ('a9400000-0000-4000-8000-00000000000' || n)::uuid,
  ('a9000000-0000-4000-8000-00000000000' || n)::uuid, 'A9 thread', 'active'
from generate_series(1, 4) n;

-- Athlete 3 was told to see a professional first, so no plan was built.
insert into public.onboarding_screenings(
  user_id, exercises_regularly, known_disease, symptoms, cleared_by_professional, outcome)
values ('a9000000-0000-4000-8000-000000000003', false, false, true, false, 'see_professional');

create temporary table calls(label text primary key, result jsonb);
grant all on calls to service_role;

set local role service_role;
insert into calls select 'p1', public.prepare_coach_chat(
  'a9000000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001',
  'How am I doing?', 'Pacific/Kiritimati', gen_random_uuid());
insert into calls select 'p2', public.prepare_coach_chat(
  'a9000000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001',
  'And today?', 'Pacific/Kiritimati', gen_random_uuid());
insert into calls select 'n1', public.prepare_coach_chat(
  'a9000000-0000-4000-8000-000000000002', 'a9400000-0000-4000-8000-000000000002',
  'What should I do?', 'Pacific/Pago_Pago', gen_random_uuid());
insert into calls select 's1', public.prepare_coach_chat(
  'a9000000-0000-4000-8000-000000000003', 'a9400000-0000-4000-8000-000000000003',
  'Can I train?', 'UTC', gen_random_uuid());
insert into calls select 'n7', public.prepare_coach_chat_v7(
  'a9000000-0000-4000-8000-000000000002', 'a9400000-0000-4000-8000-000000000002',
  'What should I do?', 'Pacific/Pago_Pago', gen_random_uuid(), 'general');
insert into calls select 'n8', public.prepare_coach_chat_v8(
  'a9000000-0000-4000-8000-000000000002', 'a9400000-0000-4000-8000-000000000002',
  'What should I do?', 'Pacific/Pago_Pago', gen_random_uuid(), 'general');
insert into calls select 'p8', public.prepare_coach_chat_v8(
  'a9000000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001',
  'How am I doing?', 'Pacific/Kiritimati', gen_random_uuid(), 'general');
reset role;

-- The athlete's own date ----------------------------------------------------------------
select is(
  (select result->'context'->>'coaching_date' from calls where label = 'p1'),
  (statement_timestamp() at time zone 'Pacific/Kiritimati')::date::text,
  'a UTC+14 athlete gets the date in their zone');
select is(
  (select result->'context'->>'coaching_date' from calls where label = 'n1'),
  (statement_timestamp() at time zone 'Pacific/Pago_Pago')::date::text,
  'a UTC-11 athlete gets the date in their zone');
select ok(
  (select bool_or(result->'context'->>'coaching_date' <> current_date::text)
   from calls where label in ('p1', 'n1')),
  'at least one of the two zones is on a different day from UTC, and chat followed the athlete');
select is(
  (select features->>'local_date' from public.feature_snapshots
   where user_id = 'a9000000-0000-4000-8000-000000000001' and trigger_kind = 'daily'
   order by created_at desc limit 1),
  (statement_timestamp() at time zone 'Pacific/Kiritimati')::date::text,
  'the day''s snapshot is made for the local date');
select is(
  (select result->>'feature_snapshot_id' from calls where label = 'p2'),
  (select result->>'feature_snapshot_id' from calls where label = 'p1'),
  'a second question the same local day reuses the day''s snapshot');
select is(
  (select count(*) from public.feature_snapshots
   where user_id = 'a9000000-0000-4000-8000-000000000001' and trigger_kind = 'daily'),
  1::bigint, 'and no second snapshot was made');

-- With a plan ------------------------------------------------------------------------------
select is((select result->'context'->'plan_status'->>'has_active_plan' from calls where label = 'p1'),
  'true', 'an athlete with a plan is marked as having one');
select is((select result->'context'->'plan_status'->>'reason' from calls where label = 'p1'),
  null, 'and has no reason for missing one');
select ok((select result->'context'->'permitted_evidence' ? 'APPROVED_PLAN_ACTIVE' from calls where label = 'p1'),
  'the approved plan can be cited as evidence');
select ok((select result->'context'->'permitted_evidence' ? 'APPROVED_PLAN_ACTIVE' from calls where label = 'p8'),
  'the full v8 context for an athlete with a plan keeps the approved plan as evidence');

-- Without a plan ---------------------------------------------------------------------------
select is((select result->'context'->'plan_status'->>'has_active_plan' from calls where label = 'n1'),
  'false', 'an athlete without a plan can chat, and the context says there is none');
select is((select result->'context'->'plan_status'->>'reason' from calls where label = 'n1'),
  'no_approved_plan', 'the reason is that no plan is approved yet');
select is((select result->'context'->'plan_status'->>'screening_outcome' from calls where label = 'n1'),
  null, 'an athlete who was never screened has no screening outcome');
select is((select result->'context'->'active_plan' from calls where label = 'n1'),
  'null'::jsonb, 'the context holds no plan');
select ok(not (select result->'context'->'permitted_evidence' ? 'APPROVED_PLAN_ACTIVE' from calls where label = 'n1'),
  'the approved plan cannot be cited when there is none');
select ok((select result->>'feature_snapshot_id' is not null and result->>'policy_evaluation_id' is not null
  from calls where label = 'n1'), 'the turn still has its snapshot and policy for the usage record');
select is(
  (select features->>'local_date' from public.feature_snapshots
   where user_id = 'a9000000-0000-4000-8000-000000000002' and trigger_kind = 'daily'
   order by created_at desc limit 1),
  (statement_timestamp() at time zone 'Pacific/Pago_Pago')::date::text,
  'the no-plan snapshot is also made for the local date');
select is((select result->'context'->'plan_status'->>'reason' from calls where label = 's1'),
  'see_professional', 'the see-a-professional outcome is the reason');
select is((select result->'context'->'plan_status'->>'screening_outcome' from calls where label = 's1'),
  'see_professional', 'and the screening outcome is in the context');
select ok((select result->'context'->'plan_status'->>'screened_on' is not null from calls where label = 's1'),
  'with its date');
select ok(not (select result->'context'->'permitted_evidence' ? 'APPROVED_PLAN_ACTIVE' from calls where label = 'n7'),
  'v7 drops the approved plan from permitted evidence when there is none');
select is((select result->'context'->>'schema_version' from calls where label = 'n8'), '8.0',
  'the frozen v8 builds its full context for an athlete without a plan');
select is((select result->'context'->'plan_status'->>'has_active_plan' from calls where label = 'n8'),
  'false', 'and it carries the plan status through');
select ok(not (select result->'context'->'permitted_evidence' ? 'APPROVED_PLAN_ACTIVE' from calls where label = 'n8'),
  'and does not permit the approved plan as evidence');

-- The daily decision still needs an approved plan -----------------------------------------
set local role service_role;
select throws_ok(
  $$select public.prepare_daily_coaching('a9000000-0000-4000-8000-000000000002',
    current_date, 'Pacific/Pago_Pago', gen_random_uuid())$$,
  '22023', 'approved plan required', 'the daily decision still refuses an athlete without a plan');
reset role;

-- One budget gate --------------------------------------------------------------------------
-- Athlete 4 has USD 6.20 of spend and 31 requests today: past the old literals (USD 5, 30 a
-- day) and past the USD 3 stop. Preparing the context no longer refuses; the reservation does.
insert into public.ai_usage_events(user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
select 'a9000000-0000-4000-8000-000000000004', 'progress_vision', 'anthropic',
  'claude-sonnet-5-5', 1, 1, 0.20, 1
from generate_series(1, 31);

set local role service_role;
insert into calls select 'b1', public.prepare_coach_chat(
  'a9000000-0000-4000-8000-000000000004', 'a9400000-0000-4000-8000-000000000004',
  'Hello', 'UTC', gen_random_uuid());
select throws_ok(
  $$select public.reserve_ai_budget_v2('a9000000-0000-4000-8000-000000000004', 'coach_chat', 0.02)$$,
  'P0001', 'monthly cost limit reached', 'the reservation is what refuses an athlete over the stop');
reset role;
select ok((select result->'context' is not null from calls where label = 'b1'),
  'preparing the chat context has no spending literals of its own');
select is((select result->>'budget_warning' from calls where label = 'p1'), 'false',
  'an athlete with no spend gets no budget warning');
select is((select result->>'budget_warning' from calls where label = 'b1'), 'true',
  'an athlete past 80% of the stop gets the warning');

-- The warning follows the limits row, at 80% of the stop, in the chat context and in the
-- athlete's budget state alike. Athlete 4 has USD 6.20: 80% of an USD 8 stop is 6.40 (half would
-- be 4.00), 80% of an USD 7 stop is 5.60.
update private.ai_budget_limits set per_person_monthly_usd = 8;
set local role service_role;
insert into calls select 'b2', public.prepare_coach_chat(
  'a9000000-0000-4000-8000-000000000004', 'a9400000-0000-4000-8000-000000000004',
  'Hello again', 'UTC', gen_random_uuid());
reset role;
select is((select result->>'budget_warning' from calls where label = 'b2'), 'false',
  'USD 6.20 is below 80% of an USD 8 stop, so there is no warning');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a9000000-0000-4000-8000-000000000004';
select is((public.get_my_ai_budget_state()->>'warning_threshold_usd')::numeric, 6.4::numeric,
  'the budget state puts the warning at 80% of the stop');
select is((public.get_my_ai_budget_state()->>'warning')::boolean, false,
  'and agrees that USD 6.20 is not yet a warning');
reset role;

update private.ai_budget_limits set per_person_monthly_usd = 7;
set local role service_role;
insert into calls select 'b3', public.prepare_coach_chat(
  'a9000000-0000-4000-8000-000000000004', 'a9400000-0000-4000-8000-000000000004',
  'Hello a third time', 'UTC', gen_random_uuid());
reset role;
select is((select result->>'budget_warning' from calls where label = 'b3'), 'true',
  'USD 6.20 is past 80% of an USD 7 stop, so the chat warns');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a9000000-0000-4000-8000-000000000004';
select is((public.get_my_ai_budget_state()->>'warning')::boolean, true,
  'and the budget state agrees');
reset role;

select * from finish();
rollback;
