begin;
select plan(21);

insert into auth.users(id,role) values
 ('11111111-bbbb-4111-8111-111111111111','authenticated'),
 ('22222222-bbbb-4222-8222-222222222222','authenticated');

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid=any(array[
 'public.user_foods'::regclass,'public.media_objects'::regclass,'public.meals'::regclass,
 'public.meal_analysis_candidates'::regclass,'public.meal_items'::regclass])),
 'nutrition tables enable and force RLS');
select ok(not has_table_privilege('authenticated','public.meals','insert'),
 'mobile cannot directly insert meals');
select ok(has_function_privilege('authenticated','public.save_manual_meal(date,text,text,uuid,jsonb,text)','execute'),
 'authenticated owner can save a manual meal');
select ok(has_function_privilege('authenticated','public.confirm_fixture_meal(uuid,uuid[])','execute'),
 'authenticated owner can confirm selected fixture candidates');
select is((select public from storage.buckets where id='meal-images'),false,
 'meal image bucket is private');
select is((select file_size_limit from storage.buckets where id='meal-images'),10485760::bigint,
 'meal image bucket has a ten megabyte limit');
select is((select count(*) from pg_policies where schemaname='storage' and tablename='objects'
 and policyname in ('meal_images_insert_own','meal_images_read_own','meal_images_delete_own')),3::bigint,
 'meal image storage has scoped insert read and delete policies');

set local role authenticated;
set local "request.jwt.claim.sub"='11111111-bbbb-4111-8111-111111111111';
create temporary table manual_result as select public.save_manual_meal(
 '2026-07-02','Asia/Kolkata','breakfast','31111111-bbbb-4111-8111-111111111111',
 '[{"name":"Oats","serving_label":"80 g","calories":300,"protein_g":12,"carbohydrate_g":52,"fat_g":6}]'::jsonb,'') id;
select is((select count(*) from public.meals where status='confirmed'),1::bigint,
 'manual meal is confirmed transactionally');
select is((public.get_my_daily_nutrition('2026-07-02')->>'calories')::numeric,300::numeric,
 'confirmed manual item contributes to daily calories');
select is((public.get_my_daily_nutrition('2026-07-02')->>'confirmed_meals')::integer,1,
 'confirmed meal count is deterministic');
select lives_ok($$select public.save_manual_meal(
 '2026-07-02','Asia/Kolkata','breakfast','31111111-bbbb-4111-8111-111111111111',
 '[{"name":"Ignored replay","serving_label":"1","calories":1,"protein_g":1,"carbohydrate_g":1,"fat_g":1}]'::jsonb,'')$$,
 'manual meal retry is idempotent');
select is((select count(*) from public.meals),1::bigint,'manual replay does not duplicate meal');

create temporary table fixture_result as select public.create_fixture_meal(
 '2026-07-02','Asia/Kolkata','lunch','41111111-bbbb-4111-8111-111111111111') id;
select is((select count(*) from public.meal_analysis_candidates),2::bigint,
 'fixture analysis creates editable candidates');
select is((public.get_my_daily_nutrition('2026-07-02')->>'calories')::numeric,300::numeric,
 'unconfirmed candidates never affect totals');
select lives_ok($$select public.confirm_fixture_meal(
 (select id from fixture_result),
 array[(select id from public.meal_analysis_candidates where meal_id=(select id from fixture_result) order by candidate_order limit 1)])$$,
 'selected candidate confirms transactionally');
select is((public.get_my_daily_nutrition('2026-07-02')->>'calories')::numeric,820::numeric,
 'only the confirmed selected candidate affects totals');
select is((select count(*) from public.audit_events where action_code like 'meal.%'),2::bigint,
 'meal confirmations emit sanitized audit events');

set local "request.jwt.claim.sub"='22222222-bbbb-4222-8222-222222222222';
select is((select count(*) from public.meals),0::bigint,'cross-user meal reads are denied');
select is((public.get_my_daily_nutrition('2026-07-02')->>'calories')::numeric,0::numeric,
 'cross-user totals are empty');
select throws_ok(format('select public.confirm_fixture_meal(%L, array[]::uuid[])',
 (select id from fixture_result)),'P0002','meal not found','cross-user confirmation is denied');

set local "request.jwt.claim.sub"='11111111-bbbb-4111-8111-111111111111';
select throws_ok($$select public.save_manual_meal('2026-07-02','Asia/Kolkata','breakfast',
 '51111111-bbbb-4111-8111-111111111111','[]'::jsonb,'')$$,'22023','invalid meal',
 'empty manual item list is rejected');

select * from finish();
rollback;
