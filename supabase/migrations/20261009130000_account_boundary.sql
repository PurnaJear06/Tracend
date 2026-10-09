-- Sign-ups are invite-only -------------------------------------------------------------

-- Reachable only from the SQL editor: no API role can read or write it.
create table private.signup_invites (
  email text primary key check (email = lower(btrim(email)) and length(email) between 3 and 254),
  note text check (length(note) <= 200),
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by uuid
);
revoke all on private.signup_invites from public, anon, authenticated, service_role;

-- Every existing account keeps its place, so no address is written here.
insert into private.signup_invites(email, note, claimed_at, claimed_by)
select lower(btrim(email)), 'existing account', created_at, id
from auth.users where email is not null and length(btrim(email)) between 3 and 254
on conflict (email) do nothing;

-- Auth inserts the user and this trigger runs in the same transaction, so a
-- refused sign-up leaves no user behind and sends no email. Rows with no email,
-- phone or anonymous flag only come from direct SQL (tests, administration).
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is not null or new.phone is not null or coalesce(new.is_anonymous, false) then
    update private.signup_invites
    set claimed_at = coalesce(claimed_at, now()), claimed_by = coalesce(claimed_by, new.id)
    where email = lower(btrim(new.email));
    if not found then
      raise exception 'signup is invite-only' using errcode = '42501';
    end if;
  end if;
  insert into public.user_accounts (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Recent sign-in comes from `amr`, not `iat` ------------------------------------------

-- A refreshed token gets a new `iat`, so `iat` cannot show a recent sign-in.
-- The `amr` claim keeps the time of the sign-in that started the session.
create function private.has_recent_sign_in(max_age interval)
returns boolean language plpgsql stable set search_path = '' as $$
declare claim jsonb := auth.jwt() -> 'amr';
begin
  if claim is null or jsonb_typeof(claim) <> 'array' then return false; end if;
  return exists (
    select 1 from jsonb_array_elements(claim) entry
    where jsonb_typeof(entry) = 'object'
      and entry ->> 'method' in ('password', 'otp', 'totp')
      and coalesce(entry ->> 'timestamp', '') ~ '^[0-9]{9,11}$'
      and to_timestamp((entry ->> 'timestamp')::bigint)
        between now() - max_age and now() + interval '1 minute'
  );
end $$;
revoke all on function private.has_recent_sign_in(interval) from public, anon, authenticated;

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

create or replace function public.request_my_account_deletion(confirmation text) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare request_id uuid; message_id bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if not private.has_recent_sign_in(interval '10 minutes') then
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

-- No export completes once a deletion is pending ----------------------------------------

create or replace function public.complete_data_export(
  target_export_id uuid, object_path text, object_bytes bigint
) returns void language plpgsql security definer set search_path = ''
as $$
declare target_user_id uuid;
begin
  if object_path !~ ('^' || (select user_id::text from public.data_exports
    where id = target_export_id) || '/[0-9a-f-]+[.]tracendexport$') then
    raise exception 'invalid export path' using errcode = '22023';
  end if;
  if exists (select 1 from public.deletion_requests request
    join public.data_exports export on export.user_id = request.user_id
    where export.id = target_export_id and request.status in ('queued', 'processing')) then
    raise exception 'account deletion pending' using errcode = '55000';
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

-- Account deletion removes every object in the user's folders, including any
-- upload that never got a database row.
create function public.list_account_storage_objects(target_user_id uuid)
returns table (bucket_id text, name text)
language sql stable security definer set search_path = '' as $$
  select object.bucket_id, object.name from storage.objects object
  where object.bucket_id in ('meal-images', 'progress-photos', 'account-exports')
    and object.name like target_user_id::text || '/%'
  order by object.bucket_id, object.name;
$$;
revoke all on function public.list_account_storage_objects(uuid) from public, anon, authenticated;
grant execute on function public.list_account_storage_objects(uuid) to service_role;

-- Deleting a Coach conversation removes what was saved with it -------------------------

do $$
declare constraint_name text;
begin
  select conname into constraint_name from pg_constraint
  where conrelid = 'public.coach_context_snapshots'::regclass
    and confrelid = 'public.coach_threads'::regclass and contype = 'f';
  if constraint_name is not null then
    execute format('alter table public.coach_context_snapshots drop constraint %I', constraint_name);
  end if;
end $$;
alter table public.coach_context_snapshots
  add constraint coach_context_snapshots_thread_id_fkey
  foreign key (thread_id) references public.coach_threads(id) on delete cascade;

create or replace function public.delete_coach_thread(target_thread_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare deleted_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  delete from public.coach_session_summaries
  where thread_id=target_thread_id and user_id=auth.uid();
  delete from public.coach_threads
  where id=target_thread_id and user_id=auth.uid() returning id into deleted_id;
  if deleted_id is null then
    raise exception 'thread not found' using errcode='P0002';
  end if;
  insert into public.audit_events(
    user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'coach.thread.deleted','coach_thread',deleted_id,
    'succeeded',jsonb_build_object('schema_version','1.0'));
  return true;
end $$;
