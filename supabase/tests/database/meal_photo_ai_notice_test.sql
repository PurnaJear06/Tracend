begin;
select plan(12);

insert into auth.users(id, role) values
  ('e1000000-0000-4000-8000-000000000001', 'authenticated'),
  ('e1000000-0000-4000-8000-000000000002', 'authenticated');

select is((private.current_meal_photo_ai_notice()).version, 'meal-photo-ai-v1',
  'the meal photo notice is published');
select is((private.current_meal_photo_ai_notice()).provider, 'groq', 'it names the provider');
select ok(not has_function_privilege('authenticated', 'public.has_meal_photo_ai_consent(uuid)', 'execute'),
  'clients cannot check another athlete''s consent');
select ok(not has_function_privilege('authenticated', 'public.get_meal_photo_ai_consent(uuid)', 'execute'),
  'clients cannot read the server consent state');

set local role authenticated;
set local "request.jwt.claim.sub" = 'e1000000-0000-4000-8000-000000000001';
select is(public.get_my_meal_photo_ai_notice()->>'granted', 'false', 'nothing is granted at first');
select is(public.get_my_meal_photo_ai_notice()->>'schema_version', '1.0', 'the notice is versioned');
insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('e1000000-0000-4000-8000-000000000001', 'meal_photo_ai', 'meal-photo-ai-v1', 'granted', 'ios_app');
select is(public.get_my_meal_photo_ai_notice()->>'granted', 'true', 'a grant of the current notice counts');
reset role;

select is(public.get_meal_photo_ai_consent('e1000000-0000-4000-8000-000000000001'),
  '{"granted": true, "provider": "groq"}'::jsonb, 'the server sees the grant and the provider');
select is(public.has_meal_photo_ai_consent('e1000000-0000-4000-8000-000000000002'), false,
  'another athlete''s grant does not count');

insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('e1000000-0000-4000-8000-000000000002', 'progress_photo_ai', 'progress-photo-ai-v1', 'granted', 'ios_app');
select is(public.has_meal_photo_ai_consent('e1000000-0000-4000-8000-000000000002'), false,
  'physique consent is not meal photo consent');

select private.publish_meal_photo_ai_notice('meal-photo-ai-v2', 'gemini', 'Google', 'gemini-3.5-flash', 'New provider.');
select is(public.has_meal_photo_ai_consent('e1000000-0000-4000-8000-000000000001'), false,
  'a new notice needs a new grant');
select is((select count(*) from public.photo_ai_notices where version like 'meal-%'), 0::bigint,
  'the physique notice is untouched');

select * from finish();
rollback;
