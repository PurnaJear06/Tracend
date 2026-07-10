begin;
select plan(14);

insert into auth.users(id, role) values
  ('83333333-eeee-4333-8333-333333333333', 'authenticated'),
  ('84444444-eeee-4444-8444-444444444444', 'authenticated');

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class
   where oid = 'public.data_exports'::regclass),
  'data exports enable and force RLS'
);
select ok(
  not has_table_privilege('authenticated', 'public.data_exports', 'insert'),
  'clients cannot bypass export request validation'
);
select ok(
  has_function_privilege('authenticated', 'public.request_my_data_export()', 'execute'),
  'authenticated owners can request an export'
);
select ok(
  not has_function_privilege('authenticated', 'public.claim_data_export(uuid)', 'execute'),
  'clients cannot claim export jobs'
);
select ok(
  exists(select 1 from storage.buckets where id = 'account-exports' and not public),
  'export Storage bucket is private'
);

set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', '83333333-eeee-4333-8333-333333333333',
  'role', 'authenticated', 'iat', extract(epoch from now())::bigint
)::text, true);
select lives_ok(
  $$select public.request_my_data_export()$$,
  'recently authenticated owner can queue an export'
);
select is((select count(*) from public.data_exports), 1::bigint,
  'owner sees the queued export');
reset role;
select is(
  (select message ->> 'schema_version' from pgmq.q_privacy_exports limit 1),
  '1.0', 'queue payload contains only the version and opaque export ID'
);

set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', '84444444-eeee-4444-8444-444444444444',
  'role', 'authenticated', 'iat', extract(epoch from now())::bigint
)::text, true);
select is((select count(*) from public.data_exports), 0::bigint,
  'cross-user export rows are hidden by RLS');

select set_config('request.jwt.claims', json_build_object(
  'sub', '84444444-eeee-4444-8444-444444444444',
  'role', 'authenticated',
  'iat', extract(epoch from now() - interval '11 minutes')::bigint
)::text, true);
select throws_ok(
  $$select public.request_my_data_export()$$,
  '42501', 'recent authentication required',
  'stale authentication cannot request an export'
);

reset role;
select is(
  public.claim_data_export((select id from public.data_exports)),
  '83333333-eeee-4333-8333-333333333333'::uuid,
  'service claim returns the owning user'
);
select is((select count(*) from pgmq.q_privacy_exports), 0::bigint,
  'claim removes the durable queue message');
select lives_ok(
  $$select public.complete_data_export(
    (select id from public.data_exports),
    '83333333-eeee-4333-8333-333333333333/' ||
      (select id from public.data_exports)::text || '.tracendexport', 1024
  )$$,
  'service can finalize an encrypted package reference'
);
select ok(
  (select status = 'ready' and expires_at <= now() + interval '7 days 1 minute'
    and download_count = 0 from public.data_exports),
  'ready export has bounded expiry and download count'
);

select * from finish();
rollback;
