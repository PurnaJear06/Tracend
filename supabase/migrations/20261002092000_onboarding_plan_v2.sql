-- Onboarding plan v2: a plan built from the athlete's answers, proposed by an
-- AI model or Tracend's rules, validated by deterministic code, and delivered
-- exactly as approved.
--
-- - change_proposals 2.0 carries the exact workouts and exercises (catalog
--   slugs). Only respond_to_onboarding_proposal_v2 builds them; v1 approval
--   now refuses 2.0 proposals, so installed older apps keep their own flow.
-- - onboarding_generations makes generation durable and idempotent: one
--   running generation per athlete, a lease, and worker writes that only land
--   while their generation is still current.
-- - Approval activates the goal, writes the profile and the onboarding weight,
--   and inserts the approved workouts instead of the generic seed.
-- - New profile fields are writable only by approval; the app keeps column
--   grants for the fields it already writes.
-- - Onboarding plan model calls count toward the owner AI budget.

-- Profile -------------------------------------------------------------------

alter table public.user_profiles
  add column sex text check (sex in ('male','female','unspecified')),
  add column birth_year smallint check (birth_year between 1900 and 2100),
  add column daily_activity text check (daily_activity in
    ('mostly_sitting','some_standing','mostly_standing','physical_labour')),
  add column equipment text[] not null default '{}' check (equipment <@ array[
    'dumbbells','barbell','bench','cables','machines','pull_up_bar','kettlebells','bands']::text[]),
  add column limitations_note text check (length(limitations_note) <= 500),
  add column nutrition_note text check (length(nutrition_note) <= 500);

-- The app writes only these columns (onboarding step 0); everything else is
-- written by approval.
revoke insert, update on public.user_profiles from authenticated;
grant insert (user_id, adult_attested_at, eligible, experience_level, training_days, session_minutes)
  on public.user_profiles to authenticated;
grant update (user_id, adult_attested_at, eligible, experience_level, training_days, session_minutes)
  on public.user_profiles to authenticated;

alter table public.change_responses
  add column revision_note text check (length(revision_note) between 1 and 500);

alter table public.training_plans drop constraint training_plans_source_check;
alter table public.training_plans add constraint training_plans_source_check
  check (source in ('mock_ai','user','imported','hybrid','ai','rules'));

-- Plans that arrive with their workouts are never given the generic seed.
create or replace function private.seed_active_plan_workouts_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status='active' and not exists(
    select 1 from public.training_plans
    where id=new.plan_id and user_id=new.user_id and source in ('imported','ai','rules')
  ) then
    perform private.seed_workouts_for_plan_version(new.id,new.user_id);
  end if;
  return new;
end $$;

-- Proposal 2.0 ------------------------------------------------------------

create function private.jsonb_int_between(value jsonb, low numeric, high numeric)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]+$'
    and value::text::numeric between low and high, false);
$$;

create function private.jsonb_number_between(value jsonb, low numeric, high numeric)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(value) = 'number' and value::text::numeric between low and high, false);
$$;

create function private.jsonb_text_between(value jsonb, low integer, high integer)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(value) = 'string' and length(value #>> '{}') between low and high, false);
$$;

-- Structure only (a check constraint cannot read the catalog); catalog slugs
-- are checked when the proposal is stored and again when it is approved.
-- Every limit matches the planned_workouts / planned_exercises columns, so an
-- approved proposal always inserts.
create function private.is_valid_initial_proposal_v2(training jsonb, nutrition jsonb)
returns boolean language sql immutable strict set search_path = '' as $$
  select
    jsonb_typeof(training) = 'object'
    and private.jsonb_text_between(training -> 'title', 1, 120)
    and private.jsonb_int_between(training -> 'block_weeks', 1, 24)
    and jsonb_typeof(training -> 'weekly_structure') = 'array'
    and jsonb_array_length(training -> 'weekly_structure') between 1 and 7
    and private.jsonb_int_between(training -> 'sessions_per_week',
      jsonb_array_length(training -> 'weekly_structure'),
      jsonb_array_length(training -> 'weekly_structure'))
    and jsonb_typeof(training -> 'prescription') = 'object'
    and coalesce(training ->> 'origin' in ('ai','rules'), false)
    and not exists (
      select 1 from jsonb_array_elements(training -> 'weekly_structure') workout
      where not (
        jsonb_typeof(workout) = 'object'
        and private.jsonb_int_between(workout -> 'workout_order', 1, 7)
        and private.jsonb_text_between(workout -> 'name', 1, 120)
        and private.jsonb_text_between(workout -> 'objective', 1, 500)
        and private.jsonb_int_between(workout -> 'preferred_weekday', 1, 7)
        and private.jsonb_int_between(workout -> 'estimated_minutes', 15, 180)
        and private.jsonb_text_between(workout -> 'warm_up_guidance', 1, 500)
        and private.jsonb_text_between(workout -> 'cool_down_guidance', 1, 500)
        and jsonb_typeof(workout -> 'exercises') = 'array'
        and jsonb_array_length(workout -> 'exercises') between 1 and 30
        and not exists (
          select 1 from jsonb_array_elements(workout -> 'exercises') exercise
          where not (
            jsonb_typeof(exercise) = 'object'
            and private.jsonb_int_between(exercise -> 'exercise_order', 1, 30)
            and private.jsonb_text_between(exercise -> 'slug', 1, 80)
            and private.jsonb_text_between(exercise -> 'name', 1, 120)
            and private.jsonb_int_between(exercise -> 'sets', 1, 12)
            and private.jsonb_int_between(exercise -> 'rep_min', 1, 100)
            and private.jsonb_int_between(exercise -> 'rep_max', 1, 100)
            and case when private.jsonb_int_between(exercise -> 'rep_min', 1, 100)
                and private.jsonb_int_between(exercise -> 'rep_max', 1, 100)
              then (exercise ->> 'rep_max')::numeric >= (exercise ->> 'rep_min')::numeric
              else false end
            and private.jsonb_number_between(exercise -> 'target_rpe', 1, 10)
            and private.jsonb_int_between(exercise -> 'rest_seconds', 15, 600)
            and (exercise -> 'notes' is null
              or private.jsonb_text_between(exercise -> 'notes', 0, 500))
          )
        )
      )
    )
    and (
      select count(distinct workout ->> 'workout_order') = count(*)
        and count(distinct workout ->> 'preferred_weekday') = count(*)
      from jsonb_array_elements(training -> 'weekly_structure') workout
    )
    and jsonb_typeof(nutrition) = 'object'
    and private.jsonb_int_between(nutrition -> 'calories', 1000, 6000)
    and private.jsonb_int_between(nutrition -> 'protein_g', 30, 400)
    and private.jsonb_int_between(nutrition -> 'carbohydrate_g', 20, 1000)
    and private.jsonb_int_between(nutrition -> 'fat_g', 20, 300);
$$;
revoke all on function private.is_valid_initial_proposal_v2(jsonb, jsonb)
from public, anon, authenticated;

alter table public.change_proposals drop constraint change_proposals_schema_version_check;
alter table public.change_proposals add constraint change_proposals_schema_version_check
  check (schema_version in ('1.0','2.0'));
alter table public.change_proposals drop constraint change_proposals_valid_payload;
alter table public.change_proposals add constraint change_proposals_valid_payload check (
  case schema_version
    when '1.0' then private.is_valid_initial_proposal(proposed_training, proposed_nutrition)
    else private.is_valid_initial_proposal_v2(proposed_training, proposed_nutrition)
  end
);

-- True when every exercise in a 2.0 proposal names an active catalog entry
-- with that entry's name.
create function private.proposal_uses_active_catalog(training jsonb)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1
    from jsonb_array_elements(training -> 'weekly_structure') workout,
      jsonb_array_elements(workout -> 'exercises') exercise
    left join public.exercise_catalog catalog
      on catalog.slug = exercise ->> 'slug' and catalog.status = 'active'
    where catalog.slug is null or catalog.name <> exercise ->> 'name'
  );
$$;
revoke all on function private.proposal_uses_active_catalog(jsonb) from public, anon, authenticated;

-- Generation jobs -----------------------------------------------------------

create table public.onboarding_generations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  snapshot_hash text not null check (length(snapshot_hash) between 16 and 128),
  status text not null check (status in ('running','succeeded','failed','superseded')),
  attempt integer not null check (attempt between 1 and 100000),
  lease_expires_at timestamptz not null,
  proposal_id uuid,
  error_code text check (error_code ~ '^[a-z][a-z0-9_]{0,63}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (proposal_id, user_id) references public.change_proposals(id, user_id),
  check ((status = 'succeeded') = (proposal_id is not null))
);
create unique index onboarding_generations_one_running
  on public.onboarding_generations(user_id) where status = 'running';
create index onboarding_generations_user_created
  on public.onboarding_generations(user_id, created_at desc);
alter table public.onboarding_generations enable row level security;
alter table public.onboarding_generations force row level security;
create policy onboarding_generations_select_own on public.onboarding_generations
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.onboarding_generations from public, anon, authenticated;
grant select on public.onboarding_generations to authenticated;

-- Starts a generation for these answers, or returns the one already running
-- or finished for them. Serialised per athlete by locking the account row.
create function public.claim_onboarding_generation(
  target_user_id uuid, target_snapshot_hash text, lease_seconds integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  running public.onboarding_generations%rowtype;
  finished public.onboarding_generations%rowtype;
  new_id uuid;
  attempt_number integer;
begin
  if lease_seconds not between 30 and 400 then
    raise exception 'invalid lease' using errcode = '22023';
  end if;
  perform 1 from public.user_accounts where id = target_user_id for update;
  if not found then raise exception 'account not found' using errcode = 'P0002'; end if;

  update public.onboarding_generations
    set status = 'failed', error_code = 'lease_expired', updated_at = now()
    where user_id = target_user_id and status = 'running' and lease_expires_at <= now();

  select * into running from public.onboarding_generations
    where user_id = target_user_id and status = 'running';
  if found then
    if running.snapshot_hash = target_snapshot_hash then
      return jsonb_build_object('generation_id', running.id, 'status', 'running', 'started', false);
    end if;
    update public.onboarding_generations
      set status = 'superseded', updated_at = now() where id = running.id;
  end if;

  select g.* into finished from public.onboarding_generations g
    join public.change_proposals p on p.id = g.proposal_id and p.user_id = g.user_id
    where g.user_id = target_user_id and g.status = 'succeeded'
      and g.snapshot_hash = target_snapshot_hash
      and p.status = 'pending' and p.expires_at > now()
    order by g.created_at desc limit 1;
  if found then
    return jsonb_build_object('generation_id', finished.id, 'status', 'succeeded',
      'proposal_id', finished.proposal_id, 'started', false);
  end if;

  -- The answers changed, or the last proposal was answered or expired: an
  -- older pending 2.0 proposal no longer matches what the athlete reviewed.
  update public.change_proposals set status = 'expired'
    where user_id = target_user_id and status = 'pending' and schema_version = '2.0';

  select count(*) + 1 into attempt_number
    from public.onboarding_generations where user_id = target_user_id;
  insert into public.onboarding_generations(user_id, snapshot_hash, status, attempt, lease_expires_at)
  values (target_user_id, target_snapshot_hash, 'running', attempt_number,
    now() + make_interval(secs => lease_seconds))
  returning id into new_id;
  return jsonb_build_object('generation_id', new_id, 'status', 'running', 'started', true);
end $$;
revoke all on function public.claim_onboarding_generation(uuid, text, integer)
from public, anon, authenticated;
grant execute on function public.claim_onboarding_generation(uuid, text, integer) to service_role;

-- Records why a generation failed; a no-op once it is no longer running.
create function public.fail_onboarding_generation(target_generation_id uuid, failure_code text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if failure_code !~ '^[a-z][a-z0-9_]{0,63}$' then
    raise exception 'invalid failure code' using errcode = '22023';
  end if;
  update public.onboarding_generations
    set status = 'failed', error_code = failure_code, updated_at = now()
    where id = target_generation_id and status = 'running';
  return found;
end $$;
revoke all on function public.fail_onboarding_generation(uuid, text) from public, anon, authenticated;
grant execute on function public.fail_onboarding_generation(uuid, text) to service_role;

-- The app's view of its newest generation. A running generation whose lease
-- ran out reads as failed, so the app never waits forever.
create function public.get_my_onboarding_generation()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'generation_id', g.id,
    'status', case when g.status = 'running' and g.lease_expires_at <= now() then 'failed'
      else g.status end,
    'error_code', case when g.status = 'running' and g.lease_expires_at <= now()
      then 'lease_expired' else g.error_code end,
    'proposal_id', g.proposal_id,
    'proposal_status', (select p.status from public.change_proposals p
      where p.id = g.proposal_id and p.user_id = g.user_id),
    'started_at', g.created_at)
  from public.onboarding_generations g
  where g.user_id = auth.uid()
  order by g.created_at desc
  limit 1;
$$;
revoke all on function public.get_my_onboarding_generation() from public, anon, authenticated;
grant execute on function public.get_my_onboarding_generation() to authenticated;

-- Stores a generation's proposal, only while that generation is current.
create function public.persist_onboarding_proposal_v2(
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
revoke all on function public.persist_onboarding_proposal_v2(
  uuid, uuid, text, jsonb, jsonb, jsonb, jsonb, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.persist_onboarding_proposal_v2(
  uuid, uuid, text, jsonb, jsonb, jsonb, jsonb, text, text, text, text
) to service_role;

-- Approves, rejects, or asks for a revision of a 2.0 proposal. Approval
-- activates exactly the proposed workouts, the nutrition targets, the goal,
-- the profile and the onboarding weight, in one transaction.
create function public.respond_to_onboarding_proposal_v2(
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
  if proposal.expires_at <= statement_timestamp() then
    update public.change_proposals set status = 'expired' where id = proposal.id;
    raise exception 'proposal is stale' using errcode = '55000';
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
revoke all on function public.respond_to_onboarding_proposal_v2(
  uuid, public.proposal_response_action, text
) from public, anon, authenticated;
grant execute on function public.respond_to_onboarding_proposal_v2(
  uuid, public.proposal_response_action, text
) to authenticated;

-- AI usage ------------------------------------------------------------------

alter table public.ai_usage_events drop constraint ai_usage_events_purpose_check;
alter table public.ai_usage_events add constraint ai_usage_events_purpose_check
  check (purpose in ('meal_vision','progress_vision','onboarding_plan'));
-- Meal photos keep their evaluated model list; an onboarding plan may use any
-- model the owner configures (it passes the onboarding eval first).
alter table public.ai_usage_events drop constraint ai_usage_events_model_check;
alter table public.ai_usage_events add constraint ai_usage_events_model_check check (
  (purpose <> 'onboarding_plan' and model in
    ('gemini-3.5-flash','qwen/qwen3.6-27b','qwen/qwen3.8-27b','deepseek-v4-flash'))
  or (purpose = 'onboarding_plan' and length(model) between 1 and 100)
);

create or replace function public.record_ai_usage_event(
  target_user_id uuid,run_purpose text,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric,run_latency_ms integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare event_id uuid;
begin
  if run_purpose = 'onboarding_plan' then
    if run_provider not in ('deepseek','groq','gemini') or length(run_model) not between 1 and 100
    then raise exception 'invalid usage event' using errcode='22023'; end if;
  elsif run_purpose not in ('meal_vision','progress_vision') or
    not ((run_provider='gemini' and run_model='gemini-3.5-flash') or
      (run_provider='groq' and run_model in ('qwen/qwen3.6-27b','qwen/qwen3.8-27b')))
  then raise exception 'invalid usage event' using errcode='22023'; end if;
  insert into public.ai_usage_events(user_id,purpose,provider,model,input_units,output_units,estimated_cost_usd,latency_ms)
  values(target_user_id,run_purpose,run_provider,run_model,run_input_units,run_output_units,run_estimated_cost_usd,run_latency_ms)
  returning id into event_id; return event_id;
end $$;

create or replace function public.assert_owner_ai_budget(target_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare monthly_cost numeric; today_requests integer;
begin
  select coalesce(sum(estimated_cost_usd),0), count(*) filter(where purpose in
    ('daily_coaching','coach_chat','meal_vision','onboarding_plan') and created_at>=date_trunc('day',now()))
  into monthly_cost,today_requests from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=target_user_id and created_at>=date_trunc('month',now())
    union all select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=target_user_id and created_at>=date_trunc('month',now())
  ) usage;
  if monthly_cost>=2 then raise exception 'monthly cost limit reached' using errcode='P0001'; end if;
  if today_requests>=30 then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
end $$;

create or replace function public.get_my_ai_budget_state()
returns jsonb language sql security definer set search_path='' stable as $$
with usage as (
  select coalesce(sum(estimated_cost_usd),0) monthly_cost,
    count(*) filter(where purpose in ('daily_coaching','coach_chat','meal_vision','onboarding_plan')
      and created_at>=date_trunc('day',now())) today_requests
  from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=auth.uid() and created_at>=date_trunc('month',now())
    union all
    select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=auth.uid() and created_at>=date_trunc('month',now())
  ) all_usage
)
select jsonb_build_object('period','current_month','estimated_cost_usd',monthly_cost,
  'warning_threshold_usd',1,'hard_stop_usd',2,'warning',monthly_cost>=1,
  'blocked',monthly_cost>=2,'today_requests',today_requests,'daily_limit',30)
from usage;
$$;

-- Older app builds ------------------------------------------------------------
-- v1 approval refuses 2.0 proposals, and the mock generator reuses only a
-- pending 1.0 proposal.

create or replace function public.respond_to_onboarding_proposal(
  proposal_id uuid,
  response_action public.proposal_response_action
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  proposal public.change_proposals%rowtype;
  plan_id uuid;
  plan_version_id uuid;
  nutrition_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into proposal
  from public.change_proposals
  where id = proposal_id and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'proposal not found' using errcode = 'P0002';
  end if;
  if proposal.status <> 'pending' then
    raise exception 'proposal is not pending' using errcode = '55000';
  end if;
  if proposal.expires_at <= statement_timestamp() then
    update public.change_proposals set status = 'expired' where id = proposal.id;
    raise exception 'proposal is stale' using errcode = '55000';
  end if;
  -- A 2.0 proposal carries the exact workouts; only respond_to_onboarding_proposal_v2
  -- builds them, so an installed older app cannot approve one into the generic seed.
  if proposal.schema_version <> '1.0' then
    raise exception 'proposal requires a newer app' using errcode = '55000';
  end if;
  if not private.is_valid_initial_proposal(proposal.proposed_training, proposal.proposed_nutrition) then
    raise exception 'proposal payload is invalid' using errcode = '22023';
  end if;

  if response_action = 'accept' then
    update public.training_plan_versions
      set status = 'superseded'
      where user_id = auth.uid() and status = 'active';
    update public.nutrition_target_sets
      set status = 'superseded'
      where user_id = auth.uid() and status = 'active';

    insert into public.training_plans (user_id, title, source)
    values (auth.uid(), proposal.proposed_training ->> 'title', 'mock_ai')
    returning id into plan_id;

    insert into public.training_plan_versions (
      user_id, plan_id, version_number, status, block_weeks,
      sessions_per_week, prescription, rationale, source_proposal_id,
      approved_at, effective_date
    ) values (
      auth.uid(), plan_id, 1, 'active',
      (proposal.proposed_training ->> 'block_weeks')::smallint,
      (proposal.proposed_training ->> 'sessions_per_week')::smallint,
      proposal.proposed_training -> 'prescription', proposal.rationale,
      proposal.id, statement_timestamp(), proposal.effective_date
    ) returning id into plan_version_id;

    insert into public.nutrition_target_sets (
      user_id, version_number, status, calories, protein_g, carbohydrate_g,
      fat_g, rationale, source_proposal_id, approved_at, effective_date
    ) values (
      auth.uid(),
      coalesce((select max(version_number) + 1 from public.nutrition_target_sets where user_id = auth.uid()), 1),
      'active',
      (proposal.proposed_nutrition ->> 'calories')::integer,
      (proposal.proposed_nutrition ->> 'protein_g')::integer,
      (proposal.proposed_nutrition ->> 'carbohydrate_g')::integer,
      (proposal.proposed_nutrition ->> 'fat_g')::integer,
      proposal.rationale, proposal.id, statement_timestamp(), proposal.effective_date
    ) returning id into nutrition_id;

    update public.change_proposals set status = 'accepted' where id = proposal.id;
    update public.user_accounts set onboarding_state = 'completed' where id = auth.uid();
  elsif response_action = 'reject' then
    update public.change_proposals set status = 'rejected' where id = proposal.id;
  else
    update public.change_proposals set status = 'revision_requested' where id = proposal.id;
  end if;

  insert into public.change_responses (user_id, proposal_id, action)
  values (auth.uid(), proposal.id, response_action);

  insert into public.audit_events (
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    auth.uid(), 'onboarding_proposal_' || response_action::text,
    'change_proposal', proposal.id, 'succeeded',
    jsonb_build_object('schema_version', proposal.schema_version)
  );

  return jsonb_build_object(
    'proposal_id', proposal.id,
    'status', case response_action
      when 'accept' then 'accepted'
      when 'reject' then 'rejected'
      else 'revision_requested'
    end,
    'training_plan_version_id', plan_version_id,
    'nutrition_target_set_id', nutrition_id
  );
end;
$$;

create or replace function public.persist_mock_onboarding_proposal(
  target_user_id uuid,
  snapshot_hash text,
  snapshot_features jsonb,
  training_payload jsonb,
  nutrition_payload jsonb,
  evidence_payload jsonb,
  proposal_rationale text,
  proposal_benefit text,
  proposal_downside text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  snapshot_id uuid;
  proposal_id uuid;
begin
  if not exists (
    select 1 from public.user_profiles
    where user_id = target_user_id and eligible is true and adult_attested_at is not null
  ) then
    raise exception 'eligible adult profile required' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.onboarding_drafts
    where user_id = target_user_id and path is not null
  ) then
    raise exception 'onboarding draft required' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.consent_records c
    where c.user_id = target_user_id
      and c.consent_type = 'terms'
      and c.action = 'granted'
      and c.created_at = (
        select max(latest.created_at)
        from public.consent_records latest
        where latest.user_id = target_user_id and latest.consent_type = 'terms'
      )
  ) or not exists (
    select 1
    from public.consent_records c
    where c.user_id = target_user_id
      and c.consent_type = 'privacy'
      and c.action = 'granted'
      and c.created_at = (
        select max(latest.created_at)
        from public.consent_records latest
        where latest.user_id = target_user_id and latest.consent_type = 'privacy'
      )
  ) then
    raise exception 'current terms and privacy consent required' using errcode = '22023';
  end if;

  if not private.is_valid_initial_proposal(training_payload, nutrition_payload) then
    raise exception 'mock provider payload is invalid' using errcode = '22023';
  end if;

  select id into proposal_id
  from public.change_proposals
  where user_id = target_user_id
    and status = 'pending'
    and schema_version = '1.0'
    and expires_at > statement_timestamp()
  order by created_at desc
  limit 1;

  if proposal_id is not null then
    return proposal_id;
  end if;

  insert into public.feature_snapshots (
    user_id, trigger_kind, schema_version, feature_engine_version,
    features, coverage, missing_data, data_hash
  ) values (
    target_user_id, 'onboarding', '1.0', 'onboarding-v1',
    snapshot_features, jsonb_build_object('onboarding', 'complete'), '{}',
    snapshot_hash
  )
  on conflict (user_id, data_hash) do nothing
  returning id into snapshot_id;

  if snapshot_id is null then
    select id into snapshot_id
    from public.feature_snapshots
    where user_id = target_user_id and data_hash = snapshot_hash;
  end if;

  insert into public.change_proposals (
    user_id, feature_snapshot_id, schema_version, proposed_training,
    proposed_nutrition, evidence, rationale, expected_benefit, downside,
    confidence, effective_date, expires_at
  ) values (
    target_user_id, snapshot_id, '1.0', training_payload,
    nutrition_payload, evidence_payload, proposal_rationale, proposal_benefit,
    proposal_downside, 'medium', current_date, statement_timestamp() + interval '7 days'
  ) returning id into proposal_id;

  return proposal_id;
end;
$$;
