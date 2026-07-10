begin;
select plan(12);

insert into auth.users(id, role) values
  ('85555555-eeee-4555-8555-555555555555', 'authenticated'),
  ('86666666-eeee-4666-8666-666666666666', 'authenticated');

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class
   where oid = 'public.deletion_requests'::regclass),
  'deletion requests enable and force RLS'
);
select ok(not has_table_privilege('authenticated', 'public.deletion_requests', 'insert'),
  'client cannot insert deletion requests directly');
select ok(has_function_privilege('authenticated',
  'public.request_my_account_deletion(text)', 'execute'),
  'authenticated owner can request deletion');
select ok(not has_function_privilege('authenticated',
  'public.claim_account_deletion(uuid)', 'execute'),
  'client cannot claim deletion work');

set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', '85555555-eeee-4555-8555-555555555555',
  'role', 'authenticated', 'iat', extract(epoch from now())::bigint
)::text, true);
select throws_ok(
  $$select public.request_my_account_deletion('delete')$$,
  '22023', 'invalid confirmation', 'confirmation is exact and case sensitive'
);
select lives_ok(
  $$select public.request_my_account_deletion('DELETE')$$,
  'recently authenticated owner can queue deletion'
);
select is((select count(*) from public.deletion_requests), 1::bigint,
  'owner sees the pending deletion state');

select set_config('request.jwt.claims', json_build_object(
  'sub', '86666666-eeee-4666-8666-666666666666',
  'role', 'authenticated', 'iat', extract(epoch from now())::bigint
)::text, true);
select is((select count(*) from public.deletion_requests), 0::bigint,
  'cross-user deletion state is hidden');
select set_config('request.jwt.claims', json_build_object(
  'sub', '86666666-eeee-4666-8666-666666666666',
  'role', 'authenticated',
  'iat', extract(epoch from now() - interval '11 minutes')::bigint
)::text, true);
select throws_ok(
  $$select public.request_my_account_deletion('DELETE')$$,
  '42501', 'recent authentication required',
  'stale authentication cannot request deletion'
);

reset role;
select is(
  public.claim_account_deletion((select id from public.deletion_requests)),
  '85555555-eeee-4555-8555-555555555555'::uuid,
  'service claim returns the canonical owner'
);
select is((select count(*) from pgmq.q_account_deletions), 0::bigint,
  'claim removes the queue message');
select lives_ok(
  $$select public.complete_account_deletion(
    (select id from public.deletion_requests), true
  )$$,
  'service records a minimal completion receipt'
);

select * from finish();
rollback;
