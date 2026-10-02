-- Review fixes for the onboarding plan (PR #61 review, 2026-10-02).
--
-- 1. Movements to avoid: a stored proposal may not use an exercise whose
--    movement pattern the athlete's reviewed answers avoid. The Edge Function
--    already leaves them out of both the AI and the rules plan; this is the
--    last check before the athlete can approve it.
-- 2. Expired proposals: the app's generation status reports a pending
--    proposal past its expiry as expired, with its expiry time, so the app
--    offers a rebuild instead of buttons that cannot work. Answering an expired
--    proposal now records the expiry and returns status 'expired' instead of
--    raising, which rolled the update back and left it pending.
--
-- respond_to_onboarding_proposal (v1, used by older apps) is unchanged: those
-- apps expect the stale error.

create function private.proposal_avoids_patterns(training jsonb, avoid jsonb)
returns boolean language sql stable set search_path = '' as $$
  select jsonb_typeof(coalesce(avoid, '[]'::jsonb)) = 'array' and not exists (
    select 1
    from jsonb_array_elements(training -> 'weekly_structure') workout,
      jsonb_array_elements(workout -> 'exercises') exercise
    join public.exercise_catalog catalog on catalog.slug = exercise ->> 'slug'
    where catalog.movement_pattern in (
      select jsonb_array_elements_text(coalesce(avoid, '[]'::jsonb)))
  );
$$;
revoke all on function private.proposal_avoids_patterns(jsonb, jsonb)
from public, anon, authenticated;

create or replace function public.persist_onboarding_proposal_v2(
  target_generation_id uuid,
  target_user_id uuid,
  target_snapshot_hash text,
  snapshot_features jsonb,
  training_payload jsonb,
  nutrition_payload jsonb,
  evidence_payload jsonb,
  proposal_rationale text,
  proposal_benefit text,
  proposal_downside text,
  proposal_confidence text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  generation public.onboarding_generations%rowtype;
  snapshot_id uuid;
  new_proposal_id uuid;
begin
  select * into generation from public.onboarding_generations
    where id = target_generation_id and user_id = target_user_id for update;
  if not found or generation.status <> 'running'
    or generation.snapshot_hash <> target_snapshot_hash then
    raise exception 'generation is not current' using errcode = '55000';
  end if;

  if not exists (
    select 1 from public.user_profiles
    where user_id = target_user_id and eligible is true and adult_attested_at is not null
  ) then
    raise exception 'eligible adult profile required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.onboarding_drafts where user_id = target_user_id and path is not null
  ) then
    raise exception 'onboarding draft required' using errcode = '22023';
  end if;
  if exists (
    select 1 from (values ('terms'::public.consent_type), ('privacy'::public.consent_type)) needed(kind)
    where coalesce((
      select c.action = 'granted' from public.consent_records c
      where c.user_id = target_user_id and c.consent_type = needed.kind
      order by c.created_at desc, c.id desc limit 1
    ), false) is false
  ) then
    raise exception 'current terms and privacy consent required' using errcode = '22023';
  end if;
  if not private.is_valid_initial_proposal_v2(training_payload, nutrition_payload)
    or not private.proposal_uses_active_catalog(training_payload)
    or not private.proposal_avoids_patterns(training_payload,
      snapshot_features -> 'answers' -> 'avoid_patterns')
    or jsonb_typeof(evidence_payload) <> 'array'
    or jsonb_typeof(snapshot_features) <> 'object'
  then
    raise exception 'onboarding proposal is invalid' using errcode = '22023';
  end if;

  insert into public.feature_snapshots(
    user_id, trigger_kind, schema_version, feature_engine_version,
    features, coverage, missing_data, data_hash
  ) values (
    target_user_id, 'onboarding', '2.0', 'onboarding-policy-v1',
    snapshot_features, jsonb_build_object('onboarding', 'complete'), '{}', target_snapshot_hash
  )
  on conflict (user_id, data_hash) do nothing
  returning id into snapshot_id;
  if snapshot_id is null then
    select id into snapshot_id from public.feature_snapshots
      where user_id = target_user_id and data_hash = target_snapshot_hash;
  end if;

  insert into public.change_proposals(
    user_id, feature_snapshot_id, schema_version, proposed_training,
    proposed_nutrition, evidence, rationale, expected_benefit, downside,
    confidence, effective_date, expires_at
  ) values (
    target_user_id, snapshot_id, '2.0', training_payload,
    nutrition_payload, evidence_payload, proposal_rationale, proposal_benefit,
    proposal_downside, proposal_confidence, current_date,
    statement_timestamp() + interval '7 days'
  ) returning id into new_proposal_id;

  update public.onboarding_generations
    set status = 'succeeded', proposal_id = new_proposal_id, updated_at = now()
    where id = target_generation_id;

  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (target_user_id, 'onboarding.plan.generated', 'onboarding_generation',
    target_generation_id, 'succeeded', jsonb_strip_nulls(jsonb_build_object(
      'proposal_id', new_proposal_id,
      'origin', training_payload ->> 'origin',
      'provider', training_payload ->> 'provider',
      'model', training_payload ->> 'model',
      'fallback_reason', training_payload ->> 'fallback_reason',
      'policy_version', training_payload ->> 'policy_version')));
  return new_proposal_id;
end $$;

-- The app's view of its newest generation. A running generation whose lease
-- ran out reads as failed, and a pending proposal past its expiry reads as
-- expired, so the app never waits on, or offers, something that cannot work.
create or replace function public.get_my_onboarding_generation()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'generation_id', g.id,
    'status', case when g.status = 'running' and g.lease_expires_at <= now() then 'failed'
      else g.status end,
    'error_code', case when g.status = 'running' and g.lease_expires_at <= now()
      then 'lease_expired' else g.error_code end,
    'proposal_id', g.proposal_id,
    'proposal_status', case when p.status = 'pending' and p.expires_at <= now() then 'expired'
      else p.status::text end,
    'proposal_expires_at', p.expires_at,
    'started_at', g.created_at)
  from public.onboarding_generations g
  left join public.change_proposals p on p.id = g.proposal_id and p.user_id = g.user_id
  where g.user_id = auth.uid()
  -- attempt breaks ties between generations started in one transaction.
  order by g.created_at desc, g.attempt desc
  limit 1;
$$;

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
      proposal.id, statement_timestamp(), proposal.effective_date
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
      proposal.id, statement_timestamp(), proposal.effective_date
    ) returning id into nutrition_id;

    insert into public.user_profiles(
      user_id, experience_level, height_cm, training_days, session_minutes, sex,
      birth_year, daily_activity, equipment, limitations_note, nutrition_note
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
      nullif(answers ->> 'nutrition_context', '')
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
      nutrition_note = excluded.nutrition_note;

    -- The onboarding weight becomes the first measurement, unless the athlete
    -- already has one for that day.
    if answers -> 'weight_kg' is not null and not exists (
      select 1 from public.body_measurements
      where user_id = auth.uid() and measured_on = proposal.effective_date
        and superseded_at is null
    ) then
      insert into public.body_measurements(user_id, measured_on, source, weight_kg, protocol_version)
      values (auth.uid(), proposal.effective_date, 'manual',
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
