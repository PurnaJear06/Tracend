begin;
select no_plan();

-- B5-3: when a deload could help (private.deload_signals, rules deload-v1). Real athletes with a plan,
-- logged sets, check-ins and approved deload blocks made through the Coach proposal path: each reason
-- alone and at its boundary, each suppression, the status, the history a block leaves, and the way a
-- running deload meets the safety route, the joint rules and the same-day adjustment. The week itself
-- is built and tested in TypeScript (coach_proposals/build_test.ts).

insert into auth.users(id, role)
select ('b5300000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'authenticated'
from generate_series(1, 60) n;

create function pg_temp.u(p_n integer) returns uuid language sql as $$
  select ('b5300000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid
$$;

create temporary table t as select private.local_date_for(pg_temp.u(1)) as today;
grant select on t to authenticated;
create temporary table wk(uid uuid primary key, version_id uuid, workout_id uuid, e1 uuid, e2 uuid);
grant select on wk to authenticated;
create temporary table p(name text primary key, id uuid);
grant all on p to authenticated;

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid, true);
end $$;

-- An athlete with a plan: one workout on today's weekday, bench 4 x 5-8 at RPE 8 and curl 3 x 8-12.
-- The plan version began p_activated days ago.
create function pg_temp.make_athlete(p_n integer, p_spw integer default 3, p_activated integer default 90,
  p_block_weeks integer default 6) returns void language plpgsql as $$
declare
  uid uuid := pg_temp.u(p_n);
  pl uuid := gen_random_uuid(); v uuid := gen_random_uuid(); w uuid := gen_random_uuid();
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid();
  today date := private.local_date_for(pg_temp.u(p_n));
begin
  insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level,
    training_days, session_minutes)
  values (uid, now(), true, 'beginner', array[2,5]::smallint[], 45);
  insert into public.training_plans(id, user_id, title, source) values (pl, uid, 'Strength', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, uid, pl, 1, 'active', p_block_weeks, p_spw, '{}', 'Approved',
    now() - p_activated * interval '1 day', today - p_activated);
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (w, uid, v, 1, 'Upper A', 'Press', extract(isodow from today)::integer, 50, 'Warm up', 'Cool down');
  insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
    display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
  values (a, uid, w, 1, 'Barbell bench press', 4, 5, 8, 8, 120, 'barbell-bench-press'),
    (b, uid, w, 2, 'Dumbbell curl', 3, 8, 12, null, 60, 'dumbbell-curl');
  insert into wk values (uid, v, w, a, b);
end $$;

-- A completed session p_days ago with no logged sets (it only counts as trained).
create function pg_temp.session(p_n integer, p_days integer) returns uuid language plpgsql as $$
declare sid uuid := gen_random_uuid(); athlete uuid := pg_temp.u(p_n);
begin
  insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  select sid, athlete, k.version_id, k.workout_id, private.local_date_for(athlete) - p_days, 'UTC', 'completed',
    gen_random_uuid(), now() - p_days * interval '1 day', 3000, 8, 'athlete', 'manual'
  from wk k where k.uid = pg_temp.u(p_n);
  return sid;
end $$;

-- Sessions on each of these days ago.
create function pg_temp.sessions(p_n integer, p_days integer[]) returns void language plpgsql as $$
declare d integer;
begin
  foreach d in array p_days loop perform pg_temp.session(p_n, d); end loop;
end $$;

-- A completed session p_days ago with the bench (p_bench_sets x p_bench_reps at p_bench_kg) and, when
-- p_curl_reps is given, the curl (p_curl_sets x p_curl_reps at p_curl_kg).
create function pg_temp.lifts(p_n integer, p_days integer, p_bench_reps integer, p_curl_reps integer default null,
  p_bench_sets integer default 4, p_curl_sets integer default 3, p_bench_kg numeric default 60,
  p_curl_kg numeric default 20) returns void language plpgsql as $$
declare sid uuid := pg_temp.session(p_n, p_days); athlete uuid := pg_temp.u(p_n); pid uuid;
begin
  insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
    exercise_order, status, performance_kind)
  select athlete, sid, k.e1, 1, 'performed', 'prescribed' from wk k where k.uid = pg_temp.u(p_n)
  returning id into pid;
  insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg, completed)
  select athlete, pid, s, p_bench_reps, p_bench_kg, true from generate_series(1, p_bench_sets) s;
  if p_curl_reps is not null then
    insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
      exercise_order, status, performance_kind)
    select athlete, sid, k.e2, 2, 'performed', 'prescribed' from wk k where k.uid = pg_temp.u(p_n)
    returning id into pid;
    insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg, completed)
    select athlete, pid, s, p_curl_reps, p_curl_kg, true from generate_series(1, p_curl_sets) s;
  end if;
end $$;

-- Both lifts stall: the same load and reps in three sessions (B3: lower, stall).
create function pg_temp.stall_both(p_n integer) returns void language plpgsql as $$
begin
  perform pg_temp.lifts(p_n, 16, 6, 8);
  perform pg_temp.lifts(p_n, 9, 6, 8);
  perform pg_temp.lifts(p_n, 2, 6, 8);
end $$;

-- A check-in p_days ago. p_current false stores it as a revision that a later one replaced.
create function pg_temp.check_in(p_n integer, p_days integer, p_sleep integer, p_energy integer,
  p_sore integer, p_mood integer, p_pain integer, p_current boolean default true)
returns void language plpgsql as $$
declare uid uuid := pg_temp.u(p_n);
begin
  insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key,
    sleep_quality, energy, soreness, hunger, mood, pain_severity, available_to_train, superseded_at)
  values (uid, private.local_date_for(uid) - p_days, 'UTC', case when p_current then 2 else 1 end,
    gen_random_uuid(), p_sleep, p_energy, p_sore, 3, p_mood, p_pain, true,
    case when p_current then null else now() end);
end $$;

-- Check-ins that read amber (a poor night: one point) or green, on each of these days ago.
create function pg_temp.amber(p_n integer, p_days integer[]) returns void language plpgsql as $$
declare d integer;
begin
  foreach d in array p_days loop perform pg_temp.check_in(p_n, d, 2, 3, 3, 3, 0); end loop;
end $$;
create function pg_temp.green(p_n integer, p_days integer[]) returns void language plpgsql as $$
declare d integer;
begin
  foreach d in array p_days loop perform pg_temp.check_in(p_n, d, 3, 3, 3, 3, 0); end loop;
end $$;

create function pg_temp.sleep(p_n integer, p_days integer, p_minutes integer) returns void language plpgsql as $$
declare uid uuid := pg_temp.u(p_n);
begin
  insert into public.daily_health_summaries(user_id, local_date, timezone, present_types, source_refs,
    source_checksum, completeness, observed_through, sleep_minutes)
  values (uid, private.local_date_for(uid) - p_days, 'UTC', array['sleep'], '[]'::jsonb, repeat('a', 64),
    'partial', now(), p_minutes);
end $$;

create function pg_temp.metrics(p_n integer, p_days integer, p_score integer, p_confidence text)
returns void language plpgsql as $$
declare uid uuid := pg_temp.u(p_n);
begin
  insert into public.daily_computed_metrics(user_id, local_date, recovery_score, data_confidence, scores_jsonb)
  values (uid, private.local_date_for(uid) - p_days, p_score, p_confidence,
    jsonb_build_object('recovery_mode', 'night'));
end $$;

-- The deload signals for athlete p_n today.
create function pg_temp.d(p_n integer) returns jsonb language sql as $$
  select private.deload_signals(pg_temp.u(p_n), (select today from t))
$$;

-- A block through the real proposal path: stored, then approved by the athlete. p_kind is the block's
-- kind, p_level its effort level (null: the key is left out, as older blocks had it), p_title its title.
-- The block's workout is p_exercise on today's weekday, 3 sets at effort 7.
create function pg_temp.block(p_n integer, p_kind text, p_level text, p_title text, p_ends_in integer,
  p_exercise text default 'bodyweight-squat') returns uuid language plpgsql as $$
declare
  uid uuid := pg_temp.u(p_n);
  today date := private.local_date_for(pg_temp.u(p_n));
  pid uuid;
  payload jsonb;
begin
  payload := jsonb_build_object('training', jsonb_strip_nulls(jsonb_build_object(
    'mode', 'block', 'block_kind', p_kind, 'intensity_level', p_level, 'title', p_title,
    'block_weeks', 1, 'ends_on', today + p_ends_in,
    'weekly_structure', jsonb_build_array(jsonb_build_object('workout_order', 1, 'name', 'Block A',
      'objective', 'Easy week', 'preferred_weekday', extract(isodow from today)::integer,
      'estimated_minutes', 30, 'warm_up_guidance', 'w', 'cool_down_guidance', 'c',
      'exercises', jsonb_build_array(jsonb_build_object('exercise_order', 1, 'slug', p_exercise,
        'name', 'Exercise', 'sets', 3, 'rep_min', 8, 'rep_max', 12, 'target_rpe', 7,
        'rest_seconds', 90, 'notes', '')))))));
  pid := (public.persist_coach_proposal_v1(uid,
    case p_kind when 'temporary_block' then 'temporary_block' else 'intensity_or_phase' end,
    p_title, 'Because you asked.', 'A benefit.', 'A downside.', 'medium',
    '[{"code":"TRAINING_STANDARD","label":"Limits","source":"policy_evaluation"}]',
    '{"rows":[{"label":"Sets","value":"9"}]}', '{"rows":[{"label":"Sets","value":"5"}]}',
    payload,
    jsonb_build_object('screening', 'cleared', 'nutrition_version_id', null, 'goal_id', null,
      'training_version_id', (select v.id from public.training_plan_versions v
        where v.user_id = uid and v.status = 'active')),
    today + p_ends_in, 72) ->> 'proposal_id')::uuid;
  return pid;
end $$;

create function pg_temp.approve(p_n integer, p_proposal uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', pg_temp.u(p_n)::text, true);
  set local role authenticated;
  perform public.respond_to_coach_proposal_v1(p_proposal, 'approve');
  reset role;
end $$;

-- A block that began and ended p_ago days ago (its last day), through the real path.
create function pg_temp.ended_block(p_n integer, p_level text, p_title text, p_ago integer)
returns uuid language plpgsql as $$
declare
  uid uuid := pg_temp.u(p_n);
  pid uuid := pg_temp.block(p_n, 'intensity', p_level, p_title, 6);
begin
  perform pg_temp.approve(p_n, pid);
  update public.training_plan_versions set ends_on = private.local_date_for(uid) - p_ago
  where user_id = uid and status = 'active';
  perform private.end_ended_plan_blocks(uid);
  return pid;
end $$;

-- Shape, grants and rules ----------------------------------------------------------------------------------

select is(private.deload_rules() ->> 'version', 'deload-v1', 'at rules version deload-v1');
select ok(not has_function_privilege('authenticated', 'private.deload_rules()', 'execute')
  and not has_function_privilege('authenticated', 'private.is_deload_proposal(text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'private.readiness_band_on(uuid, date)', 'execute')
  and not has_function_privilege('authenticated', 'private.deload_signals(uuid, date)', 'execute')
  and not has_function_privilege('authenticated', 'private.training_guidance(uuid, date)', 'execute')
  and not has_function_privilege('anon', 'private.deload_signals(uuid, date)', 'execute'),
  'the rules and helpers are private');
select ok(has_function_privilege('authenticated', 'public.get_my_training_guidance_v1(date)', 'execute')
  and not has_function_privilege('anon', 'public.get_my_training_guidance_v1(date)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_training_guidance_for_v1(uuid, date)', 'execute')
  and not has_function_privilege('anon', 'public.get_training_guidance_for_v1(uuid, date)', 'execute')
  and has_function_privilege('service_role', 'public.get_training_guidance_for_v1(uuid, date)', 'execute'),
  'athletes read their own guidance; only the service role reads another''s');
select ok((select bool_and(prosecdef and proconfig = array['search_path=""']) from pg_proc
    where oid in ('public.get_my_training_guidance_v1(date)'::regprocedure,
      'public.get_training_guidance_for_v1(uuid, date)'::regprocedure,
      'private.deload_signals(uuid, date)'::regprocedure,
      'private.readiness_band_on(uuid, date)'::regprocedure,
      'private.training_guidance(uuid, date)'::regprocedure)),
  'the readers and the signals are security definer with an empty search path');

-- Which blocks are deloads ------------------------------------------------------------------------------------

select ok(private.is_deload_proposal('intensity_or_phase', '{"training":{"intensity_level":"deload"}}'),
  'an effort block marked deload is a deload');
select ok(not private.is_deload_proposal('intensity_or_phase', '{"training":{"intensity_level":"moderate","title":"Deload until 1 Oct"}}'),
  'a block marked moderate is not, whatever its title says');
select ok(private.is_deload_proposal('intensity_or_phase', '{"training":{"title":"Deload until 31 Oct"}}'),
  'a block from before the mark is recognised by the title the builder gave it');
select ok(not private.is_deload_proposal('intensity_or_phase', '{"training":{"title":"Moderate effort until 31 Oct"}}'),
  'a moderate block with no mark is not a deload');
select ok(not private.is_deload_proposal('temporary_block', '{"training":{"intensity_level":"deload"}}'),
  'only an effort block can be a deload');
select ok(not private.is_deload_proposal('intensity_or_phase', '{"nutrition":{}}'),
  'a proposal with no training part is not');

-- No plan -------------------------------------------------------------------------------------------------------------

select is(pg_temp.d(42), jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb,
    'last_ended_on', null, 'weeks_since', null, 'proposal_id', null, 'proposal_origin', null, 'ends_on', null,
    'suppressed_by', 'no_plan'),
  'an athlete with no plan has nothing to deload');

-- A healthy athlete: nothing due ------------------------------------------------------------------------------------

select pg_temp.make_athlete(1, 3, 14);
select pg_temp.sessions(1, array[1, 3, 6, 9, 11, 13, 16, 19, 23]);
select is(pg_temp.d(1), jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb,
    'last_ended_on', null, 'weeks_since', 2, 'proposal_id', null, 'proposal_origin', null, 'ends_on', null,
    'suppressed_by', null),
  'a steady athlete in week 2 of a plan is not due, and the answer has exactly its eight keys');

-- performance_drop: two different exercises heading down ------------------------------------------------------------

select pg_temp.make_athlete(2);
select pg_temp.stall_both(2);
select is(pg_temp.d(2) -> 'reasons', '["performance_drop"]'::jsonb, 'two stalled lifts are a reason');
select is(pg_temp.d(2) ->> 'status', 'suggested', 'and the status is suggested');
select is(pg_temp.d(2) -> 'weeks_since', '12'::jsonb, 'with the weeks since the plan began (90 days)');

select pg_temp.make_athlete(3);
select pg_temp.lifts(3, 16, 6);
select pg_temp.lifts(3, 9, 6);
select pg_temp.lifts(3, 2, 6);
select is(pg_temp.d(3) ->> 'status', 'not_due', 'one stalled lift is not enough');
select is(pg_temp.d(3) -> 'reasons', '[]'::jsonb, 'and it names no reason');

select pg_temp.make_athlete(4);
select pg_temp.lifts(4, 16, 6);
select pg_temp.lifts(4, 9, 6, 6);
select pg_temp.lifts(4, 2, 6, 6);
select is(pg_temp.d(4) -> 'reasons', '["performance_drop"]'::jsonb,
  'a stall and two sessions under the rep range at one load are two lifts heading down');

select pg_temp.make_athlete(5);
select pg_temp.lifts(5, 16, 6, 8, 2, 2);
select pg_temp.lifts(5, 9, 6, 8, 2, 2);
select pg_temp.lifts(5, 2, 6, 8, 2, 2);
select is(pg_temp.d(5) ->> 'status', 'not_due',
  'sets cut short are held by the targets, not lowered, so they are not a drop');

-- run_down: amber or red days among the days with a check-in ---------------------------------------------------------

select pg_temp.make_athlete(6);
select pg_temp.sessions(6, array[1, 6, 12, 20]);
select pg_temp.amber(6, array[1, 2, 3, 4]);
select pg_temp.green(6, array[5, 6]);
select is(pg_temp.d(6) -> 'reasons', '["run_down"]'::jsonb, 'four amber days of seven are a reason');

select pg_temp.make_athlete(7);
select pg_temp.sessions(7, array[1, 6, 12, 20]);
select pg_temp.amber(7, array[1, 2, 3]);
select pg_temp.green(7, array[4, 5, 6]);
select is(pg_temp.d(7) ->> 'status', 'not_due', 'three amber days are not');

select pg_temp.make_athlete(8);
select pg_temp.sessions(8, array[1, 6, 12, 20]);
select pg_temp.amber(8, array[1, 2, 3, 4]);
select is(pg_temp.d(8) -> 'reasons', '["run_down"]'::jsonb,
  'days with no check-in are not counted against the athlete: four amber days of four are a reason');

select pg_temp.make_athlete(9);
select pg_temp.sessions(9, array[1, 6, 12, 20]);
select pg_temp.amber(9, array[1, 2, 3]);
select is(pg_temp.d(9) ->> 'status', 'not_due', 'and three amber days of three are not enough');

-- D9: a low recovery score with a clean check-in is a green day.
select pg_temp.make_athlete(10);
select pg_temp.sessions(10, array[1, 6, 12, 20]);
select pg_temp.green(10, array[0, 1, 2, 3, 4, 5, 6]);
select pg_temp.metrics(10, d, 20, 'high') from generate_series(0, 6) d;
select is(pg_temp.d(10) ->> 'status', 'not_due',
  'a low recovery score never makes a day amber without the check-in (heart-derived signals alone do not count)');

-- Short sleep is a point of its own.
select pg_temp.make_athlete(11);
select pg_temp.sessions(11, array[1, 6, 12, 20]);
select pg_temp.green(11, array[1, 2, 3, 4]);
select pg_temp.sleep(11, d, 300) from generate_series(1, 4) d;
select is(pg_temp.d(11) -> 'reasons', '["run_down"]'::jsonb, 'four short nights read amber');

select pg_temp.make_athlete(12);
select pg_temp.sessions(12, array[1, 6, 12, 20]);
select pg_temp.green(12, array[1, 2, 3, 4]);
select pg_temp.sleep(12, 1, 0);
select pg_temp.sleep(12, 2, 1000);
select pg_temp.sleep(12, 3, 359);
select pg_temp.sleep(12, 4, 360);
select is(pg_temp.d(12) ->> 'status', 'not_due',
  'no sleep recorded (0), an impossible value (1000) and 360 minutes are not short nights; 359 alone is one day');

-- A pain of 7 or more on past days reads red.
select pg_temp.make_athlete(13);
select pg_temp.sessions(13, array[1, 6, 12, 20]);
select pg_temp.check_in(13, d, 3, 3, 3, 3, 8) from generate_series(1, 4) d;
select is(pg_temp.d(13) -> 'reasons', '["run_down"]'::jsonb, 'four red days count');
select is(private.training_guidance(pg_temp.u(13), (select today from t)) ->> 'safety_route', null,
  'and they leave today without a safety route');

-- Today's pain routes out: no deload is offered that day.
select pg_temp.make_athlete(14);
select pg_temp.stall_both(14);
select pg_temp.check_in(14, 0, 3, 3, 3, 3, 8);
select is(pg_temp.d(14) ->> 'status', 'suggested', 'the signals alone would suggest a deload');
select is(private.training_guidance(pg_temp.u(14), (select today from t)) -> 'deload' ->> 'status', 'not_due',
  'but a pain of 8 today withholds it');
select is(private.training_guidance(pg_temp.u(14), (select today from t)) -> 'deload' ->> 'suppressed_by',
  'safety_route', 'because of the safety route');
select is(private.training_guidance(pg_temp.u(14), (select today from t)) ->> 'safety_route', 'pain_referral',
  'which the guidance names');

-- A red flag from the pain check routes out too.
select pg_temp.make_athlete(15);
select pg_temp.stall_both(15);
select pg_temp.as_user(pg_temp.u(15)::text);
set local role authenticated;
select public.record_pain_check_v1((select today from t), 'check_in', 'back', 5, 'rest',
  array['bladder_bowel_saddle'], false, null, gen_random_uuid());
reset role;
select is(private.training_guidance(pg_temp.u(15), (select today from t)) ->> 'safety_route', 'urgent',
  'an urgent red flag gives the day a safety route');
select is(private.training_guidance(pg_temp.u(15), (select today from t)) -> 'deload' ->> 'status', 'not_due',
  'and no deload is offered');

-- A superseded check-in and a day outside the window do not count.
select pg_temp.make_athlete(16);
select pg_temp.sessions(16, array[1, 6, 12, 20]);
select pg_temp.amber(16, array[1, 2, 3]);
select pg_temp.check_in(16, 4, 2, 3, 3, 3, 0, false);
select pg_temp.green(16, array[4]);
select pg_temp.amber(16, array[7]);
select is(pg_temp.d(16) ->> 'status', 'not_due',
  'a check-in a later one replaced, and an amber day eight days back, are not counted: three amber days');

-- block_done: the plan has run its length and was trained ------------------------------------------------------------

select pg_temp.make_athlete(17, 3, 42, 6);
select pg_temp.sessions(17, array[1, 3, 6, 9, 11, 13, 16, 19, 23]);
select is(pg_temp.d(17) -> 'reasons', '["block_done"]'::jsonb, 'six weeks into a six-week plan, with 9 of 12 sessions done, it is time');
select is(pg_temp.d(17) -> 'weeks_since', '6'::jsonb, 'six weeks since the plan began');

select pg_temp.make_athlete(18, 3, 42, 6);
select pg_temp.sessions(18, array[1, 3, 6, 9, 11, 13, 16, 19]);
select is(pg_temp.d(18) ->> 'status', 'not_due', '8 of 12 sessions is under three quarters');

select pg_temp.make_athlete(19, 3, 41, 6);
select pg_temp.sessions(19, array[1, 3, 6, 9, 11, 13, 16, 19, 23]);
select is(pg_temp.d(19) ->> 'status', 'not_due', 'one day short of six weeks is not yet (5 weeks)');
select is(pg_temp.d(19) -> 'weeks_since', '5'::jsonb, 'and says 5 weeks');

select pg_temp.make_athlete(20, 3, 28, 2);
select pg_temp.sessions(20, array[1, 3, 6, 9, 11, 13, 16, 19, 23]);
select is(pg_temp.d(20) -> 'reasons', '["block_done"]'::jsonb, 'a two-week plan is treated as four weeks, not two');
select pg_temp.make_athlete(21, 3, 27, 2);
select pg_temp.sessions(21, array[1, 3, 6, 9, 11, 13, 16, 19, 23]);
select is(pg_temp.d(21) ->> 'status', 'not_due', 'and three weeks is under that floor');

select pg_temp.make_athlete(22, 3, 56, 24);
select pg_temp.sessions(22, array[1, 3, 6, 9, 11, 13, 16, 19, 23]);
select is(pg_temp.d(22) -> 'reasons', '["block_done"]'::jsonb, 'a 24-week plan is treated as eight weeks, not 24');
select pg_temp.make_athlete(23, 3, 55, 24);
select pg_temp.sessions(23, array[1, 3, 6, 9, 11, 13, 16, 19, 23]);
select is(pg_temp.d(23) ->> 'status', 'not_due', 'and seven weeks is under that cap');

select pg_temp.make_athlete(24, 1, 42, 6);
select pg_temp.sessions(24, array[3, 10, 17]);
select is(pg_temp.d(24) -> 'reasons', '["block_done"]'::jsonb,
  'one session a week: 3 of 4 is exactly three quarters');

-- Suppressions ----------------------------------------------------------------------------------------------------------

-- A deload that ended 27 days ago still suppresses; one that ended 28 days ago does not.
select pg_temp.make_athlete(25);
select pg_temp.stall_both(25);
insert into p select 'ended27', pg_temp.ended_block(25, 'deload', 'Deload until 1 Oct', 27);
select is(pg_temp.d(25) ->> 'suppressed_by', 'recent_deload', 'a deload that ended 27 days ago suppresses a new one');
select is(pg_temp.d(25) ->> 'status', 'not_due', 'so nothing is suggested');
select is(pg_temp.d(25) -> 'reasons', '[]'::jsonb, 'and no reason is given');
select is(pg_temp.d(25) ->> 'last_ended_on', ((select today from t) - 27)::text, 'its end is reported');
select is((select count(*) from public.training_plan_versions where user_id = pg_temp.u(25)
    and block_kind = 'intensity' and status = 'superseded'), 1::bigint, 'it was a real, ended block');

select pg_temp.make_athlete(26);
select pg_temp.stall_both(26);
insert into p select 'ended28', pg_temp.ended_block(26, 'deload', 'Deload until 30 Sep', 28);
select is(pg_temp.d(26) ->> 'status', 'suggested', 'one that ended 28 days ago does not');
select is(pg_temp.d(26) -> 'weeks_since', '4'::jsonb,
  'and the weeks since count from the later of the plan''s start and the deload''s end (28 days: 4 weeks)');
select is(pg_temp.d(26) ->> 'last_ended_on', ((select today from t) - 28)::text, 'with its end reported');

-- An undone deload never ran, but the athlete took it back: new suggestions wait 14 days from that day.
select pg_temp.make_athlete(27);
select pg_temp.stall_both(27);
insert into p select 'undone', pg_temp.block(27, 'intensity', 'deload', 'Deload until 31 Oct', 6);
select pg_temp.approve(27, (select id from p where name = 'undone'));
select pg_temp.as_user(pg_temp.u(27)::text);
set local role authenticated;
select public.undo_coach_proposal_v1((select id from p where name = 'undone'));
reset role;
select is(pg_temp.d(27) ->> 'status', 'not_due', 'an undone deload holds the next suggestion back');
select is(pg_temp.d(27) ->> 'suppressed_by', 'declined_recently', 'as a declined one does');
select is(pg_temp.d(27) -> 'last_ended_on', 'null'::jsonb, 'and is not the last deload');

-- A moderate-effort block is not a deload.
select pg_temp.make_athlete(28);
select pg_temp.stall_both(28);
insert into p select 'moderate', pg_temp.ended_block(28, 'moderate', 'Moderate effort until 31 Oct', 5);
select is(pg_temp.d(28) ->> 'status', 'suggested', 'a moderate-effort block that just ended does not suppress');

-- A block approved before the builder marked its level is found by its title.
select pg_temp.make_athlete(29);
select pg_temp.stall_both(29);
insert into p select 'legacy', pg_temp.ended_block(29, null, 'Deload until 25 Oct', 5);
select is(pg_temp.d(29) ->> 'suppressed_by', 'recent_deload', 'an older deload is still a deload');

-- A deload running now.
select pg_temp.make_athlete(30);
select pg_temp.stall_both(30);
insert into p select 'running', pg_temp.block(30, 'intensity', 'deload', 'Deload until 31 Oct', 6);
select pg_temp.approve(30, (select id from p where name = 'running'));
select is(pg_temp.d(30) ->> 'status', 'running', 'a deload block that is the active version is running');
select is(pg_temp.d(30) ->> 'proposal_id', (select id::text from p where name = 'running'),
  'with its proposal');
select is(pg_temp.d(30) -> 'reasons', '[]'::jsonb, 'and no reasons');
select is(pg_temp.d(30) -> 'suppressed_by', 'null'::jsonb, 'and nothing suppressing it');

-- Another block running.
select pg_temp.make_athlete(31);
select pg_temp.stall_both(31);
insert into p select 'away', pg_temp.block(31, 'temporary_block', null, 'Bodyweight block', 6);
select pg_temp.approve(31, (select id from p where name = 'away'));
select is(pg_temp.d(31) ->> 'status', 'not_due', 'while a temporary block runs nothing is suggested');
select is(pg_temp.d(31) ->> 'suppressed_by', 'block_running', 'because a block is running');

-- A deload whose last day has passed but which the hourly job has not ended yet.
select pg_temp.make_athlete(32);
select pg_temp.stall_both(32);
insert into p select 'overdue', pg_temp.block(32, 'intensity', 'deload', 'Deload until 31 Oct', 6);
select pg_temp.approve(32, (select id from p where name = 'overdue'));
update public.training_plan_versions set ends_on = (select today from t) - 1
where user_id = pg_temp.u(32) and status = 'active';
select is(pg_temp.d(32) ->> 'status', 'not_due', 'a block past its last day is not running');
select is(pg_temp.d(32) ->> 'suppressed_by', 'block_running', 'but it still holds the plan until the job ends it');
select is(pg_temp.d(32) -> 'proposal_id', 'null'::jsonb, 'and names no proposal');

-- An open proposal.
select pg_temp.make_athlete(33);
select pg_temp.sessions(33, array[1, 6, 12, 20]);
insert into p select 'open', pg_temp.block(33, 'intensity', 'deload', 'Deload until 31 Oct', 6);
select is(pg_temp.d(33) ->> 'status', 'pending', 'an open deload proposal is pending, with nothing else due');
select is(pg_temp.d(33) ->> 'proposal_id', (select id::text from p where name = 'open'), 'and named');

select pg_temp.make_athlete(34);
select pg_temp.sessions(34, array[1, 6, 12, 20]);
insert into p select 'stale', pg_temp.block(34, 'intensity', 'deload', 'Deload until 31 Oct', 6);
update public.change_proposals set expires_at = now() - interval '1 minute'
where id = (select id from p where name = 'stale');
select is(pg_temp.d(34) ->> 'status', 'not_due', 'an expired proposal is not pending');

select pg_temp.make_athlete(35);
select pg_temp.sessions(35, array[1, 6, 12, 20]);
insert into p select 'old', pg_temp.ended_block(35, 'deload', 'Deload until 15 Oct', 10);
insert into p select 'again', pg_temp.block(35, 'intensity', 'deload', 'Deload until 31 Oct', 6);
select is(pg_temp.d(35) ->> 'status', 'pending',
  'a proposal the athlete asked for stays visible within a month of the last deload');
select is(pg_temp.d(35) ->> 'suppressed_by', 'recent_deload', 'while new suggestions stay held back');

select pg_temp.make_athlete(36);
select pg_temp.sessions(36, array[1, 6, 12, 20]);
insert into p select 'blocked', pg_temp.block(36, 'intensity', 'deload', 'Deload until 31 Oct', 6);
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values (pg_temp.u(36), true, false, true, false, 'see_professional');
select is(pg_temp.d(36) ->> 'status', 'not_due', 'under see_professional an open proposal is hidden: it cannot be approved');
select is(pg_temp.d(36) ->> 'suppressed_by', 'screening', 'because of the health check');
select is(pg_temp.d(36) -> 'proposal_id', 'null'::jsonb, 'and not named');

select pg_temp.make_athlete(37);
select pg_temp.stall_both(37);
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values (pg_temp.u(37), true, false, true, false, 'see_professional');
select is(pg_temp.d(37) ->> 'suppressed_by', 'screening', 'see_professional suppresses a suggestion');
select is(pg_temp.d(37) ->> 'status', 'not_due', 'and nothing is suggested');

select pg_temp.make_athlete(38);
select pg_temp.stall_both(38);
insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
  cleared_by_professional, outcome)
values (pg_temp.u(38), true, true, false, false, 'moderate_until_cleared');
select is(pg_temp.d(38) ->> 'status', 'suggested', 'moderate_until_cleared still allows a suggestion (easing is the safe direction)');

-- Too little training to deload from.
select pg_temp.make_athlete(39);
select pg_temp.lifts(39, 4, 6, 8);
select pg_temp.lifts(39, 3, 6, 8);
select pg_temp.lifts(39, 2, 6, 8);
select is(pg_temp.d(39) ->> 'suppressed_by', 'not_enough_training',
  'three sessions in one week of four is nothing to recover from');
select is(pg_temp.d(39) -> 'reasons', '[]'::jsonb, 'and no reason is given');

select pg_temp.make_athlete(44);
select pg_temp.lifts(44, 9, 6, 8);
select pg_temp.lifts(44, 3, 6, 8);
select pg_temp.lifts(44, 2, 6, 8);
select is(pg_temp.d(44) ->> 'suppressed_by', 'not_enough_training',
  'sessions in two of the last four weeks are not enough either');

select pg_temp.make_athlete(40);
select pg_temp.lifts(40, 16, 6, 8);
select pg_temp.lifts(40, 9, 6, 8);
select pg_temp.lifts(40, 2, 6, 8);
select is(pg_temp.d(40) ->> 'status', 'suggested', 'three of the last four weeks trained is enough');

-- The readers: own today only ------------------------------------------------------------------------------------------

select pg_temp.as_user(pg_temp.u(2)::text);
create temporary table r(name text, j jsonb);
grant all on r to authenticated;
set local role authenticated;
insert into r select 'mine', public.get_my_training_guidance_v1((select today from t));
reset role;
select is((select j -> 'deload' ->> 'status' from r where name = 'mine'), 'suggested',
  'an athlete reads their own deload status');
select pg_temp.as_user(pg_temp.u(1)::text);
set local role authenticated;
insert into r select 'other', public.get_my_training_guidance_v1((select today from t));
reset role;
select is((select j -> 'deload' ->> 'status' from r where name = 'other'), 'not_due',
  'another athlete reads theirs, never the first''s');
select is((select j ->> 'local_date' from r where name = 'other'), (select today::text from t),
  'for their own today');
set local role authenticated;
select throws_ok($$select public.get_my_training_guidance_v1((select today from t) - 1)$$, '22023', null,
  'yesterday is refused');
select throws_ok($$select public.get_my_training_guidance_v1((select today from t) + 1)$$, '22023', null,
  'and so is tomorrow');
select throws_ok($$select public.get_my_training_guidance_v1(null)$$, '22023', null, 'and no date');
reset role;
select pg_temp.as_user('');
select throws_ok($$select public.get_my_training_guidance_v1((select today from t))$$, '42501', null,
  'a caller with no identity cannot read');
select is(public.get_training_guidance_for_v1(pg_temp.u(2), (select today from t)) -> 'deload' ->> 'status',
  'suggested', 'the service-role reader answers for the athlete it is asked about');
select throws_ok($$select public.get_training_guidance_for_v1(pg_temp.u(2), (select today from t) - 1)$$,
  '22023', null, 'but only for their own today');
select throws_ok($$select public.get_training_guidance_for_v1(null, (select today from t))$$,
  '22023', null, 'and not for nobody');

-- Interplay: a running deload does not override a joint rule or a same-day adjustment --------------------------------------------

-- A deload week of a high-stress knee lift, with the knee limited (a pain of 5, no red flag).
select pg_temp.make_athlete(41, 3, 90);
insert into p select 'knee_week', pg_temp.block(41, 'intensity', 'deload', 'Deload until 31 Oct', 6, 'barbell-back-squat');
select pg_temp.approve(41, (select id from p where name = 'knee_week'));
select pg_temp.as_user(pg_temp.u(41)::text);
set local role authenticated;
select public.record_pain_check_v1((select today from t), 'check_in', 'knee', 5, 'movement', '{}', false, null,
  gen_random_uuid());
insert into r select 'knee_day', public.get_my_day_adjustment_v1((select today from t), true);
reset role;
select is((select j ->> 'kind' from r where name = 'knee_day'), 'joint_adjust',
  'a limited knee still changes the deload week''s squat: the joint rule applies on top of the plan');
select ok((select j -> 'changes' -> 0 ->> 'joint_action' in ('swap', 'drop') from r where name = 'knee_day'),
  'by swapping or leaving out the high-stress lift');
select is((select j -> 'changes' -> 0 ->> 'sets_from' from r where name = 'knee_day'), '3',
  'counted from the deload week''s own sets');
select is(pg_temp.d(41) ->> 'status', 'running', 'while the deload runs');

-- A poor night on a deload day is eased further by the same-day adjustment, never raised.
select pg_temp.make_athlete(43, 3, 90);
insert into p select 'poor_night', pg_temp.block(43, 'intensity', 'deload', 'Deload until 31 Oct', 6, 'barbell-back-squat');
select pg_temp.approve(43, (select id from p where name = 'poor_night'));
select pg_temp.check_in(43, 0, 1, 2, 3, 3, 0);
select pg_temp.as_user(pg_temp.u(43)::text);
set local role authenticated;
insert into r select 'poor_day', public.get_my_day_adjustment_v1((select today from t), true);
reset role;
select is((select j ->> 'kind' from r where name = 'poor_day'), 'reduce_sets',
  'a poor night on a deload day still eases the session');
select is((select array[j -> 'changes' -> 0 ->> 'sets_from', j -> 'changes' -> 0 ->> 'sets_to',
    j -> 'changes' -> 0 ->> 'rpe_to'] from r where name = 'poor_day'), array['3', '2', '6'],
  'one set fewer than the deload week''s three, and effort one point under its 7');

-- Review round 1 -------------------------------------------------------------------------------------------------------------------

-- A deload week for the athlete's bench: 2 sets of the plan's 5 to 8 at effort 7, 60 kg held. Stored, not approved.
create function pg_temp.bench_deload(p_n integer) returns uuid language plpgsql as $$
declare
  uid uuid := pg_temp.u(p_n);
  today date := private.local_date_for(pg_temp.u(p_n));
  payload jsonb;
begin
  payload := jsonb_build_object('training', jsonb_build_object('mode', 'block', 'block_kind', 'intensity',
    'intensity_level', 'deload', 'title', 'Deload until 31 Oct', 'block_weeks', 1, 'ends_on', today + 6,
    'weekly_structure', jsonb_build_array(jsonb_build_object('workout_order', 1, 'name', 'Upper A',
      'objective', 'Easy week', 'preferred_weekday', extract(isodow from today)::integer,
      'estimated_minutes', 30, 'warm_up_guidance', 'w', 'cool_down_guidance', 'c',
      'exercises', jsonb_build_array(jsonb_build_object('exercise_order', 1, 'slug', 'barbell-bench-press',
        'name', 'Barbell bench press', 'sets', 2, 'rep_min', 5, 'rep_max', 8, 'target_rpe', 7,
        'rest_seconds', 120, 'notes', '', 'start_load_kg', 60))))));
  return (public.persist_coach_proposal_v1(uid, 'intensity_or_phase', 'Deload until 31 Oct',
    'Because you asked.', 'A benefit.', 'A downside.', 'medium',
    '[{"code":"TRAINING_STANDARD","label":"Limits","source":"policy_evaluation"}]',
    '{"rows":[{"label":"Sets","value":"9"}]}', '{"rows":[{"label":"Sets","value":"5"}]}',
    payload,
    jsonb_build_object('screening', 'cleared', 'nutrition_version_id', null, 'goal_id', null,
      'training_version_id', (select v.id from public.training_plan_versions v
        where v.user_id = uid and v.status = 'active')),
    today + 6, 72) ->> 'proposal_id')::uuid;
end $$;

create function pg_temp.respond(p_n integer, p_proposal uuid, p_action text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', pg_temp.u(p_n)::text, true);
  set local role authenticated;
  perform public.respond_to_coach_proposal_v1(p_proposal, p_action);
  reset role;
end $$;

-- A completed bench session p_days ago, logged against the athlete's active plan version: p_sets x p_reps at
-- p_kg with p_rir reps left.
create function pg_temp.bench(p_n integer, p_days integer, p_sets integer, p_reps integer,
  p_kg numeric default 60, p_rir integer default 3) returns void language plpgsql as $$
declare
  uid uuid := pg_temp.u(p_n);
  sid uuid := gen_random_uuid();
  pid uuid; v uuid; w uuid; e uuid;
begin
  select pv.id, pw.id, pe.id into v, w, e
  from public.training_plan_versions pv
  join public.planned_workouts pw on pw.plan_version_id = pv.id and pw.user_id = pv.user_id
  join public.planned_exercises pe on pe.planned_workout_id = pw.id and pe.user_id = pw.user_id
  where pv.user_id = uid and pv.status = 'active' and pe.exercise_slug = 'barbell-bench-press';
  insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
    timezone, state, idempotency_key, completed_at, duration_seconds, session_effort,
    session_effort_source, completion_source)
  values (sid, uid, v, w, private.local_date_for(uid) - p_days, 'UTC', 'completed', gen_random_uuid(),
    now() - p_days * interval '1 day', 3000, 7, 'athlete', 'manual');
  insert into public.exercise_performances(user_id, workout_session_id, planned_exercise_id,
    exercise_order, status, performance_kind)
  values (uid, sid, e, 1, 'performed', 'prescribed') returning id into pid;
  insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg, rir, completed)
  select uid, pid, s, p_reps, p_kg, p_rir, true from generate_series(1, p_sets) s;
end $$;

-- The B3 target for the athlete's bench.
create function pg_temp.bench_target(p_n integer) returns jsonb language sql as $$
  select t from jsonb_array_elements(private.next_session_targets(pg_temp.u(p_n))) t
  where t ->> 'exercise_key' = 'barbell-bench-press'
$$;

-- H1: during a deload week B3 never steps the load up. The last session before the week was at the top
-- of the range with three reps left, which on a normal week is a step up.
select pg_temp.make_athlete(45);
select pg_temp.bench(45, 4, 4, 8);
select is(pg_temp.bench_target(45) ->> 'action', 'add_load', 'before the deload the top of the range with reps left adds load');
select is((pg_temp.bench_target(45) ->> 'load_kg')::numeric, 62.5, 'one step up');
insert into p select 'h1', pg_temp.bench_deload(45);
select pg_temp.approve(45, (select id from p where name = 'h1'));
select is(pg_temp.bench_target(45) ->> 'action', 'hold', 'in the deload week the same evidence holds');
select is(pg_temp.bench_target(45) ->> 'reason', 'deload', 'with the reason deload');
select is((pg_temp.bench_target(45) ->> 'load_kg')::numeric, 60.0, 'at the last working load');
select is(pg_temp.bench_target(45) ->> 'reps', '8', 'and the reps the athlete reached');
-- The second session of the lift in the same week reads the first deload session.
select pg_temp.bench(45, 0, 2, 8);
select is(pg_temp.bench_target(45) ->> 'action', 'hold', 'after the first deload session the target still holds');
select is(pg_temp.bench_target(45) ->> 'reason', 'deload', 'for the same reason');
select is((pg_temp.bench_target(45) ->> 'load_kg')::numeric, 60.0, 'at the same load');
select is(pg_temp.bench_target(45) -> 'basis' -> 'recent' -> 0 ->> 'adjusted', 'true',
  'and the deload session is marked adjusted, like a session done under an accepted day answer');

-- H2: deload sessions are not stall evidence. During the week:
select pg_temp.make_athlete(47);
select pg_temp.bench(47, 13, 4, 6, 60, 2);
select pg_temp.bench(47, 10, 4, 6, 60, 2);
select is(pg_temp.bench_target(47) ->> 'reason', 'within_range', 'two full sessions at one load are not yet a stall');
insert into p select 'h2_during', pg_temp.bench_deload(47);
select pg_temp.approve(47, (select id from p where name = 'h2_during'));
select pg_temp.bench(47, 1, 2, 6, 60, 3);
select is(pg_temp.bench_target(47) ->> 'action', 'add_reps',
  'a half-set deload session at the same load and reps is not the third stalled session');

-- and after it: two deload sessions, then a full session matching the pre-deload reps.
select pg_temp.make_athlete(46);
select pg_temp.bench(46, 40, 4, 6, 60, 2);
insert into p select 'h2_after', pg_temp.bench_deload(46);
select pg_temp.approve(46, (select id from p where name = 'h2_after'));
select pg_temp.bench(46, 17, 2, 6, 60, 3);
select pg_temp.bench(46, 16, 2, 6, 60, 3);
update public.training_plan_versions set ends_on = (select today from t) - 8
where user_id = pg_temp.u(46) and status = 'active';
select private.end_ended_plan_blocks(pg_temp.u(46));
select pg_temp.bench(46, 2, 4, 6, 60, 2);
select is((select count(*) from public.training_plan_versions where user_id = pg_temp.u(46)
    and status = 'active' and block_kind is null), 1::bigint, 'the regular plan is back');
select isnt(pg_temp.bench_target(46) ->> 'action', 'lower', 'the first full session after the deload is not a stall');
select is(pg_temp.bench_target(46) ->> 'action', 'add_reps', 'it asks for one more rep, as any full session below the range top does');
select is((select count(*) from jsonb_array_elements(pg_temp.bench_target(46) -> 'basis' -> 'recent') s
    where s ->> 'adjusted' = 'true'), 2::bigint, 'the two deload sessions are the ones marked adjusted');

-- M1: a pending deload proposal is not shown on a day with a safety route, and cannot be approved.
select pg_temp.make_athlete(48);
select pg_temp.sessions(48, array[1, 6, 12, 20]);
insert into p select 'routed', pg_temp.bench_deload(48);
select is(pg_temp.d(48) ->> 'status', 'pending', 'an open deload proposal is pending on an ordinary day');
select pg_temp.as_user(pg_temp.u(48)::text);
set local role authenticated;
select public.record_pain_check_v1((select today from t), 'check_in', 'back', 5, 'rest',
  array['bladder_bowel_saddle'], false, null, gen_random_uuid());
reset role;
select is(private.training_guidance(pg_temp.u(48), (select today from t)) ->> 'safety_route', 'urgent', 'an urgent red flag today');
select is(private.training_guidance(pg_temp.u(48), (select today from t)) -> 'deload' ->> 'status', 'not_due',
  'the pending proposal is withheld');
select is(private.training_guidance(pg_temp.u(48), (select today from t)) -> 'deload' -> 'proposal_id', 'null'::jsonb,
  'with no proposal id');
select is(private.training_guidance(pg_temp.u(48), (select today from t)) -> 'deload' ->> 'suppressed_by', 'safety_route',
  'because of the safety route');
select is(private.training_guidance(pg_temp.u(48), (select today from t)) -> 'deload' -> 'reasons', '[]'::jsonb,
  'and names no reason');
set local role authenticated;
select throws_ok($$select public.respond_to_coach_proposal_v1((select id from p where name = 'routed'), 'approve')$$,
  '55000', 'a deload cannot be approved on a day with a safety route', 'approving it is refused');
reset role;
select is((select status::text from public.change_proposals where id = (select id from p where name = 'routed')),
  'pending', 'and it stays open');

select pg_temp.make_athlete(49);
select pg_temp.sessions(49, array[1, 6, 12, 20]);
insert into p select 'referral', pg_temp.bench_deload(49);
select pg_temp.check_in(49, 0, 3, 3, 3, 3, 8);
select is(private.training_guidance(pg_temp.u(49), (select today from t)) ->> 'safety_route', 'pain_referral', 'a pain of 8 today');
select is(private.training_guidance(pg_temp.u(49), (select today from t)) -> 'deload' ->> 'suppressed_by', 'safety_route',
  'withholds the pending proposal too');
select is(private.training_guidance(pg_temp.u(49), (select today from t)) -> 'deload' -> 'proposal_id', 'null'::jsonb,
  'with no proposal id');
select pg_temp.as_user(pg_temp.u(49)::text);
set local role authenticated;
select throws_ok($$select public.respond_to_coach_proposal_v1((select id from p where name = 'referral'), 'approve')$$,
  '55000', 'a deload cannot be approved on a day with a safety route', 'and approving it is refused');
reset role;

-- M2: no new suggestion for 14 days after a deload proposal was declined or ran out unanswered.
select pg_temp.make_athlete(50);
select pg_temp.stall_both(50);
insert into p select 'dec13', pg_temp.bench_deload(50);
select pg_temp.respond(50, (select id from p where name = 'dec13'), 'decline');
update public.change_responses set created_at = now() - interval '13 days'
where proposal_id = (select id from p where name = 'dec13');
select is(pg_temp.d(50) ->> 'suppressed_by', 'declined_recently', 'declined 13 days ago: still held back');
select is(pg_temp.d(50) ->> 'status', 'not_due', 'so nothing is suggested');
select is(pg_temp.d(50) -> 'reasons', '[]'::jsonb, 'and no reason is given');

select pg_temp.make_athlete(51);
select pg_temp.stall_both(51);
insert into p select 'dec15', pg_temp.bench_deload(51);
select pg_temp.respond(51, (select id from p where name = 'dec15'), 'decline');
update public.change_responses set created_at = now() - interval '15 days'
where proposal_id = (select id from p where name = 'dec15');
select is(pg_temp.d(51) ->> 'status', 'suggested', 'declined 15 days ago: the signals suggest again');
select is(pg_temp.d(51) -> 'suppressed_by', 'null'::jsonb, 'with nothing in the way');

select pg_temp.make_athlete(52);
select pg_temp.stall_both(52);
insert into p select 'exp13', pg_temp.bench_deload(52);
update public.change_proposals set expires_at = now() - interval '13 days' where id = (select id from p where name = 'exp13');
select is(pg_temp.d(52) ->> 'suppressed_by', 'declined_recently', 'a proposal that ran out 13 days ago holds suggestions back');
select is(pg_temp.d(52) ->> 'status', 'not_due', 'so nothing is suggested');

select pg_temp.make_athlete(53);
select pg_temp.stall_both(53);
insert into p select 'exp15', pg_temp.bench_deload(53);
update public.change_proposals set expires_at = now() - interval '15 days' where id = (select id from p where name = 'exp15');
select is(pg_temp.d(53) ->> 'status', 'suggested', 'one that ran out 15 days ago does not');

-- A proposal a newer one replaced did not run out.
select pg_temp.make_athlete(55);
select pg_temp.stall_both(55);
insert into p select 'old_card', pg_temp.bench_deload(55);
insert into p select 'new_card', pg_temp.bench_deload(55);
select is((select status::text from public.change_proposals where id = (select id from p where name = 'old_card')),
  'expired', 'the newer card replaced the older');
select is(pg_temp.d(55) ->> 'status', 'pending', 'the newer card is the pending one');
select is(pg_temp.d(55) ->> 'suppressed_by', null, 'and the replaced one does not start a cool-down');

-- L4: a pending proposal built on a plan version that is no longer the current one is stale, not pending.
select pg_temp.make_athlete(54);
select pg_temp.sessions(54, array[1, 6, 12, 20]);
insert into p select 'moved', pg_temp.bench_deload(54);
select is(pg_temp.d(54) ->> 'status', 'pending', 'built on the current plan version it is pending');
update public.change_proposals
set basis = jsonb_set(basis, '{training_version_id}', to_jsonb(gen_random_uuid()::text))
where id = (select id from p where name = 'moved');
select is(pg_temp.d(54) ->> 'status', 'not_due', 'built on another plan version it is not offered');
select is(pg_temp.d(54) -> 'proposal_id', 'null'::jsonb, 'and not named');

-- Review round 2 -------------------------------------------------------------------------------------------------------------------

-- A card a newer one replaced: its own expiry later passes, which is not the athlete letting it run out.
update public.change_proposals set created_at = now() - interval '16 days', expires_at = now() - interval '13 days'
where id = (select id from p where name = 'old_card');
update public.change_proposals set created_at = now() - interval '15 days'
where id = (select id from p where name = 'new_card');
select is(pg_temp.d(55) ->> 'suppressed_by', null,
  'a card replaced by a newer one starts no cool-down, even after its own expiry has passed');
select is(pg_temp.d(55) ->> 'status', 'pending', 'and the newer card is still the pending one');

-- A card that expired because the plan moved on (the approval is answered "expired", with the reason on record).
select pg_temp.make_athlete(56);
select pg_temp.stall_both(56);
insert into p select 'stale_plan', pg_temp.bench_deload(56);
update public.change_proposals
set basis = jsonb_set(basis, '{training_version_id}', to_jsonb(gen_random_uuid()::text))
where id = (select id from p where name = 'stale_plan');
select pg_temp.approve(56, (select id from p where name = 'stale_plan'));
select is((select status::text from public.change_proposals where id = (select id from p where name = 'stale_plan')),
  'expired', 'approving a card built on another plan version expires it');
select is((select metadata ->> 'reason' from public.audit_events
    where target_id = (select id from p where name = 'stale_plan') and action_code = 'coach_proposal_expired'),
  'plan_changed', 'with the reason on record');
update public.change_proposals set expires_at = now() - interval '13 days'
where id = (select id from p where name = 'stale_plan');
select is(pg_temp.d(56) ->> 'suppressed_by', null, 'its old expiry, now past, starts no cool-down');
select is(pg_temp.d(56) ->> 'status', 'suggested', 'so the signals suggest again');

-- A card that ran out and was found out by an approval attempt is still a timeout: the cool-down applies.
select pg_temp.make_athlete(57);
select pg_temp.stall_both(57);
insert into p select 'late', pg_temp.bench_deload(57);
update public.change_proposals set expires_at = now() - interval '13 days' where id = (select id from p where name = 'late');
select pg_temp.approve(57, (select id from p where name = 'late'));
select is((select metadata ->> 'reason' from public.audit_events
    where target_id = (select id from p where name = 'late') and action_code = 'coach_proposal_expired'),
  'expired', 'an approval after the card ran out records the reason expired');
select is(pg_temp.d(57) ->> 'suppressed_by', 'declined_recently', 'and that timeout holds suggestions back');

-- A deload ended early keeps one end date; the 28 days count from it.
create function pg_temp.dat(p_n integer, p_ahead integer) returns jsonb language sql as $$
  select private.deload_signals(pg_temp.u(p_n), (select today from t) + p_ahead)
$$;
select pg_temp.make_athlete(58);
select pg_temp.stall_both(58);
insert into p select 'early', pg_temp.bench_deload(58);
select pg_temp.approve(58, (select id from p where name = 'early'));
select private.end_plan_block((select id from public.training_plan_versions
  where user_id = pg_temp.u(58) and status = 'active'));
select is(pg_temp.dat(58, 2) ->> 'last_ended_on', (select today::text from t), 'ended early on a day: that day is its end');
select is(pg_temp.dat(58, 17) ->> 'last_ended_on', (select today::text from t),
  'and it is the same day later on, not the day of the question');
select is(pg_temp.dat(58, 27) ->> 'suppressed_by', 'recent_deload', '27 days after the early end it still holds suggestions back');
select isnt(pg_temp.dat(58, 28) ->> 'suppressed_by', 'recent_deload', 'and 28 days after it no longer does');

select * from finish();
rollback;
