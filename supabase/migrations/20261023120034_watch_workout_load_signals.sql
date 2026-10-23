-- Watch-workout prompt and load signals (coaching platform chunk C4, migration code 34).
--
-- 1. get_my_watch_workout_status_v1 tells the app how many of the athlete's last three finished
--    workouts had Apple Watch heart rate (a Watch workout sampling every few seconds). The app
--    uses it to decide whether to suggest starting a Watch workout before the next session.
-- 2. get_workout_load_inputs_v1 (service role only) returns what the training engine's load
--    signals need: the athlete's recent finished workouts with, for each set that has a heart-rate
--    summary, the rest taken before it and the summary. It returns no load, no repetitions and no
--    reps in reserve, so a signal worked out from it cannot depend on them.
-- Heart rate never changes a load or a prescription (program decision D9). Neither function writes
-- anything, no table is added, and the functions are additive.

-- 1. The app's status ------------------------------------------------------------------------

-- The last three finished workouts of the last 28 days that had at least one finished set: how many
-- sets they finished and how many of those sets have Watch-workout heart rate with at least half of
-- the set and the minute after it covered. Workouts marked complete from Apple Health (no sets) and
-- discarded ones are left out.
create function private.watch_workout_status(target_user uuid, as_of date)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'as_of', as_of,
    'recent_sessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'local_date', r.local_date, 'completed_sets', r.completed_sets, 'watch_sets', r.watch_sets)
        order by r.local_date desc, r.completed_at desc)
      from (
        select w.local_date, w.completed_at, c.completed_sets, c.watch_sets
        from public.workout_sessions w
        cross join lateral (
          select (count(*) filter (where s.completed))::integer as completed_sets,
            (count(*) filter (
              where s.completed and h.source = 'watch_workout' and h.coverage >= 0.5))::integer as watch_sets
          from public.exercise_performances p
          join public.exercise_sets s on s.exercise_performance_id = p.id and s.user_id = p.user_id
          left join public.exercise_set_heart_rate h on h.exercise_set_id = s.id and h.user_id = s.user_id
          where p.workout_session_id = w.id and p.user_id = w.user_id) c
        where w.user_id = target_user and w.state = 'completed'
          and w.local_date between as_of - 27 and as_of and c.completed_sets > 0
        order by w.local_date desc, w.completed_at desc
        limit 3) r), '[]'::jsonb));
$$;
revoke all on function private.watch_workout_status(uuid, date) from public, anon, authenticated;

create function public.get_my_watch_workout_status_v1(local_date date default null)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare as_of date := coalesce(get_my_watch_workout_status_v1.local_date, current_date);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if as_of > current_date + 2 or as_of < current_date - 2 then
    raise exception 'local_date is out of range' using errcode = '22023';
  end if;
  return private.watch_workout_status(auth.uid(), as_of);
end $$;
revoke all on function public.get_my_watch_workout_status_v1(date) from public, anon, authenticated;
grant execute on function public.get_my_watch_workout_status_v1(date) to authenticated;

-- 2. The engine's inputs ---------------------------------------------------------------------

-- Finished workouts of the last 28 days, newest 12. Each lists how many sets it finished and, for
-- the finished sets that have a heart-rate summary, the exercise order and set number, the rest
-- actually taken before the set (null when not recorded) and the Contract 4 summary. Sets without a
-- summary are not listed: the engine counts them through `completed_sets`. At most 120 summaries
-- are listed per workout. Discarded and unfinished workouts are left out.
create function private.workout_load_inputs(target_user uuid, as_of date)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'as_of', as_of,
    'sessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'local_date', r.local_date,
        'completed_sets', r.completed_sets,
        'sets', r.sets)
        order by r.local_date desc, r.completed_at desc)
      from (
        select w.local_date, w.completed_at, c.completed_sets,
          coalesce((
            select jsonb_agg(jsonb_build_object(
              'exercise_order', x.exercise_order, 'set_number', x.set_number,
              'rest_before_seconds', x.rest_before_seconds,
              'start_bpm', x.start_bpm, 'peak_bpm', x.peak_bpm, 'end_bpm', x.end_bpm,
              'drop_30s_bpm', x.drop_30s_bpm, 'drop_60s_bpm', x.drop_60s_bpm,
              'coverage', x.coverage, 'sample_count', x.sample_count, 'source', x.source)
              order by x.exercise_order, x.set_number)
            from (
              select p.exercise_order, s.set_number, s.rest_before_seconds, h.start_bpm, h.peak_bpm,
                h.end_bpm, h.drop_30s_bpm, h.drop_60s_bpm, h.coverage, h.sample_count, h.source
              from public.exercise_performances p
              join public.exercise_sets s on s.exercise_performance_id = p.id and s.user_id = p.user_id
              join public.exercise_set_heart_rate h on h.exercise_set_id = s.id and h.user_id = s.user_id
              where p.workout_session_id = w.id and p.user_id = w.user_id and s.completed
              order by p.exercise_order, s.set_number
              limit 120) x), '[]'::jsonb) as sets
        from public.workout_sessions w
        cross join lateral (
          select count(*)::integer as completed_sets
          from public.exercise_performances p
          join public.exercise_sets s on s.exercise_performance_id = p.id and s.user_id = p.user_id
          where p.workout_session_id = w.id and p.user_id = w.user_id and s.completed) c
        where w.user_id = target_user and w.state = 'completed'
          and w.local_date between as_of - 27 and as_of and c.completed_sets > 0
        order by w.local_date desc, w.completed_at desc
        limit 12) r), '[]'::jsonb));
$$;
revoke all on function private.workout_load_inputs(uuid, date) from public, anon, authenticated;

-- The engine's read: any athlete, the service role only (the same rule as get_heart_rate_inputs_v1).
create function public.get_workout_load_inputs_v1(target_user uuid, local_date date)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
begin
  if target_user is null or get_workout_load_inputs_v1.local_date is null then
    raise exception 'target_user and local_date are required' using errcode = '22023';
  end if;
  return private.workout_load_inputs(target_user, get_workout_load_inputs_v1.local_date);
end $$;
revoke all on function public.get_workout_load_inputs_v1(uuid, date) from public, anon, authenticated;
grant execute on function public.get_workout_load_inputs_v1(uuid, date) to service_role;
