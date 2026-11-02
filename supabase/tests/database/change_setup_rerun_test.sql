begin;
select plan(30);

-- "Change my setup" builds a new plan for an athlete who has already finished onboarding, through
-- the same generation, storage and approval functions the first plan used. This pins that those
-- functions need nothing from the account being new: the draft stays writable, a plan built from
-- the same answers is built again, the active plan is untouched until approval, approval replaces
-- it with a new version and an audit event, and the health check still stops a plan.

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

-- The same answers changed to three training days on a longer session.
create temporary table changed as select
  jsonb_set(jsonb_set(training, '{sessions_per_week}', '3'), '{weekly_structure}',
    (training -> 'weekly_structure') || jsonb_build_array(
      (training -> 'weekly_structure' -> 0)
        || '{"workout_order":3,"name":"Full body C","preferred_weekday":7}'::jsonb)) training,
  '{"calories":2300,"protein_g":150,"carbohydrate_g":260,"fat_g":65,"rationale":"A longer week"}'::jsonb nutrition,
  jsonb_set(jsonb_set(snapshot, '{answers,training_weekdays}', '[2,5,7]'),
    '{answers,session_minutes}', '60') snapshot
from payload;

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

-- Claims a generation for the hash and stores the given plan as its proposal.
create function pg_temp.proposal(uid uuid, hash text, training jsonb, nutrition jsonb, snapshot jsonb)
returns uuid language plpgsql as $$
declare claim jsonb := public.claim_onboarding_generation(uid, hash, 140);
begin
  perform public.persist_onboarding_proposal_v3((claim ->> 'generation_id')::uuid, uid, hash,
    snapshot, training, nutrition, '[]', 'Why', 'Benefit', 'Downside', 'medium', null);
  return (select proposal_id from public.onboarding_generations
    where id = (claim ->> 'generation_id')::uuid);
end $$;

select pg_temp.athlete('d1000000-0000-4000-8000-000000000001');
select pg_temp.athlete('d1000000-0000-4000-8000-000000000002');
create temporary table p(name text primary key, id uuid);
grant all on p to authenticated;
create temporary table first_plan(id uuid, generation_id uuid);

-- 1. The first plan, as at onboarding -------------------------------------------------------------

insert into p select 'first', pg_temp.proposal('d1000000-0000-4000-8000-000000000001', repeat('1', 64),
  (select training from payload), (select nutrition from payload), (select snapshot from payload));
set local role authenticated;
set local "request.jwt.claim.sub" = 'd1000000-0000-4000-8000-000000000001';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'first'), 'accept') ->> 'status',
  'accepted', 'the first plan is approved');
reset role;
select is((select onboarding_state::text from public.user_accounts where id = 'd1000000-0000-4000-8000-000000000001'),
  'completed', 'and onboarding is complete');
insert into first_plan
select (select id from public.training_plan_versions
    where user_id = 'd1000000-0000-4000-8000-000000000001' and status = 'active'),
  (select id from public.onboarding_generations where user_id = 'd1000000-0000-4000-8000-000000000001');

-- 2. The athlete reopens their setup and changes answers ---------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1000000-0000-4000-8000-000000000001';
select lives_ok($$update public.onboarding_drafts set current_section = 'review',
    payload = '{"session_minutes":60,"training_weekdays":[2,5,7]}'::jsonb
  where user_id = 'd1000000-0000-4000-8000-000000000001'$$,
  'a finished athlete can still save their answers');
reset role;
select is((select onboarding_state::text from public.user_accounts where id = 'd1000000-0000-4000-8000-000000000001'),
  'completed', 'saving them does not reopen onboarding');

create temporary table claim_two as
select public.claim_onboarding_generation('d1000000-0000-4000-8000-000000000001', repeat('2', 64), 140) value;
select is((select value ->> 'started' from claim_two), 'true', 'new answers start a new generation');
select isnt((select (value ->> 'generation_id')::uuid from claim_two), (select generation_id from first_plan),
  'which is not the first one');
select is((select status::text from public.training_plan_versions where id = (select id from first_plan)),
  'active', 'the active plan is untouched while the new one builds');

-- 3. The new proposal waits for approval ---------------------------------------------------------------

select lives_ok($$select public.persist_onboarding_proposal_v3(
    (select (value ->> 'generation_id')::uuid from claim_two),
    'd1000000-0000-4000-8000-000000000001', repeat('2', 64),
    (select snapshot from changed), (select training from changed), (select nutrition from changed),
    '[]', 'Why', 'Benefit', 'Downside', 'medium', null)$$,
  'the new plan is stored');
insert into p select 'second', proposal_id from public.onboarding_generations
  where id = (select (value ->> 'generation_id')::uuid from claim_two);
set local role authenticated;
set local "request.jwt.claim.sub" = 'd1000000-0000-4000-8000-000000000001';
select is(public.get_my_onboarding_generation() ->> 'proposal_status', 'pending',
  'it is pending');
reset role;
select is((select status::text from public.training_plan_versions where id = (select id from first_plan)),
  'active', 'the active plan is still untouched');
select is((select count(*)::integer from public.training_plan_versions
    where user_id = 'd1000000-0000-4000-8000-000000000001'), 1, 'and there is no second version yet');
select is(public.claim_onboarding_generation('d1000000-0000-4000-8000-000000000001', repeat('2', 64), 140) ->> 'proposal_id',
  (select id::text from p where name = 'second'), 'asking again for the same answers returns the pending plan');

-- 4. Approval replaces the plan ---------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1000000-0000-4000-8000-000000000001';
select is(public.respond_to_onboarding_proposal_v2((select id from p where name = 'second'), 'accept') ->> 'status',
  'accepted', 'the athlete approves the new plan');
reset role;
select is((select status::text from public.training_plan_versions where id = (select id from first_plan)),
  'superseded', 'the first plan version is superseded');
select is((select count(*)::integer from public.training_plan_versions
    where user_id = 'd1000000-0000-4000-8000-000000000001' and status = 'active'), 1,
  'exactly one plan version is active');
select is((select sessions_per_week::integer from public.training_plan_versions
    where user_id = 'd1000000-0000-4000-8000-000000000001' and status = 'active'), 3,
  'with the new three days');
select is((select source_proposal_id from public.training_plan_versions
    where user_id = 'd1000000-0000-4000-8000-000000000001' and status = 'active'),
  (select id from p where name = 'second'), 'built from the approved proposal');
select is((select count(*)::integer from public.planned_workouts w
    join public.training_plan_versions v on v.id = w.plan_version_id
    where v.user_id = 'd1000000-0000-4000-8000-000000000001' and v.id = (select id from first_plan)), 2,
  'the first version keeps its workouts, so history still points at them');
select is((select calories from public.nutrition_target_sets
    where user_id = 'd1000000-0000-4000-8000-000000000001' and status = 'active'), 2300,
  'the nutrition targets are the new ones');
select is((select version_number from public.nutrition_target_sets
    where user_id = 'd1000000-0000-4000-8000-000000000001' and status = 'active'), 2,
  'as version 2');
select is((select training_days from public.user_profiles where user_id = 'd1000000-0000-4000-8000-000000000001'),
  array[2,5,7]::smallint[], 'and the profile holds the new schedule');
select is((select session_minutes::integer from public.user_profiles where user_id = 'd1000000-0000-4000-8000-000000000001'),
  60, 'and session length');
select is((select count(*)::integer from public.audit_events
    where user_id = 'd1000000-0000-4000-8000-000000000001' and action_code = 'onboarding_proposal_accept'), 2,
  'each approval is audited');
select is((select onboarding_state::text from public.user_accounts where id = 'd1000000-0000-4000-8000-000000000001'),
  'completed', 'the account stays complete');

-- 5. The same answers can be built again, and the health check still applies --------------------------------

select is(public.claim_onboarding_generation('d1000000-0000-4000-8000-000000000001', repeat('2', 64), 140) ->> 'started',
  'true', 'answers whose plan was approved build a fresh plan, not the approved one');
set local role authenticated;
set local "request.jwt.claim.sub" = 'd1000000-0000-4000-8000-000000000001';
select is(public.record_screening_v1(true, false, true) ->> 'outcome', 'see_professional',
  'the athlete records a symptom');
reset role;
select is((select status from public.onboarding_generations
    where user_id = 'd1000000-0000-4000-8000-000000000001' order by created_at desc, attempt desc limit 1),
  'superseded', 'the plan being built stops');
select throws_ok($$select pg_temp.proposal('d1000000-0000-4000-8000-000000000001', repeat('3', 64),
    (select training from changed), (select nutrition from changed), (select snapshot from changed))$$,
  '55000', 'a health professional must clear this athlete first', 'and no new plan can be stored');
select is((select status::text from public.training_plan_versions
    where user_id = 'd1000000-0000-4000-8000-000000000001' and status = 'active'
      and source_proposal_id = (select id from p where name = 'second')), 'active',
  'while the approved plan stays usable');

-- 6. Another athlete's generations are not visible -----------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1000000-0000-4000-8000-000000000002';
select is(public.get_my_onboarding_generation(), null::jsonb, 'an athlete reads only their own generations');
reset role;

select * from finish();
rollback;
