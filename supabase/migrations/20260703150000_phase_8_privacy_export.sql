create table public.data_exports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  status text not null default 'queued' check (
    status in ('queued', 'processing', 'ready', 'failed', 'expired')
  ),
  scope text not null default 'complete' check (scope = 'complete'),
  storage_path text,
  byte_size bigint check (byte_size is null or byte_size between 1 and 1073741824),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz,
  download_count integer not null default 0 check (download_count between 0 and 3),
  sanitized_error_code text,
  queue_message_id bigint,
  constraint data_exports_ready_shape check (
    status <> 'ready' or
    (storage_path is not null and byte_size is not null and completed_at is not null
      and expires_at is not null)
  )
);

create unique index data_exports_one_open_per_user
on public.data_exports(user_id)
where status in ('queued', 'processing', 'ready');
create index data_exports_expiry_idx on public.data_exports(expires_at)
where status = 'ready';

alter table public.data_exports enable row level security;
alter table public.data_exports force row level security;
create policy data_exports_own_read on public.data_exports
for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.data_exports from anon, authenticated;
grant select(id, status, scope, byte_size, created_at, completed_at, expires_at,
  download_count, sanitized_error_code) on public.data_exports to authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'account-exports', 'account-exports', false, 1073741824,
  array['application/octet-stream']
)
on conflict(id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy account_exports_service_only on storage.objects
for all to service_role using (bucket_id = 'account-exports')
with check (bucket_id = 'account-exports');

select pgmq.create('privacy_exports');

create function public.request_my_data_export() returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  issued_at timestamptz;
  existing_id uuid;
  export_id uuid;
  message_id bigint;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  issued_at := to_timestamp(coalesce((auth.jwt() ->> 'iat')::bigint, 0));
  if issued_at < now() - interval '10 minutes' then
    raise exception 'recent authentication required' using errcode = '42501';
  end if;
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
revoke all on function public.request_my_data_export() from public, anon, authenticated, service_role;
grant execute on function public.request_my_data_export() to authenticated;

create function public.claim_data_export(target_export_id uuid) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare target_user_id uuid;
declare message_id bigint;
begin
  update public.data_exports set status = 'processing', started_at = now(),
    sanitized_error_code = null
  where id = target_export_id and status = 'queued'
  returning user_id, queue_message_id into target_user_id, message_id;
  if message_id is not null then perform pgmq.delete('privacy_exports', message_id); end if;
  return target_user_id;
end
$$;

create function public.complete_data_export(
  target_export_id uuid, object_path text, object_bytes bigint
) returns void language plpgsql security definer set search_path = ''
as $$
declare target_user_id uuid;
begin
  if object_path !~ ('^' || (select user_id::text from public.data_exports
    where id = target_export_id) || '/[0-9a-f-]+[.]tracendexport$') then
    raise exception 'invalid export path' using errcode = '22023';
  end if;
  update public.data_exports set status = 'ready', storage_path = object_path,
    byte_size = object_bytes, completed_at = now(), expires_at = now() + interval '7 days'
  where id = target_export_id and status = 'processing'
  returning user_id into target_user_id;
  if target_user_id is null then raise exception 'export not processing' using errcode = 'P0002'; end if;
  insert into public.audit_events(user_id, action_code, target_type,
    target_id, outcome, metadata)
  values (target_user_id, 'privacy_export_completed', 'data_export',
    target_export_id, 'succeeded', jsonb_build_object('encrypted', true));
end
$$;

create function public.fail_data_export(target_export_id uuid, failure_code text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if failure_code !~ '^[a-z0-9_]{1,64}$' then
    failure_code := 'export_failed';
  end if;
  update public.data_exports set status = 'failed', sanitized_error_code = failure_code
  where id = target_export_id and status in ('queued', 'processing');
end
$$;

create function public.record_data_export_download(target_export_id uuid)
returns text language plpgsql security definer set search_path = ''
as $$
declare object_path text;
begin
  update public.data_exports set download_count = download_count + 1
  where id = target_export_id and status = 'ready' and user_id = auth.uid()
    and expires_at > now() and download_count < 3
  returning storage_path into object_path;
  if object_path is null then
    raise exception 'export unavailable' using errcode = '42501';
  end if;
  insert into public.audit_events(user_id, action_code, target_type,
    target_id, outcome, metadata)
  values (auth.uid(), 'privacy_export_downloaded', 'data_export',
    target_export_id, 'succeeded', '{}'::jsonb);
  return object_path;
end
$$;
revoke all on function public.record_data_export_download(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.record_data_export_download(uuid) to authenticated;

create function public.expire_data_exports() returns table(storage_path text)
language plpgsql security definer set search_path = ''
as $$
begin
  update public.data_exports e set status = 'expired'
  where e.status = 'ready' and (e.expires_at <= now() or e.download_count >= 3)
    and e.storage_path is not null;
  return query select e.storage_path from public.data_exports e
    where e.status = 'expired' and e.storage_path is not null;
end
$$;

create function public.complete_data_export_retention(object_path text, deletion_succeeded boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if deletion_succeeded then
    update public.data_exports set storage_path = null
    where storage_path = object_path and status = 'expired';
  end if;
end
$$;

revoke all on function public.claim_data_export(uuid) from public, anon, authenticated, service_role;
revoke all on function public.complete_data_export(uuid, text, bigint) from public, anon, authenticated, service_role;
revoke all on function public.fail_data_export(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.expire_data_exports() from public, anon, authenticated, service_role;
revoke all on function public.complete_data_export_retention(text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_data_export(uuid) to service_role;
grant execute on function public.complete_data_export(uuid, text, bigint) to service_role;
grant execute on function public.fail_data_export(uuid, text) to service_role;
grant execute on function public.expire_data_exports() to service_role;
grant execute on function public.complete_data_export_retention(text, boolean) to service_role;
