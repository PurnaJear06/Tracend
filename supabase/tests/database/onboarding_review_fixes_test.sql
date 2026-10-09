begin;
select plan(15);

insert into auth.users(id, role) values
  ('f1000000-0000-4000-8000-000000000001', 'authenticated');

-- Daily coaching follows its own notice -----------------------------------------

insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('f1000000-0000-4000-8000-000000000001', 'ai_coaching', 'ai-coaching-v5', 'granted', 'ios_app');
select ok(public.has_ai_coaching_consent('f1000000-0000-4000-8000-000000000001', 'daily_coaching'),
  'a v4 grant allows daily coaching while v4 is its notice');
select lives_ok($$select private.publish_ai_notice('ai-daily-v2', 'Another provider',
    array['daily_coaching'], 'Daily decisions move to another provider')$$,
  'the owner publishes a notice for daily coaching only');
select ok(not public.has_ai_coaching_consent('f1000000-0000-4000-8000-000000000001', 'daily_coaching'),
  'the daily-coaching notice change stops the old grant counting for daily coaching');
select ok(public.has_ai_coaching_consent('f1000000-0000-4000-8000-000000000001', 'coach_chat'),
  'the same grant still allows the Coach chat');
select ok(public.has_ai_coaching_consent('f1000000-0000-4000-8000-000000000001'),
  'the one-argument form older functions call still means the Coach chat');

-- Setup for a stored proposal -----------------------------------------------------

insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level, training_days, session_minutes)
values ('f1000000-0000-4000-8000-000000000001', now(), true, 'beginner', array[2,5]::smallint[], 45);
insert into public.consent_records(user_id, consent_type, notice_version, action, source) values
  ('f1000000-0000-4000-8000-000000000001', 'terms', '2026-07-01', 'granted', 'ios_app'),
  ('f1000000-0000-4000-8000-000000000001', 'privacy', '2026-07-01', 'granted', 'ios_app');
insert into public.onboarding_drafts(user_id, path, current_section, payload)
values ('f1000000-0000-4000-8000-000000000001', 'beginner', 'review', '{}');

create temporary table review_payload as select
  '{"title":"Foundation block","block_weeks":6,"sessions_per_week":2,"split":"full_body",
    "origin":"rules","policy_version":"onboarding-policy-v1",
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
  '{"schema_version":"2.0","answers":{"goal":"muscle_gain","experience":"beginner","sex":"female",
    "birth_year":1992,"height_cm":165,"weight_kg":62.5,"daily_activity":"some_standing",
    "training_weekdays":[2,5],"session_minutes":45,"equipment_items":["dumbbells"],
    "limitations":"Squats hurt","avoid_patterns":["squat"],"nutrition_context":""}}'::jsonb snapshot;

select is(public.claim_onboarding_generation('f1000000-0000-4000-8000-000000000001', repeat('c', 64), 140)->>'started',
  'true', 'a generation starts');

-- Movements to avoid --------------------------------------------------------------

select throws_ok($$select public.persist_onboarding_proposal_v2(
    (select id from public.onboarding_generations where status = 'running'),
    'f1000000-0000-4000-8000-000000000001', repeat('c', 64), snapshot, training, nutrition, '[]',
    'Why', 'Benefit', 'Downside', 'medium') from review_payload$$,
  '22023', null, 'a proposal with a squat is refused when the answers avoid squats');
select lives_ok($$select public.persist_onboarding_proposal_v2(
    (select id from public.onboarding_generations where status = 'running'),
    'f1000000-0000-4000-8000-000000000001', repeat('c', 64), snapshot,
    jsonb_set(training, '{weekly_structure,0,exercises,0}',
      '{"exercise_order":1,"slug":"dumbbell-reverse-lunge","name":"Dumbbell reverse lunge","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7.5,"rest_seconds":120,"notes":""}'),
    nutrition, '[]', 'Why', 'Benefit', 'Downside', 'medium') from review_payload$$,
  'the same plan with a lunge instead is stored');

-- Expired proposals ------------------------------------------------------------------

update public.change_proposals set expires_at = now() - interval '1 minute'
  where user_id = 'f1000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" = 'f1000000-0000-4000-8000-000000000001';
select is(public.get_my_onboarding_generation()->>'proposal_status', 'expired',
  'the app is told the proposal expired');
select ok(public.get_my_onboarding_generation()->>'proposal_expires_at' is not null,
  'with its expiry time');
select is(public.respond_to_onboarding_proposal_v2(
    (select id from public.change_proposals where schema_version = '2.0'), 'accept')->>'status',
  'expired', 'approving an expired proposal reports it expired instead of raising');
reset role;

select is((select status::text from public.change_proposals
  where user_id = 'f1000000-0000-4000-8000-000000000001'), 'expired',
  'the expiry is stored, not rolled back');
select is((select count(*) from public.training_plan_versions
  where user_id = 'f1000000-0000-4000-8000-000000000001'), 0::bigint,
  'nothing was activated');

set local role authenticated;
set local "request.jwt.claim.sub" = 'f1000000-0000-4000-8000-000000000001';
select throws_ok($$select public.respond_to_onboarding_proposal_v2(
    (select id from public.change_proposals where schema_version = '2.0'), 'reject')$$,
  '55000', null, 'an expired proposal cannot be answered again');
reset role;

select is(public.claim_onboarding_generation('f1000000-0000-4000-8000-000000000001', repeat('c', 64), 140)->>'started',
  'true', 'the same answers start a fresh generation after expiry');

select * from finish();
rollback;
