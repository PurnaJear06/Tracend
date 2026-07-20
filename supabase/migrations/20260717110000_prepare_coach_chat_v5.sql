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

-- NOTE: prepare_coach_chat_v4 is maintained in earlier migrations.
-- v5 wraps v4 for memory-layer augmentation; do not redefine v4 here.
-- If v4 changes are needed, create a separate migration.

create function public.persist_coach_narrative_entry(
  target_user_id uuid, phase text, headline text, since date, cause_snapshot_ids uuid[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  entry_id uuid;
begin
  update public.coach_narrative_entries set until = since
    where user_id = target_user_id and until is null;
  insert into public.coach_narrative_entries(user_id, phase, headline, since, cause_snapshot_ids)
  values(target_user_id, phase, headline, since, cause_snapshot_ids) returning id into entry_id;
  return entry_id;
end $$;

revoke all on function public.persist_coach_narrative_entry(uuid,text,text,date,uuid[])
  from public, anon, authenticated;
grant execute on function public.persist_coach_narrative_entry(uuid,text,text,date,uuid[])
  to service_role;

create function public.persist_coach_preference(
  target_user_id uuid, category text, pref_key text, pref_value text,
  provenance text
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  pref_id uuid;
begin
  if provenance not in ('onboarding','chat_statement','repeated_signal','manual') then
    raise exception 'invalid provenance' using errcode='22023';
  end if;
  if category not in ('training','food','schedule','communication','notification','lifestyle') then
    raise exception 'invalid category' using errcode='22023';
  end if;
  update public.user_preferences set superseded_at = now()
    where user_id = target_user_id and key = pref_key and superseded_at is null;
  insert into public.user_preferences(user_id, category, key, value, provenance)
  values(target_user_id, category, pref_key, pref_value, provenance) returning id into pref_id;
  return pref_id;
end $$;

revoke all on function public.persist_coach_preference(uuid,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.persist_coach_preference(uuid,text,text,text,text)
  to service_role;

create function public.persist_coach_session_summary(
  target_user_id uuid, coaching_date date, summary_text text,
  thread_id_param uuid, key_snapshot_ids uuid[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  summary_id uuid;
begin
  insert into public.coach_session_summaries(user_id, coaching_date, summary,
    thread_id, key_snapshot_ids)
  values(target_user_id, coaching_date, summary_text, thread_id_param, key_snapshot_ids)
  returning id into summary_id;
  delete from public.coach_session_summaries where user_id = target_user_id
    and id not in (select id from public.coach_session_summaries
      where user_id = target_user_id order by coaching_date desc limit 30);
  return summary_id;
end $$;

revoke all on function public.persist_coach_session_summary(uuid,date,text,uuid,uuid[])
  from public, anon, authenticated;
grant execute on function public.persist_coach_session_summary(uuid,date,text,uuid,uuid[])
  to service_role;

create function public.search_coach_messages(
  target_user_id uuid, query_text text, max_results integer default 8
) returns jsonb language plpgsql security definer set search_path='' stable as $$
declare
  results jsonb;
begin
  select coalesce(jsonb_agg(msg order by relevance desc), '[]'::jsonb) into results
  from (
    select jsonb_build_object(
      'id', m.id, 'thread_id', m.thread_id, 'role', m.role,
      'content', m.content, 'created_at', m.created_at,
      'relevance', ts_rank(search_vector, plainto_tsquery('english', query_text))
    ) msg,
      ts_rank(m.search_vector, plainto_tsquery('english', query_text)) relevance
    from public.coach_messages m
    where m.user_id = target_user_id
      and plainto_tsquery('english', query_text) @@ m.search_vector
    order by relevance desc
    limit max_results
  ) ranked;
  return coalesce(results, '[]'::jsonb);
end $$;

revoke all on function public.search_coach_messages(uuid,text,integer)
  from public, anon, authenticated;
grant execute on function public.search_coach_messages(uuid,text,integer)
  to service_role;
