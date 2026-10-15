begin;
select plan(25);

create function pg_temp.signup(addr text, referrer text default null)
returns void language sql as $$
  insert into private.waitlist_signups(email, status, confirmed_at, unsub_token_hash,
    referral_code, referred_by, consent_version)
  values (addr, 'confirmed', now(), encode(sha256(convert_to('u-' || addr, 'UTF8')), 'hex'),
    private.waitlist_referral_code(),
    (select s.id from private.waitlist_signups s where s.email = referrer),
    'waitlist-2026-10-13')
$$;

-- Access is unchanged --------------------------------------------------------------------
select is((select count(*) from pg_class c, aclexplode(c.relacl) grant_row
  where c.oid in ('private.signup_invites'::regclass, 'private.waitlist_signups'::regclass)
    and grant_row.grantee in (0, 'anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole)),
  0::bigint,
  'no API role has any privilege on the invite list or the waitlist');
select ok(not has_function_privilege('service_role', 'private.forget_account_invite(uuid, text)', 'execute')
  and not has_function_privilege('authenticated', 'private.forget_account_invite(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'private.forget_account_invite(uuid, text)', 'execute'),
  'no API role can remove invites');
select ok(not has_function_privilege('service_role', 'private.handle_deleted_auth_user()', 'execute')
  and not has_function_privilege('authenticated', 'private.handle_deleted_auth_user()', 'execute'),
  'no API role can call the deletion trigger');
select ok(not has_function_privilege('service_role', 'private.forget_deleted_account_invites()', 'execute')
  and not has_function_privilege('authenticated', 'private.forget_deleted_account_invites()', 'execute'),
  'the cleanup of earlier deletions is for the owner only');
select has_trigger('auth', 'users', 'auth_user_forget_invite', 'deleting an Auth user runs the trigger');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
  where oid = 'public.deletion_requests'::regclass), 'deletion requests still force RLS');

-- Setup ----------------------------------------------------------------------------------
insert into private.signup_invites(email, note) values
  ('gone@example.test', 'waitlist'),
  ('stay@example.test', 'waitlist'),
  ('later@example.test', 'waitlist'),
  ('mover@example.test', 'beta'),
  ('moved@example.test', 'beta');
select pg_temp.signup('gone@example.test');
select pg_temp.signup('friend@example.test', 'gone@example.test');
select pg_temp.signup('stay@example.test');
select pg_temp.signup('later@example.test');
select pg_temp.signup('moved@example.test');
insert into auth.users(id, role, email) values
  ('d1000000-0000-4000-8000-000000000001', 'authenticated', 'Gone@Example.test '),
  ('d1000000-0000-4000-8000-000000000002', 'authenticated', 'stay@example.test'),
  ('d1000000-0000-4000-8000-000000000003', 'authenticated', 'mover@example.test');
update auth.users set email = 'moved@example.test' where id = 'd1000000-0000-4000-8000-000000000003';

select is((select claimed_by from private.signup_invites where email = 'gone@example.test'),
  'd1000000-0000-4000-8000-000000000001'::uuid, 'the invite names the account that claimed it');

create temp table others_invites on commit drop as
select i::text as row_text from private.signup_invites i
where i.email in ('stay@example.test', 'later@example.test');
create temp table others_signups on commit drop as
select s::text as row_text from private.waitlist_signups s
where s.email in ('stay@example.test', 'later@example.test');

-- The deletion flow ----------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', 'd1000000-0000-4000-8000-000000000001', 'role', 'authenticated',
  'iat', extract(epoch from now())::bigint,
  'amr', json_build_array(json_build_object('method', 'password',
    'timestamp', extract(epoch from now())::bigint))
)::text, true);
select set_config('test.request_id', public.request_my_account_deletion('DELETE')::text, true);
reset role;
set local role service_role;
select is(public.claim_account_deletion(current_setting('test.request_id')::uuid),
  'd1000000-0000-4000-8000-000000000001'::uuid, 'the deletion is claimed');
reset role;
-- privacy-delete-account then calls auth.admin.deleteUser, which deletes the Auth row.
select lives_ok($$delete from auth.users where id = 'd1000000-0000-4000-8000-000000000001'$$,
  'the Auth user is deleted');
set local role service_role;
select public.complete_account_deletion(current_setting('test.request_id')::uuid, true);
reset role;

select is((select status from public.deletion_requests where id = current_setting('test.request_id')::uuid),
  'completed', 'the deletion completes');
select ok(not exists(select 1 from private.signup_invites where email = 'gone@example.test'),
  'the deleted account''s invite is removed');
select ok(not exists(select 1 from private.signup_invites
  where claimed_by = 'd1000000-0000-4000-8000-000000000001'),
  'no invite names the deleted account');
select ok(not exists(select 1 from private.waitlist_signups where email = 'gone@example.test'),
  'the deleted account''s waitlist signup is removed');
select is((select referred_by from private.waitlist_signups where email = 'friend@example.test'),
  null::bigint, 'a signup they referred stays, without the link to them');
select results_eq($$select i::text from private.signup_invites i
  where i.email in ('stay@example.test', 'later@example.test') order by 1$$,
  $$select row_text from others_invites order by 1$$, 'other people''s invites are untouched');
select results_eq($$select s::text from private.waitlist_signups s
  where s.email in ('stay@example.test', 'later@example.test') order by 1$$,
  $$select row_text from others_signups order by 1$$, 'other people''s waitlist signups are untouched');
select throws_ok($$insert into auth.users(id, role, email)
  values ('d1000000-0000-4000-8000-000000000004', 'authenticated', 'gone@example.test')$$,
  '42501', 'signup is invite-only', 'coming back needs a new invite');

-- An account whose email changed after it signed up ---------------------------------------
delete from auth.users where id = 'd1000000-0000-4000-8000-000000000003';
select ok(not exists(select 1 from private.signup_invites
  where email in ('mover@example.test', 'moved@example.test')),
  'the claimed invite and an unclaimed invite for the current email are both removed');
select ok(not exists(select 1 from private.waitlist_signups where email = 'moved@example.test'),
  'and the current email''s waitlist signup');

-- Accounts deleted before this change ------------------------------------------------------
insert into private.signup_invites(email, note, claimed_at, claimed_by) values
  ('orphan@example.test', 'beta', now(), 'd1000000-0000-4000-8000-000000000099'),
  ('back@example.test', 'beta', now(), 'd1000000-0000-4000-8000-000000000098');
select pg_temp.signup('orphan@example.test');
select pg_temp.signup('back@example.test');
-- Signed up again after an earlier deletion: the insert trigger kept the old claimer.
insert into auth.users(id, role, email)
values ('d1000000-0000-4000-8000-000000000005', 'authenticated', 'back@example.test');
delete from others_invites;
insert into others_invites select i::text from private.signup_invites i
where i.email in ('stay@example.test', 'later@example.test');

select is(private.forget_deleted_account_invites(), 1, 'one invite from an earlier deletion is removed');
select ok(not exists(select 1 from private.signup_invites where email = 'orphan@example.test')
  and not exists(select 1 from private.waitlist_signups where email = 'orphan@example.test'),
  'with its waitlist signup');
select is((select claimed_by from private.signup_invites where email = 'back@example.test'),
  'd1000000-0000-4000-8000-000000000005'::uuid, 'an invite claimed again now names the live account');
select ok(exists(select 1 from private.waitlist_signups where email = 'back@example.test'),
  'and its waitlist signup stays');
select results_eq($$select i::text from private.signup_invites i
  where i.email in ('stay@example.test', 'later@example.test') order by 1$$,
  $$select row_text from others_invites order by 1$$, 'other invites are untouched by the cleanup');
select is(private.forget_deleted_account_invites(), 0, 'running it again changes nothing');

select * from finish();
rollback;
