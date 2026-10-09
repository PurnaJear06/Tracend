begin;
select plan(20);

-- Invite-only sign-ups -----------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'private.signup_invites', 'select'),
  'clients cannot read the invite list');
select ok(not has_table_privilege('service_role', 'private.signup_invites', 'select'),
  'the service role cannot read the invite list');

select throws_ok($$insert into auth.users(id, role, email)
  values ('b1000000-0000-4000-8000-000000000009', 'authenticated', 'stranger@example.test')$$,
  '42501', 'signup is invite-only', 'an uninvited email cannot sign up');
select is((select count(*) from auth.users where email = 'stranger@example.test'), 0::bigint,
  'a refused sign-up leaves no user');
select throws_ok($$insert into auth.users(id, role, phone)
  values ('b1000000-0000-4000-8000-000000000008', 'authenticated', '15550000000')$$,
  '42501', 'signup is invite-only', 'a phone sign-up is refused');

insert into private.signup_invites(email, note) values ('athlete@example.test', 'beta');
select lives_ok($$insert into auth.users(id, role, email)
  values ('b1000000-0000-4000-8000-000000000001', 'authenticated', 'Athlete@Example.test ')$$,
  'an invited email signs up whatever its case');
select is((select claimed_by from private.signup_invites where email = 'athlete@example.test'),
  'b1000000-0000-4000-8000-000000000001'::uuid, 'the invite records who claimed it');
select ok(exists(select 1 from public.user_accounts where id = 'b1000000-0000-4000-8000-000000000001'),
  'an invited sign-up gets its account row');
select lives_ok($$insert into auth.users(id, role)
  values ('b1000000-0000-4000-8000-000000000002', 'authenticated')$$,
  'a row with no email, phone or anonymous flag (direct SQL) is not gated');

-- Recent sign-in -----------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', 'b1000000-0000-4000-8000-000000000001', 'role', 'authenticated',
  'iat', extract(epoch from now())::bigint,
  'amr', json_build_array(json_build_object('method', 'password',
    'timestamp', extract(epoch from now() - interval '2 hours')::bigint))
)::text, true);
select throws_ok($$select public.request_my_data_export()$$, '42501',
  'recent authentication required', 'a refreshed token with an old sign-in is refused');

select set_config('request.jwt.claims', json_build_object(
  'sub', 'b1000000-0000-4000-8000-000000000001', 'role', 'authenticated',
  'iat', extract(epoch from now())::bigint)::text, true);
select throws_ok($$select public.request_my_data_export()$$, '42501',
  'recent authentication required', 'a token with no amr is refused');

select set_config('request.jwt.claims', json_build_object(
  'sub', 'b1000000-0000-4000-8000-000000000001', 'role', 'authenticated',
  'iat', extract(epoch from now())::bigint, 'amr', 'password')::text, true);
select throws_ok($$select public.request_my_data_export()$$, '42501',
  'recent authentication required', 'a malformed amr is refused');

select set_config('request.jwt.claims', json_build_object(
  'sub', 'b1000000-0000-4000-8000-000000000001', 'role', 'authenticated',
  'iat', extract(epoch from now())::bigint,
  'amr', json_build_array(json_build_object('method', 'oauth',
    'timestamp', extract(epoch from now())::bigint))
)::text, true);
select throws_ok($$select public.request_my_account_deletion('DELETE')$$, '42501',
  'recent authentication required', 'a sign-in method other than a password is refused');

select set_config('request.jwt.claims', json_build_object(
  'sub', 'b1000000-0000-4000-8000-000000000001', 'role', 'authenticated',
  'iat', extract(epoch from now() - interval '2 hours')::bigint,
  'amr', json_build_array(json_build_object('method', 'totp',
    'timestamp', extract(epoch from now())::bigint))
)::text, true);
select lives_ok($$select public.request_my_account_deletion('DELETE')$$,
  'a fresh sign-in is accepted');

-- No export while a deletion is pending -------------------------------------------------
select throws_ok($$select public.request_my_data_export()$$, '55000',
  'account deletion pending', 'an export cannot start while deletion is pending');
reset role;
insert into public.data_exports(id, user_id, status)
values ('b1300000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'processing');
set local role service_role;
select throws_ok($$select public.complete_data_export('b1300000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001/b1300000-0000-4000-8000-000000000001.tracendexport', 10)$$,
  '55000', 'account deletion pending', 'an export cannot complete while deletion is pending');
reset role;

-- Account Storage listing ---------------------------------------------------------------
insert into storage.objects(bucket_id, name, owner_id) values
  ('meal-images', 'b1000000-0000-4000-8000-000000000001/meal/orphan.jpg',
   'b1000000-0000-4000-8000-000000000001'),
  ('meal-images', 'b1000000-0000-4000-8000-000000000002/meal/other.jpg',
   'b1000000-0000-4000-8000-000000000002');
select is((select array_agg(name) from public.list_account_storage_objects(
  'b1000000-0000-4000-8000-000000000001')),
  array['b1000000-0000-4000-8000-000000000001/meal/orphan.jpg'],
  'deletion lists every object in the user''s folders and nothing else');
select ok(not has_function_privilege('authenticated',
  'public.list_account_storage_objects(uuid)', 'execute'), 'clients cannot list Storage for an account');

-- Deleting a Coach conversation ---------------------------------------------------------
insert into public.coach_threads(id, user_id, title)
values ('b1400000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002', 'Plan');
insert into public.coach_context_snapshots(user_id, thread_id, schema_version, trigger_kind,
  coaching_date, context, context_checksum)
values ('b1000000-0000-4000-8000-000000000002', 'b1400000-0000-4000-8000-000000000001', '2.0',
  'chat', current_date, '{}', repeat('a', 64));
insert into public.coach_session_summaries(user_id, coaching_date, summary, thread_id)
values ('b1000000-0000-4000-8000-000000000002', current_date, 'Talked about squats.',
  'b1400000-0000-4000-8000-000000000001');
set local role authenticated;
set local "request.jwt.claim.sub" = 'b1000000-0000-4000-8000-000000000002';
select lives_ok($$select public.delete_coach_thread('b1400000-0000-4000-8000-000000000001')$$,
  'a conversation with a context snapshot and a summary deletes');
reset role;
select is((select count(*) from public.coach_context_snapshots
  where thread_id = 'b1400000-0000-4000-8000-000000000001')
  + (select count(*) from public.coach_session_summaries
  where thread_id = 'b1400000-0000-4000-8000-000000000001'), 0::bigint,
  'the conversation''s snapshots and summaries go with it');

select * from finish();
rollback;
