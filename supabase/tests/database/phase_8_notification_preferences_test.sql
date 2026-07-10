begin;
select plan(10);

insert into auth.users(id, role) values
  ('81111111-eeee-4111-8111-111111111111', 'authenticated'),
  ('82222222-eeee-4222-8222-222222222222', 'authenticated');

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class
   where oid = 'public.notification_preferences'::regclass),
  'notification preferences enable and force RLS'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.save_my_notification_preferences(boolean,boolean,text)',
    'execute'
  ),
  'authenticated owner can save notification preferences'
);
select ok(
  not has_table_privilege('authenticated', 'public.notification_preferences', 'insert'),
  'client cannot bypass the validated preference RPC'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '81111111-eeee-4111-8111-111111111111';
select lives_ok(
  $$select public.save_my_notification_preferences(true, true, 'authorized')$$,
  'owner can enable privacy-safe reminder types'
);
select ok(
  (select daily_check_in and weekly_review from public.notification_preferences),
  'enabled reminder types persist'
);
select is(
  (select action::text from public.consent_records
   where consent_type::text = 'notifications' order by created_at desc limit 1),
  'granted',
  'enabling reminders appends consent evidence'
);
select throws_ok(
  $$select public.save_my_notification_preferences(true, false, 'denied')$$,
  '22023', 'notification permission required',
  'denied iOS permission cannot persist an enabled reminder'
);

set local "request.jwt.claim.sub" = '82222222-eeee-4222-8222-222222222222';
select is(
  (select count(*) from public.notification_preferences),
  0::bigint,
  'cross-user preferences are hidden by RLS'
);

set local "request.jwt.claim.sub" = '81111111-eeee-4111-8111-111111111111';
select lives_ok(
  $$select public.save_my_notification_preferences(false, false, 'authorized')$$,
  'owner can disable all reminder types'
);
select is(
  (select count(*) from public.consent_records
   where consent_type::text = 'notifications' and action = 'withdrawn'),
  1::bigint,
  'disabling reminders appends withdrawal evidence'
);

select * from finish();
rollback;
