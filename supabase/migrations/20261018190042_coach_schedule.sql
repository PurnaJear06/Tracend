-- Coach sees the next seven days and the muscles shared on consecutive days.
--
-- The Coach plan baseline stopped at the calendar week: on a Sunday it listed the week's
-- remaining sessions and called a Monday session "done this week" because last Monday's had
-- been logged, so Coach never saw that tomorrow's session trained the muscles of the one it
-- was prescribing today. The schedule from the athlete's own date and the overlap are worked
-- out in TypeScript (_shared/training/schedule); this migration only adds the data they need.
-- Every change adds fields and bumps schema_version from 1.0 to 1.1; no field is removed.
--
-- 0. private.coach_session_exercises  the sets a finished session logged, per exercise
--    private.coach_plan_sessions      the sessions of one plan version (shared by the plan state)
-- 1. get_coach_plan_state_v1     + recent_completed: yesterday's and today's finished sessions,
--                                  + after_block: the sessions a temporary block hands back to
-- 2. get_coach_data_index_v1     + schedule: the active plan's weekdays and the first date a plan covers
-- 3. coach_lookup_plan_history_v1  filter "schedule": the plan laid over any range of dates,
--                                  past or ahead (private.coach_plan_schedule)

-- 0 ----------------------------------------------------------------------------------------------

-- The exercises of a finished session as {slug, sets}: the sets the athlete logged as completed
-- for each exercise performed, else, when nothing was logged (a session completed without sets),
-- the sets it was planned with. The slug is the performed exercise's own: the trigger
-- private.exercise_performance_slug gives a performance a catalog slug only while it is the
-- prescribed exercise, so a substitution or an extra exercise has none and reports a null slug
-- (Coach then says its muscles are unknown). The planned exercise's slug is never used for a
-- substitute. Like the other private helpers it is not SECURITY DEFINER: the public functions that
-- call it are.
create function private.coach_session_exercises(p_user_id uuid, p_session_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select case when jsonb_array_length(logged.items) > 0 then logged.items else planned.items end
  from (
    select coalesce(jsonb_agg(jsonb_build_object('slug', p.exercise_slug, 'sets', n.sets)
        order by p.exercise_order), '[]'::jsonb) as items
    from public.exercise_performances p
    cross join lateral (select count(*)::integer as sets from public.exercise_sets es
      where es.exercise_performance_id = p.id and es.user_id = p.user_id and es.completed) n
    where p.workout_session_id = p_session_id and p.user_id = p_user_id
      and p.status = 'performed' and n.sets > 0
  ) logged,
  (
    select coalesce(jsonb_agg(jsonb_build_object('slug', e.exercise_slug, 'sets', e.set_count)
        order by e.exercise_order), '[]'::jsonb) as items
    from public.workout_sessions s
    join public.planned_exercises e on e.planned_workout_id = s.planned_workout_id
      and e.user_id = s.user_id
    where s.id = p_session_id and s.user_id = p_user_id
  ) planned;
$$;
revoke all on function private.coach_session_exercises(uuid, uuid) from public, anon, authenticated;

-- 0b ---------------------------------------------------------------------------------------------

-- The sessions of one plan version with their exercises, as get_coach_plan_state_v1 has always
-- listed them. Not SECURITY DEFINER, like the other private helpers.
create function private.coach_plan_sessions(p_user_id uuid, p_version_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce((select jsonb_agg(jsonb_build_object(
        'planned_workout_id', w.id, 'order', w.workout_order, 'name', w.name,
        'weekday', w.preferred_weekday, 'minutes', w.estimated_minutes,
        'exercises', (select coalesce(jsonb_agg(jsonb_build_object(
            'planned_exercise_id', e.id, 'order', e.exercise_order,
            'name', e.display_name_snapshot, 'slug', e.exercise_slug, 'sets', e.set_count,
            'rep_min', e.rep_min, 'rep_max', e.rep_max, 'rest_seconds', e.rest_seconds,
            'target_rpe', e.target_rpe, 'load_kg', e.target_load_kg
          ) order by e.exercise_order), '[]'::jsonb)
          from public.planned_exercises e
          where e.planned_workout_id = w.id and e.user_id = w.user_id)
      ) order by w.workout_order)
      from public.planned_workouts w where w.plan_version_id = p_version_id and w.user_id = p_user_id), '[]'::jsonb);
$$;
revoke all on function private.coach_plan_sessions(uuid, uuid) from public, anon, authenticated;

-- 1 ----------------------------------------------------------------------------------------------

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
    'schema_version', '1.1',
    'local_date', p_local_date,
    'weekday', extract(isodow from p_local_date)::integer,
    -- Equipment counts only once the athlete answered the intake that asks for it.
    'equipment', (select case when pr.daily_activity is not null then to_jsonb(pr.equipment) end
      from public.user_profiles pr where pr.user_id = p_user_id),
    'avoid_patterns', (select to_jsonb(pr.avoid_patterns)
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
    'progression', public.get_progression_summary_v1(p_user_id));
$$;

-- 2 ----------------------------------------------------------------------------------------------

create or replace function public.get_coach_data_index_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.1',
    'local_date', p_local_date,
    'domains', jsonb_build_object(
      'workouts', (select jsonb_build_object('first', min(s.local_date), 'last', max(s.local_date),
          'count', count(*)) from public.workout_sessions s
        where s.user_id = p_user_id and s.state = 'completed'),
      'meals', (select jsonb_build_object('first', min(m.local_date), 'last', max(m.local_date),
          'count', count(distinct m.local_date)) from public.meals m
        where m.user_id = p_user_id and m.status = 'confirmed'),
      -- The same readings as coach_lookup_body_v1: manual and HealthKit weights, an amended
      -- reading replaced by its amendment, one count per date.
      'body', (select jsonb_build_object('first', min(r.d), 'last', max(r.d), 'count', count(*))
        from (
          select b.measured_on as d from public.body_measurements b
          where b.user_id = p_user_id
            and not exists (select 1 from public.body_measurements newer
              where newer.user_id = b.user_id and newer.amended_from_id = b.id)
          union
          select h.local_date from public.daily_health_summaries h
          where h.user_id = p_user_id and h.weight_kg is not null
            and not exists (select 1 from public.body_measurements m
              where m.user_id = h.user_id and m.measured_on = h.local_date
                and m.weight_kg is not null
                and not exists (select 1 from public.body_measurements newer
                  where newer.user_id = m.user_id and newer.amended_from_id = m.id))
        ) r),
      'check_ins', (select jsonb_build_object('first', min(c.local_date), 'last', max(c.local_date),
          'count', count(*)) from public.daily_check_ins c
        where c.user_id = p_user_id and c.superseded_at is null),
      'recovery', (select jsonb_build_object('first', min(h.local_date), 'last', max(h.local_date),
          'count', count(*)) from public.daily_health_summaries h where h.user_id = p_user_id),
      'plan_history', (select jsonb_build_object('first', min(private.local_day(p_user_id, v.created_at)),
          'last', max(private.local_day(p_user_id, v.created_at)), 'count', count(*))
        from public.training_plan_versions v where v.user_id = p_user_id),
      'goals', (select jsonb_build_object('first', min(private.local_day(p_user_id, g.created_at)),
          'last', max(private.local_day(p_user_id, g.created_at)), 'count', count(*))
        from public.user_goals g where g.user_id = p_user_id),
      'weekly_reviews', (select jsonb_build_object('first', min(r.review_week),
          'last', max(r.review_week), 'count', count(*))
        from public.progress_reviews r where r.user_id = p_user_id),
      'health_history', (select jsonb_build_object('first', min(hm.month), 'last', max(hm.month),
          'count', count(*)) from public.health_history_months hm where hm.user_id = p_user_id)),
    -- The training plan repeats every week: which weekdays have a session and from when, so Coach
    -- knows the schedule covers any date from then on, past or ahead (plan_history lookup with the
    -- filter "schedule").
    'schedule', (select jsonb_build_object('version', v.version_number,
        'starts_on', (select min(coalesce(x.effective_date, private.local_day(p_user_id, x.created_at)))
          from public.training_plan_versions x
          where x.user_id = p_user_id and x.status in ('active', 'superseded')),
        'weekdays', (select coalesce(jsonb_agg(distinct w.preferred_weekday
            order by w.preferred_weekday), '[]'::jsonb)
          from public.planned_workouts w
          where w.plan_version_id = v.id and w.user_id = p_user_id
            and w.preferred_weekday is not null))
      from public.training_plan_versions v where v.user_id = p_user_id and v.status = 'active'
      limit 1));
$$;

-- 3 ----------------------------------------------------------------------------------------------

-- The training plan laid over a range of dates, past or ahead. Each date uses the plan version in
-- force on it: the latest non-draft version that took effect on or before the date (a plan change
-- shows from its effective date; earlier dates keep the version superseded then). When that
-- version is a temporary block (ends_on set), the dates after its last day use the version it
-- restores, which is what the athlete returns to. A date before the first version shows only what
-- was logged. Every day names its version (id and number) and says if it is a block; every session
-- names the version it belongs to. The plan repeats weekly on
-- each session's weekday. Every finished session in the range is listed with the sets it logged
-- per exercise, so the muscles can be worked out from sets. Days with neither a planned nor a
-- finished session are left out. `today` is the athlete's own date, which tells a missed session
-- from an upcoming one. Planned sessions name a workout in `sessions`; the range is cut to 400 days
-- and to 90 days after the athlete's today.
create function private.coach_plan_schedule(p_user_id uuid, p_from date, p_to date)
returns jsonb language sql stable set search_path = '' as $$
  with active as (
    select v.id, v.version_number, v.sessions_per_week,
      coalesce(v.effective_date, private.local_day(p_user_id, v.created_at)) as starts_on
    from public.training_plan_versions v
    where v.user_id = p_user_id and v.status = 'active' limit 1
  ), bounds as (
    -- At most 400 days, ending no later than 90 days after the athlete's own today
    -- (maxScheduleAheadDays in coach_lookups/catalogue.ts, which validates the same bound).
    select greatest(p_from, least(p_to, private.local_date_for(p_user_id) + 90) - 399) as first_day,
      least(p_to, private.local_date_for(p_user_id) + 90) as last_day
  ), versions as (
    select v.id, v.version_number, v.block_kind, v.ends_on, v.restores_version_id, v.created_at,
      coalesce(v.effective_date, private.local_day(p_user_id, v.created_at)) as starts_on
    from public.training_plan_versions v
    where v.user_id = p_user_id and v.status in ('active', 'superseded')
  ), span as (
    select (b.first_day + g)::date as day
    from bounds b, generate_series(0, b.last_day - b.first_day) g
  ), resolved as (
    select sp.day,
      case when pick.ends_on is not null and sp.day > pick.ends_on then pick.restores_version_id
        else pick.id end as version_id,
      coalesce(pick.ends_on is not null and sp.day <= pick.ends_on, false) as in_block
    from span sp
    left join lateral (
      select x.* from versions x where x.starts_on <= sp.day
      order by x.starts_on desc, x.created_at desc limit 1) pick on true
  ), planned as (
    select w.id, w.plan_version_id, w.name, w.preferred_weekday as weekday, w.workout_order,
      w.estimated_minutes
    from public.planned_workouts w
    where w.user_id = p_user_id and w.preferred_weekday is not null
      and w.plan_version_id in (select r.version_id from resolved r where r.version_id is not null)
  ), done as (
    select s.local_date, cw.id as workout_id, cw.name,
      private.coach_session_exercises(p_user_id, s.id) as exercises
    from public.workout_sessions s
    join public.planned_workouts cw on cw.id = s.planned_workout_id and cw.user_id = s.user_id
    cross join bounds b
    where s.user_id = p_user_id and s.state = 'completed'
      and s.local_date between b.first_day and b.last_day
  ), days as (
    select r.day, extract(isodow from r.day)::integer as weekday, r.version_id, rv.version_number,
      r.in_block,
      (select jsonb_agg(jsonb_build_object('id', pl.id, 'name', pl.name,
          'minutes', pl.estimated_minutes) order by pl.workout_order)
        from planned pl
        where pl.plan_version_id = r.version_id
          and pl.weekday = extract(isodow from r.day)::integer) as planned,
      (select jsonb_agg(jsonb_build_object('planned_workout_id', dn.workout_id, 'name', dn.name,
          'exercises', dn.exercises) order by dn.name, dn.workout_id)
        from done dn where dn.local_date = r.day) as done
    from resolved r
    left join public.training_plan_versions rv on rv.id = r.version_id and rv.user_id = p_user_id
  )
  select jsonb_build_object(
    'schema_version', '1.1', 'lookup', 'plan_history', 'filter', 'schedule',
    'from', (select first_day from bounds), 'to', (select last_day from bounds),
    'today', private.local_date_for(p_user_id),
    'truncated', false,
    'plan', (select jsonb_build_object('id', a.id, 'version', a.version_number,
        'starts_on', a.starts_on, 'sessions_per_week', a.sessions_per_week) from active a),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object('id', pl.id,
        'version_id', pl.plan_version_id, 'name', pl.name,
        'weekday', pl.weekday, 'exercises', (select coalesce(jsonb_agg(jsonb_build_object(
            'slug', e.exercise_slug, 'sets', e.set_count) order by e.exercise_order), '[]'::jsonb)
          from public.planned_exercises e
          where e.planned_workout_id = pl.id and e.user_id = p_user_id))
        order by pl.plan_version_id, pl.workout_order) from planned pl), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(jsonb_build_object('date', d.day, 'weekday', d.weekday,
        'version_id', d.version_id, 'version', d.version_number, 'block', d.in_block,
        'planned', coalesce(d.planned, '[]'::jsonb), 'done', coalesce(d.done, '[]'::jsonb))
        order by d.day) from days d where d.planned is not null or d.done is not null), '[]'::jsonb));
$$;
revoke all on function private.coach_plan_schedule(uuid, date, date) from public, anon, authenticated;

create or replace function public.coach_lookup_plan_history_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  -- The filter "schedule" asks for the day-by-day schedule of the range instead of the versions.
  if lower(btrim(coalesce(p_filter, ''))) = 'schedule' then
    return private.coach_plan_schedule(p_user_id, p_from, p_to);
  end if;
  return (
  with versions as (
      select v.id, v.version_number, v.status, p.title, v.sessions_per_week, v.block_weeks,
        v.effective_date, v.created_at, v.rationale
      from public.training_plan_versions v
      join public.training_plans p on p.id = v.plan_id and p.user_id = v.user_id
      where v.user_id = p_user_id
        and (v.status = 'active'
          or private.local_day(p_user_id, v.created_at) between greatest(p_from, p_to - 399) and p_to)
      order by v.created_at desc limit 7
    ), targets as (
      select s.version_number, s.status, s.calories, s.protein_g, s.carbohydrate_g, s.fat_g,
        s.effective_date, s.created_at, s.rationale
      from public.nutrition_target_sets s
      where s.user_id = p_user_id
        and (s.status = 'active'
          or private.local_day(p_user_id, s.created_at) between greatest(p_from, p_to - 399) and p_to)
      order by s.created_at desc limit 13
    )
    select jsonb_build_object(
      'schema_version', '1.1', 'lookup', 'plan_history', 'from', greatest(p_from, p_to - 399),
      'to', p_to,
      'truncated', (select count(*) > 6 from versions) or (select count(*) > 12 from targets),
      'training', coalesce((select jsonb_agg(jsonb_build_object('version', v.version_number,
          'status', v.status, 'title', v.title, 'sessions_per_week', v.sessions_per_week,
          'block_weeks', v.block_weeks, 'effective_date', v.effective_date,
          'created_on', private.local_day(p_user_id, v.created_at), 'rationale', left(v.rationale, 400),
          'sessions', (select coalesce(jsonb_agg(jsonb_build_object('name', w.name,
              'weekday', w.preferred_weekday,
              'exercises', (select coalesce(jsonb_agg(jsonb_build_object('name',
                  e.display_name_snapshot, 'sets', e.set_count, 'rep_min', e.rep_min,
                  'rep_max', e.rep_max) order by e.exercise_order), '[]'::jsonb)
                from public.planned_exercises e
                where e.planned_workout_id = w.id and e.user_id = w.user_id))
              order by w.workout_order), '[]'::jsonb)
            from public.planned_workouts w
            where w.plan_version_id = v.id and w.user_id = p_user_id))
          order by v.created_at desc)
        from (select * from versions order by created_at desc limit 6) v), '[]'::jsonb),
      'nutrition', coalesce((select jsonb_agg(jsonb_build_object('version', t.version_number,
          'status', t.status, 'calories', t.calories, 'protein_g', t.protein_g,
          'carbohydrate_g', t.carbohydrate_g, 'fat_g', t.fat_g,
          'effective_date', t.effective_date, 'created_on', private.local_day(p_user_id, t.created_at),
          'rationale', left(t.rationale, 300)) order by t.created_at desc)
        from (select * from targets order by created_at desc limit 12) t), '[]'::jsonb)));
end $$;
