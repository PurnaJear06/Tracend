create type public.health_sync_status as enum ('completed', 'partial', 'failed');
create type public.health_summary_completeness as enum ('complete', 'partial');

create table public.health_sync_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  idempotency_key uuid not null,
  requested_start date not null,
  requested_end date not null,
  requested_types text[] not null,
  returned_types text[] not null,
  accepted_count integer not null check (accepted_count >= 0),
  rejected_count integer not null check (rejected_count >= 0),
  status public.health_sync_status not null,
  sanitized_error_code text check (
    sanitized_error_code is null or length(sanitized_error_code) between 1 and 80
  ),
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key),
  check (requested_start <= requested_end),
  check (requested_end - requested_start <= 31),
  check (
    requested_types <@ array[
      'steps', 'active_energy', 'sleep', 'workouts', 'weight',
      'resting_heart_rate', 'hrv_sdnn'
    ]::text[]
  ),
  check (returned_types <@ requested_types)
);

create table public.daily_health_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  local_date date not null,
  timezone text not null check (length(timezone) between 1 and 64),
  source_scope text not null default 'healthkit' check (source_scope = 'healthkit'),
  steps integer check (steps between 0 and 200000),
  active_energy_kcal numeric(8,2) check (active_energy_kcal between 0 and 30000),
  sleep_minutes integer check (sleep_minutes between 0 and 1440),
  sleep_awake_minutes integer check (sleep_awake_minutes between 0 and 1440),
  sleep_light_minutes integer check (sleep_light_minutes between 0 and 1440),
  sleep_deep_minutes integer check (sleep_deep_minutes between 0 and 1440),
  sleep_rem_minutes integer check (sleep_rem_minutes between 0 and 1440),
  workout_count smallint check (workout_count between 0 and 50),
  workout_minutes integer check (workout_minutes between 0 and 1440),
  weight_kg numeric(6,2) check (weight_kg between 20 and 500),
  resting_heart_rate_bpm numeric(5,2) check (
    resting_heart_rate_bpm between 20 and 250
  ),
  hrv_value_ms numeric(7,2) check (hrv_value_ms between 0 and 1000),
  hrv_metric text check (hrv_metric is null or hrv_metric = 'sdnn'),
  hrv_unit text check (hrv_unit is null or hrv_unit = 'ms'),
  present_types text[] not null,
  source_refs jsonb not null default '[]'::jsonb check (
    jsonb_typeof(source_refs) = 'array'
  ),
  source_checksum text not null check (source_checksum ~ '^[0-9a-f]{64}$'),
  completeness public.health_summary_completeness not null,
  observed_through timestamptz not null,
  last_synced_at timestamptz not null default now(),
  unique (user_id, local_date, source_scope),
  unique (id, user_id),
  check (
    present_types <@ array[
      'steps', 'active_energy', 'sleep', 'workouts', 'weight',
      'resting_heart_rate', 'hrv_sdnn'
    ]::text[]
  ),
  check (cardinality(present_types) > 0),
  check (
    sleep_minutes is not null
    or (
      sleep_awake_minutes is null and sleep_light_minutes is null
      and sleep_deep_minutes is null and sleep_rem_minutes is null
    )
  ),
  check (
    coalesce(sleep_light_minutes, 0) + coalesce(sleep_deep_minutes, 0)
      + coalesce(sleep_rem_minutes, 0) <= 1440
  ),
  check (
    (hrv_value_ms is null) = (hrv_metric is null)
    and (hrv_value_ms is null) = (hrv_unit is null)
  )
);

create index health_sync_runs_user_completed
on public.health_sync_runs(user_id, completed_at desc);

create index daily_health_summaries_user_date
on public.daily_health_summaries(user_id, local_date desc);

alter table public.health_sync_runs enable row level security;
alter table public.health_sync_runs force row level security;
alter table public.daily_health_summaries enable row level security;
alter table public.daily_health_summaries force row level security;

create policy health_sync_runs_own_read
on public.health_sync_runs for select to authenticated
using (user_id = (select auth.uid()));

create policy daily_health_summaries_own_read
on public.daily_health_summaries for select to authenticated
using (user_id = (select auth.uid()));

revoke all on public.health_sync_runs, public.daily_health_summaries
from anon, authenticated;
grant select on public.health_sync_runs, public.daily_health_summaries
to authenticated;

create function public.persist_health_sync(
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
      'resting_heart_rate', 'hrv_sdnn'
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

revoke all on function public.persist_health_sync(
  uuid, uuid, date, date, text[], text[], jsonb
) from public, anon, authenticated;
grant execute on function public.persist_health_sync(
  uuid, uuid, date, date, text[], text[], jsonb
) to service_role;
