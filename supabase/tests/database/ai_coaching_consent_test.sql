begin;

select plan(6);

insert into auth.users (id, role)
values
  ('c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'authenticated'),
  ('d2d2d2d2-d2d2-4d2d-8d2d-d2d2d2d2d2d2', 'authenticated');

select ok(
  'ai_coaching' = any(enum_range(null::public.consent_type)::text[]),
  'ai_coaching is a consent purpose'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1';

select lives_ok(
  $$insert into public.consent_records (
      user_id, consent_type, notice_version, action, source)
    values ('c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'ai_coaching',
      'ai-coaching-v1', 'withdrawn', 'ios_app'),
    ('c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'ai_coaching',
      'ai-coaching-v1', 'granted', 'ios_app')$$,
  'an athlete records their own AI coaching choices'
);

select throws_ok(
  $$insert into public.consent_records (
      user_id, consent_type, notice_version, action, source)
    values ('d2d2d2d2-d2d2-4d2d-8d2d-d2d2d2d2d2d2', 'ai_coaching',
      'ai-coaching-v1', 'granted', 'ios_app')$$,
  '42501',
  null,
  'nobody can record AI coaching consent for another athlete'
);

select throws_ok(
  $$update public.consent_records set action = 'granted'
    where consent_type = 'ai_coaching'$$,
  '42501',
  null,
  'a recorded choice cannot be rewritten'
);

select is(
  (select count(*) from public.consent_records where consent_type = 'ai_coaching'),
  2::bigint,
  'an athlete sees their own AI coaching history'
);

set local "request.jwt.claim.sub" = 'd2d2d2d2-d2d2-4d2d-8d2d-d2d2d2d2d2d2';

select is(
  (select count(*) from public.consent_records where consent_type = 'ai_coaching'),
  0::bigint,
  'another athlete cannot read that history'
);

reset role;

select * from finish();
rollback;
