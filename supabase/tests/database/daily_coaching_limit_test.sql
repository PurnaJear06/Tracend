begin;

select plan(3);

insert into auth.users (id, role)
values ('d8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8', 'authenticated');

insert into public.feature_snapshots (
  id, user_id, trigger_kind, schema_version, feature_engine_version, features, data_hash)
values ('e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9', 'd8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8',
  'daily', '2.0', 'daily-v2', '{}'::jsonb, 'limit-test-snapshot-hash');

insert into public.policy_evaluations (
  id, user_id, feature_snapshot_id, policy_version, outcome)
values ('f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0', 'd8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8',
  'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9', 'daily-v1', 'maintain_only');

-- Twelve deterministic decisions today: no AI provider was called.
insert into public.model_runs (
  user_id, feature_snapshot_id, policy_evaluation_id, idempotency_key, purpose,
  provider, model, prompt_version, schema_version, status, validation_status, latency_ms)
select 'd8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8', 'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9',
  'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0', gen_random_uuid(), 'daily_coaching',
  'mock', 'deterministic-mock-v2', 'daily-v1', '1.0', 'succeeded', 'passed', 5
from generate_series(1, 12);

-- Past the limit, preparation continues to the next check: no approved plan.
select throws_ok(
  $$select public.prepare_daily_coaching('d8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8',
    current_date, 'Asia/Kolkata', gen_random_uuid())$$,
  '22023',
  'approved plan required',
  'deterministic runs do not count toward the daily limit'
);

insert into public.model_runs (
  user_id, feature_snapshot_id, policy_evaluation_id, idempotency_key, purpose,
  provider, model, prompt_version, schema_version, status, validation_status, latency_ms)
select 'd8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8', 'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9',
  'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0', gen_random_uuid(), 'daily_coaching',
  'deepseek', 'deepseek-flash', 'daily-v1', '1.0', 'succeeded', 'passed', 900
from generate_series(1, 29);

select throws_ok(
  $$select public.prepare_daily_coaching('d8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8',
    current_date, 'Asia/Kolkata', gen_random_uuid())$$,
  '22023',
  'approved plan required',
  '29 AI calls today stay within the limit'
);

insert into public.model_runs (
  user_id, feature_snapshot_id, policy_evaluation_id, idempotency_key, purpose,
  provider, model, prompt_version, schema_version, status, validation_status, latency_ms)
values ('d8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8', 'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9',
  'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0', gen_random_uuid(), 'daily_coaching',
  'deepseek', 'deepseek-flash', 'daily-v1', '1.0', 'succeeded', 'passed', 900);

select throws_ok(
  $$select public.prepare_daily_coaching('d8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8',
    current_date, 'Asia/Kolkata', gen_random_uuid())$$,
  'P0001',
  'daily rate limit reached',
  'the 31st AI call of the day is refused'
);

select * from finish();
rollback;
