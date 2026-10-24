begin;
select no_plan();

-- Guidance 1.2 (PR #178 review): who made an open or running deload proposal (proposal_origin), when a
-- running week ends (ends_on), the 14-day quiet after an undone deload, and the per-athlete store lock.

insert into auth.users(id, role)
select ('b5400000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'authenticated'
from generate_series(1, 10) n;

create function pg_temp.u(p_n integer) returns uuid language sql as $$
  select ('b5400000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid
$$;

create temporary table t as select private.local_date_for(pg_temp.u(1)) as today;
grant select on t to authenticated;
create temporary table wk(uid uuid primary key, version_id uuid, workout_id uuid);
grant select on wk to authenticated;
create temporary table p(name text primary key, id uuid);
grant all on p to authenticated;

-- An athlete with a plan (one workout on today's weekday) and enough training behind it for a suggestion
-- to be allowed: a completed session in each of the last four weeks.
create function pg_temp.make_athlete(p_n integer) returns void language plpgsql as $$
declare
  uid uuid := pg_temp.u(p_n);
  pl uuid := gen_random_uuid(); v uuid := gen_random_uuid(); w uuid := gen_random_uuid();
  today date := private.local_date_for(pg_temp.u(p_n));
  d integer;
begin
  insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level,
    training_days, session_minutes)
  values (uid, now(), true, 'beginner', array[2,5]::smallint[], 45);
  insert into public.training_plans(id, user_id, title, source) values (pl, uid, 'Strength', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, uid, pl, 1, 'active', 6, 3, '{}', 'Approved', now() - 14 * interval '1 day', today - 14);
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (w, uid, v, 1, 'Upper A', 'Press', extract(isodow from today)::integer, 50, 'Warm up', 'Cool down');
  insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
    display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
  values (gen_random_uuid(), uid, w, 1, 'Barbell bench press', 4, 5, 8, 8, 120, 'barbell-bench-press');
  insert into wk values (uid, v, w);
  foreach d in array array[1, 8, 15, 22] loop
    insert into public.workout_sessions(user_id, plan_version_id, planned_workout_id, local_date, timezone,
      state, idempotency_key, completed_at, duration_seconds, session_effort, session_effort_source,
      completion_source)
    values (uid, v, w, today - d, 'UTC', 'completed', gen_random_uuid(), now() - d * interval '1 day',
      3000, 8, 'athlete', 'manual');
  end loop;
end $$;

create function pg_temp.d(p_n integer) returns jsonb language sql as $$
  select private.deload_signals(pg_temp.u(p_n), (select today from t))
$$;

-- A deload proposal through the real path. p_signals true adds the evidence the rules' suggestion adds.
create function pg_temp.deload(p_n integer, p_signals boolean) returns uuid language plpgsql as $$
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
    'Because of your sets.', 'A benefit.', 'A downside.', 'medium',
    case when p_signals
      then '[{"code":"TRAINING_STANDARD","label":"Limits","source":"policy_evaluation"},{"code":"DELOAD_SIGNALS","label":"Your lifts","source":"training_guidance"}]'::jsonb
      else '[{"code":"TRAINING_STANDARD","label":"Limits","source":"policy_evaluation"}]'::jsonb end,
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

-- Who made it -------------------------------------------------------------------------------------------------------

select pg_temp.make_athlete(1);
select is(pg_temp.d(1) -> 'proposal_origin', 'null'::jsonb, 'with no proposal there is no origin');
select is(pg_temp.d(1) -> 'ends_on', 'null'::jsonb, 'and no end date');

insert into p select 'coach', pg_temp.deload(1, false);
select is(pg_temp.d(1) ->> 'status', 'pending', 'an open deload shows as pending');
select is(pg_temp.d(1) ->> 'proposal_origin', 'coach', 'one without the rules'' evidence is one the athlete asked Coach for');
select is(pg_temp.d(1) -> 'ends_on', 'null'::jsonb, 'a pending week has no end date yet');

select pg_temp.make_athlete(2);
insert into p select 'rules', pg_temp.deload(2, true);
select is(pg_temp.d(2) ->> 'proposal_origin', 'tracend', 'one that carries DELOAD_SIGNALS is the rules'' suggestion');

select is(private.training_guidance(pg_temp.u(2), (select today from t)) -> 'deload' ->> 'proposal_origin', 'tracend',
  'and the guidance carries it');
select is(private.training_guidance(pg_temp.u(2), (select today from t)) ->> 'schema_version', '1.2',
  'at schema version 1.2');

select pg_temp.respond(2, (select id from p where name = 'rules'), 'approve');
select is(pg_temp.d(2) ->> 'status', 'running', 'once approved the week is running');
select is(pg_temp.d(2) ->> 'proposal_origin', 'tracend', 'still the rules'' suggestion');
select is(pg_temp.d(2) ->> 'ends_on', ((select today from t) + 6)::text, 'with the last day of the week');

select pg_temp.make_athlete(3);
insert into p select 'coach_run', pg_temp.deload(3, false);
select pg_temp.respond(3, (select id from p where name = 'coach_run'), 'approve');
select is(pg_temp.d(3) ->> 'proposal_origin', 'coach', 'a running week the athlete asked Coach for says so');
select is(pg_temp.d(3) ->> 'ends_on', ((select today from t) + 6)::text, 'with its last day');

-- An undone deload ----------------------------------------------------------------------------------------------------

create function pg_temp.undo(p_n integer, p_proposal uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', pg_temp.u(p_n)::text, true);
  set local role authenticated;
  perform public.undo_coach_proposal_v1(p_proposal);
  reset role;
end $$;

select pg_temp.make_athlete(4);
insert into p select 'undone', pg_temp.deload(4, true);
select pg_temp.respond(4, (select id from p where name = 'undone'), 'approve');
select is(pg_temp.d(4) ->> 'status', 'running', 'a running week');
select pg_temp.undo(4, (select id from p where name = 'undone'));
select is(pg_temp.d(4) ->> 'status', 'not_due', 'taken back, it is not running and not offered again at once');
select is(pg_temp.d(4) ->> 'suppressed_by', 'declined_recently', 'the 14 days of quiet start from the day it was undone');
select is(pg_temp.d(4) -> 'last_ended_on', 'null'::jsonb, 'an undone week never ran, so it is not the last deload');
select is(pg_temp.d(4) -> 'proposal_origin', 'null'::jsonb, 'and nothing is open');

-- Fourteen days on, the quiet is over: the undo happened 15 days ago.
update public.change_proposals set undone_at = undone_at - interval '15 days'
where id = (select id from p where name = 'undone');
select is(pg_temp.d(4) ->> 'suppressed_by', null, '15 days after the undo nothing holds a suggestion back');

-- 13 days ago is still inside the quiet (the day counts in the athlete's own time zone).
update public.change_proposals set undone_at = statement_timestamp() - interval '13 days'
where id = (select id from p where name = 'undone');
select is(pg_temp.d(4) ->> 'suppressed_by', 'declined_recently', '13 days after the undo it still does');

-- A deload that was approved and ran its week is not an undone one.
select pg_temp.make_athlete(5);
insert into p select 'ran', pg_temp.deload(5, true);
select pg_temp.respond(5, (select id from p where name = 'ran'), 'approve');
select is(pg_temp.d(5) ->> 'suppressed_by', null, 'a running week is not held back by the undo rule');

-- Another athlete is untouched by the first one's undo.
select is(pg_temp.d(1) ->> 'suppressed_by', null, 'one athlete''s undo holds back no one else');

-- One store at a time per athlete -----------------------------------------------------------------------------------

select ok(pg_get_functiondef('public.persist_coach_proposal_v1(uuid, text, text, text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid)'::regprocedure)
    like '%pg_advisory_xact_lock(hashtext(p_user_id::text))%',
  'storing a proposal takes the athlete''s transaction lock');
select ok(has_function_privilege('service_role',
    'public.persist_coach_proposal_v1(uuid, text, text, text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.persist_coach_proposal_v1(uuid, text, text, text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid)', 'execute'),
  'and it is still the service role''s alone');

select * from finish();
rollback;
