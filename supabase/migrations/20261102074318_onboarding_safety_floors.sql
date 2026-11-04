-- Pre-beta audit (origin/main 4421da9): onboarding safety floors and direct-write grants.
-- Forward-only. Every redefined function is its latest earlier definition plus the hunks named
-- here (create or replace, same signature and owner, so its grants stay); pinned by
-- _shared/onboarding/safety_floors_migration_test.ts and safety_floors_test.sql.
--
-- 1. B5a, healthy-weight floors at onboarding approval. private.onboarding_floor_violation checks
--    the answers a plan was built from against the floors Coach and set_goal_target_v1 already
--    apply: no target weight under BMI 18.5 for the height, and, at a BMI (to one decimal) under
--    19.5, no calorie target under the lower maintenance estimate (the onboarding policy's
--    Mifflin-St Jeor, activity factor and training energy; _shared/onboarding/policy.ts, with
--    5 kcal for its rounding to 10). respond_to_onboarding_proposal_v2 runs it before anything is
--    written; a plan that breaks a floor is recorded as expired, not approved, and the app (every
--    build) answers an expired proposal by building a fresh one, which the onboarding policy then
--    holds at maintenance with no target under the floor.
-- 2. B5b, the signed-in role can no longer write past the floors.
--    - public.user_goals: column grants for exactly what the app writes (insert user_id,
--      goal_type, priority, status; update goal_type), and policies that keep those rows drafts.
--      Details, targets, phases and activation stay inside the security definer functions, which
--      check the floors and write the audit event.
--    - public.user_accounts.onboarding_state: insert and update revoked. Approval sets completed
--      inside respond_to_onboarding_proposal_v2 and the first draft moves not_started to
--      in_progress (20261031100000); the installed build no longer writes the column.
--    - A missing screening is unscreened, never cleared. private.current_screening_outcome returns
--      'unscreened' when the athlete has no screening row; it ranks with moderate_until_cleared,
--      so it carries the moderate effort cap (hold_plan_to_screening, the cardio week's
--      `= 'cleared'` test, Coach and its proposals) and assert_screening_allows refuses a plan that
--      was not itself built as unscreened, so no onboarding plan is stored or approved until the
--      health check is answered. get_my_screening_v1 keeps its answer for a never-screened athlete
--      (screened false), which installed builds read.
-- 3. Security finding 5: get_healthkit_completion_candidate(date) is no longer executable by
--    public or anon (it filters on auth.uid(), so this only removes reach). safety_floors_test.sql
--    fails when any public function is executable by anon, or a public security definer function
--    taking a user uuid is executable by authenticated.

-- 1. Healthy-weight floors at approval -------------------------------------------------------

-- The floor an onboarding proposal breaks, or null. `answers` is the snapshot's answers and
-- `nutrition` the proposal's nutrition. Missing body or schedule answers fail closed.
create function private.onboarding_floor_violation(answers jsonb, nutrition jsonb)
returns text language plpgsql stable set search_path = '' as $$
declare
  height_m numeric := (answers ->> 'height_cm')::numeric / 100;
  weight_kg numeric := (answers ->> 'weight_kg')::numeric;
  target_kg numeric := (answers ->> 'target_weight_kg')::numeric;
  calories numeric := (nutrition ->> 'calories')::numeric;
  age integer := extract(year from statement_timestamp() at time zone 'UTC')::integer
    - (answers ->> 'birth_year')::integer;
  maintenance numeric;
begin
  if height_m is null or weight_kg is null or calories is null then
    return 'answers_incomplete';
  end if;
  if target_kg is not null and target_kg < round(18.5 * height_m * height_m, 1) then
    return 'target_below_healthy_floor';
  end if;
  if round(weight_kg / (height_m * height_m), 1) >= 19.5 then
    return null;
  end if;
  -- The lower estimate: the female equation when sex is not given, as the policy's bmrLow.
  maintenance := (10 * weight_kg + 6.25 * height_m * 100 - 5 * age
      + case when answers ->> 'sex' = 'male' then 5 else -161 end)
    * case answers ->> 'daily_activity'
        when 'mostly_sitting' then 1.2
        when 'some_standing' then 1.375
        when 'mostly_standing' then 1.55
        when 'physical_labour' then 1.725
      end
    + 4 * 3.5 * weight_kg / 200 * (answers ->> 'session_minutes')::numeric
      * jsonb_array_length(answers -> 'training_weekdays') / 7;
  if maintenance is null then
    return 'answers_incomplete';
  end if;
  if calories + 5 < least(maintenance, 6000) then
    return 'deficit_near_healthy_floor';
  end if;
  return null;
end $$;
revoke all on function private.onboarding_floor_violation(jsonb, jsonb)
  from public, anon, authenticated;

-- Body as in 20261017050226_onboarding_screening.sql plus the floor check.
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
  floor_rule text;
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
    -- The healthy-weight floors, checked again on the answers the plan was built from. A plan
    -- that breaks one (built before the floors existed, or by any other path) is recorded as
    -- expired and reported, not raised, so the app builds a fresh plan under the floors.
    floor_rule := private.onboarding_floor_violation(answers, proposal.proposed_nutrition);
    if floor_rule is not null then
      update public.change_proposals set status = 'expired' where id = proposal.id;
      insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
      values (auth.uid(), 'onboarding_proposal_expired', 'change_proposal', proposal.id, 'succeeded',
        jsonb_build_object('schema_version', proposal.schema_version, 'reason', floor_rule));
      return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
        'status', 'expired', 'training_plan_version_id', null, 'nutrition_target_set_id', null);
    end if;
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


-- 2. Direct writes --------------------------------------------------------------------------

-- user_goals: the app inserts a draft goal and changes its type before approval; nothing else.
revoke insert, update on public.user_goals from authenticated;
grant insert (user_id, goal_type, priority, status) on public.user_goals to authenticated;
grant update (goal_type) on public.user_goals to authenticated;
drop policy user_goals_own on public.user_goals;
create policy user_goals_select_own on public.user_goals
for select to authenticated using (user_id = (select auth.uid()));
create policy user_goals_insert_own_draft on public.user_goals
for insert to authenticated
with check (user_id = (select auth.uid()) and status = 'draft');
create policy user_goals_update_own_draft on public.user_goals
for update to authenticated
using (user_id = (select auth.uid()) and status = 'draft')
with check (user_id = (select auth.uid()) and status = 'draft');

-- user_accounts.onboarding_state: only the definer functions and the first-draft trigger move it.
revoke insert (onboarding_state), update (onboarding_state) on public.user_accounts
  from authenticated;

-- A missing screening is unscreened. 0 cleared, 1 moderate_until_cleared or unscreened,
-- 2 see_professional; a missing value (a plan snapshot without one) is cleared.
create or replace function private.screening_rank(outcome text)
returns integer language sql immutable set search_path = '' as $$
  select case outcome when 'see_professional' then 2 when 'moderate_until_cleared' then 1
    when 'unscreened' then 1 else 0 end
$$;

-- The athlete's current outcome: the newest row, or unscreened when never screened.
create or replace function private.current_screening_outcome(target_user_id uuid)
returns text language sql stable set search_path = '' as $$
  select coalesce((
    select s.outcome from public.onboarding_screenings s
    where s.user_id = target_user_id order by s.screened_at desc, s.id desc limit 1
  ), 'unscreened')
$$;

-- Body as in 20261017050226_onboarding_screening.sql plus the unscreened refusal: a plan built
-- while the athlete was unscreened (a Coach proposal, which holds effort to moderate) may still be
-- approved; any other plan waits for the health check.
create or replace function private.assert_screening_allows(target_user_id uuid, built_under text)
returns void language plpgsql stable set search_path = '' as $$
declare
  current_outcome text := private.current_screening_outcome(target_user_id);
begin
  if current_outcome = 'see_professional' then
    raise exception 'a health professional must clear this athlete first' using errcode = '55000';
  end if;
  if current_outcome = 'unscreened' and built_under is distinct from 'unscreened' then
    raise exception 'the health check must be answered first' using errcode = '55000';
  end if;
  if private.screening_rank(current_outcome) > private.screening_rank(built_under) then
    raise exception 'the plan was built before the health check changed' using errcode = '55000';
  end if;
end $$;

-- Body as in 20261018120018_coach_proposals.sql; unscreened holds effort as moderate does.
create or replace function private.hold_plan_to_screening(p_user uuid, p_version uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if private.current_screening_outcome(p_user) in ('moderate_until_cleared', 'unscreened') then
    update public.planned_exercises e set target_rpe = least(e.target_rpe, 7)
    from public.planned_workouts w
    where w.plan_version_id = p_version and e.planned_workout_id = w.id
      and e.user_id = p_user and e.target_rpe is not null;
  end if;
end $$;

-- 3. Function reach ---------------------------------------------------------------------------

revoke all on function public.get_healthkit_completion_candidate(date) from public, anon;
grant execute on function public.get_healthkit_completion_candidate(date) to authenticated;
