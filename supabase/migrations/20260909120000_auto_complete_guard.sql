-- Repair healthkit_auto_complete_workout guard parity (2026-09-09).
--
-- Two production bugs found by the failing healthkit_auto_complete_workout_test.sql
-- (statically classified 2026-09-09, confirmed against both the 2026-07-18 original
-- and the 2026-07-26 re-creation):
--
-- 1. Missing weekday guard. get_healthkit_completion_candidate only surfaces a
--    planned workout whose preferred_weekday matches the queried date, but the
--    auto-complete RPC accepted ANY planned workout in the active plan for any
--    date with HealthKit data — a client could force-complete Thursday's
--    workout on Tuesday. Mirrors the candidate RPC's guard.
-- 2. NULL-duration phantom sessions. With no summary row for the date,
--    `select coalesce(workout_minutes, 0) * 60 into v_duration_seconds` left the
--    variable NULL, so the `if v_duration_seconds = 0` no-data check never fired
--    and a completed session with NULL duration_seconds was inserted.
--
-- Additive create-or-replace; signature, return shape, grants, and audit events
-- unchanged. The deployed Flutter app only invokes this from the weekday-correct
-- candidate flow, so legitimate calls are unaffected.

create or replace function public.healthkit_auto_complete_workout(
  p_planned_workout_id uuid,
  p_local_date date
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid;
  v_plan_version_id uuid;
  v_duration_seconds integer;
  v_session_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select v.id into v_plan_version_id
  from public.planned_workouts w
  join public.training_plan_versions v
    on v.id = w.plan_version_id and v.user_id = w.user_id
  where w.id = p_planned_workout_id
    and w.user_id = v_user_id
    and v.status = 'active'
    and w.preferred_weekday = extract(isodow from p_local_date)::integer;

  if v_plan_version_id is null then
    raise exception 'planned workout not found, not in active plan, or not scheduled for this weekday';
  end if;

  if exists (
    select 1 from public.workout_sessions
    where user_id = v_user_id
      and planned_workout_id = p_planned_workout_id
      and local_date = p_local_date
      and state = 'completed'
  ) then
    return jsonb_build_object('session_id', null, 'replayed', true);
  end if;

  select coalesce(h.workout_minutes, 0) * 60 into v_duration_seconds
  from public.daily_health_summaries h
  where h.user_id = v_user_id
    and h.local_date = p_local_date
    and h.source_scope = 'healthkit'
  limit 1;

  if v_duration_seconds is null or v_duration_seconds = 0 then
    raise exception 'no HealthKit workout data available for this date';
  end if;

  insert into public.workout_sessions (
    user_id, plan_version_id, planned_workout_id,
    local_date, timezone, state, idempotency_key,
    started_at, completed_at, actual_started_at, actual_ended_at,
    duration_seconds, session_effort, notes
  ) values (
    v_user_id, v_plan_version_id, p_planned_workout_id,
    p_local_date, 'UTC', 'completed',
    gen_random_uuid(),
    now() - make_interval(secs := v_duration_seconds), now(),
    now() - make_interval(secs := v_duration_seconds), now(),
    v_duration_seconds,
    5,
    'Marked complete from Apple Health evidence'
  )
  returning id into v_session_id;

  insert into public.audit_events (
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    v_user_id, 'workout.auto_completed',
    'workout_session', v_session_id, 'succeeded',
    jsonb_build_object(
      'source', 'healthkit',
      'planned_workout_id', p_planned_workout_id,
      'local_date', p_local_date,
      'duration_seconds', v_duration_seconds,
      'effort', 5
    )
  );

  return jsonb_build_object(
    'session_id', v_session_id,
    'replayed', false,
    'effort', 5
  );
end;
$$;

revoke all on function public.healthkit_auto_complete_workout(uuid, date) from public, anon;
grant execute on function public.healthkit_auto_complete_workout(uuid, date) to authenticated;
