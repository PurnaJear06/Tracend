begin;

select plan(31);

insert into auth.users (id, role)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'authenticated');

select results_eq(
  $$select id from public.user_accounts where id in (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ) order by id$$,
  $$values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid)$$,
  'auth user creation creates application account roots'
);

select ok(
  (select bool_and(relrowsecurity and relforcerowsecurity)
   from pg_class
   where oid = any(array[
     'public.user_profiles'::regclass,
     'public.consent_records'::regclass,
     'public.onboarding_drafts'::regclass,
     'public.user_goals'::regclass,
     'public.feature_snapshots'::regclass,
     'public.training_plans'::regclass,
     'public.training_plan_versions'::regclass,
     'public.nutrition_target_sets'::regclass,
     'public.change_proposals'::regclass,
     'public.change_responses'::regclass,
     'public.audit_events'::regclass
   ])),
  'every Phase 2 user-owned table enables and forces RLS'
);

select ok(
  not has_table_privilege('anon', 'public.user_profiles', 'select'),
  'anonymous role cannot read profiles'
);
select ok(
  not has_table_privilege('anon', 'public.change_proposals', 'select'),
  'anonymous role cannot read proposals'
);
select ok(
  not has_table_privilege('authenticated', 'public.change_proposals', 'insert'),
  'mobile clients cannot create provider proposals directly'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.respond_to_onboarding_proposal(uuid, public.proposal_response_action)',
    'execute'
  ),
  'authenticated users can invoke the narrow proposal response RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.persist_mock_onboarding_proposal(uuid, text, jsonb, jsonb, jsonb, jsonb, text, text, text)',
    'execute'
  ),
  'mobile clients cannot invoke the service-only mock persistence RPC'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select lives_ok(
  $$insert into public.user_profiles (
    user_id, adult_attested_at, eligible, experience_level,
    training_days, session_minutes
  ) values (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now(), true, 'beginner',
    array[1, 3, 5]::smallint[], 60
  )$$,
  'a user can create their own eligible profile'
);

select throws_ok(
  $$insert into public.user_profiles (user_id, eligible)
    values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', true)$$,
  '42501', null,
  'a user cannot create another user profile'
);

select lives_ok(
  $$insert into public.onboarding_drafts (user_id, path, current_section, payload)
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'beginner', 'goal',
      '{"goal":"strength"}'::jsonb
    )$$,
  'beginner onboarding draft is user-writable'
);

select lives_ok(
  $$update public.onboarding_drafts
    set current_section = 'schedule', payload = payload || '{"days":3}'::jsonb
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'onboarding autosave updates the current section and payload'
);

select is(
  (select row_version from public.onboarding_drafts
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  2,
  'onboarding autosave increments the row version'
);

select lives_ok(
  $$insert into public.consent_records (
    user_id, consent_type, notice_version, action, source
  ) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'terms', '2026-07-01', 'granted', 'owner_development'),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'privacy', '2026-07-01', 'granted', 'owner_development')$$,
  'terms and privacy consent are append-only authenticated writes'
);

select throws_ok(
  $$update public.consent_records set action = 'withdrawn'$$,
  '42501', null,
  'consent history cannot be rewritten by the client'
);

reset role;
set local "request.jwt.claim.sub" = '';

insert into public.onboarding_drafts (user_id, path, current_section, payload)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'experienced', 'current_plan',
  '{"preserve":"compound lifts"}'::jsonb
);

insert into public.feature_snapshots (
  id, user_id, trigger_kind, schema_version, feature_engine_version,
  features, coverage, missing_data, data_hash
) values
  (
    '10000000-0000-4000-8000-000000000001',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'onboarding', '1.0', 'onboarding-v1',
    '{"path":"beginner","goal":"strength"}', '{"required":1}', '{}',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'onboarding', '1.0', 'onboarding-v1',
    '{"path":"experienced","preserve":true}', '{"required":1}', '{}',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  );

insert into public.change_proposals (
  id, user_id, feature_snapshot_id, schema_version,
  proposed_training, proposed_nutrition, evidence, rationale,
  expected_benefit, downside, confidence, effective_date, expires_at
) values
  (
    '30000000-0000-4000-8000-000000000003',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '10000000-0000-4000-8000-000000000001', '1.0',
    '{"title":"Foundation Strength","block_weeks":6,"sessions_per_week":3,"weekly_structure":["Full body A","Full body B","Full body C"],"prescription":{"focus":"compound patterns"}}',
    '{"calories":2300,"protein_g":160,"carbohydrate_g":250,"fat_g":70}',
    '[{"code":"ONBOARDING_COMPLETE","source":"feature_snapshot"}]',
    'Build a stable baseline before progression.',
    'A repeatable three-day structure.', 'Initial estimates require review.',
    'medium', current_date, now() + interval '7 days'
  ),
  (
    '40000000-0000-4000-8000-000000000004',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '20000000-0000-4000-8000-000000000002', '1.0',
    '{"title":"Preserved Upper Lower","block_weeks":8,"sessions_per_week":4,"weekly_structure":["Upper A","Lower A","Upper B","Lower B"],"prescription":{"preserved":["squat","bench"]}}',
    '{"calories":2500,"protein_g":170,"carbohydrate_g":290,"fat_g":75}',
    '[{"code":"CURRENT_PLAN_REVIEWED","source":"feature_snapshot"}]',
    'Preserve effective work and close schedule gaps.',
    'Lower transition cost.', 'Unknown recent adherence.',
    'medium', current_date, now() + interval '7 days'
  );

select throws_ok(
  $$insert into public.change_proposals (
      user_id, feature_snapshot_id, schema_version,
      proposed_training, proposed_nutrition, evidence, rationale,
      expected_benefit, downside, confidence, effective_date, expires_at
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '10000000-0000-4000-8000-000000000001', '1.0',
      '{"title":"Invalid","block_weeks":0}',
      '{"calories":10}', '[]', 'Invalid provider output.',
      'None.', 'Unsafe.', 'low', current_date, now() + interval '1 day'
    )$$,
  '23514', null,
  'invalid mocked provider output cannot be persisted for activation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select results_eq(
  'select id from public.change_proposals order by id',
  $$values ('30000000-0000-4000-8000-000000000003'::uuid)$$,
  'a user sees only their proposal'
);

select throws_ok(
  $$select public.respond_to_onboarding_proposal(
    '40000000-0000-4000-8000-000000000004', 'accept'
  )$$,
  'P0002', null,
  'a cross-user proposal cannot be resolved'
);

select lives_ok(
  $$select public.respond_to_onboarding_proposal(
    '30000000-0000-4000-8000-000000000003', 'accept'
  )$$,
  'the owner can accept a current valid proposal transactionally'
);

select is(
  (select count(*) from public.training_plan_versions where status = 'active'),
  1::bigint,
  'acceptance creates exactly one active training version'
);

select is(
  (select count(*) from public.nutrition_target_sets where status = 'active'),
  1::bigint,
  'acceptance creates exactly one active nutrition target set'
);

select is(
  (select status::text from public.change_proposals
   where id = '30000000-0000-4000-8000-000000000003'),
  'accepted',
  'accepted proposal is no longer pending'
);

select is(
  (select onboarding_state::text from public.user_accounts
   where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'completed',
  'acceptance marks onboarding complete'
);

select is(
  (select count(*) from public.change_responses
   where proposal_id = '30000000-0000-4000-8000-000000000003'),
  1::bigint,
  'acceptance records one immutable response'
);

select is(
  (select count(*) from public.audit_events
   where target_id = '30000000-0000-4000-8000-000000000003'),
  1::bigint,
  'acceptance records one sanitized audit event'
);

select throws_ok(
  $$select public.respond_to_onboarding_proposal(
    '30000000-0000-4000-8000-000000000003', 'accept'
  )$$,
  '55000', null,
  'replaying an accepted proposal cannot create another version'
);

set local "request.jwt.claim.sub" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select lives_ok(
  $$select public.respond_to_onboarding_proposal(
    '40000000-0000-4000-8000-000000000004', 'accept'
  )$$,
  'the experienced user can independently approve their proposal'
);

select is(
  (select count(*) from public.training_plan_versions where status = 'active'),
  1::bigint,
  'the experienced user sees exactly one active training version'
);

select is(
  (select count(*) from public.nutrition_target_sets where status = 'active'),
  1::bigint,
  'the experienced user sees exactly one active nutrition target set'
);

select is(
  (select onboarding_state::text from public.user_accounts
   where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'completed',
  'the experienced onboarding path completes independently'
);

reset role;
set local "request.jwt.claim.sub" = '';

select is(
  (select path::text from public.onboarding_drafts
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'beginner',
  'beginner branch draft remains identified'
);

select is(
  (select path::text from public.onboarding_drafts
   where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'experienced',
  'experienced branch draft remains identified'
);

select * from finish();
rollback;
