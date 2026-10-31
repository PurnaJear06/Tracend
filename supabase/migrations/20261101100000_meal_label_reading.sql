-- Meal photos read packaged products and nutrition labels (2026-11-01) ----------------------------
--
-- On the AI gateway path (Claude) meal-analyze now asks the model what kind of photo it is
-- (a plate, the front of a pack, a nutrition label) and, for a pack or a label, to copy what is
-- printed. Deterministic code (supabase/functions/_shared/meal_vision/packaged.ts) checks the
-- label's arithmetic, works out per-gram values and the portions, and sets the confidence from
-- the source: a label that passes its checks is "label" (high), one that does not is
-- "label_unverified" (low), a front of pack or a plate is "estimate" (never high). The model's
-- assumptions and clarification question, dropped until now, are kept for the review sheet.
-- The athlete still edits and confirms every value through confirm_analyzed_meal, unchanged.
--
-- Additive only:
--   * meal_analysis_candidates gains nullable or defaulted columns. Rows written before this
--     migration keep nulls and empty defaults; the installed app selects named columns, so it
--     never sees them.
--   * persist_meal_photo_candidates is its latest definition (20261015120011) with only two
--     hunks: the insert writes the new columns (a key the deployed function does not send is
--     null or empty, so it keeps working through the deploy), and the audit event records the
--     image kind and schema version 2 (pinned by meal_label_reading_test.ts). Same signature,
--     security definer, search_path '' and grants.
--   * private.jsonb_text_array: a JSON array of strings as text[], empty for anything else.
--
-- No RPC returns these rows to the app (it reads the table under its RLS policy), so no
-- schema_version of an RPC changes. The meal-analyze reply moves to schema_version 1.1.

-- 1. Columns ---------------------------------------------------------------------------------

alter table public.meal_analysis_candidates
  add column source text
    constraint meal_analysis_candidates_source_check
    check (source in ('label', 'label_unverified', 'estimate')),
  add column image_kind text
    constraint meal_analysis_candidates_image_kind_check
    check (image_kind in ('plate', 'pack_front', 'nutrition_label')),
  add column brand text not null default ''
    constraint meal_analysis_candidates_brand_check check (length(brand) <= 80),
  add column kcal_per_g numeric(7,4)
    constraint meal_analysis_candidates_kcal_per_g_check check (kcal_per_g between 0 and 10),
  add column protein_per_g numeric(5,4)
    constraint meal_analysis_candidates_protein_per_g_check check (protein_per_g between 0 and 1),
  add column carbohydrate_per_g numeric(5,4)
    constraint meal_analysis_candidates_carbohydrate_per_g_check
    check (carbohydrate_per_g between 0 and 1),
  add column fat_per_g numeric(5,4)
    constraint meal_analysis_candidates_fat_per_g_check check (fat_per_g between 0 and 1),
  add column serving_g numeric(7,2)
    constraint meal_analysis_candidates_serving_g_check check (serving_g > 0 and serving_g <= 5000),
  add column servings_per_pack numeric(6,2)
    constraint meal_analysis_candidates_servings_per_pack_check
    check (servings_per_pack > 0 and servings_per_pack <= 1000),
  add column pack_g numeric(7,2)
    constraint meal_analysis_candidates_pack_g_check check (pack_g > 0 and pack_g <= 10000),
  add column portion_g numeric(7,2)
    constraint meal_analysis_candidates_portion_g_check check (portion_g > 0 and portion_g <= 10000),
  add column assumptions text[] not null default '{}'
    constraint meal_analysis_candidates_assumptions_check check (
      cardinality(assumptions) <= 8 and length(array_to_string(assumptions, '')) <= 1600),
  add column question text not null default ''
    constraint meal_analysis_candidates_question_check check (length(question) <= 500),
  add column label_issues text[] not null default '{}'
    constraint meal_analysis_candidates_label_issues_check check (label_issues <@ array[
      'energy_mismatch', 'basis_mismatch', 'pack_mismatch', 'energy_not_printed',
      'serving_size_missing', 'values_implausible', 'values_not_printed']::text[]),
  -- Per-gram values come as a set, and the stored values of a portion need them.
  add constraint meal_analysis_candidates_per_gram_complete check (
    (kcal_per_g is null) = (protein_per_g is null)
    and (kcal_per_g is null) = (carbohydrate_per_g is null)
    and (kcal_per_g is null) = (fat_per_g is null)
    and (portion_g is null or kcal_per_g is not null)),
  -- "From label" only ever describes a nutrition label.
  add constraint meal_analysis_candidates_label_source_check check (
    source is null or source = 'estimate' or image_kind = 'nutrition_label');

comment on column public.meal_analysis_candidates.source is
  'label: printed values that passed the arithmetic checks; label_unverified: printed values that '
  'did not (label_issues names each); estimate: the model''s estimate. Null before 2026-11-01.';
comment on column public.meal_analysis_candidates.portion_g is
  'The grams the stored values are for when they come from the per-gram values.';

-- 2. A JSON array of strings as text[] --------------------------------------------------------

-- CASE tests its branches in order, so the elements are only read from an array.
create function private.jsonb_text_array(value jsonb)
returns text[] language sql immutable set search_path = '' as $$
  select case
    when coalesce(jsonb_typeof(value), '') <> 'array' then '{}'::text[]
    when exists (select 1 from jsonb_array_elements(value) item where jsonb_typeof(item) <> 'string')
      then '{}'::text[]
    else array(select item from jsonb_array_elements_text(value) with ordinality as t(item, position)
      order by position)
  end;
$$;
revoke all on function private.jsonb_text_array(jsonb) from public, anon, authenticated;

-- 3. persist_meal_photo_candidates -----------------------------------------------------------

-- From 20261015120011.
create or replace function public.persist_meal_photo_candidates(
  target_user_id uuid,target_meal_id uuid,candidates jsonb,run_provider text,run_model text
) returns integer language plpgsql security definer set search_path='' as $$
declare meal public.meals%rowtype; item jsonb; item_count integer:=0;
begin
  select * into meal from public.meals where id=target_meal_id and user_id=target_user_id for update;
  if not found then raise exception 'meal not found' using errcode='P0002'; end if;
  if meal.source<>'photo_analysis' or meal.status<>'draft' or jsonb_typeof(candidates)<>'array'
    or jsonb_array_length(candidates) not between 1 and 20 or
    not ((run_provider='gemini' and run_model='gemini-3.5-flash') or
      (run_provider='groq' and run_model in ('qwen/qwen3.6-27b','qwen/qwen3.8-27b')) or
      (run_provider = 'anthropic'
        and run_model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$'))
  then raise exception 'invalid meal analysis' using errcode='22023'; end if;
  delete from public.meal_analysis_candidates where meal_id=target_meal_id;
  for item in select value from jsonb_array_elements(candidates) loop
    item_count:=item_count+1;
    insert into public.meal_analysis_candidates(user_id,meal_id,candidate_order,food_label,serving_label,calories,protein_g,carbohydrate_g,fat_g,confidence,
      source,image_kind,brand,kcal_per_g,protein_per_g,carbohydrate_per_g,fat_per_g,serving_g,servings_per_pack,pack_g,portion_g,assumptions,question,label_issues)
    values(target_user_id,target_meal_id,item_count,item->>'name',item->>'serving_label',(item->>'calories')::numeric,(item->>'protein_g')::numeric,(item->>'carbohydrate_g')::numeric,(item->>'fat_g')::numeric,item->>'confidence',
      item->>'source',item->>'image_kind',coalesce(item->>'brand',''),(item->>'kcal_per_g')::numeric,(item->>'protein_per_g')::numeric,(item->>'carbohydrate_per_g')::numeric,(item->>'fat_per_g')::numeric,
      (item->>'serving_g')::numeric,(item->>'servings_per_pack')::numeric,(item->>'pack_g')::numeric,(item->>'portion_g')::numeric,
      private.jsonb_text_array(item->'assumptions'),coalesce(item->>'question',''),private.jsonb_text_array(item->'label_issues'));
  end loop;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(target_user_id,'meal.photo.candidates_created','meal',target_meal_id,'succeeded',jsonb_build_object('candidate_count',item_count,'provider',run_provider,'model',run_model,
      'schema_version',2,'image_kind',candidates->0->>'image_kind'));
  return item_count;
end $$;

revoke all on function public.persist_meal_photo_candidates(uuid, uuid, jsonb, text, text)
from public, anon, authenticated;
grant execute on function public.persist_meal_photo_candidates(uuid, uuid, jsonb, text, text)
to service_role;
