create function public.compute_winsorized_ewma(
  metric_values numeric[],
  n_obs integer
)
returns numeric language plpgsql immutable as $$
declare
  half_life_days numeric;
  lambda numeric;
  ewma numeric;
  median numeric;
  mad numeric;
  spread numeric;
  lower_bound numeric;
  upper_bound numeric;
  hard_lower numeric;
  hard_upper numeric;
  val numeric;
  winsorized numeric;
  i integer;
begin
  if n_obs < 3 then return null; end if;

  select percentile_cont(0.5) within group (order by v) into median
  from unnest(metric_values) as v;

  select percentile_cont(0.5) within group (order by abs(v - median)) into mad
  from unnest(metric_values) as v;

  spread := 1.4826 * coalesce(mad, 0);
  if spread = 0 then return metric_values[n_obs]; end if;

  lower_bound := median - 3.0 * spread;
  upper_bound := median + 3.0 * spread;
  hard_lower := median - 5.0 * spread;
  hard_upper := median + 5.0 * spread;

  ewma := metric_values[1];

  for i in 2..n_obs loop
    val := metric_values[i];
    if val < hard_lower or val > hard_upper then continue; end if;

    winsorized := greatest(lower_bound, least(upper_bound, val));

    if i <= 8 then half_life_days := 3; else half_life_days := 14; end if;
    lambda := 1.0 - (0.5 ^ (1.0 / half_life_days));

    ewma := lambda * winsorized + (1.0 - lambda) * ewma;
  end loop;

  return ewma;
end $$;

create function public.compute_user_baselines(
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
begin
  if target_user_id is null
    or not exists(select 1 from public.user_accounts where id = target_user_id)
  then raise exception 'account not found' using errcode = 'P0002';
  end if;

  for _metric_name in
    select unnest(array['hrv_sdnn_ms', 'resting_hr_bpm', 'sleep_minutes', 'weight_kg'])
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

    insert into public.metric_baseline_history (
      user_id, metric_name, baseline_value, spread, n_observations,
      observation_date, raw_value, lambda_used, engine_version
    ) values (
      target_user_id, _metric_name, ewma, spread, n_obs,
      (select local_date from public.daily_health_summaries
       where user_id = target_user_id and source_scope = 'healthkit'
       order by local_date limit 1),
      values_arr[1], 1.0, 'baseline-v1'
    ) returning id into prior_history_id;

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
    elsif n_obs >= 4 then confidence := 'medium';
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

create function public.compute_daily_metrics(
  target_user_id uuid,
  target_date date,
  target_timezone text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  baseline record;
  today_health public.daily_health_summaries%rowtype;
  hrv_z numeric; rhr_z numeric; sleep_z numeric; strain_z numeric;
  composite_z numeric; recovery_score integer;
  sleep_efficiency numeric; restorative_pct numeric;
  sleep_quality_score integer;
  acwr numeric; monotony numeric; daily_strain numeric;
  weight_trend_7d numeric; weight_trend_28d numeric; weight_r2 numeric;
  macro_adherence_pct numeric;
  data_confidence text;
  active_target record;
  baseline_jsonb jsonb := '{}'::jsonb;
  scores_jsonb jsonb;
  missing_components text[] := '{}';
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

  if today_health.hrv_value_ms is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'hrv_sdnn_ms';
    if found and baseline.spread > 0 then
      hrv_z := (today_health.hrv_value_ms - baseline.baseline_value) / baseline.spread;
    else hrv_z := 0; end if;
    composite_z := composite_z + 0.55 * hrv_z;
    weight_total := weight_total + 0.55;
  else
    hrv_z := 0;
    missing_components := missing_components || ARRAY['hrv_sdnn']::text[];
  end if;

  if today_health.resting_heart_rate_bpm is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'resting_hr_bpm';
    if found and baseline.spread > 0 then
      rhr_z := -(today_health.resting_heart_rate_bpm - baseline.baseline_value) / baseline.spread;
    else rhr_z := 0; end if;
    composite_z := composite_z + 0.25 * rhr_z;
    weight_total := weight_total + 0.25;
  else
    rhr_z := 0;
    missing_components := missing_components || ARRAY['resting_hr']::text[];
  end if;

  if today_health.sleep_minutes is not null then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'sleep_minutes';
    if found and baseline.spread > 0 then
      sleep_z := (today_health.sleep_minutes - baseline.baseline_value) / baseline.spread;
    else sleep_z := 0; end if;
    composite_z := composite_z + 0.15 * sleep_z;
    weight_total := weight_total + 0.15;
  else
    sleep_z := 0;
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

  strain_z := 0;
  if today_health.id is not null then
    composite_z := composite_z + 0.05 * (-1.0 * strain_z);
    weight_total := weight_total + 0.05;
  end if;

  if weight_total > 0 then
    composite_z := composite_z / weight_total;
  end if;

  recovery_score := round(100.0 / (1.0 + exp(-1.6 * (composite_z + 0.2))));

  sleep_quality_score := null;
  if today_health.sleep_minutes is not null and today_health.sleep_minutes > 0 then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'sleep_minutes';

    sleep_efficiency := coalesce(
      (today_health.sleep_minutes - coalesce(today_health.sleep_awake_minutes, 0))
        ::numeric / today_health.sleep_minutes, 0
    );

    restorative_pct := coalesce(
      (coalesce(today_health.sleep_deep_minutes, 0)
       + coalesce(today_health.sleep_rem_minutes, 0))::numeric
       / today_health.sleep_minutes, 0
    );

    sleep_quality_score := round(
      case when sleep_z > 0 then 50 + (sleep_z * 15) else 50 + (sleep_z * 10) end
      + (sleep_efficiency * 20)
      + (restorative_pct * 20)
    );
    if sleep_quality_score > 100 then sleep_quality_score := 100; end if;
    if sleep_quality_score < 0 then sleep_quality_score := 0; end if;
  end if;

  acwr := null;
  monotony := null;
  begin
    select
      case when avg28 != 0 then round(avg7 / avg28, 2) end,
      case when stddev7 != 0 then round(avg7 / stddev7, 2) end
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
      'prev_strain_z', round(strain_z, 3)
    ),
    'sleep_quality', sleep_quality_score,
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

  return jsonb_build_object(
    'baselines', baseline_jsonb,
    'scores', scores_jsonb,
    'data_confidence', data_confidence
  );
end $$;

create function public.evaluate_change_eligibility(
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
    select round(avg(
      case when nt.calories > 0
        then least(day_calories / nt.calories * 100, 200)
      end
    )) into macro_adherence
    from (
      select m.local_date, coalesce(sum(mi.calories), 0) as day_calories
      from public.meals m
      join public.meal_items mi on mi.meal_id = m.id and mi.user_id = target_user_id
      where m.user_id = target_user_id
        and m.local_date >= coaching_date - 13
        and m.local_date <= coaching_date
        and m.status = 'confirmed'
        and mi.confirmed_at is not null
      group by m.local_date
    ) daily
    cross join (
      select calories from public.nutrition_target_sets
      where user_id = target_user_id and status = 'active' limit 1
    ) nt;
  end if;

  if weight_days_28d >= 14
     and macro_adherence is not null and macro_adherence >= 80
     and weight_r2 is not null and weight_r2 >= 0.3
  then
    nutrition_eligible := true;
    nutrition_reason := 'sufficient_evidence';
    nutrition_detail := weight_days_28d || ' weight days, '
      || macro_adherence || '% adherence, trend r2=' || round(weight_r2, 3);
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
        coalesce(macro_adherence, 0) || '% adherence (need 80%). '
      else ''
    end
    || case
      when weight_r2 is null or weight_r2 < 0.3 then
        'trend r2=' || coalesce(round(weight_r2, 3), 0) || ' (need >=0.3).'
      else ''
    end;
  end if;

  return jsonb_build_object(
    'eligibility_version', 'eligibility-v1',
    'training_change', jsonb_build_object(
      'eligible', training_eligible,
      'reason', training_reason,
      'detail', training_detail
    ),
    'nutrition_change', jsonb_build_object(
      'eligible', nutrition_eligible,
      'reason', nutrition_reason,
      'detail', nutrition_detail
    ),
    'general', case when training_eligible or nutrition_eligible
      then 'change_review_allowed' else 'maintain_only' end
  );
end $$;

create function public.recompute_stale_metrics()
returns integer language plpgsql security definer set search_path = '' as $$
declare
  stale record;
  processed integer := 0;
begin
  for stale in
    select dhs.user_id, dhs.local_date, dhs.timezone
    from public.daily_health_summaries dhs
    left join public.feature_snapshots fs
      on fs.user_id = dhs.user_id
      and fs.trigger_kind = 'daily'
      and fs.features->>'local_date' = dhs.local_date::text
      and fs.feature_engine_version = 'daily-v2'
    where dhs.source_scope = 'healthkit'
      and dhs.local_date = current_date - 1
      and fs.id is null
      and exists(select 1 from public.user_accounts ua where ua.id = dhs.user_id)
    limit 100
  loop
    begin
      perform public.compute_user_baselines(stale.user_id, stale.local_date);
      processed := processed + 1;
    exception when others then
      null;
    end;
  end loop;

  return processed;
end $$;

revoke all on function public.compute_winsorized_ewma(numeric[], integer),
  public.compute_user_baselines(uuid, date),
  public.compute_daily_metrics(uuid, date, text),
  public.evaluate_change_eligibility(uuid, date),
  public.recompute_stale_metrics()
  from public, anon, authenticated;
grant execute on function public.compute_user_baselines(uuid, date),
  public.compute_daily_metrics(uuid, date, text),
  public.evaluate_change_eligibility(uuid, date)
  to service_role;
grant execute on function public.recompute_stale_metrics()
  to service_role;
