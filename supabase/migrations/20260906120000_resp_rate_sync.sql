-- Respiratory rate sync support (2026-09-06).
--
-- The daily_health_summaries column, present_types constraint, baseline loop,
-- and recovery composite already accept resp_rate (20260725), but the sync
-- write path did not: persist_health_sync rejected resp_rate requests, never
-- read respiratory_rate_bpm from the payload, and the health_sync_runs
-- constraint blocked the request type. This migration widens the write path.
-- Additive: 7-type requests from currently-deployed app builds stay valid.

alter table public.health_sync_runs
  drop constraint health_sync_runs_requested_types_check;

alter table public.health_sync_runs
  add constraint health_sync_runs_requested_types_check
  check (
    requested_types <@ array[
      'steps', 'active_energy', 'sleep', 'workouts', 'weight',
      'resting_heart_rate', 'hrv_sdnn', 'resp_rate'
    ]::text[]
  );

create or replace function public.persist_health_sync(
  target_user_id uuid,
  sync_idempotency_key uuid,
  request_start date,
  request_end date,
  request_types text[],
  response_types text[],
  summary_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_run public.health_sync_runs%rowtype;
  item jsonb;
  item_types text[];
  accepted integer := 0;
  result_status public.health_sync_status;
begin
  if target_user_id is null or not exists (
    select 1 from public.user_accounts where id = target_user_id
  ) then
    raise exception 'account not found' using errcode = 'P0002';
  end if;

  select * into existing_run
  from public.health_sync_runs
  where user_id = target_user_id
    and idempotency_key = sync_idempotency_key;

  if found then
    return jsonb_build_object(
      'sync_run_id', existing_run.id,
      'accepted_count', existing_run.accepted_count,
      'status', existing_run.status,
      'replayed', true
    );
  end if;

  if request_start > request_end or request_end - request_start > 31 then
    raise exception 'invalid date window' using errcode = '22023';
  end if;
  if request_types is null or cardinality(request_types) = 0
    or not request_types <@ array[
      'steps', 'active_energy', 'sleep', 'workouts', 'weight',
      'resting_heart_rate', 'hrv_sdnn', 'resp_rate'
    ]::text[]
  then
    raise exception 'invalid requested types' using errcode = '22023';
  end if;
  if cardinality(request_types) <> (
    select count(distinct value) from unnest(request_types) as value
  ) then
    raise exception 'duplicate requested types' using errcode = '22023';
  end if;
  if response_types is null or not response_types <@ request_types then
    raise exception 'invalid returned types' using errcode = '22023';
  end if;
  if cardinality(response_types) <> (
    select count(distinct value) from unnest(response_types) as value
  ) then
    raise exception 'duplicate returned types' using errcode = '22023';
  end if;
  if jsonb_typeof(summary_payload) <> 'array'
    or jsonb_array_length(summary_payload) > 32
  then
    raise exception 'invalid summary payload' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(summary_payload)
  loop
    item_types := array(select jsonb_array_elements_text(item->'present_types'));
    if (item->>'local_date')::date not between request_start and request_end
      or item->>'timezone' is null
      or length(item->>'timezone') not between 1 and 64
      or jsonb_typeof(item->'present_types') <> 'array'
      or jsonb_typeof(item->'source_refs') <> 'array'
      or jsonb_array_length(item->'source_refs') = 0
      or coalesce(item->>'source_checksum', '') !~ '^[0-9a-f]{64}$'
      or item->>'observed_through' is null
      or item_types is null
      or cardinality(item_types) = 0
      or not item_types <@ response_types
      or cardinality(item_types) <> (
        select count(distinct value) from unnest(item_types) as value
      )
      or (
        item->>'completeness' = 'complete'
      ) <> (
        item_types @> request_types and request_types @> item_types
      )
      or exists (
        select 1 from jsonb_array_elements(item->'source_refs') as reference
        where reference->>'type' is null
          or not (reference->>'type' = any(item_types))
          or coalesce(reference->>'source_id_hash', '') !~ '^[0-9a-f]{64}$'
          or coalesce(reference->>'sample_id_hash', '') !~ '^[0-9a-f]{64}$'
      )
      or exists (
        select 1 from unnest(item_types) as present_type
        where not exists (
          select 1 from jsonb_array_elements(item->'source_refs') as reference
          where reference->>'type' = present_type
        )
      )
    then
      raise exception 'invalid daily summary' using errcode = '22023';
    end if;

    insert into public.daily_health_summaries(
      user_id, local_date, timezone, steps, active_energy_kcal,
      sleep_minutes, sleep_awake_minutes, sleep_light_minutes,
      sleep_deep_minutes, sleep_rem_minutes, workout_count, workout_minutes,
      weight_kg, resting_heart_rate_bpm, hrv_value_ms, hrv_metric, hrv_unit,
      respiratory_rate_bpm,
      present_types,
      source_refs, source_checksum, completeness, observed_through,
      last_synced_at
    )
    values (
      target_user_id,
      (item->>'local_date')::date,
      item->>'timezone',
      nullif(item->>'steps', '')::integer,
      nullif(item->>'active_energy_kcal', '')::numeric,
      nullif(item->>'sleep_minutes', '')::integer,
      nullif(item->>'sleep_awake_minutes', '')::integer,
      nullif(item->>'sleep_light_minutes', '')::integer,
      nullif(item->>'sleep_deep_minutes', '')::integer,
      nullif(item->>'sleep_rem_minutes', '')::integer,
      nullif(item->>'workout_count', '')::smallint,
      nullif(item->>'workout_minutes', '')::integer,
      nullif(item->>'weight_kg', '')::numeric,
      nullif(item->>'resting_heart_rate_bpm', '')::numeric,
      nullif(item->>'hrv_value_ms', '')::numeric,
      nullif(item->>'hrv_metric', ''),
      nullif(item->>'hrv_unit', ''),
      nullif(item->>'respiratory_rate_bpm', '')::numeric,
      item_types,
      item->'source_refs',
      item->>'source_checksum',
      (item->>'completeness')::public.health_summary_completeness,
      (item->>'observed_through')::timestamptz,
      now()
    )
    on conflict (user_id, local_date, source_scope) do update
    set timezone = excluded.timezone,
        steps = excluded.steps,
        active_energy_kcal = excluded.active_energy_kcal,
        sleep_minutes = excluded.sleep_minutes,
        sleep_awake_minutes = excluded.sleep_awake_minutes,
        sleep_light_minutes = excluded.sleep_light_minutes,
        sleep_deep_minutes = excluded.sleep_deep_minutes,
        sleep_rem_minutes = excluded.sleep_rem_minutes,
        workout_count = excluded.workout_count,
        workout_minutes = excluded.workout_minutes,
        weight_kg = excluded.weight_kg,
        resting_heart_rate_bpm = excluded.resting_heart_rate_bpm,
        hrv_value_ms = excluded.hrv_value_ms,
        hrv_metric = excluded.hrv_metric,
        hrv_unit = excluded.hrv_unit,
        respiratory_rate_bpm = excluded.respiratory_rate_bpm,
        present_types = excluded.present_types,
        source_refs = excluded.source_refs,
        source_checksum = excluded.source_checksum,
        completeness = excluded.completeness,
        observed_through = excluded.observed_through,
        last_synced_at = now();
    accepted := accepted + 1;
  end loop;

  result_status := case
    when response_types @> request_types and request_types @> response_types
      then 'completed'::public.health_sync_status
    else 'partial'::public.health_sync_status
  end;

  insert into public.health_sync_runs(
    user_id, idempotency_key, requested_start, requested_end,
    requested_types, returned_types, accepted_count, rejected_count, status
  )
  values (
    target_user_id, sync_idempotency_key, request_start, request_end,
    request_types, response_types, accepted, 0, result_status
  )
  returning * into existing_run;

  return jsonb_build_object(
    'sync_run_id', existing_run.id,
    'accepted_count', accepted,
    'status', result_status,
    'replayed', false
  );
end;
$$;
