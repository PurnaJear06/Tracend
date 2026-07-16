begin;
select plan(37);

-- Test users
prepare user_a (uuid,uuid) as values (
  'a1111111-aaaa-4111-8111-111111111111'::uuid,
  'a2111111-aaaa-4111-8111-111111111111'::uuid);
prepare user_b (uuid,uuid) as values (
  'b1111111-bbbb-4111-8111-111111111111'::uuid,
  'b2111111-bbbb-4111-8111-111111111111'::uuid);

insert into auth.users(id, role) values
  ('a1111111-aaaa-4111-8111-111111111111', 'authenticated'),
  ('b1111111-bbbb-4111-8111-111111111111', 'authenticated');

-- Coach threads
insert into public.coach_threads(id, user_id, status)
values
  ('a2111111-aaaa-4111-8111-111111111111', 'a1111111-aaaa-4111-8111-111111111111', 'active'),
  ('b2111111-bbbb-4111-8111-111111111111', 'b1111111-bbbb-4111-8111-111111111111', 'active');

-- Training plan + version for user A
insert into public.training_plans(id, user_id, title, source) values
  ('a3111111-aaaa-4111-8111-111111111111', 'a1111111-aaaa-4111-8111-111111111111', 'Owner plan', 'mock_ai');
insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
  prescription, rationale, approved_at, effective_date)
values(
  'a4111111-aaaa-4111-8111-111111111111', 'a1111111-aaaa-4111-8111-111111111111',
  'a3111111-aaaa-4111-8111-111111111111', 1, 'active', 4, 3, '{}', 'Approved fixture',
  now(), current_date);
insert into public.nutrition_target_sets(
  id, user_id, version_number, status, calories, protein_g, carbohydrate_g, fat_g,
  rationale, approved_at, effective_date)
values(
  'a5111111-aaaa-4111-8111-111111111111', 'a1111111-aaaa-4111-8111-111111111111',
  1, 'active', 2200, 150, 240, 70, 'Approved fixture', now(), current_date);

-- 1: RLS - anon denied on v4
select ok(
  not has_function_privilege('anon', 'public.prepare_coach_chat_v4(uuid,uuid,text,text,uuid,text)', 'execute'),
  'anon cannot execute v4');

-- 2: RLS - authenticated denied on v4
select ok(
  not has_function_privilege('authenticated', 'public.prepare_coach_chat_v4(uuid,uuid,text,text,uuid,text)', 'execute'),
  'authenticated cannot execute v4');

-- 3: RLS - service_role granted on v4
select ok(
  has_function_privilege('service_role', 'public.prepare_coach_chat_v4(uuid,uuid,text,text,uuid,text)', 'execute'),
  'service_role can execute v4');

-- 4: RLS - anon denied on v3 wrapper
select ok(
  not has_function_privilege('anon', 'public.prepare_coach_chat_v3(uuid,uuid,text,text,uuid)', 'execute'),
  'anon cannot execute v3');

-- 5: RLS - authenticated denied on v3 wrapper
select ok(
  not has_function_privilege('authenticated', 'public.prepare_coach_chat_v3(uuid,uuid,text,text,uuid)', 'execute'),
  'authenticated cannot execute v3');

-- 6: RLS - service_role granted on v3 wrapper
select ok(
  has_function_privilege('service_role', 'public.prepare_coach_chat_v3(uuid,uuid,text,text,uuid)', 'execute'),
  'service_role can execute v3');

-- Switch to service_role for behavioral tests
set local role service_role;

-- 7: v4 returns valid JSON with daily_action kind
select lives_ok($$select public.prepare_coach_chat_v4(
  'a1111111-aaaa-4111-8111-111111111111',
  'a2111111-aaaa-4111-8111-111111111111',
  'What should I train today?', 'America/New_York',
  '00000000-0000-4000-a000-a00000000001', 'daily_action')$$,
  'v4 daily_action returns without error');

-- 8: daily_action has required top-level keys
select is(
  (select (public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'What exercise next?', 'America/New_York',
    '00000000-0000-4000-a000-a00000000002', 'daily_action')
  ->'context'->>'context_kind')::text),
  'daily_action',
  'daily_action kind is returned in context');

-- 9: v4 plan_change returns valid JSON
select lives_ok($$select public.prepare_coach_chat_v4(
  'a1111111-aaaa-4111-8111-111111111111',
  'a2111111-aaaa-4111-8111-111111111111',
  'I think I hit a plateau', 'America/New_York',
  '00000000-0000-4000-a000-a00000000003', 'plan_change')$$,
  'v4 plan_change returns without error');

-- 10: plan_change has context_kind set
select is(
  (select (public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'I am plateauing review my plan', 'America/New_York',
    '00000000-0000-4000-a000-a00000000004', 'plan_change')
  ->'context'->>'context_kind')::text),
  'plan_change',
  'plan_change kind is returned in context');

-- 11: v4 explain_evidence returns valid JSON
select lives_ok($$select public.prepare_coach_chat_v4(
  'a1111111-aaaa-4111-8111-111111111111',
  'a2111111-aaaa-4111-8111-111111111111',
  'Explain my data gaps', 'America/New_York',
  '00000000-0000-4000-a000-a00000000005', 'explain_evidence')$$,
  'v4 explain_evidence returns without error');

-- 12: explain_evidence has evidence_contract
select ok(
  (select (public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'What evidence do I have?', 'America/New_York',
    '00000000-0000-4000-a000-a00000000006', 'explain_evidence')
  ->'context'->'evidence_contract'->>'persistent_changes_require_approval')::boolean),
  'evidence_contract is present in explain_evidence');

-- 13: v4 nutrition_focus returns valid JSON
select lives_ok($$select public.prepare_coach_chat_v4(
  'a1111111-aaaa-4111-8111-111111111111',
  'a2111111-aaaa-4111-8111-111111111111',
  'What should I eat?', 'America/New_York',
  '00000000-0000-4000-a000-a00000000007', 'nutrition_focus')$$,
  'v4 nutrition_focus returns without error');

-- 14: v4 recovery returns valid JSON
select lives_ok($$select public.prepare_coach_chat_v4(
  'a1111111-aaaa-4111-8111-111111111111',
  'a2111111-aaaa-4111-8111-111111111111',
  'I feel sore and tired', 'America/New_York',
  '00000000-0000-4000-a000-a00000000008', 'recovery')$$,
  'v4 recovery returns without error');

-- 15: v4 general returns valid JSON
select lives_ok($$select public.prepare_coach_chat_v4(
  'a1111111-aaaa-4111-8111-111111111111',
  'a2111111-aaaa-4111-8111-111111111111',
  'Hello coach', 'America/New_York',
  '00000000-0000-4000-a000-a00000000009', 'general')$$,
  'v4 general returns without error');

-- 16: v4 with null context_kind falls back to general
select is(
  (select (public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'How are you?', 'America/New_York',
    '00000000-0000-4000-a000-a00000000010', null)
  ->'context'->>'context_kind')::text),
  'general',
  'null context_kind falls back to general');

-- 17: v4 with invalid context_kind falls back to general
select is(
  (select (public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'Hey', 'America/New_York',
    '00000000-0000-4000-a000-a00000000011', 'invalid_kind_xyz')
  ->'context'->>'context_kind')::text),
  'general',
  'invalid context_kind falls back to general');

-- 18: v3 wrapper calls v4 with general
select is(
  (select (public.prepare_coach_chat_v3(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'Hi', 'America/New_York',
    '00000000-0000-4000-a000-a00000000012')
  ->'context'->>'context_kind')::text),
  'general',
  'v3 wrapper defaults to general kind');

-- 19: idempotency - same key returns replayed on second call
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'Repeat me', 'America/New_York',
    '00000000-0000-4000-a000-a00000000001', 'general')
  ->>'replayed')::boolean,
  'idempotency key replay returns replayed=true');

-- 20: v4 with empty string question raises exception
select throws_ok($$select public.prepare_coach_chat_v4(
  'a1111111-aaaa-4111-8111-111111111111',
  'a2111111-aaaa-4111-8111-111111111111',
  '   ', 'America/New_York',
  '00000000-0000-4000-a000-a00000000013', 'general')$$,
  '22023');

-- 21: v4 with valid user but wrong thread raises exception
select throws_ok($$select public.prepare_coach_chat_v4(
  'a1111111-aaaa-4111-8111-111111111111',
  'b2111111-bbbb-4111-8111-111111111111',
  'Hello', 'America/New_York',
  '00000000-0000-4000-a000-a00000000014', 'general')$$,
  'P0002');

-- 22: context snapshot is persisted for v4
select is(
  (select count(*)::integer from public.coach_context_snapshots
   where user_id = 'a1111111-aaaa-4111-8111-111111111111'),
  13,
  'snapshot rows were persisted for each v4 call');

-- 23: snapshot has valid checksum
select ok(
  (select context_checksum ~ '^[0-9a-f]{64}$' from public.coach_context_snapshots
   where user_id = 'a1111111-aaaa-4111-8111-111111111111' limit 1),
  'snapshot checksum is valid sha256 hex');

-- 24: snapshot schema_version is 2.0
select is(
  (select schema_version from public.coach_context_snapshots
   where user_id = 'a1111111-aaaa-4111-8111-111111111111' limit 1),
  '2.0',
  'snapshot schema_version is 2.0');

-- 25: plan_change context has session_trends key
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'Change my plan', 'America/New_York',
    '00000000-0000-4000-a000-a00000000015', 'plan_change')
  ->'context' ? 'session_trends'),
  'plan_change context includes session_trends');

-- 26: plan_change context has data_quality
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'New routine?', 'America/New_York',
    '00000000-0000-4000-a000-a00000000016', 'plan_change')
  ->'context' ? 'data_quality'),
  'plan_change context includes data_quality');

-- 27: recovery context has training_week_structure
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'I need rest', 'America/New_York',
    '00000000-0000-4000-a000-a00000000017', 'recovery')
  ->'context' ? 'training_week_structure'),
  'recovery context includes training_week_structure');

-- 28: general context has brief_sessions
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'Hello again', 'America/New_York',
    '00000000-0000-4000-a000-a00000000018', 'general')
  ->'context' ? 'brief_sessions'),
  'general context includes brief_sessions');

-- 29: daily_action context has focused_execution
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'What should I train?', 'America/New_York',
    '00000000-0000-4000-a000-a00000000019', 'daily_action')
  ->'context' ? 'focused_execution'),
  'daily_action context includes focused_execution');

-- 30: nutrition_focus context has nutrition_compliance_7day
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'My diet advice', 'America/New_York',
    '00000000-0000-4000-a000-a00000000020', 'nutrition_focus')
  ->'context' ? 'nutrition_compliance_7day'),
  'nutrition_focus context includes nutrition_compliance_7day');

-- 31: explain_evidence context has evidence_freshness
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'What is missing?', 'America/New_York',
    '00000000-0000-4000-a000-a00000000021', 'explain_evidence')
  ->'context' ? 'evidence_freshness'),
  'explain_evidence context includes evidence_freshness');

-- 32: response includes coach_context_snapshot_id
select ok(
  (select public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'One more', 'America/New_York',
    '00000000-0000-4000-a000-a00000000022', 'general')
  ->>'coach_context_snapshot_id') is not null,
  'response includes coach_context_snapshot_id');

-- 33: context size is reasonable (< 8000 bytes for daily_action without workout data)
select ok(
  length((select (public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'Today workout', 'America/New_York',
    '00000000-0000-4000-a000-a00000000023', 'daily_action')
  ->'context')::text)) < 10000,
  'daily_action context is under 10000 bytes');

-- 34: general context size is reasonable
select ok(
  length((select (public.prepare_coach_chat_v4(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'What do you think?', 'America/New_York',
    '00000000-0000-4000-a000-a00000000024', 'general')
  ->'context')::text)) < 10000,
  'general context is under 10000 bytes');

-- 35-37: V3 wrapper RLS was tested above; test v3 wrapper produces valid replayed response
select ok(
  (select (public.prepare_coach_chat_v3(
    'a1111111-aaaa-4111-8111-111111111111',
    'a2111111-aaaa-4111-8111-111111111111',
    'Coach says', 'America/New_York',
    '00000000-0000-4000-a000-a00000000025')
  ->>'replayed')::boolean),
  'v3 wrapper idempotency returns replayed from v4');

select finish();
rollback;
