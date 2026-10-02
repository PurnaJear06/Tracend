begin;
select plan(28);

insert into auth.users(id, role) values
  ('f5000000-0000-4000-8000-000000000001', 'authenticated'),
  ('f5000000-0000-4000-8000-000000000002', 'authenticated');
insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level, training_days, session_minutes)
values ('f5000000-0000-4000-8000-000000000001', now(), true, 'intermediate', array[1,3,5]::smallint[], 60);

insert into public.progress_photo_sets(id, user_id, captured_on, capture_protocol_version, timing_context, status) values
  ('f5100000-0000-4000-8000-000000000001', 'f5000000-0000-4000-8000-000000000001', '2026-10-01', 'standard-v1', 'morning', 'complete'),
  ('f5100000-0000-4000-8000-000000000002', 'f5000000-0000-4000-8000-000000000001', '2026-10-02', 'standard-v1', 'morning', 'draft');
insert into public.media_objects(id, user_id, purpose, object_key, content_type, byte_size, checksum,
  retention_deadline, retention_exempt) values
  ('f5200000-0000-4000-8000-000000000001', 'f5000000-0000-4000-8000-000000000001', 'progress_front',
   'f5000000-0000-4000-8000-000000000001/progress/f5100000-0000-4000-8000-000000000001/front.jpg',
   'image/jpeg', 100, repeat('a', 64), 'infinity', true);
insert into public.progress_photos(user_id, photo_set_id, media_object_id, pose, quality_status) values
  ('f5000000-0000-4000-8000-000000000001', 'f5100000-0000-4000-8000-000000000001',
   'f5200000-0000-4000-8000-000000000001', 'front', 'accepted');

create temporary table result as select
  '{"schema_version":"1.0","development_priorities":[
     {"muscle":"chest","confidence":"medium","reason":"Upper chest looks less full than the arms."},
     {"muscle":"calves","confidence":"low","reason":"Calves look small next to the thighs."}],
   "observations":["Back width stands out."],"photo_issues":["lighting"],
   "limitations":"Photos cannot show strength."}'::jsonb value;
grant select on result to service_role, authenticated;

-- The notice ---------------------------------------------------------------------------

select is((select count(*) from public.photo_ai_notices), 1::bigint, 'one photo AI notice is published');
select ok((select body like '%Groq%qwen/qwen3.8-27b%Zero Data Retention%' from public.photo_ai_notices),
  'it names Groq, the model and Zero Data Retention');
select is((select count(*) from public.ai_consent_notices where body like '%Groq%'), 0::bigint,
  'the coaching notices are unchanged');

set local role authenticated;
set local "request.jwt.claim.sub" = 'f5000000-0000-4000-8000-000000000001';
select is(public.get_my_photo_ai_notice()->>'granted', 'false', 'no grant yet');
insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('f5000000-0000-4000-8000-000000000001', 'progress_photo_ai', 'progress-photo-ai-v1', 'granted', 'ios_app');
select is(public.get_my_photo_ai_notice()->>'granted', 'true', 'granting the current notice counts');
reset role;
select ok(public.has_photo_ai_consent('f5000000-0000-4000-8000-000000000001'), 'the server sees the grant');
select private.publish_photo_ai_notice('progress-photo-ai-v2', 'Groq', 'qwen/qwen3.8-27b', 'A newer notice.');
select ok(not public.has_photo_ai_consent('f5000000-0000-4000-8000-000000000001'),
  'a newer notice needs a new grant');
insert into public.consent_records(user_id, consent_type, notice_version, action, source, created_at) values
  ('f5000000-0000-4000-8000-000000000001', 'progress_photo_ai', 'progress-photo-ai-v2', 'granted', 'ios_app', now() + interval '1 second'),
  ('f5000000-0000-4000-8000-000000000001', 'progress_photo_ai', 'progress-photo-ai-v2', 'withdrawn', 'ios_app', now() + interval '2 seconds');
select ok(not public.has_photo_ai_consent('f5000000-0000-4000-8000-000000000001'),
  'withdrawing stops checks');
insert into public.consent_records(user_id, consent_type, notice_version, action, source, created_at)
values ('f5000000-0000-4000-8000-000000000001', 'progress_photo_ai', 'progress-photo-ai-v2', 'granted', 'ios_app', now() + interval '3 seconds');
select ok(not has_function_privilege('authenticated', 'public.has_photo_ai_consent(uuid)', 'execute'),
  'only the server reads another account''s consent');

-- Storing a check -----------------------------------------------------------------------

set local role service_role;
select throws_ok($$select public.persist_physique_analysis('f5000000-0000-4000-8000-000000000001',
    'f5100000-0000-4000-8000-000000000002', (select value from result), 'groq', 'qwen/qwen3.8-27b',
    'progress-photo-ai-v2', null)$$, 'P0002', null, 'only a complete set is checked');
select throws_ok($$select public.persist_physique_analysis('f5000000-0000-4000-8000-000000000001',
    'f5100000-0000-4000-8000-000000000001', (select value from result), 'groq', 'qwen/qwen3.8-27b',
    'progress-photo-ai-v1', null)$$, '22023', null, 'a check under an older notice is refused');
select throws_ok($$select public.persist_physique_analysis('f5000000-0000-4000-8000-000000000001',
    'f5100000-0000-4000-8000-000000000001',
    jsonb_set((select value from result), '{body_fat}', '"15%"'), 'groq', 'qwen/qwen3.8-27b',
    'progress-photo-ai-v2', null)$$, '23514', null, 'a body-fat field cannot be stored');
select throws_ok($$select public.persist_physique_analysis('f5000000-0000-4000-8000-000000000001',
    'f5100000-0000-4000-8000-000000000001',
    jsonb_set((select value from result), '{development_priorities,0,muscle}', '"forearms"'),
    'groq', 'qwen/qwen3.8-27b', 'progress-photo-ai-v2', null)$$,
  '23514', null, 'only catalog muscles');
create temporary table analysis as select public.persist_physique_analysis(
  'f5000000-0000-4000-8000-000000000001', 'f5100000-0000-4000-8000-000000000001',
  (select value from result), 'groq', 'qwen/qwen3.8-27b', 'progress-photo-ai-v2',
  '{"attempts":1,"input_units":6800}') id;
grant select on analysis to authenticated;
reset role;
select is((select confidence from public.physique_analyses), 'medium', 'the analysis is stored');
select is((select metadata->>'input_units' from public.audit_events
    where action_code = 'progress.physique_check.completed'), '6800', 'and audited with its telemetry');
select ok(not has_function_privilege('authenticated',
    'public.persist_physique_analysis(uuid, uuid, jsonb, text, text, text, jsonb)', 'execute'),
  'only the server stores checks');

-- Confirming focus muscles ----------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'f5000000-0000-4000-8000-000000000001';
select throws_ok(format($$select public.set_my_priority_muscles(array['back'], %L)$$, (select id from analysis)),
  '22023', null, 'from a check, only the muscles it suggested');
select throws_ok($$select public.set_my_priority_muscles(array['chest','calves','back'])$$,
  '22023', null, 'at most two');
select is(public.set_my_priority_muscles(array['calves','chest'], (select id from analysis))->'priority_muscles',
  '["chest", "calves"]'::jsonb, 'the athlete confirms, in catalog order');
select is((select priority_muscles from public.user_profiles), array['chest','calves'],
  'the focus muscles are the athlete''s');
select is((select confirmed_muscles from public.physique_analyses), array['chest','calves'],
  'the analysis records what was confirmed');
select is(public.set_my_priority_muscles(array[]::text[])->'priority_muscles', '[]'::jsonb,
  'the focus can be cleared');
set local "request.jwt.claim.sub" = 'f5000000-0000-4000-8000-000000000002';
select is((select count(*) from public.physique_analyses), 0::bigint, 'nobody else reads the analysis');
select throws_ok($$select public.set_my_priority_muscles(array['chest'])$$, 'P0002', null,
  'an athlete without a profile has no focus to set');

-- Deleting ----------------------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'f5000000-0000-4000-8000-000000000001';
select ok(public.delete_my_progress_photo_set('f5100000-0000-4000-8000-000000000001'),
  'a set with an analysis can be deleted');
reset role;
select is((select count(*) from public.physique_analyses), 0::bigint, 'its analysis goes with it');
select is((select count(*) from public.media_objects where user_id = 'f5000000-0000-4000-8000-000000000001'),
  0::bigint, 'and its media');
insert into public.physique_analyses(user_id, baseline_photo_set_id, current_photo_set_id, result)
select 'f5000000-0000-4000-8000-000000000001', 'f5100000-0000-4000-8000-000000000002',
  'f5100000-0000-4000-8000-000000000002', value from result;
select lives_ok($$delete from auth.users where id = 'f5000000-0000-4000-8000-000000000001'$$,
  'deleting the account removes sets and analyses together');

select * from finish();
rollback;
