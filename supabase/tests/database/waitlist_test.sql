begin;
select plan(45);

create function pg_temp.h(t text) returns text language sql as $$ select encode(sha256(convert_to(t, 'UTF8')), 'hex') $$;
create function pg_temp.join_as(addr text, ip text, tag text, ref text default null)
returns jsonb language sql as $$
  select public.waitlist_join(addr, ip, pg_temp.h('c-' || tag), pg_temp.h('u-' || tag), ref,
    'waitlist-2026-10-13', 'Asia/Kolkata', '{"source":"instagram","medium":7}'::jsonb)
$$;

-- Access ---------------------------------------------------------------------------------
select ok(not has_table_privilege('anon', 'private.waitlist_signups', 'select'), 'visitors cannot read the waitlist');
select ok(not has_table_privilege('authenticated', 'private.waitlist_signups', 'select'), 'app users cannot read the waitlist');
select ok(not has_table_privilege('service_role', 'private.waitlist_signups', 'select'), 'the service role cannot read the waitlist directly');
select ok(not has_table_privilege('service_role', 'private.waitlist_secret', 'select'), 'nobody but the owner reads the IP salt');
select ok(not has_function_privilege('anon', 'public.waitlist_join(text, text, text, text, text, text, text, jsonb)', 'execute'), 'visitors cannot call join directly');
select ok(not has_function_privilege('authenticated', 'public.waitlist_confirm(text)', 'execute'), 'app users cannot call confirm');
select ok(not has_function_privilege('anon', 'public.waitlist_unsubscribe(text)', 'execute'), 'visitors cannot call unsubscribe directly');
select ok(not has_function_privilege('anon', 'public.waitlist_unsent(text, text)', 'execute'), 'visitors cannot undo a send');
select ok(has_function_privilege('service_role', 'public.waitlist_join(text, text, text, text, text, text, text, jsonb)', 'execute'), 'the Edge Function can join');
select ok(not has_function_privilege('service_role', 'private.invite_from_waitlist(integer)', 'execute'), 'inviting is for the owner only');

-- Join -----------------------------------------------------------------------------------
set local role service_role;
create temp table r on commit drop as select pg_temp.join_as(' Ana@Example.test ', '203.0.113.1', 'ana') as v;
select is((select v ->> 'outcome' from r), 'send', 'a new address gets a confirmation email');
select matches((select v ->> 'referral_code' from r), '^[0-9A-HJKMNP-TV-Z]{8}$', 'and an 8-character invite code');
select is(pg_temp.join_as('ana@example.test', '203.0.113.1', 'ana2') ->> 'outcome', 'none',
  'joining again within 10 minutes sends nothing');
select is(pg_temp.join_as('ANA@example.test', '203.0.113.1', 'ana3') ->> 'referral_code',
  (select v ->> 'referral_code' from r), 'the same person keeps the same code whatever the case');
select throws_ok($$select pg_temp.join_as('not-an-email', '203.0.113.1', 'x')$$, '22023', 'invalid email',
  'a malformed address is refused');
select throws_ok($$select public.waitlist_join('a@b.test', null, 'nothex', pg_temp.h('u'), null, 'v1', null, null)$$,
  '22023', 'invalid token hash', 'a malformed token hash is refused');

reset role;
select is((select email from private.waitlist_signups where confirm_token_hash = pg_temp.h('c-ana')),
  'ana@example.test', 'the address is stored trimmed and lower case, the token only as a hash');
select is((select utm_source from private.waitlist_signups where email = 'ana@example.test'),
  'instagram', 'campaign tags are kept');
select is((select count(*) from private.waitlist_attempts), 3::bigint, 'each attempt is counted');
select ok((select bool_and(ip_hash ~ '^[0-9a-f]{64}$') from private.waitlist_attempts), 'and the IP address is stored only as a salted hash');

-- Rate limit -----------------------------------------------------------------------------
set local role service_role;
select pg_temp.join_as('rate' || n || '@example.test', '198.51.100.7', 'rate' || n) from generate_series(1, 5) n;
select is(pg_temp.join_as('rate6@example.test', '198.51.100.7', 'rate6') ->> 'outcome', 'rate_limited',
  'the sixth try from one network in an hour is refused');
select is(pg_temp.join_as('ben@example.test', '198.51.100.8', 'ben') ->> 'outcome', 'send',
  'another network is unaffected');

-- Email not sent -------------------------------------------------------------------------
select public.waitlist_unsent('ben@example.test', pg_temp.h('c-ben'));
select is(pg_temp.join_as('ben@example.test', '198.51.100.8', 'ben2') ->> 'outcome', 'send',
  'after a failed email the next try sends at once');
select is((select v ->> 'status' from (select public.waitlist_confirm(pg_temp.h('c-ben')) v) x), 'invalid',
  'the unsent link no longer works');

-- Confirm --------------------------------------------------------------------------------
select is(public.waitlist_confirm(pg_temp.h('c-ana')) ->> 'status', 'confirmed', 'the email link confirms');
select is(public.waitlist_confirm(pg_temp.h('c-ana')) ->> 'referral_code', (select v ->> 'referral_code' from r),
  'a second tap still says confirmed and shows the code');
select is(public.waitlist_confirm(pg_temp.h('unknown')) ->> 'status', 'invalid', 'an unknown link is invalid');
select is(public.waitlist_confirm('nothex') ->> 'status', 'invalid', 'a malformed link is invalid');
select is(pg_temp.join_as('ana@example.test', '203.0.113.2', 'ana4') ->> 'outcome', 'none',
  'a confirmed address is never emailed again by joining');

reset role;
update private.waitlist_signups set confirm_expires_at = now() - interval '1 second' where email = 'ben@example.test';
set local role service_role;
select is(public.waitlist_confirm(pg_temp.h('c-ben2')) ->> 'status', 'expired', 'an old link has expired');

-- Referrals ------------------------------------------------------------------------------
select is(pg_temp.join_as('cy@example.test', '203.0.113.3', 'cy', lower((select v ->> 'referral_code' from r))) ->> 'outcome',
  'send', 'a friend joins through an invite link');
select public.waitlist_confirm(pg_temp.h('c-cy'));
reset role;
select is((select referred_by from private.waitlist_signups where email = 'cy@example.test'),
  (select id from private.waitlist_signups where email = 'ana@example.test'), 'the referral is recorded');

-- Unsubscribe ----------------------------------------------------------------------------
set local role service_role;
select is(public.waitlist_unsubscribe(pg_temp.h('u-cy')) ->> 'status', 'unsubscribed', 'the unsubscribe link works');
select is(public.waitlist_unsubscribe(pg_temp.h('u-cy')) ->> 'status', 'unsubscribed', 'and works twice');
select is(public.waitlist_unsubscribe(pg_temp.h('nobody')) ->> 'status', 'invalid', 'an unknown unsubscribe link is invalid');
select is(public.waitlist_confirm(pg_temp.h('c-cy')) ->> 'status', 'unsubscribed', 'an unsubscribed address cannot be confirmed');
select is(pg_temp.join_as('cy@example.test', '203.0.113.4', 'cy2') ->> 'outcome', 'send',
  'joining again after unsubscribing asks for fresh consent');
reset role;
select is((select status from private.waitlist_signups where email = 'cy@example.test'), 'pending',
  'and starts over as pending');

-- Invites --------------------------------------------------------------------------------
set local role service_role;
select pg_temp.join_as('dee@example.test', '203.0.113.5', 'dee');
select public.waitlist_confirm(pg_temp.h('c-dee'));
select public.waitlist_confirm(pg_temp.h('c-cy2'));
reset role;
-- ana has one confirmed referral (cy), so she goes first even though dee joined later.
select results_eq($$select email from private.invite_from_waitlist(1)$$, array['ana@example.test'],
  'the person with the most confirmed referrals is invited first');
select results_eq($$select email from private.invite_from_waitlist(5) order by 1$$,
  array['cy@example.test', 'dee@example.test'], 'then the rest of the confirmed list, never pending ones');
select is((select count(*) from private.invite_from_waitlist(5)), 0::bigint, 'nobody is invited twice');
select is((select count(*) from private.signup_invites where note = 'waitlist'), 3::bigint,
  'invited addresses join the sign-up invite list');
select lives_ok($$insert into auth.users(id, role, email)
  values ('c1000000-0000-4000-8000-000000000001', 'authenticated', 'dee@example.test')$$,
  'an invited waitlister can create an app account');

-- Cleanup --------------------------------------------------------------------------------
update private.waitlist_signups set last_sent_at = now() - interval '31 days' where email = 'ben@example.test';
select private.waitlist_cleanup();
select ok(not exists(select 1 from private.waitlist_signups where email = 'ben@example.test')
  and exists(select 1 from private.waitlist_signups where email = 'ana@example.test'),
  'unconfirmed signups go after 30 days, confirmed ones stay');
select ok(exists(select 1 from cron.job where jobname = 'tracend-waitlist-cleanup'), 'cleanup runs daily');

select * from finish();
rollback;
