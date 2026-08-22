-- Additive migration: 180-minute session duration cap.
-- 1. complete_workout clamps duration to 10800s server-side (never hard-errors).
-- 2. compute_daily_metrics excludes sessions > 10800s from strain/ACWR windows
--    (handles the historical July-22 row without rewriting data).
-- No UPDATE of historical rows. No constraint changes. Fully additive.

create or replace function public.complete_workout(
  session_id uuid,
  client_revision integer,
  duration_seconds integer,
  session_energy smallint,
  session_effort numeric,
  notes text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare session public.workout_sessions%rowtype; completed_sets integer; total_sets integer; coverage numeric;
  capped_duration integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into session from public.workout_sessions where id=session_id and user_id=auth.uid() for update;
  if not found then raise exception 'session not found' using errcode='P0002'; end if;
  if session.state='completed' then return jsonb_build_object('session_id',session.id,'replayed',true); end if;
  if client_revision < session.client_revision then raise exception 'stale client revision' using errcode='40001'; end if;
  select count(*) filter(where s.completed),count(*) into completed_sets,total_sets
  from public.exercise_sets s join public.exercise_performances p on p.id=s.exercise_performance_id
  where p.workout_session_id=session.id;
  if completed_sets=0 then raise exception 'complete at least one set' using errcode='22023'; end if;
  coverage := completed_sets::numeric / greatest(total_sets,1);
  capped_duration := least(complete_workout.duration_seconds, 10800);
  update public.exercise_performances p set status=case
    when p.status='skipped' then 'skipped'
    when exists(select 1 from public.exercise_sets s where s.exercise_performance_id=p.id and s.completed) then 'performed'
    else 'unknown' end
  where p.workout_session_id=session.id;
  update public.workout_sessions set
    state='completed',completed_at=now(),actual_ended_at=coalesce(actual_ended_at,now()),
    duration_seconds=capped_duration,session_energy=complete_workout.session_energy,
    session_effort=complete_workout.session_effort,notes=complete_workout.notes,
    logging_completeness=coverage,client_revision=greatest(workout_sessions.client_revision,complete_workout.client_revision),updated_at=now()
  where id=session.id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'workout.completed','workout_session',session.id,'succeeded',
    jsonb_build_object('completed_sets',completed_sets,'total_sets',total_sets,'logging_completeness',coverage));
  return jsonb_build_object('session_id',session.id,'completed_sets',completed_sets,'total_sets',total_sets,'logging_completeness',coverage,'replayed',false);
end $$;

create or replace function public.compute_daily_metrics(
  target_user_id uuid,
  target_date date,
  target_timezone text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  baseline record;
  today_health public.daily_health_summaries%rowtype;
  hrv_z numeric; rhr_z numeric; sleep_z numeric; resp_rate_z numeric; strain_z numeric;
  composite_z numeric; recovery_score integer;
  sleep_efficiency numeric; restorative_pct numeric;
  duration_score numeric; efficiency_score numeric; restorative_score numeric;
  consistency_score numeric; sleep_quality_score integer;
  sleep_consistency_stddev numeric; sleep_consistency_mean numeric;
  sleep_7d_avg_minutes numeric; sleep_debt_minutes integer;
  prev_7d_strain_avg numeric; prev_7d_strain_data record;
  acwr numeric; monotony numeric; daily_strain numeric;
  weight_trend_7d numeric; weight_trend_28d numeric; weight_r2 numeric;
  macro_adherence_pct numeric;
  data_confidence text;
  active_target record;
  baseline_jsonb jsonb := '{}'::jsonb;
  scores_jsonb jsonb;
  eligibility_jsonb jsonb;
  missing_components text[] := '{}';
  weight_total numeric;
  computed_at timestamptz := now();
begin
  if target_user_id is null
    or not exists(select 1 from public.user_accounts where id = target_user_id)
  then raise exception 'account not found' using errcode = 'P0002';
  end if;

  perform public.compute_user_baselines(target_user_id, target_date);

  select * into today_health from public.daily_health_summaries
    where user_id = target_user_id and local_date = target_date
      and source_scope = 'healthkit';

  for baseline in
    select metric_name, baseline_value, spread, n_observations, confidence
    from public.user_baselines where user_id = target_user_id
  loop
    baseline_jsonb := baseline_jsonb || jsonb_build_object(
      baseline.metric_name,
      jsonb_build_object(
        'ewma', round(baseline.baseline_value, 2),
        'spread', round(baseline.spread, 2),
        'n_obs', baseline.n_observations,
        'confidence', baseline.confidence
      )
    );
  end loop;

  composite_z := 0;
  weight_total := 0;
  hrv_z := 0; rhr_z := 0; sleep_z := 0; resp_rate_z := 0; strain_z := 0;

  if today_health.hrv_value_ms is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'hrv_sdnn_ms';
    if found and baseline.spread > 0 then
      hrv_z := (today_health.hrv_value_ms - baseline.baseline_value) / baseline.spread;
    end if;
    composite_z := composite_z + 0.55 * hrv_z;
    weight_total := weight_total + 0.55;
  else
    missing_components := missing_components || ARRAY['hrv_sdnn']::text[];
  end if;

  if today_health.resting_heart_rate_bpm is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'resting_hr_bpm';
    if found and baseline.spread > 0 then
      rhr_z := -(today_health.resting_heart_rate_bpm - baseline.baseline_value) / baseline.spread;
    end if;
    composite_z := composite_z + 0.20 * rhr_z;
    weight_total := weight_total + 0.20;
  else
    missing_components := missing_components || ARRAY['resting_hr']::text[];
  end if;

  if today_health.sleep_minutes is not null and today_health.sleep_minutes > 0 then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'sleep_minutes';
    if found and baseline.spread > 0 then
      sleep_z := (today_health.sleep_minutes - baseline.baseline_value) / baseline.spread;
    end if;
    composite_z := composite_z + 0.15 * sleep_z;
    weight_total := weight_total + 0.15;
  else
    sleep_z := 0;
  end if;

  if today_health.respiratory_rate_bpm is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'resp_rate_bpm';
    if found and baseline.spread > 0 then
      resp_rate_z := -(today_health.respiratory_rate_bpm - baseline.baseline_value) / baseline.spread;
    end if;
    composite_z := composite_z + 0.05 * resp_rate_z;
    weight_total := weight_total + 0.05;
  end if;

  daily_strain := coalesce((
    select sum(session_effort * duration_seconds / 600.0)
    from public.workout_sessions
    where user_id = target_user_id
      and local_date = target_date
      and state = 'completed'
      and session_effort is not null
      and duration_seconds is not null
      and duration_seconds <= 10800
  ), 0);

  prev_7d_strain_avg := null;
  select avg(strain) into prev_7d_strain_avg from (
    select local_date,
      coalesce(sum(session_effort * duration_seconds / 600.0), 0) as strain
    from public.workout_sessions
    where user_id = target_user_id
      and local_date < target_date
      and local_date >= target_date - 7
      and state = 'completed'
      and session_effort is not null
      and duration_seconds is not null
      and duration_seconds <= 10800
    group by local_date
  ) p7d;

  if prev_7d_strain_avg is not null and prev_7d_strain_avg > 0 then
    select avg(strain), stddev_samp(strain), count(*)
    into prev_7d_strain_data
    from (
      select local_date,
        coalesce(sum(session_effort * duration_seconds / 600.0), 0) as strain
      from public.workout_sessions
      where user_id = target_user_id
        and local_date >= target_date - 28
        and local_date <= target_date - 1
        and state = 'completed'
        and session_effort is not null
        and duration_seconds is not null
        and duration_seconds <= 10800
      group by local_date
    ) h;

    if prev_7d_strain_data.stddev_samp > 0 then
      strain_z := (prev_7d_strain_avg - prev_7d_strain_data.avg)
        / prev_7d_strain_data.stddev_samp;
    end if;
    composite_z := composite_z - 0.05 * strain_z;
    weight_total := weight_total + 0.05;
  end if;

  if weight_total > 0 then
    composite_z := composite_z / weight_total;
  end if;

  recovery_score := round(100.0 / (1.0 + exp(-1.6 * (composite_z + 0.2))));

  sleep_quality_score := null;
  duration_score := null; efficiency_score := null;
  restorative_score := null; consistency_score := null;
  sleep_debt_minutes := null;

  if today_health.sleep_minutes is not null and today_health.sleep_minutes > 0 then
    sleep_efficiency := coalesce(
      (today_health.sleep_minutes - coalesce(today_health.sleep_awake_minutes, 0))
        ::numeric / today_health.sleep_minutes, 0
    );

    restorative_pct := coalesce(
      (coalesce(today_health.sleep_deep_minutes, 0)
       + coalesce(today_health.sleep_rem_minutes, 0))::numeric
       / today_health.sleep_minutes, 0
    );

    duration_score := greatest(0, least(100,
      case when baseline.baseline_value > 0
        then 480.0 / baseline.baseline_value * 100
        else 100
      end
    ));

    efficiency_score := sleep_efficiency * 100;
    restorative_score := restorative_pct * 100;

    select stddev_samp(sleep_minutes), avg(sleep_minutes)
    into sleep_consistency_stddev, sleep_consistency_mean
    from public.daily_health_summaries
    where user_id = target_user_id
      and source_scope = 'healthkit'
      and local_date >= target_date - 6
      and local_date <= target_date
      and sleep_minutes is not null;

    if sleep_consistency_stddev is not null
       and sleep_consistency_mean is not null
       and sleep_consistency_mean > 0 then
      consistency_score := greatest(0,
        100 - ((sleep_consistency_stddev / sleep_consistency_mean) * 50));
    else
      consistency_score := 100;
    end if;

    sleep_quality_score := round(
      0.50 * coalesce(duration_score, 50)
      + 0.20 * coalesce(efficiency_score, 50)
      + 0.20 * coalesce(restorative_score, 50)
      + 0.10 * coalesce(consistency_score, 50)
    );

    if sleep_quality_score > 100 then sleep_quality_score := 100; end if;
    if sleep_quality_score < 0 then sleep_quality_score := 0; end if;

    select avg(sleep_minutes) into sleep_7d_avg_minutes
    from public.daily_health_summaries
    where user_id = target_user_id
      and source_scope = 'healthkit'
      and local_date >= target_date - 6
      and local_date <= target_date
      and sleep_minutes is not null;

    if sleep_7d_avg_minutes is not null then
      sleep_debt_minutes := 480 - round(sleep_7d_avg_minutes);
    end if;
  end if;

  acwr := null;
  monotony := null;
  begin
    select
      case when avg28 != 0 then round(avg7 / avg28, 2) end,
      case when stddev7 > 0 then round(avg7 / stddev7, 2) end
    into acwr, monotony
    from (
      select
        avg(strain) filter (where rn <= 7) as avg7,
        avg(strain) filter (where rn <= 28) as avg28,
        stddev_samp(strain) filter (where rn <= 7) as stddev7
      from (
        select
          local_date,
          coalesce(sum(session_effort * duration_seconds / 600.0), 0) as strain,
          row_number() over (order by local_date desc) as rn
        from public.workout_sessions
        where user_id = target_user_id
          and local_date <= target_date
          and state = 'completed'
          and session_effort is not null
          and duration_seconds is not null
          and duration_seconds <= 10800
        group by local_date
      ) d
    ) r;
  exception when others then
    acwr := null; monotony := null;
  end;

  weight_trend_7d := null; weight_trend_28d := null; weight_r2 := null;
  begin
    select
      regr_slope(weight_kg, extract(epoch from measured_on::timestamp) / 86400.0)
        filter (where measured_on >= target_date - 6),
      regr_slope(weight_kg, extract(epoch from measured_on::timestamp) / 86400.0)
        filter (where measured_on >= target_date - 27),
      regr_r2(weight_kg, extract(epoch from measured_on::timestamp) / 86400.0)
        filter (where measured_on >= target_date - 27)
    into weight_trend_7d, weight_trend_28d, weight_r2
    from (
      select measured_on, weight_kg
      from public.body_measurements
      where user_id = target_user_id and measured_on <= target_date
      union
      select local_date, weight_kg
      from public.daily_health_summaries
      where user_id = target_user_id and source_scope = 'healthkit'
        and local_date <= target_date and weight_kg is not null
        and local_date not in (
          select measured_on from public.body_measurements
          where user_id = target_user_id
        )
    ) w
    where measured_on >= target_date - 27;
  exception when others then
    weight_trend_7d := null; weight_trend_28d := null; weight_r2 := null;
  end;

  macro_adherence_pct := null;
  select id, calories, protein_g, carbohydrate_g, fat_g
    into active_target
    from public.nutrition_target_sets
    where user_id = target_user_id and status = 'active' limit 1;
  if found and active_target.calories > 0 then
    select round(avg(
      case when active_target.calories > 0
        then least(day_calories / active_target.calories * 100, 200)
      end
    )) into macro_adherence_pct
    from (
      select
        m.local_date,
        coalesce(sum(mi.calories), 0) as day_calories
      from public.meals m
      join public.meal_items mi on mi.meal_id = m.id and mi.user_id = target_user_id
      where m.user_id = target_user_id
        and m.local_date >= target_date - 13
        and m.local_date <= target_date
        and m.status = 'confirmed'
        and mi.confirmed_at is not null
      group by m.local_date
    ) daily;
  end if;

  if today_health.id is not null then
    if cardinality(missing_components) = 0 then
      data_confidence := 'high';
    elsif cardinality(missing_components) <= 2 then
      data_confidence := 'medium';
    else
      data_confidence := 'low';
    end if;
  else
    data_confidence := 'low';
  end if;

  scores_jsonb := jsonb_build_object(
    'recovery', recovery_score,
    'recovery_breakdown', jsonb_build_object(
      'hrv_z', round(hrv_z, 3),
      'rhr_z', round(rhr_z, 3),
      'sleep_z', round(sleep_z, 3),
      'resp_rate_z', round(resp_rate_z, 3),
      'prev_strain_z', round(strain_z, 3)
    ),
    'sleep_quality', sleep_quality_score,
    'sleep_breakdown', case when sleep_quality_score is not null
      then jsonb_build_object(
        'duration_score', round(duration_score, 1),
        'efficiency_score', round(efficiency_score, 1),
        'restorative_score', round(restorative_score, 1),
        'consistency_score', round(consistency_score, 1))
      end,
    'sleep_debt_minutes', sleep_debt_minutes,
    'daily_strain', round(daily_strain, 2),
    'acwr', acwr,
    'training_monotony', monotony,
    'weight_trend_7d_kg_per_day', case when weight_trend_7d is not null
      then round(weight_trend_7d, 4) end,
    'weight_trend_28d_kg_per_day', case when weight_trend_28d is not null
      then round(weight_trend_28d, 4) end,
    'weight_trend_r2_28d', case when weight_r2 is not null
      then round(weight_r2, 4) end,
    'macro_adherence_pct', macro_adherence_pct
  );

  eligibility_jsonb := public.evaluate_change_eligibility(target_user_id, target_date);

  insert into public.daily_computed_metrics (
    user_id, local_date, recovery_score, sleep_quality_score,
    sleep_debt_minutes, daily_strain, acwr, training_monotony,
    weight_trend_7d_kg_per_day, weight_trend_28d_kg_per_day,
    macro_adherence_pct, data_confidence, scores_jsonb,
    baseline_snapshot_jsonb, eligibility_jsonb, schema_version
  ) values (
    target_user_id, target_date, recovery_score, sleep_quality_score,
    sleep_debt_minutes, daily_strain, acwr, monotony,
    case when weight_trend_7d is not null then round(weight_trend_7d, 4) end,
    case when weight_trend_28d is not null then round(weight_trend_28d, 4) end,
    macro_adherence_pct, data_confidence, scores_jsonb,
    baseline_jsonb, eligibility_jsonb, '2.0'
  )
  on conflict (user_id, local_date) do update set
    recovery_score = excluded.recovery_score,
    sleep_quality_score = excluded.sleep_quality_score,
    sleep_debt_minutes = excluded.sleep_debt_minutes,
    daily_strain = excluded.daily_strain,
    acwr = excluded.acwr,
    training_monotony = excluded.training_monotony,
    weight_trend_7d_kg_per_day = excluded.weight_trend_7d_kg_per_day,
    weight_trend_28d_kg_per_day = excluded.weight_trend_28d_kg_per_day,
    macro_adherence_pct = excluded.macro_adherence_pct,
    data_confidence = excluded.data_confidence,
    scores_jsonb = excluded.scores_jsonb,
    baseline_snapshot_jsonb = excluded.baseline_snapshot_jsonb,
    eligibility_jsonb = excluded.eligibility_jsonb,
    computed_at = excluded.computed_at;

  return jsonb_build_object(
    'baselines', baseline_jsonb,
    'scores', scores_jsonb,
    'data_confidence', data_confidence
  );
end $$;
