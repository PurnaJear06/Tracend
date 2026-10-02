begin;
select plan(10);

insert into auth.users(id, role) values
  ('f2000000-0000-4000-8000-000000000001', 'authenticated');
insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level, training_days, session_minutes)
values ('f2000000-0000-4000-8000-000000000001', now(), true, 'beginner', array[2,5]::smallint[], 45);
insert into public.consent_records(user_id, consent_type, notice_version, action, source) values
  ('f2000000-0000-4000-8000-000000000001', 'terms', '2026-07-01', 'granted', 'ios_app'),
  ('f2000000-0000-4000-8000-000000000001', 'privacy', '2026-07-01', 'granted', 'ios_app');
insert into public.onboarding_drafts(user_id, path, current_section, payload)
values ('f2000000-0000-4000-8000-000000000001', 'beginner', 'review', '{}');

create temporary table telemetry_payload as select
  '{"title":"Foundation block","block_weeks":6,"sessions_per_week":2,"split":"full_body",
    "origin":"ai","provider":"deepseek","model":"deepseek-flash","policy_version":"onboarding-policy-v1",
    "prescription":{"strategy":"foundation_block","review_after_weeks":2},
    "weekly_structure":[
      {"workout_order":1,"name":"Full body A","objective":"Squat and row","preferred_weekday":2,
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
  '{"schema_version":"2.0","answers":{"goal":"muscle_gain","avoid_patterns":[]}}'::jsonb snapshot,
  '{"thinking":true,"latency_ms":41250,"attempts":1,"input_units":4100,
    "output_units":9800,"reasoning_units":7300,"finish_reason":"stop"}'::jsonb metadata;

-- The metadata check ---------------------------------------------------------------

select ok(private.is_valid_generation_metadata(null), 'no metadata is allowed (rules plan)');
select ok(private.is_valid_generation_metadata((select metadata from telemetry_payload)),
  'complete metadata is valid');
select ok(not private.is_valid_generation_metadata(
    (select metadata || '{"prompt":"text"}' from telemetry_payload)),
  'an unknown key is refused');
select ok(not private.is_valid_generation_metadata(
    (select metadata - 'thinking' from telemetry_payload)),
  'a missing key is refused');
select ok(not private.is_valid_generation_metadata(
    (select metadata || '{"latency_ms":"slow"}' from telemetry_payload)),
  'a non-number is refused without raising');
select ok(not private.is_valid_generation_metadata(
    (select metadata || '{"latency_ms":120001}' from telemetry_payload)),
  'latency above the usage-event limit is refused');

-- Stored with the audit event ----------------------------------------------------------

select is(public.claim_onboarding_generation('f2000000-0000-4000-8000-000000000001', repeat('d', 64), 140)->>'started',
  'true', 'a generation starts');
select throws_ok($$select public.persist_onboarding_proposal_v3(
    (select id from public.onboarding_generations where status = 'running'),
    'f2000000-0000-4000-8000-000000000001', repeat('d', 64), snapshot, training, nutrition, '[]',
    'Why', 'Benefit', 'Downside', 'medium', metadata || '{"attempts":3}') from telemetry_payload$$,
  '22023', null, 'invalid metadata stops the proposal being stored');
select lives_ok($$select public.persist_onboarding_proposal_v3(
    (select id from public.onboarding_generations where status = 'running'),
    'f2000000-0000-4000-8000-000000000001', repeat('d', 64), snapshot, training, nutrition, '[]',
    'Why', 'Benefit', 'Downside', 'medium', metadata) from telemetry_payload$$,
  'v3 stores the proposal with its metadata');
select is((select metadata - 'proposal_id' from public.audit_events
    where user_id = 'f2000000-0000-4000-8000-000000000001'
      and action_code = 'onboarding.plan.generated'),
  '{"origin":"ai","provider":"deepseek","model":"deepseek-flash","policy_version":"onboarding-policy-v1",
    "thinking":true,"latency_ms":41250,"attempts":1,"input_units":4100,"output_units":9800,
    "reasoning_units":7300,"finish_reason":"stop"}'::jsonb,
  'the audit event carries the generation metadata');

select * from finish();
rollback;
