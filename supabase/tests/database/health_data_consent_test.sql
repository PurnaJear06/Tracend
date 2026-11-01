begin;
select plan(5);

insert into auth.users(id, role) values
  ('e2000000-0000-4000-8000-000000000001', 'authenticated'),
  ('e2000000-0000-4000-8000-000000000002', 'authenticated');

select ok(
  exists (
    select 1 from pg_enum e
    where e.enumtypid = 'public.consent_type'::regtype and e.enumlabel = 'health_data'
  ),
  'health_data is a consent type of its own');

set local role authenticated;
set local "request.jwt.claim.sub" = 'e2000000-0000-4000-8000-000000000001';
select lives_ok($$
  insert into public.consent_records(user_id, consent_type, notice_version, action, source)
  values ('e2000000-0000-4000-8000-000000000001', 'health_data', '2026-11-02', 'granted', 'ios_app')
$$, 'an athlete records their own health-data consent');
select is(
  (select notice_version from public.consent_records where consent_type = 'health_data'),
  '2026-11-02',
  'the athlete reads back the version they agreed to');
select throws_ok($$
  insert into public.consent_records(user_id, consent_type, notice_version, action, source)
  values ('e2000000-0000-4000-8000-000000000002', 'health_data', '2026-11-02', 'granted', 'ios_app')
$$, '42501', null, 'nobody records consent for another athlete');
set local "request.jwt.claim.sub" = 'e2000000-0000-4000-8000-000000000002';
select is(
  (select count(*) from public.consent_records where consent_type = 'health_data'),
  0::bigint,
  'another athlete sees none of it');
reset role;

select * from finish();
rollback;
