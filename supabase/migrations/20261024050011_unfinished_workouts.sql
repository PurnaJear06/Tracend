-- A workout the athlete logged but did not finish is offered back, never lost and never finished
-- for them.
--
-- Incident (2026-10-23/24): the owner logged 23 sets of Legs B from 16:45, never tapped Finish, and
-- the hourly stale-workout job (20261023150021) closed the session as abandoned at 00:47. At 05:00
-- Coach said "Legs B from earlier this week was not done". Logged training had silently become
-- "not done". Completing it for them would write a durable workout the athlete did not confirm
-- (architecture rule 3), so the athlete is asked instead.
--
--   1. private.unfinished_workouts          the rule: which closed sessions are offered back
--   2. get_my_unfinished_workout_v1         the app's read: the newest offered session, or null
--   3. resolve_unfinished_workout_v1        Save (the existing stale-closed completion path) or
--                                           Discard (final), each audited
--   4. private.workout_closed_as_stale      a discarded session no longer takes a late send
--   5. private.complete_workout_session     no duration given for a stale-closed session stays
--                                           unknown instead of becoming the three hour cap
--   6. get_coach_plan_state_v1              1.3: `unfinished`, so Coach reads "logged N sets, not
--                                           finished" and not "not done"
--
-- Offered means: closed by the stale rule (audit reason 'stale', see private.workout_closed_as_stale),
-- local day within the last seven days and before today, at least one completed set, and no finished
-- session of the same planned workout on the same day (the athlete already logged it again). An
-- answered session leaves the offer by itself: Save completes it, and Discard ends the stale-closed
-- state. Sessions the athlete discarded in the app (abandon_workout) carry no reason and are never
-- offered.

-- 1. The rule -----------------------------------------------------------------------------------

create function private.unfinished_workouts(p_user uuid, p_today date)
returns table (
  session_id uuid,
  planned_workout_id uuid,
  workout_name text,
  local_date date,
  started_at timestamptz,
  client_revision integer,
  logged_sets integer,
  total_sets integer,
  first_set_at timestamptz,
  last_set_at timestamptz
) language sql stable set search_path = '' as $$
  select s.id, s.planned_workout_id, w.name, s.local_date,
    coalesce(s.actual_started_at, s.started_at), s.client_revision,
    t.logged, t.total, t.first_at, t.last_at
  from public.workout_sessions s
  join public.planned_workouts w on w.id = s.planned_workout_id and w.user_id = s.user_id
  cross join lateral (
    select count(*) filter (where e.completed)::integer as logged,
      count(*)::integer as total,
      min(coalesce(e.started_at, e.completed_at)) filter (where e.completed) as first_at,
      max(coalesce(e.completed_at, e.started_at)) filter (where e.completed) as last_at
    from public.exercise_sets e
    join public.exercise_performances p on p.id = e.exercise_performance_id
    where p.workout_session_id = s.id
  ) t
  where s.user_id = p_user
    and s.state = 'abandoned'
    and s.local_date between p_today - 7 and p_today - 1
    and t.logged > 0
    and private.workout_closed_as_stale(s.id)
    and not exists (
      select 1 from public.workout_sessions c
      where c.user_id = s.user_id and c.state = 'completed'
        and c.planned_workout_id = s.planned_workout_id and c.local_date = s.local_date);
$$;
revoke all on function private.unfinished_workouts(uuid, date) from public, anon, authenticated;

-- 2. The read -----------------------------------------------------------------------------------

-- The newest offered session, or `workout: null`. A session left open since an earlier day is
-- closed first, so the answer does not wait for the hourly job.
create function public.get_my_unfinished_workout_v1()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare found_row record;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  perform private.abandon_stale_workouts(auth.uid());
  select * into found_row
  from private.unfinished_workouts(auth.uid(), private.local_date_for(auth.uid())) u
  order by u.local_date desc, u.started_at desc
  limit 1;
  if not found then
    return jsonb_build_object('schema_version', '1.0', 'workout', null);
  end if;
  return jsonb_build_object('schema_version', '1.0', 'workout', jsonb_build_object(
    'session_id', found_row.session_id,
    'planned_workout_id', found_row.planned_workout_id,
    'name', found_row.workout_name,
    'local_date', found_row.local_date,
    'started_at', found_row.started_at,
    'logged_sets', found_row.logged_sets,
    'total_sets', found_row.total_sets,
    'first_set_at', found_row.first_set_at,
    'last_set_at', found_row.last_set_at));
end $$;
revoke all on function public.get_my_unfinished_workout_v1() from public, anon, authenticated;
grant execute on function public.get_my_unfinished_workout_v1() to authenticated;

-- 3. The athlete's answer -------------------------------------------------------------------------

-- 'save' completes the session on its own local day through private.complete_workout_session, the
-- path complete_workout_v2 uses for a session the rule closed, with the athlete's own 1 to 10
-- effort. Its duration is the time from its start to the last set logged; with no set times it is
-- left unknown and never invented. 'discard' keeps the session abandoned for good. Either answer
-- is audited as workout.unfinished_resolved and the session is never offered again. A repeat of
-- the same answer replays; the opposite answer is refused.
create function public.resolve_unfinished_workout_v1(
  p_session_id uuid,
  p_action text,
  p_session_effort numeric default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session public.workout_sessions%rowtype;
  offered record;
  earlier text;
  duration integer;
  result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_action is null or p_action not in ('save', 'discard') then
    raise exception 'action must be save or discard' using errcode = '22023';
  end if;
  select * into session from public.workout_sessions
    where id = p_session_id and user_id = auth.uid() for update;
  if not found then raise exception 'session not found' using errcode = 'P0002'; end if;

  select e.metadata->>'resolution' into earlier from public.audit_events e
    where e.target_type = 'workout_session' and e.target_id = session.id
      and e.action_code = 'workout.unfinished_resolved'
    order by e.created_at desc limit 1;
  if earlier = 'discarded' then
    if p_action = 'discard' then
      return jsonb_build_object('schema_version', '1.0', 'session_id', session.id,
        'state', session.state, 'resolution', 'discarded', 'replayed', true);
    end if;
    raise exception 'workout was discarded' using errcode = '55000';
  end if;
  if session.state = 'completed' then
    if p_action = 'discard' then
      raise exception 'a completed workout cannot be discarded' using errcode = '22023';
    end if;
    return jsonb_build_object('schema_version', '1.0', 'session_id', session.id,
      'state', 'completed', 'resolution', 'saved', 'replayed', true);
  end if;

  select * into offered
  from private.unfinished_workouts(auth.uid(), private.local_date_for(auth.uid())) u
  where u.session_id = session.id;
  if not found then
    raise exception 'workout is not an unfinished workout' using errcode = 'P0002';
  end if;

  if p_action = 'discard' then
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (auth.uid(), 'workout.unfinished_resolved', 'workout_session', session.id, 'succeeded',
      jsonb_build_object('resolution', 'discarded', 'completed_sets', offered.logged_sets,
        'local_date', session.local_date));
    return jsonb_build_object('schema_version', '1.0', 'session_id', session.id,
      'state', 'abandoned', 'resolution', 'discarded', 'replayed', false);
  end if;

  if p_session_effort is null or p_session_effort not between 1 and 10
    or p_session_effort <> round(p_session_effort) then
    raise exception 'session effort must be a whole number from 1 to 10' using errcode = '22023';
  end if;
  duration := case
    when offered.last_set_at is null or offered.last_set_at <= offered.started_at then null
    else floor(extract(epoch from offered.last_set_at - offered.started_at))::integer end;
  result := private.complete_workout_session(session.id, session.client_revision, duration,
    null, p_session_effort, coalesce(session.notes, ''), 'athlete');
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'workout.unfinished_resolved', 'workout_session', session.id, 'succeeded',
    jsonb_build_object('resolution', 'saved', 'completed_sets', offered.logged_sets,
      'local_date', session.local_date));
  return jsonb_build_object('schema_version', '1.0') || result
    || jsonb_build_object('state', 'completed', 'resolution', 'saved');
end $$;
revoke all on function public.resolve_unfinished_workout_v1(uuid, text, numeric)
  from public, anon, authenticated;
grant execute on function public.resolve_unfinished_workout_v1(uuid, text, numeric) to authenticated;

-- 4. A discarded session is final ---------------------------------------------------------------

-- The definition of 20261023150021_close_stale_workouts.sql plus: an athlete's discard of an
-- unfinished workout ends the allowance, so a late send from a phone cannot complete it after.
create or replace function private.workout_closed_as_stale(p_session_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from public.audit_events e
    where e.target_type = 'workout_session' and e.target_id = p_session_id
      and e.action_code = 'workout.abandoned' and e.metadata->>'reason' = 'stale')
    and not exists (
    select 1 from public.audit_events d
    where d.target_type = 'workout_session' and d.target_id = p_session_id
      and d.action_code = 'workout.unfinished_resolved' and d.metadata->>'resolution' = 'discarded');
$$;

-- 5. No duration stays unknown ------------------------------------------------------------------

-- The definition of 20261023150021_close_stale_workouts.sql plus: a session the rule closed and
-- completed without a duration records none, and no end time, instead of the three hour cap.
create or replace function private.complete_workout_session(
  p_session_id uuid,
  p_client_revision integer,
  p_duration_seconds integer,
  p_session_energy smallint,
  p_session_effort numeric,
  p_notes text,
  p_effort_source text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session public.workout_sessions%rowtype; completed_sets integer; total_sets integer;
  coverage numeric; capped_duration integer; closed_as_stale boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into session from public.workout_sessions
    where id = p_session_id and user_id = auth.uid() for update;
  if not found then raise exception 'session not found' using errcode = 'P0002'; end if;
  if session.state = 'completed' then
    return jsonb_build_object('session_id', session.id, 'replayed', true);
  end if;
  closed_as_stale := session.state = 'abandoned' and private.workout_closed_as_stale(session.id);
  if session.state = 'abandoned' and not closed_as_stale then
    raise exception 'session was discarded' using errcode = '55000';
  end if;
  if p_client_revision < session.client_revision then
    raise exception 'stale client revision' using errcode = '40001';
  end if;
  select count(*) filter (where s.completed), count(*) into completed_sets, total_sets
  from public.exercise_sets s
  join public.exercise_performances p on p.id = s.exercise_performance_id
  where p.workout_session_id = session.id;
  if completed_sets = 0 then raise exception 'complete at least one set' using errcode = '22023'; end if;
  coverage := completed_sets::numeric / greatest(total_sets, 1);
  capped_duration := case when p_duration_seconds is null and closed_as_stale then null
    else least(p_duration_seconds, 10800) end;
  update public.exercise_performances p set status = case
    when p.status = 'skipped' then 'skipped'
    when exists (select 1 from public.exercise_sets s
                 where s.exercise_performance_id = p.id and s.completed) then 'performed'
    else 'unknown' end
  where p.workout_session_id = session.id;
  update public.workout_sessions set
    state = 'completed', completed_at = now(),
    actual_ended_at = coalesce(actual_ended_at, case when closed_as_stale
      then case when capped_duration is null then null
        else least(now(), coalesce(actual_started_at, started_at) + capped_duration * interval '1 second') end
      else now() end),
    duration_seconds = capped_duration, session_energy = p_session_energy,
    session_effort = p_session_effort, notes = p_notes,
    completion_source = 'manual', session_effort_source = p_effort_source,
    logging_completeness = coverage,
    client_revision = greatest(workout_sessions.client_revision, p_client_revision),
    updated_at = now()
  where id = session.id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'workout.completed', 'workout_session', session.id, 'succeeded',
    jsonb_build_object('completed_sets', completed_sets, 'total_sets', total_sets,
      'logging_completeness', coverage, 'effort_source', p_effort_source));
  return jsonb_build_object('session_id', session.id, 'completed_sets', completed_sets,
    'total_sets', total_sets, 'logging_completeness', coverage, 'replayed', false);
end $$;

-- 6. Coach plan state 1.3 -----------------------------------------------------------------------

-- The definition of 20261023100050_advanced_level_catalog.sql (1.2) plus `unfinished`: the sessions
-- offered back above, each with the planned workout's name so Coach can tell which planned session
-- it stands for. A key is only added; a reader of 1.2 ignores it.
create or replace function public.get_coach_plan_state_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with active as (
    select v.id as version_id, v.version_number, v.sessions_per_week, p.title, v.ends_on,
      v.restores_version_id
    from public.training_plan_versions v
    join public.training_plans p on p.id = v.plan_id and p.user_id = v.user_id
    where v.user_id = p_user_id and v.status = 'active' limit 1
  )
  select jsonb_build_object(
    'schema_version', '1.3',
    'local_date', p_local_date,
    'weekday', extract(isodow from p_local_date)::integer,
    -- Equipment counts only once the athlete answered the intake that asks for it.
    'equipment', (select case when pr.daily_activity is not null then to_jsonb(pr.equipment) end
      from public.user_profiles pr where pr.user_id = p_user_id),
    'avoid_patterns', (select to_jsonb(pr.avoid_patterns)
      from public.user_profiles pr where pr.user_id = p_user_id),
    -- The athlete's level (beginner, intermediate, advanced; null when never recorded): Coach
    -- offers alternatives from the exercises that level is offered.
    'experience', (select to_jsonb(pr.experience_level)
      from public.user_profiles pr where pr.user_id = p_user_id),
    'plan', (select jsonb_build_object('title', a.title, 'version_number', a.version_number,
      'sessions_per_week', a.sessions_per_week) from active a),
    'sessions', private.coach_plan_sessions(p_user_id, (select a.version_id from active a)),
    -- When the active version is a temporary block, the sessions the athlete returns to after its
    -- last day: the schedule after `ends_on` is these, not the block's.
    'after_block', (select jsonb_build_object('ends_on', a.ends_on,
        'version_number', r.version_number,
        'sessions', private.coach_plan_sessions(p_user_id, r.id))
      from active a join public.training_plan_versions r
        on r.id = a.restores_version_id and r.user_id = p_user_id
      where a.ends_on is not null),
    -- A session finished under an earlier plan version still counts this week: it carries the
    -- workout's name, day and order so it can be matched to the active plan's workouts.
    'completed_this_week', coalesce((select jsonb_agg(jsonb_build_object(
        'planned_workout_id', s.planned_workout_id, 'local_date', s.local_date,
        'name', cw.name, 'weekday', cw.preferred_weekday, 'order', cw.workout_order)
        order by s.local_date)
      from public.workout_sessions s
      join public.planned_workouts cw on cw.id = s.planned_workout_id and cw.user_id = s.user_id
      where s.user_id = p_user_id and s.state = 'completed'
        and s.local_date between p_local_date - (extract(isodow from p_local_date)::integer - 1)
          and p_local_date), '[]'::jsonb),
    -- Yesterday's and today's finished sessions whatever the calendar week, each with the sets
    -- it logged per exercise: the week-ahead schedule needs yesterday on a Monday, and
    -- completed_this_week stops at Monday.
    'recent_completed', coalesce((select jsonb_agg(jsonb_build_object(
        'planned_workout_id', s.planned_workout_id, 'local_date', s.local_date, 'name', cw.name,
        'exercises', private.coach_session_exercises(p_user_id, s.id))
        order by s.local_date)
      from public.workout_sessions s
      join public.planned_workouts cw on cw.id = s.planned_workout_id and cw.user_id = s.user_id
      where s.user_id = p_user_id and s.state = 'completed'
        and s.local_date between p_local_date - 1 and p_local_date), '[]'::jsonb),
    -- Workouts logged but not finished that the athlete has not answered yet: not done, and not
    -- missed either.
    'unfinished', coalesce((select jsonb_agg(jsonb_build_object(
        'planned_workout_id', u.planned_workout_id, 'local_date', u.local_date,
        'name', u.workout_name, 'logged_sets', u.logged_sets)
        order by u.local_date)
      from private.unfinished_workouts(p_user_id, p_local_date) u), '[]'::jsonb),
    'progression', public.get_progression_summary_v1(p_user_id));
$$;
