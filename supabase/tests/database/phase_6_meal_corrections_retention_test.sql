begin;
select plan(20);

insert into auth.users(id, role) values
  ('61111111-bbbb-4111-8111-111111111111', 'authenticated'),
  ('62222222-bbbb-4222-8222-222222222222', 'authenticated');

select ok(
  has_function_privilege(
    'authenticated',
    'public.confirm_analyzed_meal(uuid,jsonb)',
    'execute'
  ),
  'authenticated user can confirm corrected candidates'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.confirm_fixture_meal_v2(uuid,jsonb)',
    'execute'
  ),
  'the retired fixture confirmation is closed to the app'
);
select ok(
  has_function_privilege('authenticated', 'public.delete_my_meal(uuid)', 'execute'),
  'authenticated user can delete an owned meal'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.claim_expired_meal_media(integer)',
    'execute'
  ),
  'client cannot claim retention work'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.claim_expired_meal_media(integer)',
    'execute'
  ),
  'service role can claim retention work'
);

insert into public.meals(id, user_id, local_date, timezone, meal_type, source, status, idempotency_key)
values (
  '61111111-cccc-4111-8111-111111111111', '61111111-bbbb-4111-8111-111111111111',
  '2026-07-02', 'Asia/Kolkata', 'lunch', 'fixture_analysis', 'draft',
  '61111111-cccc-4111-8111-111111111111'
);
insert into public.meal_analysis_candidates(
  user_id, meal_id, candidate_order, food_label, serving_label, calories, protein_g,
  carbohydrate_g, fat_g, confidence
) values
  ('61111111-bbbb-4111-8111-111111111111', '61111111-cccc-4111-8111-111111111111',
   1, 'Rice bowl', '1 bowl', 520, 24, 72, 14, 'medium'),
  ('61111111-bbbb-4111-8111-111111111111', '61111111-cccc-4111-8111-111111111111',
   2, 'Greek yogurt', '150 g', 130, 15, 8, 4, 'high');

set local role authenticated;
set local "request.jwt.claim.sub" = '61111111-bbbb-4111-8111-111111111111';

select is(
  (public.get_my_daily_nutrition('2026-07-02') ->> 'calories')::numeric,
  0::numeric,
  'candidate edits remain excluded before confirmation'
);

select lives_ok(
  $$select public.confirm_analyzed_meal(
    '61111111-cccc-4111-8111-111111111111',
    jsonb_build_array(jsonb_build_object(
      'id', (select id from public.meal_analysis_candidates
        where meal_id = '61111111-cccc-4111-8111-111111111111'
        order by candidate_order limit 1),
      'name', 'Chicken rice bowl',
      'serving_label', '420 g',
      'calories', 610,
      'protein_g', 42,
      'carbohydrate_g', 70,
      'fat_g', 18
    ))
  )$$,
  'corrected candidate confirms transactionally'
);
select is(
  (select name_snapshot from public.meal_items
    where meal_id = '61111111-cccc-4111-8111-111111111111'),
  'Chicken rice bowl',
  'confirmed item stores the corrected name snapshot'
);
select is(
  (public.get_my_daily_nutrition('2026-07-02') ->> 'calories')::numeric,
  610::numeric,
  'corrected calories affect totals only after confirmation'
);

set local "request.jwt.claim.sub" = '62222222-bbbb-4222-8222-222222222222';
select is(
  public.delete_my_meal('61111111-cccc-4111-8111-111111111111'),
  true,
  'cross-user deletion returns an idempotent non-disclosing result'
);

set local "request.jwt.claim.sub" = '61111111-bbbb-4111-8111-111111111111';
select is(
  (select count(*) from public.meals where id = '61111111-cccc-4111-8111-111111111111'),
  1::bigint,
  'cross-user deletion does not remove the meal'
);
select is(
  public.delete_my_meal('61111111-cccc-4111-8111-111111111111'),
  true,
  'owner deletion succeeds'
);
select is(
  (public.get_my_daily_nutrition('2026-07-02') ->> 'calories')::numeric,
  0::numeric,
  'deleting a confirmed meal removes it from totals'
);
select is(
  (select count(*) from public.audit_events where action_code = 'meal.deleted'),
  1::bigint,
  'meal deletion emits a sanitized audit event'
);

reset role;
insert into public.media_objects(
  id, user_id, purpose, object_key, content_type, byte_size, checksum,
  retention_deadline, retention_exempt
) values
  (
    '63111111-bbbb-4111-8111-111111111111',
    '61111111-bbbb-4111-8111-111111111111', 'meal_analysis',
    '61111111-bbbb-4111-8111-111111111111/meal/expired.jpg',
    'image/jpeg', 100, repeat('a', 64), now() - interval '1 day', false
  ),
  (
    '63222222-bbbb-4222-8222-222222222222',
    '61111111-bbbb-4111-8111-111111111111', 'meal_analysis',
    '61111111-bbbb-4111-8111-111111111111/meal/saved.jpg',
    'image/jpeg', 100, repeat('b', 64), now() - interval '1 day', true
  );

set local role service_role;
create temporary table claimed_media as
select * from public.claim_expired_meal_media(50);
select is((select count(*) from claimed_media), 1::bigint,
  'retention claims only expired non-exempt media');
select is(
  (select lifecycle_status from public.media_objects
    where id = '63111111-bbbb-4111-8111-111111111111'),
  'pending_deletion',
  'claimed media is locked in pending deletion state'
);
select lives_ok(
  $$select public.complete_meal_media_retention(
    '63111111-bbbb-4111-8111-111111111111', false
  )$$,
  'failed byte deletion is retryable'
);
select is(
  (select lifecycle_status from public.media_objects
    where id = '63111111-bbbb-4111-8111-111111111111'),
  'active',
  'failed deletion returns metadata to active state'
);

reset role;
update public.media_objects
set retention_deadline = now() - interval '1 minute'
where id = '63111111-bbbb-4111-8111-111111111111';
set local role service_role;
select public.claim_expired_meal_media(1);
select lives_ok(
  $$select public.complete_meal_media_retention(
    '63111111-bbbb-4111-8111-111111111111', true
  )$$,
  'successful byte deletion finalizes metadata'
);
select is(
  (select lifecycle_status from public.media_objects
    where id = '63111111-bbbb-4111-8111-111111111111'),
  'deleted',
  'successful retention cleanup tombstones media metadata'
);

select * from finish();
rollback;
