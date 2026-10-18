-- Coach sees the next seven days and the muscles shared on consecutive days.
--
-- The Coach plan baseline stopped at the calendar week: on a Sunday it listed the week's
-- remaining sessions and called a Monday session "done this week" because last Monday's had
-- been logged, so Coach never saw that tomorrow's session trained the muscles of the one it
-- was prescribing today. The schedule from the athlete's own date and the overlap are worked
-- out in TypeScript (_shared/training/schedule); this migration only adds the data they need.
-- Every change adds fields and bumps schema_version from 1.0 to 1.1; no field is removed.
--
-- 1. get_coach_plan_state_v1     + recent_completed: yesterday's and today's finished sessions
-- 2. get_coach_data_index_v1     + schedule: the active plan's weekdays and the date it started
-- 3. coach_lookup_plan_history_v1  filter "schedule": the plan laid over any range of dates,
--                                  past or ahead (private.coach_plan_schedule)

-- 1 ----------------------------------------------------------------------------------------------

create or replace function public.get_coach_plan_state_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with active as (
    select v.id as version_id, v.version_number, v.sessions_per_week, p.title
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
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
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
      from public.planned_workouts w join active a on a.version_id = w.plan_version_id
      where w.user_id = p_user_id), '[]'::jsonb),
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
    -- Yesterday's and today's finished sessions whatever the calendar week, each with the
    -- exercises it was planned with: the week-ahead schedule needs yesterday on a Monday, and
    -- completed_this_week stops at Monday.
    'recent_completed', coalesce((select jsonb_agg(jsonb_build_object(
        'planned_workout_id', s.planned_workout_id, 'local_date', s.local_date, 'name', cw.name,
        'exercises', (select coalesce(jsonb_agg(jsonb_build_object('slug', e.exercise_slug,
            'sets', e.set_count) order by e.exercise_order), '[]'::jsonb)
          from public.planned_exercises e
          where e.planned_workout_id = cw.id and e.user_id = cw.user_id))
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
        'starts_on', coalesce(v.effective_date, private.local_day(p_user_id, v.created_at)),
        'weekdays', (select coalesce(jsonb_agg(distinct w.preferred_weekday
            order by w.preferred_weekday), '[]'::jsonb)
          from public.planned_workouts w
          where w.plan_version_id = v.id and w.user_id = p_user_id
            and w.preferred_weekday is not null))
      from public.training_plan_versions v where v.user_id = p_user_id and v.status = 'active'
      limit 1));
$$;

-- 3 ----------------------------------------------------------------------------------------------

-- The training plan laid over a range of dates, past or ahead. The active plan repeats weekly on
-- each session's weekday from the day it took effect; a date before that shows only what was
-- logged. Every finished session in the range is listed with the exercises it was planned with,
-- so the muscles can be worked out from sets. Days with neither a planned nor a finished session
-- are left out. `today` is the athlete's own date, which tells a missed session from an upcoming
-- one. Planned sessions name a workout in `sessions`; the range is cut to 400 days ending on p_to.
create function private.coach_plan_schedule(p_user_id uuid, p_from date, p_to date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with active as (
    select v.id, v.version_number, v.sessions_per_week,
      coalesce(v.effective_date, private.local_day(p_user_id, v.created_at)) as starts_on
    from public.training_plan_versions v
    where v.user_id = p_user_id and v.status = 'active' limit 1
  ), bounds as (
    select greatest(p_from, p_to - 399) as first_day
  ), planned as (
    select w.id, w.name, w.preferred_weekday as weekday, w.workout_order, w.estimated_minutes
    from public.planned_workouts w join active a on a.id = w.plan_version_id
    where w.user_id = p_user_id and w.preferred_weekday is not null
  ), done as (
    select s.local_date, cw.name,
      (select coalesce(jsonb_agg(jsonb_build_object('slug', e.exercise_slug, 'sets', e.set_count)
          order by e.exercise_order), '[]'::jsonb)
        from public.planned_exercises e
        where e.planned_workout_id = cw.id and e.user_id = cw.user_id) as exercises
    from public.workout_sessions s
    join public.planned_workouts cw on cw.id = s.planned_workout_id and cw.user_id = s.user_id
    cross join bounds b
    where s.user_id = p_user_id and s.state = 'completed'
      and s.local_date between b.first_day and p_to
  ), span as (
    select (b.first_day + g)::date as day
    from bounds b, generate_series(0, p_to - b.first_day) g
  ), days as (
    select sp.day, extract(isodow from sp.day)::integer as weekday,
      (select jsonb_agg(jsonb_build_object('name', pl.name, 'minutes', pl.estimated_minutes)
          order by pl.workout_order)
        from planned pl cross join active a
        where pl.weekday = extract(isodow from sp.day)::integer and sp.day >= a.starts_on) as planned,
      (select jsonb_agg(jsonb_build_object('name', dn.name, 'exercises', dn.exercises)
          order by dn.name)
        from done dn where dn.local_date = sp.day) as done
    from span sp
  )
  select jsonb_build_object(
    'schema_version', '1.1', 'lookup', 'plan_history', 'filter', 'schedule',
    'from', (select first_day from bounds), 'to', p_to,
    'today', private.local_date_for(p_user_id),
    'truncated', false,
    'plan', (select jsonb_build_object('version', a.version_number, 'starts_on', a.starts_on,
        'sessions_per_week', a.sessions_per_week) from active a),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object('name', pl.name,
        'weekday', pl.weekday, 'exercises', (select coalesce(jsonb_agg(jsonb_build_object(
            'slug', e.exercise_slug, 'sets', e.set_count) order by e.exercise_order), '[]'::jsonb)
          from public.planned_exercises e
          where e.planned_workout_id = pl.id and e.user_id = p_user_id))
        order by pl.workout_order) from planned pl), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(jsonb_build_object('date', d.day, 'weekday', d.weekday,
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
