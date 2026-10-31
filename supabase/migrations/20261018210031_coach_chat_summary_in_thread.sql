-- Coach chat: the app's data summary stays in the conversation the Coach reads.
--
-- When Coach cannot produce a valid answer, the app shows a labelled data summary
-- (coach_messages.answer_source = 'data_summary'). Every layer of prepare_coach_chat since v2
-- left those out of recent_messages, so on the next turn the Coach could not see a number the
-- app had just shown ("I can't find a 0.07 kg/day figure") and answered as if the thread had
-- not happened.
--
-- prepare_coach_chat_v10 wraps v9 unchanged and rebuilds recent_messages the way v8 did (the
-- newest ten messages of the thread, a long message cut to its start and end) but with the
-- summaries in. A summary carries answer_source = 'data_summary' next to role and content, so the
-- prompt can label it as the app's reply and not the Coach's own words; every other message keeps
-- the shape it had, except that a summary also carries local_date (the athlete's local date of
-- its creation, so its figures ground only a turn on that same coaching date), and that a question marked superseded (safety_state 'unavailable' on a user
-- message: the athlete sent the same text again after it failed) carries that state, so the
-- reader can drop it and the summary that followed it (coach-chat/superseded.ts). The summary
-- itself carries no safety_state: it is stored as 'unavailable' too, and would be dropped always.
-- The context's schema_version moves from 8.0 to 8.1 (a field was added, none
-- removed or renamed). The stored context snapshot is rewritten to match, as v9 does.
--
-- Additive only: v8 and v9 are not touched and stay callable. The edge function calls v10 once
-- this migration is applied (the deploy runs migrations before functions).
create function public.prepare_coach_chat_v10(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prepared jsonb;
  c jsonb;
begin
  prepared := public.prepare_coach_chat_v9(target_user_id, target_thread_id, question,
    coaching_timezone, request_idempotency_key, context_kind);
  if coalesce((prepared ->> 'replayed')::boolean, false) or not (prepared ? 'context') then
    return prepared;
  end if;
  c := prepared -> 'context';
  c := c || jsonb_build_object(
    'schema_version', '8.1',
    'recent_messages', (
      select coalesce(jsonb_agg(message order by created_at, turn_rank), '[]'::jsonb) from (
        select jsonb_build_object('role', m.role, 'content', case when length(m.content) > 2000
            then left(m.content, 500) || ' … ' || right(m.content, 1400) else m.content end)
          || case when m.answer_source = 'data_summary'
            then jsonb_build_object('answer_source', 'data_summary',
              'local_date', private.local_day(target_user_id, m.created_at)) else '{}'::jsonb end
          || case when m.role = 'user' and m.safety_state = 'unavailable'
            then jsonb_build_object('safety_state', 'unavailable') else '{}'::jsonb end message,
          m.created_at, case m.role when 'user' then 0 else 1 end turn_rank
        from public.coach_messages m
        where m.user_id = target_user_id and m.thread_id = target_thread_id
        order by m.created_at desc, turn_rank desc limit 10
      ) recent));
  if prepared ? 'coach_context_snapshot_id' then
    update public.coach_context_snapshots
    set context = c,
      context_checksum = encode(extensions.digest(convert_to(c::text, 'UTF8'), 'sha256'), 'hex')
    where id = (prepared ->> 'coach_context_snapshot_id')::uuid and user_id = target_user_id;
  end if;
  return prepared || jsonb_build_object('context', c);
end $$;
revoke all on function public.prepare_coach_chat_v10(uuid, uuid, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.prepare_coach_chat_v10(uuid, uuid, text, text, uuid, text)
  to service_role;
