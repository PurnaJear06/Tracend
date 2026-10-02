begin;
select plan(44);

insert into auth.users(id, role) values
  ('e1000000-0000-4000-8000-000000000001', 'authenticated'),
  ('e2000000-0000-4000-8000-000000000002', 'authenticated');

-- Reference data and access -------------------------------------------------

select ok(
  (select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid = any(array[
    'public.onboarding_generations'::regclass, 'public.ai_consent_notices'::regclass,
    'public.ai_notice_current'::regclass, 'public.exercise_catalog'::regclass])),
  'new tables enable and force RLS');
select is((select count(*) from public.exercise_catalog where status = 'active'), 72::bigint,
  'the catalog seeds all 72 exercises');
select ok(not has_table_privilege('anon', 'public.exercise_catalog', 'select'),
  'anonymous callers cannot read the catalog');
select ok(not has_table_privilege('authenticated', 'public.exercise_catalog', 'insert'),
  'athletes cannot add exercises');
select ok(not has_table_privilege('authenticated', 'public.ai_consent_notices', 'insert'),
  'athletes cannot publish notices');
select ok(not has_function_privilege('authenticated',
  'public.claim_onboarding_generation(uuid,text,integer)', 'execute'),
  'only the server claims generations');
select ok(not has_function_privilege('authenticated',
  'public.persist_onboarding_proposal_v2(uuid,uuid,text,jsonb,jsonb,jsonb,jsonb,text,text,text,text)',
  'execute'), 'only the server stores proposals');
select ok(has_function_privilege('authenticated',
  'public.respond_to_onboarding_proposal_v2(uuid,public.proposal_response_action,text)', 'execute'),
  'athletes respond through the v2 RPC');
select ok(not has_column_privilege('authenticated', 'public.user_profiles', 'sex', 'update'),
  'athletes cannot write approval-owned profile fields');
select ok(has_column_privilege('authenticated', 'public.user_profiles', 'session_minutes', 'update'),
  'the fields older apps write stay writable');

-- AI notice per purpose -----------------------------------------------------

insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('e1000000-0000-4000-8000-000000000001', 'ai_coaching', 'ai-coaching-v1', 'granted', 'ios_app');
select ok(public.has_ai_coaching_consent('e1000000-0000-4000-8000-000000000001'),
  'a v1 grant still allows the Coach');
select ok(not public.has_ai_coaching_consent('e1000000-0000-4000-8000-000000000001', 'onboarding_plan'),
  'a v1 grant does not cover the onboarding plan');
select is(public.get_current_ai_notice()->>'version', 'ai-coaching-v1',
  'the app is shown the notice current for the most purposes');

select throws_ok($$select private.publish_ai_notice('ai-coaching-bad', 'X', array['everything'], 'Body')$$,
  '23514', null, 'a notice with an unknown purpose is refused');
select is((select version from public.ai_notice_current where purpose = 'coach_chat'), 'ai-coaching-v1',
  'a refused publish changes nothing');

-- Onboarding answers --------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'e1000000-0000-4000-8000-000000000001';
select lives_ok($$
  insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level, training_days, session_minutes)
  values ('e1000000-0000-4000-8000-000000000001', now(), true, 'beginner', array[1,2,3]::smallint[], 60)
  on conflict (user_id) do update set eligible = excluded.eligible, session_minutes = excluded.session_minutes$$,
  'the step-0 profile upsert of older apps still works');
select throws_ok($$update public.user_profiles set sex = 'male'$$, '42501', null,
  'a direct write of sex is denied');
reset role;

insert into public.consent_records(user_id, consent_type, notice_version, action, source) values
  ('e1000000-0000-4000-8000-000000000001', 'terms', '2026-07-01', 'granted', 'ios_app'),
  ('e1000000-0000-4000-8000-000000000001', 'privacy', '2026-07-01', 'granted', 'ios_app');
insert into public.onboarding_drafts(user_id, path, current_section, payload)
values ('e1000000-0000-4000-8000-000000000001', 'beginner', 'review', '{}');
insert into public.user_goals(user_id, goal_type, priority, status)
values ('e1000000-0000-4000-8000-000000000001', 'recomposition', 1, 'draft');

create temporary table v2_payload as select
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

-- Generations -----------------------------------------------------------------

select is(public.claim_onboarding_generation('e1000000-0000-4000-8000-000000000001', repeat('a', 64), 140)->>'started',
  'true', 'the first claim starts a generation');
select is(public.claim_onboarding_generation('e1000000-0000-4000-8000-000000000001', repeat('a', 64), 140)->>'started',
  'false', 'the same answers return the running generation');
select is(public.claim_onboarding_generation('e1000000-0000-4000-8000-000000000001', repeat('b', 64), 140)->>'started',
  'true', 'new answers start a new generation');
select is((select array_agg(status order by created_at) from public.onboarding_generations
  where user_id = 'e1000000-0000-4000-8000-000000000001'), array['superseded','running'],
  'the older generation is superseded, one runs');
select throws_ok($$select public.persist_onboarding_proposal_v2(
    (select id from public.onboarding_generations where status = 'superseded'),
    'e1000000-0000-4000-8000-000000000001', repeat('a', 64), snapshot, training, nutrition, '[]',
    'Why', 'Benefit', 'Downside', 'medium') from v2_payload$$,
  '55000', null, 'a superseded worker cannot store its proposal');
select throws_ok($$select public.persist_onboarding_proposal_v2(
    (select id from public.onboarding_generations where status = 'running'),
    'e1000000-0000-4000-8000-000000000001', repeat('b', 64), snapshot,
    jsonb_set(training, '{weekly_structure,0,exercises,0,slug}', '"made-up"'), nutrition, '[]',
    'Why', 'Benefit', 'Downside', 'medium') from v2_payload$$,
  '22023', null, 'an exercise outside the catalog is refused');
select lives_ok($$select public.persist_onboarding_proposal_v2(
    (select id from public.onboarding_generations where status = 'running'),
    'e1000000-0000-4000-8000-000000000001', repeat('b', 64), snapshot, training, nutrition, '[]',
    'Why', 'Benefit', 'Downside', 'medium') from v2_payload$$,
  'the current generation stores its proposal');
select is((select status from public.onboarding_generations where proposal_id is not null), 'succeeded',
  'the generation records its proposal');
select is(public.claim_onboarding_generation('e1000000-0000-4000-8000-000000000001', repeat('b', 64), 140)->>'status',
  'succeeded', 'claiming the same answers again returns the finished proposal');
select is((select count(*) from public.audit_events where action_code = 'onboarding.plan.generated'),
  1::bigint, 'generation is audited');

-- Approval --------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'e1000000-0000-4000-8000-000000000001';
select is(public.get_my_onboarding_generation()->>'status', 'succeeded',
  'the app sees its finished generation');
select throws_ok($$select public.respond_to_onboarding_proposal(
    (select id from public.change_proposals where schema_version = '2.0'), 'accept')$$,
  '55000', null, 'an older app cannot approve a 2.0 proposal');
select lives_ok($$select public.respond_to_onboarding_proposal_v2(
    (select id from public.change_proposals where schema_version = '2.0'), 'accept')$$,
  'the athlete approves the 2.0 proposal');
reset role;

select is((select array_agg(w.name || '@' || w.preferred_weekday order by w.workout_order)
  from public.planned_workouts w join public.training_plan_versions v on v.id = w.plan_version_id
  where v.user_id = 'e1000000-0000-4000-8000-000000000001' and v.status = 'active'),
  array['Full body A@2','Full body B@5'], 'exactly the proposed workouts on the proposed days');
select is((select array_agg(e.exercise_slug order by w.workout_order, e.exercise_order)
  from public.planned_exercises e join public.planned_workouts w on w.id = e.planned_workout_id
  join public.training_plan_versions v on v.id = w.plan_version_id
  where v.user_id = 'e1000000-0000-4000-8000-000000000001' and v.status = 'active'),
  array['goblet-squat','one-arm-dumbbell-row','dumbbell-romanian-deadlift','dumbbell-floor-press'],
  'exactly the proposed exercises, with their catalog slugs, and no generic seed');
select is((select p.source from public.training_plans p join public.training_plan_versions v on v.plan_id = p.id
  where v.user_id = 'e1000000-0000-4000-8000-000000000001' and v.status = 'active'), 'ai',
  'the plan records where it came from');
select is((select goal_type::text || ':' || status::text || ':' || (details->>'target_weight_kg')
  from public.user_goals where user_id = 'e1000000-0000-4000-8000-000000000001' and status = 'active'),
  'muscle_gain:active:65', 'the goal is activated with its target weight');
select is((select sex || ':' || birth_year || ':' || daily_activity || ':' || array_to_string(equipment, ',')
  || ':' || array_to_string(training_days, ',') || ':' || session_minutes || ':' || nutrition_note
  from public.user_profiles where user_id = 'e1000000-0000-4000-8000-000000000001'),
  'female:1992:some_standing:dumbbells:2,5:45:Vegetarian', 'the profile holds the reviewed answers');
select is((select weight_kg || ':' || protocol_version from public.body_measurements
  where user_id = 'e1000000-0000-4000-8000-000000000001'), '62.50:onboarding-v1',
  'the onboarding weight becomes the first measurement');
select is((select calories from public.nutrition_target_sets
  where user_id = 'e1000000-0000-4000-8000-000000000001' and status = 'active'), 2100,
  'the nutrition targets are active');
select is((select onboarding_state::text from public.user_accounts where id = 'e1000000-0000-4000-8000-000000000001'),
  'completed', 'onboarding is complete');
select is((select count(*) from public.audit_events where target_type = 'change_proposal'
  and user_id = 'e1000000-0000-4000-8000-000000000001'), 1::bigint,
  'one audit row targets the proposal');

-- Consent changes, other athletes, usage ---------------------------------------

select lives_ok($$select private.publish_ai_notice('ai-coaching-v3', 'Another provider',
    array['coach_chat','daily_coaching','onboarding_plan'], 'New provider notice')$$,
  'the owner publishes a new notice for every purpose');
select ok(not public.has_ai_coaching_consent('e1000000-0000-4000-8000-000000000001'),
  'an older Coach grant stops counting once a newer notice is current');

set local role authenticated;
set local "request.jwt.claim.sub" = 'e2000000-0000-4000-8000-000000000002';
select is(public.get_my_onboarding_generation(), null, 'another athlete sees no generation');
select throws_ok($$select public.respond_to_onboarding_proposal_v2(
    (select id from public.change_proposals limit 1), 'reject')$$,
  'P0002', null, 'another athlete cannot answer the proposal');
reset role;

select lives_ok($$select public.record_ai_usage_event('e1000000-0000-4000-8000-000000000001',
    'onboarding_plan', 'deepseek', 'deepseek-flash', 4000, 2000, 0.0036, 18000)$$,
  'onboarding usage accepts the configured model');

select * from finish();
rollback;
