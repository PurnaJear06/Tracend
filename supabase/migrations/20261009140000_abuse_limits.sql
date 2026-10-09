-- Time zones: one writer, and a bad value never stops the scheduler ---------------------

-- `set_my_timezone` validates against pg_timezone_names; the app never writes
-- the column directly, so the direct column grants go.
revoke insert (timezone), update (timezone) on public.user_accounts from authenticated;

update public.user_accounts set timezone = 'UTC'
where timezone not in (select name from pg_catalog.pg_timezone_names);

create function private.safe_timezone(zone text)
returns text language sql stable set search_path = '' as $$
  select coalesce(
    (select name from pg_catalog.pg_timezone_names where name = zone limit 1), 'UTC');
$$;
revoke all on function private.safe_timezone(text) from public, anon, authenticated;

create or replace function public.request_my_weekly_review(target_review_week date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  local_today date;
  current_monday date;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  select timezone(private.safe_timezone(a.timezone), now())::date into local_today
  from public.user_accounts a
  where a.id = auth.uid() and a.account_status = 'active'
    and a.onboarding_state = 'completed';
  if local_today is null then
    raise exception 'active completed account required' using errcode = '42501';
  end if;
  current_monday := local_today - (extract(isodow from local_today)::integer - 1);
  if extract(isodow from target_review_week) <> 1
    or target_review_week < current_monday - 56
    or target_review_week > current_monday
  then
    raise exception 'invalid review week' using errcode = '22023';
  end if;
  return private.enqueue_weekly_review_job(auth.uid(), target_review_week);
end
$$;

create or replace function public.schedule_weekly_progress_reviews()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  account record;
  target_week date;
  scheduled integer := 0;
begin
  for account in
    select id, timezone from public.user_accounts
    where account_status = 'active' and onboarding_state = 'completed'
  loop
    target_week := timezone(private.safe_timezone(account.timezone), now())::date;
    target_week := target_week
      - (extract(isodow from target_week)::integer - 1) - 7;
    perform private.enqueue_weekly_review_job(account.id, target_week);
    scheduled := scheduled + 1;
  end loop;
  return scheduled;
end
$$;

-- Per-user row caps ---------------------------------------------------------------------

-- BEFORE INSERT trigger: TG_ARGV[0] is the limit and TG_ARGV[1] the window
-- ('all' counts every row the user has). The table needs user_id and created_at.
-- Inserts for one user and table wait for each other (a transaction lock), and
-- each count runs after the lock in a fresh snapshot, so parallel requests
-- cannot all see a count under the cap.
create function private.enforce_user_row_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  row_limit integer := TG_ARGV[0]::integer;
  existing integer;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('tracend.row_limit:' || TG_TABLE_NAME || ':' || new.user_id::text, 0));
  if TG_ARGV[1] = 'all' then
    execute format('select count(*) from %I.%I where user_id = $1', TG_TABLE_SCHEMA, TG_TABLE_NAME)
      into existing using new.user_id;
  else
    execute format('select count(*) from %I.%I where user_id = $1 and created_at > now() - $2::interval',
      TG_TABLE_SCHEMA, TG_TABLE_NAME)
      into existing using new.user_id, TG_ARGV[1];
  end if;
  if existing >= row_limit then
    raise exception '% limit reached', TG_TABLE_NAME using errcode = '54000';
  end if;
  return new;
end $$;
revoke all on function private.enforce_user_row_limit() from public, anon, authenticated;

create trigger consent_records_daily_limit before insert on public.consent_records
for each row execute function private.enforce_user_row_limit('100', '24 hours');
create trigger user_goals_total_limit before insert on public.user_goals
for each row execute function private.enforce_user_row_limit('200', 'all');
create trigger coach_threads_daily_limit before insert on public.coach_threads
for each row execute function private.enforce_user_row_limit('50', '24 hours');
create trigger coach_threads_total_limit before insert on public.coach_threads
for each row execute function private.enforce_user_row_limit('1000', 'all');
create trigger progress_photo_sets_daily_limit before insert on public.progress_photo_sets
for each row execute function private.enforce_user_row_limit('10', '24 hours');

-- Consent records: the client sets only what it means ----------------------------------

-- `created_at` and `id` always take their defaults, so a client cannot date a
-- record ahead of a later one.
revoke insert on public.consent_records from authenticated;
grant insert (user_id, consent_type, notice_version, action, source)
  on public.consent_records to authenticated;
create index consent_records_user_type_recent
  on public.consent_records(user_id, consent_type, created_at desc, id desc);

-- Bounded client JSON (new and updated rows; older rows are not rechecked) ---------------

alter table public.onboarding_drafts add constraint onboarding_drafts_payload_size
  check (octet_length(payload::text) <= 131072) not valid;
alter table public.user_goals add constraint user_goals_details_size
  check (octet_length(details::text) <= 16384) not valid;

-- Health sync bounds --------------------------------------------------------------------

-- Reconciliation now covers only the workouts in this payload. The app resends
-- the last seven days on every refresh, so recent sessions are still matched.
create or replace function public.persist_health_workouts(target_user_id uuid,workout_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb; accepted integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  if jsonb_typeof(workout_payload)<>'array' or jsonb_array_length(workout_payload)>100 then raise exception 'invalid workout payload' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(workout_payload) loop
    if coalesce(item->>'sample_id_hash','')!~'^[0-9a-f]{64}$' or coalesce(item->>'source_id_hash','')!~'^[0-9a-f]{64}$'
      or length(coalesce(item->>'activity_type','')) not between 1 and 80
      or (item->>'ended_at')::timestamptz <= (item->>'started_at')::timestamptz then
      raise exception 'invalid health workout' using errcode='22023';
    end if;
    insert into public.health_workout_references(user_id,sample_id_hash,source_id_hash,activity_type,started_at,ended_at,duration_seconds,energy_kcal,local_date)
    values(target_user_id,item->>'sample_id_hash',item->>'source_id_hash',item->>'activity_type',(item->>'started_at')::timestamptz,(item->>'ended_at')::timestamptz,(item->>'duration_seconds')::integer,nullif(item->>'energy_kcal','')::numeric,(item->>'local_date')::date)
    on conflict(user_id,sample_id_hash) do update set activity_type=excluded.activity_type,started_at=excluded.started_at,ended_at=excluded.ended_at,duration_seconds=excluded.duration_seconds,energy_kcal=excluded.energy_kcal,last_synced_at=now();
    accepted:=accepted+1;
  end loop;
  insert into public.workout_reconciliations(user_id,workout_session_id,health_workout_reference_id,status,confidence,overlap_seconds,duration_difference_seconds)
  select target_user_id,s.id,h.id,
    case when abs(coalesce(s.duration_seconds,h.duration_seconds)-h.duration_seconds)>900 then 'conflict' else 'suggested' end,
    greatest(0,least(1,
      (case when s.local_date=h.local_date then .45 else 0 end)+
      (case when h.activity_type in ('TRADITIONAL_STRENGTH_TRAINING','FUNCTIONAL_STRENGTH_TRAINING','OTHER') then .25 else .05 end)+
      (case when abs(coalesce(s.duration_seconds,h.duration_seconds)-h.duration_seconds)<=900 then .30 when abs(coalesce(s.duration_seconds,h.duration_seconds)-h.duration_seconds)<=1800 then .15 else 0 end)
    )),
    greatest(0,extract(epoch from least(coalesce(s.actual_ended_at,s.completed_at),h.ended_at)-greatest(coalesce(s.actual_started_at,s.started_at),h.started_at))::integer),
    abs(coalesce(s.duration_seconds,h.duration_seconds)-h.duration_seconds)
  from public.workout_sessions s join public.health_workout_references h on h.user_id=s.user_id and h.local_date=s.local_date
  where s.user_id=target_user_id and s.state='completed'
    and h.sample_id_hash in (select value->>'sample_id_hash' from jsonb_array_elements(workout_payload))
  on conflict(workout_session_id,health_workout_reference_id) do update set confidence=excluded.confidence,overlap_seconds=excluded.overlap_seconds,duration_difference_seconds=excluded.duration_difference_seconds,status=case when workout_reconciliations.status in ('confirmed','rejected') then workout_reconciliations.status else excluded.status end;
  return jsonb_build_object('accepted_count',accepted);
end $$;

-- The limits match `healthSyncLimits` in _shared/contracts/health_sync_v1.ts.
-- A replay returns the stored run and skips the workouts.
create or replace function public.persist_health_sync_v2(
  target_user_id uuid,sync_idempotency_key uuid,request_start date,request_end date,
  request_types text[],response_types text[],summary_payload jsonb,workout_payload jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; workout_result jsonb;
begin
  if auth.role()<>'service_role' then raise exception 'service role required' using errcode='42501'; end if;
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

-- Upload quotas -------------------------------------------------------------------------

-- Counts, not bytes: the size is not known when the row is inserted, and each
-- bucket's file_size_limit already caps every object. Policies run as
-- `authenticated`, which cannot use `private`, so this lives in `public`; it
-- only reveals the caller's own quota.
create function public.storage_upload_allowed(target_bucket text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  daily_limit integer;
  kept_limit integer;
begin
  if target_bucket = 'meal-images' then daily_limit := 100; kept_limit := 3000;
  elsif target_bucket = 'progress-photos' then daily_limit := 60; kept_limit := 2000;
  else return true;
  end if;
  -- Uploads by one athlete to one bucket wait for each other until commit, and
  -- the counts below run after the lock, so parallel uploads cannot all pass.
  perform pg_advisory_xact_lock(
    hashtextextended('tracend.upload_quota:' || target_bucket || ':' || coalesce(auth.uid()::text, ''), 0));
  return (select count(*) from storage.objects where bucket_id = target_bucket
      and owner_id = auth.uid()::text and created_at > now() - interval '24 hours') < daily_limit
    and (select count(*) from storage.objects where bucket_id = target_bucket
      and owner_id = auth.uid()::text) < kept_limit;
end $$;
revoke all on function public.storage_upload_allowed(text) from public, anon;
grant execute on function public.storage_upload_allowed(text) to authenticated;

create policy user_media_upload_quota on storage.objects as restrictive
for insert to authenticated
with check (bucket_id not in ('meal-images', 'progress-photos')
  or public.storage_upload_allowed(bucket_id));

-- Objects with no database row: an upload whose RPC never ran, or an export
-- that never completed. The retention worker removes them through Storage.
create function public.list_orphan_storage_objects(batch_size integer default 100)
returns table (bucket_id text, name text)
language sql stable security definer set search_path = '' as $$
  select object.bucket_id, object.name from storage.objects object
  where (object.bucket_id in ('meal-images', 'progress-photos')
      and object.created_at < now() - interval '24 hours'
      and not exists (select 1 from public.media_objects media where media.object_key = object.name))
    or (object.bucket_id = 'account-exports'
      and object.created_at < now() - interval '1 hour'
      and not exists (select 1 from public.data_exports export where export.storage_path = object.name))
  order by object.created_at
  limit least(greatest(batch_size, 1), 500);
$$;
revoke all on function public.list_orphan_storage_objects(integer) from public, anon, authenticated;
grant execute on function public.list_orphan_storage_objects(integer) to service_role;
