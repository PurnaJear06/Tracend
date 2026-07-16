drop function if exists public.prepare_coach_chat_v3(uuid,uuid,text,text,uuid);

create function public.prepare_coach_chat_v4(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  prepared jsonb; c jsonb; coaching_date date;
  snapshot_id uuid; checksum text; ctx_kind text;
begin
  ctx_kind := case
    when context_kind in ('daily_action','plan_change','explain_evidence','nutrition_focus','recovery')
      then context_kind
    else 'general'
  end;

  prepared := public.prepare_coach_chat_v2(target_user_id, target_thread_id, question,
    coaching_timezone, request_idempotency_key);
  if coalesce((prepared->>'replayed')::boolean, false) then return prepared; end if;

  c := prepared->'context';
  coaching_date := coalesce((c->>'coaching_date')::date, current_date);
  c := c || jsonb_build_object('schema_version', '2.0', 'context_kind', ctx_kind);

  checksum := encode(extensions.digest(convert_to(c::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.coach_context_snapshots(user_id, thread_id, schema_version, trigger_kind, coaching_date, context, context_checksum)
  values(target_user_id, target_thread_id, '2.0', 'chat', coaching_date, c, checksum) returning id into snapshot_id;
  return prepared || jsonb_build_object('context', c, 'coach_context_snapshot_id', snapshot_id);
end $$;

create or replace function public.prepare_coach_chat_v3(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid
) returns jsonb language sql security definer set search_path='' as $$
select public.prepare_coach_chat_v4(target_user_id, target_thread_id, question,
  coaching_timezone, request_idempotency_key, 'general');
$$;

revoke all on function public.prepare_coach_chat_v4(uuid,uuid,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.prepare_coach_chat_v4(uuid,uuid,text,text,uuid,text) to service_role;
revoke all on function public.prepare_coach_chat_v3(uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.prepare_coach_chat_v3(uuid,uuid,text,text,uuid) to service_role;
