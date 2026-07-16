begin;
select plan(28);

select has_table('public'::name, 'physique_analyses'::name, 'physique_analyses table exists');
select has_column('public'::name, 'physique_analyses'::name, 'qualitative_observations', 'qualitative_observations column exists');
select has_column('public'::name, 'physique_analyses'::name, 'body_fat_range', 'body_fat_range column exists');
select has_column('public'::name, 'physique_analyses'::name, 'confidence', 'confidence column exists');
select has_column('public'::name, 'physique_analyses'::name, 'baseline_photo_set_id', 'baseline FK exists');

select has_index('public'::name, 'physique_analyses'::name, 'physique_analyses_user_date', 'user date index exists');

select ok(
  exists(select 1 from pg_catalog.pg_policies p join pg_catalog.pg_class c on c.oid=p.polrelid where c.relname='physique_analyses' and p.polname='physique_analyses_own_read'),
  'physique_analyses RLS policy enabled'
);

select ok(
  (select relforcerowsecurity from pg_catalog.pg_class where relname='physique_analyses') = true,
  'physique_analyses RLS forced'
);

select has_function('public'::name, 'prepare_coach_chat_v4', ARRAY['uuid','uuid','text','text','uuid','text'], 'prepare_coach_chat_v4(…) exists');

select lives_ok(
  format(
    $$select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1),
      gen_random_uuid(),
      'hello',
      'Asia/Kolkata',
      gen_random_uuid(),
      'general'
    )$$
  ),
  'prepare_coach_chat_v4 returns without error for general kind'
);

select lives_ok(
  format(
    $$select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1),
      gen_random_uuid(),
      'what should I train next',
      'Asia/Kolkata',
      gen_random_uuid(),
      'daily_action'
    )$$
  ),
  'prepare_coach_chat_v4 returns without error for daily_action kind'
);

select lives_ok(
  format(
    $$select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1),
      gen_random_uuid(),
      'change my plan',
      'Asia/Kolkata',
      gen_random_uuid(),
      'plan_change'
    )$$
  ),
  'prepare_coach_chat_v4 returns without error for plan_change kind'
);

select lives_ok(
  format(
    $$select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1),
      gen_random_uuid(),
      'explain my trend',
      'Asia/Kolkata',
      gen_random_uuid(),
      'explain_evidence'
    )$$
  ),
  'prepare_coach_chat_v4 returns without error for explain_evidence kind'
);

select lives_ok(
  format(
    $$select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1),
      gen_random_uuid(),
      'what should I eat',
      'Asia/Kolkata',
      gen_random_uuid(),
      'nutrition_focus'
    )$$
  ),
  'prepare_coach_chat_v4 returns without error for nutrition_focus kind'
);

select lives_ok(
  format(
    $$select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1),
      gen_random_uuid(),
      'I feel sore',
      'Asia/Kolkata',
      gen_random_uuid(),
      'recovery'
    )$$
  ),
  'prepare_coach_chat_v4 returns without error for recovery kind'
);

select lives_ok(
  format(
    $$select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1),
      gen_random_uuid(),
      'hello',
      'Asia/Kolkata',
      gen_random_uuid(),
      null
    )$$
  ),
  'prepare_coach_chat_v4 falls back to general on null kind'
);

select lives_ok(
  format(
    $$select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1),
      gen_random_uuid(),
      'hello',
      'Asia/Kolkata',
      gen_random_uuid(),
      'bogus_kind'
    )$$
  ),
  'prepare_coach_chat_v4 falls back to general on invalid kind'
);

select is(
  (select jsonb_typeof(
    (select public.prepare_coach_chat_v4(
      (select id from auth.users limit 1), gen_random_uuid(), 'change my plan',
      'Asia/Kolkata', gen_random_uuid(), 'plan_change'
    )->'context'->'schema_version')
  )::text, 'string',
  'v4 returns schema_version as string'
);

select ok(
  (select (public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'change my plan',
    'Asia/Kolkata', gen_random_uuid(), 'plan_change'
  )->'context'->>'schema_version') = '3.0',
  'v4 schema_version is 3.0'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'change my plan',
    'Asia/Kolkata', gen_random_uuid(), 'plan_change'
  )->'context' ? 'nutrition_adherence'),
  'plan_change context includes nutrition_adherence'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'change my plan',
    'Asia/Kolkata', gen_random_uuid(), 'plan_change'
  )->'context'->'nutrition_adherence' ? 'days_with_confirmed_meals_7d'),
  'nutrition_adherence includes days_with_confirmed_meals_7d'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'change my plan',
    'Asia/Kolkata', gen_random_uuid(), 'plan_change'
  )->'context'->'nutrition_adherence' ? 'schedule_slot_compliance'),
  'nutrition_adherence includes schedule_slot_compliance'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'change my plan',
    'Asia/Kolkata', gen_random_uuid(), 'plan_change'
  )->'context'->'data_quality' ? 'last_photo_set'),
  'plan_change data_quality includes last_photo_set'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'explain my trend',
    'Asia/Kolkata', gen_random_uuid(), 'explain_evidence'
  )->'context'->'data_quality' ? 'photo_sets_completed'),
  'explain_evidence data_quality includes photo_sets_completed'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'explain my trend',
    'Asia/Kolkata', gen_random_uuid(), 'explain_evidence'
  )->'context'->'data_quality' ? 'has_physique_analysis'),
  'explain_evidence data_quality includes has_physique_analysis'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'explain my trend',
    'Asia/Kolkata', gen_random_uuid(), 'explain_evidence'
  )->'context'->'evidence_freshness' ? 'last_photo_set'),
  'explain_evidence evidence_freshness includes last_photo_set'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'what should I eat',
    'Asia/Kolkata', gen_random_uuid(), 'nutrition_focus'
  )->'context'->'nutrition_compliance_7day' ? 'avg_daily_carbohydrate_g'),
  'nutrition_focus compliance includes avg_daily_carbohydrate_g'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'what should I eat',
    'Asia/Kolkata', gen_random_uuid(), 'nutrition_focus'
  )->'context'->'nutrition_compliance_7day' ? 'avg_daily_fat_g'),
  'nutrition_focus compliance includes avg_daily_fat_g'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'what should I eat',
    'Asia/Kolkata', gen_random_uuid(), 'nutrition_focus'
  )->'context'->'nutrition_compliance_7day' ? 'days_with_meals'),
  'nutrition_focus compliance includes days_with_meals'
);

select ok(
  (select public.prepare_coach_chat_v4(
    (select id from auth.users limit 1), gen_random_uuid(), 'hello',
    'Asia/Kolkata', gen_random_uuid(), 'general'
  )->'context' ? 'today_meal_schedule'),
  'general context includes today_meal_schedule'
);

select finish();
rollback;
