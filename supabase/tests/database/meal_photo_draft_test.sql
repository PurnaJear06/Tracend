begin;
select plan(22);

insert into auth.users(id, role) values
  ('11111111-1111-7777-8777-111111111111', 'authenticated'),
  ('22222222-2222-7777-8777-222222222222', 'authenticated');

select ok(has_function_privilege('authenticated',
  'public.create_meal_photo_draft(date,text,text,uuid,text,text,integer,text)', 'execute'),
  'authenticated owner can create meal photo draft');
select ok(has_function_privilege('authenticated',
  'public.confirm_analyzed_meal(uuid,jsonb)', 'execute'),
  'authenticated owner can confirm analyzed meal');
select ok(has_function_privilege('authenticated',
  'public.save_scheduled_manual_meal(date,text,text,uuid,jsonb,uuid,text)', 'execute'),
  'authenticated owner can save scheduled manual meal');
select ok(has_function_privilege('service_role',
  'public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text)', 'execute'),
  'service_role can persist meal photo candidates');
select ok(not has_function_privilege('authenticated',
  'public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text)', 'execute'),
  'authenticated cannot forge meal candidates');

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-7777-8777-111111111111';

create temporary table draft as
select public.create_meal_photo_draft(
  current_date, 'Asia/Kolkata', 'breakfast',
  '11111117-1111-7777-8777-111111111111',
  '11111111-1111-7777-8777-111111111111/meal/photo_001.jpg',
  'image/jpeg', 1024000,
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
) json;

select ok((select json->>'meal_id' is not null from draft),
  'photo draft returns a meal_id');

select is((select json->>'replayed' from draft), 'false',
  'first creation is not a replay');

select ok((select json->>'media_id' is not null from draft),
  'photo draft returns a media_id');

select is((select json->>'object_path' from draft),
  '11111111-1111-7777-8777-111111111111/meal/photo_001.jpg',
  'object_path is echoed back');

select lives_ok$$select public.create_meal_photo_draft(
  current_date, 'Asia/Kolkata', 'breakfast',
  '11111117-1111-7777-8777-111111111111',
  '11111111-1111-7777-8777-111111111111/meal/photo_001.jpg',
  'image/jpeg', 1024000,
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
)$$, 'draft creation is idempotent');

select is((select count(*) from public.meals
  where user_id = '11111111-1111-7777-8777-111111111111'), 1::bigint,
  'idempotent key does not duplicate meal');

select throws_ok$$select public.create_meal_photo_draft(
  current_date, 'Asia/Kolkata', 'invalid_kind',
  '21111117-1111-7777-8777-111111111111',
  '11111111-1111-7777-8777-111111111111/meal/photo_002.jpg',
  'image/jpeg', 1024000,
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
)$$, '22023', null, 'invalid meal kind is rejected');

select throws_ok$$select public.create_meal_photo_draft(
  current_date, 'Asia/Kolkata', 'lunch',
  '31111117-1111-7777-8777-111111111111',
  '22222222-2222-7777-8777-222222222222/meal/other.jpg',
  'image/jpeg', 1024000,
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
)$$, '22023', null, 'object path not owned by user is rejected');

select throws_ok$$select public.create_meal_photo_draft(
  current_date, 'Asia/Kolkata', 'lunch',
  '41111117-1111-7777-8777-111111111111',
  '11111111-1111-7777-8777-111111111111/meal/photo_003.bmp',
  'image/bmp', 1024000,
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
)$$, '22023', null, 'unsupported content type is rejected');

select throws_ok$$select public.create_meal_photo_draft(
  current_date, 'Asia/Kolkata', 'lunch',
  '51111117-1111-7777-8777-111111111111',
  '11111111-1111-7777-8777-111111111111/meal/photo_004.jpg',
  'image/jpeg', 0,
  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
)$$, '22023', null, 'zero byte size is rejected');

set local "request.jwt.claim.sub" = '22222222-2222-7777-8777-222222222222';
select is((select count(*) from public.meals), 0::bigint,
  'cross-user sees no meals');

select throws_ok(format($$select public.confirm_analyzed_meal(
  %L, '[{"id":"00000000-0000-0000-0000-000000000000","name":"Test","serving_label":"1 serving"}]'::jsonb)$$,
  (select json->>'meal_id' from draft)),
  'P0002', 'meal not found',
  'cross-user cannot confirm another meal');

set local "request.jwt.claim.sub" = '11111111-1111-7777-8777-111111111111';

select throws_ok(format($$select public.confirm_analyzed_meal(
  %L, '[]'::jsonb)$$,
  (select json->>'meal_id' from draft)),
  '22023', null,
  'empty candidate payload is rejected');

select throws_ok(format($$select public.confirm_analyzed_meal(
  %L, '[{"id":"00000000-0000-0000-0000-000000000000","name":"","serving_label":"1"}]'::jsonb)$$,
  (select json->>'meal_id' from draft)),
  '23514', null,
  'empty candidate name is rejected');

reset role;
insert into public.nutrition_schedule_versions(
  id, user_id, version_number, status, title, rationale, approved_at, effective_date)
values(
  '11111111-8111-7777-8777-111111111111', '11111111-1111-7777-8777-111111111111',
  1, 'active', 'Schedule', 'Approved', now(), current_date);

insert into public.nutrition_schedule_items(
  id, user_id, schedule_version_id, item_order, slot_key, label, local_time,
  window_minutes, foods)
values(
  '11111111-9111-7777-8777-111111111111', '11111111-1111-7777-8777-111111111111',
  '11111111-8111-7777-8777-111111111111', 1, 'pre_workout', 'Pre-workout',
  '07:45', 60, '[{"name":"Oats","quantity":"60 g"}]'::jsonb);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-7777-8777-111111111111';

select lives_ok$$select public.save_scheduled_manual_meal(
  current_date, 'Asia/Kolkata', 'pre_workout',
  '61111117-1111-7777-8777-111111111111',
  '[{"name":"Banana","serving_label":"1 medium","calories":105,"protein_g":1,"carbohydrate_g":27,"fat_g":0}]'::jsonb,
  '11111111-9111-7777-8777-111111111111', '')$$,
  'scheduled manual meal is saved');

select is((select count(*) from public.meals
  where nutrition_schedule_item_id = '11111111-9111-7777-8777-111111111111'), 1::bigint,
  'scheduled meal links to schedule item');

select throws_ok(format($$select public.save_scheduled_manual_meal(
  current_date, 'Asia/Kolkata', 'pre_workout',
  '71111117-1111-7777-8777-111111111111',
  '[{"name":"Banana","serving_label":"1"}]'::jsonb,
  '00000000-0000-0000-0000-000000000000', '')$$),
  'P0002', null, 'nonexistent schedule item is rejected');

select * from finish();
rollback;
