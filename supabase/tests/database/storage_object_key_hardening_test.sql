begin;
select plan(17);

insert into auth.users(id, role) values
  ('a1000000-0000-4000-8000-000000000001', 'authenticated'),
  ('a1000000-0000-4000-8000-000000000002', 'authenticated');

insert into storage.objects(bucket_id, name, owner_id) values
  ('meal-images', 'a1000000-0000-4000-8000-000000000001/meal/a1100000-0000-4000-8000-000000000001.jpg',
   'a1000000-0000-4000-8000-000000000001'),
  ('meal-images', 'a1000000-0000-4000-8000-000000000002/meal/a1100000-0000-4000-8000-000000000002.jpg',
   'a1000000-0000-4000-8000-000000000002'),
  ('meal-images', 'a1000000-0000-4000-8000-000000000001/meal/a1100000-0000-4000-8000-000000000003.jpg',
   'a1000000-0000-4000-8000-000000000002'),
  ('progress-photos', 'a1000000-0000-4000-8000-000000000001/progress/a1200000-0000-4000-8000-000000000001/front.jpg',
   'a1000000-0000-4000-8000-000000000001');
insert into public.progress_photo_sets(id, user_id, captured_on, capture_protocol_version, timing_context, status)
values ('a1200000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001',
  '2026-10-01', 'standard-v1', 'morning', 'draft');

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';

-- Meal drafts ---------------------------------------------------------------------------
select lives_ok($$select public.create_meal_photo_draft(current_date, 'UTC', 'lunch',
  'a1100000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001/meal/a1100000-0000-4000-8000-000000000001.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  'the exact key the app uploads is accepted');
select is((select public.create_meal_photo_draft(current_date, 'UTC', 'lunch',
  'a1100000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001/meal/a1100000-0000-4000-8000-000000000001.jpg',
  'image/jpeg', 100, repeat('a', 64))->>'replayed'), 'true',
  'a replay returns the same meal');
select throws_ok($$select public.create_meal_photo_draft(current_date, 'UTC', 'lunch',
  'a1100000-0000-4000-8000-000000000004',
  'a1000000-0000-4000-8000-000000000001/meal/../../a1000000-0000-4000-8000-000000000002/meal/a1100000-0000-4000-8000-000000000002.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  '22023', null, 'a key that leaves the meal folder is refused');
select throws_ok($$select public.create_meal_photo_draft(current_date, 'UTC', 'lunch',
  'a1100000-0000-4000-8000-000000000005',
  'a1000000-0000-4000-8000-000000000001/meal/a1100000-0000-4000-8000-000000000001.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  '22023', null, 'a key that does not match the request id is refused');
select throws_ok($$select public.create_meal_photo_draft(current_date, 'UTC', 'lunch',
  'a1100000-0000-4000-8000-000000000006',
  'a1000000-0000-4000-8000-000000000001/meal/a1100000-0000-4000-8000-000000000006.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  'P0002', 'uploaded object not found', 'a key with no uploaded object is refused');
select throws_ok($$select public.create_meal_photo_draft(current_date, 'UTC', 'lunch',
  'a1100000-0000-4000-8000-000000000003',
  'a1000000-0000-4000-8000-000000000001/meal/a1100000-0000-4000-8000-000000000003.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  'P0002', 'uploaded object not found', 'an object owned by someone else is refused');
select throws_ok($$select public.create_meal_photo_draft(current_date, 'UTC', 'lunch',
  'a1100000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000002/meal/a1100000-0000-4000-8000-000000000002.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  '22023', null, 'another user''s folder is refused');

-- Progress photos -----------------------------------------------------------------------
select throws_ok($$select public.register_progress_photo('a1200000-0000-4000-8000-000000000001', 'front',
  'a1000000-0000-4000-8000-000000000001/progress/a1200000-0000-4000-8000-000000000001/front./../../../a1000000-0000-4000-8000-000000000002/meal/a1100000-0000-4000-8000-000000000002.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  '22023', null, 'a progress key that continues after the pose is refused');
select throws_ok($$select public.register_progress_photo('a1200000-0000-4000-8000-000000000001', 'front',
  'a1000000-0000-4000-8000-000000000001/progress/a1200000-0000-4000-8000-000000000001/side.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  '22023', null, 'a progress key for another pose is refused');
select lives_ok($$select public.register_progress_photo('a1200000-0000-4000-8000-000000000001', 'front',
  'a1000000-0000-4000-8000-000000000001/progress/a1200000-0000-4000-8000-000000000001/front.jpg',
  'image/jpeg', 100, repeat('a', 64))$$,
  'the exact progress key the app uploads is accepted');

-- Coach preferences ---------------------------------------------------------------------
select throws_ok($$select public.persist_coach_preference('a1000000-0000-4000-8000-000000000002',
  'training', 'split', 'upper lower', 'chat_statement')$$,
  '42501', 'not allowed', 'a preference cannot be written for another athlete');
select lives_ok($$select public.persist_coach_preference('a1000000-0000-4000-8000-000000000001',
  'training', 'split', 'upper lower', 'chat_statement')$$,
  'an athlete can confirm their own preference');
select throws_ok($$select public.persist_coach_preference(null,
  'training', 'split', 'upper lower', 'chat_statement')$$,
  '42501', 'not allowed', 'a missing athlete is refused');

reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok($$select public.persist_coach_preference('a1000000-0000-4000-8000-000000000002',
  'food', 'breakfast', 'oats', 'chat_statement')$$,
  'the service role still writes for any athlete');
reset role;

select is((select count(*) from public.user_preferences
  where user_id = 'a1000000-0000-4000-8000-000000000002' and key = 'split'), 0::bigint,
  'no preference was written for the other athlete by the app');

-- Stored keys ---------------------------------------------------------------------------
select throws_ok($$insert into public.media_objects(user_id, purpose, object_key, content_type,
  byte_size, checksum, retention_deadline) values ('a1000000-0000-4000-8000-000000000001',
  'meal_analysis', 'a1000000-0000-4000-8000-000000000001/meal/../x.jpg', 'image/jpeg', 1,
  repeat('a', 64), now())$$,
  '23514', null, 'a stored key cannot contain a dot segment');
select throws_ok($$insert into public.media_objects(user_id, purpose, object_key, content_type,
  byte_size, checksum, retention_deadline) values ('a1000000-0000-4000-8000-000000000001',
  'meal_analysis', 'a1000000-0000-4000-8000-000000000002/meal/x.jpg', 'image/jpeg', 1,
  repeat('a', 64), now())$$,
  '23514', null, 'a stored key stays in its owner''s folder');

select * from finish();
rollback;
