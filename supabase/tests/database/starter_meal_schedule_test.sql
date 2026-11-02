begin;
select plan(32);

-- Approving nutrition targets gives an athlete with no meal schedule a starting one
-- (20261102224851_starter_meal_schedule.sql): four slots with the approved calories and protein
-- split between them, refreshed in place while it is still the starter, and never replacing a
-- schedule the athlete or the owner confirmed.

create temporary table payload as select
  '{"title":"Foundation block","block_weeks":6,"sessions_per_week":2,"split":"full_body",
    "origin":"ai","provider":"deepseek","model":"deepseek-flash","policy_version":"onboarding-policy-v1",
    "prescription":{"strategy":"foundation_block","review_after_weeks":2},
    "weekly_structure":[
      {"workout_order":1,"name":"Full body A","objective":"Squat and press","preferred_weekday":2,
       "estimated_minutes":40,"warm_up_guidance":"Easy movement","cool_down_guidance":"Walk",
       "exercises":[
         {"exercise_order":1,"slug":"goblet-squat","name":"Goblet squat","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""},
         {"exercise_order":2,"slug":"one-arm-dumbbell-row","name":"One-arm dumbbell row","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""}]},
      {"workout_order":2,"name":"Full body B","objective":"Hinge and press","preferred_weekday":5,
       "estimated_minutes":40,"warm_up_guidance":"Easy movement","cool_down_guidance":"Walk",
       "exercises":[
         {"exercise_order":1,"slug":"dumbbell-romanian-deadlift","name":"Dumbbell Romanian deadlift","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""},
         {"exercise_order":2,"slug":"dumbbell-floor-press","name":"Dumbbell floor press","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""}]}]}'::jsonb training,
  '{"calories":2100,"protein_g":140,"carbohydrate_g":235,"fat_g":65,"rationale":"Middle of the range"}'::jsonb nutrition,
  '{"schema_version":"2.0","answers":{"goal":"muscle_gain","experience":"beginner","sex":"female",
    "birth_year":1992,"height_cm":165,"weight_kg":62.5,"target_weight_kg":65,"daily_activity":"some_standing",
    "training_weekdays":[2,5],"session_minutes":45,"equipment_items":["dumbbells"],
    "limitations":"","nutrition_context":"Vegetarian"}}'::jsonb snapshot;
grant select on payload to authenticated;

create function pg_temp.athlete(uid uuid) returns void language plpgsql as $$
begin
  insert into auth.users(id, role) values (uid, 'authenticated');
  insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level,
    training_days, session_minutes)
  values (uid, now(), true, 'beginner', array[2,5]::smallint[], 45);
  insert into public.consent_records(user_id, consent_type, notice_version, action, source) values
    (uid, 'terms', '2026-07-01', 'granted', 'ios_app'),
    (uid, 'privacy', '2026-07-01', 'granted', 'ios_app');
  insert into public.onboarding_drafts(user_id, path, current_section, payload)
  values (uid, 'beginner', 'review', '{}');
  insert into public.user_goals(user_id, goal_type, priority, status)
  values (uid, 'recomposition', 1, 'draft');
end $$;

-- A stored proposal with these nutrition targets for an athlete at the Review step.
create function pg_temp.proposal(uid uuid, hash text, nutrition jsonb) returns uuid language plpgsql as $$
declare claim jsonb := public.claim_onboarding_generation(uid, hash, 140);
begin
  perform public.persist_onboarding_proposal_v3((claim ->> 'generation_id')::uuid, uid, hash,
    (select snapshot from payload), (select training from payload), nutrition, '[]',
    'Why', 'Benefit', 'Downside', 'medium', null);
  return (select proposal_id from public.onboarding_generations
    where id = (claim ->> 'generation_id')::uuid);
end $$;

select pg_temp.athlete(('c1000000-0000-4000-8000-00000000000' || n)::uuid) from generate_series(1, 5) n;
create temporary table p(name text primary key, id uuid);
grant all on p to authenticated;
create temporary table before_refresh(slot_key text, id uuid);
grant all on before_refresh to authenticated;

-- 1. A new athlete has no schedule, then approval gives them one ---------------------------------

insert into p select 'one', pg_temp.proposal('c1000000-0000-4000-8000-000000000001', repeat('1', 64),
  (select nutrition from payload));
set local role authenticated;
set local "request.jwt.claim.sub" = 'c1000000-0000-4000-8000-000000000001';
select is(jsonb_array_length(public.get_my_nutrition_schedule(current_date) -> 'items'), 0,
  'before approval there is no schedule');
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'one'), 'accept') ->> 'status',
  'accepted', 'the athlete approves the plan');
select is(public.get_my_nutrition_schedule(current_date) -> 'version' ->> 'title', 'Starting meal schedule',
  'the plan comes with a starting schedule, labelled as one');
select is(public.get_my_nutrition_schedule(current_date) ->> 'schema_version', '1.0',
  'read at the schedule contract version it always had');
select is((select array_agg(i ->> 'slot_key' order by (i ->> 'order')::integer)
    from jsonb_array_elements(public.get_my_nutrition_schedule(current_date) -> 'items') i),
  array['breakfast', 'lunch', 'snack', 'dinner'], 'breakfast, lunch, a snack and dinner');
select is((select array_agg(i ->> 'local_time' order by (i ->> 'order')::integer)
    from jsonb_array_elements(public.get_my_nutrition_schedule(current_date) -> 'items') i),
  array['08:00', '13:00', '16:30', '19:30'], 'spread across the day');
select is((select array_agg(i -> 'foods' -> 0 ->> 'quantity' order by (i ->> 'order')::integer)
    from jsonb_array_elements(public.get_my_nutrition_schedule(current_date) -> 'items') i),
  array['about 530 kcal and 35 g protein', 'about 630 kcal and 40 g protein',
    'about 320 kcal and 20 g protein', 'about 630 kcal and 40 g protein'],
  'with the approved calories and protein split between them');
select is((select array_agg(i ->> 'optional' order by (i ->> 'order')::integer)
    from jsonb_array_elements(public.get_my_nutrition_schedule(current_date) -> 'items') i),
  array['false', 'false', 'true', 'false'], 'the snack is optional');
select ok(not (select bool_or((i ->> 'reminder_enabled')::boolean)
    from jsonb_array_elements(public.get_my_nutrition_schedule(current_date) -> 'items') i),
  'no reminders until the athlete turns them on');
select ok(public.get_my_daily_brief(current_date) ? 'next_meal', 'the daily brief can name a next meal');
reset role;
select is((select count(*)::integer from public.nutrition_schedule_versions
    where user_id = 'c1000000-0000-4000-8000-000000000001' and status = 'active' and starter), 1,
  'one active version, marked as the starter');
select is((select count(*)::integer from public.audit_events
    where user_id = 'c1000000-0000-4000-8000-000000000001' and action_code = 'nutrition.schedule.activated'
      and (metadata ->> 'starter')::boolean), 1, 'and the creation is audited');

-- 2. A new target refreshes the amounts in place --------------------------------------------------

insert into before_refresh
select slot_key, id from public.nutrition_schedule_items
where user_id = 'c1000000-0000-4000-8000-000000000001';
with m as (
  insert into public.meals(user_id, local_date, timezone, meal_type, source, status, idempotency_key,
    confirmed_at, nutrition_schedule_item_id)
  select user_id, current_date, 'UTC', 'lunch', 'manual', 'confirmed', gen_random_uuid(), now(), id
  from public.nutrition_schedule_items
  where user_id = 'c1000000-0000-4000-8000-000000000001' and slot_key = 'lunch'
  returning id)
insert into public.meal_items(user_id, meal_id, name_snapshot, serving_label, calories, protein_g,
  carbohydrate_g, fat_g, confirmed_at)
select 'c1000000-0000-4000-8000-000000000001', m.id, 'Food', '1 serving', 600, 40, 60, 20, now() from m;
insert into p select 'one_again', pg_temp.proposal('c1000000-0000-4000-8000-000000000001', repeat('2', 64),
  '{"calories":2400,"protein_g":160,"carbohydrate_g":260,"fat_g":70,"rationale":"Higher"}'::jsonb);
set local role authenticated;
set local "request.jwt.claim.sub" = 'c1000000-0000-4000-8000-000000000001';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'one_again'), 'accept') ->> 'status',
  'accepted', 'a second approval, with higher targets');
select is((select array_agg(i -> 'foods' -> 0 ->> 'quantity' order by (i ->> 'order')::integer)
    from jsonb_array_elements(public.get_my_nutrition_schedule(current_date) -> 'items') i),
  array['about 600 kcal and 40 g protein', 'about 720 kcal and 50 g protein',
    'about 360 kcal and 25 g protein', 'about 720 kcal and 50 g protein'],
  'refreshes the amounts');
select is((select count(*)::integer from public.nutrition_schedule_versions), 1,
  'in the same version');
select is((select count(*)::integer from public.nutrition_schedule_items i
    join before_refresh b on b.id = i.id and b.slot_key = i.slot_key), 4,
  'and the same slots');
select is((select i ->> 'status' from jsonb_array_elements(public.get_my_nutrition_schedule(current_date) -> 'items') i
    where i ->> 'slot_key' = 'lunch'), 'logged', 'so a meal already logged keeps its slot');
reset role;

-- 3. A schedule that is not the starter is never touched -------------------------------------------

insert into public.nutrition_schedule_versions(id, user_id, version_number, status, title, rationale,
  approved_at, effective_date)
values ('c1100000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002', 1, 'active',
  'Confirmed schedule', 'Confirmed by the athlete', now(), current_date);
insert into public.nutrition_schedule_items(user_id, schedule_version_id, item_order, slot_key, label,
  local_time, foods)
values ('c1000000-0000-4000-8000-000000000002', 'c1100000-0000-4000-8000-000000000002', 1, 'lunch',
  'Lunch', '12:30', '[{"name":"Rice","quantity":"200 g"}]');
insert into p select 'two', pg_temp.proposal('c1000000-0000-4000-8000-000000000002', repeat('3', 64),
  (select nutrition from payload));
set local role authenticated;
set local "request.jwt.claim.sub" = 'c1000000-0000-4000-8000-000000000002';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'two'), 'accept') ->> 'status',
  'accepted', 'an athlete with a confirmed schedule approves a plan');
select is(public.get_my_nutrition_schedule(current_date) -> 'version' ->> 'title', 'Confirmed schedule',
  'their schedule is still the active one');
select is((public.get_my_nutrition_schedule(current_date) -> 'items' -> 0 -> 'foods' -> 0) ->> 'quantity', '200 g',
  'with its foods unchanged');
reset role;
select is((select count(*)::integer from public.nutrition_schedule_versions
    where user_id = 'c1000000-0000-4000-8000-000000000002'), 1, 'and no second version');

-- 4. Targets that were not approved start nothing --------------------------------------------------

insert into public.nutrition_target_sets(user_id, version_number, status, calories, protein_g,
  carbohydrate_g, fat_g, rationale, approved_at, effective_date)
values ('c1000000-0000-4000-8000-000000000003', 1, 'active', 2200, 150, 240, 70, 'Written directly',
  now(), current_date);
select is((select count(*)::integer from public.nutrition_schedule_versions
    where user_id = 'c1000000-0000-4000-8000-000000000003'), 0,
  'a target set with no approved proposal behind it creates no schedule');

-- 5. A rejected plan creates nothing ----------------------------------------------------------------

insert into p select 'four', pg_temp.proposal('c1000000-0000-4000-8000-000000000004', repeat('4', 64),
  (select nutrition from payload));
set local role authenticated;
set local "request.jwt.claim.sub" = 'c1000000-0000-4000-8000-000000000004';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'four'), 'reject') ->> 'status',
  'rejected', 'the athlete rejects the plan');
select is(jsonb_array_length(public.get_my_nutrition_schedule(current_date) -> 'items'), 0,
  'and has no schedule');
reset role;

-- 6. Reach and shape ---------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c1000000-0000-4000-8000-000000000005';
select is((select count(*)::integer from public.nutrition_schedule_versions
    where user_id = 'c1000000-0000-4000-8000-000000000001'), 0, 'another athlete cannot read the schedule');
reset role;
select ok(not has_function_privilege('authenticated', 'private.starter_schedule_items(integer, integer)', 'execute'),
  'the split is private');
select ok(not has_function_privilege('authenticated', 'private.sync_starter_meal_schedule()', 'execute'),
  'and so is the trigger function');
select is(to_regprocedure('public.activate_my_nutrition_schedule(text, text, date, jsonb)'), null,
  'no function replaces a schedule from raw JSON');
select lives_ok($$insert into public.nutrition_schedule_items(user_id, schedule_version_id, item_order,
    slot_key, label, local_time, foods)
  select user_id, id, 5, 'breakfast', 'Breakfast', '08:00', '[{"name":"x","quantity":"1"}]'
  from public.nutrition_schedule_versions where id = 'c1100000-0000-4000-8000-000000000002'$$,
  'breakfast is a slot name the table accepts');
select throws_ok($$insert into public.nutrition_schedule_items(user_id, schedule_version_id, item_order,
    slot_key, label, local_time, foods)
  select user_id, id, 6, 'brunch', 'Brunch', '10:00', '[{"name":"x","quantity":"1"}]'
  from public.nutrition_schedule_versions where id = 'c1100000-0000-4000-8000-000000000002'$$,
  '23514', null, 'and any other name is still refused');
select is((select jsonb_array_length(private.starter_schedule_items(1000, 30))), 4,
  'the smallest targets still split into four slots');
select is(private.starter_schedule_items(1000, 30) -> 2 -> 'foods' -> 0 ->> 'quantity',
  'about 150 kcal and 5 g protein', 'with no slot rounded to nothing');

select * from finish();
rollback;
