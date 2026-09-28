-- Coach chat v8: one complete athlete file for every question.
--
-- v4 fetched different sections per keyword-guessed topic, and the Edge
-- formatter then deleted more per topic, so a question that mixed topics
-- (workload + weight + diet) reached the model without data it needed.
-- v8 builds the same complete file for every question; context_kind no longer
-- changes data. prepare_coach_chat_v7 stays intact for rollback.
--
-- Also:
-- - record_coach_chat_question saves the user's question when the turn starts,
--   so a failed answer no longer erases it, and bumps last_message_at.
-- - persist_failed_coach_chat_run accepts every provider model_runs allows
--   (it rejected deepseek) and records the finite validation rule names.
-- - persist_coach_chat_data_summary stores the labeled deterministic reply
--   served when the model cannot produce a valid answer.
-- - Conversation memory is rebuilt without labeled data summaries, keeping the
--   newest turns (v5's size guard kept the oldest ten of the last twenty).
-- - A retried request (same idempotency key) reports what its first attempt
--   produced (coach_chat_turn), because a saved question is no longer proof
--   of a completed reply.
-- - Watch-data averages carry a day count per metric.

alter table public.coach_messages
  add column answer_source text check (answer_source in ('model', 'data_summary'));

create or replace function public.build_coach_athlete_context(
  target_user_id uuid, coaching_date date, coaching_timezone text
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  safe_timezone text := 'UTC';
begin
  if exists(select 1 from pg_catalog.pg_timezone_names where name = coaching_timezone) then
    safe_timezone := coaching_timezone;
  end if;

  return jsonb_build_object(
    'training_log_28d', (select coalesce(jsonb_agg(session_row order by local_date desc, started_at desc), '[]'::jsonb) from (
      select s.local_date, s.started_at, jsonb_build_object(
        'local_date', s.local_date,
        'workout', w.name,
        'duration_minutes', round(s.duration_seconds / 60.0),
        'effort', s.session_effort,
        'energy', s.session_energy,
        'completed_sets', totals.completed_sets,
        'volume_kg', totals.volume_kg,
        'avg_rpe', totals.avg_rpe,
        'logging_completeness', s.logging_completeness
      ) session_row
      from public.workout_sessions s
      join public.planned_workouts w on w.id = s.planned_workout_id and w.user_id = s.user_id
      cross join lateral (
        select count(*) filter (where es.completed) completed_sets,
          round(coalesce(sum(es.repetitions * es.load_kg) filter (where es.completed), 0)::numeric, 1) volume_kg,
          round((avg(es.rpe) filter (where es.completed))::numeric, 1) avg_rpe
        from public.exercise_performances ep
        join public.exercise_sets es on es.exercise_performance_id = ep.id and es.user_id = ep.user_id
        where ep.workout_session_id = s.id and ep.user_id = s.user_id
      ) totals
      where s.user_id = target_user_id and s.state = 'completed'
        and s.local_date between coaching_date - 27 and coaching_date
    ) logged),

    'training_totals', (select jsonb_object_agg(window_label, window_totals) from (
      select w.window_label, jsonb_build_object(
        'days', w.days,
        'sessions', count(s.id),
        'total_minutes', round(coalesce(sum(s.duration_seconds), 0) / 60.0),
        'completed_sets', coalesce(sum(t.completed_sets), 0),
        'volume_kg', round(coalesce(sum(t.volume_kg), 0)::numeric, 1)
      ) window_totals
      from (values ('last_7_days', 7), ('last_14_days', 14), ('last_28_days', 28)) w(window_label, days)
      left join public.workout_sessions s on s.user_id = target_user_id and s.state = 'completed'
        and s.local_date between coaching_date - (w.days - 1) and coaching_date
      left join lateral (
        select count(*) filter (where es.completed) completed_sets,
          coalesce(sum(es.repetitions * es.load_kg) filter (where es.completed), 0) volume_kg
        from public.exercise_performances ep
        join public.exercise_sets es on es.exercise_performance_id = ep.id and es.user_id = ep.user_id
        where ep.workout_session_id = s.id and ep.user_id = s.user_id
      ) t on true
      group by w.window_label, w.days
    ) windows),

    'watch_workouts_14d', (select coalesce(jsonb_agg(workout order by started_at desc), '[]'::jsonb) from (
      select h.started_at, jsonb_build_object(
        'local_date', (h.started_at at time zone safe_timezone)::date,
        'activity_type', h.activity_type,
        'duration_minutes', round(h.duration_seconds / 60.0)
      ) workout
      from public.health_workout_references h
      where h.user_id = target_user_id
        and (h.started_at at time zone safe_timezone)::date between coaching_date - 13 and coaching_date
      order by h.started_at desc limit 40
    ) workouts),

    'training_week_structure', (select jsonb_build_object(
      'sessions_per_week', v.sessions_per_week, 'block_weeks', v.block_weeks,
      'planned_workouts', (select coalesce(jsonb_agg(jsonb_build_object(
        'name', pw.name, 'target_day', pw.preferred_weekday
      ) order by pw.preferred_weekday, pw.workout_order), '[]'::jsonb)
      from public.planned_workouts pw
      where pw.user_id = target_user_id and pw.plan_version_id = v.id)
    ) from public.training_plan_versions v where v.user_id = target_user_id and v.status = 'active' limit 1),

    'health_daily_28d', (select coalesce(jsonb_agg(day_row order by local_date desc), '[]'::jsonb) from (
      select local_date, jsonb_build_object(
        'local_date', local_date,
        'sleep_minutes', sleep_minutes,
        'resting_heart_rate_bpm', resting_heart_rate_bpm,
        'hrv_ms', hrv_value_ms,
        'steps', steps,
        'active_energy_kcal', active_energy_kcal,
        'workout_minutes', workout_minutes,
        'weight_kg', weight_kg,
        'completeness', completeness
      ) day_row
      from public.daily_health_summaries
      where user_id = target_user_id and local_date between coaching_date - 27 and coaching_date
    ) days),

    -- Each average skips days its metric was not measured, so each carries
    -- its own day count: a week of steps with one measured night is one
    -- night of sleep evidence, not seven.
    'health_averages', jsonb_build_object(
      'last_7_days', (select jsonb_build_object(
        'days_synced', count(*),
        'days_with_sleep', count(sleep_minutes),
        'avg_sleep_minutes', round(avg(sleep_minutes)::numeric, 0),
        'days_with_resting_heart_rate', count(resting_heart_rate_bpm),
        'avg_resting_heart_rate_bpm', round(avg(resting_heart_rate_bpm)::numeric, 1),
        'days_with_hrv', count(hrv_value_ms),
        'avg_hrv_ms', round(avg(hrv_value_ms)::numeric, 1),
        'days_with_steps', count(steps),
        'avg_steps', round(avg(steps)::numeric, 0))
        from public.daily_health_summaries
        where user_id = target_user_id and local_date between coaching_date - 6 and coaching_date),
      'last_28_days', (select jsonb_build_object(
        'days_synced', count(*),
        'days_with_sleep', count(sleep_minutes),
        'avg_sleep_minutes', round(avg(sleep_minutes)::numeric, 0),
        'days_with_resting_heart_rate', count(resting_heart_rate_bpm),
        'avg_resting_heart_rate_bpm', round(avg(resting_heart_rate_bpm)::numeric, 1),
        'days_with_hrv', count(hrv_value_ms),
        'avg_hrv_ms', round(avg(hrv_value_ms)::numeric, 1),
        'days_with_steps', count(steps),
        'avg_steps', round(avg(steps)::numeric, 0))
        from public.daily_health_summaries
        where user_id = target_user_id and local_date between coaching_date - 27 and coaching_date)
    ),

    'weight_series_8w', (select coalesce(jsonb_agg(point order by measured_on desc, created_at desc), '[]'::jsonb) from (
      select bm.measured_on, bm.created_at, jsonb_build_object(
        'measured_on', bm.measured_on, 'weight_kg', bm.weight_kg, 'waist_cm', bm.waist_cm, 'source', bm.source
      ) point
      from public.body_measurements bm
      where bm.user_id = target_user_id and bm.weight_kg is not null
        and bm.measured_on between coaching_date - 55 and coaching_date
        and not exists(select 1 from public.body_measurements newer
          where newer.user_id = bm.user_id and newer.amended_from_id = bm.id)
      order by bm.measured_on desc, bm.created_at desc limit 60
    ) points),

    'check_ins_14d', (select coalesce(jsonb_agg(entry order by local_date desc), '[]'::jsonb) from (
      select local_date, jsonb_build_object(
        'local_date', local_date, 'sleep_quality', sleep_quality, 'energy', energy,
        'soreness', soreness, 'hunger', hunger, 'mood', mood,
        'pain_severity', pain_severity, 'available_to_train', available_to_train
      ) entry
      from public.daily_check_ins
      where user_id = target_user_id and superseded_at is null
        and local_date between coaching_date - 13 and coaching_date
    ) entries),

    'nutrition_daily_28d', (select coalesce(jsonb_agg(day_row order by local_date desc), '[]'::jsonb) from (
      select m.local_date, jsonb_build_object(
        'local_date', m.local_date,
        'confirmed_meals', count(distinct m.id),
        'calories', round(coalesce(sum(i.calories), 0)::numeric, 0),
        'protein_g', round(coalesce(sum(i.protein_g), 0)::numeric, 0),
        'carbohydrate_g', round(coalesce(sum(i.carbohydrate_g), 0)::numeric, 0),
        'fat_g', round(coalesce(sum(i.fat_g), 0)::numeric, 0)
      ) day_row
      from public.meals m
      join public.meal_items i on i.meal_id = m.id and i.user_id = m.user_id
      where m.user_id = target_user_id and m.status = 'confirmed'
        and m.local_date between coaching_date - 27 and coaching_date
      group by m.local_date
    ) days),

    'today_confirmed_meals', (select coalesce(jsonb_agg(meal order by created_at desc), '[]'::jsonb) from (
      select m.created_at, jsonb_build_object(
        'created_at', m.created_at, 'local_date', m.local_date,
        'foods', (select coalesce(jsonb_agg(jsonb_build_object(
          'food', mi.name_snapshot, 'serving', mi.serving_label,
          'calories', mi.calories, 'protein_g', mi.protein_g,
          'carbohydrate_g', mi.carbohydrate_g, 'fat_g', mi.fat_g
        )), '[]'::jsonb)
        from public.meal_items mi where mi.meal_id = m.id and mi.user_id = m.user_id)
      ) meal
      from public.meals m
      where m.user_id = target_user_id and m.status = 'confirmed' and m.local_date = coaching_date
      order by m.created_at desc limit 8
    ) meals),

    'nutrition_adherence', jsonb_build_object(
      'days_with_confirmed_meals_7d', (select count(distinct m.local_date)
        from public.meals m where m.user_id = target_user_id
          and m.status = 'confirmed' and m.local_date between coaching_date - 6 and coaching_date),
      'confirmed_meal_count_7d', (select count(*)
        from public.meals where user_id = target_user_id
          and status = 'confirmed' and local_date between coaching_date - 6 and coaching_date)
    ),

    'plan_proposals', (select coalesce(jsonb_agg(proposal order by created_at desc), '[]'::jsonb) from (
      select created_at, jsonb_build_object(
        'status', status, 'proposed_training', proposed_training,
        'proposed_nutrition', proposed_nutrition, 'rationale', coalesce(rationale, ''),
        'confidence', confidence, 'effective_date', effective_date
      ) proposal
      from public.change_proposals where user_id = target_user_id
      order by created_at desc limit 3
    ) proposals),

    'workout_reconciliations', (select coalesce(jsonb_agg(reconciliation order by started_at desc), '[]'::jsonb) from (
      select h.started_at, jsonb_build_object(
        'status', r.status, 'confidence', r.confidence, 'activity_type', h.activity_type,
        'duration_difference_seconds', r.duration_difference_seconds
      ) reconciliation
      from public.workout_reconciliations r
      join public.health_workout_references h on h.id = r.health_workout_reference_id and h.user_id = r.user_id
      where r.user_id = target_user_id
      order by h.started_at desc limit 5
    ) reconciliations),

    'data_quality', jsonb_build_object(
      'training_logging_coverage', (select round(coalesce(avg(logging_completeness), 0)::numeric, 2)
        from public.workout_sessions where user_id = target_user_id
          and state = 'completed' and local_date >= coaching_date - 27),
      'last_health_sync', (select max(last_synced_at)
        from public.daily_health_summaries where user_id = target_user_id),
      'last_check_in', (select max(local_date)
        from public.daily_check_ins where user_id = target_user_id and superseded_at is null),
      'last_confirmed_meal', (select max(created_at)
        from public.meals where user_id = target_user_id and status = 'confirmed'),
      'last_measurement', (select max(measured_on)
        from public.body_measurements where user_id = target_user_id),
      'last_completed_workout', (select max(local_date)
        from public.workout_sessions where user_id = target_user_id and state = 'completed'),
      'conflict_count', (select count(*)
        from public.workout_reconciliations where user_id = target_user_id and status = 'conflict')
    )
  );
end $$;

revoke all on function public.build_coach_athlete_context(uuid,date,text)
  from public, anon, authenticated;
grant execute on function public.build_coach_athlete_context(uuid,date,text)
  to service_role;

-- What a request's first attempt produced. The question is saved when a turn
-- starts, so a saved question alone is not a completed reply: the turn is
-- answered (a model answer or a labeled data summary), failed, or still in
-- progress.
create or replace function public.coach_chat_turn(
  target_user_id uuid, request_idempotency_key uuid
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  question_row public.coach_messages%rowtype;
  run public.model_runs%rowtype;
  reply public.coach_messages%rowtype;
begin
  select * into question_row from public.coach_messages
  where user_id = target_user_id and idempotency_key = request_idempotency_key;
  select * into run from public.model_runs
  where user_id = target_user_id and idempotency_key = request_idempotency_key;
  -- persist_coach_chat_data_summary keys the summary from the request key.
  select * into reply from public.coach_messages
  where user_id = target_user_id
    and idempotency_key = md5(request_idempotency_key::text || ':data_summary')::uuid;
  -- persist_coach_chat_result stores a model answer with its run, in one
  -- transaction.
  if reply.id is null and run.status = 'succeeded' then
    select * into reply from public.coach_messages
    where user_id = target_user_id and thread_id = question_row.thread_id
      and role = 'assistant' and created_at >= run.created_at
    order by created_at limit 1;
  end if;
  return jsonb_build_object(
    'state', case when reply.id is not null then 'answered'
      when run.id is not null then 'failed' else 'in_progress' end,
    'failure_code', run.sanitized_error_code,
    'model_provider', run.provider,
    'model', run.model,
    'message', case when reply.id is not null then jsonb_build_object(
      'id', reply.id, 'content', reply.content, 'evidence', reply.evidence,
      'missing_data', to_jsonb(reply.missing_data), 'safety_state', reply.safety_state,
      'answer_source', reply.answer_source, 'created_at', reply.created_at) end);
end $$;

revoke all on function public.coach_chat_turn(uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.coach_chat_turn(uuid,uuid)
  to service_role;

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

revoke all on function public.prepare_coach_chat_v8(uuid,uuid,text,text,uuid,text)
  from public, anon, authenticated;
grant execute on function public.prepare_coach_chat_v8(uuid,uuid,text,text,uuid,text)
  to service_role;

create or replace function public.record_coach_chat_question(
  target_user_id uuid, target_thread_id uuid, question text, request_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare message_id uuid;
begin
  if not exists(select 1 from public.coach_threads
    where id = target_thread_id and user_id = target_user_id and status = 'active') then
    raise exception 'thread not found' using errcode = 'P0002';
  end if;
  if question is null or length(trim(question)) not between 1 and 2000 then
    raise exception 'invalid question' using errcode = '22023';
  end if;
  -- Same idempotency key as persist_coach_chat_result, so a successful answer
  -- reuses this row instead of inserting the question twice.
  insert into public.coach_messages(user_id, thread_id, role, content, idempotency_key)
  values(target_user_id, target_thread_id, 'user', trim(question), request_idempotency_key)
  on conflict(user_id, idempotency_key) where idempotency_key is not null
  do update set idempotency_key = excluded.idempotency_key
  returning id into message_id;
  update public.coach_threads
  set last_message_at = now(), updated_at = now(),
    title = case when title = 'New conversation' then left(trim(question), 80) else title end
  where id = target_thread_id and user_id = target_user_id;
  return message_id;
end $$;

revoke all on function public.record_coach_chat_question(uuid,uuid,text,uuid)
  from public, anon, authenticated;
grant execute on function public.record_coach_chat_question(uuid,uuid,text,uuid)
  to service_role;

-- Replaced with a superset signature: the new trailing argument has a default,
-- so the currently deployed Edge Function's eight-argument call still resolves
-- while this migration is live and before the new function version deploys.
drop function public.persist_failed_coach_chat_run(uuid,uuid,uuid,uuid,integer,text,text,text);

create function public.persist_failed_coach_chat_run(
  target_user_id uuid, snapshot_id uuid, policy_id uuid, request_idempotency_key uuid,
  run_latency_ms integer, error_code text, run_provider text, run_model text,
  failure_rules text[] default '{}'::text[]
) returns uuid language plpgsql security definer set search_path = '' as $$
declare run_id uuid;
begin
  if error_code is null or length(error_code) not between 1 and 80
    or run_provider not in ('mock','gemini','groq','deepseek')
    or run_model is null or length(run_model) not between 1 and 120
    or failure_rules is null or cardinality(failure_rules) > 4
    or exists(select 1 from unnest(failure_rules) as r(rule_name) where r.rule_name !~ '^[a-z_]{1,64}$')
  then raise exception 'invalid failure metadata' using errcode = '22023'; end if;
  if not exists(select 1 from public.policy_evaluations
    where id = policy_id and user_id = target_user_id and feature_snapshot_id = snapshot_id) then
    raise exception 'policy not found' using errcode = 'P0002';
  end if;
  select id into run_id from public.model_runs
  where user_id = target_user_id and idempotency_key = request_idempotency_key;
  if run_id is not null then return run_id; end if;
  insert into public.model_runs(user_id, feature_snapshot_id, policy_evaluation_id, idempotency_key,
    purpose, provider, model, prompt_version, schema_version, status, validation_status,
    latency_ms, sanitized_error_code)
  values(target_user_id, snapshot_id, policy_id, request_idempotency_key,
    'coach_chat', run_provider, run_model, 'coach-chat-v1', '1.0', 'failed', 'failed',
    run_latency_ms, error_code)
  returning id into run_id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values(target_user_id, 'coach.chat.model_run.failed', 'model_run', run_id, 'rejected',
    jsonb_build_object('error_code', error_code, 'schema_version', '1.0',
      'provider', run_provider, 'model', run_model, 'rules', to_jsonb(failure_rules)));
  return run_id;
end $$;

revoke all on function public.persist_failed_coach_chat_run(uuid,uuid,uuid,uuid,integer,text,text,text,text[])
  from public, anon, authenticated;
grant execute on function public.persist_failed_coach_chat_run(uuid,uuid,uuid,uuid,integer,text,text,text,text[])
  to service_role;

create or replace function public.persist_coach_chat_data_summary(
  target_user_id uuid, target_thread_id uuid, request_idempotency_key uuid, summary_payload jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  message_id uuid;
  message_created_at timestamptz;
  -- Derived from the request key so a retried request stores one reply.
  summary_key uuid := md5(request_idempotency_key::text || ':data_summary')::uuid;
begin
  if not exists(select 1 from public.coach_threads
    where id = target_thread_id and user_id = target_user_id and status = 'active') then
    raise exception 'thread not found' using errcode = 'P0002';
  end if;
  if jsonb_typeof(summary_payload) <> 'object'
    or length(summary_payload->>'answer') not between 1 and 12000
    or jsonb_typeof(summary_payload->'evidence') <> 'array'
    or jsonb_typeof(summary_payload->'missing_data') <> 'array'
    or summary_payload->>'safety_state' not in ('allowed','limited','refused','unavailable')
  then raise exception 'invalid data summary' using errcode = '22023'; end if;
  if exists(select 1 from jsonb_array_elements(summary_payload->'evidence') e
    where not (e ? 'code' and e ? 'label' and e ? 'source')) then
    raise exception 'invalid evidence' using errcode = '22023';
  end if;
  insert into public.coach_messages(user_id, thread_id, role, content, evidence, missing_data,
    safety_state, idempotency_key, answer_source)
  values(target_user_id, target_thread_id, 'assistant', summary_payload->>'answer',
    summary_payload->'evidence',
    array(select jsonb_array_elements_text(summary_payload->'missing_data')),
    summary_payload->>'safety_state', summary_key, 'data_summary')
  on conflict(user_id, idempotency_key) where idempotency_key is not null
  do update set idempotency_key = excluded.idempotency_key
  returning id, created_at into message_id, message_created_at;
  update public.coach_threads set last_message_at = now(), updated_at = now()
  where id = target_thread_id and user_id = target_user_id;
  return jsonb_build_object('assistant_message_id', message_id, 'created_at', message_created_at);
end $$;

revoke all on function public.persist_coach_chat_data_summary(uuid,uuid,uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.persist_coach_chat_data_summary(uuid,uuid,uuid,jsonb)
  to service_role;
