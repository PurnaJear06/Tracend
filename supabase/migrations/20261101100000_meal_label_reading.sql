-- Meal photos read packaged products and nutrition labels (2026-11-01) ----------------------------
--
-- On the AI gateway path (Claude) meal-analyze now asks the model what kind of photo it is
-- (a plate, the front of a pack, a nutrition label) and, for a pack or a label, to copy what is
-- printed. Deterministic code (supabase/functions/_shared/meal_vision/packaged.ts) checks the
-- label's arithmetic, works out per-unit values (per gram, or per ml for a drink) and the
-- portions, and sets the confidence from the source: a label that passes its checks is "label"
-- (high), one that does not, or that is printed per ml, is "label_unverified" (low), a front of
-- pack or a plate is "estimate" (never high). The model's assumptions and clarification
-- question, dropped until now, are kept for the review sheet. Millilitres are never stored or
-- shown as grams: quantity_unit says which unit the sizes and per-unit values are in.
--
-- Additive only:
--   * meal_analysis_candidates gains nullable or defaulted columns. Rows written before this
--     migration keep nulls and empty defaults; the installed app selects named columns, so it
--     never sees them.
--   * persist_meal_photo_candidates is its latest definition (20261015120011) with only two
--     hunks: the insert writes the new columns (a key the deployed function does not send is
--     null or empty, so it keeps working through the deploy), and the audit event records the
--     image kind and schema version 2.
--   * confirm_analyzed_meal is its latest definition (20260704150000) with one hunk: the
--     candidate's portion_size becomes the portion the athlete confirmed (the app sends it when
--     the values are a chosen portion), or null when the payload has none, as from an older app
--     or after the athlete typed the values; a stored default never outlives a change.
--   * Both keep their signature, security definer, search_path '' and grants, and are pinned by
--     meal-analyze/meal_label_reading_test.ts.
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
  add column quantity_unit text
    constraint meal_analysis_candidates_quantity_unit_check check (quantity_unit in ('g', 'ml')),
  add column kcal_per_unit numeric(7,4)
    constraint meal_analysis_candidates_kcal_per_unit_check check (kcal_per_unit between 0 and 10),
  add column protein_per_unit numeric(5,4)
    constraint meal_analysis_candidates_protein_per_unit_check
    check (protein_per_unit between 0 and 1),
  add column carbohydrate_per_unit numeric(5,4)
    constraint meal_analysis_candidates_carbohydrate_per_unit_check
    check (carbohydrate_per_unit between 0 and 1),
  add column fat_per_unit numeric(5,4)
    constraint meal_analysis_candidates_fat_per_unit_check check (fat_per_unit between 0 and 1),
  add column serving_size numeric(7,2)
    constraint meal_analysis_candidates_serving_size_check
    check (serving_size > 0 and serving_size <= 5000),
  add column servings_per_pack numeric(6,2)
    constraint meal_analysis_candidates_servings_per_pack_check
    check (servings_per_pack > 0 and servings_per_pack <= 1000),
  add column pack_size numeric(7,2)
    constraint meal_analysis_candidates_pack_size_check check (pack_size > 0 and pack_size <= 10000),
  add column portion_size numeric(7,2)
    constraint meal_analysis_candidates_portion_size_check
    check (portion_size > 0 and portion_size <= 10000),
  add column assumptions text[] not null default '{}'
    constraint meal_analysis_candidates_assumptions_check check (
      cardinality(assumptions) <= 8 and length(array_to_string(assumptions, '')) <= 1600),
  add column question text not null default ''
    constraint meal_analysis_candidates_question_check check (length(question) <= 500),
  add column label_issues text[] not null default '{}'
    constraint meal_analysis_candidates_label_issues_check check (label_issues <@ array[
      'energy_mismatch', 'basis_mismatch', 'pack_mismatch', 'energy_not_printed',
      'serving_size_missing', 'values_implausible', 'values_not_printed',
      'volume_basis']::text[]),
  -- Per-unit values come as a set, and the stored values of a portion need them.
  add constraint meal_analysis_candidates_per_unit_complete check (
    (kcal_per_unit is null) = (protein_per_unit is null)
    and (kcal_per_unit is null) = (carbohydrate_per_unit is null)
    and (kcal_per_unit is null) = (fat_per_unit is null)
    and (portion_size is null or kcal_per_unit is not null)),
  -- A size or a per-unit value always says its unit.
  add constraint meal_analysis_candidates_unit_named check (
    quantity_unit is not null
    or (kcal_per_unit is null and serving_size is null and pack_size is null
      and portion_size is null)),
  -- "From label" only ever describes a nutrition label, and never one printed per ml.
  add constraint meal_analysis_candidates_label_source_check check (
    source is null or source = 'estimate'
    or (image_kind = 'nutrition_label'
      and (source = 'label_unverified' or quantity_unit is distinct from 'ml')));

comment on column public.meal_analysis_candidates.source is
  'label: printed values that passed the arithmetic checks; label_unverified: printed values that '
  'did not, or are per ml (label_issues names each); estimate: the model''s estimate. Null before '
  '2026-11-01.';
comment on column public.meal_analysis_candidates.quantity_unit is
  'g or ml: the unit of serving_size, pack_size, portion_size and the *_per_unit values.';
comment on column public.meal_analysis_candidates.portion_size is
  'The amount (in quantity_unit) the stored values are for when they come from the per-unit '
  'values: the default portion, then the portion the athlete confirmed, or null.';

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
      source,image_kind,brand,quantity_unit,kcal_per_unit,protein_per_unit,carbohydrate_per_unit,fat_per_unit,serving_size,servings_per_pack,pack_size,portion_size,assumptions,question,label_issues)
    values(target_user_id,target_meal_id,item_count,item->>'name',item->>'serving_label',(item->>'calories')::numeric,(item->>'protein_g')::numeric,(item->>'carbohydrate_g')::numeric,(item->>'fat_g')::numeric,item->>'confidence',
      item->>'source',item->>'image_kind',coalesce(item->>'brand',''),item->>'quantity_unit',(item->>'kcal_per_unit')::numeric,(item->>'protein_per_unit')::numeric,(item->>'carbohydrate_per_unit')::numeric,(item->>'fat_per_unit')::numeric,
      (item->>'serving_size')::numeric,(item->>'servings_per_pack')::numeric,(item->>'pack_size')::numeric,(item->>'portion_size')::numeric,
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

-- 4. confirm_analyzed_meal ---------------------------------------------------------------------

-- From 20260704150000. portion_size must name the per-unit values the row holds: the table's
-- checks refuse a portion without them (23514), so nothing is confirmed with a portion that
-- cannot be recalculated.
create or replace function public.confirm_analyzed_meal(
  target_meal_id uuid,candidate_payload jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare meal public.meals%rowtype; candidate jsonb; candidate_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into meal from public.meals
  where id=target_meal_id and user_id=auth.uid() for update;
  if not found then raise exception 'meal not found' using errcode='P0002'; end if;
  if meal.status='confirmed' then return meal.id; end if;
  if meal.source not in ('fixture_analysis','photo_analysis')
    or jsonb_typeof(candidate_payload)<>'array'
    or jsonb_array_length(candidate_payload) not between 1 and 30
  then raise exception 'invalid confirmation' using errcode='22023'; end if;
  for candidate in select value from jsonb_array_elements(candidate_payload) loop
    begin candidate_id:=(candidate->>'id')::uuid;
    exception when others then raise exception 'invalid candidate' using errcode='22023'; end;
    if length(coalesce(candidate->>'name','')) not between 1 and 120
      or length(coalesce(candidate->>'serving_label','')) not between 1 and 80
    then raise exception 'invalid candidate' using errcode='22023'; end if;
    update public.meal_analysis_candidates set
      food_label=candidate->>'name',serving_label=candidate->>'serving_label',
      calories=(candidate->>'calories')::numeric,
      protein_g=(candidate->>'protein_g')::numeric,
      carbohydrate_g=(candidate->>'carbohydrate_g')::numeric,
      fat_g=(candidate->>'fat_g')::numeric,selected=true,
      portion_size=(candidate->>'portion_size')::numeric
    where id=candidate_id and meal_id=meal.id and user_id=auth.uid();
    if not found then raise exception 'candidate not found' using errcode='P0002'; end if;
  end loop;
  update public.meal_analysis_candidates set selected=false
  where meal_id=meal.id and user_id=auth.uid() and id not in (
    select (value->>'id')::uuid from jsonb_array_elements(candidate_payload));
  insert into public.meal_items(
    user_id,meal_id,name_snapshot,serving_label,calories,protein_g,
    carbohydrate_g,fat_g,confirmed_at)
  select user_id,meal_id,food_label,serving_label,calories,protein_g,
    carbohydrate_g,fat_g,now() from public.meal_analysis_candidates
  where meal_id=meal.id and selected;
  update public.meals set status='confirmed',confirmed_at=now() where id=meal.id;
  update public.media_objects set retention_deadline=least(retention_deadline,now()+interval '30 days')
  where id=meal.media_object_id and user_id=auth.uid() and not retention_exempt;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'meal.analysis.confirmed','meal',meal.id,'succeeded',
    jsonb_build_object('item_count',jsonb_array_length(candidate_payload),
      'schema_version',3,'source',meal.source));
  return meal.id;
end $$;

revoke all on function public.confirm_analyzed_meal(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.confirm_analyzed_meal(uuid, jsonb) to authenticated;
