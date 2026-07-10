create table public.deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  status text not null default 'queued' check (
    status in ('queued', 'processing', 'completed', 'failed')
  ),
  queue_message_id bigint,
  requested_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  sanitized_error_code text
);
create unique index deletion_requests_one_open on public.deletion_requests(user_id)
where status in ('queued', 'processing');
create index deletion_requests_retention on public.deletion_requests(completed_at)
where status in ('completed', 'failed');

alter table public.deletion_requests enable row level security;
alter table public.deletion_requests force row level security;
create policy deletion_requests_own_read on public.deletion_requests
for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.deletion_requests from anon, authenticated;
grant select(id, status, requested_at, started_at, completed_at,
  sanitized_error_code) on public.deletion_requests to authenticated;

select pgmq.create('account_deletions');

create function public.request_my_account_deletion(confirmation text) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare issued_at timestamptz; request_id uuid; message_id bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  issued_at := to_timestamp(coalesce((auth.jwt() ->> 'iat')::bigint, 0));
  if issued_at < now() - interval '10 minutes' then
    raise exception 'recent authentication required' using errcode = '42501';
  end if;
  if confirmation <> 'DELETE' then raise exception 'invalid confirmation' using errcode = '22023'; end if;
  select id into request_id from public.deletion_requests
    where user_id = auth.uid() and status in ('queued', 'processing') limit 1;
  if request_id is not null then return request_id; end if;
  insert into public.deletion_requests(user_id) values(auth.uid()) returning id into request_id;
  select * into message_id from pgmq.send('account_deletions', jsonb_build_object(
    'schema_version', '1.0', 'deletion_request_id', request_id
  ));
  update public.deletion_requests set queue_message_id = message_id where id = request_id;
  return request_id;
end
$$;
revoke all on function public.request_my_account_deletion(text)
  from public, anon, authenticated, service_role;
grant execute on function public.request_my_account_deletion(text) to authenticated;

create function public.claim_account_deletion(target_request_id uuid) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare target_user_id uuid; message_id bigint;
begin
  update public.deletion_requests set status = 'processing', started_at = now()
  where id = target_request_id and status = 'queued'
  returning user_id, queue_message_id into target_user_id, message_id;
  if message_id is not null then perform pgmq.delete('account_deletions', message_id); end if;
  return target_user_id;
end
$$;

create function public.complete_account_deletion(target_request_id uuid, succeeded boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  update public.deletion_requests set
    status = case when succeeded then 'completed' else 'failed' end,
    completed_at = now(),
    sanitized_error_code = case when succeeded then null else 'deletion_failed' end
  where id = target_request_id and status = 'processing';
end
$$;

create function public.cleanup_deletion_receipts() returns integer
language plpgsql security definer set search_path = ''
as $$
declare removed integer;
begin
  delete from public.deletion_requests
  where completed_at < now() - interval '180 days';
  get diagnostics removed = row_count;
  return removed;
end
$$;

revoke all on function public.claim_account_deletion(uuid),
  public.complete_account_deletion(uuid, boolean), public.cleanup_deletion_receipts()
  from public, anon, authenticated, service_role;
grant execute on function public.claim_account_deletion(uuid),
  public.complete_account_deletion(uuid, boolean), public.cleanup_deletion_receipts()
  to service_role;
