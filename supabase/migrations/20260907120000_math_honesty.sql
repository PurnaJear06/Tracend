-- Pass 2 — Math honesty (2026-09-07).
--
-- Problem (review P2.5 #9, #10, #11 + production symptoms):
--   * HRV z-scored in raw ms: the long right tail of HRV distributions
--     dominated the MAD spread, so one high-SDNN day produced a monstrous z.
--     The noop reference (readiness_hrv_ln) folds in ln(ms); the same
--     relative deviation now yields the same z at any scale.
--   * ACWR computed from however few strain days existed (guard was only
--     avg28 != 0), so a single logged session produced ACWR = 1.0 — a
--     confident-looking number made of nothing. Monotony had the same
--     thin-history disease (production showed 5.57 on near-zero variance).
--   * Sleep sub-scores fabricated inputs: missing awake minutes coalesced
--     to 0 (= 100% efficiency), missing deep/rem stages coalesced to 0
--     (= 0% restorative), a single night coalesced to perfect consistency.
--   * Cold-start sleep: the <3-observation fold anchors the baseline to the
--     first value, so the first-ever night scored duration 100 against
--     itself. Below 7 nights (noop minNeedNights) the personal need falls
--     back to the 480-minute population floor.
--   * No plausibility bands at the fold: a single 400 ms SDNN or 350 kg
--     weight reading would fold straight into the baseline (up to the ±5σ
--     mercy of the MAD, which a small history cannot mount).
--
-- Fix (additive — create or replace + one-time UPDATE, no schema changes):
--   * HRV folds in ln domain. user_baselines.baseline_value for
--     hrv_sdnn_ms now stores ln(ms); spread is the MAD-based spread of the
--     ln values (relative). A one-time UPDATE converts the stored row
--     (spread via the first-order delta method, spread_ln ≈ spread_ms /
--     ewma_ms); the next compute re-folds exactly from raw history anyway,
--     and the read-only future-date guard reads the converted value in the
--     meantime. baseline_snapshot_jsonb in daily_computed_metrics keeps
--     historical raw-ms rows as the historical record they are.
--   * ACWR/monotony move to calendar windows with zero-filled rest days
--     (rest is load 0 — that is what a workload ratio means). ACWR is null
--     until >= 14 strain days in the 28-day window (noop minChronic);
--     monotony is null unless >= 4 strain days in the acute week AND
--     stddev > 0.
--   * Sleep sub-scores: a missing sub-input scores null and drops out of
--     the composite, which renormalizes over the remaining weights (the
--     recovery-composite pattern). sleep_breakdown is emitted only when
--     all four sub-scores are computable — the deployed Dart parser
--     requires every key when the object exists — and a new additive
--     scores key, sleep_breakdown_missing, names the dropped sub-scores.
--   * duration_score uses the personal sleep EWMA only after >= 7 nights;
--     below that the 480-minute population floor is the need.
--   * Plausibility bands at the fold AND at today's value: HRV 5–250 ms,
--     RHR 30–120 bpm, respiratory rate 8–25 bpm, sleep 1–960 min (a
--     0-minute night is the absence of an observation, not an observation
--     of zero sleep), weight 30–300 kg. Out-of-band observations are
--     rejected (reported missing), never clamped into the baseline.
--   * Version bumps per docs/ALGORITHMS.md §8: daily scoring JSON
--     2.1 → 2.2, daily brief RPC 1.2 → 1.3, baseline engine
--     baseline-v1 → baseline-v2 (history rows from v2 record fold-domain
--     baseline_value in ln ms; raw_value keeps the raw observation).

-- One-time: convert the stored HRV baseline to the ln domain. All SET
-- expressions read the pre-update row, so the spread conversion divides by
-- the raw-ms ewma before baseline_value itself is replaced.
update public.user_baselines
set baseline_value = ln(baseline_value),
    spread = spread / baseline_value
where metric_name = 'hrv_sdnn_ms'
  and baseline_value > 0;

create or replace function public.compute_user_baselines(
  target_user_id uuid,
  target_date date
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  _metric_name text;
  values_arr numeric[];
  raw_arr numeric[];
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
    -- Plausibility bands reject out-of-band observations before the fold
    -- (never clamp). HRV additionally folds in ln(ms) to stop the long
    -- upper tail dominating the MAD spread; raw_arr keeps the raw
    -- observation for the history audit trail.
    case _metric_name
      when 'hrv_sdnn_ms' then
        select array_agg(ln(hrv_value_ms) order by local_date),
               array_agg(hrv_value_ms order by local_date)
        into values_arr, raw_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and hrv_value_ms between 5 and 250;
      when 'resting_hr_bpm' then
        select array_agg(resting_heart_rate_bpm order by local_date) into values_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and resting_heart_rate_bpm between 30 and 120;
        raw_arr := values_arr;
      when 'sleep_minutes' then
        select array_agg(sleep_minutes order by local_date) into values_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and sleep_minutes between 1 and 960;
        raw_arr := values_arr;
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
        ) w
        where w.weight_kg between 30 and 300;
        raw_arr := values_arr;
      when 'resp_rate_bpm' then
        select array_agg(respiratory_rate_bpm order by local_date) into values_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and respiratory_rate_bpm between 8 and 25;
        raw_arr := values_arr;
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
        _obs_date, raw_arr[1], 1.0, 'baseline-v2'
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
          null, raw_arr[i], true,
          0, prior_history_id, 'baseline-v2'
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
        null, raw_arr[i],
        values_arr[i] <> winsorized,
        lambda, prior_history_id, 'baseline-v2'
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
  sleep_baseline_value numeric; sleep_baseline_n integer;
  sleep_composite numeric; sleep_weight_total numeric;
  sleep_missing_components text[] := '{}';
  sleep_consistency_stddev numeric; sleep_consistency_mean numeric;
  sleep_consistency_n integer;
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

  -- FUTURE-DATE GUARD: a target_date beyond current_date + 1 cannot have
  -- begun anywhere on Earth, so it is always a future page (Train weekday
  -- strip forward, week rail). Never fold baselines through it and never
  -- persist a computed row for it; return the read-only payload instead.
  if target_date > current_date + 1 then
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

    missing_components := array['hrv_sdnn', 'resting_hr', 'sleep_minutes',
      'resp_rate', 'prev_strain']::text[];

    scores_jsonb := jsonb_build_object(
      'recovery', null,
      'recovery_breakdown', jsonb_build_object(
        'hrv_z', 0,
        'rhr_z', 0,
        'sleep_z', 0,
        'resp_rate_z', 0,
        'prev_strain_z', 0,
        'missing_components', to_jsonb(missing_components)
      ),
      'sleep_quality', null,
      'sleep_breakdown', null,
      'sleep_breakdown_missing', null,
      'sleep_debt_minutes', null,
      'daily_strain', 0,
      'acwr', null,
      'training_monotony', null,
      'weight_trend_7d_kg_per_day', null,
      'weight_trend_28d_kg_per_day', null,
      'weight_trend_r2_28d', null,
      'macro_adherence_pct', null
    );

    return jsonb_build_object(
      'baselines', baseline_jsonb,
      'scores', scores_jsonb,
      'data_confidence', 'low'
    );
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

  -- HRV (weight 0.55), ln domain. The plausibility band gates both the
  -- fold (above) and today's value: an out-of-band reading is rejected,
  -- never z-scored. ln keeps the z scale-free — the same relative
  -- deviation from baseline yields the same z at any HRV level.
  if today_health.hrv_value_ms is not null
     and today_health.hrv_value_ms between 5 and 250 then
    select baseline_value, spread into baseline
    from public.user_baselines
    where user_id = target_user_id and metric_name = 'hrv_sdnn_ms';
    if found and baseline.spread > 0 then
      hrv_z := (ln(today_health.hrv_value_ms) - baseline.baseline_value) / baseline.spread;
      composite_z := composite_z + 0.55 * hrv_z;
      weight_total := weight_total + 0.55;
    else
      missing_components := missing_components || array['hrv_sdnn']::text[];
    end if;
  else
    missing_components := missing_components || array['hrv_sdnn']::text[];
  end if;

  -- Resting HR (weight 0.20). Lower than baseline is better recovery.
  if today_health.resting_heart_rate_bpm is not null
     and today_health.resting_heart_rate_bpm between 30 and 120 then
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
  if today_health.sleep_minutes is not null
     and today_health.sleep_minutes between 1 and 960 then
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
  if today_health.respiratory_rate_bpm is not null
     and today_health.respiratory_rate_bpm between 8 and 25 then
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

  -- Sleep quality: each sub-score is computed only from measured inputs;
  -- a missing sub-input scores null, drops out, and the composite
  -- renormalizes over the remaining weights. duration is always computable
  -- for a valid night (population floor fallback), efficiency needs
  -- awake minutes, restorative needs both deep and REM, consistency needs
  -- at least two nights in the window.
  sleep_quality_score := null;
  duration_score := null; efficiency_score := null;
  restorative_score := null; consistency_score := null;
  sleep_debt_minutes := null;
  sleep_missing_components := '{}';

  if today_health.sleep_minutes is not null
     and today_health.sleep_minutes between 1 and 960 then
    if today_health.sleep_awake_minutes is not null then
      sleep_efficiency := (
        today_health.sleep_minutes - today_health.sleep_awake_minutes
      )::numeric / today_health.sleep_minutes;
      efficiency_score := sleep_efficiency * 100;
    else
      sleep_missing_components := sleep_missing_components || array['efficiency']::text[];
    end if;

    if today_health.sleep_deep_minutes is not null
       and today_health.sleep_rem_minutes is not null then
      restorative_pct := (
        today_health.sleep_deep_minutes + today_health.sleep_rem_minutes
      )::numeric / today_health.sleep_minutes;
      restorative_score := restorative_pct * 100;
    else
      sleep_missing_components := sleep_missing_components || array['restorative']::text[];
    end if;

    -- Personal sleep need only after 7+ nights of history; before that a
    -- first-night-anchored EWMA would score every night against itself.
    select ub.baseline_value, ub.n_observations
    into sleep_baseline_value, sleep_baseline_n
    from public.user_baselines ub
    where ub.user_id = target_user_id and ub.metric_name = 'sleep_minutes';

    duration_score := greatest(0, least(100,
      today_health.sleep_minutes::numeric
        / case when sleep_baseline_n >= 7 and sleep_baseline_value > 0
          then sleep_baseline_value else 480 end
        * 100
    ));

    select stddev_samp(sleep_minutes), avg(sleep_minutes), count(*)
    into sleep_consistency_stddev, sleep_consistency_mean, sleep_consistency_n
    from public.daily_health_summaries
    where user_id = target_user_id
      and source_scope = 'healthkit'
      and local_date >= target_date - 6
      and local_date <= target_date
      and sleep_minutes is not null;

    if sleep_consistency_n >= 2
       and sleep_consistency_stddev is not null
       and sleep_consistency_mean is not null
       and sleep_consistency_mean > 0 then
      consistency_score := greatest(0,
        100 - ((sleep_consistency_stddev / sleep_consistency_mean) * 50));
    else
      sleep_missing_components := sleep_missing_components || array['consistency']::text[];
    end if;

    sleep_composite := 0;
    sleep_weight_total := 0;
    if duration_score is not null then
      sleep_composite := sleep_composite + 0.50 * duration_score;
      sleep_weight_total := sleep_weight_total + 0.50;
    end if;
    if efficiency_score is not null then
      sleep_composite := sleep_composite + 0.20 * efficiency_score;
      sleep_weight_total := sleep_weight_total + 0.20;
    end if;
    if restorative_score is not null then
      sleep_composite := sleep_composite + 0.20 * restorative_score;
      sleep_weight_total := sleep_weight_total + 0.20;
    end if;
    if consistency_score is not null then
      sleep_composite := sleep_composite + 0.10 * consistency_score;
      sleep_weight_total := sleep_weight_total + 0.10;
    end if;

    if sleep_weight_total > 0 then
      sleep_quality_score := round(sleep_composite / sleep_weight_total);
      if sleep_quality_score > 100 then sleep_quality_score := 100; end if;
      if sleep_quality_score < 0 then sleep_quality_score := 0; end if;
    end if;

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

  -- ACWR/monotony over calendar windows with zero-filled rest days (rest
  -- days are load 0 — that is what a workload ratio measures). ACWR needs
  -- >= 14 strain days in the 28-day chronic window (noop minChronic);
  -- monotony needs >= 4 strain days in the acute week and a non-zero
  -- stddev. Below the gates the answer is null, never a confident 1.0
  -- built from one or two sessions.
  acwr := null;
  monotony := null;
  begin
    select
      case when chronic_days >= 14 and avg28 is not null and avg28 > 0
        then round(avg7 / avg28, 2) end,
      case when acute_days >= 4 and stddev7 is not null and stddev7 > 0
        then round(avg7 / stddev7, 2) end
    into acwr, monotony
    from (
      select
        avg(strain) filter (where local_date >= target_date - 6) as avg7,
        stddev_samp(strain) filter (where local_date >= target_date - 6) as stddev7,
        avg(strain) as avg28,
        count(*) filter (where strain > 0 and local_date >= target_date - 6) as acute_days,
        count(*) filter (where strain > 0) as chronic_days
      from (
        select (g.dt)::date as local_date,
          coalesce(sum(ws.session_effort * ws.duration_seconds / 600.0), 0) as strain
        from generate_series(
          target_date - 27, target_date, interval '1 day'
        ) as g(dt)
        left join public.workout_sessions ws
          on ws.user_id = target_user_id
          and ws.local_date = (g.dt)::date
          and ws.state = 'completed'
          and ws.session_effort is not null
          and ws.duration_seconds is not null
          and ws.duration_seconds <= 10800
        group by (g.dt)::date
      ) days
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
    'sleep_breakdown', case
      when sleep_quality_score is not null
        and duration_score is not null and efficiency_score is not null
        and restorative_score is not null and consistency_score is not null
      then jsonb_build_object(
        'duration_score', round(duration_score, 1),
        'efficiency_score', round(efficiency_score, 1),
        'restorative_score', round(restorative_score, 1),
        'consistency_score', round(consistency_score, 1))
    end,
    'sleep_breakdown_missing', case when sleep_quality_score is not null
      then to_jsonb(sleep_missing_components) end,
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
    baseline_jsonb, eligibility_jsonb, '2.2', now()
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

-- Brief version bump (1.2 → 1.3): computed.scores gained the additive
-- sleep_breakdown_missing key and its semantics changed under the 2.2
-- scoring version. Body unchanged otherwise.
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
    return jsonb_build_object('schema_version', '1.3',
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
    'schema_version', '1.3',
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
