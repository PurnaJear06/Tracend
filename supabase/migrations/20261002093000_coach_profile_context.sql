-- The Coach reads the onboarding answers that approval now stores on the
-- profile (20261002092000_onboarding_plan_v2.sql). Everything else is
-- unchanged from 20260927230000_coach_chat_v8_full_athlete_context.sql.

create or replace function public.prepare_coach_chat_v8(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prepared jsonb; c jsonb; coaching_date date;
  omitted text[] := '{}';
  section text;
  -- Dropped whole, least important first, only if the file is oversized.
  droppable constant text[] := array[
    'recent_other_conversations', 'session_journal', 'plan_proposals',
    'workout_reconciliations', 'watch_workouts_14d', 'nutrition_daily_28d',
    'health_daily_28d', 'training_log_28d'];
begin
  -- v7 builds the shared base, fresh coaching-date scores, and permitted
  -- evidence. The neutral kind keeps every section independent of the
  -- keyword guess.
  prepared := public.prepare_coach_chat_v7(target_user_id, target_thread_id,
    question, coaching_timezone, request_idempotency_key, 'general');
  if coalesce((prepared->>'replayed')::boolean, false) then
    return prepared || jsonb_build_object(
      'turn', public.coach_chat_turn(target_user_id, request_idempotency_key));
  end if;

  c := prepared->'context';
  coaching_date := coalesce((c->>'coaching_date')::date, current_date);

  -- Onboarding answers that approval writes to the profile (2026-10): sex, age,
  -- daily activity, equipment and the athlete's own notes on limitations and
  -- diet. Equipment is shown only for profiles written by that approval.
  c := c || jsonb_build_object('profile_context',
    coalesce(nullif(c->'profile_context', 'null'::jsonb), '{}'::jsonb) || coalesce((
      select jsonb_strip_nulls(jsonb_build_object(
        'sex', p.sex,
        'age', extract(year from coaching_date)::integer - p.birth_year,
        'daily_activity', p.daily_activity,
        'equipment', case when p.daily_activity is not null then to_jsonb(p.equipment) end,
        'limitations', p.limitations_note,
        'nutrition_notes', p.nutrition_note))
      from public.user_profiles p where p.user_id = target_user_id), '{}'::jsonb));

  -- Conversation memory, rebuilt from coach_messages:
  -- - A labeled data summary was shown to the athlete but not written by the
  --   model, so it never returns to the model as the coach's own words.
  -- - v5's size guard kept the first ten of the last twenty messages, which
  --   are the oldest, so a long thread lost its newest turns (including the
  --   coach's clarifying question). The newest ten are kept; the prompt shows ten.
  -- - Before v8 a question and its answer were saved in one transaction with
  --   the same created_at, so the question is ordered first.
  -- - Each message is capped at 2,000 characters, keeping its ending, so a few
  --   long answers cannot crowd the athlete file out of the size guard. The
  --   prompt itself shows at most the first 300 and last 900 characters.
  c := c || jsonb_build_object(
    'recent_messages', (select coalesce(jsonb_agg(message order by created_at, turn_rank), '[]'::jsonb) from (
      select jsonb_build_object('role', m.role, 'content', case when length(m.content) > 2000
          then left(m.content, 500) || ' … ' || right(m.content, 1400) else m.content end) message,
        m.created_at, case m.role when 'user' then 0 else 1 end turn_rank
      from public.coach_messages m
      where m.user_id = target_user_id and m.thread_id = target_thread_id
        and m.answer_source is distinct from 'data_summary'
      order by m.created_at desc, turn_rank desc limit 10
    ) recent),
    'recent_other_conversations', (select coalesce(jsonb_agg(message order by created_at, turn_rank), '[]'::jsonb) from (
      select jsonb_build_object('role', m.role, 'content', case when length(m.content) > 2000
          then left(m.content, 500) || ' … ' || right(m.content, 1400) else m.content end) message,
        m.created_at, case m.role when 'user' then 0 else 1 end turn_rank
      from public.coach_messages m
      where m.user_id = target_user_id and m.thread_id <> target_thread_id
        and m.answer_source is distinct from 'data_summary'
      order by m.created_at desc, turn_rank desc limit 10
    ) other));

  c := c || public.build_coach_athlete_context(target_user_id, coaching_date, coaching_timezone)
    || jsonb_build_object(
      'schema_version', '8.0',
      'context_kind', case
        when context_kind in ('daily_action','plan_change','explain_evidence','nutrition_focus','recovery')
          then context_kind
        else 'general'
      end);

  foreach section in array droppable loop
    exit when length(c::text) <= 90000;
    if c ? section then
      c := c - section;
      omitted := omitted || section;
    end if;
  end loop;
  c := c || jsonb_build_object('omitted_sections', to_jsonb(omitted));

  if prepared ? 'coach_context_snapshot_id' then
    update public.coach_context_snapshots
    set context = c,
      context_checksum = encode(extensions.digest(convert_to(c::text, 'UTF8'), 'sha256'), 'hex')
    where id = (prepared->>'coach_context_snapshot_id')::uuid and user_id = target_user_id;
  end if;

  return prepared || jsonb_build_object('context', c);
end $$;
