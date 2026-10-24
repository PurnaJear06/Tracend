begin;
select plan(90);

-- A trains; B is another athlete. Every id is d1 + kind + n: 40 athlete, 41 plan, 42 version, 43
-- planned workout, 44 planned exercise, 45 session, 46 performance, 47 idempotency key.
create function pg_temp.u(kind integer, n integer) returns uuid language sql as $$
  select ('d1' || lpad(kind::text, 2, '0') || '0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;

insert into auth.users(id, role) values
  (pg_temp.u(40, 1), 'authenticated'),
  (pg_temp.u(40, 2), 'authenticated');

-- Source 'imported' keeps the seed trigger from adding its own workouts.
insert into public.training_plans(id, user_id, title, source) values
  (pg_temp.u(41, 1), pg_temp.u(40, 1), 'Plan A', 'imported'),
  (pg_temp.u(41, 2), pg_temp.u(40, 2), 'Plan B', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date) values
  (pg_temp.u(42, 1), pg_temp.u(40, 1), pg_temp.u(41, 1), 1, 'active', 6, 3, '{}', 'Approved', now(),
   current_date),
  (pg_temp.u(42, 2), pg_temp.u(40, 2), pg_temp.u(41, 2), 1, 'active', 6, 1, '{}', 'Approved', now(),
   current_date),
  -- An earlier version of A's plan: a plan version holds at most 7 workouts.
  (pg_temp.u(42, 3), pg_temp.u(40, 1), pg_temp.u(41, 1), 2, 'superseded', 6, 2, '{}', 'Earlier',
   now(), current_date - 120);

create temporary table t as
  select private.local_date_for(pg_temp.u(40, 1)) today;
grant select on t to authenticated;
create temporary table h(name text primary key, j jsonb);
grant all on h to authenticated;

-- n: the workout and session; ver: its plan version (1 active, 3 earlier) and ord its place in it;
-- ago: days before today; done and total: sets logged and planned; timed: the sets carry start and
-- end times (the first set ends 30 minutes after the session began).
create temporary table fx(n integer primary key, ver integer, ord integer, name text, ago integer,
  done integer, total integer, timed boolean);
insert into fx values
  (1, 1, 1, 'Legs B', 1, 3, 5, true),   -- the owner's case: logged, never finished
  (2, 1, 2, 'Upper', 2, 1, 3, false),
  (3, 1, 3, 'Pull', 3, 2, 4, false),
  (4, 1, 4, 'Push', 9, 1, 2, false),    -- past the 7 days it can be saved, inside the 28 days Coach reads
  (5, 1, 5, 'Dup', 4, 1, 2, false),     -- the athlete finished the same workout that day (session 6)
  (7, 1, 6, 'Blank', 5, 0, 2, false),   -- nothing logged
  (8, 3, 1, 'Self', 6, 1, 2, false),    -- the athlete discarded it herself in the app
  (10, 3, 2, 'Edge', 7, 1, 2, false),   -- the last day it can still be saved
  (11, 3, 3, 'Ancient', 29, 1, 2, false), -- past the 28 days Coach looks back over
  (12, 3, 4, 'Offline', 2, 1, 2, false);  -- the athlete discarded it offline: the discard arrives late

insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
select pg_temp.u(43, n), pg_temp.u(40, 1), pg_temp.u(42, ver), ord, name, 'Train', 1, 50, 'Warm up',
  'Cool down' from fx;
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance) values
  (pg_temp.u(43, 9), pg_temp.u(40, 2), pg_temp.u(42, 2), 1, 'Any', 'Train', 1, 50, 'Warm up',
   'Cool down');
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds)
select pg_temp.u(44, n), pg_temp.u(40, 1), pg_temp.u(43, n), 1, 'Lift', total, 5, 8, 90 from fx;
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, rest_seconds) values
  (pg_temp.u(44, 9), pg_temp.u(40, 2), pg_temp.u(43, 9), 1, 'Lift', 2, 5, 8, 90);

-- Every session was left open 30 hours ago.
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at)
select pg_temp.u(45, n), pg_temp.u(40, 1), pg_temp.u(42, ver), pg_temp.u(43, n), t.today - ago, 'UTC',
  'in_progress', pg_temp.u(47, n), now() - interval '30 hours', now() - interval '30 hours'
from fx cross join t;
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at)
select pg_temp.u(45, 9), pg_temp.u(40, 2), pg_temp.u(42, 2), pg_temp.u(43, 9), t.today - 1, 'UTC',
  'in_progress', pg_temp.u(47, 9), now() - interval '30 hours', now() - interval '30 hours' from t;
insert into public.exercise_performances(id, user_id, workout_session_id, planned_exercise_id,
  exercise_order, status, performance_kind, performed_name)
select pg_temp.u(46, n), pg_temp.u(40, 1), pg_temp.u(45, n), pg_temp.u(44, n), 1, 'performed',
  'prescribed', 'Lift' from fx;
insert into public.exercise_performances(id, user_id, workout_session_id, planned_exercise_id,
  exercise_order, status, performance_kind, performed_name) values
  (pg_temp.u(46, 9), pg_temp.u(40, 2), pg_temp.u(45, 9), pg_temp.u(44, 9), 1, 'performed',
   'prescribed', 'Lift');
insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
  completed, started_at, completed_at)
select pg_temp.u(40, 1), pg_temp.u(46, n), g, 5, 80, g <= done,
  case when timed and g <= done
    then now() - interval '30 hours' + g * interval '30 minutes' - interval '2 minutes' end,
  case when timed and g <= done then now() - interval '30 hours' + g * interval '30 minutes' end
from fx, generate_series(1, fx.total) g;
insert into public.exercise_sets(user_id, exercise_performance_id, set_number, repetitions, load_kg,
  completed) values (pg_temp.u(40, 2), pg_temp.u(46, 9), 1, 5, 60, true),
  (pg_temp.u(40, 2), pg_temp.u(46, 9), 2, null, null, false);

-- Session 6: the athlete finished the same workout as session 5 that day.
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, local_date,
  timezone, state, idempotency_key, started_at, actual_started_at, completed_at)
select pg_temp.u(45, 6), pg_temp.u(40, 1), pg_temp.u(42, 1), pg_temp.u(43, 5), t.today - 4, 'UTC',
  'completed', pg_temp.u(47, 6), now() - interval '4 days', now() - interval '4 days',
  now() - interval '4 days' + interval '1 hour' from t;

-- Session 8 was discarded in the app: an audit event without the stale reason.
update public.workout_sessions set state = 'abandoned' where id = pg_temp.u(45, 8);
insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
values (pg_temp.u(40, 1), 'workout.abandoned', 'workout_session', pg_temp.u(45, 8), 'succeeded',
  jsonb_build_object('completed_sets', 1));

-- Surface -------------------------------------------------------------------------------------

select has_function('private', 'unfinished_workouts', array['uuid', 'date'], 'the rule exists');
select ok(not has_function_privilege('authenticated', 'private.unfinished_workouts(uuid,date)', 'execute'),
  'and no API role can run it');
select ok(not has_function_privilege('anon', 'public.get_my_unfinished_workout_v1()', 'execute'),
  'anon cannot read an unfinished workout');
select ok(has_function_privilege('authenticated', 'public.get_my_unfinished_workout_v1()', 'execute'),
  'the athlete can');
select ok(not has_function_privilege('anon',
    'public.resolve_unfinished_workout_v1(uuid,text,numeric)', 'execute'),
  'anon cannot answer one');
select ok(has_function_privilege('authenticated',
    'public.resolve_unfinished_workout_v1(uuid,text,numeric)', 'execute'),
  'the athlete can');

-- The redefined functions keep what they had -----------------------------------------------------

select ok((select p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""']
    from pg_proc p where p.oid =
      'private.complete_workout_session(uuid,integer,integer,smallint,numeric,text,text)'::regprocedure),
  'completing a session is still security definer with an empty search path');
select ok((select p.prosrc like '%closed_as_stale := session.state = ''abandoned'' and private.workout_closed_as_stale(session.id)%'
      and p.prosrc like '%raise exception ''session was discarded''%'
      and p.prosrc like '%raise exception ''stale client revision''%'
      and p.prosrc like '%raise exception ''complete at least one set''%'
      and p.prosrc like '%coverage := completed_sets::numeric / greatest(total_sets, 1)%'
      and p.prosrc like '%least(p_duration_seconds, 10800)%'
      and p.prosrc like '%actual_ended_at = coalesce(actual_ended_at, case when closed_as_stale%'
      and p.prosrc like '%least(now(), coalesce(actual_started_at, started_at) + capped_duration * interval ''1 second'')%'
      and p.prosrc like '%''workout.completed''%'
    from pg_proc p where p.oid =
      'private.complete_workout_session(uuid,integer,integer,smallint,numeric,text,text)'::regprocedure),
  'and still applies the stale-close, revision, set, coverage, cap and audit steps it had');
select ok((select p.prosrc like '%capped_duration := case when p_duration_seconds is null and closed_as_stale then null%'
      and p.prosrc like '%case when capped_duration is null then null%'
    from pg_proc p where p.oid =
      'private.complete_workout_session(uuid,integer,integer,smallint,numeric,text,text)'::regprocedure),
  'the new hunk: no duration for a stale-closed session stays unknown');
select ok((select not p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
    from pg_proc p where p.oid = 'private.workout_closed_as_stale(uuid)'::regprocedure),
  'the stale-close test is still a stable invoker function with an empty search path');
select ok((select p.prosrc like '%e.action_code = ''workout.abandoned'' and e.metadata->>''reason'' = ''stale''%'
      and p.prosrc like '%d.action_code = ''workout.unfinished_resolved'' and d.metadata->>''resolution'' = ''discarded''%'
    from pg_proc p where p.oid = 'private.workout_closed_as_stale(uuid)'::regprocedure),
  'it still needs the rule''s own close, plus the new hunk: and no discard of it');
select ok((select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
    from pg_proc p where p.oid = 'public.get_coach_plan_state_v1(uuid,date)'::regprocedure),
  'the Coach plan state is still a stable security definer function with an empty search path');
select ok((select p.prosrc like '%''schema_version'', ''1.3''%'
      and p.prosrc like '%private.coach_plan_sessions(p_user_id, (select a.version_id from active a))%'
      and p.prosrc like '%private.coach_session_exercises(p_user_id, s.id)%'
      and p.prosrc like '%public.get_progression_summary_v1(p_user_id)%'
      and p.prosrc like '%to_jsonb(pr.experience_level)%'
      and p.prosrc like '%a.ends_on is not null%'
      and p.prosrc like '%''unfinished'', coalesce(%private.unfinished_workouts(p_user_id, p_local_date)%'
      and p.prosrc like '%''offerable'', u.save_by >= p_local_date%'
    from pg_proc p where p.oid = 'public.get_coach_plan_state_v1(uuid,date)'::regprocedure),
  'and keeps every earlier source, with the unfinished list added');

select ok((select p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""']
    from pg_proc p where p.oid = 'public.abandon_workout(uuid)'::regprocedure),
  'discarding a workout is still security definer with an empty search path');
select ok((select p.prosrc like '%raise exception ''authentication required''%'
      and p.prosrc like '%raise exception ''session not found'' using errcode = ''P0002''%'
      and p.prosrc like '%raise exception ''a completed workout cannot be discarded'' using errcode = ''22023''%'
      and p.prosrc like '%actual_ended_at = coalesce(actual_ended_at, now())%'
      and p.prosrc like '%''workout.abandoned'', ''workout_session''%jsonb_build_object(''completed_sets'', logged_sets)%'
      and p.prosrc like '%''state'', ''abandoned'', ''replayed'', true%'
      and p.prosrc like '%''state'', ''abandoned'', ''replayed'', false%'
      and p.prosrc like '%if session.state = ''abandoned'' then%if private.workout_closed_as_stale(session.id) then%''workout.unfinished_resolved''%''resolution'', ''discarded''%'
    from pg_proc p where p.oid = 'public.abandon_workout(uuid)'::regprocedure),
  'and still discards as before, with the new hunk: a late discard of a stale-closed session is recorded');

-- The stale rule closes every open session of both athletes: 9 of A, 1 of B.
select is(private.abandon_stale_workouts(), 10, 'the stale rule closed the forgotten sessions');

-- A discard sent offline that reaches the server after the stale close is the athlete's answer.
set local role authenticated;
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000001';
insert into h select 'late_discard', public.abandon_workout('d1450000-0000-4000-8000-000000000012');
reset role;
select is((select j->>'replayed' from h where name = 'late_discard'), 'true',
  'the late discard finds the session already closed');
select is((select metadata->>'resolution' from public.audit_events
    where target_id = pg_temp.u(45, 12) and action_code = 'workout.unfinished_resolved'), 'discarded',
  'and is recorded as the athlete''s discard');
select is(private.workout_closed_as_stale(pg_temp.u(45, 12)), false, 'so it is no longer unfinished');

-- The read ------------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000001';
insert into h select 'first', public.get_my_unfinished_workout_v1();
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000002';
insert into h select 'other', public.get_my_unfinished_workout_v1();
reset role;

select is((select j->>'schema_version' from h where name = 'first'), '1.0', 'the read is 1.0');
select is((select j->'workout'->>'session_id' from h where name = 'first'),
  'd1450000-0000-4000-8000-000000000001', 'it offers the newest day: Legs B, not an older one');
select is((select j->'workout'->>'planned_workout_id' from h where name = 'first'),
  'd1430000-0000-4000-8000-000000000001', 'with its planned workout');
select is((select j->'workout'->>'name' from h where name = 'first'), 'Legs B', 'its name');
select is((select (j->'workout'->>'save_by')::date from h where name = 'first'),
  (select today + 6 from t), 'and the last day it can be saved: seven days after its own');
select is((select j->'workout'->>'logged_sets' from h where name = 'first'), '3', 'the sets logged');
select is((select j->'workout'->>'total_sets' from h where name = 'first'), '5', 'of those planned');
select is((select (j->'workout'->>'local_date')::date from h where name = 'first'),
  (select today - 1 from t), 'on its own day');
select is((select (j->'workout'->>'last_set_at')::timestamptz - (j->'workout'->>'started_at')::timestamptz
    from h where name = 'first'), interval '5400 seconds',
  'with when it began and when the last set ended');
select is((select (j->'workout'->>'first_set_at')::timestamptz - (j->'workout'->>'started_at')::timestamptz
    from h where name = 'first'), interval '1680 seconds', 'and the first set began');
select is((select j->'workout'->>'session_id' from h where name = 'other'),
  'd1450000-0000-4000-8000-000000000009', 'another athlete is offered only their own');

-- Coach reads the same facts ------------------------------------------------------------------

select is((select public.get_coach_plan_state_v1(pg_temp.u(40, 1), (select today from t))->>'schema_version'),
  '1.3', 'the Coach plan state is 1.3');
select is((select jsonb_array_length(public.get_coach_plan_state_v1(pg_temp.u(40, 1),
    (select today from t))->'unfinished')), 5,
  'it lists five: the four offered and Push (9 days ago), not the 29 day old one, the finished day, the empty one or the discards');
select is((select count(*) from jsonb_array_elements(public.get_coach_plan_state_v1(pg_temp.u(40, 1),
    (select today from t))->'unfinished') e where (e->>'offerable')::boolean), 4::bigint,
  'four of them can still be saved');
select is((select e->>'name' from jsonb_array_elements(public.get_coach_plan_state_v1(pg_temp.u(40, 1),
    (select today from t))->'unfinished') e where not (e->>'offerable')::boolean), 'Push',
  'and the one past its seven days is listed as not offerable');
select is((select e->>'logged_sets' from jsonb_array_elements(public.get_coach_plan_state_v1(
      pg_temp.u(40, 1), (select today from t))->'unfinished') e where e->>'name' = 'Legs B'),
  '3', 'Legs B with the sets it logged');
select is((select jsonb_array_length(public.get_coach_plan_state_v1(pg_temp.u(40, 2),
    (select today from t))->'unfinished')), 1, 'and each athlete''s own');
select is((select array(select k from jsonb_object_keys(public.get_coach_plan_state_v1(
      pg_temp.u(40, 1), (select today from t))) k order by k collate "C")),
  array['after_block', 'avoid_patterns', 'completed_this_week', 'equipment', 'experience',
    'local_date', 'plan', 'progression', 'recent_completed', 'schema_version', 'sessions',
    'unfinished', 'weekday'], 'every 1.2 key is still there beside the new one');
select is((select public.get_coach_plan_state_v1(pg_temp.u(40, 1), (select today from t))
    ->'plan'->>'title'), 'Plan A', 'the active plan is still read');
select is((select jsonb_array_length(public.get_coach_plan_state_v1(pg_temp.u(40, 1),
    (select today from t))->'sessions')), 6, 'with every planned session of the active version');

-- Answers that are refused ------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000001';

select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000009', 'discard')$$, 'P0002', null,
  'another athlete''s session is not found');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000004', 'discard')$$, 'P0002', null,
  'a session past its seven days is not offered');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000005', 'save', 6)$$, 'P0002', null,
  'nor one finished again the same day');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000007', 'save', 6)$$, 'P0002', null,
  'nor one with no set logged');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000008', 'save', 6)$$, 'P0002', null,
  'nor one the athlete discarded in the app');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000001', 'finish', 6)$$, '22023', null, 'an unknown action');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000001', 'save')$$, '22023', null, 'saving needs the athlete''s effort');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000001', 'save', 5.5)$$, '22023', null, 'a whole number');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000001', 'save', 11)$$, '22023', null, 'from 1 to 10');

set local "request.jwt.claim.sub" = '';
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000001', 'discard')$$, '42501', null, 'signed out, nothing is answered');
select throws_ok($$select public.get_my_unfinished_workout_v1()$$, '42501', null, 'or read');
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000002';
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000001', 'save', 6)$$, 'P0002', null,
  'another athlete cannot save A''s Legs B');
reset role;

select is((select state::text from public.workout_sessions where id = pg_temp.u(45, 1)), 'abandoned',
  'none of that changed Legs B');

-- Save -------------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000001';
insert into h select 'save1', public.resolve_unfinished_workout_v1(
  'd1450000-0000-4000-8000-000000000001', 'save', 7);
reset role;

select is((select j->>'resolution' from h where name = 'save1'), 'saved', 'Legs B is saved');
select is((select j->>'replayed' from h where name = 'save1'), 'false', 'not as a repeat');
select is((select j->>'state' from h where name = 'save1'), 'completed', 'completed');
select is((select state::text from public.workout_sessions where id = pg_temp.u(45, 1)), 'completed',
  'in the table');
select is((select local_date from public.workout_sessions where id = pg_temp.u(45, 1)),
  (select today - 1 from t), 'on its own date');
select is((select duration_seconds from public.workout_sessions where id = pg_temp.u(45, 1)), 5400,
  'with the time from its start to its last set');
select is((select actual_ended_at - actual_started_at from public.workout_sessions
    where id = pg_temp.u(45, 1)), interval '5400 seconds', 'ending there, not when it was saved');
select is((select session_effort from public.workout_sessions where id = pg_temp.u(45, 1)), 7.0,
  'the effort is the athlete''s');
select is((select session_effort_source from public.workout_sessions where id = pg_temp.u(45, 1)),
  'athlete', 'recorded as theirs');
select is((select completion_source from public.workout_sessions where id = pg_temp.u(45, 1)),
  'manual', 'a manual completion');
select is((select count(*) from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id
    where p.workout_session_id = pg_temp.u(45, 1) and s.completed), 3::bigint, 'its three sets are intact');
select is((select count(*) from public.audit_events
    where target_id = pg_temp.u(45, 1) and action_code = 'workout.completed'), 1::bigint,
  'the completion is audited');
select is((select metadata->>'resolution' from public.audit_events
    where target_id = pg_temp.u(45, 1) and action_code = 'workout.unfinished_resolved'), 'saved',
  'and so is the answer');

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000001';
select is(public.resolve_unfinished_workout_v1('d1450000-0000-4000-8000-000000000001', 'save', 7)->>'replayed',
  'true', 'saving again replays');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000001', 'discard')$$, '22023', null,
  'a saved workout cannot be discarded');
insert into h select 'second', public.get_my_unfinished_workout_v1();
reset role;

select is((select j->'workout'->>'session_id' from h where name = 'second'),
  'd1450000-0000-4000-8000-000000000002', 'the next offer is the next day back');

-- Discard ----------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000001';
insert into h select 'discard', public.resolve_unfinished_workout_v1(
  'd1450000-0000-4000-8000-000000000002', 'discard');
insert into h select 'discard2', public.resolve_unfinished_workout_v1(
  'd1450000-0000-4000-8000-000000000002', 'discard');
select throws_ok($$select public.resolve_unfinished_workout_v1(
    'd1450000-0000-4000-8000-000000000002', 'save', 7)$$, '55000', null, 'a discard cannot be saved after');
select throws_ok($$select public.sync_workout_draft('d1450000-0000-4000-8000-000000000002', 1,
    '{"exercises":[]}'::jsonb)$$, '55000', null, 'it takes no late sets');
select throws_ok($$select public.complete_workout_v2('d1450000-0000-4000-8000-000000000002', 1, 600, 5,
    '')$$, '55000', null, 'and no late finish');
insert into h select 'third', public.get_my_unfinished_workout_v1();
reset role;

select is((select j->>'resolution' from h where name = 'discard'), 'discarded', 'Upper is discarded');
select is((select j->>'replayed' from h where name = 'discard'), 'false', 'once');
select is((select j->>'replayed' from h where name = 'discard2'), 'true', 'and again replays');
select is((select state::text from public.workout_sessions where id = pg_temp.u(45, 2)), 'abandoned',
  'it stays abandoned');
select is((select count(*) from public.audit_events
    where target_id = pg_temp.u(45, 2) and action_code = 'workout.unfinished_resolved'), 1::bigint,
  'with one audit event');
select is(private.workout_closed_as_stale(pg_temp.u(45, 2)), false, 'it no longer counts as closed by the rule');
select is((select count(*) from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id
    where p.workout_session_id = pg_temp.u(45, 2) and s.completed), 1::bigint,
  'its set is kept');
select is((select j->'workout'->>'session_id' from h where name = 'third'),
  'd1450000-0000-4000-8000-000000000003', 'and it is never offered again');

-- Saving with no set times --------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000001';
select is(public.resolve_unfinished_workout_v1('d1450000-0000-4000-8000-000000000003', 'save', 5)->>'resolution',
  'saved', 'a workout whose sets carry no times is saved');
insert into h select 'fourth', public.get_my_unfinished_workout_v1();
reset role;

select is((select duration_seconds from public.workout_sessions where id = pg_temp.u(45, 3)), null,
  'its duration is unknown, not the three hour cap');
select is((select actual_ended_at from public.workout_sessions where id = pg_temp.u(45, 3)), null,
  'and it has no end time');
select is((select state::text from public.workout_sessions where id = pg_temp.u(45, 3)), 'completed',
  'it is completed');
select is((select j->'workout'->>'session_id' from h where name = 'fourth'),
  'd1450000-0000-4000-8000-000000000010', 'the last day it can be saved is still offered');

-- The end ----------------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1400000-0000-4000-8000-000000000001';
select is(public.resolve_unfinished_workout_v1('d1450000-0000-4000-8000-000000000010', 'discard')->>'resolution',
  'discarded', 'the last one is discarded');
insert into h select 'last', public.get_my_unfinished_workout_v1();
reset role;

select is(jsonb_typeof((select j->'workout' from h where name = 'last')), 'null',
  'and then nothing is offered');
select is(private.abandon_stale_workouts(), 0, 'the stale rule revives nothing');
select is((select count(*) from public.workout_sessions
    where user_id = pg_temp.u(40, 1) and state = 'in_progress'), 0::bigint, 'no session is open');
select is((select jsonb_array_length(public.get_coach_plan_state_v1(pg_temp.u(40, 1),
    (select today from t))->'unfinished')), 1, 'Coach is told only of the one no longer offered');
select is((select count(*) from public.workout_sessions
    where user_id = pg_temp.u(40, 1) and state = 'completed'), 3::bigint,
  'the finished one and the two the athlete saved');

select * from finish();
rollback;
