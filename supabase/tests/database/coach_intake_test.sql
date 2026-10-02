begin;
select plan(35);

insert into auth.users(id, role) values
  ('f4000000-0000-4000-8000-000000000001', 'authenticated'),
  ('f4000000-0000-4000-8000-000000000002', 'authenticated');

-- Profile and proposal shape -----------------------------------------------------------

select throws_ok($$insert into public.user_profiles(user_id, priority_muscles)
    values ('f4000000-0000-4000-8000-000000000002', array['chest','back','calves'])$$,
  '23514', null, 'at most two focus muscles');
select throws_ok($$insert into public.user_profiles(user_id, strong_muscles)
    values ('f4000000-0000-4000-8000-000000000002', array['forearms'])$$,
  '23514', null, 'only catalog muscles');

create temporary table payload as select
  '{"title":"Strength block","block_weeks":6,"sessions_per_week":1,"split":"full_body",
    "origin":"ai","provider":"deepseek","model":"deepseek-flash","policy_version":"onboarding-policy-v2",
    "prescription":{"strategy":"preserve_validated_practices","review_after_weeks":2},
    "calculation":{"priority_minimums":[{"muscle":"chest","sets":6}]},
    "weekly_structure":[
      {"workout_order":1,"name":"Upper","objective":"Press and row","preferred_weekday":3,
       "estimated_minutes":45,"warm_up_guidance":"Easy movement","cool_down_guidance":"Walk",
       "exercises":[
         {"exercise_order":1,"slug":"barbell-bench-press","name":"Barbell bench press","sets":4,"rep_min":5,"rep_max":8,"target_rpe":8,"rest_seconds":150,"notes":"","start_load_kg":82.5},
         {"exercise_order":2,"slug":"barbell-row","name":"Barbell row","sets":3,"rep_min":6,"rep_max":10,"target_rpe":8,"rest_seconds":120,"notes":""}]}]}'::jsonb training,
  '{"calories":2600,"protein_g":160,"carbohydrate_g":300,"fat_g":80,"rationale":"Middle of the range"}'::jsonb nutrition,
  '{"schema_version":"2.0","policy_version":"onboarding-policy-v2",
    "answers":{"goal":"strength","experience":"intermediate","sex":"male",
    "birth_year":1990,"height_cm":180,"weight_kg":84,"daily_activity":"mostly_sitting",
    "training_weekdays":[3],"session_minutes":60,"equipment_items":["barbell","bench"],
    "equipment_note":"","limitations":"","avoid_patterns":[],"nutrition_context":"",
    "current_plan":"5x5","training_years":"over_5","priority_muscles":["chest"],
    "strong_muscles":["back","quads"],"current_lifts":[],"follow_ups":[]}}'::jsonb snapshot;

select ok((select private.is_valid_initial_proposal_v2(training, nutrition) from payload),
  'an exercise may carry a starting load');
select ok((select private.is_valid_initial_proposal_v2(
    jsonb_set(training, '{weekly_structure,0,exercises,0,start_load_kg}', '2500'), nutrition)
    from payload) is false, 'a starting load past 2000 kg is refused');
select ok((select private.is_valid_initial_proposal_v2(
    training #- '{weekly_structure,0,exercises,0,start_load_kg}', nutrition) from payload),
  'a proposal without starting loads stays valid');

-- Storing and approving ------------------------------------------------------------------

insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level, training_days, session_minutes)
values ('f4000000-0000-4000-8000-000000000001', now(), true, 'intermediate', array[3]::smallint[], 60);
insert into public.consent_records(user_id, consent_type, notice_version, action, source) values
  ('f4000000-0000-4000-8000-000000000001', 'terms', '2026-07-01', 'granted', 'ios_app'),
  ('f4000000-0000-4000-8000-000000000001', 'privacy', '2026-07-01', 'granted', 'ios_app');
insert into public.onboarding_drafts(user_id, path, current_section, payload)
values ('f4000000-0000-4000-8000-000000000001', 'experienced', 'review', '{}');

select is(public.claim_onboarding_generation('f4000000-0000-4000-8000-000000000001', repeat('a', 64), 140)->>'started',
  'true', 'a generation starts');
select throws_ok($$select public.persist_onboarding_proposal_v3(
    (select id from public.onboarding_generations where status = 'running'),
    'f4000000-0000-4000-8000-000000000001', repeat('a', 64),
    jsonb_set(snapshot, '{policy_version}', '"onboarding-policy-v9"'), training, nutrition,
    '[]', 'Why', 'Benefit', 'Downside', 'medium', null) from payload$$,
  '22023', null, 'an unknown policy version is refused');
select lives_ok($$select public.persist_onboarding_proposal_v3(
    (select id from public.onboarding_generations where status = 'running'),
    'f4000000-0000-4000-8000-000000000001', repeat('a', 64), snapshot, training, nutrition,
    '[{"code":"REPORTED_BARBELL_LIFTS","label":"The recent top sets you reported","source":"feature_snapshot"}]',
    'Why', 'Benefit', 'Downside', 'medium', null) from payload$$,
  'a v2 proposal with a starting load is stored');
select is((select feature_engine_version from public.feature_snapshots
    where user_id = 'f4000000-0000-4000-8000-000000000001'),
  'onboarding-policy-v2', 'the snapshot records the policy it was built under');

set local role authenticated;
set local "request.jwt.claim.sub" = 'f4000000-0000-4000-8000-000000000001';
select is(public.respond_to_onboarding_proposal_v2(
    (select id from public.change_proposals where schema_version = '2.0'), 'accept')->>'status',
  'accepted', 'the athlete approves');
select is((select array_agg(target_load_kg order by exercise_order)::text from public.planned_exercises),
  '{82.50,NULL}', 'the starting load is copied; the other exercise has none');
select is((public.get_my_training_hub()->'workouts'->0->'exercises'->0->>'target_load_kg')::numeric,
  82.5, 'the training hub reports it');
select is(public.get_my_training_hub()->>'schema_version', '1.5', 'hub schema 1.5');
select is(public.get_my_daily_brief(current_date)->>'schema_version', '1.6', 'brief schema 1.6');
reset role;
select is((select array[training_years, priority_muscles::text, strong_muscles::text]
    from public.user_profiles where user_id = 'f4000000-0000-4000-8000-000000000001'),
  array['over_5', '{chest}', '{back,quads}'], 'approval keeps the training years and muscles');

insert into public.coach_threads(id, user_id, title, status)
values ('f4700000-0000-4000-8000-000000000001', 'f4000000-0000-4000-8000-000000000001',
  'Chest', 'active');
set local role service_role;
create temporary table coach_context as select public.prepare_coach_chat_v8(
  'f4000000-0000-4000-8000-000000000001', 'f4700000-0000-4000-8000-000000000001',
  'How do I bring my chest up?', 'Asia/Kolkata', gen_random_uuid(), 'plan_change') value;
reset role;
select is((select value->'context'->'profile_context'->'priority_muscles' from coach_context),
  '["chest"]'::jsonb, 'the Coach sees the focus muscles');
select is((select value->'context'->'profile_context'->>'training_years' from coach_context),
  'over_5', 'and how long the athlete has trained');

-- Follow-up questions ---------------------------------------------------------------------

set local role service_role;
select is((public.store_onboarding_questions('f4000000-0000-4000-8000-000000000001', repeat('b', 64),
    '[{"category":"stalled_lift","question":"How often do you bench?","choices":["Once","Twice"]}]',
    null, '{"thinking":true,"latency_ms":9000,"attempts":1,"input_units":900,"output_units":1500,"reasoning_units":1200,"finish_reason":"stop"}'
  )->'questions'->0->>'category'), 'stalled_lift', 'questions are stored');
select is(jsonb_array_length(public.store_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('b', 64), '[]', 'no_questions_needed', null)->'questions'),
  1, 'a second request for the same answers gets the first questions');
select throws_ok($$select public.store_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('c', 64), '[{"category":"injury_history","question":"Any injuries?","choices":[]}]', null, null)$$,
  '23514', null, 'a question outside the allowed topics is refused');
select ok(public.record_ai_usage_event('f4000000-0000-4000-8000-000000000001', 'onboarding_questions',
    'deepseek', 'deepseek-flash', 900, 1500, 0.002, 9000) is not null,
  'question calls are recorded as their own purpose');
reset role;
select is((select metadata->>'reasoning_units' from public.audit_events
    where action_code = 'onboarding.questions.generated'), '1200', 'and audited with their telemetry');
select ok(not has_function_privilege('authenticated',
    'public.store_onboarding_questions(uuid, text, jsonb, text, jsonb)', 'execute'),
  'only the server stores questions');
select ok(not has_function_privilege('authenticated',
    'public.claim_onboarding_questions(uuid, text, integer)', 'execute'),
  'and only the server claims them');

set local role service_role;
select is(public.claim_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('d', 64), 60), '{"started": true}'::jsonb, 'the first request claims the answers');
select is(public.claim_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('d', 64), 60), '{"started": false}'::jsonb, 'an overlapping one does not ask again');
select public.store_onboarding_questions('f4000000-0000-4000-8000-000000000001', repeat('d', 64),
  '[{"category":"split_history","question":"Which split?","choices":[]}]', null, null);
select is(public.claim_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('d', 64), 60)->'stored'->'questions'->0->>'category', 'split_history',
  'once stored, a claim returns the questions');
select is(public.claim_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('e', 64), 60)->>'started', 'true', 'a failed call''s answers are claimed');
select public.release_onboarding_questions('f4000000-0000-4000-8000-000000000001', repeat('e', 64));
select is(public.claim_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('e', 64), 60)->>'started', 'true', 'and after the release, claimed again');
reset role;
update public.onboarding_questions set lease_expires_at = now() - interval '1 second'
  where questions_hash = repeat('e', 64);
set local role service_role;
select is(public.claim_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('e', 64), 60)->>'started', 'true', 'a lapsed claim is taken over');
select throws_ok($$select public.claim_onboarding_questions('f4000000-0000-4000-8000-000000000001',
    repeat('f', 64), 600)$$, '22023', null, 'the lease stays short');
reset role;

-- Apple Health history ----------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'f4000000-0000-4000-8000-000000000001';
select is(public.save_health_history(jsonb_build_array(
    jsonb_build_object('month', to_char(date_trunc('month', current_date) - interval '1 month', 'YYYY-MM-DD'),
      'workouts', 16, 'strength_workouts', 14, 'workout_minutes', 900, 'sleep_nights', 28,
      'sleep_minutes_avg', 425, 'weight_days', 5, 'weight_kg_avg', 84.2, 'data_days', 30,
      'first_data_date', to_char(date_trunc('month', current_date) - interval '1 month', 'YYYY-MM-DD'),
      'last_data_date', to_char(date_trunc('month', current_date) - interval '1 day', 'YYYY-MM-DD'))))->>'saved',
  '1', 'a completed month is saved');
select throws_ok($$select public.save_health_history(jsonb_build_array(
    jsonb_build_object('month', to_char(date_trunc('month', current_date), 'YYYY-MM-DD'),
      'workouts', 1, 'strength_workouts', 1, 'workout_minutes', 60, 'sleep_nights', 0,
      'weight_days', 0, 'data_days', 1)))$$,
  '22023', null, 'the month in progress is refused');
select is((select count(*) from public.health_history_months), 1::bigint,
  'the athlete reads their own months');
set local "request.jwt.claim.sub" = 'f4000000-0000-4000-8000-000000000002';
select is((select count(*) from public.health_history_months), 0::bigint,
  'and nobody else''s');
reset role;

select * from finish();
rollback;
