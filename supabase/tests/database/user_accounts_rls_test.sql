begin;

select plan(8);

insert into auth.users (id, role)
values
  ('11111111-1111-4111-8111-111111111111', 'authenticated'),
  ('22222222-2222-4222-8222-222222222222', 'authenticated'),
  ('33333333-3333-4333-8333-333333333333', 'authenticated');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_accounts'::regclass),
  'user_accounts has RLS enabled'
);

select ok(
  (select relforcerowsecurity from pg_class where oid = 'public.user_accounts'::regclass),
  'user_accounts forces RLS'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select results_eq(
  'select id from public.user_accounts order by id',
  $$values ('11111111-1111-4111-8111-111111111111'::uuid)$$,
  'an authenticated user reads only their account'
);

select lives_ok(
  $$update public.user_accounts set timezone = 'Asia/Kolkata' where id = '11111111-1111-4111-8111-111111111111'$$,
  'an authenticated user can update their account'
);

select is(
  (select timezone from public.user_accounts where id = '11111111-1111-4111-8111-111111111111'),
  'Asia/Kolkata',
  'the own-account update persists'
);

select is(
  (select row_version from public.user_accounts where id = '11111111-1111-4111-8111-111111111111'),
  2,
  'an update increments row_version'
);

select is_empty(
  $$update public.user_accounts set timezone = 'UTC' where id = '22222222-2222-4222-8222-222222222222' returning id$$,
  'a cross-user update changes no row'
);

select throws_ok(
  $$insert into public.user_accounts (id) values ('33333333-3333-4333-8333-333333333333')$$,
  '42501',
  null,
  'a user cannot insert an account for another identity'
);

select * from finish();
rollback;
