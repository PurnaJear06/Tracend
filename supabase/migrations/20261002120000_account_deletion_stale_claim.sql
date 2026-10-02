-- A deletion whose Edge Function stopped after claiming it (the worker hit its
-- wall-clock limit or crashed) stayed 'processing' for good:
-- request_my_account_deletion kept returning it and this claim refused it, so
-- the athlete could never delete the account. An Edge Function stops within
-- minutes, so a request still processing after ten is no longer running and
-- may be claimed again. Every deletion step is safe to repeat.
create or replace function public.claim_account_deletion(target_request_id uuid) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare target_user_id uuid; message_id bigint;
begin
  update public.deletion_requests set status = 'processing', started_at = now()
  where id = target_request_id
    and (
      status = 'queued'
      or (status = 'processing' and started_at < now() - interval '10 minutes')
    )
  returning user_id, queue_message_id into target_user_id, message_id;
  if message_id is not null then
    perform pgmq.delete('account_deletions', message_id);
  end if;
  return target_user_id;
end
$$;

revoke all on function public.claim_account_deletion(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_account_deletion(uuid) to service_role;
