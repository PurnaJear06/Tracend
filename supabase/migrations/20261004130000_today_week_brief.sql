-- Today redesign (owner, 2026-10-04): the brief carries what the new Today
-- page draws, so the app never derives it.
--
-- get_my_daily_brief 1.7 adds, without changing any existing field:
--   recovery_previous  yesterday's stored recovery score ("+6 from yesterday")
--   plan               the active plan's title, version, block length and the
--                      week number since it took effect ("Week 3 of 20")
--   week               Monday to Sunday of target_date's week: each day's
--                      recovery and training strain (today's from the live
--                      computation), whether
--                      a session was completed, and whether the active plan
--                      has a workout that weekday
--   today_session      today's latest kept session: its state and the
--                      completed sets per exercise, so Today mirrors logging
--
-- Copied from 20261002110000_coach_intake.sql; only the fields above and the
-- schema version change.

create or replace function public.get_my_daily_brief(
  target_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
volatile
as $$
declare
  v_user_id uuid := auth.uid();
  v_timezone text;
  v_metrics jsonb;
  v_week_start date := target_date - (extract(isodow from target_date)::integer - 1);
begin
  if v_user_id is null then
    return jsonb_build_object('schema_version', '1.7',
                              'local_date', target_date);
  end if;

  select coalesce(dhs.timezone, 'UTC') into v_timezone
  from public.daily_health_summaries dhs
  where dhs.user_id = v_user_id
    and dhs.source_scope = 'healthkit'
  order by dhs.local_date desc
  limit 1;

  begin
    v_metrics := public.compute_daily_metrics(
      v_user_id, target_date, v_timezone
    );
  exception when others then
    v_metrics := null;
  end;

  return jsonb_build_object(
    'schema_version', '1.7',
    'local_date', target_date,
    'today_workout', private.planned_workout_for_date(v_user_id, target_date),
    'next_meal', (
      select item
      from (
        select public.get_my_nutrition_schedule(target_date) value
      ) n,
      jsonb_array_elements(value->'items') item
      where item->>'status' in ('due', 'upcoming', 'optional')
      order by (item->>'order')::integer
      limit 1
    ),
    'check_in', (
      select to_jsonb(c) - 'user_id' - 'note' - 'idempotency_key'
      from public.daily_check_ins c
      where c.user_id = v_user_id
        and c.local_date = target_date
        and c.superseded_at is null
      limit 1
    ),
    'health', (
      select jsonb_build_object(
        'local_date', d.local_date,
        'last_synced_at', d.last_synced_at,
        'present_types', d.present_types,
        'completeness', d.completeness
      )
      from public.daily_health_summaries d
      where d.user_id = v_user_id
        and d.local_date <= target_date
        and d.local_date >= target_date - 31
      order by d.local_date desc, d.last_synced_at desc
      limit 1
    ),
    'nutrition', public.get_my_daily_nutrition(target_date),
    'computed', v_metrics,
    'latest_decision', (
      select jsonb_build_object(
        'id', cd.id,
        'final_decision', cd.head_coach->>'final_decision',
        'reason', cd.head_coach->>'reason',
        'confidence', cd.confidence,
        'created_at', cd.created_at,
        'evidence', cd.evidence,
        'missing_data', cd.missing_data
      )
      from public.coach_decisions cd
      where cd.user_id = v_user_id
      order by cd.created_at desc
      limit 1
    ),
    'recovery_previous', (
      select m.recovery_score
      from public.daily_computed_metrics m
      where m.user_id = v_user_id
        and m.local_date = target_date - 1
    ),
    'plan', (
      select jsonb_build_object(
        'title', p.title,
        'version_number', v.version_number,
        'block_weeks', v.block_weeks,
        'week_number', greatest(1,
          (target_date - coalesce(v.effective_date, v.approved_at::date)) / 7 + 1)
      )
      from public.training_plan_versions v
      join public.training_plans p on p.id = v.plan_id and p.user_id = v.user_id
      where v.user_id = v_user_id
        and v.status = 'active'
      order by v.version_number desc
      limit 1
    ),
    'week', (
      select jsonb_agg(jsonb_build_object(
        'local_date', d.day,
        'recovery', case
          when d.day = target_date then coalesce(
            (v_metrics->'scores'->>'recovery')::integer, m.recovery_score)
          else m.recovery_score end,
        'strain', case
          when d.day = target_date then coalesce(
            (v_metrics->'scores'->>'daily_strain')::numeric, m.daily_strain)
          else m.daily_strain end,
        'trained', exists (
          select 1 from public.workout_sessions s
          where s.user_id = v_user_id
            and s.local_date = d.day
            and s.state = 'completed'),
        'planned', exists (
          select 1
          from public.planned_workouts w
          join public.training_plan_versions pv
            on pv.id = w.plan_version_id and pv.user_id = w.user_id
          where w.user_id = v_user_id
            and pv.status = 'active'
            and w.preferred_weekday = extract(isodow from d.day)::integer)
      ) order by d.day)
      from (
        select (v_week_start + offs)::date as day
        from generate_series(0, 6) offs
      ) d
      left join public.daily_computed_metrics m
        on m.user_id = v_user_id and m.local_date = d.day
    ),
    'today_session', (
      select jsonb_build_object(
        'state', s.state,
        'exercises', coalesce((
          select jsonb_agg(jsonb_build_object(
            'order', p.exercise_order,
            'completed_sets', (
              select count(*) from public.exercise_sets es
              where es.exercise_performance_id = p.id and es.completed)
          ) order by p.exercise_order)
          from public.exercise_performances p
          where p.workout_session_id = s.id
        ), '[]'::jsonb)
      )
      from public.workout_sessions s
      where s.user_id = v_user_id
        and s.local_date = target_date
        and s.state <> 'abandoned'
      order by s.started_at desc
      limit 1
    )
  );
end;
$$;

