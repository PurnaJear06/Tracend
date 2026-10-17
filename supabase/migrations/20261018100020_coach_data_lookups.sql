-- A10 part 1: Coach can look up the athlete's data, read-only.
--
-- 1. coach_messages.guard_faults / lookups   what a turn's guards and lookups did (names and
--                                            counts only, never content)
-- 2. private.nutrition_day_totals            one definition of a complete logging day
-- 3. evaluate_change_eligibility             nutrition adherence averages complete days only
-- 4. get_coach_plan_state_v1                 baseline: the plan, this week, next targets
--    get_coach_nutrition_state_v1            baseline: the week's complete days, today's meals
--    get_coach_data_index_v1                 baseline: what data exists and its date range
-- 5. coach_lookup_<name>_v1 (ten)         on-demand lookups over a date range
--
-- Every function here is SECURITY DEFINER, read-only, granted to service_role only and returns
-- schema_version. The user id is always the authenticated request's, set by the Edge Function;
-- the model only names a lookup, a range and a filter. Each lookup clamps its range to 400 days
-- and caps its rows; the Edge Function validates the same bounds before calling.

-- 1. Observability -------------------------------------------------------------------------------

-- Rule names and counts, for example 'rule:numbers_not_grounded:2' or 'fallback:provider_timeout',
-- and the lookups a turn ran, for example 'exercise_history:14' (rows). Never message content.
-- Row-level security already limits a row to its owner; the lead reads them in the SQL editor.
alter table public.coach_messages
  add column guard_faults text[],
  add column lookups text[],
  add constraint coach_messages_guard_faults_check check (guard_faults is null or (
    cardinality(guard_faults) <= 12
    and char_length(array_to_string(guard_faults, ' ')) <= 600
    and array_to_string(guard_faults, ' ') ~ '^[a-z0-9_: ]*$')),
  add constraint coach_messages_lookups_check check (lookups is null or (
    cardinality(lookups) <= 12
    and char_length(array_to_string(lookups, ' ')) <= 600
    and array_to_string(lookups, ' ') ~ '^[a-z0-9_: ]*$'));

-- 2. Complete logging days -----------------------------------------------------------------------

-- A day is complete when it has at least 3 confirmed meals or its energy reaches 70% of the
-- active calorie target. Anything less is a partial day: the rest of the day was probably not
-- logged, so it says nothing about intake. docs/ALGORITHMS.md section 6.
create function private.nutrition_complete_day_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"min_meals":3,"min_target_share":0.7}'::jsonb;
$$;
revoke all on function private.nutrition_complete_day_rules() from public, anon, authenticated;

create function private.nutrition_day_totals(p_user uuid, p_from date, p_to date)
returns table (local_date date, meals integer, calories numeric, protein_g numeric,
  carbohydrate_g numeric, fat_g numeric, complete boolean)
language sql stable security definer set search_path = '' as $$
  select d.local_date, d.meals, d.calories, d.protein_g, d.carbohydrate_g, d.fat_g,
    coalesce(d.meals >= (private.nutrition_complete_day_rules() ->> 'min_meals')::integer
      or (t.calories > 0 and d.calories >=
        t.calories * (private.nutrition_complete_day_rules() ->> 'min_target_share')::numeric),
      false)
  from (
    select m.local_date, count(distinct m.id)::integer as meals,
      coalesce(sum(i.calories), 0) as calories, coalesce(sum(i.protein_g), 0) as protein_g,
      coalesce(sum(i.carbohydrate_g), 0) as carbohydrate_g, coalesce(sum(i.fat_g), 0) as fat_g
    from public.meals m
    join public.meal_items i on i.meal_id = m.id and i.user_id = m.user_id
    where m.user_id = p_user and m.status = 'confirmed' and i.confirmed_at is not null
      and m.local_date between p_from and p_to
    group by m.local_date
  ) d
  left join lateral (
    select s.calories from public.nutrition_target_sets s
    where s.user_id = p_user and s.status = 'active' limit 1
  ) t on true;
$$;
revoke all on function private.nutrition_day_totals(uuid, date, date)
  from public, anon, authenticated;

-- The athlete's calendar day for a moment, in their account time zone (UTC when unset), so a
-- range of dates filters records by the day the athlete lived, not the UTC day.
create function private.local_day(p_user uuid, p_at timestamptz)
returns date language sql stable set search_path = '' as $$
  select (p_at at time zone coalesce((
    select a.timezone from public.user_accounts a
    join pg_catalog.pg_timezone_names z on z.name = a.timezone
    where a.id = p_user), 'UTC'))::date;
$$;
revoke all on function private.local_day(uuid, timestamptz) from public, anon, authenticated;

-- 3. Change eligibility --------------------------------------------------------------------------

-- The definition from 20260724000001_feature_engine_baselines.sql, unchanged except the nutrition
-- adherence: it averages the complete days of the last 14 only (a breakfast-only day no longer
-- counts as a 1,200 kcal deficit) and the result reports how many days that was. The formula
-- changed, so the version field in the result is bumped to eligibility-v2 (docs/ALGORITHMS.md
-- section 8, rules 1 and 5).

create or replace function public.evaluate_change_eligibility(
  target_user_id uuid,
  coaching_date date
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  comparable_sessions integer;
  adherence_14d numeric;
  training_eligible boolean;
  training_reason text;
  training_detail text;
  weight_days_28d integer;
  weight_trend numeric;
  weight_r2 numeric;
  macro_adherence numeric;
  complete_days integer := 0;
  nutrition_eligible boolean;
  nutrition_reason text;
  nutrition_detail text;
  has_active_target boolean;
begin
  if target_user_id is null
    or not exists(select 1 from public.user_accounts where id = target_user_id)
  then raise exception 'account not found' using errcode = 'P0002';
  end if;

  select count(*) into comparable_sessions
  from public.workout_sessions
  where user_id = target_user_id
    and state = 'completed'
    and local_date >= coaching_date - 14
    and logging_completeness >= 0.5;

  select coalesce(
    count(*) filter (where state = 'completed')::numeric
    / nullif(count(*), 0)::numeric, 0
  ) into adherence_14d
  from public.workout_sessions
  where user_id = target_user_id
    and local_date >= coaching_date - 14;

  if comparable_sessions >= 2 then
    training_eligible := true;
    training_reason := 'sufficient_comparable_sessions';
    training_detail := comparable_sessions || ' comparable sessions in last 14 days';
  elsif adherence_14d >= 0.80 then
    training_eligible := true;
    training_reason := 'sufficient_adherence';
    training_detail := round(adherence_14d * 100) || '% adherence over last 14 days';
  else
    training_eligible := false;
    training_reason := 'insufficient_evidence';
    training_detail := comparable_sessions || ' comparable session(s), '
      || round(adherence_14d * 100) || '% adherence. Need 2+ sessions or 80%+ adherence.';
  end if;

  select count(distinct measured_on) into weight_days_28d
  from (
    select measured_on from public.body_measurements
    where user_id = target_user_id and measured_on >= coaching_date - 28
    union
    select local_date from public.daily_health_summaries
    where user_id = target_user_id and source_scope = 'healthkit'
      and local_date >= coaching_date - 28 and weight_kg is not null
  ) w;

  select regr_slope(weight_kg, extract(epoch from measured_on::timestamp) / 86400.0),
         regr_r2(weight_kg, extract(epoch from measured_on::timestamp) / 86400.0)
  into weight_trend, weight_r2
  from (
    select measured_on, weight_kg
    from public.body_measurements
    where user_id = target_user_id and measured_on >= coaching_date - 27
    union
    select local_date, weight_kg
    from public.daily_health_summaries
    where user_id = target_user_id and source_scope = 'healthkit'
      and local_date >= coaching_date - 27 and weight_kg is not null
      and local_date not in (
        select measured_on from public.body_measurements
        where user_id = target_user_id
      )
  ) w;

  select exists(
    select 1 from public.nutrition_target_sets
    where user_id = target_user_id and status = 'active'
  ) into has_active_target;

  macro_adherence := null;
  if has_active_target then
    select round(avg(least(d.calories / nt.calories * 100, 200))), count(*)::integer
    into macro_adherence, complete_days
    from private.nutrition_day_totals(target_user_id, coaching_date - 13, coaching_date) d
    cross join (
      select calories from public.nutrition_target_sets
      where user_id = target_user_id and status = 'active' limit 1
    ) nt
    where d.complete and nt.calories > 0 and d.local_date <= coaching_date;
  end if;

  if weight_days_28d >= 14
     and macro_adherence is not null and macro_adherence >= 80
     and weight_r2 is not null and weight_r2 >= 0.3
  then
    nutrition_eligible := true;
    nutrition_reason := 'sufficient_evidence';
    nutrition_detail := weight_days_28d || ' weight days, '
      || macro_adherence || '% adherence over ' || complete_days
      || ' complete logging days, trend r2=' || round(weight_r2, 3);
  else
    nutrition_eligible := false;
    nutrition_reason := 'insufficient_evidence';
    nutrition_detail := case
      when weight_days_28d < 14 then
        weight_days_28d || ' weight days (need 14). '
      else ''
    end
    || case
      when macro_adherence is null or macro_adherence < 80 then
        coalesce(macro_adherence, 0) || '% adherence over ' || complete_days
        || ' complete logging days (need 80%). '
      else ''
    end
    || case
      when weight_r2 is null or weight_r2 < 0.3 then
        'trend r2=' || coalesce(round(weight_r2, 3), 0) || ' (need >=0.3).'
      else ''
    end;
  end if;

  return jsonb_build_object(
    'eligibility_version', 'eligibility-v2',
    'training_change', jsonb_build_object(
      'eligible', training_eligible,
      'reason', training_reason,
      'detail', training_detail
    ),
    'nutrition_change', jsonb_build_object(
      'eligible', nutrition_eligible,
      'reason', nutrition_reason,
      'detail', nutrition_detail,
      'complete_days', complete_days
    ),
    'general', case when training_eligible or nutrition_eligible
      then 'change_review_allowed' else 'maintain_only' end
  );
end $$;

-- 4. The baseline ---------------------------------------------------------------------------------

-- The active plan (every session by weekday with its exercises), the sessions finished this ISO
-- week and the next-session targets with the last logged top set (get_progression_summary_v1).
-- Which session is today's or next is decided in TypeScript from these, with the coaching date.
create function public.get_coach_plan_state_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with active as (
    select v.id as version_id, v.version_number, v.sessions_per_week, p.title
    from public.training_plan_versions v
    join public.training_plans p on p.id = v.plan_id and p.user_id = v.user_id
    where v.user_id = p_user_id and v.status = 'active' limit 1
  )
  select jsonb_build_object(
    'schema_version', '1.0',
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
    'progression', public.get_progression_summary_v1(p_user_id));
$$;

-- The last 7 days of nutrition with complete-day flags, the active target, the meal schedule
-- with what is already logged today, what was eaten today and where the last 14 days of meals
-- came from (photo estimate, schedule, typed in).
create function public.get_coach_nutrition_state_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'local_date', p_local_date,
    'target', (select jsonb_build_object('calories', s.calories, 'protein_g', s.protein_g,
        'carbohydrate_g', s.carbohydrate_g, 'fat_g', s.fat_g)
      from public.nutrition_target_sets s where s.user_id = p_user_id and s.status = 'active'
      limit 1),
    'rules', private.nutrition_complete_day_rules(),
    'days', coalesce((select jsonb_agg(jsonb_build_object('local_date', t.local_date,
        'meals', t.meals, 'calories', round(t.calories), 'protein_g', round(t.protein_g),
        'carbohydrate_g', round(t.carbohydrate_g), 'fat_g', round(t.fat_g),
        'complete', t.complete) order by t.local_date desc)
      from private.nutrition_day_totals(p_user_id, p_local_date - 6, p_local_date) t),
      '[]'::jsonb),
    'schedule', coalesce((select jsonb_agg(jsonb_build_object('label', i.label,
        'local_time', to_char(i.local_time, 'HH24:MI'), 'optional', i.optional, 'foods', i.foods,
        'logged', exists (select 1 from public.meals m
          where m.user_id = p_user_id and m.local_date = p_local_date and m.status = 'confirmed'
            and m.nutrition_schedule_item_id = i.id)) order by i.item_order)
      from public.nutrition_schedule_items i
      join public.nutrition_schedule_versions v on v.id = i.schedule_version_id
        and v.user_id = i.user_id
      where i.user_id = p_user_id and v.status = 'active'), '[]'::jsonb),
    'eaten_today', coalesce((select jsonb_agg(jsonb_build_object('meal_type', m.meal_type,
        'source', m.source, 'from_schedule', m.nutrition_schedule_item_id is not null,
        'foods', (select coalesce(jsonb_agg(jsonb_build_object('name', mi.name_snapshot,
            'serving', mi.serving_label, 'calories', round(mi.calories),
            'protein_g', round(mi.protein_g))), '[]'::jsonb)
          from public.meal_items mi where mi.meal_id = m.id and mi.user_id = m.user_id))
        order by m.created_at)
      from public.meals m
      where m.user_id = p_user_id and m.status = 'confirmed' and m.local_date = p_local_date),
      '[]'::jsonb),
    'sources', (select jsonb_build_object('window_days', 14, 'meals', count(*),
        'photo_estimate', count(*) filter (where m.source = 'photo_analysis'),
        'from_schedule', count(*) filter (where m.source <> 'photo_analysis'
          and m.nutrition_schedule_item_id is not null),
        'typed_in', count(*) filter (where m.source <> 'photo_analysis'
          and m.nutrition_schedule_item_id is null))
      from public.meals m
      where m.user_id = p_user_id and m.status = 'confirmed'
        and m.local_date between p_local_date - 13 and p_local_date));
$$;

-- What data exists, by kind, with its first and last date and a count: the index Coach reads to
-- know what it can look up.
create function public.get_coach_data_index_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
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
          'count', count(*)) from public.health_history_months hm where hm.user_id = p_user_id)));
$$;

-- 5. Lookups -------------------------------------------------------------------------------------

-- Every lookup takes (p_user_id, p_from, p_to, p_filter) and returns
-- {schema_version, lookup, from, to, ...arrays, truncated}. The range is cut to 400 days ending
-- on p_to; arrays are capped, newest first unless said otherwise. A filter is matched as plain
-- text (position), never as a pattern.

-- Sessions in the range with every exercise and set: planned against logged, load, reps, reps in
-- reserve and effort, and the set's heart-rate summary when the watch recorded one. A filter
-- keeps the sessions (and exercises) whose exercise matches it. At most 15 sessions.
create function public.coach_lookup_workouts_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with matched as (
    select s.id, s.local_date, s.completed_at, w.name, s.duration_seconds, s.session_effort,
      s.session_energy
    from public.workout_sessions s
    join public.planned_workouts w on w.id = s.planned_workout_id and w.user_id = s.user_id
    where s.user_id = p_user_id and s.state = 'completed'
      and s.local_date between greatest(p_from, p_to - 399) and p_to
      and (p_filter is null or exists (
        select 1 from public.exercise_performances p
        left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
        where p.workout_session_id = s.id and p.user_id = s.user_id
          and (p.exercise_slug = lower(p_filter)
            or position(lower(p_filter) in lower(coalesce(p.performed_name, pe.display_name_snapshot))) > 0)))
    order by s.local_date desc, s.completed_at desc
    limit 16
  ), shown as (
    select m.*, row_number() over (order by m.local_date desc, m.completed_at desc) as rn
    from matched m
  )
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'workouts', 'from', greatest(p_from, p_to - 399),
    'to', p_to,
    'truncated', (select count(*) > 15 from matched),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
        'local_date', x.local_date, 'workout', x.name,
        'minutes', round(x.duration_seconds / 60.0), 'effort', x.session_effort,
        'energy', x.session_energy,
        'exercises', (select coalesce(jsonb_agg(jsonb_build_object(
            'name', coalesce(p.performed_name, pe.display_name_snapshot),
            'status', p.status, 'pain', p.pain_flag,
            'planned', jsonb_build_object('sets', pe.set_count, 'rep_min', pe.rep_min,
              'rep_max', pe.rep_max),
            'sets', (select coalesce(jsonb_agg(jsonb_build_object('reps', es.repetitions,
                'load_kg', es.load_kg, 'rir', es.rir, 'rpe', es.rpe, 'done', es.completed,
                'peak_bpm', hr.peak_bpm, 'drop_60s_bpm', hr.drop_60s_bpm)
                order by es.set_number), '[]'::jsonb)
              from public.exercise_sets es
              left join public.exercise_set_heart_rate hr on hr.exercise_set_id = es.id
                and hr.user_id = es.user_id
              where es.exercise_performance_id = p.id and es.user_id = p.user_id)
          ) order by p.exercise_order), '[]'::jsonb)
          from public.exercise_performances p
          left join public.planned_exercises pe on pe.id = p.planned_exercise_id
            and pe.user_id = p.user_id
          where p.workout_session_id = x.id and p.user_id = p_user_id
            and (p_filter is null or p.exercise_slug = lower(p_filter)
              or position(lower(p_filter) in lower(coalesce(p.performed_name, pe.display_name_snapshot))) > 0))
      ) order by x.local_date desc) from shown x where x.rn <= 15), '[]'::jsonb));
$$;

-- One exercise across the range, a row per session (oldest first, newest 40): the heaviest
-- completed set with its reps, the estimated one-rep max (Epley, sets of 1 to 12 reps), the
-- sets done and the fewest reps in reserve; plus the plan's prescription and next target.
-- An assisted exercise (an assisted-* slug or an "assisted ..." name, as B3 detects it) logs
-- machine help as its load: its top set is the LEAST help (0 is unassisted), it has no one-rep
-- max, and the row says assisted so the load is read as help.
-- The filter is required: an exercise slug or part of its name.
create function public.coach_lookup_exercise_history_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if p_filter is null or btrim(p_filter) = '' then
    raise exception 'exercise filter required' using errcode = '22023';
  end if;
  with perf as (
    select p.id as perf_id, s.local_date, coalesce(p.performed_name, pe.display_name_snapshot) as name,
      p.exercise_slug,
      coalesce(p.exercise_slug like 'assisted-%',
        private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
          like 'assisted %') as assisted
    from public.workout_sessions s
    join public.exercise_performances p on p.workout_session_id = s.id and p.user_id = s.user_id
    left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
    where s.user_id = p_user_id and s.state = 'completed' and p.status <> 'skipped'
      and s.local_date between greatest(p_from, p_to - 399) and p_to
      and (p.exercise_slug = lower(p_filter)
        or position(lower(p_filter) in lower(coalesce(p.performed_name, pe.display_name_snapshot))) > 0)
  ), done as (
    select pf.perf_id, pf.assisted, es.load_kg, es.repetitions, es.rir
    from perf pf join public.exercise_sets es on es.exercise_performance_id = pf.perf_id
      and es.user_id = p_user_id
    where es.completed and es.repetitions > 0
  ), top as (
    select distinct on (d.perf_id) d.perf_id, d.load_kg, d.repetitions
    from done d order by d.perf_id,
      case when d.assisted then d.load_kg else -d.load_kg end nulls last, d.repetitions desc
  ), rows_all as (
    select pf.local_date, pf.name, pf.assisted, t.load_kg as top_load_kg, t.repetitions as top_reps,
      (select count(*) from done d where d.perf_id = pf.perf_id) as sets,
      (select max(round(d.load_kg * (1 + d.repetitions / 30.0), 1)) from done d
        where d.perf_id = pf.perf_id and not pf.assisted and d.load_kg > 0
          and d.repetitions between 1 and 12) as e1rm_kg,
      (select min(d.rir) from done d where d.perf_id = pf.perf_id) as min_rir
    from perf pf join top t on t.perf_id = pf.perf_id
  ), newest as (select * from rows_all order by local_date desc limit 41)
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'exercise_history',
    'from', greatest(p_from, p_to - 399), 'to', p_to,
    'truncated', (select count(*) > 40 from newest),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object('local_date', n.local_date,
        'name', n.name, 'assisted', n.assisted, 'top_load_kg', n.top_load_kg, 'top_reps', n.top_reps, 'sets', n.sets,
        'e1rm_kg', n.e1rm_kg, 'min_rir', n.min_rir) order by n.local_date)
      from (select * from newest order by local_date desc limit 40) n), '[]'::jsonb),
    'planned', coalesce((select jsonb_agg(jsonb_build_object('name', e.display_name_snapshot,
        'sets', e.set_count, 'rep_min', e.rep_min, 'rep_max', e.rep_max,
        'rest_seconds', e.rest_seconds))
      from public.training_plan_versions v
      join public.planned_workouts w on w.plan_version_id = v.id and w.user_id = v.user_id
      join public.planned_exercises e on e.planned_workout_id = w.id and e.user_id = w.user_id
      where v.user_id = p_user_id and v.status = 'active'
        and (e.exercise_slug = lower(p_filter)
          or position(lower(p_filter) in lower(e.display_name_snapshot)) > 0)), '[]'::jsonb),
    'next_targets', coalesce((select jsonb_agg(t) from jsonb_array_elements(
        private.next_session_targets(p_user_id)) t
      where t ->> 'exercise_key' = lower(p_filter)
        or position(lower(p_filter) in lower(t ->> 'name')) > 0), '[]'::jsonb))
  into result;
  return result;
end $$;

-- Nutrition by day (newest 60 days) with complete or partial, and the meals with their foods
-- (newest 30). A filter keeps the meals whose type or food matches.
create function public.coach_lookup_meals_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with days as (
    select * from private.nutrition_day_totals(p_user_id, greatest(p_from, p_to - 399), p_to)
    order by local_date desc limit 61
  ), mealrows as (
    select m.local_date, m.created_at, m.meal_type, m.source, m.nutrition_schedule_item_id,
      (select coalesce(jsonb_agg(jsonb_build_object('name', mi.name_snapshot,
          'serving', mi.serving_label, 'calories', round(mi.calories),
          'protein_g', round(mi.protein_g))), '[]'::jsonb)
        from public.meal_items mi where mi.meal_id = m.id and mi.user_id = m.user_id) as foods
    from public.meals m
    where m.user_id = p_user_id and m.status = 'confirmed'
      and m.local_date between greatest(p_from, p_to - 399) and p_to
      and (p_filter is null or m.meal_type = lower(p_filter) or exists (
        select 1 from public.meal_items mi where mi.meal_id = m.id and mi.user_id = m.user_id
          and position(lower(p_filter) in lower(mi.name_snapshot)) > 0))
    order by m.local_date desc, m.created_at desc limit 31
  )
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'meals', 'from', greatest(p_from, p_to - 399),
    'to', p_to,
    'truncated', (select count(*) > 60 from days) or (select count(*) > 30 from mealrows),
    'target_kcal', (select s.calories from public.nutrition_target_sets s
      where s.user_id = p_user_id and s.status = 'active' limit 1),
    'rules', private.nutrition_complete_day_rules(),
    'days', coalesce((select jsonb_agg(jsonb_build_object('local_date', d.local_date,
        'meals', d.meals, 'calories', round(d.calories), 'protein_g', round(d.protein_g),
        'carbohydrate_g', round(d.carbohydrate_g), 'fat_g', round(d.fat_g),
        'complete', d.complete) order by d.local_date desc)
      from (select * from days order by local_date desc limit 60) d), '[]'::jsonb),
    'meals', coalesce((select jsonb_agg(jsonb_build_object('local_date', r.local_date,
        'meal_type', r.meal_type, 'source', r.source,
        'from_schedule', r.nutrition_schedule_item_id is not null, 'foods', r.foods)
        order by r.local_date desc, r.created_at desc)
      from (select * from mealrows order by local_date desc, created_at desc limit 30) r),
      '[]'::jsonb));
$$;

-- Weight readings (newest 90; a manual or watch reading, an amended one replaced by its
-- amendment) and the tape measurements (newest 30). The filter is not used.
create function public.coach_lookup_body_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with weights as (
    select bm.measured_on, bm.created_at, bm.weight_kg, bm.source
    from public.body_measurements bm
    where bm.user_id = p_user_id and bm.weight_kg is not null
      and bm.measured_on between greatest(p_from, p_to - 399) and p_to
      and not exists (select 1 from public.body_measurements newer
        where newer.user_id = bm.user_id and newer.amended_from_id = bm.id)
    union all
    select dhs.local_date, dhs.last_synced_at, dhs.weight_kg, 'healthkit'
    from public.daily_health_summaries dhs
    where dhs.user_id = p_user_id and dhs.weight_kg is not null
      and dhs.local_date between greatest(p_from, p_to - 399) and p_to
      and not exists (select 1 from public.body_measurements m
        where m.user_id = dhs.user_id and m.measured_on = dhs.local_date
          and m.weight_kg is not null
          and not exists (select 1 from public.body_measurements newer
            where newer.user_id = m.user_id and newer.amended_from_id = m.id))
  ), tape as (
    select bm.measured_on, bm.waist_cm, bm.chest_cm, bm.hip_cm, bm.arm_cm, bm.thigh_cm
    from public.body_measurements bm
    where bm.user_id = p_user_id
      and (bm.waist_cm is not null or bm.chest_cm is not null or bm.hip_cm is not null
        or bm.arm_cm is not null or bm.thigh_cm is not null)
      and bm.measured_on between greatest(p_from, p_to - 399) and p_to
      and not exists (select 1 from public.body_measurements newer
        where newer.user_id = bm.user_id and newer.amended_from_id = bm.id)
  )
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'body', 'from', greatest(p_from, p_to - 399),
    'to', p_to,
    'truncated', (select count(*) > 90 from weights) or (select count(*) > 30 from tape),
    'weights', coalesce((select jsonb_agg(jsonb_build_object('date', w.measured_on,
        'kg', w.weight_kg, 'source', w.source) order by w.measured_on desc, w.created_at desc)
      from (select * from weights order by measured_on desc, created_at desc limit 90) w),
      '[]'::jsonb),
    'measurements', coalesce((select jsonb_agg(jsonb_build_object('date', t.measured_on,
        'waist_cm', t.waist_cm, 'chest_cm', t.chest_cm, 'hip_cm', t.hip_cm, 'arm_cm', t.arm_cm,
        'thigh_cm', t.thigh_cm) order by t.measured_on desc)
      from (select * from tape order by measured_on desc limit 30) t), '[]'::jsonb));
$$;

-- Daily check-ins with the athlete's own note (untrusted text, cut to 300 characters), newest 60.
create function public.coach_lookup_check_ins_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with rows_all as (
    select c.local_date, c.sleep_quality, c.energy, c.soreness, c.hunger, c.mood,
      c.pain_severity, c.available_to_train, left(c.note, 300) as note
    from public.daily_check_ins c
    where c.user_id = p_user_id and c.superseded_at is null
      and c.local_date between greatest(p_from, p_to - 399) and p_to
    order by c.local_date desc limit 61
  )
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'check_ins', 'from', greatest(p_from, p_to - 399),
    'to', p_to, 'truncated', (select count(*) > 60 from rows_all),
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('local_date', r.local_date,
        'sleep_quality', r.sleep_quality, 'energy', r.energy, 'soreness', r.soreness,
        'hunger', r.hunger, 'mood', r.mood, 'pain_severity', r.pain_severity,
        'available_to_train', r.available_to_train, 'note', r.note)
        order by r.local_date desc)
      from (select * from rows_all order by local_date desc limit 60) r), '[]'::jsonb));
$$;

-- Watch and recovery data by day, newest 60: sleep minutes, resting heart rate, HRV, steps and
-- the computed recovery score, sleep quality and training load ratio.
create function public.coach_lookup_recovery_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with rows_all as (
    select h.local_date, h.sleep_minutes, h.resting_heart_rate_bpm, h.hrv_value_ms, h.steps,
      m.recovery_score, m.sleep_quality_score, m.acwr
    from public.daily_health_summaries h
    left join lateral (
      select dcm.recovery_score, dcm.sleep_quality_score, dcm.acwr
      from public.daily_computed_metrics dcm
      where dcm.user_id = h.user_id and dcm.local_date = h.local_date
      order by dcm.computed_at desc limit 1) m on true
    where h.user_id = p_user_id
      and h.local_date between greatest(p_from, p_to - 399) and p_to
    order by h.local_date desc limit 61
  )
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'recovery', 'from', greatest(p_from, p_to - 399),
    'to', p_to, 'truncated', (select count(*) > 60 from rows_all),
    'days', coalesce((select jsonb_agg(jsonb_build_object('local_date', r.local_date,
        'sleep_minutes', r.sleep_minutes, 'resting_heart_rate_bpm', r.resting_heart_rate_bpm,
        'hrv_ms', r.hrv_value_ms, 'steps', r.steps, 'recovery_score', r.recovery_score,
        'sleep_quality', r.sleep_quality_score, 'acwr', r.acwr) order by r.local_date desc)
      from (select * from rows_all order by local_date desc limit 60) r), '[]'::jsonb));
$$;

-- Training plan versions created in the range (or the active one), newest 6, with their
-- sessions and exercises, and the nutrition target versions (newest 12) with their rationale.
create function public.coach_lookup_plan_history_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
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
    'schema_version', '1.0', 'lookup', 'plan_history', 'from', greatest(p_from, p_to - 399),
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
      from (select * from targets order by created_at desc limit 12) t), '[]'::jsonb));
$$;

-- Goals (any status) created in the range or active, with their target, and the health-check
-- (screening) outcomes in the range. Newest 10 each.
create function public.coach_lookup_goals_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with goal_rows as (
    select x.* from public.user_goals x where x.user_id = p_user_id
      and (x.status = 'active'
        or private.local_day(p_user_id, x.created_at) between greatest(p_from, p_to - 399) and p_to)
    order by x.created_at desc limit 11
  ), screening_rows as (
    select x.* from public.onboarding_screenings x where x.user_id = p_user_id
      and private.local_day(p_user_id, x.screened_at) between greatest(p_from, p_to - 399) and p_to
    order by x.screened_at desc limit 11
  )
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'goals', 'from', greatest(p_from, p_to - 399),
    'to', p_to,
    'truncated', (select count(*) > 10 from goal_rows) or (select count(*) > 10 from screening_rows),
    'goals', coalesce((select jsonb_agg(jsonb_build_object('goal_type', g.goal_type,
        'status', g.status, 'priority', g.priority, 'created_on', private.local_day(p_user_id, g.created_at),
        'activated_on', private.local_day(p_user_id, g.activated_at), 'target', private.goal_target_json(g.details))
        order by g.created_at desc)
      from (select * from goal_rows order by created_at desc limit 10) g), '[]'::jsonb),
    'screenings', coalesce((select jsonb_agg(jsonb_build_object('outcome', s.outcome,
        'screened_on', private.local_day(p_user_id, s.screened_at)) order by s.screened_at desc)
      from (select * from screening_rows order by screened_at desc limit 10) s), '[]'::jsonb));
$$;

-- Weekly reviews for the weeks starting in the range, newest 12.
create function public.coach_lookup_weekly_reviews_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with rows_all as (
    select r.review_week, r.summary from public.progress_reviews r
    where r.user_id = p_user_id
      and r.review_week between greatest(p_from, p_to - 399) and p_to
    order by r.review_week desc limit 13
  )
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'weekly_reviews', 'from', greatest(p_from, p_to - 399),
    'to', p_to, 'truncated', (select count(*) > 12 from rows_all),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('review_week', r.review_week,
        'outcome_code', r.summary ->> 'outcome_code',
        'next_focus_code', r.summary ->> 'next_focus_code',
        'training', r.summary -> 'training', 'recovery', r.summary -> 'recovery',
        'nutrition', r.summary -> 'nutrition', 'progress', r.summary -> 'progress',
        'missing_data', r.summary -> 'missing_data') order by r.review_week desc)
      from (select * from rows_all order by review_week desc limit 12) r), '[]'::jsonb));
$$;

-- The monthly Apple Health summary imported at onboarding (workouts, sleep, weight), for the
-- months in the range, newest 12.
create function public.coach_lookup_health_history_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with rows_all as (
    select hm.* from public.health_history_months hm
    where hm.user_id = p_user_id
      and hm.month between date_trunc('month', greatest(p_from, p_to - 399))::date and p_to
    order by hm.month desc limit 13
  )
  select jsonb_build_object(
    'schema_version', '1.0', 'lookup', 'health_history', 'from', greatest(p_from, p_to - 399),
    'to', p_to, 'truncated', (select count(*) > 12 from rows_all),
    'months', coalesce((select jsonb_agg(jsonb_build_object('month', r.month,
        'workouts', r.workouts, 'strength_workouts', r.strength_workouts,
        'workout_minutes', r.workout_minutes, 'sleep_nights', r.sleep_nights,
        'sleep_minutes_avg', r.sleep_minutes_avg, 'weight_days', r.weight_days,
        'weight_kg_avg', r.weight_kg_avg) order by r.month desc)
      from (select * from rows_all order by month desc limit 12) r), '[]'::jsonb));
$$;

-- Only the service role calls any of these.
do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'coach\_lookup\_%\_v1'
        or p.proname in ('get_coach_plan_state_v1', 'get_coach_nutrition_state_v1',
          'get_coach_data_index_v1'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
