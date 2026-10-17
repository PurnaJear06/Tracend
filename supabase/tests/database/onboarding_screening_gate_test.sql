begin;
select plan(29);

-- A plan built under a weaker health check can neither be stored nor approved once the current
-- outcome is stricter (migration 26): record_screening_v1 ends what is open, and
-- persist_onboarding_proposal_v3 and respond_to_onboarding_proposal_v2 enforce it themselves.

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


grant select on v2_payload to authenticated;

-- An eligible athlete with consents, a draft and a draft goal, as at the Review step.
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

-- Claims a generation for these answers and stores a proposal built under `built_under`
-- (null: the snapshot has no screening, as before the screening existed).
create function pg_temp.proposal(uid uuid, hash text, built_under text default null)
returns uuid language plpgsql as $$
declare claim jsonb := public.claim_onboarding_generation(uid, hash, 140);
begin
  perform public.persist_onboarding_proposal_v3((claim ->> 'generation_id')::uuid, uid, hash,
    (select snapshot from v2_payload) ||
      case when built_under is null then '{}'::jsonb else jsonb_build_object('screening', built_under) end,
    (select training from v2_payload), (select nutrition from v2_payload), '[]',
    'Why', 'Benefit', 'Downside', 'medium', null);
  return (select proposal_id from public.onboarding_generations
    where id = (claim ->> 'generation_id')::uuid);
end $$;

select pg_temp.athlete(('b6a00000-0000-4000-8000-00000000000' || n)::uuid) from generate_series(1, 8) n;
create temporary table p(name text primary key, id uuid);
grant all on p to authenticated;

-- 1. Symptoms recorded after a cleared plan was built ---------------------------------------------

insert into p select 'one', pg_temp.proposal('b6a00000-0000-4000-8000-000000000001', repeat('1', 64));
set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000001';
select is(public.get_my_onboarding_generation() ->> 'proposal_status', 'pending',
  'a plan built while cleared is waiting for approval');
select is(public.record_screening_v1(true, false, true) ->> 'outcome', 'see_professional',
  'the athlete then records a symptom');
select is((select status::text from public.change_proposals where id = (select id from p where name = 'one')),
  'expired', 'the open proposal is expired');
select is(public.get_my_onboarding_generation() ->> 'proposal_status', 'expired',
  'the app sees it as expired');
select throws_ok($$select public.respond_to_onboarding_proposal_v2(
    (select id from p where name = 'one'), 'accept')$$, '55000', null,
  'and it cannot be approved');
reset role;

-- 2. A generation still running when symptoms are recorded -------------------------------------------

select public.claim_onboarding_generation('b6a00000-0000-4000-8000-000000000002', repeat('2', 64), 140);
set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000002';
select public.record_screening_v1(true, false, true);
reset role;
select is((select status from public.onboarding_generations
    where user_id = 'b6a00000-0000-4000-8000-000000000002'), 'superseded',
  'a running generation is superseded when the outcome becomes stricter');
select throws_ok($$select public.persist_onboarding_proposal_v3(
    (select id from public.onboarding_generations where user_id = 'b6a00000-0000-4000-8000-000000000002'),
    'b6a00000-0000-4000-8000-000000000002', repeat('2', 64), snapshot, training, nutrition, '[]',
    'Why', 'Benefit', 'Downside', 'medium', null) from v2_payload$$, '55000', null,
  'and its worker cannot store a plan');

-- 3. The checks themselves, with the proposal still pending (the stored outcome written directly) ---------

insert into p select 'three', pg_temp.proposal('b6a00000-0000-4000-8000-000000000003', repeat('3', 64));
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values ('b6a00000-0000-4000-8000-000000000003', true, false, true, false, 'see_professional');
select is((select status::text from public.change_proposals where id = (select id from p where name = 'three')),
  'pending', 'the proposal is still pending');
set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000003';
select throws_ok($$select public.respond_to_onboarding_proposal_v2(
    (select id from p where name = 'three'), 'accept')$$, '55000',
  'a health professional must clear this athlete first',
  'see_professional refuses approval');
select lives_ok($$select public.respond_to_onboarding_proposal_v2(
    (select id from p where name = 'three'), 'reject')$$,
  'but the athlete can still reject the plan');
reset role;
select is((select status::text from public.change_proposals where id = (select id from p where name = 'three')),
  'rejected', 'and it is rejected');
select throws_ok($$select pg_temp.proposal('b6a00000-0000-4000-8000-000000000003', repeat('4', 64))$$,
  '55000', 'a health professional must clear this athlete first',
  'see_professional refuses to store a plan');

insert into p select 'four', pg_temp.proposal('b6a00000-0000-4000-8000-000000000004', repeat('5', 64));
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values ('b6a00000-0000-4000-8000-000000000004', true, true, false, false, 'moderate_until_cleared');
set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000004';
select throws_ok($$select public.respond_to_onboarding_proposal_v2(
    (select id from p where name = 'four'), 'accept')$$, '55000',
  'the plan was built before the health check changed',
  'moderate_until_cleared refuses a plan built as cleared');
reset role;
select throws_ok($$select pg_temp.proposal('b6a00000-0000-4000-8000-000000000004', repeat('6', 64))$$,
  '55000', 'the plan was built before the health check changed',
  'and refuses to store one');
select lives_ok($$select pg_temp.proposal('b6a00000-0000-4000-8000-000000000004', repeat('7', 64),
  'moderate_until_cleared')$$, 'but stores a plan built as moderate');

-- 4. Moderate recorded after a cleared plan was built --------------------------------------------------

insert into p select 'five', pg_temp.proposal('b6a00000-0000-4000-8000-000000000005', repeat('8', 64));
set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000005';
select is(public.record_screening_v1(true, true, false, false) ->> 'outcome', 'moderate_until_cleared',
  'a known condition without clearance, while exercising, is moderate');
select is((select status::text from public.change_proposals where id = (select id from p where name = 'five')),
  'expired', 'the cleared plan is expired');
select throws_ok($$select public.respond_to_onboarding_proposal_v2(
    (select id from p where name = 'five'), 'accept')$$, '55000', null,
  'and cannot be approved');
reset role;

-- 5. Cleared stays approvable ----------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000006';
select public.record_screening_v1(true, false, false);
reset role;
insert into p select 'six', pg_temp.proposal('b6a00000-0000-4000-8000-000000000006', repeat('9', 64));
set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000006';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'six'), 'accept') ->> 'status',
  'accepted', 'a cleared athlete approves a cleared plan');
select is(public.record_screening_v1(true, false, false) ->> 'outcome', 'cleared',
  'answering the same again changes nothing');
reset role;

-- 6. An athlete with no screening row is unaffected --------------------------------------------------------

insert into p select 'seven', pg_temp.proposal('b6a00000-0000-4000-8000-000000000007', repeat('a', 64));
set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000007';
select is(public.get_my_screening_v1() ->> 'screened', 'false', 'no row reads as not screened');
select is(public.get_my_screening_v1() ->> 'outcome', 'cleared', 'and as cleared');
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'seven'), 'accept') ->> 'status',
  'accepted', 'the plan is approved as before the screening existed');
reset role;

-- 7. A moderate athlete approves a plan built as moderate -----------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000008';
select public.record_screening_v1(true, true, false, false);
reset role;
select throws_ok($$select pg_temp.proposal('b6a00000-0000-4000-8000-000000000008', repeat('b', 64))$$,
  '55000', 'the plan was built before the health check changed', 'a plan stored without the outcome is refused');
insert into p select 'eight', pg_temp.proposal('b6a00000-0000-4000-8000-000000000008', repeat('c', 64),
  'moderate_until_cleared');
set local role authenticated;
set local "request.jwt.claim.sub" = 'b6a00000-0000-4000-8000-000000000008';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'eight'), 'accept') ->> 'status',
  'accepted', 'and a plan built as moderate is approved');
select is((select array_agg(k order by k) from jsonb_object_keys(public.get_my_screening_v1()) k),
  array['cleared_by_professional', 'exercises_regularly', 'known_disease', 'outcome', 'schema_version',
    'screened', 'screened_at', 'symptoms'],
  'the read answers exactly its contract keys');
select is(public.get_my_screening_v1() ->> 'schema_version', '1.0', 'at schema version 1.0');
select ok(not has_function_privilege('anon', 'public.get_my_screening_v1()', 'execute'),
  'signed-out callers cannot read');
reset role;
select ok(not has_function_privilege('authenticated', 'private.assert_screening_allows(uuid, text)', 'execute'),
  'the guard is private');

select * from finish();
rollback;
