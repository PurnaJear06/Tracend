-- Privacy jobs that stopped halfway can be picked up again -------------------------------
--
-- 1. An export left in `processing` (the function timed out or was stopped) blocked every later
--    export: `request_my_data_export` hands back the open row and `claim_data_export` only took
--    queued rows. A processing export whose claim is 15 minutes old is claimed again.
-- 2. A `ready` export that has expired or used its three downloads still counted as open until the
--    daily retention run, so a new request got the dead one back. Such an export is marked expired
--    when the owner asks for a new one (retention then removes its file as usual).
-- 3. Meal media claimed by the retention worker stayed `pending_deletion` forever when the worker
--    stopped before writing the result. A claim 30 minutes old is handed out again.
--
-- Every function below is its latest earlier definition plus the hunks marked "new" (pinned by
-- supabase/functions/privacy-export/privacy_recovery_test.ts). CREATE OR REPLACE keeps each
-- function's owner and grants; the grants are restated so the migration reads on its own.

alter table public.media_objects add column retention_claimed_at timestamptz;

create index media_objects_retention_stale_claim
  on public.media_objects(retention_claimed_at)
  where lifecycle_status = 'pending_deletion';

create or replace function public.claim_data_export(target_export_id uuid) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare target_user_id uuid;
declare message_id bigint;
begin
  update public.data_exports set status = 'processing', started_at = now(),
    sanitized_error_code = null
  where id = target_export_id
    and (status = 'queued'
      -- new: a worker that stopped leaves the export processing; take it again after 15 minutes
      or (status = 'processing'
        and coalesce(started_at, created_at) < now() - interval '15 minutes'))
  returning user_id, queue_message_id into target_user_id, message_id;
  if message_id is not null then perform pgmq.delete('privacy_exports', message_id); end if;
  return target_user_id;
end
$$;

create or replace function public.request_my_data_export() returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  existing_id uuid;
  export_id uuid;
  message_id bigint;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if not private.has_recent_sign_in(interval '10 minutes') then
    raise exception 'recent authentication required' using errcode = '42501';
  end if;
  if exists (select 1 from public.deletion_requests
    where user_id = auth.uid() and status in ('queued', 'processing')) then
    raise exception 'account deletion pending' using errcode = '55000';
  end if;
  -- new: a ready export that has expired or used its downloads is not an open export
  update public.data_exports set status = 'expired'
  where user_id = auth.uid() and status = 'ready'
    and (expires_at <= now() or download_count >= 3);
  select id into existing_id from public.data_exports
  where user_id = auth.uid() and status in ('queued', 'processing', 'ready')
  order by created_at desc limit 1;
  if existing_id is not null then return existing_id; end if;
  insert into public.data_exports(user_id) values (auth.uid()) returning id into export_id;
  select * into message_id from pgmq.send('privacy_exports', jsonb_build_object(
    'schema_version', '1.0', 'export_id', export_id
  ));
  update public.data_exports set queue_message_id = message_id where id = export_id;
  insert into public.audit_events(user_id, action_code, target_type,
    target_id, outcome, metadata)
  values (auth.uid(), 'privacy_export_requested', 'data_export', export_id,
    'succeeded', jsonb_build_object('scope', 'complete'));
  return export_id;
end
$$;

create or replace function public.claim_expired_meal_media(batch_size integer default 50)
returns table(media_object_id uuid, object_key text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if batch_size not between 1 and 100 then
    raise exception 'invalid batch size' using errcode = '22023';
  end if;

  return query
  with due as (
    select id
    from public.media_objects
    where ((lifecycle_status = 'active'
      and not retention_exempt
      and retention_deadline <= now())
      -- new: a claim whose worker never wrote the result back is handed out again after 30 minutes
      or (lifecycle_status = 'pending_deletion'
        and not retention_exempt
        and coalesce(retention_claimed_at, '-infinity'::timestamptz) < now() - interval '30 minutes'))
    order by retention_deadline, created_at
    for update skip locked
    limit batch_size
  )
  update public.media_objects media
  set lifecycle_status = 'pending_deletion',
      retention_claimed_at = now()
  from due
  where media.id = due.id
  returning media.id, media.object_key;
end
$$;

revoke all on function public.claim_data_export(uuid) from public, anon, authenticated, service_role;
grant execute on function public.claim_data_export(uuid) to service_role;
revoke all on function public.request_my_data_export() from public, anon, authenticated, service_role;
grant execute on function public.request_my_data_export() to authenticated;
revoke all on function public.claim_expired_meal_media(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_expired_meal_media(integer) to service_role;
