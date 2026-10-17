-- Pre-exercise screening gate (coaching platform Contract 8, chunk B6).
--
-- 1. public.onboarding_screenings keeps what the athlete answered before the first plan, the
--    outcome and the date. Rows are only added, so every answer the athlete gave stays on record;
--    the newest row is the current one. An athlete who was never screened (an account made before
--    this migration, or an app build that does not ask) has no row, and no row reads as "cleared".
-- 2. record_screening_v1 stores one screening for the caller. The database works out the outcome
--    from the four answers (the same rule as _shared/training/screening/screening.ts), and a check
--    constraint keeps a stored outcome from ever disagreeing with its answers.
-- 3. get_my_screening_v1 returns the caller's current screening, so the app can honour a stop
--    when it reopens.
-- 4. A stricter outcome ends what was built under a weaker one: record_screening_v1 supersedes a
--    running generation and expires pending proposals built as a less strict outcome, and
--    persist_onboarding_proposal_v3 and respond_to_onboarding_proposal_v2 (create or replace, same
--    signatures, bodies as in 20261002110000 plus one guard) refuse to store or approve a plan
--    that the current outcome does not allow. The refusal is SQLSTATE 55000, which the app already
--    reads as "this proposal can no longer be answered" and answers with a rebuild.
-- Server code (service role) reads the newest row of a user directly.
-- The outcome only caps the plan's intensity or stops plan building; it never diagnoses anything.
-- Everything is additive.

-- 1. Table ------------------------------------------------------------------------------------

-- Own words, following the ACSM 2015 preparticipation logic: any current sign or symptom, or no
-- regular exercise with a known heart, metabolic or kidney condition and no clearance, means see
-- a professional first; regular exercise with a known condition and no clearance means moderate
-- effort until cleared; everything else is cleared.
create function private.screening_outcome(
  exercises_regularly boolean, known_disease boolean, symptoms boolean, cleared_by_professional boolean)
returns text language sql immutable set search_path = '' as $$
  select case
    when symptoms then 'see_professional'
    when known_disease and not cleared_by_professional and not exercises_regularly
      then 'see_professional'
    when known_disease and not cleared_by_professional then 'moderate_until_cleared'
    else 'cleared'
  end
$$;
revoke all on function private.screening_outcome(boolean, boolean, boolean, boolean)
  from public, anon, authenticated;

-- 0 cleared, 1 moderate_until_cleared, 2 see_professional; a missing value is cleared.
create function private.screening_rank(outcome text)
returns integer language sql immutable set search_path = '' as $$
  select case outcome when 'see_professional' then 2 when 'moderate_until_cleared' then 1 else 0 end
$$;
revoke all on function private.screening_rank(text) from public, anon, authenticated;

create table public.onboarding_screenings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  exercises_regularly boolean not null,
  known_disease boolean not null,
  symptoms boolean not null,
  cleared_by_professional boolean not null default false,
  outcome text not null,
  screened_at timestamptz not null default clock_timestamp(),
  constraint onboarding_screenings_outcome_check check (
    outcome in ('cleared', 'moderate_until_cleared', 'see_professional')),
  constraint onboarding_screenings_outcome_matches_answers check (
    outcome = private.screening_outcome(
      exercises_regularly, known_disease, symptoms, cleared_by_professional))
);

create index onboarding_screenings_user_newest
  on public.onboarding_screenings (user_id, screened_at desc);

comment on table public.onboarding_screenings is
  'Pre-plan screening answers, the outcome (cleared, moderate_until_cleared, see_professional) and the date. Append-only; the newest row per user is current; no row reads as cleared.';
comment on column public.onboarding_screenings.cleared_by_professional is
  'True when a professional has cleared the athlete to exercise. False when not asked (no known condition, or a current symptom).';

alter table public.onboarding_screenings enable row level security;
alter table public.onboarding_screenings force row level security;
create policy onboarding_screenings_own_read on public.onboarding_screenings
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.onboarding_screenings from anon, authenticated;
grant select on public.onboarding_screenings to authenticated;

-- 2. Record -----------------------------------------------------------------------------------

-- The athlete's current outcome: the newest row, or cleared when never screened.
create function private.current_screening_outcome(target_user_id uuid)
returns text language sql stable set search_path = '' as $$
  select coalesce((
    select s.outcome from public.onboarding_screenings s
    where s.user_id = target_user_id order by s.screened_at desc, s.id desc limit 1
  ), 'cleared')
$$;
revoke all on function private.current_screening_outcome(uuid) from public, anon, authenticated;

-- Refuses (55000) a plan the current outcome does not allow: nothing at all under
-- see_professional, and nothing built as a less strict outcome under moderate_until_cleared.
-- built_under is the outcome recorded in the plan's snapshot; none means cleared.
create function private.assert_screening_allows(target_user_id uuid, built_under text)
returns void language plpgsql stable set search_path = '' as $$
declare
  current_outcome text := private.current_screening_outcome(target_user_id);
begin
  if current_outcome = 'see_professional' then
    raise exception 'a health professional must clear this athlete first' using errcode = '55000';
  end if;
  if private.screening_rank(current_outcome) > private.screening_rank(built_under) then
    raise exception 'the plan was built before the health check changed' using errcode = '55000';
  end if;
end $$;
revoke all on function private.assert_screening_allows(uuid, text) from public, anon, authenticated;

create function public.record_screening_v1(
  exercises_regularly boolean,
  known_disease boolean,
  symptoms boolean,
  cleared_by_professional boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  newest public.onboarding_screenings%rowtype;
  previous_rank integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if exercises_regularly is null or known_disease is null or symptoms is null
    or cleared_by_professional is null then
    raise exception 'every screening answer is required' using errcode = '22023';
  end if;

  select * into newest from public.onboarding_screenings s
  where s.user_id = auth.uid() order by s.screened_at desc, s.id desc limit 1;

  -- Answering the same again adds no row, so passing the step twice keeps one record.
  if not found
    or newest.exercises_regularly is distinct from record_screening_v1.exercises_regularly
    or newest.known_disease is distinct from record_screening_v1.known_disease
    or newest.symptoms is distinct from record_screening_v1.symptoms
    or newest.cleared_by_professional is distinct from record_screening_v1.cleared_by_professional
  then
    previous_rank := private.screening_rank(private.current_screening_outcome(auth.uid()));
    insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
      cleared_by_professional, outcome)
    values (auth.uid(), record_screening_v1.exercises_regularly, record_screening_v1.known_disease,
      record_screening_v1.symptoms, record_screening_v1.cleared_by_professional,
      private.screening_outcome(record_screening_v1.exercises_regularly,
        record_screening_v1.known_disease, record_screening_v1.symptoms,
        record_screening_v1.cleared_by_professional))
    returning * into newest;
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (auth.uid(), 'onboarding_screening_recorded', 'onboarding_screening', newest.id,
      'succeeded', jsonb_build_object('screening_outcome', newest.outcome));

    -- A stricter outcome ends what was built under a weaker one: pending proposals made as a less
    -- strict outcome can no longer be approved, and a generation still running is replaced.
    update public.change_proposals p set status = 'expired'
    where p.user_id = auth.uid() and p.status = 'pending' and p.schema_version = '2.0'
      and private.screening_rank((
        select f.features ->> 'screening' from public.feature_snapshots f
        where f.id = p.feature_snapshot_id and f.user_id = p.user_id))
        < private.screening_rank(newest.outcome);
    if private.screening_rank(newest.outcome) > previous_rank then
      update public.onboarding_generations set status = 'superseded', updated_at = now()
      where user_id = auth.uid() and status = 'running';
    end if;
  end if;

  return jsonb_build_object('schema_version', '1.0', 'outcome', newest.outcome,
    'screened_at', newest.screened_at);
end $$;
revoke all on function public.record_screening_v1(boolean, boolean, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.record_screening_v1(boolean, boolean, boolean, boolean)
  to authenticated;

-- 3. Read -------------------------------------------------------------------------------------

-- The caller's current screening. An athlete never screened gets outcome "cleared" with screened
-- false, so a caller never treats a missing row as a special case.
create function public.get_my_screening_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  newest public.onboarding_screenings%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into newest from public.onboarding_screenings s
  where s.user_id = auth.uid() order by s.screened_at desc, s.id desc limit 1;
  if not found then
    return jsonb_build_object('schema_version', '1.0', 'screened', false, 'outcome', 'cleared',
      'exercises_regularly', null, 'known_disease', null, 'symptoms', null,
      'cleared_by_professional', null, 'screened_at', null);
  end if;
  return jsonb_build_object('schema_version', '1.0', 'screened', true, 'outcome', newest.outcome,
    'exercises_regularly', newest.exercises_regularly, 'known_disease', newest.known_disease,
    'symptoms', newest.symptoms, 'cleared_by_professional', newest.cleared_by_professional,
    'screened_at', newest.screened_at);
end $$;
revoke all on function public.get_my_screening_v1() from public, anon, authenticated;
grant execute on function public.get_my_screening_v1() to authenticated;

-- 4. Plans must fit the current outcome ------------------------------------------------------

-- Bodies as in 20261002110000_coach_intake.sql with one added guard each.
create or replace function public.persist_onboarding_proposal_v3(
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
  proposal_confidence text,
  generation_metadata jsonb
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
  -- The health check may have changed while the plan was being built.
  perform private.assert_screening_allows(target_user_id, snapshot_features ->> 'screening');

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
    or not private.is_valid_generation_metadata(generation_metadata)
    or coalesce(snapshot_features ->> 'policy_version', 'onboarding-policy-v1')
      not in ('onboarding-policy-v1', 'onboarding-policy-v2')
  then
    raise exception 'onboarding proposal is invalid' using errcode = '22023';
  end if;

  insert into public.feature_snapshots(
    user_id, trigger_kind, schema_version, feature_engine_version,
    features, coverage, missing_data, data_hash
  ) values (
    target_user_id, 'onboarding', '2.0',
    coalesce(snapshot_features ->> 'policy_version', 'onboarding-policy-v1'),
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
      'policy_version', training_payload ->> 'policy_version')
      || coalesce(generation_metadata, '{}'::jsonb)));
  return new_proposal_id;
end $$;

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
    -- A plan built before the health check got stricter cannot be approved.
    perform private.assert_screening_allows(auth.uid(), (
      select s.features ->> 'screening' from public.feature_snapshots s
      where s.id = proposal.feature_snapshot_id and s.user_id = auth.uid()));
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
          rep_min, rep_max, target_rpe, rest_seconds, notes, exercise_slug, target_load_kg
        ) values (
          auth.uid(), new_workout_id, (exercise ->> 'exercise_order')::smallint,
          exercise ->> 'name', (exercise ->> 'sets')::smallint,
          (exercise ->> 'rep_min')::smallint, (exercise ->> 'rep_max')::smallint,
          (exercise ->> 'target_rpe')::numeric, (exercise ->> 'rest_seconds')::smallint,
          coalesce(exercise ->> 'notes', ''), exercise ->> 'slug',
          (exercise ->> 'start_load_kg')::numeric
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
      avoid_patterns, equipment_note, training_years, priority_muscles, strong_muscles
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
      nullif(answers ->> 'equipment_note', ''),
      answers ->> 'training_years',
      array(select value from jsonb_array_elements_text(
        coalesce(answers -> 'priority_muscles', '[]'::jsonb)) value),
      array(select value from jsonb_array_elements_text(
        coalesce(answers -> 'strong_muscles', '[]'::jsonb)) value)
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
      equipment_note = excluded.equipment_note,
      training_years = excluded.training_years,
      priority_muscles = excluded.priority_muscles,
      strong_muscles = excluded.strong_muscles;

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
