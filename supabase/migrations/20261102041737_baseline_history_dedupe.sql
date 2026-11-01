-- Baseline history dedupe (pre-beta audit P1-1). compute_user_baselines wrote the whole
-- metric_baseline_history trail again on every call: one row per past observation for each of the seven
-- metrics, from every brief, Coach turn, daily decision and the 06:00 recompute. In production that was
-- 157,165 rows (76 MB of a 131 MB database) for one athlete with about 200 observations. Only the first
-- row of each call carried a date (and the wrong one: the athlete's first HealthKit day, whatever the
-- metric), so the trail could not be read by date. Account deletion went quadratic through the unindexed
-- prior_baseline_id self-reference, the data export neared its size cap, and concurrent recomputes queued
-- on the inserts.
--
-- The fix makes the trail what DATA_MODEL.md says it is: one row per user, metric and observation day,
-- the state after that day's observation.
--
--   1. prior_baseline_id loses its foreign key and is no longer written. The day orders the trail, so the
--      linked list adds nothing, and with no table referencing metric_baseline_history a deletion is one
--      indexed pass. Nothing reads the column (the export copies it as it is); a later cleanup migration
--      drops it, after this one is live (the two-step rule).
--   2. The old trail is cleared. Its rows have no day to key them by, so none of them is a row the fixed
--      function would keep; step 5 writes the trail again from the athlete's own data. Clearing is safe
--      under the additive rule: the trail is derived data (recomputed from daily_health_summaries and
--      body_measurements), the app never reads it (only the privacy export does, by its columns), and
--      no column, type or RPC that build 920 or a deployed function uses changes.
--   3. observation_date is required and unique per user and metric. The unique key replaces the old
--      (user_id, metric_name, observation_date desc) index, which it covers.
--   4. compute_user_baselines (latest definition 20261004160000_recovery_modes.sql) collects the trail
--      during the fold and reconciles it once per metric: a day no longer observed loses its row (HealthKit
--      re-sends the last days), and only rows that differ from the fold are written (a new day, a revised
--      day and every later day it moved). A repeated call writes and locks nothing. A fold for an earlier
--      day than the trail's newest (the 06:00 recompute of yesterday, a past brief) leaves the trail alone.
--      Two weigh-ins on one day are one row, the state after the later one; same-day weigh-ins now fold
--      in entry order (created_at, then id), so that row is always the same entry. Each row records the
--      observation count and the baseline spread after that observation, as documented (it recorded the
--      whole call's count and the Winsor scale). user_baselines and every score are computed as before,
--      except that same-day weigh-in order no longer varies; nothing reads the trail back.
--   5. Every athlete who could have a trail (a baseline row, computed metrics or a weigh-in) gets it
--      rebuilt by one call at their local today, the day their next brief folds through.
--
-- Deploy: steps 1 to 3 take the table lock for well under a second (the table is empty from step 2 on),
-- and step 5 is one fold per athlete (one in production today). The app's history writes wait for the
-- commit; nothing in the app reads the table.

-- 1. No self-reference -------------------------------------------------------------------------------------

alter table public.metric_baseline_history
  drop constraint metric_baseline_history_prior_baseline_id_fkey;

comment on column public.metric_baseline_history.prior_baseline_id is
  'Not written since 20261102041737_baseline_history_dedupe; a later migration drops it.';

-- 2. Clear the old trail -----------------------------------------------------------------------------------

truncate table public.metric_baseline_history;

-- 3. One row per observation day ---------------------------------------------------------------------------

drop index public.metric_baseline_history_user_metric_date;

alter table public.metric_baseline_history
  alter column observation_date set not null,
  add constraint metric_baseline_history_observation_key
    unique (user_id, metric_name, observation_date);

-- 4. Write each observation once ---------------------------------------------------------------------------

create or replace function public.compute_user_baselines(
  target_user_id uuid,
  target_date date
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  _metric_name text;
  values_arr numeric[];
  raw_arr numeric[];
  dates_arr date[];
  baseline numeric;
  median numeric;
  mad numeric;
  spread numeric;
  spread_ewma numeric;
  floor_spread numeric;
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
  i integer;
  newest_obs_date date;
  trail_baselines numeric[];
  trail_spreads numeric[];
  trail_winsorized boolean[];
  trail_rejected boolean[];
  trail_lambdas numeric[];
  trail_end date;
  trail_current boolean;
begin
  if target_user_id is null
    or not exists(select 1 from public.user_accounts where id = target_user_id)
  then raise exception 'account not found' using errcode = 'P0002';
  end if;

  -- One fold per athlete at a time: two overlapping recomputes for
  -- different days could otherwise both judge the trail current, and the
  -- earlier day's fold would delete the newer day's rows.
  perform pg_advisory_xact_lock(
    hashtextextended('tracend.compute_user_baselines:' || target_user_id::text, 0));

  for _metric_name in
    select unnest(array['hrv_sdnn_ms','resting_hr_bpm','sleep_minutes','weight_kg','resp_rate_bpm',
                         'hrv_sleep_ms','hrv_morning_ms'])
  loop
    -- Plausibility bands reject out-of-band observations before the fold
    -- (never clamp). HRV additionally folds in ln(ms) to stop the long
    -- upper tail dominating the MAD spread; raw_arr keeps the raw
    -- observation for the history audit trail.
    case _metric_name
      when 'hrv_sdnn_ms' then
        select array_agg(ln(hrv_value_ms) order by local_date),
               array_agg(hrv_value_ms order by local_date),
               array_agg(local_date order by local_date)
        into values_arr, raw_arr, dates_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and hrv_value_ms between 5 and 250;
      -- Night and morning HRV fold apart (2026-10-04): a reading taken
      -- asleep and one taken awake are different measurements, so each is
      -- only ever compared with its own kind. Same ln domain and band.
      when 'hrv_sleep_ms' then
        select array_agg(ln(hrv_sleep_ms) order by local_date),
               array_agg(hrv_sleep_ms order by local_date),
               array_agg(local_date order by local_date)
        into values_arr, raw_arr, dates_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and hrv_sleep_ms between 5 and 250;
      when 'hrv_morning_ms' then
        select array_agg(ln(hrv_morning_ms) order by local_date),
               array_agg(hrv_morning_ms order by local_date),
               array_agg(local_date order by local_date)
        into values_arr, raw_arr, dates_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and hrv_morning_ms between 5 and 250;
      -- Resting HR folds through yesterday: recovery scores yesterday's
      -- final value, and today's, which Apple revises through the day,
      -- must not move the baseline it is compared with.
      when 'resting_hr_bpm' then
        select array_agg(resting_heart_rate_bpm order by local_date),
               array_agg(local_date order by local_date)
        into values_arr, dates_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date < target_date
          and resting_heart_rate_bpm between 30 and 120;
        raw_arr := values_arr;
      when 'sleep_minutes' then
        select array_agg(sleep_minutes order by local_date),
               array_agg(local_date order by local_date)
        into values_arr, dates_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and sleep_minutes between 1 and 960;
        raw_arr := values_arr;
      when 'weight_kg' then
        -- Weigh-ins on one day fold in the order they were entered
        -- (created_at, then id), so the day's last entry is always the
        -- same one. Identical same-day entries still count once.
        select array_agg(w.weight_kg order by w.measured_on, w.entered_at, w.entry_id),
               array_agg(w.measured_on order by w.measured_on, w.entered_at, w.entry_id)
        into values_arr, dates_arr
        from (
          (select distinct on (measured_on, weight_kg)
             measured_on, weight_kg, created_at as entered_at, id as entry_id
           from public.body_measurements
           where user_id = target_user_id and measured_on <= target_date
           order by measured_on, weight_kg, created_at desc, id desc)
          union all
          select local_date, weight_kg, last_synced_at, id
          from public.daily_health_summaries
          where user_id = target_user_id and source_scope = 'healthkit'
            and local_date <= target_date and weight_kg is not null
            and local_date not in (
              select measured_on from public.body_measurements
              where user_id = target_user_id
            )
        ) w
        where w.weight_kg between 30 and 300;
        raw_arr := values_arr;
      when 'resp_rate_bpm' then
        select array_agg(respiratory_rate_bpm order by local_date),
               array_agg(local_date order by local_date)
        into values_arr, dates_arr
        from public.daily_health_summaries
        where user_id = target_user_id
          and source_scope = 'healthkit'
          and local_date <= target_date
          and respiratory_rate_bpm between 8 and 25;
        raw_arr := values_arr;
    end case;

    -- The trail is the fold at the athlete's newest day. A fold for an
    -- earlier day (the 06:00 recompute of yesterday, a past brief) leaves
    -- it alone: rows past the fold's last foldable day mean a newer fold
    -- wrote it. Resting HR folds through the day before target_date.
    trail_end := case when _metric_name = 'resting_hr_bpm'
      then target_date - 1 else target_date end;
    trail_current := not exists (
      select 1 from public.metric_baseline_history h
      where h.user_id = target_user_id
        and h.metric_name = _metric_name
        and h.observation_date > trail_end
    );

    if values_arr is null or array_length(values_arr, 1) < 3 then
      -- Below three observations there is no fold, so no trail.
      if trail_current then
        delete from public.metric_baseline_history h
        where h.user_id = target_user_id and h.metric_name = _metric_name;
      end if;
      insert into public.user_baselines (
        user_id, metric_name, baseline_value, spread, n_observations,
        confidence, last_observation_date
      ) values (
        target_user_id, _metric_name, coalesce(values_arr[1], 0),
        public.baseline_floor_spread(_metric_name),
        coalesce(array_length(values_arr, 1), 0),
        'cold_start',
        -- Zero observations = never observed: null date, so the brief
        -- reports null age_days (never observed is not "observed today").
        -- One or two observations still stamp the true observation date.
        case when array_length(values_arr, 1) is null
          then null
          else dates_arr[array_length(values_arr, 1)] end
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

    -- Winsor bounds use the full-history scale so early bands are not
    -- pathological on tiny histories; the SPREAD STORED as the baseline is
    -- the recent-window tracker below (Pass 3a).
    spread := 1.4826 * coalesce(mad, 0);
    floor_spread := public.baseline_floor_spread(_metric_name);
    spread := greatest(floor_spread, spread);
    lower_bound := median - 3.0 * spread;
    upper_bound := median + 3.0 * spread;
    hard_lower := median - 5.0 * spread;
    hard_upper := median + 5.0 * spread;

    ewma := values_arr[1];
    spread_ewma := spread;

    -- The trail: the state after each observation, collected through the
    -- fold and written once at the end of the metric (below).
    trail_baselines := array[ewma];
    trail_spreads := array[spread_ewma];
    trail_winsorized := array[false];
    trail_rejected := array[false];
    trail_lambdas := array[1.0];

    for i in 2..n_obs loop
      if values_arr[i] < hard_lower or values_arr[i] > hard_upper then
        trail_baselines := trail_baselines || ewma;
        trail_spreads := trail_spreads || spread_ewma;
        trail_winsorized := trail_winsorized || false;
        trail_rejected := trail_rejected || true;
        trail_lambdas := trail_lambdas || 0::numeric;
        continue;
      end if;

      winsorized := greatest(lower_bound, least(upper_bound, values_arr[i]));

      if i <= 8 then half_life_days := 3; else half_life_days := 14; end if;
      lambda := 1.0 - (0.5 ^ (1.0 / half_life_days));

      ewma := lambda * winsorized + (1.0 - lambda) * ewma;

      -- Spread tracks |deviation| with a 21-day half-life (noop):
      -- lambda = 1 - 0.5^(1/21) ~= 0.0323; 0.9670/0.0330 are the rounded
      -- complements. Input is the raw deviation from the running center
      -- (the same value the Winsor bounds clamp for the center update), the
      -- floor keeps near-identical histories from amplifying noise into
      -- dramatic z-scores.
      spread_ewma := greatest(
        floor_spread,
        0.9670 * spread_ewma + 0.0330 * abs(values_arr[i] - ewma)
      );

      trail_baselines := trail_baselines || ewma;
      trail_spreads := trail_spreads || spread_ewma;
      trail_winsorized := trail_winsorized || (values_arr[i] <> winsorized);
      trail_rejected := trail_rejected || false;
      trail_lambdas := trail_lambdas || lambda;
    end loop;

    -- One history row per user, metric and observation day, matching this
    -- fold: a day no longer observed (HealthKit re-sends recent days) loses
    -- its row, and a row is written only where it differs from the fold
    -- (a new day, a revised day and the later days it moved). A repeated
    -- call writes and locks nothing. Two weigh-ins on one day are one row:
    -- the state after the later one.
    if trail_current then
      delete from public.metric_baseline_history h
      where h.user_id = target_user_id
        and h.metric_name = _metric_name
        and h.observation_date <> all(dates_arr);

      insert into public.metric_baseline_history (
        user_id, metric_name, baseline_value, spread, n_observations,
        observation_date, raw_value, was_winsorized, was_outlier_rejected,
        lambda_used, engine_version
      )
      select target_user_id, _metric_name, o.baseline_value, o.spread,
        o.n_observations::integer, o.observation_date, o.raw_value,
        o.was_winsorized, o.was_outlier_rejected, o.lambda_used, 'baseline-v2'
      from (
        select distinct on (t.observation_date) t.*
        from unnest(dates_arr, raw_arr, trail_baselines, trail_spreads,
                    trail_winsorized, trail_rejected, trail_lambdas)
          with ordinality as t(observation_date, raw_value, baseline_value,
                               spread, was_winsorized, was_outlier_rejected,
                               lambda_used, n_observations)
        order by t.observation_date, t.n_observations desc
      ) o
      where not exists (
        select 1 from public.metric_baseline_history h
        where h.user_id = target_user_id
          and h.metric_name = _metric_name
          and h.observation_date = o.observation_date
          and (h.baseline_value, h.spread, h.n_observations, h.raw_value,
               h.was_winsorized, h.was_outlier_rejected, h.lambda_used,
               h.engine_version)
            is not distinct from
              (o.baseline_value, o.spread, o.n_observations::integer,
               o.raw_value, o.was_winsorized, o.was_outlier_rejected,
               o.lambda_used, 'baseline-v2'::text)
      )
      on conflict (user_id, metric_name, observation_date) do update set
        baseline_value = excluded.baseline_value,
        spread = excluded.spread,
        n_observations = excluded.n_observations,
        raw_value = excluded.raw_value,
        was_winsorized = excluded.was_winsorized,
        was_outlier_rejected = excluded.was_outlier_rejected,
        lambda_used = excluded.lambda_used,
        engine_version = excluded.engine_version
      where (public.metric_baseline_history.baseline_value,
             public.metric_baseline_history.spread,
             public.metric_baseline_history.n_observations,
             public.metric_baseline_history.raw_value,
             public.metric_baseline_history.was_winsorized,
             public.metric_baseline_history.was_outlier_rejected,
             public.metric_baseline_history.lambda_used,
             public.metric_baseline_history.engine_version)
        is distinct from
          (excluded.baseline_value, excluded.spread, excluded.n_observations,
           excluded.raw_value, excluded.was_winsorized,
           excluded.was_outlier_rejected, excluded.lambda_used,
           excluded.engine_version);
    end if;

    baseline := public.compute_winsorized_ewma(values_arr, n_obs);
    spread := spread_ewma;

    if n_obs >= 14 then confidence := 'high';
    elsif n_obs >= 7 then confidence := 'medium';
    else confidence := 'low';
    end if;

    newest_obs_date := dates_arr[n_obs];
    insert into public.user_baselines (
      user_id, metric_name, baseline_value, spread, n_observations,
      confidence, last_observation_date
    ) values (
      target_user_id, _metric_name, baseline, spread, n_obs,
      confidence, newest_obs_date
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


-- 5. Rebuild the trail -------------------------------------------------------------------------------------

do $$
declare
  athlete uuid;
begin
  for athlete in
    select b.user_id from public.user_baselines b
    union
    select m.user_id from public.daily_computed_metrics m
    union
    select w.user_id from public.body_measurements w
  loop
    perform public.compute_user_baselines(athlete, private.local_date_for(athlete));
  end loop;
end $$;
