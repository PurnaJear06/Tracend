begin;
select plan(55);

-- 20261102074318: the healthy-weight floors at onboarding approval, the narrowed direct writes, a
-- missing screening read as unscreened, and the function reach of the app roles. Grants are checked
-- by privilege; behaviour runs as the signed-in role only where it is allowed to call.

create temporary table floors_payload as select
  '{"title":"Foundation block","block_weeks":6,"sessions_per_week":2,"split":"full_body",
    "origin":"rules","policy_version":"onboarding-policy-v2",
    "prescription":{"strategy":"foundation_block","review_after_weeks":2},
    "weekly_structure":[
      {"workout_order":1,"name":"Full body A","objective":"Squat and press","preferred_weekday":1,
       "estimated_minutes":40,"warm_up_guidance":"Easy movement","cool_down_guidance":"Walk",
       "exercises":[
         {"exercise_order":1,"slug":"goblet-squat","name":"Goblet squat","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""},
         {"exercise_order":2,"slug":"one-arm-dumbbell-row","name":"One-arm dumbbell row","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""}]},
      {"workout_order":2,"name":"Full body B","objective":"Hinge and press","preferred_weekday":3,
       "estimated_minutes":40,"warm_up_guidance":"Easy movement","cool_down_guidance":"Walk",
       "exercises":[
         {"exercise_order":1,"slug":"dumbbell-romanian-deadlift","name":"Dumbbell Romanian deadlift","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""},
         {"exercise_order":2,"slug":"dumbbell-floor-press","name":"Dumbbell floor press","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""}]}]}'::jsonb training,
  -- A woman of 165 cm and 45 kg (BMI 16.5) who chose fat loss. Her lower maintenance estimate is
  -- about 1,449 kcal (age 36), and lower every later year, so 1,450 is maintenance and 1,300 a cut.
  '{"schema_version":"2.0","policy_version":"onboarding-policy-v2","answers":{"goal":"fat_loss",
    "experience":"beginner","sex":"female","birth_year":1990,"height_cm":165,"weight_kg":45,
    "target_weight_kg":null,"daily_activity":"mostly_sitting","training_weekdays":[1,3,5],
    "session_minutes":60,"equipment_items":["dumbbells"],"limitations":"",
    "nutrition_context":""}}'::jsonb snapshot;
grant select on floors_payload to authenticated;

create function pg_temp.athlete(uid uuid, screened boolean default true) returns void
language plpgsql as $$
begin
  insert into auth.users(id, role) values (uid, 'authenticated');
  insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level,
    training_days, session_minutes)
  values (uid, now(), true, 'beginner', array[1,3,5]::smallint[], 60);
  insert into public.consent_records(user_id, consent_type, notice_version, action, source) values
    (uid, 'terms', '2026-07-01', 'granted', 'ios_app'),
    (uid, 'privacy', '2026-07-01', 'granted', 'ios_app');
  insert into public.onboarding_drafts(user_id, path, current_section, payload)
  values (uid, 'beginner', 'review', '{}');
  insert into public.user_goals(user_id, goal_type, priority, status)
  values (uid, 'fat_loss', 1, 'draft');
  if screened then
    insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
      outcome)
    values (uid, true, false, false, 'cleared');
  end if;
end $$;

-- Stores a proposal with these answers and calories (the screening check runs at storing too).
create function pg_temp.proposal(uid uuid, hash text, answers jsonb, calories integer)
returns uuid language plpgsql as $$
declare claim jsonb := public.claim_onboarding_generation(uid, hash, 140);
begin
  perform public.persist_onboarding_proposal_v3((claim ->> 'generation_id')::uuid, uid, hash,
    (select snapshot from floors_payload)
      || jsonb_build_object('answers', (select snapshot -> 'answers' from floors_payload) || answers),
    (select training from floors_payload),
    jsonb_build_object('calories', calories, 'protein_g', 100, 'carbohydrate_g', 150, 'fat_g', 45,
      'rationale', 'Test'),
    '[]', 'Why', 'Benefit', 'Downside', 'medium', null);
  return (select proposal_id from public.onboarding_generations
    where id = (claim ->> 'generation_id')::uuid);
end $$;

select pg_temp.athlete(('f1000000-0000-4000-8000-00000000000' || n)::uuid) from generate_series(1, 4) n;
select pg_temp.athlete('f1000000-0000-4000-8000-000000000005', false);
create temporary table p(name text primary key, id uuid);
grant all on p to authenticated;

-- 1. The floor rule, from the answers ------------------------------------------------------------

select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload), '{"calories":1300}'),
  'deficit_near_healthy_floor', 'a cut under BMI 19.5 breaks the floor');
select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload), '{"calories":1450}'),
  null, 'maintenance under BMI 19.5 does not');
select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload) || '{"target_weight_kg":40}',
    '{"calories":1450}'),
  'target_below_healthy_floor', 'a target under BMI 18.5 (50.4 kg at 165 cm) breaks the floor');
select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload) || '{"target_weight_kg":50.4}',
    '{"calories":1450}'),
  null, 'a target at the floor does not');
select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload) || '{"weight_kg":53}',
    '{"calories":1300}'),
  null, 'BMI 19.47 rounds to 19.5, where a cut is allowed again (as in Coach)');
select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload) - 'height_cm', '{"calories":1450}'),
  'answers_incomplete', 'answers without a height fail closed');
select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload) || '{"height_cm":200,"weight_kg":77.8}',
    '{"calories":1300}'),
  null, 'BMI exactly 19.45 rounds up to 19.5, as the Deno bmiOf does: no hold');
select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload) - 'daily_activity', '{"calories":1450}'),
  'answers_incomplete', 'under BMI 19.5, answers without a daily activity fail closed');
select is(private.onboarding_floor_violation(
    (select snapshot -> 'answers' from floors_payload) - 'birth_year', '{"calories":1450}'),
  'answers_incomplete', 'and so do answers without a birth year');
select ok(not has_function_privilege('authenticated',
  'private.onboarding_floor_violation(jsonb, jsonb)', 'execute'), 'the rule is private');

-- 2. Approval re-checks it -----------------------------------------------------------------------

insert into p values
  ('cut', pg_temp.proposal('f1000000-0000-4000-8000-000000000001', repeat('a', 64), '{}', 1300)),
  ('target', pg_temp.proposal('f1000000-0000-4000-8000-000000000002', repeat('b', 64),
    '{"target_weight_kg":40}', 1450)),
  ('held', pg_temp.proposal('f1000000-0000-4000-8000-000000000003', repeat('c', 64),
    '{"target_weight_kg":52}', 1450));

set local role authenticated;
set local "request.jwt.claim.sub" = 'f1000000-0000-4000-8000-000000000001';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'cut'), 'accept')
  ->> 'status', 'expired', 'a cut under BMI 19.5 is not approved: the proposal expires');
select is(public.get_my_onboarding_generation() ->> 'proposal_status', 'expired',
  'the app sees it as expired and builds a fresh plan');
reset role;
select is((select count(*)::integer from public.user_goals
  where user_id = 'f1000000-0000-4000-8000-000000000001' and status = 'active'), 0,
  'no goal was activated');
select is((select count(*)::integer from public.nutrition_target_sets
  where user_id = 'f1000000-0000-4000-8000-000000000001'), 0, 'no calorie target was stored');
select is((select onboarding_state::text from public.user_accounts
  where id = 'f1000000-0000-4000-8000-000000000001'), 'in_progress', 'onboarding is not complete');
select is((select metadata ->> 'reason' from public.audit_events
  where user_id = 'f1000000-0000-4000-8000-000000000001'
    and action_code = 'onboarding_proposal_expired'), 'deficit_near_healthy_floor',
  'the audit event names the floor');

set local role authenticated;
set local "request.jwt.claim.sub" = 'f1000000-0000-4000-8000-000000000002';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'target'), 'accept')
  ->> 'status', 'expired', 'a target under the floor is never stored');
reset role;
select is((select count(*)::integer from public.user_goals
  where user_id = 'f1000000-0000-4000-8000-000000000002' and details ? 'target_weight_kg'), 0,
  'no goal carries the target');

set local role authenticated;
set local "request.jwt.claim.sub" = 'f1000000-0000-4000-8000-000000000003';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'held'), 'accept')
  ->> 'status', 'accepted', 'maintenance with a target above the floor is approved');
reset role;
select is((select (details ->> 'target_weight_kg')::numeric from public.user_goals
  where user_id = 'f1000000-0000-4000-8000-000000000003' and status = 'active'), 52::numeric,
  'and its target is stored');
select is((select calories from public.nutrition_target_sets
  where user_id = 'f1000000-0000-4000-8000-000000000003' and status = 'active'), 1450,
  'at maintenance');

-- 3. A missing screening is unscreened ---------------------------------------------------------

select is(private.current_screening_outcome('f1000000-0000-4000-8000-000000000005'), 'unscreened',
  'no screening row is unscreened');
select is(private.screening_rank('unscreened'), 1, 'which ranks with moderate_until_cleared');
select throws_ok(
  $$select pg_temp.proposal('f1000000-0000-4000-8000-000000000005', repeat('e', 64), '{}', 1450)$$,
  '55000', 'the health check must be answered first', 'no plan is stored before the health check');
select throws_ok(
  $$select private.assert_screening_allows('f1000000-0000-4000-8000-000000000005', 'cleared')$$,
  '55000', 'the health check must be answered first', 'nor approved');
select lives_ok(
  $$select private.assert_screening_allows('f1000000-0000-4000-8000-000000000005', 'unscreened')$$,
  'a plan built as unscreened (a Coach proposal held to moderate effort) may be approved');
select lives_ok(
  $$select private.assert_screening_allows('f1000000-0000-4000-8000-000000000001', 'unscreened')$$,
  'and still once the athlete has answered it and is cleared');
set local role authenticated;
set local "request.jwt.claim.sub" = 'f1000000-0000-4000-8000-000000000005';
select is(public.get_my_screening_v1() -> 'screened', 'false'::jsonb,
  'installed builds still read a never-screened athlete as not screened');
select is(public.record_screening_v1(true, false, false) ->> 'outcome', 'cleared',
  'answering the health check');
reset role;
select is(private.current_screening_outcome('f1000000-0000-4000-8000-000000000005'), 'cleared',
  'clears the athlete');
select lives_ok(
  $$select pg_temp.proposal('f1000000-0000-4000-8000-000000000005', repeat('f', 64), '{}', 1450)$$,
  'and a plan can then be stored');

-- A plan restored for an unscreened athlete is held to moderate effort.
insert into auth.users(id, role) values ('f1000000-0000-4000-8000-000000000006', 'authenticated');
insert into public.training_plans(id, user_id, title, source)
values ('f1000000-0000-4000-8000-0000000000a6', 'f1000000-0000-4000-8000-000000000006', 'Plan', 'rules');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date)
values ('f1000000-0000-4000-8000-0000000000b6', 'f1000000-0000-4000-8000-000000000006',
  'f1000000-0000-4000-8000-0000000000a6', 1, 'active', 6, 1, '{}', 'Why', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
values ('f1000000-0000-4000-8000-0000000000c6', 'f1000000-0000-4000-8000-000000000006',
  'f1000000-0000-4000-8000-0000000000b6', 1, 'A', 'Squat', 1, 40, 'Easy', 'Walk');
insert into public.planned_exercises(user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, notes)
values ('f1000000-0000-4000-8000-000000000006', 'f1000000-0000-4000-8000-0000000000c6', 1,
  'Goblet squat', 3, 8, 12, 9, 120, '');
select private.hold_plan_to_screening('f1000000-0000-4000-8000-000000000006',
  'f1000000-0000-4000-8000-0000000000b6');
select is((select target_rpe from public.planned_exercises
  where planned_workout_id = 'f1000000-0000-4000-8000-0000000000c6'), 7::numeric,
  'an unscreened athlete gets at most effort 7');

-- 4. Direct writes --------------------------------------------------------------------------

select ok(has_table_privilege('authenticated', 'public.user_goals', 'select'),
  'the app reads its goals');
select ok(not has_table_privilege('authenticated', 'public.user_goals', 'insert'),
  'it has no table-wide insert on goals');
select ok(not has_table_privilege('authenticated', 'public.user_goals', 'update'),
  'nor table-wide update');
select ok(has_column_privilege('authenticated', 'public.user_goals', 'goal_type', 'insert')
    and has_column_privilege('authenticated', 'public.user_goals', 'priority', 'insert')
    and has_column_privilege('authenticated', 'public.user_goals', 'status', 'insert')
    and has_column_privilege('authenticated', 'public.user_goals', 'user_id', 'insert'),
  'it inserts the draft goal the onboarding flow saves');
select ok(not has_column_privilege('authenticated', 'public.user_goals', 'details', 'insert')
    and not has_column_privilege('authenticated', 'public.user_goals', 'activated_at', 'insert'),
  'but never details or an activation');
select ok(has_column_privilege('authenticated', 'public.user_goals', 'goal_type', 'update'),
  'it changes the draft goal type');
select ok(not has_column_privilege('authenticated', 'public.user_goals', 'details', 'update')
    and not has_column_privilege('authenticated', 'public.user_goals', 'status', 'update')
    and not has_column_privilege('authenticated', 'public.user_goals', 'activated_at', 'update')
    and not has_column_privilege('authenticated', 'public.user_goals', 'priority', 'update'),
  'and nothing else: targets, phases and status stay with the definer functions');
select ok(not has_column_privilege('authenticated', 'public.user_accounts', 'onboarding_state', 'insert')
    and not has_column_privilege('authenticated', 'public.user_accounts', 'onboarding_state', 'update'),
  'the app cannot write the onboarding state');

set local role authenticated;
set local "request.jwt.claim.sub" = 'f1000000-0000-4000-8000-000000000004';
select lives_ok($$insert into public.user_goals(user_id, goal_type, priority, status)
  values ('f1000000-0000-4000-8000-000000000004', 'muscle_gain', 1, 'draft')$$,
  'the app still saves a draft goal, as build 920 does');
select lives_ok($$update public.user_goals set goal_type = 'strength'
  where user_id = 'f1000000-0000-4000-8000-000000000004' and status = 'draft'$$,
  'and changes its type');
select throws_ok($$insert into public.user_goals(user_id, goal_type, priority, status)
  values ('f1000000-0000-4000-8000-000000000004', 'fat_loss', 1, 'active')$$,
  '42501', null, 'an active goal cannot be inserted');
select throws_ok($$update public.user_goals set details = '{"target_weight_kg":35}'
  where user_id = 'f1000000-0000-4000-8000-000000000004'$$,
  '42501', null, 'a target cannot be written past set_goal_target_v1');
select throws_ok($$insert into public.user_goals(user_id, goal_type, priority, status, details)
  values ('f1000000-0000-4000-8000-000000000004', 'fat_loss', 1, 'draft', '{"target_weight_kg":35}')$$,
  '42501', null, 'a draft goal cannot be inserted with details');
select throws_ok($$insert into public.user_goals(user_id, goal_type, priority, status, activated_at)
  values ('f1000000-0000-4000-8000-000000000004', 'fat_loss', 1, 'draft', now())$$,
  '42501', null, 'nor with an activation time');
select throws_ok($$update public.user_accounts set onboarding_state = 'completed'
  where id = 'f1000000-0000-4000-8000-000000000004'$$,
  '42501', null, 'onboarding cannot be marked complete by the app');
set local "request.jwt.claim.sub" = 'f1000000-0000-4000-8000-000000000003';
select lives_ok($$update public.user_goals set goal_type = 'strength'
  where user_id = 'f1000000-0000-4000-8000-000000000003' and status = 'active'$$,
  'an update aimed at the active goal raises nothing');
reset role;
select is((select goal_type::text from public.user_goals
  where user_id = 'f1000000-0000-4000-8000-000000000003' and status = 'active'), 'fat_loss',
  'but changes no row: only drafts are writable');
select is((select onboarding_state::text from public.user_accounts
  where id = 'f1000000-0000-4000-8000-000000000004'), 'in_progress', 'it stays in progress');

-- 5. Function reach of the app roles --------------------------------------------------------

select ok(not has_function_privilege('anon', 'public.get_healthkit_completion_candidate(date)',
  'execute'), 'the HealthKit candidate read is closed to anon');
select ok(has_function_privilege('authenticated', 'public.get_healthkit_completion_candidate(date)',
  'execute'), 'and open to the app');
select ok(not has_schema_privilege('anon', 'private', 'usage')
    and not has_schema_privilege('authenticated', 'private', 'usage'),
  'the private schema is out of reach, so only public functions need checking');
select is(
  (select coalesce(array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text),
    '{}'::text[])
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and not exists (select 1 from pg_depend d
       where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'execute')),
  '{}'::text[], 'no public function is executable by anon');
select is(
  (select coalesce(array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text),
    '{}'::text[])
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   cross join lateral (
     select coalesce(p.proallargtypes, array(select unnest(p.proargtypes::oid[]))) as types) a
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from pg_depend d
       where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('authenticated', p.oid, 'execute')
     and exists (select 1 from generate_subscripts(a.types, 1) i
       where a.types[i] = 'uuid'::regtype
         and coalesce(p.proargmodes[i], 'i') in ('i', 'b', 'v')
         and p.proargnames[i] ~ '^(p_|target_)?(user|athlete|owner)(_id)?$')),
  '{}'::text[],
  'no security definer function that takes a user id is executable by the signed-in role');

select * from finish();
rollback;
