-- Apply context budget guard to prevent silent context bloat from causing
-- Edge Function failures.  See docs/CONTEXT_BUDGET.md for the full contract.
--
-- v5 is the outermost assembly layer; all prior layers (v1-v4) pass their
-- context through unchecked after the v1 16K guard.  This migration adds a
-- post-assembly guard in v5 and trims the highest-volume arrays when the
-- serialised context exceeds 40KiB.

create or replace function public.prepare_coach_chat_v5(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  prepared jsonb; c jsonb; coaching_date date;
  snapshot_id uuid; checksum text; ctx_kind text;
  narrative jsonb; preferences jsonb; journal jsonb;
  context_len integer;
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
      order by s.coaching_date desc limit 5
    ) sub;
  c := c || jsonb_build_object('session_journal', journal);

  -- Budget guard: if the fully assembled context exceeds 40K chars, trim
  -- the highest-volume arrays to keep the Edge Function's 32K budget
  -- reachable after key-abbreviation compaction and Tier 1-3 trimming.
  context_len := length(c::text);
  if context_len > 40000 then
    c := c || jsonb_build_object(
      'recent_messages',
      (select coalesce(jsonb_agg(elem), '[]'::jsonb)
       from (select jsonb_array_elements(c->'recent_messages') elem limit 10) s),
      'recent_other_conversations',
      (select coalesce(jsonb_agg(elem), '[]'::jsonb)
       from (select jsonb_array_elements(c->'recent_other_conversations') elem limit 10) s),
      'session_journal',
      (select coalesce(jsonb_agg(elem), '[]'::jsonb)
       from (select jsonb_array_elements(c->'session_journal') elem limit 5) s),
      'context_trimming_applied', true
    );
  end if;

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

-- Also reduce recent_other_conversations in v2 to shrink the base context
-- before v4/v5 augmentation.  This prevents the budget guard from triggering
-- unnecessarily for users with many short chat messages.

create or replace function public.prepare_coach_chat_v2(
  target_user_id uuid,target_thread_id uuid,question text,
  coaching_timezone text,request_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare prepared jsonb; context_payload jsonb; missing jsonb; permitted jsonb;
  other_thread_history jsonb; coaching_date date; has_recent_health boolean;
  has_today_check_in boolean;
begin
  prepared:=public.prepare_coach_chat(target_user_id,target_thread_id,question,
    coaching_timezone,request_idempotency_key);
  if coalesce((prepared->>'replayed')::boolean,false) then return prepared; end if;
  context_payload:=prepared->'context';
  coaching_date:=coalesce((context_payload->>'coaching_date')::date,current_date);
  select exists(select 1 from public.daily_health_summaries
    where user_id=target_user_id and local_date between coaching_date-2 and coaching_date),
    exists(select 1 from public.daily_check_ins where user_id=target_user_id
      and local_date=coaching_date and superseded_at is null)
  into has_recent_health,has_today_check_in;
  select coalesce(jsonb_agg(value),'[]'::jsonb) into missing
  from jsonb_array_elements_text(coalesce(context_payload->'missing_data','[]'::jsonb)) value
  where not (value='health_context' and has_recent_health)
    and not (value='recovery_check_in' and has_today_check_in);
  select coalesce(jsonb_agg(value),'[]'::jsonb) into permitted
  from jsonb_array_elements_text(coalesce(context_payload->'permitted_evidence','[]'::jsonb)) value
  where value<>'HEALTH_CONTEXT_AVAILABLE' or has_recent_health;
  if has_recent_health and not permitted @> '["HEALTH_CONTEXT_AVAILABLE"]'::jsonb then
    permitted:=permitted||'"HEALTH_CONTEXT_AVAILABLE"'::jsonb;
  end if;
  select coalesce(jsonb_agg(message order by created_at),'[]'::jsonb)
  into other_thread_history from (
    select jsonb_build_object('role',role,'content',content) message,created_at
    from public.coach_messages where user_id=target_user_id
      and thread_id<>target_thread_id order by created_at desc limit 10
  ) other_messages;
  context_payload:=context_payload||jsonb_build_object(
    'missing_data',missing,
    'permitted_evidence',permitted,
    'recent_other_conversations',other_thread_history,
    'context_coverage',jsonb_build_object(
      'approved_plan',context_payload->'active_plan'<>'null'::jsonb,
      'active_goal',context_payload->'active_goal'<>'null'::jsonb,
      'profile',context_payload->'profile_context'<>'null'::jsonb,
      'healthkit_recent',has_recent_health,
      'today_check_in',has_today_check_in,
      'confirmed_nutrition',jsonb_array_length(coalesce(context_payload->'confirmed_nutrition_history','[]'::jsonb))>0,
      'completed_workouts',jsonb_array_length(coalesce(context_payload->'recent_execution','[]'::jsonb))>0,
      'measurements',jsonb_array_length(coalesce(context_payload->'measurement_history','[]'::jsonb))>0,
      'conversation_messages',jsonb_array_length(coalesce(context_payload->'recent_messages','[]'::jsonb))));
  return prepared||jsonb_build_object('context',context_payload);
end $$;

revoke all on function public.prepare_coach_chat_v2(uuid,uuid,text,text,uuid)
  from public, anon, authenticated;
grant execute on function public.prepare_coach_chat_v2(uuid,uuid,text,text,uuid)
  to service_role;
