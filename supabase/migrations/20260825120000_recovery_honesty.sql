-- Chunk 7 — Recovery honesty.
--
-- Problem (observed in production 2026-08-25):
--   * Every z-score defaulted to 0 and was still added to the composite with
--     its full weight, so a day with no usable data scored recovery 58 via the
--     sigmoid's +0.2 optimism offset instead of reporting "no data".
--   * A present value without a usable baseline (cold start / spread = 0)
--     masqueraded as "exactly at baseline" (z = 0) with full weight.
--   * data_confidence only counted two of the five components, so days with
--     no sleep or respiratory data still reported 'high'.
--
-- Fix (fully additive — create or replace, no schema or column changes):
--   * A component only joins the composite when it has BOTH a value today and
--     a usable baseline (spread > 0). Otherwise it is listed in
--     recovery_breakdown.missing_components.
--   * recovery is NULL when no component is usable (never a fabricated number).
--   * The +0.2 optimism offset is removed; recovery is centred on 50 at
--     baseline.
--   * data_confidence counts the four HealthKit components
--     (hrv / resting hr / sleep / respiratory rate). prev_strain is reported
--     missing but does not lower confidence on its own (rest days are normal).
--   * All five z-score keys remain present and non-null (0 when unusable) so
--     already-shipped clients keep parsing the shape they know.
--   * duration_score now reads the sleep baseline from a dedicated select.
--     Previously it reused the shared `baseline` record, which on days with
--     respiratory data held the resp-rate baseline, so the sleep-duration
--     component (weight 0.50 of sleep_quality) ignored the documented sleep
--     EWMA. Pre-existing since 20260725000000; fixed here because this
--     rewrite is the honesty change and had not deployed yet.
--   * duration_score compares tonight's sleep duration against the personal
--     baseline (480-minute target fallback). The previous 480/baseline form
--     ignored tonight's sleep entirely: a 4-hour night scored identically to
--     a 9-hour night, and any baseline <= 480 was pinned at 100 forever.
--     Found by the noop StrandAnalytics rigor cross-check (2026-08-26).
--   * prev_strain only joins the composite when the 28-day strain spread is
--     > 0. A single strain day (stddev NULL) or identical days (stddev 0)
--     previously entered at z = 0 with full weight — the same fabrication
--     pattern this migration removes for the four health components.

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
  sleep_baseline_value numeric;
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
  health_missing_count integer;
  weight_total numeric;
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

  -- HRV (weight 0.55). Usable only with a value today AND a baseline with
  -- spread > 0; otherwise reported missing and excluded from the composite.
  if today_health.hrv_value_ms is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'hrv_sdnn_ms';
    if found and baseline.spread > 0 then
      hrv_z := (today_health.hrv_value_ms - baseline.baseline_value) / baseline.spread;
      composite_z := composite_z + 0.55 * hrv_z;
      weight_total := weight_total + 0.55;
    else
      missing_components := missing_components || array['hrv_sdnn']::text[];
    end if;
  else
    missing_components := missing_components || array['hrv_sdnn']::text[];
  end if;

  -- Resting HR (weight 0.20). Lower than baseline is better recovery.
  if today_health.resting_heart_rate_bpm is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'resting_hr_bpm';
    if found and baseline.spread > 0 then
      rhr_z := -(today_health.resting_heart_rate_bpm - baseline.baseline_value) / baseline.spread;
      composite_z := composite_z + 0.20 * rhr_z;
      weight_total := weight_total + 0.20;
    else
      missing_components := missing_components || array['resting_hr']::text[];
    end if;
  else
    missing_components := missing_components || array['resting_hr']::text[];
  end if;

  -- Sleep (weight 0.15). More than baseline is better recovery.
  if today_health.sleep_minutes is not null and today_health.sleep_minutes > 0 then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'sleep_minutes';
    if found and baseline.spread > 0 then
      sleep_z := (today_health.sleep_minutes - baseline.baseline_value) / baseline.spread;
      composite_z := composite_z + 0.15 * sleep_z;
      weight_total := weight_total + 0.15;
    else
      missing_components := missing_components || array['sleep_minutes']::text[];
    end if;
  else
    missing_components := missing_components || array['sleep_minutes']::text[];
  end if;

  -- Respiratory rate (weight 0.05). Lower than baseline is better recovery.
  if today_health.respiratory_rate_bpm is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'resp_rate_bpm';
    if found and baseline.spread > 0 then
      resp_rate_z := -(today_health.respiratory_rate_bpm - baseline.baseline_value) / baseline.spread;
      composite_z := composite_z + 0.05 * resp_rate_z;
      weight_total := weight_total + 0.05;
    else
      missing_components := missing_components || array['resp_rate']::text[];
    end if;
  else
    missing_components := missing_components || array['resp_rate']::text[];
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

  -- Prior strain (weight 0.05, subtracted). Higher recent strain lowers
  -- recovery. Usable only with a non-zero 7-day strain average AND a 28-day
  -- spread > 0; a single strain day (stddev NULL) or identical days
  -- (stddev 0) cannot produce a z-score, so the component is reported
  -- missing instead of joining the composite at z = 0 with full weight.
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
      composite_z := composite_z - 0.05 * strain_z;
      weight_total := weight_total + 0.05;
    else
      missing_components := missing_components || array['prev_strain']::text[];
    end if;
  else
    missing_components := missing_components || array['prev_strain']::text[];
  end if;

  if weight_total > 0 then
    composite_z := composite_z / weight_total;
    -- No optimism offset: composite 0 (exactly at baseline) maps to 50.
    recovery_score := round(100.0 / (1.0 + exp(-1.6 * composite_z)));
  else
    recovery_score := null;
  end if;

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

    -- Dedicated select: the shared `baseline` record may hold another
    -- metric's baseline here (resp rate runs after sleep), which silently
    -- corrupted duration_score on resp-present days.
    select ub.baseline_value into sleep_baseline_value
    from public.user_baselines ub
    where ub.user_id = target_user_id and ub.metric_name = 'sleep_minutes';

    -- Tonight's duration against the personal baseline (fallback: the 480-min
    -- target). The old 480/baseline form ignored tonight's sleep entirely:
    -- a 4-hour night scored identically to a 9-hour night, and any baseline
    -- <= 480 was pinned at 100 forever.
    duration_score := greatest(0, least(100,
      today_health.sleep_minutes::numeric
        / coalesce(nullif(sleep_baseline_value, 0), 480) * 100
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

  -- Confidence counts the four HealthKit components. prev_strain is reported
  -- missing above but does not lower confidence by itself.
  select count(*) into health_missing_count
  from unnest(missing_components) m
  where m in ('hrv_sdnn', 'resting_hr', 'sleep_minutes', 'resp_rate');

  if today_health.id is null or health_missing_count >= 3 then
    data_confidence := 'low';
  elsif health_missing_count = 0 then
    data_confidence := 'high';
  else
    data_confidence := 'medium';
  end if;

  scores_jsonb := jsonb_build_object(
    'recovery', recovery_score,
    'recovery_breakdown', jsonb_build_object(
      'hrv_z', round(hrv_z, 3),
      'rhr_z', round(rhr_z, 3),
      'sleep_z', round(sleep_z, 3),
      'resp_rate_z', round(resp_rate_z, 3),
      'prev_strain_z', round(strain_z, 3),
      'missing_components', to_jsonb(missing_components)
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
    baseline_snapshot_jsonb, eligibility_jsonb, schema_version, computed_at
  ) values (
    target_user_id, target_date, recovery_score, sleep_quality_score,
    sleep_debt_minutes, daily_strain, acwr, monotony,
    case when weight_trend_7d is not null then round(weight_trend_7d, 4) end,
    case when weight_trend_28d is not null then round(weight_trend_28d, 4) end,
    macro_adherence_pct, data_confidence, scores_jsonb,
    baseline_jsonb, eligibility_jsonb, '2.1', now()
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

-- get_my_daily_brief passes the computed payload through unchanged; bump its
-- schema_version to advertise the additive recovery_breakdown field.
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
begin
  if v_user_id is null then
    return jsonb_build_object('schema_version', '1.2',
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
    'schema_version', '1.2',
    'local_date', target_date,
    'today_workout', (
      select value->'today_workout'
      from (select public.get_my_training_hub(28) value) t
    ),
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
    )
  );
end;
$$;
