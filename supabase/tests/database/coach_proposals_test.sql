begin;
select plan(108);

-- Coach proposals (migration 18): rules compute a change, Coach stores it as a pending proposal, the
-- athlete approves it with one tap (a new version and an audit event) and can undo it for seven days.

create temporary table v2_payload as select
  '{"title":"Foundation block","block_weeks":6,"sessions_per_week":2,"split":"full_body",
    "origin":"ai","provider":"deepseek","model":"deepseek-flash","policy_version":"onboarding-policy-v1",
    "prescription":{"strategy":"foundation_block","progression":"Add a rep","review_after_weeks":2},
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

-- An athlete who has approved an onboarding plan: profile, goal, plan version 1 and nutrition set 1.
create function pg_temp.athlete(uid uuid, hash text) returns void language plpgsql as $$
declare
  claim jsonb;
  pid uuid;
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
  claim := public.claim_onboarding_generation(uid, hash, 140);
  perform public.persist_onboarding_proposal_v3((claim ->> 'generation_id')::uuid, uid, hash,
    (select snapshot from v2_payload), (select training from v2_payload),
    (select nutrition from v2_payload), '[]', 'Why', 'Benefit', 'Downside', 'medium', null);
  select proposal_id into pid from public.onboarding_generations
  where id = (claim ->> 'generation_id')::uuid;
  perform set_config('request.jwt.claim.sub', uid::text, true);
  set local role authenticated;
  perform public.respond_to_onboarding_proposal_v2(pid, 'accept');
  reset role;
end $$;

-- The versions a proposal built now would be based on.
create function pg_temp.basis(uid uuid, with_training boolean, with_nutrition boolean,
  with_goal boolean) returns jsonb language sql as $$
  select jsonb_build_object('screening', 'cleared',
    'training_version_id', case when with_training then (select id from public.training_plan_versions
      where user_id = uid and status = 'active') end,
    'nutrition_version_id', case when with_nutrition then (select id from public.nutrition_target_sets
      where user_id = uid and status = 'active') end,
    'goal_id', case when with_goal then private.active_goal_id(uid) end);
$$;

create function pg_temp.store(uid uuid, kind text, payload jsonb, basis jsonb,
  ends_on date default null, hours integer default 72) returns uuid language sql as $$
  select (public.persist_coach_proposal_v1(uid, kind, 'A change from Coach', 'Because you asked.',
    'A benefit.', 'A downside.', 'medium',
    '[{"code":"TRAINING_STANDARD","label":"Limits","source":"policy_evaluation"}]',
    '{"rows":[{"label":"Calories","value":"2,100 kcal"}]}',
    '{"rows":[{"label":"Calories","value":"2,000 kcal"}]}',
    payload, basis, ends_on, hours) ->> 'proposal_id')::uuid;
$$;

-- The same basis, under the moderate health check section 11 records.
create function pg_temp.basis_m(uid uuid, with_training boolean, with_nutrition boolean,
  with_goal boolean) returns jsonb language sql as $$
  select pg_temp.basis(uid, with_training, with_nutrition, with_goal)
    || '{"screening":"moderate_until_cleared"}'::jsonb;
$$;

-- A three-day schedule built on one exercise, with the profile it sets.
create function pg_temp.schedule(slug text, minutes integer) returns jsonb language sql as $$
  select jsonb_build_object('training', jsonb_build_object('mode', 'new_version',
    'title', 'Schedule', 'block_weeks', 8,
    'weekly_structure', (select jsonb_agg(jsonb_build_object('workout_order', n, 'name', 'Day ' || n,
      'objective', 'Train', 'preferred_weekday', d, 'estimated_minutes', 40,
      'warm_up_guidance', 'w', 'cool_down_guidance', 'c', 'exercises', jsonb_build_array(
        jsonb_build_object('exercise_order', 1, 'slug', slug, 'name', 'Exercise', 'sets', 3,
          'rep_min', 8, 'rep_max', 12, 'target_rpe', 7, 'rest_seconds', 90, 'notes', ''))))
      from (values (1, 1), (2, 3), (3, 5)) as t(n, d)),
    'profile', jsonb_build_object('training_days', jsonb_build_array(1, 3, 5),
      'session_minutes', minutes)));
$$;

select pg_temp.athlete('a8000000-0000-4000-8000-000000000001', repeat('1', 64));
select pg_temp.athlete('a8000000-0000-4000-8000-000000000002', repeat('2', 64));
create temporary table p(name text primary key, id uuid);
grant all on p to authenticated;

-- 1. Storing a proposal ------------------------------------------------------------------------------------

select ok(not has_function_privilege('authenticated',
    'public.persist_coach_proposal_v1(uuid, text, text, text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid)',
    'execute'), 'only the service role stores a proposal');
select ok(has_function_privilege('service_role',
    'public.persist_coach_proposal_v1(uuid, text, text, text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid)',
    'execute'), 'and it can');

insert into p select 'calories', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"A gentler pace."}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false));
select is((select status::text from public.change_proposals where id = (select id from p where name = 'calories')),
  'pending', 'a stored proposal is pending');
select is((select schema_version || ' ' || proposal_kind from public.change_proposals
    where id = (select id from p where name = 'calories')),
  '3.0 nutrition_targets', 'at schema 3.0 with its kind');
select is((select feature_snapshot_id is null from public.change_proposals
    where id = (select id from p where name = 'calories')),
  true, 'with no feature snapshot');
select is((select count(*)::integer from public.audit_events
    where target_id = (select id from p where name = 'calories') and action_code = 'coach_proposal_created'),
  1, 'and an audit event');
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
    '{"nutrition":{"calories":900,"protein_g":140,"carbohydrate_g":100,"fat_g":65,"rationale":"x"}}',
    pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false))$$,
  '22023', 'coach proposal is invalid', 'calories outside the table bounds are refused');
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
    '{"nutrition":{"calories":1100,"protein_g":140,"carbohydrate_g":0,"fat_g":65,"rationale":"x"}}',
    pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false))$$,
  '22023', 'coach proposal is invalid', 'macros that do not add up are refused');
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
    '{"nutrition":{"calories":1100,"protein_g":100,"carbohydrate_g":100,"fat_g":30,"rationale":"x"}}',
    pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false))$$,
  '22023', 'calories are below the minimum', 'calories under the sex minimum are refused');
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
    '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"x"}}',
    '{"screening":"cleared","nutrition_version_id":"00000000-0000-4000-8000-000000000000"}')$$,
  '55000', 'the plan changed while the proposal was built', 'a proposal based on an old version is refused');
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'sell_supplements',
    '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"x"}}',
    pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false))$$,
  '22023', 'coach proposal is invalid', 'a kind outside the list is refused');
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'temporary_block',
    '{"training":{"mode":"block","block_kind":"temporary_block","title":"Block","block_weeks":1,
      "ends_on":"2026-12-01","weekly_structure":[{"workout_order":1,"name":"A","objective":"B",
      "preferred_weekday":1,"estimated_minutes":40,"warm_up_guidance":"w","cool_down_guidance":"c",
      "exercises":[{"exercise_order":1,"slug":"goblet-squat","name":"Goblet squat","sets":99,
      "rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":90,"notes":""}]}]}}',
    pg_temp.basis('a8000000-0000-4000-8000-000000000001', true, false, false))$$,
  '22023', 'coach proposal is invalid', 'a training payload outside the plan limits is refused');
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'temporary_block',
    '{"training":{"mode":"block","block_kind":"temporary_block","title":"Block","block_weeks":1,
      "ends_on":"2026-12-01","weekly_structure":[{"workout_order":1,"name":"A","objective":"B",
      "preferred_weekday":1,"estimated_minutes":40,"warm_up_guidance":"w","cool_down_guidance":"c",
      "exercises":[{"exercise_order":1,"slug":"no-such-move","name":"No such move","sets":3,
      "rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":90,"notes":""}]}]}}',
    pg_temp.basis('a8000000-0000-4000-8000-000000000001', true, false, false))$$,
  '22023', 'coach proposal is invalid', 'an exercise outside the catalog is refused');
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
    '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"x"}}',
    pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false) || '{"gates":["nutrition_change"]}')$$,
  '55000', 'not enough logged data for this change', 'a change that needs logged evidence is refused without it');
select is(private.is_valid_coach_training('{"title":"No mode"}'), false,
  'a training payload with no mode is invalid, not unknown');
select is(private.is_valid_coach_proposal_row('training_schedule', '{}', '{}',
    '{"training":{"title":"No mode"}}'), false, 'and so is a proposal row that carries it');

-- 2. Reading ------------------------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is((select array_agg(k order by k collate "C") from jsonb_object_keys(
    public.get_my_coach_proposals_v1() -> 'proposals' -> 0) k),
  array['after', 'applied_at', 'before', 'benefit', 'can_undo', 'confidence', 'created_at', 'downside',
    'ends_on', 'evidence', 'expires_at', 'id', 'kind', 'rationale', 'source_message_id', 'status',
    'title', 'undo_until', 'undone_at'],
  'a proposal is read with exactly its contract keys');
select is(public.get_my_coach_proposals_v1() ->> 'schema_version', '1.0', 'at schema version 1.0');
select is(public.get_my_coach_proposals_v1() -> 'proposals' -> 0 ->> 'status', 'pending', 'pending');
select is(public.get_my_coach_proposals_v1() -> 'proposals' -> 0 ->> 'title', 'A change from Coach',
  'with its title');
select is(public.get_my_coach_proposals_v1() -> 'proposals' -> 0 ->> 'can_undo', 'false',
  'and nothing to undo yet');
select is(jsonb_array_length(public.get_my_coach_proposals_v1(
    (select id from p where name = 'calories')) -> 'proposals'), 1, 'one proposal by id');
select ok(not has_function_privilege('anon', 'public.get_my_coach_proposals_v1(uuid, integer)', 'execute'),
  'signed-out callers cannot read');
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000002';
select is(jsonb_array_length(public.get_my_coach_proposals_v1() -> 'proposals'), 0,
  'another athlete sees none of it');
select is((select count(*)::integer from public.change_proposals
    where id = (select id from p where name = 'calories')), 0, 'and cannot select the row');
select throws_ok($$select public.respond_to_coach_proposal_v1(
    (select id from p where name = 'calories'), 'approve')$$, 'P0002', 'proposal not found',
  'nor answer it');
reset role;

-- 3. Approving a nutrition change ----------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is((select array_agg(k order by k collate "C") from jsonb_object_keys(
    public.respond_to_coach_proposal_v1((select id from p where name = 'calories'), 'approve')) k),
  array['goal_id', 'nutrition_target_set_id', 'proposal_id', 'schema_version', 'status',
    'training_plan_version_id', 'undo_until'],
  'approval answers exactly its contract keys');
reset role;
select is((select status::text from public.change_proposals where id = (select id from p where name = 'calories')),
  'accepted', 'the proposal is accepted');
select is((select calories::text || '/' || version_number::text || '/' || status::text from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  '2000/2/active', 'a new nutrition version is active');
select is((select status::text from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and version_number = 1),
  'superseded', 'and the old one is superseded, not edited');
select is((select source_proposal_id from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and version_number = 2),
  (select id from p where name = 'calories'), 'carrying its source proposal');
select is((select count(*)::integer from public.change_responses
    where proposal_id = (select id from p where name = 'calories') and action = 'accept'),
  1, 'the answer is recorded');
select is((select count(*)::integer from public.audit_events
    where target_id = (select id from p where name = 'calories') and action_code = 'coach_proposal_accepted'),
  1, 'with an audit event');
select ok((select undo_until > now() + interval '6 days 23 hours' from public.change_proposals
    where id = (select id from p where name = 'calories')), 'and seven days to undo it');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select throws_ok($$select public.respond_to_coach_proposal_v1(
    (select id from p where name = 'calories'), 'approve')$$, '55000', 'proposal is not pending',
  'an answered proposal cannot be answered again');
select is(public.get_my_coach_proposals_v1((select id from p where name = 'calories')) -> 'proposals' -> 0 ->> 'can_undo',
  'true', 'it can be undone');

-- 4. Undo ------------------------------------------------------------------------------------------------------

select is((select array_agg(k order by k collate "C") from jsonb_object_keys(
    public.undo_coach_proposal_v1((select id from p where name = 'calories'))) k),
  array['goal_id', 'nutrition_target_set_id', 'proposal_id', 'schema_version', 'status',
    'training_plan_version_id'],
  'undo answers exactly its contract keys');
reset role;
select is((select calories::text || '/' || version_number::text from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  '2100/3', 'the earlier targets return as a new version');
select is((select count(*)::integer from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001'), 3, 'no version was edited or removed');
select is((select count(*)::integer from public.audit_events
    where target_id = (select id from p where name = 'calories') and action_code = 'coach_proposal_undone'),
  1, 'and the undo is audited');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.undo_coach_proposal_v1((select id from p where name = 'calories')) ->> 'status', 'undone',
  'undoing twice changes nothing');
reset role;
select is((select count(*)::integer from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001'), 3, 'and adds no version');

-- 5. Expired, stale and replaced proposals ----------------------------------------------------------------------

insert into p select 'old', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"A gentler pace."}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false));
update public.change_proposals set expires_at = now() - interval '1 minute'
where id = (select id from p where name = 'old');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'old'), 'approve') ->> 'status',
  'expired', 'an expired proposal is reported as expired');
reset role;
select is((select status::text from public.change_proposals where id = (select id from p where name = 'old')),
  'expired', 'and recorded as expired');
select is((select count(*)::integer from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001'), 3, 'with no new version');

insert into p select 'stale', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"A gentler pace."}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false));
update public.nutrition_target_sets set status = 'superseded'
where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active';
insert into public.nutrition_target_sets(user_id, version_number, status, calories, protein_g,
  carbohydrate_g, fat_g, rationale, approved_at, effective_date)
values ('a8000000-0000-4000-8000-000000000001', 4, 'active', 2200, 140, 255, 65, 'Changed meanwhile',
  now(), current_date);
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'stale'), 'approve') ->> 'reason',
  'nutrition_changed', 'a proposal based on a version that has since changed is refused');
reset role;
select is((select calories from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  2200, 'and the newer targets stay');

insert into p select 'first', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"One."}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false));
insert into p select 'second', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2050,"protein_g":140,"carbohydrate_g":225,"fat_g":65,"rationale":"Two."}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false));
select is((select status::text from public.change_proposals where id = (select id from p where name = 'first')),
  'expired', 'a newer proposal for the same thing replaces the open one');

-- 6. Declining, and asking for a change -------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'second'), 'decline') ->> 'status',
  'declined', 'declining closes a proposal');
reset role;
select is((select status::text from public.change_proposals where id = (select id from p where name = 'second')),
  'rejected', 'as rejected');
select is((select calories from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  2200, 'with no change to the targets');
insert into p select 'change', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"Three."}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false));
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'change'), 'change',
    'Make it 2100') ->> 'status', 'changed', '"change it" closes a proposal');
reset role;
select is((select revision_note from public.change_responses where proposal_id = (select id from p where name = 'change')),
  'Make it 2100', 'keeping the athlete''s note');

-- 7. A new schedule, undone ---------------------------------------------------------------------------------------

insert into p select 'schedule', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'training_schedule',
  '{"training":{"mode":"new_version","title":"Foundation block","block_weeks":8,"weekly_structure":[
    {"workout_order":1,"name":"Full body A","objective":"Squat","preferred_weekday":1,"estimated_minutes":40,
     "warm_up_guidance":"w","cool_down_guidance":"c","exercises":[
       {"exercise_order":1,"slug":"goblet-squat","name":"Goblet squat","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":90,"notes":"","start_load_kg":20}]},
    {"workout_order":2,"name":"Full body B","objective":"Hinge","preferred_weekday":3,"estimated_minutes":40,
     "warm_up_guidance":"w","cool_down_guidance":"c","exercises":[
       {"exercise_order":1,"slug":"dumbbell-romanian-deadlift","name":"Dumbbell Romanian deadlift","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":90,"notes":""}]},
    {"workout_order":3,"name":"Full body C","objective":"Press","preferred_weekday":5,"estimated_minutes":40,
     "warm_up_guidance":"w","cool_down_guidance":"c","exercises":[
       {"exercise_order":1,"slug":"dumbbell-floor-press","name":"Dumbbell floor press","sets":3,"rep_min":8,"rep_max":12,"target_rpe":7,"rest_seconds":90,"notes":""}]}],
    "profile":{"training_days":[1,3,5],"session_minutes":40}}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', true, false, false));
create temporary table original_version as
  select id, version_number from public.training_plan_versions
  where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active';
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select public.respond_to_coach_proposal_v1((select id from p where name = 'schedule'), 'approve');
reset role;
select is((select version_number::text || '/' || sessions_per_week::text || '/' || block_weeks::text from public.training_plan_versions
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  '2/3/8', 'a schedule change is a new plan version');
select is((select source_proposal_id from public.training_plan_versions
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  (select id from p where name = 'schedule'), 'carrying its source proposal');
select is((select count(*)::integer from public.planned_workouts w
    join public.training_plan_versions v on v.id = w.plan_version_id
    where v.user_id = 'a8000000-0000-4000-8000-000000000001' and v.status = 'active'),
  3, 'with its three sessions');
select is((select target_load_kg from public.planned_exercises e
    join public.planned_workouts w on w.id = e.planned_workout_id
    join public.training_plan_versions v on v.id = w.plan_version_id
    where v.user_id = 'a8000000-0000-4000-8000-000000000001' and v.status = 'active'
      and e.exercise_slug = 'goblet-squat'), 20.00, 'and the carried load');
select is((select training_days::text || '/' || session_minutes::text from public.user_profiles
    where user_id = 'a8000000-0000-4000-8000-000000000001'), '{1,3,5}/40', 'the profile follows');
select is((select status::text from public.training_plan_versions where id = (select id from original_version)),
  'superseded', 'the old version is superseded, not edited');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select public.undo_coach_proposal_v1((select id from p where name = 'schedule'));
reset role;
select is((select version_number from public.training_plan_versions
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  3, 'undo restores the earlier plan as a new version');
select is((select count(*)::integer from public.planned_workouts
    where plan_version_id = (select id from public.training_plan_versions
      where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active')),
  2, 'with the earlier two sessions');
select is((select training_days::text || '/' || session_minutes::text from public.user_profiles
    where user_id = 'a8000000-0000-4000-8000-000000000001'), '{2,5}/45', 'and the earlier profile');

-- 8. A temporary block ends by itself ------------------------------------------------------------------------------

insert into p select 'block', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'temporary_block',
  jsonb_build_object('training', jsonb_build_object('mode', 'block', 'block_kind', 'temporary_block',
    'title', 'Bodyweight block', 'block_weeks', 1,
    'ends_on', private.local_date_for('a8000000-0000-4000-8000-000000000001') + 3,
    'weekly_structure', '[{"workout_order":1,"name":"Home A","objective":"Bodyweight","preferred_weekday":2,
      "estimated_minutes":30,"warm_up_guidance":"w","cool_down_guidance":"c","exercises":[
      {"exercise_order":1,"slug":"bodyweight-squat","name":"Bodyweight squat","sets":3,"rep_min":10,"rep_max":15,
       "target_rpe":7,"rest_seconds":60,"notes":""}]}]'::jsonb)),
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', true, false, false),
  private.local_date_for('a8000000-0000-4000-8000-000000000001') + 3);
create temporary table before_block as
  select id from public.training_plan_versions
  where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active';
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select public.respond_to_coach_proposal_v1((select id from p where name = 'block'), 'approve');
reset role;
select is((select block_kind || '/' || (restores_version_id = (select id from before_block))::text
    from public.training_plan_versions
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  'temporary_block/true', 'a block is an active version that names the version to restore');
select is((select title from public.training_plans where id = (select plan_id from public.training_plan_versions
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active')),
  'Bodyweight block', 'under its own plan title');
select is(private.end_ended_plan_blocks('a8000000-0000-4000-8000-000000000001'), 0,
  'it stays while its last day has not passed');
update public.training_plan_versions set ends_on = private.local_date_for('a8000000-0000-4000-8000-000000000001') - 1
where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active';
select is(private.end_ended_plan_blocks('a8000000-0000-4000-8000-000000000001'), 1,
  'and ends the day after');
select is((select ends_on is null and block_kind is null from public.training_plan_versions
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  true, 'the regular plan is back as an ordinary version');
select is((select count(*)::integer from public.planned_workouts
    where plan_version_id = (select id from public.training_plan_versions
      where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active')),
  2, 'with its own sessions');
select is((select count(*)::integer from public.audit_events
    where user_id = 'a8000000-0000-4000-8000-000000000001' and action_code = 'coach_proposal_block_ended'),
  1, 'and an audit event');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.undo_coach_proposal_v1((select id from p where name = 'block')) ->> 'status', 'superseded',
  'a block that already ended cannot be undone');
reset role;

-- A block whose last day has passed is never shown as running to the proposal engine.
insert into p select 'block2', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'temporary_block',
  jsonb_build_object('training', jsonb_build_object('mode', 'block', 'block_kind', 'temporary_block',
    'title', 'Second block', 'block_weeks', 1,
    'ends_on', private.local_date_for('a8000000-0000-4000-8000-000000000001') + 3,
    'weekly_structure', '[{"workout_order":1,"name":"Home A","objective":"Bodyweight","preferred_weekday":2,
      "estimated_minutes":30,"warm_up_guidance":"w","cool_down_guidance":"c","exercises":[
      {"exercise_order":1,"slug":"bodyweight-squat","name":"Bodyweight squat","sets":3,"rep_min":10,"rep_max":15,
       "target_rpe":7,"rest_seconds":60,"notes":""}]}]'::jsonb)),
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', true, false, false), private.local_date_for('a8000000-0000-4000-8000-000000000001') + 3);
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select public.respond_to_coach_proposal_v1((select id from p where name = 'block2'), 'approve');
reset role;
update public.training_plan_versions set ends_on = private.local_date_for('a8000000-0000-4000-8000-000000000001') - 1
where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active';
select is(public.get_coach_proposal_inputs_v1('a8000000-0000-4000-8000-000000000001') -> 'plan' ->> 'block_kind', null,
  'an ended block is not reported as running');
select is(public.get_coach_proposal_inputs_v1('a8000000-0000-4000-8000-000000000001') -> 'plan' ->> 'ends_on', null,
  'and the regular plan is the active one');

-- 9. A diet break: the goal and the targets move together ---------------------------------------------------------------

insert into p select 'break', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'goal_or_phase',
  jsonb_build_object('goal', jsonb_build_object('goal_type', 'muscle_gain', 'phase', 'diet_break',
      'phase_started_on', private.local_date_for('a8000000-0000-4000-8000-000000000001'),
      'phase_ends_on', private.local_date_for('a8000000-0000-4000-8000-000000000001') + 13),
    'nutrition', '{"calories":2200,"protein_g":140,"carbohydrate_g":255,"fat_g":65,"rationale":"Maintenance."}'::jsonb),
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, true),
  private.local_date_for('a8000000-0000-4000-8000-000000000001') + 13);
create temporary table before_goal as
  select id, activated_at from public.user_goals
  where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active';
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select public.respond_to_coach_proposal_v1((select id from p where name = 'break'), 'approve');
reset role;
select is((select details ->> 'phase' from public.user_goals
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  'diet_break', 'the new goal version records the phase');
select is((select activated_at = (select activated_at from before_goal) from public.user_goals
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  true, 'and keeps the goal''s start, so the weeks into the goal continue');
select is((select status::text from public.user_goals where id = (select id from before_goal)),
  'superseded', 'the old goal is superseded');
select is((select source_proposal_id from public.user_goals
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  (select id from p where name = 'break'), 'carrying its source proposal');
select is((select calories from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  2200, 'and the targets are at maintenance');
select is(public.get_coach_proposals_context_v1('a8000000-0000-4000-8000-000000000001',
    private.local_date_for('a8000000-0000-4000-8000-000000000001')) -> 'phase' ->> 'phase', 'diet_break',
  'Coach is told the goal phase');
select is(public.get_coach_proposals_context_v1('a8000000-0000-4000-8000-000000000001',
    private.local_date_for('a8000000-0000-4000-8000-000000000001')) -> 'phase' ->> 'ends_on',
  (private.local_date_for('a8000000-0000-4000-8000-000000000001') + 13)::text, 'and the day a diet break ends');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select public.undo_coach_proposal_v1((select id from p where name = 'break'));
reset role;
select is((select coalesce(details ->> 'phase', 'none') from public.user_goals
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  'none', 'undo restores the earlier goal as a new version');
select is((select calories from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  2200, 'and the targets that were in force before it');

-- 9b. The undo window ----------------------------------------------------------------------------------------------

insert into p select 'window', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"Six."}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false));
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'window'), 'approve') ->> 'status',
  'accepted', 'a proposal approved');
reset role;
update public.change_proposals set undo_until = now() - interval '1 minute'
where id = (select id from p where name = 'window');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.undo_coach_proposal_v1((select id from p where name = 'window')) ->> 'status',
  'undo_window_ended', 'cannot be undone after seven days');
reset role;
select is((select calories from public.nutrition_target_sets
    where user_id = 'a8000000-0000-4000-8000-000000000001' and status = 'active'),
  2000, 'and stays in force');

-- 9c. The chat links a reply to its proposal, and Coach is told about proposals ----------------------------------------

insert into public.coach_threads(id, user_id, title)
values ('a8000000-0000-4000-8000-0000000000a1', 'a8000000-0000-4000-8000-000000000001', 'Thread');
insert into public.coach_messages(id, user_id, thread_id, role, content)
values ('a8000000-0000-4000-8000-0000000000a2', 'a8000000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-0000000000a1',
  'assistant', 'Here is a proposal you can approve.');
select public.link_coach_proposal_v1('a8000000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-0000000000a2',
  (select id from p where name = 'window'));
select is((select proposal_id from public.coach_messages
    where id = 'a8000000-0000-4000-8000-0000000000a2'),
  (select id from p where name = 'window'), 'the reply points at its proposal');
select is((select source_message_id from public.change_proposals
    where id = (select id from p where name = 'window')),
  'a8000000-0000-4000-8000-0000000000a2'::uuid, 'and the proposal at its reply');
select throws_ok($$select public.link_coach_proposal_v1('a8000000-0000-4000-8000-000000000001',
    'a8000000-0000-4000-8000-0000000000ff', (select id from p where name = 'window'))$$,
  'P0002', 'message or proposal not found', 'a message that is not the athlete''s cannot be linked');
select ok(not has_function_privilege('authenticated',
    'public.link_coach_proposal_v1(uuid, uuid, uuid)', 'execute'),
  'only the service role links');
-- Every row in this transaction has the same created_at; make the newest one clearly newest.
update public.change_proposals set created_at = now() + interval '1 hour'
where id = (select id from p where name = 'window');
select is(public.get_coach_proposals_context_v1('a8000000-0000-4000-8000-000000000001',
    private.local_date_for('a8000000-0000-4000-8000-000000000001')) -> 'proposals' -> 0 ->> 'status', 'accepted',
  'Coach is told how the newest proposal was answered');
select is(public.get_coach_proposals_context_v1('a8000000-0000-4000-8000-000000000001',
    private.local_date_for('a8000000-0000-4000-8000-000000000001')) -> 'proposals' -> 0 ->> 'title', 'A change from Coach',
  'with its title');
select is(public.get_coach_proposals_context_v1('a8000000-0000-4000-8000-000000000001',
    private.local_date_for('a8000000-0000-4000-8000-000000000001')) -> 'block', 'null'::jsonb, 'and that no block is running');

-- 10. A stricter health check, undo after seven days, and deletion --------------------------------------------------------

insert into p select 'strict', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"Four."}}',
  pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false));
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values ('a8000000-0000-4000-8000-000000000001', true, true, false, false, 'moderate_until_cleared');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select throws_ok($$select public.respond_to_coach_proposal_v1((select id from p where name = 'strict'), 'approve')$$,
  '55000', 'the plan was built before the health check changed',
  'a proposal made before the health check got stricter cannot be approved');
reset role;
select throws_ok($$select pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
    '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"Five."}}',
    pg_temp.basis('a8000000-0000-4000-8000-000000000001', false, true, false))$$,
  '55000', 'the plan was built before the health check changed', 'nor can one be stored on the old basis');
select is((select count(*)::integer from public.change_proposals
    where user_id = 'a8000000-0000-4000-8000-000000000001' and schema_version = '3.0'), 12,
  'the athlete has all their proposals');
-- 11. Approval checks again what the build checked ---------------------------------------------------------------------

insert into p select 'moved', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"Seven."}}',
  pg_temp.basis_m('a8000000-0000-4000-8000-000000000001', false, true, false));
update public.change_proposals set basis = jsonb_set(basis, '{weight_check_kg}', '40')
where id = (select id from p where name = 'moved');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'moved'), 'approve') ->> 'reason',
  'weight_changed', 'a weight that moved since the proposal was made expires it');
reset role;

insert into p select 'profile', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"Eight."}}',
  pg_temp.basis_m('a8000000-0000-4000-8000-000000000001', false, true, false));
update public.user_profiles set height_cm = 171 where user_id = 'a8000000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'profile'), 'approve') ->> 'reason',
  'profile_changed', 'so does a profile value the rules read');
reset role;

insert into p select 'minimum', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"Nine."}}',
  pg_temp.basis_m('a8000000-0000-4000-8000-000000000001', false, true, false));
update public.change_proposals set proposal_payload = jsonb_set(proposal_payload, '{nutrition}',
  '{"calories":1100,"protein_g":100,"carbohydrate_g":100,"fat_g":30,"rationale":"Low."}')
where id = (select id from p where name = 'minimum');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'minimum'), 'approve') ->> 'reason',
  'below_minimum', 'calories under the minimum are refused at approval too');
reset role;

insert into p select 'gate', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'nutrition_targets',
  '{"nutrition":{"calories":2000,"protein_g":140,"carbohydrate_g":215,"fat_g":65,"rationale":"Ten."}}',
  pg_temp.basis_m('a8000000-0000-4000-8000-000000000001', false, true, false));
update public.change_proposals set basis = basis || '{"gates":["nutrition_change"]}'
where id = (select id from p where name = 'gate');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'gate'), 'approve') ->> 'reason',
  'not_eligible', 'a gate the build required must still pass at approval');
reset role;
select is(private.coach_gates_pass('a8000000-0000-4000-8000-000000000001', '[]', current_date), true, 'no gate always passes');
select is(private.coach_gates_pass('a8000000-0000-4000-8000-000000000001', '["nutrition_change"]', current_date), false,
  'a gate without the logged evidence does not');
select is(private.coach_gates_pass('a8000000-0000-4000-8000-000000000001', '["something_else"]', current_date), false,
  'an unknown gate does not');

insert into p select 'catalog', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'training_schedule',
  pg_temp.schedule('dumbbell-floor-press', 40), pg_temp.basis_m('a8000000-0000-4000-8000-000000000001', true, false, false));
update public.exercise_catalog set status = 'retired', retired_at = now()
where slug = 'dumbbell-floor-press';
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.respond_to_coach_proposal_v1((select id from p where name = 'catalog'), 'approve') ->> 'reason',
  'catalog_changed', 'an exercise retired since the proposal was made expires it');
reset role;

-- Undo holds the earlier plan to the current health check and leaves later profile edits alone.
insert into p select 'undo_a', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'training_schedule',
  pg_temp.schedule('goblet-squat', 40), pg_temp.basis_m('a8000000-0000-4000-8000-000000000001', true, false, false));
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select public.respond_to_coach_proposal_v1((select id from p where name = 'undo_a'), 'approve');
reset role;
update public.user_profiles set session_minutes = 50 where user_id = 'a8000000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select is(public.undo_coach_proposal_v1((select id from p where name = 'undo_a')) ->> 'status', 'undone',
  'the schedule is undone');
reset role;
select ok((select max(e.target_rpe) <= 7 from public.planned_exercises e
    join public.planned_workouts w on w.id = e.planned_workout_id
    join public.training_plan_versions v on v.id = w.plan_version_id
    where v.user_id = 'a8000000-0000-4000-8000-000000000001' and v.status = 'active'),
  'the plan that returns is held to the moderate health check');
select is((select session_minutes from public.user_profiles where user_id = 'a8000000-0000-4000-8000-000000000001'), 50::smallint,
  'a value the athlete changed since is left alone');
select is((select training_days::text from public.user_profiles where user_id = 'a8000000-0000-4000-8000-000000000001'), '{2,5}',
  'and a value still as the proposal set it goes back');

insert into p select 'undo_b', pg_temp.store('a8000000-0000-4000-8000-000000000001', 'training_schedule',
  pg_temp.schedule('goblet-squat', 40), pg_temp.basis_m('a8000000-0000-4000-8000-000000000001', true, false, false));
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select public.respond_to_coach_proposal_v1((select id from p where name = 'undo_b'), 'approve');
reset role;
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome, screened_at)
values ('a8000000-0000-4000-8000-000000000001', true, false, true, false, 'see_professional', now() + interval '1 minute');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a8000000-0000-4000-8000-000000000001';
select throws_ok($$select public.undo_coach_proposal_v1((select id from p where name = 'undo_b'))$$,
  '55000', 'a health professional must clear this athlete first',
  'nothing is restored while a health professional must clear the athlete');
reset role;

delete from public.user_accounts where id = 'a8000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from public.change_proposals
    where user_id = 'a8000000-0000-4000-8000-000000000001'), 0, 'deleting the account removes them');

select * from finish();
rollback;
