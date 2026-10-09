begin;
select plan(19);

insert into auth.users(id, role) values
  ('c1000000-0000-4000-8000-000000000001', 'authenticated'),
  ('c1000000-0000-4000-8000-000000000002', 'authenticated');

-- Time zones ----------------------------------------------------------------------------
update public.user_accounts set timezone = 'Mars/Olympus', account_status = 'active',
  onboarding_state = 'completed' where id = 'c1000000-0000-4000-8000-000000000001';
select is(private.safe_timezone('Mars/Olympus'), 'UTC', 'an unknown zone falls back to UTC');
select is(private.safe_timezone('Asia/Kolkata'), 'Asia/Kolkata', 'a known zone is kept');
select lives_ok($$select public.schedule_weekly_progress_reviews()$$,
  'one bad stored zone does not stop the weekly scheduler');

-- Consent records -----------------------------------------------------------------------
set local role authenticated;
set local "request.jwt.claim.sub" = 'c1000000-0000-4000-8000-000000000002';
select throws_ok($$insert into public.consent_records(user_id, consent_type, notice_version, action,
  source, created_at) values ('c1000000-0000-4000-8000-000000000002', 'progress_photo_ai',
  'progress-photo-ai-v1', 'granted', 'ios_app', now() + interval '1 year')$$,
  '42501', null, 'a client cannot date a consent record');
select lives_ok($$insert into public.consent_records(user_id, consent_type, notice_version, action,
  source) values ('c1000000-0000-4000-8000-000000000002', 'progress_photo_ai',
  'progress-photo-ai-v1', 'granted', 'ios_app')$$,
  'a client records consent with the columns the app sends');
reset role;
insert into public.consent_records(user_id, consent_type, notice_version, action, source)
select 'c1000000-0000-4000-8000-000000000002', 'progress_photo_ai', 'progress-photo-ai-v1',
  'granted', 'ios_app' from generate_series(1, 99);
select throws_ok($$insert into public.consent_records(user_id, consent_type, notice_version, action,
  source) values ('c1000000-0000-4000-8000-000000000002', 'progress_photo_ai',
  'progress-photo-ai-v1', 'granted', 'ios_app')$$,
  '54000', null, 'more than 100 consent records a day are refused');

-- Row caps ------------------------------------------------------------------------------
insert into public.coach_threads(user_id, title)
select 'c1000000-0000-4000-8000-000000000002', 'Thread ' || n from generate_series(1, 50) n;
select throws_ok($$insert into public.coach_threads(user_id, title)
  values ('c1000000-0000-4000-8000-000000000002', 'One more')$$,
  '54000', null, 'more than 50 conversations a day are refused');
select lives_ok($$insert into public.coach_threads(user_id, title)
  values ('c1000000-0000-4000-8000-000000000001', 'First')$$,
  'another athlete is not affected');

-- Bounded client JSON -------------------------------------------------------------------
insert into public.onboarding_drafts(user_id) values ('c1000000-0000-4000-8000-000000000001');
select throws_ok($$update public.onboarding_drafts set payload = jsonb_build_object('x', repeat('a', 140000))
  where user_id = 'c1000000-0000-4000-8000-000000000001'$$, '23514', null,
  'an oversized onboarding draft is refused');

-- Health sync ---------------------------------------------------------------------------
set local role service_role;
select throws_ok($$select public.persist_health_sync_v2('c1000000-0000-4000-8000-000000000001',
  'c1500000-0000-4000-8000-000000000001', current_date + 10, current_date + 12, array['steps'],
  array['steps'], '[]'::jsonb, '[]'::jsonb)$$, '22023', null, 'a future window is refused');
select throws_ok(format($$select public.persist_health_sync_v2('c1000000-0000-4000-8000-000000000001',
  'c1500000-0000-4000-8000-000000000002', current_date - 1, current_date, array['steps'],
  array['steps'], jsonb_build_array(jsonb_build_object('source_refs',
    (select jsonb_agg(n) from generate_series(1, 20001) n))), '[]'::jsonb)$$),
  '22023', null, 'a summary with too many source references is refused');
select throws_ok($$select public.persist_health_sync_v2('c1000000-0000-4000-8000-000000000001',
  'c1500000-0000-4000-8000-000000000003', current_date - 1, current_date, array['workouts'],
  array['workouts'], '[]'::jsonb, jsonb_build_array(jsonb_build_object('local_date', '2020-01-01')))$$,
  '22023', null, 'a workout outside the requested window is refused');
reset role;
insert into public.health_sync_runs(user_id, idempotency_key, requested_start, requested_end,
  requested_types, returned_types, accepted_count, rejected_count, status)
select 'c1000000-0000-4000-8000-000000000001', gen_random_uuid(), current_date, current_date,
  array['steps'], array['steps'], 0, 0, 'completed' from generate_series(1, 120);
set local role service_role;
select throws_ok($$select public.persist_health_sync_v2('c1000000-0000-4000-8000-000000000001',
  'c1500000-0000-4000-8000-000000000004', current_date - 1, current_date, array['steps'],
  array['steps'], '[]'::jsonb, '[]'::jsonb)$$, '54000', null, 'more than 120 syncs an hour are refused');
select is((public.persist_health_sync_v2('c1000000-0000-4000-8000-000000000001',
  (select idempotency_key from public.health_sync_runs
   where user_id = 'c1000000-0000-4000-8000-000000000001' limit 1),
  current_date, current_date, array['steps'], array['steps'], '[]'::jsonb,
  '[{"local_date":"2020-01-01"}]'::jsonb)->>'workout_reference_count'), '0',
  'a replay returns the stored run and skips the workouts');
reset role;

-- Upload quotas and orphans -------------------------------------------------------------
insert into storage.objects(bucket_id, name, owner_id, created_at)
select 'meal-images', 'c1000000-0000-4000-8000-000000000002/meal/' || gen_random_uuid() || '.jpg',
  'c1000000-0000-4000-8000-000000000002', now() from generate_series(1, 100);
set local role authenticated;
set local "request.jwt.claim.sub" = 'c1000000-0000-4000-8000-000000000002';
select is(public.storage_upload_allowed('meal-images'), false,
  'the 101st meal photo in a day is over quota');
set local "request.jwt.claim.sub" = 'c1000000-0000-4000-8000-000000000001';
select is(public.storage_upload_allowed('meal-images'), true, 'another athlete still has quota');
reset role;

insert into storage.objects(bucket_id, name, owner_id, created_at) values
  ('progress-photos', 'c1000000-0000-4000-8000-000000000001/progress/old/front.jpg',
   'c1000000-0000-4000-8000-000000000001', now() - interval '2 days'),
  ('progress-photos', 'c1000000-0000-4000-8000-000000000001/progress/new/front.jpg',
   'c1000000-0000-4000-8000-000000000001', now());
select is((select array_agg(name) from public.list_orphan_storage_objects(500)
  where name like 'c1000000-0000-4000-8000-000000000001/%'),
  array['c1000000-0000-4000-8000-000000000001/progress/old/front.jpg'],
  'only an orphan older than a day is listed');
select ok(not has_function_privilege('authenticated', 'public.list_orphan_storage_objects(integer)',
  'execute'), 'clients cannot list orphans');
select is((select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
  and policyname = 'user_media_upload_quota' and permissive = 'RESTRICTIVE'), 1::bigint,
  'the upload quota is a restrictive policy');

select * from finish();
rollback;
