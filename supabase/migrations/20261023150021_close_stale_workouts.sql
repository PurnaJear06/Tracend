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
--
-- start_workout is not changed here: the app always reads the session first, and the hourly job
-- covers the rest.

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
