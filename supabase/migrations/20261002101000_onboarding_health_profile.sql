-- Final onboarding batch, server part (2026-10-02, PR B of 4).
--
-- 1. AI notice ai-coaching-v4, current for every purpose. It adds the Apple
--    Health summary and movements to avoid to what the starting plan sends.
--    One notice for all purposes also means the app's notice (the one current
--    for the most purposes) is the one the onboarding plan checks; with v1
--    current for the Coach and v2 for the plan, a new athlete's grant never
--    counted for the plan. Using v4 avoids a clash with a v3 the owner may
--    have published by hand.
-- 2. set_my_timezone: the app stores the device's IANA time zone, so local
--    dates (the Coach, check-ins, health sync, onboarding) stop defaulting to
--    UTC for new accounts.
-- 3. user_profiles.avoid_patterns and equipment_note, written by approval, so
--    the Coach knows the movements an athlete avoids. The current plan text is
--    deliberately not kept: the approved plan replaces it, and the onboarding
--    snapshot keeps it for the audit trail.
-- 4. Approval dates the plan, nutrition targets and onboarding weight with the
--    athlete's local date at approval, not the server's UTC date at generation.
-- 5. prepare_coach_chat_v8 adds the avoided movements and equipment note to the
--    profile context; everything else is unchanged from
--    20261002093000_coach_profile_context.sql.

select private.publish_ai_notice(
  'ai-coaching-v4',
  'DeepSeek',
  array['coach_chat','daily_coaching','onboarding_plan'],
  'Your starting plan, the Coach chat and your daily decision are written by an AI model. To '
  'write your starting plan, Tracend sends DeepSeek your onboarding answers: goal, age, sex, '
  'height, weight, daily activity, training days and session length, equipment, limitations, '
  'movements to avoid, diet notes and, if you have one, your current plan. If you connected '
  'Apple Health, it also sends a summary of your last 4 weeks: average steps, active energy and '
  'sleep, workouts per week, and your weight trend. For the Coach chat and daily decision it '
  'sends your training plan and workout logs, check-ins, Apple Health summaries (sleep, heart '
  'rate, HRV, steps and workouts), meals and nutrition targets, body measurements, goals and '
  'preferences, and the messages you send the Coach. Your name, email address and photos are '
  'not sent.' || E'\n\n' ||
  'DeepSeek is run by Hangzhou DeepSeek Artificial Intelligence Co., Ltd. and processes this '
  'data on servers in China. Its terms, not Tracend''s, decide how long it keeps requests.'
  || E'\n\n' ||
  'Tracend checks every AI plan against its safety ranges, and nothing starts until you approve '
  'it. Without AI coaching, Tracend builds your starting plan with its own rules, and your plan, '
  'logging, Apple Health sync and progress keep working; the Coach chat and AI daily decisions '
  'stay off. You can change this at any time in Account.'
);

-- The athlete's local date; an unset or unknown time zone reads as UTC.
create function private.local_date_for(target_user_id uuid)
returns date language sql stable set search_path = '' as $$
  select (statement_timestamp() at time zone coalesce((
    select a.timezone from public.user_accounts a
    join pg_catalog.pg_timezone_names z on z.name = a.timezone
    where a.id = target_user_id), 'UTC'))::date;
$$;
revoke all on function private.local_date_for(uuid) from public, anon, authenticated;

create function public.set_my_timezone(timezone_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if timezone_name is null or length(timezone_name) not between 1 and 64
    or not exists (select 1 from pg_catalog.pg_timezone_names where name = timezone_name) then
    raise exception 'unknown time zone' using errcode = '22023';
  end if;
  update public.user_accounts set timezone = timezone_name
    where id = auth.uid() and timezone is distinct from timezone_name;
  return jsonb_build_object('schema_version', '1.0', 'timezone', timezone_name);
end $$;
revoke all on function public.set_my_timezone(text) from public, anon;
grant execute on function public.set_my_timezone(text) to authenticated;

alter table public.user_profiles
  add column avoid_patterns text[] check (avoid_patterns <@ array[
    'squat','lunge','hinge','horizontal_push','vertical_push','horizontal_pull','vertical_pull']),
  add column equipment_note text check (length(equipment_note) <= 500);

create or replace function public.respond_to_onboarding_proposal_v2(
  proposal_id uuid,
  response_action public.proposal_response_action,
  revision_note text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  proposal public.change_proposals%rowtype;
  answers jsonb;
  note text := nullif(btrim(respond_to_onboarding_proposal_v2.revision_note), '');
  new_goal_id uuid;
  new_plan_id uuid;
  plan_version_id uuid;
  nutrition_id uuid;
  new_workout_id uuid;
  workout jsonb;
  exercise jsonb;
  approval_date date;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if note is not null and length(note) > 500 then
    raise exception 'revision note too long' using errcode = '22023';
  end if;

  select * into proposal from public.change_proposals
    where id = respond_to_onboarding_proposal_v2.proposal_id and user_id = auth.uid()
    for update;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  if proposal.schema_version <> '2.0' then
    raise exception 'proposal is not a 2.0 proposal' using errcode = '22023';
  end if;
  if proposal.status <> 'pending' then
    raise exception 'proposal is not pending' using errcode = '55000';
  end if;
  -- An expired proposal is recorded as expired and reported, not raised: a
  -- raise would roll the status back and leave it pending forever.
  if proposal.expires_at <= statement_timestamp() then
    update public.change_proposals set status = 'expired' where id = proposal.id;
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (auth.uid(), 'onboarding_proposal_expired', 'change_proposal', proposal.id, 'succeeded',
      jsonb_build_object('schema_version', proposal.schema_version));
    return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
      'status', 'expired', 'training_plan_version_id', null, 'nutrition_target_set_id', null);
  end if;

  if response_action = 'accept' then
    if not private.is_valid_initial_proposal_v2(proposal.proposed_training, proposal.proposed_nutrition)
      or not private.proposal_uses_active_catalog(proposal.proposed_training) then
      raise exception 'proposal payload is invalid' using errcode = '22023';
    end if;
    select s.features -> 'answers' into answers from public.feature_snapshots s
      where s.id = proposal.feature_snapshot_id and s.user_id = auth.uid();
    approval_date := private.local_date_for(auth.uid());

    update public.training_plan_versions set status = 'superseded'
      where user_id = auth.uid() and status = 'active';
    update public.nutrition_target_sets set status = 'superseded'
      where user_id = auth.uid() and status = 'active';

    update public.user_goals set status = 'superseded'
      where user_id = auth.uid() and status = 'active';
    select id into new_goal_id from public.user_goals
      where user_id = auth.uid() and status = 'draft'
      order by created_at desc limit 1;
    if new_goal_id is null then
      insert into public.user_goals(user_id, goal_type, priority, status)
      values (auth.uid(), (answers ->> 'goal')::public.goal_type, 1, 'draft')
      returning id into new_goal_id;
    end if;
    update public.user_goals set
      goal_type = (answers ->> 'goal')::public.goal_type,
      priority = 1,
      status = 'active',
      activated_at = now(),
      details = (details - 'target_weight_kg') || jsonb_strip_nulls(
        jsonb_build_object('target_weight_kg', answers -> 'target_weight_kg'))
    where id = new_goal_id;

    insert into public.training_plans(user_id, goal_id, title, source)
    values (auth.uid(), new_goal_id, proposal.proposed_training ->> 'title',
      proposal.proposed_training ->> 'origin')
    returning id into new_plan_id;

    insert into public.training_plan_versions(
      user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
      prescription, rationale, source_proposal_id, approved_at, effective_date
    ) values (
      auth.uid(), new_plan_id, 1, 'active',
      (proposal.proposed_training ->> 'block_weeks')::smallint,
      jsonb_array_length(proposal.proposed_training -> 'weekly_structure')::smallint,
      proposal.proposed_training -> 'prescription', proposal.rationale,
      proposal.id, statement_timestamp(), approval_date
    ) returning id into plan_version_id;

    for workout in select value from jsonb_array_elements(proposal.proposed_training -> 'weekly_structure') loop
      insert into public.planned_workouts(
        user_id, plan_version_id, workout_order, name, objective, preferred_weekday,
        estimated_minutes, warm_up_guidance, cool_down_guidance
      ) values (
        auth.uid(), plan_version_id, (workout ->> 'workout_order')::smallint, workout ->> 'name',
        workout ->> 'objective', (workout ->> 'preferred_weekday')::smallint,
        (workout ->> 'estimated_minutes')::smallint, workout ->> 'warm_up_guidance',
        workout ->> 'cool_down_guidance'
      ) returning id into new_workout_id;
      for exercise in select value from jsonb_array_elements(workout -> 'exercises') loop
        insert into public.planned_exercises(
          user_id, planned_workout_id, exercise_order, display_name_snapshot, set_count,
          rep_min, rep_max, target_rpe, rest_seconds, notes, exercise_slug
        ) values (
          auth.uid(), new_workout_id, (exercise ->> 'exercise_order')::smallint,
          exercise ->> 'name', (exercise ->> 'sets')::smallint,
          (exercise ->> 'rep_min')::smallint, (exercise ->> 'rep_max')::smallint,
          (exercise ->> 'target_rpe')::numeric, (exercise ->> 'rest_seconds')::smallint,
          coalesce(exercise ->> 'notes', ''), exercise ->> 'slug'
        );
      end loop;
    end loop;

    insert into public.nutrition_target_sets(
      user_id, version_number, status, calories, protein_g, carbohydrate_g,
      fat_g, rationale, source_proposal_id, approved_at, effective_date
    ) values (
      auth.uid(),
      coalesce((select max(version_number) + 1 from public.nutrition_target_sets
        where user_id = auth.uid()), 1),
      'active',
      (proposal.proposed_nutrition ->> 'calories')::integer,
      (proposal.proposed_nutrition ->> 'protein_g')::integer,
      (proposal.proposed_nutrition ->> 'carbohydrate_g')::integer,
      (proposal.proposed_nutrition ->> 'fat_g')::integer,
      coalesce(nullif(proposal.proposed_nutrition ->> 'rationale', ''), proposal.rationale),
      proposal.id, statement_timestamp(), approval_date
    ) returning id into nutrition_id;

    insert into public.user_profiles(
      user_id, experience_level, height_cm, training_days, session_minutes, sex,
      birth_year, daily_activity, equipment, limitations_note, nutrition_note,
      avoid_patterns, equipment_note
    ) values (
      auth.uid(),
      (answers ->> 'experience')::public.experience_level,
      (answers ->> 'height_cm')::numeric,
      array(select value::smallint from jsonb_array_elements_text(answers -> 'training_weekdays') value),
      (answers ->> 'session_minutes')::smallint,
      answers ->> 'sex',
      (answers ->> 'birth_year')::smallint,
      answers ->> 'daily_activity',
      array(select value from jsonb_array_elements_text(answers -> 'equipment_items') value),
      nullif(answers ->> 'limitations', ''),
      nullif(answers ->> 'nutrition_context', ''),
      array(select value from jsonb_array_elements_text(
        coalesce(answers -> 'avoid_patterns', '[]'::jsonb)) value),
      nullif(answers ->> 'equipment_note', '')
    )
    on conflict (user_id) do update set
      experience_level = excluded.experience_level,
      height_cm = excluded.height_cm,
      training_days = excluded.training_days,
      session_minutes = excluded.session_minutes,
      sex = excluded.sex,
      birth_year = excluded.birth_year,
      daily_activity = excluded.daily_activity,
      equipment = excluded.equipment,
      limitations_note = excluded.limitations_note,
      nutrition_note = excluded.nutrition_note,
      avoid_patterns = excluded.avoid_patterns,
      equipment_note = excluded.equipment_note;

    -- The onboarding weight becomes the first measurement, unless the athlete
    -- already has one for that day.
    if answers -> 'weight_kg' is not null and not exists (
      select 1 from public.body_measurements
      where user_id = auth.uid() and measured_on = approval_date
        and superseded_at is null
    ) then
      insert into public.body_measurements(user_id, measured_on, source, weight_kg, protocol_version)
      values (auth.uid(), approval_date, 'manual',
        (answers ->> 'weight_kg')::numeric, 'onboarding-v1');
    end if;

    update public.change_proposals set status = 'accepted' where id = proposal.id;
    update public.user_accounts set onboarding_state = 'completed' where id = auth.uid();
  elsif response_action = 'reject' then
    update public.change_proposals set status = 'rejected' where id = proposal.id;
  else
    update public.change_proposals set status = 'revision_requested' where id = proposal.id;
  end if;

  insert into public.change_responses(user_id, proposal_id, action, revision_note)
  values (auth.uid(), proposal.id, response_action,
    case when response_action = 'request_revision' then note end);

  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'onboarding_proposal_' || response_action::text, 'change_proposal',
    proposal.id, 'succeeded', jsonb_build_object('schema_version', proposal.schema_version,
      'origin', proposal.proposed_training ->> 'origin'));

  return jsonb_build_object(
    'schema_version', '1.0',
    'proposal_id', proposal.id,
    'status', case response_action
      when 'accept' then 'accepted'
      when 'reject' then 'rejected'
      else 'revision_requested'
    end,
    'training_plan_version_id', plan_version_id,
    'nutrition_target_set_id', nutrition_id
  );
end $$;

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
  -- daily activity, equipment, the athlete's own notes on limitations, diet and
  -- equipment, and the movement patterns they asked to avoid. Equipment is
  -- shown only for profiles written by that approval.
  c := c || jsonb_build_object('profile_context',
    coalesce(nullif(c->'profile_context', 'null'::jsonb), '{}'::jsonb) || coalesce((
      select jsonb_strip_nulls(jsonb_build_object(
        'sex', p.sex,
        'age', extract(year from coaching_date)::integer - p.birth_year,
        'daily_activity', p.daily_activity,
        'equipment', case when p.daily_activity is not null then to_jsonb(p.equipment) end,
        'limitations', p.limitations_note,
        'nutrition_notes', p.nutrition_note,
        'movements_to_avoid', case when cardinality(p.avoid_patterns) > 0
          then to_jsonb(p.avoid_patterns) end,
        'equipment_note', p.equipment_note))
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
