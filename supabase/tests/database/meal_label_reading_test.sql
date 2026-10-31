begin;

select plan(30);

-- Migration 20261101100000: meal photo candidates keep the source, the image kind, the printed
-- sizes, per-gram values and the model's notes; persist_meal_photo_candidates writes them.

insert into auth.users (id, role) values
  ('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7', 'authenticated'),
  ('d8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8', 'authenticated');

insert into public.meals (
  id, user_id, local_date, timezone, meal_type, source, status, idempotency_key)
values
  ('e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9', 'c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7',
   current_date, 'Asia/Kolkata', 'snack', 'photo_analysis', 'draft',
   'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1'),
  ('f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0', 'c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7',
   current_date, 'Asia/Kolkata', 'lunch', 'photo_analysis', 'draft',
   'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');

-- 1. Columns -----------------------------------------------------------------------------------

select has_column('public'::name, 'meal_analysis_candidates'::name, 'source', 'source column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'image_kind', 'image_kind column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'brand', 'brand column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'kcal_per_g', 'kcal_per_g column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'protein_per_g', 'protein_per_g column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'carbohydrate_per_g', 'carbohydrate_per_g column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'fat_per_g', 'fat_per_g column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'serving_g', 'serving_g column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'servings_per_pack', 'servings_per_pack column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'pack_g', 'pack_g column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'portion_g', 'portion_g column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'assumptions', 'assumptions column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'question', 'question column exists');
select has_column('public'::name, 'meal_analysis_candidates'::name, 'label_issues', 'label_issues column exists');

-- 2. Grants ------------------------------------------------------------------------------------

select ok(has_function_privilege('service_role',
  'public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text)', 'execute'),
  'service_role still persists meal candidates');
select ok(not has_function_privilege('authenticated',
  'public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text)', 'execute'),
  'authenticated still cannot forge meal candidates');
select ok(not has_function_privilege('anon',
  'public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text)', 'execute'),
  'anon cannot persist meal candidates');
select ok(not has_function_privilege('authenticated', 'private.jsonb_text_array(jsonb)', 'execute'),
  'the private helper is not callable by athletes');

-- 3. The Munch label, as meal-analyze stores it (munch_label_golden.json) -------------------------

select is(
  public.persist_meal_photo_candidates('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7',
    'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9',
    '[{"name":"Nestlé Munch Max Nuts","serving_label":"Whole pack (37.4 g)","calories":195.6,
       "protein_g":3.1,"carbohydrate_g":21.5,"fat_g":10.8,"confidence":"high","source":"label",
       "image_kind":"nutrition_label","brand":"Nestlé","kcal_per_g":5.23,"protein_per_g":0.082,
       "carbohydrate_per_g":0.576,"fat_per_g":0.289,"serving_g":18.7,"servings_per_pack":2,
       "pack_g":37.4,"portion_g":37.4,
       "assumptions":["Values copied from the printed nutrition table"],
       "question":"Did you eat the whole bar (2 servings) or half of it?","label_issues":[]}]'::jsonb,
    'anthropic', 'claude-haiku-5-5'),
  1,
  'a label candidate from Claude is saved'
);

select results_eq(
  $$select source, image_kind, brand, kcal_per_g, fat_per_g, serving_g, servings_per_pack,
      pack_g, portion_g, assumptions, question, label_issues
    from public.meal_analysis_candidates where meal_id = 'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9'$$,
  $$values ('label'::text, 'nutrition_label'::text, 'Nestlé'::text, 5.23::numeric,
      0.289::numeric, 18.7::numeric, 2::numeric, 37.4::numeric,
      37.4::numeric, array['Values copied from the printed nutrition table']::text[],
      'Did you eat the whole bar (2 servings) or half of it?'::text, '{}'::text[])$$,
  'the source, sizes, per-gram values and notes are stored'
);

select is(
  (select metadata->>'image_kind' from public.audit_events
   where target_id = 'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9'
     and action_code = 'meal.photo.candidates_created'),
  'nutrition_label',
  'the audit event names the image kind'
);

-- 4. The deployed function's shape still persists (no new keys) -------------------------------

select is(
  public.persist_meal_photo_candidates('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7',
    'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0',
    '[{"name":"Dal","serving_label":"1 bowl","calories":180,"protein_g":9,
       "carbohydrate_g":24,"fat_g":5,"confidence":"low"}]'::jsonb,
    'groq', 'qwen/qwen3.8-27b'),
  1,
  'a candidate without the new keys is saved'
);

select results_eq(
  $$select source, image_kind, brand, kcal_per_g, assumptions, question, label_issues
    from public.meal_analysis_candidates where meal_id = 'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0'$$,
  $$values (null::text, null::text, ''::text, null::numeric, '{}'::text[], ''::text,
      '{}'::text[])$$,
  'its new columns are null or empty'
);

-- 5. The table refuses what code never sends ----------------------------------------------------

select throws_ok(
  $$select public.persist_meal_photo_candidates('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7',
    'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0',
    '[{"name":"Dal","serving_label":"1 bowl","calories":180,"protein_g":9,"carbohydrate_g":24,
       "fat_g":5,"confidence":"high","source":"label","image_kind":"plate"}]'::jsonb,
    'anthropic', 'claude-haiku-5-5')$$,
  '23514', null, '"From label" on a plate is refused'
);

select throws_ok(
  $$select public.persist_meal_photo_candidates('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7',
    'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0',
    '[{"name":"Bar","serving_label":"1 bar","calories":100,"protein_g":1,"carbohydrate_g":10,
       "fat_g":5,"confidence":"low","source":"estimate","image_kind":"pack_front",
       "kcal_per_g":5.2}]'::jsonb,
    'anthropic', 'claude-haiku-5-5')$$,
  '23514', null, 'per-gram values come as a set'
);

select throws_ok(
  $$select public.persist_meal_photo_candidates('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7',
    'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0',
    '[{"name":"Bar","serving_label":"1 bar","calories":100,"protein_g":1,"carbohydrate_g":10,
       "fat_g":5,"confidence":"low","source":"label_unverified","image_kind":"nutrition_label",
       "label_issues":["looks_wrong"]}]'::jsonb,
    'anthropic', 'claude-haiku-5-5')$$,
  '23514', null, 'an issue code cannot name is refused'
);

select throws_ok(
  $$select public.persist_meal_photo_candidates('c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7',
    'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0',
    '[{"name":"Bar","serving_label":"1 bar","calories":100,"protein_g":1,"carbohydrate_g":10,
       "fat_g":5,"confidence":"low","source":"estimate","image_kind":"pack_front",
       "kcal_per_g":12,"protein_per_g":0.1,"carbohydrate_per_g":0.5,"fat_per_g":0.3}]'::jsonb,
    'anthropic', 'claude-haiku-5-5')$$,
  '23514', null, 'more than 10 kcal per gram is refused'
);

select is(private.jsonb_text_array('["a", 1]'::jsonb), '{}'::text[],
  'a list with a non-string is stored as no notes');

-- 6. The athlete reads their own rows, new columns included; nobody else does --------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c7c7c7c7-c7c7-4c7c-8c7c-c7c7c7c7c7c7';

select is(
  (select source || ':' || pack_g::text from public.meal_analysis_candidates
   where meal_id = 'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9'),
  'label:37.40',
  'the owner reads the new columns'
);

set local "request.jwt.claim.sub" = 'd8d8d8d8-d8d8-4d8d-8d8d-d8d8d8d8d8d8';

select is(
  (select count(*) from public.meal_analysis_candidates
   where meal_id = 'e9e9e9e9-e9e9-4e9e-8e9e-e9e9e9e9e9e9'),
  0::bigint,
  'another athlete reads none of them'
);

reset role;

select * from finish();
rollback;
