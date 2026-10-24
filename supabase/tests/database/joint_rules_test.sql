begin;
select no_plan();

-- B5-1: what pain reports and joint states change in today's session. Real athletes with a plan, a
-- check-in and reports: the safety routes (a red flag, a pain of 7 or more), the joint changes in every
-- kind (swap, limit, drop), the answers and their staleness, start_workout, B3 reading an adjusted
-- session, the in-workout swap options and the Coach context view. The pure pieces are in
-- pain_checks_test.sql, joint_states_test.sql and joint_swap_sweep_test.sql.

insert into auth.users(id, role)
select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated'
from generate_series(1, 42) n;

create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;

create temporary table t as select private.local_date_for(pg_temp.u(1)) as today;
grant select on t to authenticated;
create temporary table r(name text, j jsonb);
grant all on r to authenticated;
create temporary table wk(uid uuid primary key, version_id uuid, workout_id uuid,
  e1 uuid, e2 uuid, e3 uuid, e4 uuid, e5 uuid);
grant select on wk to authenticated;

-- An athlete with a full gym and one workout today: bench 4 x 5-8 at RPE 8 (knee low, back low, shoulder
-- high), leg extension 3 x 10-12 at RPE 8 (knee moderate), calf raise 3 x 12-15 with no RPE (all low),
-- cable fly 3 x 10-12 at RPE 8 with no catalog link (treated as moderate everywhere), Romanian
-- deadlift 3 x 8-10 at RPE 8 (back moderate). 16 sets in all.
create function pg_temp.make_athlete(p_uid uuid, p_shift integer default 0,
  p_equipment text[] default array['dumbbells', 'barbell', 'bench', 'cables', 'machines', 'pull_up_bar',
    'kettlebells', 'bands']) returns void language plpgsql as $$
declare
  pl uuid := gen_random_uuid(); v uuid := gen_random_uuid(); wo uuid := gen_random_uuid();
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  d uuid := gen_random_uuid(); e uuid := gen_random_uuid();
  wd integer := ((extract(isodow from private.local_date_for(p_uid))::integer - 1 + p_shift) % 7) + 1;
begin
  insert into public.user_profiles(user_id, experience_level, equipment)
  values (p_uid, 'intermediate', p_equipment);
  insert into public.training_plans(id, user_id, title, source) values (pl, p_uid, 'Strength', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, p_uid, pl, 1, 'active', 6, 1, '{}', 'Approved', now(), current_date);
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (wo, p_uid, v, 1, 'Lower A', 'Press', wd, 50, 'Warm up', 'Cool down');
  insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
    display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
  values (a, p_uid, wo, 1, 'Barbell bench press', 4, 5, 8, 8, 120, 'barbell-bench-press'),
    (b, p_uid, wo, 2, 'Leg extension', 3, 10, 12, 8, 60, 'leg-extension'),
    (c, p_uid, wo, 3, 'Standing calf raise', 3, 12, 15, null, 60, 'standing-calf-raise'),
    (d, p_uid, wo, 4, 'Cable fly', 3, 10, 12, 8, 60, null),
    (e, p_uid, wo, 5, 'Dumbbell Romanian deadlift', 3, 8, 10, 8, 90, 'dumbbell-romanian-deadlift');
  insert into wk values (p_uid, v, wo, a, b, c, d, e);
  delete from public.daily_computed_metrics where user_id = p_uid and local_date = private.local_date_for(p_uid);
  insert into public.daily_computed_metrics(user_id, local_date, recovery_score, data_confidence, scores_jsonb)
  values (p_uid, private.local_date_for(p_uid), null, 'low', jsonb_build_object('recovery_mode', 'night'));
end $$;

-- A completed bench session a week ago: 4 x 8 at 60 kg with three reps left (B3: add a step, 62.5 kg x 5).
create function pg_temp.seed_history(p_uid uuid) returns void language plpgsql as $$
declare sid uuid := gen_random_uuid(); pid uuid; d date := private.local_date_for(p_uid) - 7;
begin
  insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  select sid, p_uid, k.version_id, k.workout_id, d, 'UTC', 'completed', gen_random_uuid(),
    now() - interval '7 days', 3000, 8, 'athlete', 'manual' from wk k where k.uid = p_uid;
  insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
    exercise_order, status, performance_kind)
  select p_uid, sid, k.e1, 1, 'performed', 'prescribed' from wk k where k.uid = p_uid
  returning id into pid;
  insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
    rir, completed)
  select p_uid, pid, n, 8, 60, 3, true from generate_series(1, 4) n;
end $$;

-- The current check-in for today.
create function pg_temp.check_in(p_uid uuid, p_sleep integer, p_energy integer, p_sore integer,
  p_mood integer, p_pain integer) returns void language plpgsql as $$
declare d date := private.local_date_for(p_uid); rev integer;
begin
  select coalesce(max(revision), 0) + 1 into rev from public.daily_check_ins
  where user_id = p_uid and local_date = d;
  update public.daily_check_ins set superseded_at = now()
  where user_id = p_uid and local_date = d and superseded_at is null;
  insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key,
    sleep_quality, energy, soreness, hunger, mood, pain_severity, available_to_train)
  values (p_uid, d, 'UTC', rev, gen_random_uuid(), p_sleep, p_energy, p_sore, 3, p_mood, p_pain, true);
end $$;

-- A pain report stored in order, stored on the day it is dated unless p_stored_days_ago says otherwise.
create function pg_temp.report(p_uid uuid, p_days_ago integer, p_area text, p_sev integer,
  p_flags text[] default null, p_cleared boolean default false, p_stored_days_ago integer default null)
returns void language sql as $$
  insert into public.pain_reports(user_id, local_date, source, area, severity, red_flags,
    cleared_by_clinician, outcome, created_at)
  values (p_uid, private.local_date_for(p_uid) - p_days_ago, 'workout', p_area, p_sev, p_flags, p_cleared,
    private.pain_outcome(p_sev, p_flags), clock_timestamp() - coalesce(p_stored_days_ago, p_days_ago) * interval '1 day');
$$;

-- An athlete whose only exercise today is one catalog exercise, full gym.
create function pg_temp.make_single(p_uid uuid, p_slug text, p_name text) returns void language plpgsql as $$
declare
  pl uuid := gen_random_uuid(); v uuid := gen_random_uuid(); wo uuid := gen_random_uuid();
  a uuid := gen_random_uuid();
  wd integer := extract(isodow from private.local_date_for(p_uid))::integer;
begin
  insert into public.user_profiles(user_id, experience_level, equipment)
  values (p_uid, 'intermediate', array['dumbbells', 'barbell', 'bench', 'cables', 'machines', 'pull_up_bar',
    'kettlebells', 'bands']);
  insert into public.training_plans(id, user_id, title, source) values (pl, p_uid, 'One lift', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, p_uid, pl, 1, 'active', 6, 1, '{}', 'Approved', now(), current_date);
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (wo, p_uid, v, 1, 'One lift', 'Lift', wd, 50, 'Warm up', 'Cool down');
  insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
    display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
  values (a, p_uid, wo, 1, p_name, 4, 5, 8, 8, 120, p_slug);
  insert into wk values (p_uid, v, wo, a, null, null, null, null);
  insert into public.daily_computed_metrics(user_id, local_date, recovery_score, data_confidence, scores_jsonb)
  values (p_uid, private.local_date_for(p_uid), null, 'low', jsonb_build_object('recovery_mode', 'night'));
end $$;

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid, true);
end $$;

-- Set sizes per exercise of the session started with the given key.
create function pg_temp.sets_of(p_key uuid) returns bigint[] language sql as $$
  select array_agg(c order by o) from (
    select p.exercise_order o, count(s.id) c from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    left join public.exercise_sets s on s.exercise_performance_id = p.id
    where w.idempotency_key = p_key group by p.exercise_order) x;
$$;

-- The change of an exercise (by order) in a payload's changes.
create function pg_temp.change(p_j jsonb, p_order integer) returns jsonb language sql as $$
  select c from jsonb_array_elements(p_j -> 'changes') c where (c ->> 'exercise_order')::integer = p_order;
$$;

-- 1 to 3: athletes with history; 4 to 7: plain; 8 on: see each section.
select pg_temp.make_athlete(pg_temp.u(1));
select pg_temp.seed_history(pg_temp.u(1));
select pg_temp.make_athlete(pg_temp.u(3));
select pg_temp.seed_history(pg_temp.u(3));
select pg_temp.make_athlete(pg_temp.u(4));
select pg_temp.make_athlete(pg_temp.u(5));
select pg_temp.make_athlete(pg_temp.u(6));
select pg_temp.make_athlete(pg_temp.u(7));
select pg_temp.make_athlete(pg_temp.u(8));
select pg_temp.make_athlete(pg_temp.u(9));
select pg_temp.make_athlete(pg_temp.u(10));
select pg_temp.make_athlete(pg_temp.u(11));
select pg_temp.make_athlete(pg_temp.u(12), 1);
select pg_temp.make_athlete(pg_temp.u(13));
select pg_temp.make_athlete(pg_temp.u(14));
select pg_temp.make_athlete(pg_temp.u(15));
select pg_temp.make_athlete(pg_temp.u(16));
select pg_temp.make_athlete(pg_temp.u(17));
select pg_temp.make_athlete(pg_temp.u(18));
select pg_temp.make_athlete(pg_temp.u(19));
select pg_temp.make_athlete(pg_temp.u(20));
select pg_temp.make_athlete(pg_temp.u(34));
select pg_temp.make_athlete(pg_temp.u(35));

-- A day with no pain on record: schema 1.1 and the swaps the in-workout chip can offer ----------------------

select pg_temp.as_user(pg_temp.u(1)::text);
select pg_temp.check_in(pg_temp.u(1), 3, 3, 3, 3, 0);
insert into r select 'green', public.get_my_day_adjustment_v1((select today from t));
select is((select j ->> 'schema_version' from r where name = 'green'), '1.1', 'the payload is schema 1.1');
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'status'] from r where name = 'green'),
  array['green', 'none', 'none'], 'a good day with no pain asks for nothing');
select is((select j -> 'joint_states' from r where name = 'green'), '[]'::jsonb, 'no joint is in any state');
select is((select array(select o ->> 'kind' from jsonb_array_elements(j -> 'options') o) from r
    where name = 'green'), array['hold_load', 'reduce_sets', 'swap_to_easy_cardio'],
  'and no joint option appears among the choices');
select is((select array(select (o ->> 'exercise_order') from jsonb_array_elements(j -> 'exercise_joint_options') o)
    from r where name = 'green'), array['1', '2', '3', '4', '5'], 'every exercise of today has its swap options');
select is((select o -> 'joint_options' from r, jsonb_array_elements(j -> 'exercise_joint_options') o
    where name = 'green' and (o ->> 'exercise_order') = '1'),
  '{"knee": null, "back": null, "shoulder": {"slug": "machine-chest-press", "name": "Machine chest press"}}'::jsonb,
  'the bench has a gentler shoulder swap (a machine press) and nothing gentler for the knee or back');
select is((select o -> 'joint_options' from r, jsonb_array_elements(j -> 'exercise_joint_options') o
    where name = 'green' and (o ->> 'exercise_order') = '5'),
  '{"knee": null, "back": {"slug": "cable-pull-through", "name": "Cable pull-through"}, "shoulder": null}'::jsonb,
  'the Romanian deadlift has a gentler back swap');
select is((select count(*) from r, jsonb_array_elements(j -> 'exercise_joint_options') o
    where name = 'green' and (o ->> 'exercise_order') in ('2', '3', '4')
      and o -> 'joint_options' = '{"knee": null, "back": null, "shoulder": null}'::jsonb), 3::bigint,
  'the leg extension, the calf raise and the unrated fly have none: nothing is gentler, or nothing to anchor on');

-- A held knee changes the session on a good day -------------------------------------------------------------

select pg_temp.report(pg_temp.u(1), 1, 'knee', 3, array['locks_gives_way']);
insert into r select 'knee_held', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'status', j ->> 'safety_route']
    from r where name = 'knee_held'), array['green', 'joint_adjust', 'proposed', null],
  'a knee held on a clinician flag: today is a good day but the session changes, with no referral card');
select is((select j -> 'joint_states' from r where name = 'knee_held'),
  jsonb_build_array(jsonb_build_object('area', 'knee', 'state', 'held', 'since', (select today - 1 from t),
    'severity', 3, 'persistent', false, 'hold_outcome', 'clinician')), 'the joint state is reported');
select is((select array(select c ->> 'exercise_order' || ':' || (c ->> 'joint_action')
    from jsonb_array_elements(j -> 'changes') c order by (c ->> 'exercise_order')::integer)
    from r where name = 'knee_held'), array['2:drop', '4:drop'],
  'the leg extension has nothing gentler and is left out; so is the unrated fly');
select is((select pg_temp.change(j, 2) from r where name = 'knee_held'),
  jsonb_build_object('exercise_order', 2, 'planned_exercise_id', (select e2 from wk where uid = pg_temp.u(1)),
    'name', 'Leg extension', 'sets_from', 3, 'sets_to', 0, 'load_note', null, 'load_kg_from', null,
    'load_kg_to', null, 'reps_from', null, 'reps_to', null, 'rpe_to', null, 'joint_action', 'drop',
    'joint', 'knee', 'joint_state', 'held', 'swap_to_slug', null, 'swap_to_name', null,
    'range_note_code', null, 'range_note_codes', null),
  'a left-out exercise carries no sets, load, reps or effort, and says why');
select is((select array[j ->> 'sets_total_from', j ->> 'sets_total_to'] from r where name = 'knee_held'),
  array['16', '10'], 'six sets fewer');
select is((select j ->> 'explanation' from r where name = 'knee_held'),
  'Your knee is resting until you have been seen. 2 exercises left out today.',
  'in words that name no condition');
select is((select array(select o ->> 'kind' from jsonb_array_elements(j -> 'options') o) from r
    where name = 'knee_held'), array['hold_load', 'reduce_sets', 'swap_to_easy_cardio', 'joint_adjust'],
  'the joint adjustment is also one of the choices');
select is((select array(select o ->> 'sets_total_to' from jsonb_array_elements(j -> 'options') o) from r
    where name = 'knee_held'), array['10', '7', '0', '10'],
  'and every choice carries the left-out exercises: held loads 10 sets, a set fewer 7, easy cardio 0');
select is((select (o -> 'changes') @> jsonb_build_array(jsonb_build_object('exercise_order', 2,
      'joint_action', 'drop')) from r, jsonb_array_elements(j -> 'options') o
    where name = 'knee_held' and o ->> 'kind' = 'reduce_sets'), true,
  'a lighter session still leaves the held knee''s exercise out');

-- Accepting it, and the answer standing until something stricter arrives --------------------------------------

insert into r select 'knee_accepted', public.respond_to_day_adjustment_v1((select today from t), true);
select is((select array[j ->> 'status', j ->> 'kind', j ->> 'origin'] from r where name = 'knee_accepted'),
  array['accepted', 'joint_adjust', 'proposed'], 'one tap applies the joint adjustment');
select is((select array[kind, status, origin, rules_kind, band, jsonb_array_length(changes)::text]
    from public.day_adjustments where user_id = pg_temp.u(1) and superseded_at is null),
  array['joint_adjust', 'accepted', 'proposed', 'joint_adjust', 'green', '2'], 'the answer is stored');
select is((select inputs -> 'joint_states' -> 0 ->> 'state' from public.day_adjustments
    where user_id = pg_temp.u(1) and superseded_at is null), 'held', 'with the joint states the rules read');
select is((select metadata from public.audit_events where user_id = pg_temp.u(1)
    and action_code = 'day_adjustment_answered'),
  '{"kind": "joint_adjust", "accepted": true, "band": "green", "origin": "proposed",
    "rules_version": "readiness-v1"}'::jsonb, 'with an audit event of codes only');
insert into r select 'knee_again', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'status', j ->> 'sets_total_to', (j -> 'previous_answer' = 'null'::jsonb)::text]
    from r where name = 'knee_again'), array['accepted', '10', 'true'], 'the accepted answer stands');

-- A new pain report that asks for more: the answer no longer stands.
select pg_temp.report(pg_temp.u(1), 0, 'back', 5);
insert into r select 'back_new', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'status', j ->> 'kind', j -> 'previous_answer' ->> 'reason',
      j -> 'previous_answer' ->> 'status'] from r where name = 'back_new'),
  array['proposed', 'joint_adjust', 'new_data', 'accepted'],
  'a back that is now limited asks again, and says it is new data, not a new check-in');
select is((select array(select c ->> 'exercise_order' || ':' || (c ->> 'joint_action') || ':' || (c ->> 'joint')
    from jsonb_array_elements(j -> 'changes') c order by (c ->> 'exercise_order')::integer)
    from r where name = 'back_new'), array['2:drop:knee', '4:drop:knee', '5:limit:back'],
  'the held knee still leaves out two exercises; the back shortens the deadlift''s range');
select is((select pg_temp.change(j, 5) ->> 'range_note_code' from r where name = 'back_new'), 'back_hinge_range',
  'with the cue for a hinge and the back');
select is((select (pg_temp.change(j, 5) ->> 'rpe_to')::numeric from r where name = 'back_new'), 7::numeric,
  'effort at 7 or lower');
insert into r select 'back_accepted', public.respond_to_day_adjustment_v1((select today from t), true);
select is((select count(*) from public.day_adjustments where user_id = pg_temp.u(1)), 2::bigint,
  'the new answer is a new row');
select is((select count(*) from public.day_adjustments where user_id = pg_temp.u(1) and superseded_at is null),
  1::bigint, 'and the old one is superseded');
insert into r select 'back_stands', public.get_my_day_adjustment_v1((select today from t));
select is((select j ->> 'status' from r where name = 'back_stands'), 'accepted', 'and now it stands');

-- Starting the workout leaves the held knee's exercises out of the session.
select public.start_workout((select workout_id from wk where uid = pg_temp.u(1)), (select today from t),
  'UTC', 'b5500000-0000-4000-8000-000000000001');
select is(pg_temp.sets_of('b5500000-0000-4000-8000-000000000001'), array[4::bigint, 0, 3, 0, 3],
  'a left-out exercise gets no sets; the limited one keeps its three');
select is((select array_agg(p.status order by p.exercise_order) from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    where w.idempotency_key = 'b5500000-0000-4000-8000-000000000001'),
  array['unknown', 'unknown', 'unknown', 'unknown', 'unknown'],
  'no exercise is inferred as skipped');
select is((select w.day_adjustment_id from public.workout_sessions w
    where w.idempotency_key = 'b5500000-0000-4000-8000-000000000001'),
  (select a.id from public.day_adjustments a where a.user_id = pg_temp.u(1) and a.superseded_at is null),
  'the session is linked to the answer in force');

-- Coach context view: codes only, and the stored answer shown ---------------------------------------------------

select is((select array(select k from jsonb_object_keys(public.get_readiness_context_v1(pg_temp.u(1),
      (select today from t))) k order by k collate "C")),
  array['available', 'band', 'confidence', 'joint_states', 'kind', 'local_date', 'rules_version',
    'safety_route', 'schema_version', 'status', 'triggers', 'unavailable_reason'],
  'the Coach context view has exactly its twelve keys');
select is((select array[v ->> 'kind', v ->> 'status', v ->> 'unavailable_reason']
    from (select public.get_readiness_context_v1(pg_temp.u(1), (select today from t)) v) x),
  array['joint_adjust', 'accepted', 'session_started'], 'it shows the answer in force and that the session started');
select is((select v -> 'joint_states' from (select public.get_readiness_context_v1(pg_temp.u(1),
      (select today from t)) v) x),
  '[{"area": "knee", "state": "held", "persistent": false}, {"area": "back", "state": "limited", "persistent": false}]'::jsonb,
  'the joint states carry area, state and the lasting flag, and no severity or day');
select throws_ok($$select public.get_readiness_context_v1(pg_temp.u(1), (select today - 1 from t))$$, '22023', null,
  'only the athlete''s own today can be read');
select throws_ok($$select public.get_readiness_context_v1(null, (select today from t))$$, '22023', null,
  'and only for a real athlete');

-- A limited shoulder on a lighter day: swap, limit and the reduce rule together ----------------------------------

select pg_temp.as_user(pg_temp.u(3)::text);
select pg_temp.report(pg_temp.u(3), 1, 'shoulder', 5);
select pg_temp.check_in(pg_temp.u(3), 2, 3, 4, 3, 0);
insert into r select 'shoulder_reduce', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'status', (j -> 'triggers')::text]
    from r where name = 'shoulder_reduce'), array['amber', 'reduce_sets', 'proposed', '["sleep_poor", "sore"]'],
  'poor sleep and soreness: a set fewer');
select is((select pg_temp.change(j, 1) - 'planned_exercise_id' from r where name = 'shoulder_reduce'),
  jsonb_build_object('exercise_order', 1, 'name', 'Barbell bench press', 'sets_from', 4, 'sets_to', 3,
    'load_note', null, 'load_kg_from', null, 'load_kg_to', null, 'reps_from', null, 'reps_to', null,
    'rpe_to', 7, 'joint_action', 'swap', 'joint', 'shoulder', 'joint_state', 'limited',
    'swap_to_slug', 'machine-chest-press', 'swap_to_name', 'Machine chest press', 'range_note_code', null,
    'range_note_codes', null),
  'the bench is swapped for a machine press with a set fewer and effort 7, and carries no held load');
select is((select (pg_temp.change(j, 4) - 'planned_exercise_id')
    from r where name = 'shoulder_reduce'),
  jsonb_build_object('exercise_order', 4, 'name', 'Cable fly', 'sets_from', 3, 'sets_to', 2,
    'load_note', null, 'load_kg_from', null, 'load_kg_to', null, 'reps_from', null, 'reps_to', null,
    'rpe_to', 7, 'joint_action', 'limit', 'joint', 'shoulder', 'joint_state', 'limited',
    'swap_to_slug', null, 'swap_to_name', null, 'range_note_code', 'generic_pain_free',
    'range_note_codes', jsonb_build_array('generic_pain_free')),
  'the unrated fly keeps its range, shortened, with a set fewer');
select ok(not (pg_temp.change((select j from r where name = 'shoulder_reduce'), 2) ? 'joint_action'),
  'an exercise no joint touches carries no joint keys');
select is((select j ->> 'sets_total_to' from r where name = 'shoulder_reduce'), '11', 'a set fewer on five exercises');
select is((select j ->> 'explanation' from r where name = 'shoulder_reduce'),
  'You slept poorly and you''re sore. One set fewer on 5 exercises. Your shoulder needs a lighter touch this week. 1 exercise swapped and 1 exercise kept in a pain-free range.',
  'in one reading');
select public.respond_to_day_adjustment_v1((select today from t), true);
select public.start_workout((select workout_id from wk where uid = pg_temp.u(3)), (select today from t),
  'UTC', 'b5500000-0000-4000-8000-000000000003');
select is(pg_temp.sets_of('b5500000-0000-4000-8000-000000000003'), array[3::bigint, 2, 2, 2, 2],
  'the lighter session is built with a set fewer everywhere');
select is((select array_agg(p.performance_kind || ':' || p.performed_name order by p.exercise_order)
    from public.exercise_performances p join public.workout_sessions w on w.id = p.workout_session_id
    where w.idempotency_key = 'b5500000-0000-4000-8000-000000000003'),
  array['substituted:Machine chest press', 'prescribed:Leg extension', 'prescribed:Standing calf raise',
    'prescribed:Cable fly', 'prescribed:Dumbbell Romanian deadlift'],
  'the swapped exercise is created as the exercise it was swapped for; the others are as planned');
select is((select array[p.substitution_reason, p.status, p.planned_exercise_id::text,
      (select count(*) from public.exercise_sets s where s.exercise_performance_id = p.id)::text]
    from public.exercise_performances p join public.workout_sessions w on w.id = p.workout_session_id
    where w.idempotency_key = 'b5500000-0000-4000-8000-000000000003' and p.exercise_order = 1),
  array['pain', 'unknown', (select e1::text from wk where uid = pg_temp.u(3)), '3'],
  'it is a substitution made for pain, still tied to the planned exercise, with its sets and no load');
select is((select count(*) from public.exercise_performances p
    join public.workout_sessions w on w.id = p.workout_session_id
    where w.idempotency_key = 'b5500000-0000-4000-8000-000000000003' and p.exercise_order > 1
      and p.substitution_reason is not null), 0::bigint, 'and no other exercise carries a reason');
select is((select count(*) from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id
    join public.workout_sessions w on w.id = p.workout_session_id
    where w.idempotency_key = 'b5500000-0000-4000-8000-000000000003' and s.load_kg is not null), 0::bigint,
  'no load is written for any set');

-- Watch: a high-stress lift keeps its load and gets a shorter range ---------------------------------------------

select pg_temp.as_user(pg_temp.u(4)::text);
select pg_temp.report(pg_temp.u(4), 0, 'shoulder', 2);
select pg_temp.check_in(pg_temp.u(4), 3, 3, 3, 3, 0);
insert into r select 'shoulder_watch', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', pg_temp.change(j, 1) ->> 'joint_action',
      pg_temp.change(j, 1) ->> 'range_note_code', pg_temp.change(j, 1) ->> 'rpe_to',
      jsonb_array_length(j -> 'changes')::text] from r where name = 'shoulder_watch'),
  array['joint_adjust', 'limit', 'shoulder_press_depth', '7', '1'],
  'watch: only the high-stress bench is limited, with the cue for a press and effort 7');
select is((select j ->> 'explanation' from r where name = 'shoulder_watch'),
  'Your shoulder is on watch. 1 exercise kept in a pain-free range.', 'and the words say so');
select is((select j from r where name = 'shoulder_watch'),
  (replace(replace(replace(replace(replace(replace(replace($fx${"schema_version": "1.1", "local_date": "2026-10-24", "band": "green", "triggers": [], "kind": "joint_adjust", "changes": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "sets_from": 4, "sets_to": 4, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": 7, "joint_action": "limit", "joint": "shoulder", "joint_state": "watch", "swap_to_slug": null, "swap_to_name": null, "range_note_code": "shoulder_press_depth", "range_note_codes": ["shoulder_press_depth"]}], "explanation": "Your shoulder is on watch. 1 exercise kept in a pain-free range.", "status": "proposed", "available": true, "unavailable_reason": null, "safety_route": null, "confidence": "low", "missing": ["sleep", "recovery"], "cardio": null, "planned_workout_id": "b4200000-0000-4000-8000-000000000001", "workout_name": "Lower A", "sets_total_from": 16, "sets_total_to": 16, "previous_answer": null, "answered_at": null, "rules_version": "readiness-v1", "origin": null, "options": [{"kind": "reduce_sets", "explanation": "One set fewer on 5 exercises. Your shoulder is on watch. 1 exercise kept in a pain-free range.", "sets_total_to": 11, "changes": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "sets_from": 4, "sets_to": 3, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": 7, "joint_action": "limit", "joint": "shoulder", "joint_state": "watch", "swap_to_slug": null, "swap_to_name": null, "range_note_code": "shoulder_press_depth", "range_note_codes": ["shoulder_press_depth"]}, {"exercise_order": 2, "planned_exercise_id": "b4400000-0000-4000-8000-000000000002", "name": "Leg extension", "sets_from": 3, "sets_to": 2, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": 7}, {"exercise_order": 3, "planned_exercise_id": "b4400000-0000-4000-8000-000000000003", "name": "Standing calf raise", "sets_from": 3, "sets_to": 2, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": null}, {"exercise_order": 4, "planned_exercise_id": "b4400000-0000-4000-8000-000000000004", "name": "Cable fly", "sets_from": 3, "sets_to": 2, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": 7}, {"exercise_order": 5, "planned_exercise_id": "b4400000-0000-4000-8000-000000000005", "name": "Dumbbell Romanian deadlift", "sets_from": 3, "sets_to": 2, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": 7}], "cardio": null}, {"kind": "swap_to_easy_cardio", "explanation": "Try 20 to 30 minutes of easy walking, cycling or swimming at a pace you can talk through. It keeps you moving without adding strain. Your shoulder is on watch. 1 exercise kept in a pain-free range.", "sets_total_to": 0, "changes": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "sets_from": 4, "sets_to": 0, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": 7, "joint_action": "limit", "joint": "shoulder", "joint_state": "watch", "swap_to_slug": null, "swap_to_name": null, "range_note_code": "shoulder_press_depth", "range_note_codes": ["shoulder_press_depth"]}, {"exercise_order": 2, "planned_exercise_id": "b4400000-0000-4000-8000-000000000002", "name": "Leg extension", "sets_from": 3, "sets_to": 0, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": null}, {"exercise_order": 3, "planned_exercise_id": "b4400000-0000-4000-8000-000000000003", "name": "Standing calf raise", "sets_from": 3, "sets_to": 0, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": null}, {"exercise_order": 4, "planned_exercise_id": "b4400000-0000-4000-8000-000000000004", "name": "Cable fly", "sets_from": 3, "sets_to": 0, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": null}, {"exercise_order": 5, "planned_exercise_id": "b4400000-0000-4000-8000-000000000005", "name": "Dumbbell Romanian deadlift", "sets_from": 3, "sets_to": 0, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": null}], "cardio": {"minutes_min": 20, "minutes_max": 30, "effort": "easy", "talk_test": true, "vigorous_allowed": false}}, {"kind": "joint_adjust", "explanation": "Your shoulder is on watch. 1 exercise kept in a pain-free range.", "sets_total_to": 16, "changes": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "sets_from": 4, "sets_to": 4, "load_note": null, "load_kg_from": null, "load_kg_to": null, "reps_from": null, "reps_to": null, "rpe_to": 7, "joint_action": "limit", "joint": "shoulder", "joint_state": "watch", "swap_to_slug": null, "swap_to_name": null, "range_note_code": "shoulder_press_depth", "range_note_codes": ["shoulder_press_depth"]}], "cardio": null}], "signals": {"recovery_score": null, "recovery_confidence": "low", "recovery_mode": "night", "recovery_low": false, "sleep_minutes": null}, "joint_states": [{"area": "shoulder", "state": "watch", "since": "2026-10-24", "severity": 2, "persistent": false, "hold_outcome": null}], "exercise_joint_options": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "joint_options": {"knee": null, "back": null, "shoulder": {"slug": "machine-chest-press", "name": "Machine chest press"}}}, {"exercise_order": 2, "planned_exercise_id": "b4400000-0000-4000-8000-000000000002", "name": "Leg extension", "joint_options": {"knee": null, "back": null, "shoulder": null}}, {"exercise_order": 3, "planned_exercise_id": "b4400000-0000-4000-8000-000000000003", "name": "Standing calf raise", "joint_options": {"knee": null, "back": null, "shoulder": null}}, {"exercise_order": 4, "planned_exercise_id": "b4400000-0000-4000-8000-000000000004", "name": "Cable fly", "joint_options": {"knee": null, "back": null, "shoulder": null}}, {"exercise_order": 5, "planned_exercise_id": "b4400000-0000-4000-8000-000000000005", "name": "Dumbbell Romanian deadlift", "joint_options": {"knee": null, "back": {"slug": "cable-pull-through", "name": "Cable pull-through"}, "shoulder": null}}]}$fx$, 'b4200000-0000-4000-8000-000000000001', (select workout_id::text from wk where uid = pg_temp.u(4))), 'b4400000-0000-4000-8000-000000000001', (select e1::text from wk where uid = pg_temp.u(4))), 'b4400000-0000-4000-8000-000000000002', (select e2::text from wk where uid = pg_temp.u(4))), 'b4400000-0000-4000-8000-000000000003', (select e3::text from wk where uid = pg_temp.u(4))), 'b4400000-0000-4000-8000-000000000004', (select e4::text from wk where uid = pg_temp.u(4))), 'b4400000-0000-4000-8000-000000000005', (select e5::text from wk where uid = pg_temp.u(4))), '2026-10-24', (select today::text from t)))::jsonb,
  'the contract fixture day_adjustment_v1_1_joint.json is the real answer, key for key');

-- A joint on watch with only moderate exercises asks for nothing.
select pg_temp.as_user(pg_temp.u(5)::text);
select pg_temp.report(pg_temp.u(5), 0, 'back', 2);
select pg_temp.check_in(pg_temp.u(5), 3, 3, 3, 3, 0);
insert into r select 'back_watch', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', j ->> 'status', jsonb_array_length(j -> 'changes')::text]
    from r where name = 'back_watch'), array['none', 'none', '0'],
  'a watched back with no high-stress back exercise changes nothing');
select is((select j -> 'joint_states' -> 0 ->> 'state' from r where name = 'back_watch'), 'watch',
  'though the state is reported');

-- The athlete says they cannot train: no joint adjustment is offered.
select pg_temp.as_user(pg_temp.u(6)::text);
select pg_temp.report(pg_temp.u(6), 1, 'knee', 3, array['locks_gives_way']);
insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key, sleep_quality,
  energy, soreness, hunger, mood, pain_severity, available_to_train)
values (pg_temp.u(6), (select today from t), 'UTC', 1, gen_random_uuid(), 3, 3, 3, 3, 3, 0, false);
insert into r select 'cannot_train', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', jsonb_array_length(j -> 'options')::text] from r where name = 'cannot_train'),
  array['none', '0'], 'a held knee on a day the athlete cannot train proposes nothing');
select is((select j ->> 'explanation' from r where name = 'cannot_train'),
  'You said you can''t train today. Nothing in your plan changes. Your knee is on hold until you''ve had it checked.',
  'but the day still says the knee is on hold until it has been checked');

-- A swapped exercise keeps its sets and carries no load; a held knee with an easy-cardio day --------------------

select pg_temp.as_user(pg_temp.u(7)::text);
select pg_temp.report(pg_temp.u(7), 3, 'knee', 3, array['locks_gives_way']);
select pg_temp.check_in(pg_temp.u(7), 1, 1, 3, 3, 0);
insert into r select 'cardio_knee', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', j -> 'cardio' ->> 'minutes_max', j ->> 'sets_total_to']
    from r where name = 'cardio_knee'), array['red', 'swap_to_easy_cardio', '30', '0'],
  'a very poor night and no energy: easy cardio instead');
select is((select array(select c ->> 'exercise_order' || ':' || coalesce(c ->> 'joint_action', '-')
    from jsonb_array_elements(j -> 'changes') c order by (c ->> 'exercise_order')::integer)
    from r where name = 'cardio_knee'), array['1:-', '2:drop', '3:-', '4:drop', '5:-'],
  'the swap lists every exercise at 0 sets, and the held knee''s two as left out');
select public.respond_to_day_adjustment_v1((select today from t), true);
select public.start_workout((select workout_id from wk where uid = pg_temp.u(7)), (select today from t),
  'UTC', 'b5500000-0000-4000-8000-000000000007');
select is(pg_temp.sets_of('b5500000-0000-4000-8000-000000000007'), array[4::bigint, 0, 3, 0, 3],
  'starting the strength session anyway keeps the plan''s sets, but never the held knee''s exercises');

-- A lighter day and a held knee together -------------------------------------------------------------------------

select pg_temp.as_user(pg_temp.u(8)::text);
select pg_temp.report(pg_temp.u(8), 3, 'knee', 3, array['locks_gives_way']);
select pg_temp.check_in(pg_temp.u(8), 2, 2, 3, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), true);
select public.start_workout((select workout_id from wk where uid = pg_temp.u(8)), (select today from t),
  'UTC', 'b5500000-0000-4000-8000-000000000008');
select is(pg_temp.sets_of('b5500000-0000-4000-8000-000000000008'), array[3::bigint, 0, 2, 0, 2],
  'a set fewer on what stays, nothing for what a held knee leaves out');

-- A declined answer changes nothing.
select pg_temp.as_user(pg_temp.u(9)::text);
select pg_temp.report(pg_temp.u(9), 3, 'knee', 3, array['locks_gives_way']);
select pg_temp.check_in(pg_temp.u(9), 3, 3, 3, 3, 0);
select public.respond_to_day_adjustment_v1((select today from t), false);
select public.start_workout((select workout_id from wk where uid = pg_temp.u(9)), (select today from t),
  'UTC', 'b5500000-0000-4000-8000-000000000009');
select is(pg_temp.sets_of('b5500000-0000-4000-8000-000000000009'), array[4::bigint, 3, 3, 3, 3],
  'declining leaves the plan as written: Tracend withholds advice, it never blocks');

-- Red flags and severe pain route out ---------------------------------------------------------------------------

-- A red flag recorded in the workout.
select pg_temp.as_user(pg_temp.u(10)::text);
select pg_temp.check_in(pg_temp.u(10), 3, 3, 3, 3, 0);
select public.record_pain_check_v1((select today from t), 'workout', 'knee', 5, 'movement',
  array['rapid_swelling'], false, null, 'b5600000-0000-4000-8000-000000000010');
insert into r select 'flag', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'kind', j ->> 'status', j ->> 'safety_route', (j -> 'triggers')::text,
      jsonb_array_length(j -> 'options')::text, jsonb_array_length(j -> 'changes')::text]
    from r where name = 'flag'),
  array['red', 'none', 'none', 'clinician_today', '["red_flag:rapid_swelling"]', '0', '0'],
  'a quick swelling: see someone today, no training change, no choices');
select is((select j ->> 'explanation' from r where name = 'flag'),
  'Please see a doctor or physio today, before you train this area again. Tracend leaves training aside for today.',
  'in words that send the athlete on');
select is((select j from r where name = 'flag'),
  (replace(replace(replace(replace(replace(replace(replace($fx${"schema_version": "1.1", "local_date": "2026-10-24", "band": "red", "triggers": ["red_flag:rapid_swelling"], "kind": "none", "changes": [], "explanation": "Please see a doctor or physio today, before you train this area again. Tracend leaves training aside for today.", "status": "none", "available": true, "unavailable_reason": null, "safety_route": "clinician_today", "confidence": "low", "missing": ["sleep", "recovery"], "cardio": null, "planned_workout_id": "b4200000-0000-4000-8000-000000000001", "workout_name": "Lower A", "sets_total_from": 16, "sets_total_to": 16, "previous_answer": null, "answered_at": null, "rules_version": "readiness-v1", "origin": null, "options": [], "signals": {"recovery_score": null, "recovery_confidence": "low", "recovery_mode": "night", "recovery_low": false, "sleep_minutes": null}, "joint_states": [{"area": "knee", "state": "held", "since": "2026-10-24", "severity": 5, "persistent": false, "hold_outcome": "clinician_today"}], "exercise_joint_options": [{"exercise_order": 1, "planned_exercise_id": "b4400000-0000-4000-8000-000000000001", "name": "Barbell bench press", "joint_options": {"knee": null, "back": null, "shoulder": {"slug": "machine-chest-press", "name": "Machine chest press"}}}, {"exercise_order": 2, "planned_exercise_id": "b4400000-0000-4000-8000-000000000002", "name": "Leg extension", "joint_options": {"knee": null, "back": null, "shoulder": null}}, {"exercise_order": 3, "planned_exercise_id": "b4400000-0000-4000-8000-000000000003", "name": "Standing calf raise", "joint_options": {"knee": null, "back": null, "shoulder": null}}, {"exercise_order": 4, "planned_exercise_id": "b4400000-0000-4000-8000-000000000004", "name": "Cable fly", "joint_options": {"knee": null, "back": null, "shoulder": null}}, {"exercise_order": 5, "planned_exercise_id": "b4400000-0000-4000-8000-000000000005", "name": "Dumbbell Romanian deadlift", "joint_options": {"knee": null, "back": {"slug": "cable-pull-through", "name": "Cable pull-through"}, "shoulder": null}}]}$fx$, 'b4200000-0000-4000-8000-000000000001', (select workout_id::text from wk where uid = pg_temp.u(10))), 'b4400000-0000-4000-8000-000000000001', (select e1::text from wk where uid = pg_temp.u(10))), 'b4400000-0000-4000-8000-000000000002', (select e2::text from wk where uid = pg_temp.u(10))), 'b4400000-0000-4000-8000-000000000003', (select e3::text from wk where uid = pg_temp.u(10))), 'b4400000-0000-4000-8000-000000000004', (select e4::text from wk where uid = pg_temp.u(10))), 'b4400000-0000-4000-8000-000000000005', (select e5::text from wk where uid = pg_temp.u(10))), '2026-10-24', (select today::text from t)))::jsonb,
  'the contract fixture day_adjustment_v1_1_red_flag.json is the real answer, key for key');
select is((select v ->> 'triggers' from (select public.get_readiness_context_v1(pg_temp.u(10),
      (select today from t)) v) x), '[]', 'the Coach context view never carries the red-flag codes');
select is((select v ->> 'safety_route' from (select public.get_readiness_context_v1(pg_temp.u(10),
      (select today from t)) v) x), 'clinician_today', 'but does carry the route');

-- A check-in pain of 8 with an urgent flag: the strictest route wins, and every reason is named.
select pg_temp.as_user(pg_temp.u(11)::text);
select public.save_daily_check_in((select today from t), 'UTC', 'b5700000-0000-4000-8000-000000000011',
  '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
    "pain_severity": 8, "pain_area": "back", "pain_red_flags": ["bladder_bowel_saddle"]}'::jsonb);
insert into r select 'urgent', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'safety_route', (j -> 'triggers')::text, j ->> 'kind']
    from r where name = 'urgent'),
  array['red', 'urgent', '["pain_severe", "red_flag:bladder_bowel_saddle"]', 'none'],
  'bladder or bowel trouble with back pain: urgent care, over the check-in''s pain of 8');
select is((select j ->> 'explanation' from r where name = 'urgent'),
  'What you described needs urgent care. Call your local emergency number or go to an emergency department now. Tracend won''t suggest any training until you''ve been seen.',
  'with the emergency number named');

-- A pain of 8 with no flags from a new build: the report says see someone today (the check-in alone says refer).
select pg_temp.as_user(pg_temp.u(13)::text);
select public.save_daily_check_in((select today from t), 'UTC', 'b5700000-0000-4000-8000-000000000013',
  '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
    "pain_severity": 8, "pain_area": "knee", "pain_red_flags": []}'::jsonb);
insert into r select 'eight_report', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', (j -> 'triggers')::text] from r where name = 'eight_report'),
  array['clinician_today', '["pain_severe"]'], 'a pain of 8 in a new build is clinician today');

-- An older build sends the check-in pain only: B4's referral, unchanged.
select pg_temp.as_user(pg_temp.u(14)::text);
select pg_temp.check_in(pg_temp.u(14), 3, 3, 3, 3, 8);
insert into r select 'eight_old', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', (j -> 'triggers')::text, j ->> 'band'] from r where name = 'eight_old'),
  array['pain_referral', '["pain_severe"]', 'red'], 'an older build''s pain of 8 still routes as pain_referral');

-- A clinician flag on a mild pain; the check-in's own pain of 7 or more, being stricter than it, wins.
select pg_temp.as_user(pg_temp.u(15)::text);
select public.save_daily_check_in((select today from t), 'UTC', 'b5700000-0000-4000-8000-000000000015',
  '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
    "pain_severity": 3, "pain_area": "other", "pain_red_flags": ["fever_unwell"]}'::jsonb);
insert into r select 'fever', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', (j -> 'triggers')::text, j ->> 'band'] from r where name = 'fever'),
  array['clinician', '["red_flag:fever_unwell"]', 'red'], 'a fever with pain: see a doctor or physio');
select is((select j ->> 'explanation' from r where name = 'fever'),
  'Please book a doctor or physio before you train this area again. Tracend leaves training aside for today.',
  'with the words for a booked visit');
select pg_temp.report(pg_temp.u(15), 0, 'back', 2, array['night_pain']);
select pg_temp.check_in(pg_temp.u(15), 3, 3, 3, 3, 8);
insert into r select 'fever_and_eight', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', (j -> 'triggers')::text] from r where name = 'fever_and_eight'),
  array['pain_referral', '["pain_severe", "red_flag:fever_unwell", "red_flag:night_pain"]'],
  'a check-in pain of 8 outranks a clinician flag, and every reason is listed');

-- No check-in at all: the red flag still routes out.
select pg_temp.as_user(pg_temp.u(16)::text);
select public.record_pain_check_v1((select today from t), 'workout', 'back', 2, null, array['night_pain'], false,
  null, 'b5600000-0000-4000-8000-000000000016');
insert into r select 'no_check_in', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'band', j ->> 'safety_route', (j -> 'triggers')::text, j ->> 'confidence']
    from r where name = 'no_check_in'), array['red', 'clinician', '["red_flag:night_pain"]', null],
  'with no check-in a red flag still wins over "check in"');

-- A rest day, and after the session started.
select pg_temp.as_user(pg_temp.u(12)::text);
select public.record_pain_check_v1((select today from t), 'workout', 'shoulder', 4, null,
  array['chest_or_breath'], false, null, 'b5600000-0000-4000-8000-000000000012');
insert into r select 'rest_day', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', j ->> 'unavailable_reason', j ->> 'kind'] from r where name = 'rest_day'),
  array['urgent', 'rest_day', 'none'], 'a red flag routes out on a rest day too');
select pg_temp.as_user(pg_temp.u(17)::text);
select pg_temp.check_in(pg_temp.u(17), 3, 3, 3, 3, 0);
select public.start_workout((select workout_id from wk where uid = pg_temp.u(17)), (select today from t),
  'UTC', 'b5500000-0000-4000-8000-000000000017');
select public.record_pain_check_v1((select today from t), 'workout', 'knee', 4, 'movement',
  array['pop_or_sudden'], false, null, 'b5600000-0000-4000-8000-000000000017');
insert into r select 'started', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', j ->> 'unavailable_reason', j ->> 'band', j ->> 'status']
    from r where name = 'started'), array['clinician_today', 'session_started', 'red', 'none'],
  'and after the session started');

-- A red flag overrides an answer the athlete had already given.
select pg_temp.as_user(pg_temp.u(18)::text);
select pg_temp.check_in(pg_temp.u(18), 2, 3, 4, 3, 0);
insert into r select 'before_flag', public.respond_to_day_adjustment_v1((select today from t), true);
select is((select j ->> 'status' from r where name = 'before_flag'), 'accepted', 'a lighter session was accepted');
select public.record_pain_check_v1((select today from t), 'workout', 'knee', 5, 'movement',
  array['pop_or_sudden'], false, null, 'b5600000-0000-4000-8000-000000000018');
insert into r select 'after_flag', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', j ->> 'kind', j ->> 'status', jsonb_array_length(j -> 'changes')::text,
      j ->> 'answered_at', (j -> 'previous_answer' = 'null'::jsonb)::text] from r where name = 'after_flag'),
  array['clinician_today', 'none', 'none', '0', null, 'true'],
  'the card shows the referral and none of the stored answer');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), true)$$,
  '22023', null, 'a new answer is refused on a day with a safety route');
select throws_ok($$select public.respond_to_day_adjustment_v1(private.local_date_for(auth.uid()), false)$$,
  '22023', null, 'and so is undoing the old one');
select is((select array[status, kind] from public.day_adjustments
    where user_id = pg_temp.u(18) and superseded_at is null), array['accepted', 'reduce_sets'],
  'the stored answer is untouched');

-- Yesterday's red flag does not route today; it holds the joint.
select pg_temp.as_user(pg_temp.u(19)::text);
select pg_temp.report(pg_temp.u(19), 1, 'other', 4, array['chest_or_breath']);
select pg_temp.check_in(pg_temp.u(19), 3, 3, 3, 3, 0);
insert into r select 'yesterday', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', j ->> 'kind', j ->> 'band', j ->> 'status',
      jsonb_array_length(j -> 'options')::text, (j -> 'triggers')::text, j -> 'joint_states' -> 0 ->> 'area',
      j -> 'joint_states' -> 0 ->> 'hold_outcome'] from r where name = 'yesterday'),
  array['urgent', 'none', 'red', 'none', '0', '["red_flag:chest_or_breath"]', 'other', 'urgent'],
  'yesterday''s urgent flag still routes today: urgent, red, no change, no choices, until the athlete clears it');
select is((select j ->> 'explanation' from r where name = 'yesterday'),
  'What you described needs urgent care. Call your local emergency number or go to an emergency department now. Tracend won''t suggest any training until you''ve been seen.',
  'in the words that promise it');
select pg_temp.report(pg_temp.u(19), 0, 'other', 1, '{}', true);
insert into r select 'yesterday_cleared', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', j ->> 'kind', j -> 'joint_states' -> 0 ->> 'state']
    from r where name = 'yesterday_cleared'), array[null, 'none', 'watch'],
  'the athlete''s own clearance ends the route, and the area is on watch');

-- A hold lasts until the athlete's clearance: the route, the reminder and the day's reports ---------------------

-- Another athlete: an urgent flag three days ago still routes today.
select pg_temp.make_athlete(pg_temp.u(26));
select pg_temp.report(pg_temp.u(26), 3, 'other', 4, array['chest_or_breath']);
select pg_temp.as_user(pg_temp.u(26)::text);
insert into r select 'hold_d3', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', j ->> 'band', j ->> 'kind'] from r where name = 'hold_d3'),
  array['urgent', 'red', 'none'], 'an urgent flag from three days ago still routes today');

-- The strictest hold wins; a hold on a pain of 7 or more adds that reason.
select pg_temp.make_athlete(pg_temp.u(27));
select pg_temp.report(pg_temp.u(27), 2, 'other', 4, array['chest_or_breath']);
select pg_temp.report(pg_temp.u(27), 1, 'knee', 8);
select pg_temp.as_user(pg_temp.u(27)::text);
insert into r select 'hold_two', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', (j -> 'triggers')::text] from r where name = 'hold_two'),
  array['urgent', '["pain_severe", "red_flag:chest_or_breath"]'],
  'two holds, urgent and clinician today: urgent, with both reasons');
select pg_temp.make_athlete(pg_temp.u(28));
select pg_temp.report(pg_temp.u(28), 2, 'knee', 8);
select pg_temp.report(pg_temp.u(28), 0, 'shoulder', 2, array['night_pain']);
select pg_temp.as_user(pg_temp.u(28)::text);
insert into r select 'hold_and_today', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', (j -> 'triggers')::text] from r where name = 'hold_and_today'),
  array['clinician_today', '["pain_severe", "red_flag:night_pain"]'],
  'a hold on clinician today beats a clinician flag reported today');

-- A hold on a clinician outcome gives no route on later days, only the reminder, even with nothing to change.
select pg_temp.make_athlete(pg_temp.u(29));
select pg_temp.report(pg_temp.u(29), 2, 'other', 2, array['night_pain']);
select pg_temp.check_in(pg_temp.u(29), 3, 3, 3, 3, 0);
select pg_temp.as_user(pg_temp.u(29)::text);
insert into r select 'clinician_hold', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', j ->> 'kind', j ->> 'status'] from r where name = 'clinician_hold'),
  array[null, 'none', 'none'], 'a clinician hold from two days ago routes nothing today');
select is((select j ->> 'explanation' from r where name = 'clinician_hold'),
  'Your check-in looks fine. Train as planned. The pain you reported elsewhere is on hold until you''ve had it checked.',
  'but the day says it is on hold, though no exercise changes');
select is(private.hold_reminder('[{"area": "knee", "state": "held", "hold_outcome": "clinician"},
    {"area": "back", "state": "held", "hold_outcome": "clinician_today"},
    {"area": "shoulder", "state": "limited", "hold_outcome": null},
    {"area": "other", "state": "held", "hold_outcome": "clinician"}]'::jsonb, '[]'::jsonb),
  ' Your knee is on hold until you''ve had it checked. The pain you reported elsewhere is on hold until you''ve had it checked.',
  'the reminder names each area held on a clinician outcome, in order, and no other');
select is(private.hold_reminder('[{"area": "knee", "state": "held", "hold_outcome": "clinician"}]'::jsonb,
    '[{"joint": "knee", "joint_action": "drop"}]'::jsonb), '',
  'and is not said twice for an area whose exercises already carry its sentence');

-- A report stored today counts for today whatever its date; one stored yesterday does not.
select pg_temp.make_athlete(pg_temp.u(31));
select pg_temp.report(pg_temp.u(31), 1, 'back', 2, array['night_pain'], false, 0);
select pg_temp.as_user(pg_temp.u(31)::text);
insert into r select 'stored_today', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'safety_route', (j -> 'triggers')::text] from r where name = 'stored_today'),
  array['clinician', '["red_flag:night_pain"]'],
  'a clinician flag dated yesterday by a phone but stored today routes today');
select pg_temp.make_athlete(pg_temp.u(32));
select pg_temp.report(pg_temp.u(32), 1, 'back', 2, array['night_pain'], false, 1);
select pg_temp.as_user(pg_temp.u(32)::text);
insert into r select 'stored_yesterday', public.get_my_day_adjustment_v1((select today from t));
select is((select j ->> 'safety_route' from r where name = 'stored_yesterday'), null,
  'the same report stored yesterday does not');

-- A stored answer stands only while the joint changes it carries are the ones the rules ask for now --------------

select pg_temp.make_single(pg_temp.u(33), 'barbell-back-squat', 'Barbell back squat');
select pg_temp.report(pg_temp.u(33), 1, 'knee', 3, array['locks_gives_way']);
select pg_temp.check_in(pg_temp.u(33), 3, 3, 3, 3, 0);
select pg_temp.as_user(pg_temp.u(33)::text);
insert into r select 'squat_knee', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', pg_temp.change(j, 1) ->> 'joint_action',
      (pg_temp.change(j, 1) ->> 'swap_to_slug' is not null)::text] from r where name = 'squat_knee'),
  array['joint_adjust', 'swap', 'true'], 'a held knee swaps the back squat for something gentler');
select public.respond_to_day_adjustment_v1((select today from t), true);
insert into r select 'squat_stands', public.get_my_day_adjustment_v1((select today from t));
select is((select j ->> 'status' from r where name = 'squat_stands'), 'accepted', 'the accepted swap stands');
select pg_temp.report(pg_temp.u(33), 0, 'back', 5);
insert into r select 'squat_back', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'status', j -> 'previous_answer' ->> 'reason', pg_temp.change(j, 1) ->> 'joint_action',
      (pg_temp.change(j, 1) ->> 'swap_to_slug' is distinct from (select pg_temp.change(j, 1) ->> 'swap_to_slug'
        from r where name = 'squat_knee'))::text] from r where name = 'squat_back'),
  array['proposed', 'new_data', 'swap', 'true'],
  'a sore back too makes the first swap unsafe: the answer no longer stands and a different swap is offered');
select is((select (select c.back_stress from public.exercise_catalog c
      where c.slug = pg_temp.change(j, 1) ->> 'swap_to_slug') from r where name = 'squat_back'), 'low',
  'one that is low on the back');

-- The in-workout swap options meet the same ceilings as the day's swaps -----------------------------------
select is(private.joint_caps('[{"area": "knee", "state": "held"}, {"area": "back", "state": "limited"},
    {"area": "shoulder", "state": "watch"}, {"area": "other", "state": "held"}]'::jsonb, 'knee'),
  '{"back": "low", "shoulder": "moderate"}'::jsonb, 'ceilings for the other sore joints: limited low, watch moderate');
select is(private.joint_caps('[{"area": "knee", "state": "held"}, {"area": "back", "state": "limited"}]'::jsonb, 'back'),
  '{"knee": "low"}'::jsonb, 'a held joint allows low');
select is(private.joint_caps('[]'::jsonb, 'knee'), '{}'::jsonb, 'with no sore joint, no ceiling');
select is((select o -> 'joint_options' -> 'knee' from jsonb_array_elements(private.joint_options(pg_temp.u(33),
      (select workout_id from wk where uid = pg_temp.u(33)), '[{"area": "back", "state": "limited"}]'::jsonb)) o),
  private.joint_swap('barbell-back-squat', 'knee', 'low', array['dumbbells', 'barbell', 'bench', 'cables',
    'machines', 'pull_up_bar', 'kettlebells', 'bands'], 'intermediate', null, array['barbell-back-squat'],
    '{"back": "low"}'::jsonb), 'with a sore back the knee option carries the back''s ceiling');
select is((select o -> 'joint_options' -> 'knee' from jsonb_array_elements(private.joint_options(pg_temp.u(33),
      (select workout_id from wk where uid = pg_temp.u(33)), '[]'::jsonb)) o),
  private.joint_swap('barbell-back-squat', 'knee', 'low', array['dumbbells', 'barbell', 'bench', 'cables',
    'machines', 'pull_up_bar', 'kettlebells', 'bands'], 'intermediate', null, array['barbell-back-squat'],
    '{}'::jsonb), 'and with none it has none');
select is((select (select c.back_stress from public.exercise_catalog c where c.slug = o -> 'joint_options' -> 'knee' ->> 'slug')
    from jsonb_array_elements(private.joint_options(pg_temp.u(33),
      (select workout_id from wk where uid = pg_temp.u(33)), '[{"area": "back", "state": "limited"}]'::jsonb)) o),
  'low', 'so the option offered while the back is sore is low on the back');

-- Two cues for one exercise are both kept ------------------------------------------------------------------------
select pg_temp.make_single(pg_temp.u(36), 'barbell-overhead-press', 'Barbell overhead press');
select is((select c -> 'range_note_codes' from jsonb_array_elements(private.joint_changes(pg_temp.u(36),
      (select workout_id from wk where uid = pg_temp.u(36)),
      '[{"area": "back", "state": "limited"}, {"area": "shoulder", "state": "watch"}]'::jsonb, '[]'::jsonb)) c),
  '["back_press_seated", "shoulder_press_height"]'::jsonb, 'a press with a sore back and a watched shoulder keeps both cues');
select is((select c ->> 'range_note_code' from jsonb_array_elements(private.joint_changes(pg_temp.u(36),
      (select workout_id from wk where uid = pg_temp.u(36)),
      '[{"area": "back", "state": "limited"}, {"area": "shoulder", "state": "watch"}]'::jsonb, '[]'::jsonb)) c),
  'back_press_seated', 'the first is the joint that decides');
select is((select c -> 'range_note_codes' from jsonb_array_elements(private.joint_changes(pg_temp.u(36),
      (select workout_id from wk where uid = pg_temp.u(36)),
      '[{"area": "shoulder", "state": "watch"}]'::jsonb, '[]'::jsonb)) c),
  '["shoulder_press_height"]'::jsonb, 'one joint, one cue');

-- A day Coach already adjusted still protects the joints ------------------------------------------------------------

select pg_temp.report(pg_temp.u(34), 3, 'knee', 3, array['locks_gives_way']);
select pg_temp.check_in(pg_temp.u(34), 2, 3, 4, 3, 0);
update public.training_plan_versions set block_kind = 'next_session', ends_on = (select today from t),
  restores_version_id = id where user_id = pg_temp.u(34);
select pg_temp.as_user(pg_temp.u(34)::text);
insert into r select 'coach_joint', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', j ->> 'status', j ->> 'available',
      (j -> 'unavailable_reason' = 'null'::jsonb)::text,
      (select string_agg(o ->> 'kind', ',') from jsonb_array_elements(j -> 'options') o)]
    from r where name = 'coach_joint'),
  array['joint_adjust', 'proposed', 'true', 'true', 'joint_adjust'],
  'on a day Coach adjusted, only the joint adjustment is offered, never a second lighter session');
select is((select array(select c ->> 'exercise_order' || ':' || (c ->> 'joint_action')
    from jsonb_array_elements(j -> 'changes') c order by (c ->> 'exercise_order')::integer)
    from r where name = 'coach_joint'), array['2:drop', '4:drop'], 'with the held knee''s exercises left out');
select is((select j ->> 'band' from r where name = 'coach_joint'), 'amber', 'and the readiness band still read');
select is((select j ->> 'status' from (select public.respond_to_day_adjustment_v1((select today from t), true) j) x),
  'accepted', 'it can be accepted');
select public.start_workout((select workout_id from wk where uid = pg_temp.u(34)), (select today from t),
  'UTC', 'b5500000-0000-4000-8000-000000000034');
select is(pg_temp.sets_of('b5500000-0000-4000-8000-000000000034'), array[4::bigint, 0, 3, 0, 3],
  'and start_workout leaves those exercises out of the session Coach built');
select pg_temp.check_in(pg_temp.u(35), 2, 3, 4, 3, 0);
update public.training_plan_versions set block_kind = 'next_session', ends_on = (select today from t),
  restores_version_id = id where user_id = pg_temp.u(35);
select pg_temp.as_user(pg_temp.u(35)::text);
insert into r select 'coach_plain', public.get_my_day_adjustment_v1((select today from t));
select is((select array[j ->> 'kind', j ->> 'available', j ->> 'unavailable_reason'] from r where name = 'coach_plain'),
  array['none', 'false', 'coach_adjusted'], 'with no joint to protect, a Coach-adjusted day is unavailable as before');

-- A session done under an answer that left the exercise out earns no heavier load -------------------------------------
select is((select private.progression_decision(4, 5, 8, 8, 2.5, 7, false, false, false,
    '[{"load_kg": 60, "sets": 4, "min_reps": 8, "total_reps": 32, "min_rir": 3, "effort_known": true,
       "pain": false, "adjusted": true, "sets_planned": 0}]'::jsonb) ->> 'action'), 'hold',
  'an exercise left out for a joint but trained anyway does not earn add_load');
select is((select private.progression_decision(4, 5, 8, 8, 2.5, 7, false, false, false,
    '[{"load_kg": 60, "sets": 4, "min_reps": 8, "total_reps": 32, "min_rir": 3, "effort_known": true,
       "pain": false, "adjusted": true, "sets_planned": 0}]'::jsonb) ->> 'reason'), 'incomplete',
  'and the reason is the one B3 already has for work off the plan');
select is((select private.progression_decision(4, 5, 8, 8, 2.5, 7, false, false, false,
    '[{"load_kg": 60, "sets": 4, "min_reps": 8, "total_reps": 32, "min_rir": 3, "effort_known": true,
       "pain": false, "adjusted": true, "sets_planned": 4}]'::jsonb) ->> 'action'), 'add_load',
  'the same session under an answer that kept the sets still earns it');
select is((select private.progression_decision(4, 5, 8, 8, 2.5, 7, false, false, false,
    '[{"load_kg": 60, "sets": 4, "min_reps": 8, "total_reps": 32, "min_rir": 3, "effort_known": true,
       "pain": false}]'::jsonb) ->> 'action'), 'add_load', 'and so does one with no answer at all');

-- B3 reads the answers: an accommodation is not a bad performance ------------------------------------------------

-- Two sessions of bench at 4 reps (below the range of 5 to 8) at 60 kg, a week apart; the athlete's
-- answers (if any) are given by kind and by what they say about the bench.
create function pg_temp.log_bench(p_uid uuid, p_days integer, p_kind text, p_entry text, p_exercise integer)
returns void language plpgsql as $$
declare
  sid uuid := gen_random_uuid(); pid uuid; aid uuid := gen_random_uuid();
  d date := private.local_date_for(p_uid) - p_days; target uuid; changes jsonb;
begin
  select case p_exercise when 1 then k.e1 else k.e2 end into target from wk k where k.uid = p_uid;
  if p_kind is not null then
    changes := jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('planned_exercise_id', target,
      'sets_from', 4, 'sets_to', 4, 'joint_action', p_entry)));
    insert into public.day_adjustments(id, user_id, local_date, planned_workout_id, plan_version_id,
      rules_version, band, kind, origin, rules_kind, triggers, changes, cardio, inputs, inputs_hash, status)
    select aid, p_uid, d, k.workout_id, k.version_id, 'readiness-v1', 'green', p_kind, 'proposed', 'none',
      '{}', changes, case when p_kind = 'swap_to_easy_cardio' then
        '{"minutes_min": 20, "minutes_max": 30, "effort": "easy", "talk_test": true, "vigorous_allowed": false}'::jsonb end,
      '{}', repeat('a', 64), 'accepted' from wk k where k.uid = p_uid;
  end if;
  insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source, day_adjustment_id)
  select sid, p_uid, k.version_id, k.workout_id, d, 'UTC', 'completed', gen_random_uuid(),
    now() - p_days * interval '1 day', 3000, 8, 'athlete', 'manual',
    case when p_kind is not null then aid end from wk k where k.uid = p_uid;
  insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
    exercise_order, status, performance_kind)
  select p_uid, sid, k.e1, 1, 'performed', 'prescribed' from wk k where k.uid = p_uid returning id into pid;
  insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg, rir, completed)
  select p_uid, pid, n, 4, 60, 1, true from generate_series(1, 4) n;
end $$;

create function pg_temp.bench_target(p_uid uuid) returns text language sql as $$
  select (tg ->> 'action') || ':' || (tg ->> 'reason') || ':' || trim_scale((tg ->> 'load_kg')::numeric)::text
  from jsonb_array_elements(private.next_session_targets(p_uid)) tg
  where tg ->> 'planned_exercise_id' = (select e1::text from wk where uid = p_uid);
$$;

select pg_temp.log_bench(pg_temp.u(20), 14, null, null, 1);
select pg_temp.log_bench(pg_temp.u(20), 7, null, null, 1);
select is(pg_temp.bench_target(pg_temp.u(20)), 'lower:below_range:57.5',
  'two failed sessions with no answer: B3 lowers the load');

select pg_temp.make_athlete(pg_temp.u(21));
select pg_temp.make_athlete(pg_temp.u(22));
select pg_temp.make_athlete(pg_temp.u(23));
select pg_temp.make_athlete(pg_temp.u(24));
select pg_temp.make_athlete(pg_temp.u(25));
select pg_temp.log_bench(pg_temp.u(21), 14, 'joint_adjust', 'limit', 1);
select pg_temp.log_bench(pg_temp.u(21), 7, 'joint_adjust', 'limit', 1);
select is(pg_temp.bench_target(pg_temp.u(21)), 'hold:below_range:60',
  'done under a joint adjustment that limits the bench: held, not lowered');
select pg_temp.log_bench(pg_temp.u(22), 14, 'joint_adjust', 'swap', 1);
select pg_temp.log_bench(pg_temp.u(22), 7, 'joint_adjust', 'swap', 1);
select is(pg_temp.bench_target(pg_temp.u(22)), 'hold:below_range:60',
  'a swap entry for the exercise counts as adjusted too');
select pg_temp.log_bench(pg_temp.u(23), 14, 'swap_to_easy_cardio', null, 1);
select pg_temp.log_bench(pg_temp.u(23), 7, 'swap_to_easy_cardio', null, 1);
select is(pg_temp.bench_target(pg_temp.u(23)), 'lower:below_range:57.5',
  'under an easy-cardio answer that names no joint, a failed bench is still a failed bench');
select pg_temp.log_bench(pg_temp.u(24), 14, 'swap_to_easy_cardio', 'limit', 1);
select pg_temp.log_bench(pg_temp.u(24), 7, 'swap_to_easy_cardio', 'limit', 1);
select is(pg_temp.bench_target(pg_temp.u(24)), 'hold:below_range:60',
  'but under one that limits the bench for a joint, it is held');
select pg_temp.log_bench(pg_temp.u(25), 14, 'joint_adjust', 'limit', 2);
select pg_temp.log_bench(pg_temp.u(25), 7, 'joint_adjust', 'limit', 2);
select is(pg_temp.bench_target(pg_temp.u(25)), 'lower:below_range:57.5',
  'an answer that names another exercise leaves the bench judged as ever');

select * from finish();
rollback;
