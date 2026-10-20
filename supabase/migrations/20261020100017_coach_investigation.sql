-- Coach investigates first: the records it could not reach, and the facts it should not have to
-- derive. Additive only: every change adds keys or a new function, and bumps schema_version; no
-- key, column or function is removed or renamed, so the deployed app and Edge Functions keep
-- working until the new Edge Functions read the new keys.
--
-- 1. get_coach_data_index_v1       1.1 -> 1.2  + watch_workouts, proposals, daily_decisions and
--                                              past_messages domains (first, last, count)
-- 2. coach_lookup_workouts_v1      1.0 -> 1.1  + session notes, exercise notes, substitutions
-- 3. coach_lookup_recovery_v1      1.0 -> 1.1  + breathing rate, sleep stages, night and morning HRV,
--                                              active energy, workout minutes
-- 4. coach_lookup_plan_history_v1  1.1 -> 1.2  + filter "proposals": the Coach proposals and how
--                                              they were answered (private.coach_lookup_proposals)
-- 5. coach_lookup_health_history_v1 1.0 -> 1.1 + filter "workouts": the individual watch workouts
-- 6. coach_lookup_weekly_reviews_v1 1.0 -> 1.1 + filter "decisions": the past daily decisions
-- 7. coach_lookup_past_messages_v1 1.0 -> 1.1  + coach_replies: Coach's own earlier replies that
--                                              match the words, labelled in the renderer as unverified
-- 8. get_coach_watch_outs_v1       new         the facts the watch-outs are computed from
--
-- Every public function is SECURITY DEFINER, read-only and granted to service_role only. The
-- private helper is not SECURITY DEFINER (like the other private helpers) and is revoked from
-- anon and authenticated.

-- 1 ----------------------------------------------------------------------------------------------

create or replace function public.get_coach_data_index_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.2',
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
          'count', count(*)) from public.health_history_months hm where hm.user_id = p_user_id),
      -- Workouts the watch recorded (health_history with the filter "workouts").
      'watch_workouts', (select jsonb_build_object('first', min(h.local_date), 'last', max(h.local_date),
          'count', count(*)) from public.health_workout_references h where h.user_id = p_user_id),
      -- Coach proposals (plan_history with the filter "proposals").
      'proposals', (select jsonb_build_object('first', min(private.local_day(p_user_id, c.created_at)),
          'last', max(private.local_day(p_user_id, c.created_at)), 'count', count(*))
        from public.change_proposals c where c.user_id = p_user_id and c.schema_version = '3.0'),
      -- The daily coaching decisions (weekly_reviews with the filter "decisions").
      'daily_decisions', (select jsonb_build_object('first', min(d.local_date), 'last', max(d.local_date),
          'count', count(*)) from public.coach_decisions d where d.user_id = p_user_id),
      -- The athlete's own questions in conversations Coach may remember (past_messages).
      'past_messages', (select jsonb_build_object('first', min(private.local_day(p_user_id, m.created_at)),
          'last', max(private.local_day(p_user_id, m.created_at)), 'count', count(*))
        from public.coach_messages m
        join public.coach_threads t on t.id = m.thread_id and t.user_id = m.user_id
        where m.user_id = p_user_id and m.role = 'user' and t.remember
          and m.safety_state <> 'unavailable')),
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

-- 2 ----------------------------------------------------------------------------------------------

-- Sessions in the range with every exercise and set: planned against logged, load, reps, reps in
-- reserve and effort, the set's heart-rate summary when the watch recorded one, and now the
-- athlete's own notes: the session note, each exercise's note and the reason for a substitution
-- (untrusted text, cut). A filter keeps the sessions (and exercises) whose exercise matches it.
-- At most 15 sessions.
create or replace function public.coach_lookup_workouts_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with matched as (
    select s.id, s.local_date, s.completed_at, w.name, s.duration_seconds, s.session_effort,
      s.session_energy, s.notes
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
    'schema_version', '1.1', 'lookup', 'workouts', 'from', greatest(p_from, p_to - 399),
    'to', p_to,
    'truncated', (select count(*) > 15 from matched),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
        'local_date', x.local_date, 'workout', x.name,
        'minutes', round(x.duration_seconds / 60.0), 'effort', x.session_effort,
        'energy', x.session_energy,
        'note', nullif(left(x.notes, 300), ''),
        'exercises', (select coalesce(jsonb_agg(jsonb_build_object(
            'name', coalesce(p.performed_name, pe.display_name_snapshot),
            'status', p.status, 'pain', p.pain_flag,
            'kind', p.performance_kind,
            'planned_name', pe.display_name_snapshot,
            'substitution_reason', nullif(left(p.substitution_reason, 200), ''),
            'note', nullif(left(p.note, 200), ''),
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

-- 3 ----------------------------------------------------------------------------------------------

-- Watch and recovery data by day, newest 60: sleep minutes, resting heart rate, HRV, steps and the
-- computed recovery score, sleep quality and training load ratio, and now the rest of what the
-- watch stores: breathing rate, sleep stages, night and morning HRV, active energy and workout
-- minutes. A value the watch did not measure is null, never zero.
create or replace function public.coach_lookup_recovery_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with rows_all as (
    select h.local_date, h.sleep_minutes, h.resting_heart_rate_bpm, h.hrv_value_ms, h.steps,
      h.respiratory_rate_bpm, h.sleep_awake_minutes, h.sleep_light_minutes, h.sleep_deep_minutes,
      h.sleep_rem_minutes, h.hrv_sleep_ms, h.hrv_morning_ms, h.active_energy_kcal,
      h.workout_minutes, m.recovery_score, m.sleep_quality_score, m.acwr
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
    'schema_version', '1.1', 'lookup', 'recovery', 'from', greatest(p_from, p_to - 399),
    'to', p_to, 'truncated', (select count(*) > 60 from rows_all),
    'days', coalesce((select jsonb_agg(jsonb_build_object('local_date', r.local_date,
        'sleep_minutes', r.sleep_minutes, 'resting_heart_rate_bpm', r.resting_heart_rate_bpm,
        'hrv_ms', r.hrv_value_ms, 'steps', r.steps, 'recovery_score', r.recovery_score,
        'sleep_quality', r.sleep_quality_score, 'acwr', r.acwr,
        'respiratory_rate_bpm', r.respiratory_rate_bpm,
        'sleep_awake_minutes', r.sleep_awake_minutes, 'sleep_light_minutes', r.sleep_light_minutes,
        'sleep_deep_minutes', r.sleep_deep_minutes, 'sleep_rem_minutes', r.sleep_rem_minutes,
        'hrv_sleep_ms', r.hrv_sleep_ms, 'hrv_morning_ms', r.hrv_morning_ms,
        'active_energy_kcal', r.active_energy_kcal, 'workout_minutes', r.workout_minutes)
        order by r.local_date desc)
      from (select * from rows_all order by local_date desc limit 60) r), '[]'::jsonb));
$$;

-- 4 ----------------------------------------------------------------------------------------------

-- The Coach proposals created in the range, newest 12, with how each stands (pending, accepted,
-- declined, changed, expired or undone), why it was made and what the athlete would gain and give
-- up. The athlete's answers are the status; a proposal's text is Tracend's own, not the athlete's.
create function private.coach_lookup_proposals(p_user_id uuid, p_from date, p_to date)
returns jsonb language sql stable set search_path = '' as $$
  with rows_all as (
    select c.created_at, c.proposal_kind, c.proposed_training, c.confidence, c.rationale,
      c.expected_benefit, c.downside, c.ends_on, c.applied_at,
      private.coach_proposal_json(c) ->> 'status' as state
    from public.change_proposals c
    where c.user_id = p_user_id and c.schema_version = '3.0'
      and private.local_day(p_user_id, c.created_at) between greatest(p_from, p_to - 399) and p_to
    order by c.created_at desc limit 13
  )
  select jsonb_build_object(
    'schema_version', '1.2', 'lookup', 'plan_history', 'filter', 'proposals',
    'from', greatest(p_from, p_to - 399), 'to', p_to,
    'truncated', (select count(*) > 12 from rows_all),
    'proposals', coalesce((select jsonb_agg(jsonb_build_object(
        'created_on', private.local_day(p_user_id, r.created_at),
        'kind', r.proposal_kind,
        'title', r.proposed_training ->> 'title',
        'status', r.state,
        'confidence', r.confidence,
        'rationale', left(r.rationale, 300),
        'benefit', left(r.expected_benefit, 200),
        'downside', left(r.downside, 200),
        'ends_on', r.ends_on,
        'applied_on', case when r.applied_at is null then null
          else private.local_day(p_user_id, r.applied_at) end)
        order by r.created_at desc)
      from (select * from rows_all order by created_at desc limit 12) r), '[]'::jsonb));
$$;
revoke all on function private.coach_lookup_proposals(uuid, date, date)
  from public, anon, authenticated;

create or replace function public.coach_lookup_plan_history_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  -- The filter "schedule" asks for the day-by-day schedule of the range instead of the versions;
  -- the filter "proposals" for the Coach proposals and how they were answered.
  if lower(btrim(coalesce(p_filter, ''))) = 'schedule' then
    return private.coach_plan_schedule(p_user_id, p_from, p_to);
  end if;
  if lower(btrim(coalesce(p_filter, ''))) = 'proposals' then
    return private.coach_lookup_proposals(p_user_id, p_from, p_to);
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
      'schema_version', '1.2', 'lookup', 'plan_history', 'from', greatest(p_from, p_to - 399),
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

-- 5 ----------------------------------------------------------------------------------------------

-- The monthly Apple Health summary imported at onboarding (workouts, sleep, weight), for the
-- months in the range, newest 12. With the filter "workouts", instead, the individual workouts the
-- watch recorded in the range, newest 40, each with how it was reconciled with a logged session.
create or replace function public.coach_lookup_health_history_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if lower(btrim(coalesce(p_filter, ''))) = 'workouts' then
    return (
      with rows_all as (
        select h.id, h.local_date, h.activity_type, h.duration_seconds, h.energy_kcal, h.started_at
        from public.health_workout_references h
        where h.user_id = p_user_id
          and h.local_date between greatest(p_from, p_to - 399) and p_to
        order by h.started_at desc limit 41
      )
      select jsonb_build_object(
        'schema_version', '1.1', 'lookup', 'health_history', 'filter', 'workouts',
        'from', greatest(p_from, p_to - 399), 'to', p_to,
        'truncated', (select count(*) > 40 from rows_all),
        'workouts', coalesce((select jsonb_agg(jsonb_build_object('local_date', r.local_date,
            'activity_type', r.activity_type, 'minutes', round(r.duration_seconds / 60.0),
            'energy_kcal', round(r.energy_kcal),
            'reconciliation', (select x.status from public.workout_reconciliations x
              where x.health_workout_reference_id = r.id and x.user_id = p_user_id
              order by x.confidence desc limit 1))
            order by r.started_at desc)
          from (select * from rows_all order by started_at desc limit 40) r), '[]'::jsonb));
  end if;
  return (
    with rows_all as (
      select hm.* from public.health_history_months hm
      where hm.user_id = p_user_id
        and hm.month between date_trunc('month', greatest(p_from, p_to - 399))::date and p_to
      order by hm.month desc limit 13
    )
    select jsonb_build_object(
      'schema_version', '1.1', 'lookup', 'health_history', 'from', greatest(p_from, p_to - 399),
      'to', p_to, 'truncated', (select count(*) > 12 from rows_all),
      'months', coalesce((select jsonb_agg(jsonb_build_object('month', r.month,
          'workouts', r.workouts, 'strength_workouts', r.strength_workouts,
          'workout_minutes', r.workout_minutes, 'sleep_nights', r.sleep_nights,
          'sleep_minutes_avg', r.sleep_minutes_avg, 'weight_days', r.weight_days,
          'weight_kg_avg', r.weight_kg_avg) order by r.month desc)
        from (select * from rows_all order by month desc limit 12) r), '[]'::jsonb)));
end $$;

-- 6 ----------------------------------------------------------------------------------------------

-- Weekly reviews for the weeks starting in the range, newest 12. With the filter "decisions",
-- instead, the daily coaching decisions made on the days in the range, newest 30: what Tracend
-- told the athlete to do with the day's training and nutrition, and why (Tracend's own text).
create or replace function public.coach_lookup_weekly_reviews_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if lower(btrim(coalesce(p_filter, ''))) = 'decisions' then
    return (
      with rows_all as (
        select d.* from public.coach_decisions d
        where d.user_id = p_user_id
          and d.local_date between greatest(p_from, p_to - 399) and p_to
        order by d.local_date desc, d.created_at desc limit 31
      )
      select jsonb_build_object(
        'schema_version', '1.1', 'lookup', 'weekly_reviews', 'filter', 'decisions',
        'from', greatest(p_from, p_to - 399), 'to', p_to,
        'truncated', (select count(*) > 30 from rows_all),
        'decisions', coalesce((select jsonb_agg(jsonb_build_object('local_date', r.local_date,
            'training_action', r.training ->> 'action',
            'training_summary', left(r.training ->> 'summary', 200),
            'nutrition_action', r.nutrition ->> 'action',
            'decision', left(r.head_coach ->> 'final_decision', 200),
            'confidence', r.confidence, 'risk_flags', to_jsonb(r.risk_flags))
            order by r.local_date desc, r.created_at desc)
          from (select * from rows_all order by local_date desc, created_at desc limit 30) r),
          '[]'::jsonb));
  end if;
  return (
    with rows_all as (
      select r.review_week, r.summary from public.progress_reviews r
      where r.user_id = p_user_id
        and r.review_week between greatest(p_from, p_to - 399) and p_to
      order by r.review_week desc limit 13
    )
    select jsonb_build_object(
      'schema_version', '1.1', 'lookup', 'weekly_reviews', 'from', greatest(p_from, p_to - 399),
      'to', p_to, 'truncated', (select count(*) > 12 from rows_all),
      'reviews', coalesce((select jsonb_agg(jsonb_build_object('review_week', r.review_week,
          'outcome_code', r.summary ->> 'outcome_code',
          'next_focus_code', r.summary ->> 'next_focus_code',
          'training', r.summary -> 'training', 'recovery', r.summary -> 'recovery',
          'nutrition', r.summary -> 'nutrition', 'progress', r.summary -> 'progress',
          'missing_data', r.summary -> 'missing_data') order by r.review_week desc)
        from (select * from rows_all order by review_week desc limit 12) r), '[]'::jsonb)));
end $$;

-- 7 ----------------------------------------------------------------------------------------------

-- The athlete's own questions in conversations that are remembered, matching any of the words in
-- the filter (12 at most, 300 characters each), as before. New: coach_replies, at most 4 of
-- Coach's own earlier replies in the same conversations that match the same words, 300 characters
-- each, so Coach can re-read what it advised. They are Coach's words, not records: the renderer
-- labels them unverified and the instructions tell Coach to check a claim in them against the
-- records. A reply that was a labelled data summary, or that failed, is never returned.
create or replace function public.coach_lookup_past_messages_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  lo date := greatest(p_from, p_to - 399);
  search_query tsquery;
begin
  if p_filter is null or btrim(p_filter) = '' then
    raise exception 'a search phrase is required' using errcode = '22023';
  end if;
  search_query := replace(plainto_tsquery('english', p_filter)::text, ' & ', ' | ')::tsquery;
  return (
    with rows_all as (
      select m.id, private.local_day(p_user_id, m.created_at) as local_date, m.content,
        ts_rank(m.search_vector, search_query) as rank
      from public.coach_messages m
      join public.coach_threads t on t.id = m.thread_id and t.user_id = m.user_id
      where m.user_id = p_user_id and m.role = 'user' and t.remember
        and m.safety_state <> 'unavailable'
        and private.local_day(p_user_id, m.created_at) between lo and p_to
        and m.search_vector @@ search_query
      order by rank desc, m.created_at desc
      limit 13
    ), replies as (
      select m.id, private.local_day(p_user_id, m.created_at) as local_date, m.content,
        ts_rank(m.search_vector, search_query) as rank
      from public.coach_messages m
      join public.coach_threads t on t.id = m.thread_id and t.user_id = m.user_id
      where m.user_id = p_user_id and m.role = 'assistant' and t.remember
        and m.safety_state in ('allowed', 'limited')
        and m.answer_source is distinct from 'data_summary'
        and private.local_day(p_user_id, m.created_at) between lo and p_to
        and m.search_vector @@ search_query
      order by rank desc, m.created_at desc
      limit 4
    )
    select jsonb_build_object(
      'schema_version', '1.1', 'lookup', 'past_messages', 'from', lo, 'to', p_to,
      'truncated', (select count(*) > 12 from rows_all),
      'messages', coalesce((select jsonb_agg(jsonb_build_object(
          'message_id', r.id, 'local_date', r.local_date, 'content', left(r.content, 300))
          order by r.rank desc, r.local_date desc)
        from (select * from rows_all order by rank desc, local_date desc limit 12) r), '[]'::jsonb),
      'coach_replies', coalesce((select jsonb_agg(jsonb_build_object(
          'message_id', r.id, 'local_date', r.local_date, 'content', left(r.content, 300))
          order by r.rank desc, r.local_date desc)
        from replies r), '[]'::jsonb)));
end $$;

-- 8 ----------------------------------------------------------------------------------------------

-- The facts the Coach watch-outs are computed from (functions/_shared/coach_context/contributors/
-- watch_outs.ts): raw readings and dates only, never a conclusion. The conclusions, and the
-- thresholds they use, are in TypeScript and name where each threshold comes from.
--   sleep        the newest night with sleep minutes (date, minutes)
--   metrics      the newest computed row of today or yesterday: recovery score, sleep quality score,
--                the engine's z-scores for resting heart rate and HRV (from scores_jsonb) and the
--                components that were not usable
--   check_in     the newest check-in of today or yesterday: pain, soreness, energy, sleep quality
--   pain_flags   exercises the athlete flagged for pain in the last 14 days (newest 6)
--   skipped      exercises skipped in each of their last 2 or more sessions (56 days; newest 4)
--   weigh_in     the newest weight reading's date (manual or watch)
--   health_sync  the newest Apple Health sync time, as the athlete's local date
--   plan         the active plan version: its number, the day it took effect and its block weeks
create function public.get_coach_watch_outs_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'local_date', p_local_date,
    'sleep', (select jsonb_build_object('local_date', h.local_date, 'minutes', h.sleep_minutes)
      from public.daily_health_summaries h
      where h.user_id = p_user_id and h.local_date <= p_local_date and h.sleep_minutes > 0
      order by h.local_date desc limit 1),
    'metrics', (select jsonb_build_object(
        'local_date', m.local_date,
        'recovery_score', m.recovery_score,
        'sleep_quality_score', m.sleep_quality_score,
        'hrv_z', (m.scores_jsonb -> 'recovery_breakdown' ->> 'hrv_z')::numeric,
        'rhr_z', (m.scores_jsonb -> 'recovery_breakdown' ->> 'rhr_z')::numeric,
        'missing_components', coalesce(m.scores_jsonb -> 'recovery_breakdown' -> 'missing_components',
          '[]'::jsonb))
      from public.daily_computed_metrics m
      where m.user_id = p_user_id and m.local_date between p_local_date - 1 and p_local_date
      order by m.local_date desc, m.computed_at desc limit 1),
    'check_in', (select jsonb_build_object('local_date', c.local_date, 'pain_severity', c.pain_severity,
        'soreness', c.soreness, 'energy', c.energy, 'sleep_quality', c.sleep_quality)
      from public.daily_check_ins c
      where c.user_id = p_user_id and c.superseded_at is null
        and c.local_date between p_local_date - 1 and p_local_date
      order by c.local_date desc limit 1),
    'pain_flags', coalesce((select jsonb_agg(jsonb_build_object('local_date', f.local_date,
        'name', f.name, 'slug', f.exercise_slug) order by f.local_date desc)
      from (
        select s.local_date, p.exercise_slug,
          coalesce(p.performed_name, pe.display_name_snapshot) as name
        from public.workout_sessions s
        join public.exercise_performances p on p.workout_session_id = s.id and p.user_id = s.user_id
        left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
        where s.user_id = p_user_id and s.state = 'completed' and p.pain_flag
          and s.local_date between p_local_date - 13 and p_local_date
        order by s.local_date desc limit 6
      ) f), '[]'::jsonb),
    'skipped', coalesce((select jsonb_agg(jsonb_build_object('name', k.name, 'slug', k.slug,
        'sessions', k.streak, 'last_date', k.last_date) order by k.last_date desc, k.name)
      from (
        select e.key, max(e.name) as name, max(e.slug) as slug,
          coalesce(min(e.rn) filter (where e.status <> 'skipped') - 1, count(*)) as streak,
          max(e.local_date) as last_date
        from (
          select coalesce(p.exercise_slug,
              private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))) as key,
            coalesce(p.performed_name, pe.display_name_snapshot) as name,
            p.exercise_slug as slug, s.local_date, p.status,
            row_number() over (
              partition by coalesce(p.exercise_slug,
                private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot)))
              order by s.local_date desc, s.completed_at desc) as rn
          from public.workout_sessions s
          join public.exercise_performances p on p.workout_session_id = s.id and p.user_id = s.user_id
          left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
          where s.user_id = p_user_id and s.state = 'completed'
            and s.local_date between p_local_date - 55 and p_local_date
        ) e
        group by e.key
        having coalesce(min(e.rn) filter (where e.status <> 'skipped') - 1, count(*)) >= 2
        order by max(e.local_date) desc, max(e.name) limit 4
      ) k), '[]'::jsonb),
    'weigh_in', (select jsonb_build_object('local_date', max(r.d))
      from (
        select b.measured_on as d from public.body_measurements b
        where b.user_id = p_user_id and b.weight_kg is not null and b.measured_on <= p_local_date
        union all
        select h.local_date from public.daily_health_summaries h
        where h.user_id = p_user_id and h.weight_kg is not null and h.local_date <= p_local_date
      ) r having max(r.d) is not null),
    'health_sync', (select jsonb_build_object(
        'local_date', private.local_day(p_user_id, max(h.last_synced_at)))
      from public.daily_health_summaries h where h.user_id = p_user_id having count(*) > 0),
    'plan', (select jsonb_build_object('version', v.version_number,
        'starts_on', coalesce(v.effective_date, private.local_day(p_user_id, v.created_at)),
        'block_weeks', v.block_weeks, 'ends_on', v.ends_on)
      from public.training_plan_versions v
      where v.user_id = p_user_id and v.status = 'active' limit 1));
$$;

-- Access -----------------------------------------------------------------------------------------

do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'coach\_lookup\_%\_v1'
        or p.proname in ('get_coach_plan_state_v1', 'get_coach_nutrition_state_v1',
          'get_coach_data_index_v1', 'get_coach_watch_outs_v1'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
