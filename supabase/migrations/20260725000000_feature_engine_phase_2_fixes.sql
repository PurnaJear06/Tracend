alter table public.daily_health_summaries
  add column respiratory_rate_bpm numeric(5,2)
  check (respiratory_rate_bpm between 0 and 100);

alter table public.daily_health_summaries
  drop constraint if exists daily_health_summaries_present_types_check;

alter table public.daily_health_summaries
  add constraint daily_health_summaries_present_types_check
  check (
    present_types <@ array[
      'steps', 'active_energy', 'sleep', 'workouts', 'weight',
      'resting_heart_rate', 'hrv_sdnn', 'resp_rate'
    ]::text[]
  );

alter table public.user_baselines
  drop constraint if exists user_baselines_metric_name_check;

alter table public.user_baselines
  add constraint user_baselines_metric_name_check
  check (metric_name in (
    'hrv_sdnn_ms', 'resting_hr_bpm', 'sleep_minutes', 'weight_kg', 'resp_rate_bpm'
  ));

alter table public.metric_baseline_history
  drop constraint if exists metric_baseline_history_metric_name_check;

alter table public.metric_baseline_history
  add constraint metric_baseline_history_metric_name_check
  check (metric_name in (
    'hrv_sdnn_ms', 'resting_hr_bpm', 'sleep_minutes', 'weight_kg', 'resp_rate_bpm'
  ));

create table public.daily_computed_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  local_date date not null,
  recovery_score integer check (recovery_score between 0 and 100),
  sleep_quality_score integer check (sleep_quality_score between 0 and 100),
  sleep_debt_minutes integer,
  daily_strain numeric not null default 0,
  acwr numeric,
  training_monotony numeric,
  weight_trend_7d_kg_per_day numeric,
  weight_trend_28d_kg_per_day numeric,
  macro_adherence_pct numeric,
  data_confidence text not null check (data_confidence in (
    'cold_start', 'low', 'medium', 'high'
  )),
  scores_jsonb jsonb not null default '{}'::jsonb,
  baseline_snapshot_jsonb jsonb not null default '{}'::jsonb,
  eligibility_jsonb jsonb not null default '{}'::jsonb,
  computed_at timestamptz not null default now(),
  schema_version text not null default '2.0',
  unique (user_id, local_date),
  unique (id, user_id)
);

create index daily_computed_metrics_user_date
  on public.daily_computed_metrics(user_id, local_date desc);

alter table public.daily_computed_metrics enable row level security;
alter table public.daily_computed_metrics force row level security;

create policy daily_computed_metrics_own_read on public.daily_computed_metrics
  for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.daily_computed_metrics from anon, authenticated;
grant select on public.daily_computed_metrics to authenticated;

create or replace function public.compute_user_baselines(
  target_user_id uuid,
  target_date date
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  _metric_name text;
  values_arr numeric[];
  baseline numeric;
  median numeric;
  mad numeric;
  spread numeric;
  lower_bound numeric;
  upper_bound numeric;
  hard_lower numeric;
  hard_upper numeric;
  winsorized numeric;
  half_life_days numeric;
  lambda numeric;
  ewma numeric;
  n_obs integer;
  confidence text;
  prior_history_id uuid;
  i integer;
  _obs_date date;
begin
  if target_user_id is null
    or not exists(select 1 from public.user_accounts where id = target_user_id)
  then raise exception 'account not found' using errcode = 'P0002';
  end if;

  for _metric_name in
    select unnest(array['hrv_sdnn_ms','resting_hr_bpm','sleep_minutes','weight_kg','resp_rate_bpm'])
  loop
    case _metric_name
      when 'hrv_sdnn_ms' then
        select array_agg(hrv_value_ms order by local_date) into values_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and hrv_value_ms is not null;
      when 'resting_hr_bpm' then
        select array_agg(resting_heart_rate_bpm order by local_date) into values_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and resting_heart_rate_bpm is not null;
      when 'sleep_minutes' then
        select array_agg(sleep_minutes order by local_date) into values_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and sleep_minutes is not null;
      when 'weight_kg' then
        select array_agg(w.weight_kg order by w.measured_on) into values_arr
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
          order by measured_on
        ) w;
      when 'resp_rate_bpm' then
        select array_agg(respiratory_rate_bpm order by local_date) into values_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and respiratory_rate_bpm is not null;
    end case;

    if values_arr is null or array_length(values_arr, 1) < 3 then
      insert into public.user_baselines (
        user_id, metric_name, baseline_value, spread, n_observations,
        confidence, last_observation_date
      ) values (
        target_user_id, _metric_name, coalesce(values_arr[1], 0),
        0, coalesce(array_length(values_arr, 1), 0),
        'cold_start', target_date
      )
      on conflict (user_id, metric_name) do update set
        baseline_value = excluded.baseline_value,
        spread = excluded.spread,
        n_observations = excluded.n_observations,
        confidence = excluded.confidence,
        last_calculated_at = now(),
        last_observation_date = excluded.last_observation_date;
      continue;
    end if;

    n_obs := array_length(values_arr, 1);

    select percentile_cont(0.5) within group (order by v) into median
    from unnest(values_arr) as v;

    select percentile_cont(0.5) within group (order by abs(v - median)) into mad
    from unnest(values_arr) as v;

    spread := 1.4826 * coalesce(mad, 0);
    lower_bound := median - 3.0 * spread;
    upper_bound := median + 3.0 * spread;
    hard_lower := median - 5.0 * spread;
    hard_upper := median + 5.0 * spread;

    ewma := values_arr[1];

    select local_date into _obs_date
    from public.daily_health_summaries
    where user_id = target_user_id and source_scope = 'healthkit'
      and local_date <= target_date
    order by local_date limit 1;

    if _obs_date is not null then
      insert into public.metric_baseline_history (
        user_id, metric_name, baseline_value, spread, n_observations,
        observation_date, raw_value, lambda_used, engine_version
      ) values (
        target_user_id, _metric_name, ewma, spread, n_obs,
        _obs_date, values_arr[1], 1.0, 'baseline-v1'
      ) returning id into prior_history_id;
    else
      prior_history_id := null;
    end if;

    for i in 2..n_obs loop
      if values_arr[i] < hard_lower or values_arr[i] > hard_upper then
        insert into public.metric_baseline_history (
          user_id, metric_name, baseline_value, spread, n_observations,
          observation_date, raw_value, was_outlier_rejected,
          lambda_used, prior_baseline_id, engine_version
        ) values (
          target_user_id, _metric_name, ewma, spread, n_obs,
          null, values_arr[i], true,
          0, prior_history_id, 'baseline-v1'
        ) returning id into prior_history_id;
        continue;
      end if;

      winsorized := greatest(lower_bound, least(upper_bound, values_arr[i]));

      if i <= 8 then half_life_days := 3; else half_life_days := 14; end if;
      lambda := 1.0 - (0.5 ^ (1.0 / half_life_days));

      ewma := lambda * winsorized + (1.0 - lambda) * ewma;

      insert into public.metric_baseline_history (
        user_id, metric_name, baseline_value, spread, n_observations,
        observation_date, raw_value, was_winsorized,
        lambda_used, prior_baseline_id, engine_version
      ) values (
        target_user_id, _metric_name, ewma, spread, n_obs,
        null, values_arr[i],
        values_arr[i] <> winsorized,
        lambda, prior_history_id, 'baseline-v1'
      ) returning id into prior_history_id;
    end loop;

    baseline := public.compute_winsorized_ewma(values_arr, n_obs);

    if n_obs >= 14 then confidence := 'high';
    elsif n_obs >= 7 then confidence := 'medium';
    else confidence := 'low';
    end if;

    insert into public.user_baselines (
      user_id, metric_name, baseline_value, spread, n_observations,
      confidence, last_observation_date
    ) values (
      target_user_id, _metric_name, baseline, spread, n_obs,
      confidence, target_date
    )
    on conflict (user_id, metric_name) do update set
      baseline_value = excluded.baseline_value,
      spread = excluded.spread,
      n_observations = excluded.n_observations,
      confidence = excluded.confidence,
      last_calculated_at = now(),
      last_observation_date = excluded.last_observation_date;
  end loop;
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

create or replace function public.recompute_stale_metrics()
returns integer language plpgsql security definer set search_path = '' as $$
declare
  stale record;
  processed integer := 0;
begin
  for stale in
    select dhs.user_id, dhs.local_date, dhs.timezone
    from public.daily_health_summaries dhs
    left join public.daily_computed_metrics dcm
      on dcm.user_id = dhs.user_id
      and dcm.local_date = dhs.local_date
    where dhs.source_scope = 'healthkit'
      and dhs.local_date = current_date - 1
      and dcm.id is null
      and exists(select 1 from public.user_accounts ua where ua.id = dhs.user_id)
    limit 100
  loop
    begin
      perform public.compute_daily_metrics(
        stale.user_id,
        stale.local_date,
        coalesce(stale.timezone, 'UTC')
      );
      processed := processed + 1;
    exception when others then
      null;
    end;
  end loop;

  return processed;
end $$;

revoke all on function
  public.compute_winsorized_ewma(numeric[], integer),
  public.compute_user_baselines(uuid, date),
  public.compute_daily_metrics(uuid, date, text),
  public.evaluate_change_eligibility(uuid, date),
  public.recompute_stale_metrics()
  from public, anon, authenticated;

grant execute on function
  public.compute_user_baselines(uuid, date),
  public.compute_daily_metrics(uuid, date, text),
  public.evaluate_change_eligibility(uuid, date)
  to service_role;

grant execute on function
  public.recompute_stale_metrics()
  to service_role;
