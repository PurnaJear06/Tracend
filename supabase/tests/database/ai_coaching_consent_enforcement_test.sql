begin;

select plan(7);

insert into auth.users (id, role)
values
  ('b6b6b6b6-b6b6-4b6b-8b6b-b6b6b6b6b6b6', 'authenticated'),
  ('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7', 'authenticated');

select is(
  public.has_ai_coaching_consent('b6b6b6b6-b6b6-4b6b-8b6b-b6b6b6b6b6b6'),
  false,
  'no answer yet means no AI coaching'
);

insert into public.consent_records (
  user_id, consent_type, notice_version, action, source, created_at)
values ('b6b6b6b6-b6b6-4b6b-8b6b-b6b6b6b6b6b6', 'ai_coaching', 'ai-coaching-v1',
  'granted', 'ios_app', now() - interval '2 hours');

select is(
  public.has_ai_coaching_consent('b6b6b6b6-b6b6-4b6b-8b6b-b6b6b6b6b6b6'),
  true,
  'a grant of the current notice allows AI coaching'
);

select is(
  public.has_ai_coaching_consent('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7'),
  false,
  'another athlete''s grant does not count'
);

insert into public.consent_records (
  user_id, consent_type, notice_version, action, source, created_at)
values ('b6b6b6b6-b6b6-4b6b-8b6b-b6b6b6b6b6b6', 'ai_coaching', 'ai-coaching-v1',
  'withdrawn', 'ios_app', now() - interval '1 hour');

select is(
  public.has_ai_coaching_consent('b6b6b6b6-b6b6-4b6b-8b6b-b6b6b6b6b6b6'),
  false,
  'turning AI coaching off stops it'
);

insert into public.consent_records (
  user_id, consent_type, notice_version, action, source, created_at)
values ('b6b6b6b6-b6b6-4b6b-8b6b-b6b6b6b6b6b6', 'ai_coaching', 'ai-coaching-v0',
  'granted', 'ios_app', now());

select is(
  public.has_ai_coaching_consent('b6b6b6b6-b6b6-4b6b-8b6b-b6b6b6b6b6b6'),
  false,
  'a grant of an older notice does not count'
);

select ok(
  not has_function_privilege('authenticated',
    'public.has_ai_coaching_consent(uuid)', 'execute'),
  'the app cannot call the check directly'
);

select ok(
  not has_function_privilege('anon',
    'public.has_ai_coaching_consent(uuid)', 'execute'),
  'anonymous callers cannot run the check'
);

select * from finish();
rollback;
