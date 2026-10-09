begin;
select plan(19);

insert into auth.users(id, role) values
  ('f3000000-0000-4000-8000-000000000001', 'authenticated'),
  ('f3000000-0000-4000-8000-000000000002', 'authenticated');

-- One notice for every purpose ----------------------------------------------------------

select is((select count(*) from public.ai_notice_current where version = 'ai-coaching-v5'),
  3::bigint, 'the current notice (v5) is current for the Coach chat, daily coaching and the onboarding plan');
select is(public.get_current_ai_notice()->>'version', 'ai-coaching-v5',
  'the notice every app shows, including builds already installed, is v5');
select ok((public.get_current_ai_notice()->>'body') like '%Apple Health, it also sends a summary%',
  'it tells the athlete the starting plan uses an Apple Health summary');
-- An installed app records a grant for the notice it was shown.
insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('f3000000-0000-4000-8000-000000000001', 'ai_coaching', 'ai-coaching-v5', 'granted', 'ios_app');
select ok(public.has_ai_coaching_consent('f3000000-0000-4000-8000-000000000001', 'onboarding_plan')
    and public.has_ai_coaching_consent('f3000000-0000-4000-8000-000000000001', 'coach_chat')
    and public.has_ai_coaching_consent('f3000000-0000-4000-8000-000000000001', 'daily_coaching'),
  'one grant counts for every purpose, so a new athlete gets the AI plan');

-- Time zone ---------------------------------------------------------------------------------

select is(private.local_date_for('f3000000-0000-4000-8000-000000000001'),
  (statement_timestamp() at time zone 'UTC')::date, 'an account without a zone reads as UTC');
set local role authenticated;
set local "request.jwt.claim.sub" = 'f3000000-0000-4000-8000-000000000001';
select throws_ok($$select public.set_my_timezone('Mars/Olympus')$$, '22023', null,
  'an unknown zone is refused');
select throws_ok($$select public.set_my_timezone('')$$, '22023', null, 'an empty zone is refused');
select is(public.set_my_timezone('Pacific/Kiritimati')->>'timezone', 'Pacific/Kiritimati',
  'the athlete stores the device zone');
reset role;
select is((select timezone from public.user_accounts where id = 'f3000000-0000-4000-8000-000000000001'),
  'Pacific/Kiritimati', 'it is written to the athlete''s own account');
select is((select timezone from public.user_accounts where id = 'f3000000-0000-4000-8000-000000000002'),
  'UTC', 'and no other account');
select is(private.local_date_for('f3000000-0000-4000-8000-000000000001'),
  (statement_timestamp() at time zone 'Pacific/Kiritimati')::date,
  'the athlete''s local date follows the stored zone');
select ok(not has_function_privilege('anon', 'public.set_my_timezone(text)', 'execute'),
  'a signed-out caller cannot set a zone');

-- Approval keeps the answers the Coach needs, on the athlete's date ------------------------

insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level, training_days, session_minutes)
values ('f3000000-0000-4000-8000-000000000001', now(), true, 'beginner', array[2,5]::smallint[], 45);
insert into public.consent_records(user_id, consent_type, notice_version, action, source) values
  ('f3000000-0000-4000-8000-000000000001', 'terms', '2026-07-01', 'granted', 'ios_app'),
  ('f3000000-0000-4000-8000-000000000001', 'privacy', '2026-07-01', 'granted', 'ios_app');
insert into public.onboarding_drafts(user_id, path, current_section, payload)
values ('f3000000-0000-4000-8000-000000000001', 'beginner', 'review', '{}');

create temporary table approval_payload as select
  '{"title":"Foundation block","block_weeks":6,"sessions_per_week":2,"split":"full_body",
    "origin":"rules","policy_version":"onboarding-policy-v1",
    "prescription":{"strategy":"foundation_block","review_after_weeks":2},
    "calculation":{"health":{"window_days":28,"days_with_data":26,"steps_per_day":9100}},
    "weekly_structure":[
      {"workout_order":1,"name":"Full body A","objective":"Hinge and row","preferred_weekday":2,
       "estimated_minutes":40,"warm_up_guidance":"Easy movement","cool_down_guidance":"Walk",
       "exercises":[
         {"exercise_order":1,"slug":"dumbbell-romanian-deadlift","name":"Dumbbell Romanian deadlift","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":120,"notes":""},
         {"exercise_order":2,"slug":"one-arm-dumbbell-row","name":"One-arm dumbbell row","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":120,"notes":""}]},
      {"workout_order":2,"name":"Full body B","objective":"Lunge and press","preferred_weekday":5,
       "estimated_minutes":40,"warm_up_guidance":"Easy movement","cool_down_guidance":"Walk",
       "exercises":[
         {"exercise_order":1,"slug":"dumbbell-reverse-lunge","name":"Dumbbell reverse lunge","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":120,"notes":""},
         {"exercise_order":2,"slug":"dumbbell-floor-press","name":"Dumbbell floor press","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":120,"notes":""}]}]}'::jsonb training,
  '{"calories":2100,"protein_g":140,"carbohydrate_g":235,"fat_g":65,"rationale":"Middle of the range"}'::jsonb nutrition,
  '{"schema_version":"2.0","health":{"window_days":28,"days_with_data":26,"steps_per_day":9100},
    "answers":{"goal":"muscle_gain","experience":"beginner","sex":"female",
    "birth_year":1992,"height_cm":165,"weight_kg":62.5,"daily_activity":"some_standing",
    "training_weekdays":[2,5],"session_minutes":45,"equipment_items":["dumbbells"],
    "equipment_note":"Dumbbells up to 20 kg","limitations":"Squats hurt",
    "avoid_patterns":["squat","vertical_push"],"nutrition_context":"",
    "current_plan":"Push pull legs"}}'::jsonb snapshot;

select is(public.claim_onboarding_generation('f3000000-0000-4000-8000-000000000001', repeat('e', 64), 140)->>'started',
  'true', 'a generation starts');
select lives_ok($$select public.persist_onboarding_proposal_v3(
    (select id from public.onboarding_generations where status = 'running'),
    'f3000000-0000-4000-8000-000000000001', repeat('e', 64), snapshot, training, nutrition,
    '[{"code":"APPLE_HEALTH_SUMMARY_28D","label":"Your Apple Health summary for the last 28 days","source":"feature_snapshot"}]',
    'Why', 'Benefit', 'Downside', 'medium', null) from approval_payload$$,
  'a proposal with an Apple Health summary is stored');

set local role authenticated;
set local "request.jwt.claim.sub" = 'f3000000-0000-4000-8000-000000000001';
select is(public.respond_to_onboarding_proposal_v2(
    (select id from public.change_proposals where schema_version = '2.0'), 'accept')->>'status',
  'accepted', 'the athlete approves');
reset role;

select is((select array[avoid_patterns::text, equipment_note] from public.user_profiles
    where user_id = 'f3000000-0000-4000-8000-000000000001'),
  array['{squat,vertical_push}', 'Dumbbells up to 20 kg'],
  'approval keeps the movements to avoid and the equipment note on the profile');
select is((select array[v.effective_date, n.effective_date, b.measured_on]
    from public.training_plan_versions v, public.nutrition_target_sets n, public.body_measurements b
    where v.user_id = 'f3000000-0000-4000-8000-000000000001' and v.status = 'active'
      and n.user_id = v.user_id and n.status = 'active'
      and b.user_id = v.user_id and b.protocol_version = 'onboarding-v1'),
  array[(statement_timestamp() at time zone 'Pacific/Kiritimati')::date,
    (statement_timestamp() at time zone 'Pacific/Kiritimati')::date,
    (statement_timestamp() at time zone 'Pacific/Kiritimati')::date],
  'plan, targets and weight carry the athlete''s local date at approval');

insert into public.coach_threads(id, user_id, title, status)
values ('f3700000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000001',
  'Legs', 'active');
set local role service_role;
create temporary table coach_context as select public.prepare_coach_chat_v8(
  'f3000000-0000-4000-8000-000000000001', 'f3700000-0000-4000-8000-000000000001',
  'What leg exercise should I add?', 'Asia/Kolkata', gen_random_uuid(), 'plan_change') value;
reset role;
select is((select value->'context'->'profile_context'->'movements_to_avoid' from coach_context),
  '["squat","vertical_push"]'::jsonb, 'the Coach sees the movements the athlete avoids');
select is((select value->'context'->'profile_context'->>'equipment_note' from coach_context),
  'Dumbbells up to 20 kg', 'and the equipment note');

select * from finish();
rollback;
