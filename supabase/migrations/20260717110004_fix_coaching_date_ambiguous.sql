-- fix: ambiguous column "coaching_date" in prepare_coach_chat_v5 — PL/pgSQL variable
-- shadows the table column. Use qualified reference s.coaching_date.
create or replace function public.prepare_coach_chat_v5(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  prepared jsonb; c jsonb; coaching_date date;
  snapshot_id uuid; checksum text; ctx_kind text;
  narrative jsonb; preferences jsonb; journal jsonb;
begin
  prepared := public.prepare_coach_chat_v4(target_user_id, target_thread_id,
    question, coaching_timezone, request_idempotency_key, context_kind);
  if coalesce((prepared->>'replayed')::boolean, false) then return prepared; end if;

  c := prepared->'context';
  coaching_date := coalesce((c->>'coaching_date')::date, current_date);

  c := c || jsonb_build_object('schema_version', '4.0');

  select coalesce(jsonb_build_object(
    'active', (select jsonb_build_object('phase', phase, 'headline', headline, 'since', since)
      from public.coach_narrative_entries where user_id = target_user_id
        and until is null order by since desc limit 1),
    'recent', (select coalesce(jsonb_agg(entry), '[]'::jsonb) from (
      select jsonb_build_object('phase', phase, 'headline', headline, 'since', since, 'until', until) entry
      from public.coach_narrative_entries where user_id = target_user_id
        and (until is not null or id = (select id from public.coach_narrative_entries
          where user_id = target_user_id and until is null order by since desc limit 1))
      order by since desc limit 4) s)
    ), jsonb_build_object('active', '{}'::jsonb, 'recent', '[]'::jsonb)) into narrative;
  c := c || jsonb_build_object('coaching_narrative', narrative);

  select coalesce(jsonb_agg(pref), '[]'::jsonb) into preferences
    from (
      select jsonb_build_object('id', id, 'category', category, 'key', key, 'value', value, 'provenance', provenance) pref
      from public.user_preferences
      where user_id = target_user_id and superseded_at is null
      order by category, key
    ) s;
  c := c || jsonb_build_object('active_preferences', preferences);

  select coalesce(jsonb_agg(entry), '[]'::jsonb) into journal
    from (
      select jsonb_build_object('coaching_date', s.coaching_date, 'summary', s.summary, 'thread_id', s.thread_id) entry
      from public.coach_session_summaries s where s.user_id = target_user_id
      order by s.coaching_date desc limit 10
    ) sub;
  c := c || jsonb_build_object('session_journal', journal);

  checksum := encode(extensions.digest(convert_to(c::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.coach_context_snapshots(user_id, thread_id, schema_version, trigger_kind,
    coaching_date, context, context_checksum)
  values(target_user_id, target_thread_id, '4.0', 'chat', coaching_date, c, checksum)
  returning id into snapshot_id;
  return prepared || jsonb_build_object('context', c, 'coach_context_snapshot_id', snapshot_id);
end $$;

revoke all on function public.prepare_coach_chat_v5(uuid,uuid,text,text,uuid,text)
  from public, anon, authenticated;
grant execute on function public.prepare_coach_chat_v5(uuid,uuid,text,text,uuid,text)
  to service_role;
