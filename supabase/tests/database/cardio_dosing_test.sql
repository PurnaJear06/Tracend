begin;
select no_plan();

-- B5-4: cardio dosing (rules cardio-v1) and the training guidance 1.1 that carries it. Observed minutes
-- from Apple Health workouts: what counts, the cap, overlaps, the window, the missing-data rule; the
-- target by goal; what intensity is open today (screening, readiness band, joints); the days and
-- health checks that withhold it all; and the shape of the readers.

insert into auth.users(id, role)
select ('b5400000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'authenticated'
from generate_series(1, 30) n;

create function pg_temp.u(p_n integer) returns uuid language sql as $$
  select ('b5400000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid
$$;

create temporary table t as select private.local_date_for(pg_temp.u(1)) as today;
grant select on t to authenticated;
create temporary table r(name text, j jsonb);
grant all on r to authenticated;

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid, true);
end $$;

-- Apple Health summaries for each of these days ago.
create function pg_temp.summaries(p_n integer, p_days integer[]) returns void language plpgsql as $$
declare uid uuid := pg_temp.u(p_n); d integer;
begin
  foreach d in array p_days loop
    insert into public.daily_health_summaries(user_id, local_date, timezone, present_types, source_refs,
      source_checksum, completeness, observed_through)
    values (uid, private.local_date_for(uid) - d, 'UTC', array['workouts'], '[]'::jsonb, repeat('a', 64),
      'partial', now());
  end loop;
end $$;

-- A workout of p_type, p_minutes long, p_offset minutes after 08:00 UTC, p_days ago.
create function pg_temp.workout(p_n integer, p_days integer, p_type text, p_minutes integer,
  p_offset integer default 0) returns void language plpgsql as $$
declare
  uid uuid := pg_temp.u(p_n);
  day date := private.local_date_for(pg_temp.u(p_n)) - p_days;
  started timestamptz;
begin
  started := (day::timestamp + interval '8 hours' + p_offset * interval '1 minute') at time zone 'UTC';
  insert into public.health_workout_references(user_id, sample_id_hash, source_id_hash, activity_type,
    started_at, ended_at, duration_seconds, local_date)
  values (uid, md5(random()::text) || md5(random()::text), repeat('b', 64), p_type, started,
    started + p_minutes * interval '1 minute', p_minutes * 60, day);
end $$;

create function pg_temp.check_in(p_n integer, p_sleep integer, p_pain integer, p_energy integer default 3,
  p_sore integer default 3) returns void language plpgsql as $$
declare uid uuid := pg_temp.u(p_n);
begin
  insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key,
    sleep_quality, energy, soreness, hunger, mood, pain_severity, available_to_train)
  values (uid, private.local_date_for(uid), 'UTC', 1, gen_random_uuid(), p_sleep, p_energy, p_sore, 3, 3,
    p_pain, true);
end $$;

create function pg_temp.goal(p_n integer, p_type text) returns void language plpgsql as $$
begin
  insert into public.user_goals(user_id, goal_type, priority, status)
  values (pg_temp.u(p_n), p_type::public.goal_type, 1, 'active');
end $$;

-- The cardio week and the whole guidance for athlete p_n today.
create function pg_temp.week(p_n integer, p_band text default 'green') returns jsonb language sql as $$
  select private.cardio_week(pg_temp.u(p_n), (select today from t), p_band)
$$;
create function pg_temp.guidance(p_n integer) returns jsonb language sql as $$
  select private.training_guidance(pg_temp.u(p_n), (select today from t))
$$;

-- Rules and privileges ---------------------------------------------------------------------------------------------

select is(private.cardio_rules() ->> 'version', 'cardio-v1', 'rules version cardio-v1');
select is(private.cardio_rules() -> 'easy_minutes', private.readiness_rules() -> 'easy_cardio_minutes',
  'the easy-cardio dose is the one the readiness card quotes');
select ok(not has_function_privilege('authenticated', 'private.cardio_rules()', 'execute')
  and not has_function_privilege('authenticated', 'private.cardio_week(uuid, date, text)', 'execute')
  and not has_function_privilege('anon', 'private.cardio_week(uuid, date, text)', 'execute'),
  'the rules and the week are private');
select ok((select bool_and(prosecdef and proconfig = array['search_path=""']) from pg_proc
    where oid in ('private.cardio_week(uuid, date, text)'::regprocedure,
      'private.training_guidance(uuid, date)'::regprocedure)),
  'the week and the guidance are security definer with an empty search path');
select ok(has_function_privilege('authenticated', 'public.get_my_training_guidance_v1(date)', 'execute')
  and has_function_privilege('service_role', 'public.get_training_guidance_for_v1(uuid, date)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_training_guidance_for_v1(uuid, date)', 'execute'),
  'the readers keep their grants');

-- The week's numbers -------------------------------------------------------------------------------------------------

select pg_temp.summaries(1, array[0, 1, 2, 3, 4, 5, 6]);
select pg_temp.workout(1, 5, 'WALKING', 30);
select pg_temp.workout(1, 3, 'RUNNING', 45);
select pg_temp.workout(1, 1, 'BIKING', 60);
select is(pg_temp.week(1), jsonb_build_object('target_min', 150, 'stretch_max', null, 'done_min', 135,
    'intensity_known', false, 'vigorous_allowed', true, 'vigorous_sessions_max', 2,
    'vigorous_counts_as', 2, 'lift_separation_hours', 3, 'easy_hr_reserve_max', 60,
    'window_from', (select today from t) - 6, 'window_to', (select today from t)),
  'a week of walking, running and cycling: 135 of 150 minutes, with every rule figure');

-- Missing Apple Health data is never zero.
select pg_temp.summaries(2, array[0, 1, 2, 3]);
select pg_temp.workout(2, 1, 'RUNNING', 60);
select is(pg_temp.week(2) -> 'done_min', 'null'::jsonb, 'with four days of Apple Health data there is no figure');
select pg_temp.summaries(3, array[0, 1, 2, 3, 4]);
select pg_temp.workout(3, 1, 'RUNNING', 60);
select is(pg_temp.week(3) -> 'done_min', '60'::jsonb, 'with five days there is');
select pg_temp.summaries(4, array[0, 1, 2, 3, 4, 5, 6]);
select is(pg_temp.week(4) -> 'done_min', '0'::jsonb, 'a connected week with no cardio is 0, not missing');
select is(pg_temp.week(5) -> 'done_min', 'null'::jsonb, 'an athlete with no Apple Health data has no figure');

-- Only the window counts: today back to six days ago.
select pg_temp.summaries(6, array[0, 1, 2, 3, 4, 5, 7, 8]);
select pg_temp.workout(6, 6, 'WALKING', 20);
select pg_temp.workout(6, 7, 'WALKING', 99);
select pg_temp.workout(6, 0, 'WALKING', 10);
select is(pg_temp.week(6) -> 'done_min', '30'::jsonb,
  'a workout six days ago counts, seven days ago does not; a summary outside the window does not make the week');
select is(pg_temp.week(6) -> 'window_from', to_jsonb(((select today from t) - 6)::text), 'the window is seven days');

-- What counts: cardio only, in any letter case.
select pg_temp.summaries(7, array[0, 1, 2, 3, 4, 5, 6]);
select pg_temp.workout(7, 1, 'TRADITIONAL_STRENGTH_TRAINING', 60);
select pg_temp.workout(7, 2, 'FUNCTIONAL_STRENGTH_TRAINING', 60);
select pg_temp.workout(7, 3, 'OTHER', 60);
select pg_temp.workout(7, 4, 'SOCCER', 60);
select pg_temp.workout(7, 5, 'walking', 25);
select pg_temp.workout(7, 6, 'HIGH_INTENSITY_INTERVAL_TRAINING', 20);
select is(pg_temp.week(7) -> 'done_min', '45'::jsonb,
  'strength, other and sports are not cardio; walking in lower case and intervals are, counted as moderate');
select is(pg_temp.week(7) -> 'intensity_known', 'false'::jsonb, 'and the week says it does not know the intensity');

-- One workout counts for at most three hours; overlapping workouts count once.
select pg_temp.summaries(8, array[0, 1, 2, 3, 4, 5, 6]);
select pg_temp.workout(8, 1, 'RUNNING', 240);
select is(pg_temp.week(8) -> 'done_min', '180'::jsonb, 'a four-hour record counts for three hours');
select pg_temp.summaries(9, array[0, 1, 2, 3, 4, 5, 6]);
select pg_temp.workout(9, 1, 'WALKING', 30);
select pg_temp.workout(9, 1, 'WALKING', 30);
select is(pg_temp.week(9) -> 'done_min', '30'::jsonb, 'the same walk recorded by two devices counts once');
select pg_temp.summaries(10, array[0, 1, 2, 3, 4, 5, 6]);
select pg_temp.workout(10, 1, 'WALKING', 30);
select pg_temp.workout(10, 1, 'WALKING', 30, 15);
select is(pg_temp.week(10) -> 'done_min', '45'::jsonb, 'half-overlapping workouts count their union (45)');
select pg_temp.summaries(11, array[0, 1, 2, 3, 4, 5, 6]);
select pg_temp.workout(11, 1, 'WALKING', 30);
select pg_temp.workout(11, 1, 'WALKING', 30, 30);
select is(pg_temp.week(11) -> 'done_min', '60'::jsonb, 'back-to-back workouts count both');

-- One athlete's workouts are never another's.
select is(pg_temp.week(12) -> 'done_min', 'null'::jsonb, 'an athlete with no summaries sees none of the others'' minutes');

-- The target by goal ----------------------------------------------------------------------------------------------------------

select pg_temp.goal(13, 'fat_loss');
select pg_temp.goal(14, 'recomposition');
select pg_temp.goal(15, 'strength');
select pg_temp.goal(16, 'muscle_gain');
select pg_temp.goal(17, 'aesthetic');
select is(array[pg_temp.week(13) ->> 'stretch_max', pg_temp.week(14) ->> 'stretch_max',
    pg_temp.week(15) ->> 'stretch_max', pg_temp.week(16) ->> 'stretch_max',
    pg_temp.week(17) ->> 'stretch_max', pg_temp.week(18) ->> 'stretch_max'],
  array['300', '300', null, null, null, null],
  'fat loss and recomposition show the upper figure; the other goals and no goal do not');
select is(array[pg_temp.week(13) ->> 'target_min', pg_temp.week(15) ->> 'target_min'], array['150', '150'],
  'every goal has the 150-minute floor');

-- What intensity is open today -------------------------------------------------------------------------------------------------

-- Cleared and green: hard cardio is open. A low recovery score alone changes nothing (D9).
select pg_temp.check_in(19, 3, 0);
select is(pg_temp.guidance(19) -> 'cardio_week' ->> 'vigorous_allowed', 'true', 'cleared and green: hard cardio is open');
insert into public.daily_computed_metrics(user_id, local_date, recovery_score, data_confidence, scores_jsonb)
values (pg_temp.u(19), (select today from t), 20, 'high', '{"recovery_mode":"night"}');
select is(pg_temp.guidance(19) -> 'cardio_week' ->> 'vigorous_allowed', 'true',
  'a low recovery score alone does not close it: heart-derived signals never decide');

-- An amber day (a poor night), a red day, and no check-in at all are easy-only days.
select pg_temp.check_in(20, 2, 0);
select is(pg_temp.guidance(20) -> 'cardio_week' ->> 'vigorous_allowed', 'false', 'an amber day is easy-only');
select is(pg_temp.guidance(20) -> 'cardio_week' ->> 'vigorous_sessions_max', '2', 'the weekly cap is unchanged by the day');
select pg_temp.check_in(21, 1, 5);
select is(pg_temp.guidance(21) -> 'cardio_week' ->> 'vigorous_allowed', 'false', 'a red day (a very poor night and pain of 5) is easy-only');
select is(pg_temp.guidance(22) -> 'cardio_week' ->> 'vigorous_allowed', 'false',
  'with no check-in today the band is unknown and only easy cardio is offered');

-- The health check.
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values (pg_temp.u(23), true, true, false, false, 'moderate_until_cleared');
select pg_temp.check_in(23, 3, 0);
select is(pg_temp.guidance(23) -> 'cardio_week' ->> 'vigorous_allowed', 'false',
  'under moderate_until_cleared hard cardio is never open, even on a green day');
select is(pg_temp.guidance(23) -> 'cardio_week' ->> 'vigorous_sessions_max', '0', 'and the weekly cap is 0');
select is(pg_temp.guidance(23) -> 'cardio_week' ->> 'target_min', '150', 'the target still shows');

-- A joint that is limited closes hard cardio; one on watch does not.
select pg_temp.check_in(24, 3, 0);
select pg_temp.as_user(pg_temp.u(24)::text);
set local role authenticated;
select public.record_pain_check_v1((select today from t), 'check_in', 'knee', 5, 'movement', '{}', false, null,
  gen_random_uuid());
reset role;
select is(pg_temp.guidance(24) -> 'cardio_week' ->> 'vigorous_allowed', 'false', 'a limited knee: easy-only');
select pg_temp.check_in(25, 3, 0);
select pg_temp.as_user(pg_temp.u(25)::text);
set local role authenticated;
select public.record_pain_check_v1((select today from t), 'check_in', 'knee', 2, 'movement', '{}', false, null,
  gen_random_uuid());
reset role;
select is(pg_temp.guidance(25) -> 'cardio_week' ->> 'vigorous_allowed', 'true', 'a knee on watch does not close it');

-- Days and health checks that withhold the dose ------------------------------------------------------------------------------------

select pg_temp.check_in(26, 3, 8);
select is(pg_temp.guidance(26) -> 'cardio_week', 'null'::jsonb, 'a pain of 8 today: no cardio dose');
select is(pg_temp.guidance(26) ->> 'cardio_withheld', 'safety_route', 'because of the safety route');
select pg_temp.as_user(pg_temp.u(27)::text);
set local role authenticated;
select public.record_pain_check_v1((select today from t), 'check_in', 'back', 5, 'rest',
  array['bladder_bowel_saddle'], false, null, gen_random_uuid());
reset role;
select is(pg_temp.guidance(27) ->> 'cardio_withheld', 'safety_route', 'an urgent red flag withholds it too');
select is(pg_temp.guidance(27) -> 'cardio_week', 'null'::jsonb, 'with no dose');
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values (pg_temp.u(28), true, false, true, false, 'see_professional');
select is(pg_temp.guidance(28) ->> 'cardio_withheld', 'screening',
  'under see_professional no cardio dose is given: the health check says to see a professional first');
select is(pg_temp.guidance(28) -> 'cardio_week', 'null'::jsonb, 'so there is none');
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values (pg_temp.u(26), true, false, true, false, 'see_professional');
select is(pg_temp.guidance(26) ->> 'cardio_withheld', 'safety_route',
  'a safety route is named before the health check');
select is(pg_temp.guidance(1) ->> 'cardio_withheld', null, 'and an ordinary day withholds nothing');

-- The easy-cardio day and the weekly row quote one dose -----------------------------------------------------------------------------------

create function pg_temp.make_athlete(p_n integer) returns void language plpgsql as $$
declare
  uid uuid := pg_temp.u(p_n);
  pl uuid := gen_random_uuid(); v uuid := gen_random_uuid(); w uuid := gen_random_uuid();
begin
  insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level,
    training_days, session_minutes)
  values (uid, now(), true, 'beginner', array[2,5]::smallint[], 45);
  insert into public.training_plans(id, user_id, title, source) values (pl, uid, 'Strength', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, uid, pl, 1, 'active', 6, 3, '{}', 'Approved', now(), private.local_date_for(uid));
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (w, uid, v, 1, 'Upper A', 'Press', extract(isodow from private.local_date_for(uid))::integer, 50,
    'Warm up', 'Cool down');
  insert into public.planned_exercises(user_id, planned_workout_id, exercise_order, display_name_snapshot,
    set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
  values (uid, w, 1, 'Barbell bench press', 4, 5, 8, 8, 120, 'barbell-bench-press');
end $$;

select pg_temp.make_athlete(29);
select pg_temp.check_in(29, 1, 0, 1, 5);
select pg_temp.as_user(pg_temp.u(29)::text);
set local role authenticated;
insert into r select 'swap_day', public.get_my_day_adjustment_v1((select today from t), true);
reset role;
select is((select j ->> 'kind' from r where name = 'swap_day'), 'swap_to_easy_cardio',
  'a red readiness day offers easy cardio instead of the session');
select is((select array[j -> 'cardio' ->> 'minutes_min', j -> 'cardio' ->> 'minutes_max']
    from r where name = 'swap_day'),
  array[private.cardio_rules() -> 'easy_minutes' ->> 0, private.cardio_rules() -> 'easy_minutes' ->> 1],
  'its dose is the cardio rules'' easy-cardio dose');
select is(pg_temp.guidance(29) -> 'cardio_week' ->> 'vigorous_allowed', 'false',
  'and the weekly row, on that same red day, offers easy cardio only');

-- The readers ---------------------------------------------------------------------------------------------------------------------------

select pg_temp.as_user(pg_temp.u(1)::text);
set local role authenticated;
insert into r select 'mine', public.get_my_training_guidance_v1((select today from t));
reset role;
select is((select array(select k from jsonb_object_keys(j) k order by k collate "C") from r where name = 'mine'),
  array['cardio_week', 'cardio_withheld', 'deload', 'local_date', 'safety_route', 'schema_version'],
  'the guidance has exactly its contract keys');
select is((select j ->> 'schema_version' from r where name = 'mine'), '1.1', 'at schema version 1.1');
select is((select array(select k from jsonb_object_keys(j -> 'cardio_week') k order by k collate "C")
    from r where name = 'mine'),
  array['done_min', 'easy_hr_reserve_max', 'intensity_known', 'lift_separation_hours', 'stretch_max',
    'target_min', 'vigorous_allowed', 'vigorous_counts_as', 'vigorous_sessions_max', 'window_from',
    'window_to'],
  'the cardio week has exactly its contract keys');
select is((select array(select k from jsonb_object_keys(j -> 'deload') k order by k collate "C")
    from r where name = 'mine'),
  array['last_ended_on', 'proposal_id', 'reasons', 'status', 'suppressed_by', 'weeks_since'],
  'and the deload part its six');
select is((select j -> 'cardio_week' ->> 'done_min' from r where name = 'mine'), '135',
  'the athlete reads their own minutes');
select pg_temp.as_user(pg_temp.u(5)::text);
set local role authenticated;
insert into r select 'other', public.get_my_training_guidance_v1((select today from t));
reset role;
select is((select j -> 'cardio_week' -> 'done_min' from r where name = 'other'), 'null'::jsonb,
  'another athlete reads theirs, never the first''s');
select is(public.get_training_guidance_for_v1(pg_temp.u(1), (select today from t)) -> 'cardio_week' ->> 'done_min',
  '135', 'the service-role reader answers for the athlete it is asked about');
select is(public.get_training_guidance_for_v1(pg_temp.u(1), (select today from t)) ->> 'schema_version',
  '1.1', 'at the same version');

select * from finish();
rollback;
