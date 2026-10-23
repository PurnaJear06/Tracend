-- A workout from an earlier day is closed, never resumed as today's.
--
-- Bug (2026-10-23): the owner opened today's workout and the app resumed a session left
-- in_progress since 2026-07-17. get_my_workout_session and start_workout both look for an open
-- session by planned workout alone, and a plan repeats every week, so any session ever left
-- open was found again by the same workout months later. Today's sets were written into it (its
-- local_date stayed in July) and its timer counted from July.
--
-- The rule: an in_progress session is stale when its local day (local_date) is before the
-- athlete's local today (private.local_date_for) and it started more than 10800 seconds ago, the
-- same three hours complete_workout_v2 caps a workout at. The wait keeps a workout that crosses
-- midnight resumable. A stale session becomes 'abandoned', the state abandon_workout already
-- uses: its rows, sets and local_date stay exactly as they were, it is audited as
-- workout.abandoned with the reason 'stale' and the number of sets it logged, and no history,
-- load or hub read counts it. Nothing is deleted, moved to another date or completed on the
-- athlete's behalf, and actual_ended_at stays empty because no end was recorded.
--
--   1. private.abandon_stale_workouts   the rule, for one athlete or for everyone
--   2. get_my_workout_session           closes the caller's stale sessions before it looks
--   3. an hourly job                    closes them for everyone, opened or not
--   4. start_workout                    closes the caller's stale sessions before it looks for an
--                                       open one (the definition of 20261023140024 plus the close)
--   5. the athlete's own late send      a session the rule closed still takes its unsent sets and
--                                       its finish, on its own date
--
-- The app reads the session first, the hourly job covers the rest, and start_workout closes them
-- itself so a start can never find one.

-- 1. The rule ---------------------------------------------------------------------------------

create function private.abandon_stale_workouts(p_user uuid default null)
returns integer language plpgsql set search_path = '' as $$
declare
  stale record;
  logged_sets integer;
  closed integer := 0;
begin
  for stale in
    select s.id, s.user_id, s.local_date
    from public.workout_sessions s
    where s.state = 'in_progress'
      and (p_user is null or s.user_id = p_user)
      and s.local_date < private.local_date_for(s.user_id)
      and coalesce(s.actual_started_at, s.started_at) < statement_timestamp() - interval '10800 seconds'
    order by s.user_id, s.started_at
  loop
    update public.workout_sessions
      set state = 'abandoned', updated_at = now()
      where id = stale.id and state = 'in_progress';
    if found then
      select count(*) filter (where e.completed) into logged_sets
      from public.exercise_sets e
      join public.exercise_performances p on p.id = e.exercise_performance_id
      where p.workout_session_id = stale.id;
      insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
      values (stale.user_id, 'workout.abandoned', 'workout_session', stale.id, 'succeeded',
        jsonb_build_object('reason', 'stale', 'completed_sets', logged_sets,
          'local_date', stale.local_date));
      closed := closed + 1;
    end if;
  end loop;
  return closed;
end $$;
revoke all on function private.abandon_stale_workouts(uuid) from public, anon, authenticated;

-- 2. The read -----------------------------------------------------------------------------------

create or replace function public.get_my_workout_session(
  p_planned_workout_id uuid,
  p_local_date date
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target public.workout_sessions%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  perform private.abandon_stale_workouts(auth.uid());
  select * into target from public.workout_sessions
  where user_id=auth.uid() and planned_workout_id=p_planned_workout_id
    and state<>'abandoned'
    and (state='in_progress' or local_date=p_local_date)
  order by case state when 'in_progress' then 0 else 1 end, started_at desc
  limit 1;
  if not found then return null; end if;
  return jsonb_build_object(
    'schema_version','1.1',
    'session_id',target.id,'state',target.state,'revision',target.client_revision,
    'idempotency_key',target.idempotency_key,'local_date',target.local_date,
    'actual_started_at',target.actual_started_at,'actual_ended_at',target.actual_ended_at,
    'duration_seconds',target.duration_seconds,'notes',target.notes,
    'completion_source',target.completion_source,
    'session_effort',target.session_effort,
    'session_effort_source',target.session_effort_source,
    'exercises',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'performance_id',p.id,'order',p.exercise_order,'status',p.status,
        'performance_kind',p.performance_kind,'performed_name',p.performed_name,
        'exercise_slug',p.exercise_slug,
        'substitution_reason',p.substitution_reason,'pain_flag',p.pain_flag,
        'note',p.note,'rest_seconds',p.rest_seconds,
        'sets',(select coalesce(jsonb_agg(jsonb_build_object(
          'number',s.set_number,'repetitions',s.repetitions,'load_kg',s.load_kg,
          'rpe',s.rpe,'completed',s.completed,
          'started_at',s.started_at,'completed_at',s.completed_at,
          'rest_before_seconds',s.rest_before_seconds,'rir',s.rir,
          'timing_source',s.timing_source
        ) order by s.set_number),'[]'::jsonb) from public.exercise_sets s where s.exercise_performance_id=p.id)
      ) order by p.exercise_order),'[]'::jsonb)
      from public.exercise_performances p where p.workout_session_id=target.id
    )
  );
end $$;

revoke all on function public.get_my_workout_session(uuid, date) from public, anon, authenticated;
grant execute on function public.get_my_workout_session(uuid, date) to authenticated;

-- 3. The hourly job -----------------------------------------------------------------------------

select cron.schedule('tracend-abandon-stale-workouts', '17 * * * *',
  'select private.abandon_stale_workouts()');

-- 4. Starting the workout -----------------------------------------------------------------------

create or replace function public.start_workout(
  p_planned_workout_id uuid,
  p_local_date date,
  p_timezone text,
  p_idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; version_id uuid; exercise record; performance_id uuid; n integer;
  adjustment public.day_adjustments%rowtype; adjusted boolean := false; set_total integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  -- The same lock respond_to_day_adjustment_v1 takes: an answer and a start never interleave.
  perform pg_advisory_xact_lock(hashtextextended(
    'day_adjustment:' || auth.uid()::text || coalesce(p_local_date::text, ''), 0));
  select w.plan_version_id into version_id
  from public.planned_workouts w
  join public.training_plan_versions v on v.id=w.plan_version_id and v.user_id=w.user_id
  where w.id=p_planned_workout_id and w.user_id=auth.uid() and v.status='active';
  if not found then raise exception 'planned workout not found' using errcode='P0002'; end if;

  select id into result_id from public.workout_sessions
  where user_id=auth.uid() and idempotency_key=p_idempotency_key;
  if result_id is not null then return result_id; end if;

  -- A session left open from an earlier day is closed first, so it is never found as today's.
  perform private.abandon_stale_workouts(auth.uid());
  select id into result_id from public.workout_sessions
  where user_id=auth.uid() and planned_workout_id=p_planned_workout_id and state='in_progress'
  order by started_at desc limit 1;
  if result_id is not null then return result_id; end if;

  if exists (
    select 1 from public.workout_sessions
    where user_id=auth.uid() and planned_workout_id=p_planned_workout_id
      and local_date=p_local_date and state='completed'
  ) then
    raise exception 'workout already completed for this coaching day' using errcode='55000';
  end if;

  -- The athlete's accepted answer for today is applied as given (it can only make the day easier);
  -- a start for any other date, from history, gets the plan as written.
  if p_local_date = private.local_date_for(auth.uid()) then
    select * into adjustment from public.day_adjustments a
    where a.user_id=auth.uid() and a.local_date=p_local_date
      and a.planned_workout_id=p_planned_workout_id and a.superseded_at is null
      and a.status='accepted';
    adjusted := found;
  end if;

  insert into public.workout_sessions(
    user_id,plan_version_id,planned_workout_id,local_date,timezone,idempotency_key,actual_started_at,
    day_adjustment_id
  ) values(
    auth.uid(),version_id,p_planned_workout_id,p_local_date,p_timezone,p_idempotency_key,now(),
    case when adjusted then adjustment.id end
  ) returning id into result_id;

  for exercise in select * from public.planned_exercises pe
    where pe.planned_workout_id=p_planned_workout_id order by exercise_order loop
    insert into public.exercise_performances(
      user_id,workout_session_id,planned_exercise_id,exercise_order,status,
      performance_kind,performed_name,rest_seconds
    ) values(
      auth.uid(),result_id,exercise.id,exercise.exercise_order,'unknown',
      'prescribed',exercise.display_name_snapshot,exercise.rest_seconds
    ) returning id into performance_id;
    set_total := exercise.set_count;
    if adjusted and adjustment.kind='reduce_sets' then
      select (c ->> 'sets_to')::integer into set_total
      from jsonb_array_elements(adjustment.changes) c
      where c ->> 'planned_exercise_id' = exercise.id::text;
      set_total := coalesce(set_total, exercise.set_count);
    end if;
    for n in 1..set_total loop
      insert into public.exercise_sets(user_id,exercise_performance_id,set_number)
      values(auth.uid(),performance_id,n);
    end loop;
  end loop;
  return result_id;
end $$;
revoke all on function public.start_workout(uuid, date, text, uuid) from public, anon, authenticated;
grant execute on function public.start_workout(uuid, date, text, uuid) to authenticated;

-- 5. The athlete's own late send ----------------------------------------------------------------

-- A workout finished offline can reach the server after the rule closed it. Only the rule's own
-- close counts (its audit event carries reason 'stale'); an athlete's discard has no reason and
-- stays final.
create function private.workout_closed_as_stale(p_session_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from public.audit_events e
    where e.target_type = 'workout_session' and e.target_id = p_session_id
      and e.action_code = 'workout.abandoned' and e.metadata->>'reason' = 'stale');
$$;
revoke all on function private.workout_closed_as_stale(uuid) from public, anon, authenticated;

-- Unsent sets are saved into a session the rule closed; it stays abandoned until it is finished.
create or replace function public.sync_workout_draft(session_id uuid, client_revision integer, draft jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare session public.workout_sessions%rowtype; exercise jsonb; set_row jsonb; performance_id uuid;
  requested_status text; stored public.exercise_sets%rowtype; session_start timestamptz;
  next_started timestamptz; next_completed timestamptz; next_rest integer; next_rir integer;
  next_source text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into session from public.workout_sessions where id=session_id and user_id=auth.uid() for update;
  if not found then raise exception 'session not found' using errcode='P0002'; end if;
  if session.state <> 'in_progress'
    and not (session.state = 'abandoned' and private.workout_closed_as_stale(session.id)) then
    raise exception 'session is immutable' using errcode='55000';
  end if;
  if client_revision <= session.client_revision then
    return jsonb_build_object('session_id',session.id,'client_revision',session.client_revision,'replayed',true);
  end if;
  if jsonb_typeof(draft->'exercises') <> 'array' then raise exception 'invalid workout draft' using errcode='22023'; end if;
  session_start := coalesce(session.actual_started_at, session.started_at);
  for exercise in select value from jsonb_array_elements(draft->'exercises') loop
    select id into performance_id from public.exercise_performances
    where workout_session_id=session.id and exercise_order=(exercise->>'order')::smallint;
    if performance_id is null then raise exception 'unknown exercise order' using errcode='22023'; end if;
    requested_status := coalesce(exercise->>'status','unknown');
    if requested_status not in ('unknown','performed','skipped') then raise exception 'invalid exercise status' using errcode='22023'; end if;
    update public.exercise_performances set
      status=requested_status,
      pain_flag=coalesce((exercise->>'pain_flag')::boolean,pain_flag),
      note=coalesce(exercise->>'note',note),
      rest_seconds=coalesce(nullif(exercise->>'rest_seconds','')::smallint,rest_seconds),
      performance_kind=coalesce(exercise->>'performance_kind',performance_kind),
      performed_name=coalesce(nullif(exercise->>'performed_name',''),performed_name),
      substitution_reason=coalesce(nullif(exercise->>'substitution_reason',''),substitution_reason)
    where id=performance_id;
    for set_row in select value from jsonb_array_elements(coalesce(exercise->'sets','[]'::jsonb)) loop
      select * into stored from public.exercise_sets
      where exercise_performance_id=performance_id and set_number=(set_row->>'number')::smallint
      for update;
      if not found then raise exception 'unknown set number' using errcode='22023'; end if;
      next_started := case when set_row ? 'started_at'
        then private.workout_set_time(set_row->'started_at', session_start) else stored.started_at end;
      next_completed := case when set_row ? 'completed_at'
        then private.workout_set_time(set_row->'completed_at', session_start) else stored.completed_at end;
      next_rest := case when set_row ? 'rest_before_seconds'
        then private.workout_set_whole_number(set_row->'rest_before_seconds', 0, 3600, 'rest_before_seconds')
        else stored.rest_before_seconds end;
      next_rir := case when set_row ? 'rir'
        then private.workout_set_whole_number(set_row->'rir', 0, 5, 'rir') else stored.rir end;
      next_source := stored.timing_source;
      if set_row ? 'timing_source' then
        if jsonb_typeof(set_row->'timing_source') = 'null' then
          next_source := null;
        elsif set_row->'timing_source' in ('"app"'::jsonb, '"watch"'::jsonb) then
          next_source := set_row->>'timing_source';
        else
          raise exception 'timing_source must be app or watch' using errcode='22023';
        end if;
      end if;
      if next_completed < next_started then
        raise exception 'a set cannot end before it starts' using errcode='22023';
      end if;
      update public.exercise_sets set
        repetitions=nullif(set_row->>'repetitions','')::smallint,
        load_kg=nullif(set_row->>'load_kg','')::numeric,
        rpe=nullif(set_row->>'rpe','')::numeric,
        completed=coalesce((set_row->>'completed')::boolean,false),
        started_at=next_started,
        completed_at=next_completed,
        rest_before_seconds=next_rest,
        rir=next_rir,
        timing_source=next_source
      where id=stored.id;
    end loop;
  end loop;
  update public.workout_sessions set
    client_revision=sync_workout_draft.client_revision,
    notes=coalesce(draft->>'notes',notes),updated_at=now()
  where id=session.id;
  return jsonb_build_object('session_id',session.id,'client_revision',client_revision,'replayed',false);
end $$;
revoke all on function public.sync_workout_draft(uuid, integer, jsonb) from public, anon, authenticated;
grant execute on function public.sync_workout_draft(uuid, integer, jsonb) to authenticated;

-- Finishing a session the rule closed completes it on its own local_date; its end is its start plus
-- the athlete's own duration, never the time of the late send.
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
  capped_duration := least(p_duration_seconds, 10800);
  update public.exercise_performances p set status = case
    when p.status = 'skipped' then 'skipped'
    when exists (select 1 from public.exercise_sets s
                 where s.exercise_performance_id = p.id and s.completed) then 'performed'
    else 'unknown' end
  where p.workout_session_id = session.id;
  update public.workout_sessions set
    state = 'completed', completed_at = now(),
    actual_ended_at = coalesce(actual_ended_at, case when closed_as_stale
      then least(now(), coalesce(actual_started_at, started_at) + capped_duration * interval '1 second')
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
revoke all on function private.complete_workout_session(uuid, integer, integer, smallint, numeric, text, text)
  from public, anon, authenticated;
