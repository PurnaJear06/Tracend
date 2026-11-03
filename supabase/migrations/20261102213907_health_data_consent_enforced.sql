-- Apple Health is stored only for an athlete whose newest `health_data` consent record is a
-- grant. Any notice version counts: a new page version is asked again by the app's re-consent
-- screen. A missing or withdrawn record is refused with SQLSTATE P0403, which health-sync
-- answers as 403 `health_consent_required`. Each function below is its latest earlier definition
-- plus the one check; grants are unchanged (the earlier migrations' revoke and grant statements
-- still hold for `create or replace`).

create function private.health_data_consent_granted(target_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select c.action = 'granted' from public.consent_records c
    where c.user_id = target_user_id and c.consent_type = 'health_data'
    order by c.created_at desc, c.id desc limit 1), false);
$$;
revoke all on function private.health_data_consent_granted(uuid) from public, anon, authenticated;

-- The service-role path of health-sync (summaries and workouts).
create or replace function public.persist_health_sync_v2(
  target_user_id uuid,sync_idempotency_key uuid,request_start date,request_end date,
  request_types text[],response_types text[],summary_payload jsonb,workout_payload jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; workout_result jsonb;
begin
  if auth.role()<>'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  if not private.health_data_consent_granted(target_user_id) then
    raise exception 'health data consent required' using errcode='P0403';
  end if;
  -- One sync per athlete at a time, so the hourly count and the replay check
  -- see every earlier sync.
  perform pg_advisory_xact_lock(hashtextextended('tracend.health_sync:'||target_user_id::text,0));
  if exists(select 1 from public.health_sync_runs
    where user_id=target_user_id and idempotency_key=sync_idempotency_key) then
    return public.persist_health_sync(target_user_id,sync_idempotency_key,request_start,request_end,
      request_types,response_types,summary_payload) || jsonb_build_object('workout_reference_count',0);
  end if;
  if request_end > current_date + 2 then
    raise exception 'invalid date window' using errcode='22023';
  end if;
  if (select count(*) from public.health_sync_runs
    where user_id=target_user_id and created_at > now() - interval '1 hour') >= 120 then
    raise exception 'health sync limit reached' using errcode='54000';
  end if;
  if jsonb_typeof(summary_payload)='array' and exists(
    select 1 from jsonb_array_elements(summary_payload) summary
    where jsonb_typeof(summary->'source_refs')='array'
      and jsonb_array_length(summary->'source_refs') > 20000) then
    raise exception 'invalid health summary' using errcode='22023';
  end if;
  if jsonb_typeof(workout_payload)='array' and exists(
    select 1 from jsonb_array_elements(workout_payload) workout
    where coalesce(workout->>'local_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or (workout->>'local_date')::date not between request_start - 1 and request_end + 1) then
    raise exception 'invalid health workout' using errcode='22023';
  end if;
  result:=public.persist_health_sync(target_user_id,sync_idempotency_key,request_start,request_end,request_types,response_types,summary_payload);
  workout_result:=public.persist_health_workouts(target_user_id,workout_payload);
  return result||jsonb_build_object('workout_reference_count',(workout_result->>'accepted_count')::integer);
end $$;

-- The monthly totals sent at onboarding and once a month.
create or replace function public.save_health_history(months jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  this_month date;
  row_value jsonb;
  saved integer := 0;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if not private.health_data_consent_granted(auth.uid()) then
    raise exception 'health data consent required' using errcode = 'P0403';
  end if;
  if jsonb_typeof(months) <> 'array' or jsonb_array_length(months) > 12 then
    raise exception 'months must be a list of at most 12' using errcode = '22023';
  end if;
  this_month := date_trunc('month', private.local_date_for(auth.uid()))::date;
  for row_value in select value from jsonb_array_elements(months) loop
    if jsonb_typeof(row_value) <> 'object'
      or (row_value ->> 'month') !~ '^\d{4}-\d{2}-01$'
      or (row_value ->> 'month')::date >= this_month
      or (row_value ->> 'month')::date < (this_month - interval '12 months')::date then
      raise exception 'only completed months of the last year' using errcode = '22023';
    end if;
    insert into public.health_history_months(
      user_id, month, workouts, strength_workouts, workout_minutes, sleep_nights,
      sleep_minutes_avg, weight_days, weight_kg_avg, data_days, first_data_date, last_data_date
    ) values (
      auth.uid(), (row_value ->> 'month')::date,
      (row_value ->> 'workouts')::smallint, (row_value ->> 'strength_workouts')::smallint,
      (row_value ->> 'workout_minutes')::integer, (row_value ->> 'sleep_nights')::smallint,
      (row_value ->> 'sleep_minutes_avg')::smallint, (row_value ->> 'weight_days')::smallint,
      (row_value ->> 'weight_kg_avg')::numeric, (row_value ->> 'data_days')::smallint,
      (row_value ->> 'first_data_date')::date, (row_value ->> 'last_data_date')::date
    )
    on conflict (user_id, month) do update set
      workouts = excluded.workouts,
      strength_workouts = excluded.strength_workouts,
      workout_minutes = excluded.workout_minutes,
      sleep_nights = excluded.sleep_nights,
      sleep_minutes_avg = excluded.sleep_minutes_avg,
      weight_days = excluded.weight_days,
      weight_kg_avg = excluded.weight_kg_avg,
      data_days = excluded.data_days,
      first_data_date = excluded.first_data_date,
      last_data_date = excluded.last_data_date,
      synced_at = now();
    saved := saved + 1;
  end loop;
  return jsonb_build_object('schema_version', '1.0', 'saved', saved);
end $$;

-- Heart-rate summaries of workout sets.
create or replace function public.persist_set_heart_rate_v1(session_id uuid, summaries jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  target public.workout_sessions%rowtype; item jsonb; stored_set uuid; saved integer := 0;
  start_value smallint; peak_value smallint; end_value smallint; drop_30_value smallint;
  drop_60_value smallint; coverage_value numeric; samples_value integer; source_value text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if not private.health_data_consent_granted(auth.uid()) then
    raise exception 'health data consent required' using errcode = 'P0403';
  end if;
  select * into target from public.workout_sessions w
  where w.id = persist_set_heart_rate_v1.session_id and w.user_id = auth.uid();
  if not found then raise exception 'session not found' using errcode = 'P0002'; end if;
  if target.state = 'abandoned' then raise exception 'session was discarded' using errcode = '55000'; end if;
  if jsonb_typeof(summaries) <> 'array' or jsonb_array_length(summaries) not between 1 and 100 then
    raise exception 'summaries must be a list of 1 to 100 sets' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(summaries) loop
    if jsonb_typeof(item) <> 'object' then
      raise exception 'each summary must be an object' using errcode = '22023';
    end if;
    select s.id into stored_set
    from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id and p.user_id = s.user_id
    where p.workout_session_id = target.id and s.user_id = auth.uid() and s.completed
      and p.exercise_order = private.set_heart_rate_value(item->'exercise_order', 1, 100, 'exercise_order', true, true)
      and s.set_number = private.set_heart_rate_value(item->'set_number', 1, 20, 'set_number', true, true);
    if stored_set is null then raise exception 'unknown or unfinished set' using errcode = '22023'; end if;
    start_value := private.set_heart_rate_value(item->'start_bpm', 30, 250, 'start_bpm', false, true);
    peak_value := private.set_heart_rate_value(item->'peak_bpm', 30, 250, 'peak_bpm', false, true);
    end_value := private.set_heart_rate_value(item->'end_bpm', 30, 250, 'end_bpm', false, true);
    drop_30_value := private.set_heart_rate_value(item->'drop_30s_bpm', -220, 220, 'drop_30s_bpm', false, true);
    drop_60_value := private.set_heart_rate_value(item->'drop_60s_bpm', -220, 220, 'drop_60s_bpm', false, true);
    coverage_value := private.set_heart_rate_value(item->'coverage', 0, 1, 'coverage', true, false);
    samples_value := private.set_heart_rate_value(item->'sample_count', 1, 5000, 'sample_count', true, true);
    if jsonb_typeof(item->'source') is distinct from 'string'
       or item->>'source' not in ('watch_workout', 'background') then
      raise exception 'source must be watch_workout or background' using errcode = '22023';
    end if;
    source_value := item->>'source';
    if peak_value < start_value or peak_value < end_value then
      raise exception 'the peak cannot be below the start or the end' using errcode = '22023';
    end if;
    insert into public.exercise_set_heart_rate as h(
      exercise_set_id, user_id, start_bpm, peak_bpm, end_bpm, drop_30s_bpm, drop_60s_bpm,
      coverage, sample_count, source)
    values (stored_set, auth.uid(), start_value, peak_value, end_value, drop_30_value,
      drop_60_value, coverage_value, samples_value, source_value)
    on conflict (exercise_set_id) do update set
      start_bpm = excluded.start_bpm, peak_bpm = excluded.peak_bpm, end_bpm = excluded.end_bpm,
      drop_30s_bpm = excluded.drop_30s_bpm, drop_60s_bpm = excluded.drop_60s_bpm,
      coverage = excluded.coverage, sample_count = excluded.sample_count,
      source = excluded.source, updated_at = now();
    saved := saved + 1;
  end loop;
  return jsonb_build_object('schema_version', '1.0', 'session_id', target.id, 'saved', saved);
end $$;

-- Sleeping heart rate of recent nights.
create or replace function public.persist_sleeping_heart_rate_v1(nights jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  item jsonb; night_date date; median_value smallint; lowest_value smallint; samples_value integer;
  asleep_value integer; coverage_value numeric; saved integer := 0; skipped integer := 0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if not private.health_data_consent_granted(auth.uid()) then
    raise exception 'health data consent required' using errcode = 'P0403';
  end if;
  if nights is null or jsonb_typeof(nights) <> 'array' or jsonb_array_length(nights) not between 1 and 14 then
    raise exception 'nights must be a list of 1 to 14 nights' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(nights) loop
    begin
      if jsonb_typeof(item) <> 'object' then
        raise exception 'each night must be an object' using errcode = '22023';
      end if;
      if jsonb_typeof(item->'local_date') is distinct from 'string'
         or item->>'local_date' !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'local_date must be a date' using errcode = '22023';
      end if;
      begin
        night_date := (item->>'local_date')::date;
      exception when others then
        raise exception 'local_date must be a date' using errcode = '22023';
      end;
      if night_date > current_date + 1 or night_date < current_date - 400 then
        raise exception 'local_date is out of range' using errcode = '22023';
      end if;
      median_value := private.set_heart_rate_value(item->'median_bpm', 30, 200, 'median_bpm', true, true);
      lowest_value := private.set_heart_rate_value(item->'lowest_bpm', 30, 200, 'lowest_bpm', true, true);
      samples_value := private.set_heart_rate_value(item->'sample_count', 1, 20000, 'sample_count', true, true);
      asleep_value := private.set_heart_rate_value(item->'asleep_minutes', 1, 1440, 'asleep_minutes', true, true);
      coverage_value := private.set_heart_rate_value(item->'coverage', 0, 1, 'coverage', true, false);
      if lowest_value > median_value then
        raise exception 'the lowest cannot be above the median' using errcode = '22023';
      end if;
      insert into public.sleeping_heart_rate_nights as n(
        user_id, local_date, median_bpm, lowest_bpm, sample_count, asleep_minutes, coverage)
      values (auth.uid(), night_date, median_value, lowest_value, samples_value, asleep_value,
        coverage_value)
      on conflict (user_id, local_date) do update set
        median_bpm = excluded.median_bpm, lowest_bpm = excluded.lowest_bpm,
        sample_count = excluded.sample_count, asleep_minutes = excluded.asleep_minutes,
        coverage = excluded.coverage, updated_at = now();
      saved := saved + 1;
    exception when sqlstate '22023' then
      skipped := skipped + 1;
    end;
  end loop;
  return jsonb_build_object('schema_version', '1.0', 'saved', saved, 'skipped', skipped);
end $$;
