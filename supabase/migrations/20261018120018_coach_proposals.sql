-- A8 part 1: Coach proposals (coaching platform, chunk A8, migration code 18).
--
-- Coach may ask, in chat, for a change to the plan, the nutrition targets or the goal. Deterministic
-- rules (_shared/coach_proposals) compute every number and refuse what the policy forbids; this
-- migration stores the result, lets the athlete approve it with one tap, writes the new version with
-- an audit event, and lets the athlete undo it for seven days (Architecture 2 and 3).
--
-- 1. change_proposals 3.0: a proposal kind, the payload approval applies, before and after
--    snapshots for the card, the versions it was based on, the chat message it came from, and what
--    approval created (so undo can restore it). Old 1.0 and 2.0 rows and their checks are unchanged.
-- 2. training_plan_versions gains ends_on, block_kind and restores_version_id: a temporary block is
--    an ordinary active version that carries the day it ends and the version to restore. user_goals
--    gains source_proposal_id.
-- 3. persist_coach_proposal_v1   service role only; stores one pending proposal (coach-chat calls it).
-- 4. get_my_coach_proposals_v1   the athlete's proposals for the card and the undo prompt.
-- 5. respond_to_coach_proposal_v1  approve, decline or "change it"; approve writes the new version.
-- 6. undo_coach_proposal_v1      restores the previous version as a new version within seven days.
-- 7. Temporary blocks end by themselves: an hourly job restores the plan after the block's last
--    day, and every read and answer above also ends a due block first, so the athlete never waits
--    for the job.
--
-- Everything is additive. The frozen prepare_coach_chat_v8 still reads change_proposals; 3.0 rows
-- fill proposed_training and proposed_nutrition with a short summary so its "plan_proposals" list
-- shows Coach the proposal and how the athlete answered.

-- 1. change_proposals 3.0 --------------------------------------------------------------------

alter table public.change_proposals
  add column proposal_kind text,
  add column proposal_payload jsonb,
  add column before_snapshot jsonb,
  add column after_snapshot jsonb,
  add column basis jsonb,
  add column source_message_id uuid references public.coach_messages(id) on delete set null,
  add column ends_on date,
  add column applied_at timestamptz,
  add column undo_until timestamptz,
  add column undone_at timestamptz,
  add column applied_changes jsonb;

alter table public.change_proposals alter column feature_snapshot_id drop not null;

alter table public.change_proposals add constraint change_proposals_snapshot_required
  check (schema_version = '3.0' or feature_snapshot_id is not null);

-- Structure of the training part of a payload. Catalog slugs are checked when the proposal is
-- stored; an exercise from an older plan may have no slug.
create function private.is_valid_coach_training(training jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(training) = 'object'
    and training ->> 'mode' in ('new_version', 'block', 'end_block')
    and case training ->> 'mode'
      when 'end_block' then true
      else
        private.jsonb_text_between(training -> 'title', 1, 120)
        and private.jsonb_int_between(training -> 'block_weeks', 1, 24)
        and jsonb_typeof(training -> 'weekly_structure') = 'array'
        and jsonb_array_length(training -> 'weekly_structure') between 1 and 7
        and (training ->> 'mode' <> 'block' or (
          coalesce(training ->> 'ends_on' ~ '^\d{4}-\d{2}-\d{2}$', false)
          and training ->> 'block_kind' in ('temporary_block', 'intensity', 'focus', 'next_session')))
        and (training -> 'profile' is null or (
          jsonb_typeof(training -> 'profile') = 'object'
          and jsonb_typeof(training -> 'profile' -> 'training_days') = 'array'
          and jsonb_array_length(training -> 'profile' -> 'training_days') between 1 and 7
          and private.jsonb_int_between(training -> 'profile' -> 'session_minutes', 15, 180)))
        and not exists (
          select 1 from jsonb_array_elements(training -> 'weekly_structure') workout
          where not (
            jsonb_typeof(workout) = 'object'
            and private.jsonb_int_between(workout -> 'workout_order', 1, 7)
            and private.jsonb_text_between(workout -> 'name', 1, 120)
            and private.jsonb_text_between(workout -> 'objective', 1, 500)
            and (coalesce(jsonb_typeof(workout -> 'preferred_weekday'), 'null') = 'null'
              or private.jsonb_int_between(workout -> 'preferred_weekday', 1, 7))
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
                and (coalesce(jsonb_typeof(exercise -> 'slug'), 'null') = 'null'
                  or private.jsonb_text_between(exercise -> 'slug', 1, 80))
                and private.jsonb_text_between(exercise -> 'name', 1, 120)
                and private.jsonb_int_between(exercise -> 'sets', 1, 12)
                and private.jsonb_int_between(exercise -> 'rep_min', 1, 100)
                and private.jsonb_int_between(exercise -> 'rep_max', 1, 100)
                and case when private.jsonb_int_between(exercise -> 'rep_min', 1, 100)
                    and private.jsonb_int_between(exercise -> 'rep_max', 1, 100)
                  then (exercise ->> 'rep_max')::numeric >= (exercise ->> 'rep_min')::numeric
                  else false end
                and (coalesce(jsonb_typeof(exercise -> 'target_rpe'), 'null') = 'null'
                  or private.jsonb_number_between(exercise -> 'target_rpe', 1, 10))
                and private.jsonb_int_between(exercise -> 'rest_seconds', 15, 600)
                and private.jsonb_text_between(exercise -> 'notes', 0, 500)
                and (exercise -> 'start_load_kg' is null
                  or private.jsonb_number_between(exercise -> 'start_load_kg', 0, 2000))
              )
            )
          )
        )
        and (select count(distinct w ->> 'workout_order') = count(*)
          from jsonb_array_elements(training -> 'weekly_structure') w)
    end, false);
$$;
revoke all on function private.is_valid_coach_training(jsonb) from public, anon, authenticated;

-- The nutrition part: the same bounds as the table, macros that add up to the calories.
create function private.is_valid_coach_nutrition(nutrition jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(nutrition) = 'object'
    and private.jsonb_int_between(nutrition -> 'calories', 1000, 6000)
    and private.jsonb_int_between(nutrition -> 'protein_g', 30, 400)
    and private.jsonb_int_between(nutrition -> 'carbohydrate_g', 20, 1000)
    and private.jsonb_int_between(nutrition -> 'fat_g', 20, 300)
    and private.jsonb_text_between(nutrition -> 'rationale', 1, 2000)
    and abs(4 * (nutrition ->> 'protein_g')::numeric + 4 * (nutrition ->> 'carbohydrate_g')::numeric
      + 9 * (nutrition ->> 'fat_g')::numeric - (nutrition ->> 'calories')::numeric)
      <= 0.05 * (nutrition ->> 'calories')::numeric;
$$;
revoke all on function private.is_valid_coach_nutrition(jsonb) from public, anon, authenticated;

-- True when every exercise that names a catalog slug names an active catalog entry.
create function private.coach_training_uses_catalog(training jsonb)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1
    from jsonb_array_elements(coalesce(training -> 'weekly_structure', '[]'::jsonb)) workout,
      jsonb_array_elements(workout -> 'exercises') exercise
    left join public.exercise_catalog catalog
      on catalog.slug = exercise ->> 'slug' and catalog.status = 'active'
    where coalesce(jsonb_typeof(exercise -> 'slug'), 'null') = 'string' and catalog.slug is null
  );
$$;
revoke all on function private.coach_training_uses_catalog(jsonb) from public, anon, authenticated;

create function private.is_valid_coach_goal(goal jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(goal) = 'object'
    and goal ->> 'goal_type' in ('fat_loss', 'muscle_gain', 'recomposition', 'strength', 'aesthetic')
    and goal ->> 'phase' in ('cut', 'maintenance', 'diet_break', 'gain')
    and coalesce(goal ->> 'phase_started_on' ~ '^\d{4}-\d{2}-\d{2}$', false)
    and (coalesce(jsonb_typeof(goal -> 'phase_ends_on'), 'null') = 'null'
      or coalesce(goal ->> 'phase_ends_on' ~ '^\d{4}-\d{2}-\d{2}$', false))
    and (goal -> 'target' is null or (
      jsonb_typeof(goal -> 'target') = 'object'
      and private.jsonb_number_between(goal -> 'target' -> 'weight_kg', 30, 300)
      and (goal -> 'target' -> 'date' is null
        or coalesce(goal -> 'target' ->> 'date' ~ '^\d{4}-\d{2}-\d{2}$', false))));
$$;
revoke all on function private.is_valid_coach_goal(jsonb) from public, anon, authenticated;

create function private.is_valid_coach_proposal_row(
  kind text, training jsonb, nutrition jsonb, payload jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select kind in ('temporary_block', 'training_schedule', 'exercise_swap', 'intensity_or_phase',
      'goal_or_phase', 'nutrition_targets', 'next_session_adjustment')
    and jsonb_typeof(training) = 'object'
    and jsonb_typeof(nutrition) = 'object'
    and jsonb_typeof(payload) = 'object'
    and (payload ? 'training' or payload ? 'nutrition' or payload ? 'goal')
    and (not payload ? 'training' or private.is_valid_coach_training(payload -> 'training'))
    and (not payload ? 'nutrition' or private.is_valid_coach_nutrition(payload -> 'nutrition'))
    and (not payload ? 'goal' or private.is_valid_coach_goal(payload -> 'goal'));
$$;
revoke all on function private.is_valid_coach_proposal_row(text, jsonb, jsonb, jsonb)
  from public, anon, authenticated;

alter table public.change_proposals drop constraint change_proposals_schema_version_check;
alter table public.change_proposals add constraint change_proposals_schema_version_check
  check (schema_version in ('1.0', '2.0', '3.0'));
alter table public.change_proposals drop constraint change_proposals_valid_payload;
alter table public.change_proposals add constraint change_proposals_valid_payload check (
  case schema_version
    when '1.0' then private.is_valid_initial_proposal(proposed_training, proposed_nutrition)
    when '2.0' then private.is_valid_initial_proposal_v2(proposed_training, proposed_nutrition)
    else private.is_valid_coach_proposal_row(
      proposal_kind, proposed_training, proposed_nutrition, proposal_payload)
  end
);
alter table public.change_proposals add constraint change_proposals_coach_columns check (
  schema_version <> '3.0' or (
    before_snapshot is not null and after_snapshot is not null and basis is not null
    and jsonb_typeof(before_snapshot) = 'object' and jsonb_typeof(after_snapshot) = 'object'
    and jsonb_typeof(basis) = 'object'));

create index change_proposals_coach_user_recent
  on public.change_proposals (user_id, created_at desc) where schema_version = '3.0';

comment on column public.change_proposals.proposal_kind is
  'Coach proposals (schema 3.0): temporary_block, training_schedule, exercise_swap, intensity_or_phase, goal_or_phase, nutrition_targets or next_session_adjustment.';
comment on column public.change_proposals.proposal_payload is
  'What approval writes: {training?, nutrition?, goal?}. Every number was computed by rules (_shared/coach_proposals); the model chose only the kind and its closed-vocabulary parameters.';
comment on column public.change_proposals.basis is
  'The active version ids and screening outcome the proposal was computed from. Approval refuses once any has changed.';
comment on column public.change_proposals.applied_changes is
  'What approval created and replaced (version ids, the profile values changed), so undo can restore it.';

-- 2. Versions that end, and goals that remember their proposal --------------------------------

alter table public.training_plan_versions
  add column ends_on date,
  add column block_kind text check (block_kind in
    ('temporary_block', 'intensity', 'focus', 'next_session')),
  add column restores_version_id uuid,
  add constraint training_plan_versions_restores_fk
    foreign key (restores_version_id, user_id) references public.training_plan_versions (id, user_id),
  add constraint training_plan_versions_block_complete check (
    (ends_on is null) = (restores_version_id is null) and (ends_on is null) = (block_kind is null));

comment on column public.training_plan_versions.ends_on is
  'The last day a temporary block applies. After it the version named by restores_version_id returns as a new version. Null for an ordinary plan version.';

alter table public.user_goals add column source_proposal_id uuid;
alter table public.user_goals add constraint user_goals_source_proposal_fk
  foreign key (source_proposal_id, user_id) references public.change_proposals (id, user_id);

-- 3. Plan version helpers -----------------------------------------------------------------------

-- Inserts the workouts and exercises of a payload under a version.
create function private.coach_insert_workouts(
  p_user uuid, p_version uuid, p_structure jsonb)
returns void language plpgsql set search_path = '' as $$
declare
  workout jsonb;
  exercise jsonb;
  new_workout_id uuid;
begin
  for workout in select value from jsonb_array_elements(p_structure) loop
    insert into public.planned_workouts(
      user_id, plan_version_id, workout_order, name, objective, preferred_weekday,
      estimated_minutes, warm_up_guidance, cool_down_guidance
    ) values (
      p_user, p_version, (workout ->> 'workout_order')::smallint, workout ->> 'name',
      workout ->> 'objective', (workout ->> 'preferred_weekday')::smallint,
      (workout ->> 'estimated_minutes')::smallint, workout ->> 'warm_up_guidance',
      workout ->> 'cool_down_guidance'
    ) returning id into new_workout_id;
    for exercise in select value from jsonb_array_elements(workout -> 'exercises') loop
      insert into public.planned_exercises(
        user_id, planned_workout_id, exercise_order, display_name_snapshot, set_count,
        rep_min, rep_max, target_rpe, rest_seconds, notes, exercise_slug, target_load_kg
      ) values (
        p_user, new_workout_id, (exercise ->> 'exercise_order')::smallint, exercise ->> 'name',
        (exercise ->> 'sets')::smallint, (exercise ->> 'rep_min')::smallint,
        (exercise ->> 'rep_max')::smallint, (exercise ->> 'target_rpe')::numeric,
        (exercise ->> 'rest_seconds')::smallint, coalesce(exercise ->> 'notes', ''),
        exercise ->> 'slug', (exercise ->> 'start_load_kg')::numeric
      );
    end loop;
  end loop;
end $$;
revoke all on function private.coach_insert_workouts(uuid, uuid, jsonb)
  from public, anon, authenticated;

-- The next version number of a plan.
create function private.next_plan_version_number(p_plan uuid)
returns integer language sql stable set search_path = '' as $$
  select coalesce(max(version_number), 0) + 1 from public.training_plan_versions
  where plan_id = p_plan;
$$;
revoke all on function private.next_plan_version_number(uuid) from public, anon, authenticated;

-- Copies a version, with its workouts and exercises, as the athlete's new active version on the
-- source's plan. The source keeps its history; the copy carries the source's block fields so an
-- undo of a block's end brings the block back. Versions are inserted as drafts and activated
-- last, so the generic seed trigger never runs.
create function private.clone_plan_version(
  p_source uuid, p_user uuid, p_proposal uuid, p_rationale text)
returns uuid language plpgsql set search_path = '' as $$
declare
  source public.training_plan_versions%rowtype;
  new_version_id uuid;
  workout public.planned_workouts%rowtype;
  new_workout_id uuid;
begin
  select * into source from public.training_plan_versions
  where id = p_source and user_id = p_user;
  if not found then raise exception 'plan version not found' using errcode = 'P0002'; end if;

  update public.training_plan_versions set status = 'superseded'
  where user_id = p_user and status = 'active';
  insert into public.training_plan_versions(
    user_id, plan_id, version_number, status, block_weeks, sessions_per_week, prescription,
    rationale, source_proposal_id, approved_at, effective_date, ends_on, block_kind,
    restores_version_id
  ) values (
    p_user, source.plan_id, private.next_plan_version_number(source.plan_id), 'draft',
    source.block_weeks, source.sessions_per_week, source.prescription, p_rationale, p_proposal,
    statement_timestamp(), private.local_date_for(p_user), source.ends_on, source.block_kind,
    source.restores_version_id
  ) returning id into new_version_id;

  for workout in select * from public.planned_workouts
    where plan_version_id = source.id and user_id = p_user order by workout_order loop
    insert into public.planned_workouts(
      user_id, plan_version_id, workout_order, name, objective, preferred_weekday,
      estimated_minutes, warm_up_guidance, cool_down_guidance
    ) values (
      p_user, new_version_id, workout.workout_order, workout.name, workout.objective,
      workout.preferred_weekday, workout.estimated_minutes, workout.warm_up_guidance,
      workout.cool_down_guidance
    ) returning id into new_workout_id;
    insert into public.planned_exercises(
      user_id, planned_workout_id, exercise_order, display_name_snapshot, set_count, rep_min,
      rep_max, target_rpe, rest_seconds, notes, exercise_slug, target_load_kg
    ) select p_user, new_workout_id, e.exercise_order, e.display_name_snapshot, e.set_count,
        e.rep_min, e.rep_max, e.target_rpe, e.rest_seconds, e.notes, e.exercise_slug,
        e.target_load_kg
      from public.planned_exercises e
      where e.planned_workout_id = workout.id and e.user_id = p_user;
  end loop;

  update public.training_plan_versions set status = 'active' where id = new_version_id;
  return new_version_id;
end $$;
revoke all on function private.clone_plan_version(uuid, uuid, uuid, text)
  from public, anon, authenticated;

-- 7. Temporary blocks end -----------------------------------------------------------------------

-- Holds a restored plan to the athlete's current health check: under moderate_until_cleared no
-- exercise asks for more than effort 7. Used wherever an earlier plan returns (a block ends, an
-- undo), because that plan may have been approved under a weaker check.
create function private.hold_plan_to_screening(p_user uuid, p_version uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if private.current_screening_outcome(p_user) = 'moderate_until_cleared' then
    update public.planned_exercises e set target_rpe = least(e.target_rpe, 7)
    from public.planned_workouts w
    where w.plan_version_id = p_version and e.planned_workout_id = w.id
      and e.user_id = p_user and e.target_rpe is not null;
  end if;
end $$;
revoke all on function private.hold_plan_to_screening(uuid, uuid) from public, anon, authenticated;

-- Ends one active block: the version it replaced returns as a new version. Under a stricter health
-- check than the one the plan was approved under, the returning plan is held to moderate effort.
create function private.end_plan_block(p_version uuid)
returns uuid language plpgsql set search_path = '' as $$
declare
  block public.training_plan_versions%rowtype;
  restored_id uuid;
begin
  select * into block from public.training_plan_versions
  where id = p_version and status = 'active' and ends_on is not null for update;
  if not found then return null; end if;
  restored_id := private.clone_plan_version(
    block.restores_version_id, block.user_id, block.source_proposal_id,
    'Your temporary change ended, so your regular plan is back.');
  perform private.hold_plan_to_screening(block.user_id, restored_id);
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (block.user_id, 'coach_proposal_block_ended', 'training_plan_version', restored_id,
    'succeeded', jsonb_build_object('schema_version', '1.0', 'ended_version_id', block.id,
      'block_kind', block.block_kind, 'proposal_id', block.source_proposal_id));
  return restored_id;
end $$;
revoke all on function private.end_plan_block(uuid) from public, anon, authenticated;

-- Ends every active block whose last day has passed in its athlete's time zone (one athlete when
-- p_user is given). The hourly job calls it for everyone; the proposal reads and answers call it
-- for the caller first.
create function private.end_ended_plan_blocks(p_user uuid default null)
returns integer language plpgsql set search_path = '' as $$
declare
  due record;
  ended integer := 0;
begin
  for due in
    select v.id from public.training_plan_versions v
    where v.status = 'active' and v.ends_on is not null
      and (p_user is null or v.user_id = p_user)
      and v.ends_on < private.local_date_for(v.user_id)
  loop
    if private.end_plan_block(due.id) is not null then ended := ended + 1; end if;
  end loop;
  return ended;
end $$;
revoke all on function private.end_ended_plan_blocks(uuid) from public, anon, authenticated;

select cron.schedule('tracend-end-plan-blocks', '7 * * * *',
  'select private.end_ended_plan_blocks()');

-- 3. Store a proposal ----------------------------------------------------------------------------

-- The lowest daily calories the athlete's sex allows (the rules also apply the resting-energy
-- floor; this is the part the database can check for itself).
create function private.calorie_minimum_for(p_user uuid)
returns integer language sql stable set search_path = '' as $$
  select coalesce((select case when p.sex = 'female' then 1200 else 1500 end
    from public.user_profiles p where p.user_id = p_user), 1500);
$$;
revoke all on function private.calorie_minimum_for(uuid) from public, anon, authenticated;

create function private.active_goal_id(p_user uuid)
returns uuid language sql stable set search_path = '' as $$
  select g.id from public.user_goals g where g.user_id = p_user and g.status = 'active'
  order by g.priority, g.activated_at desc nulls last limit 1;
$$;
revoke all on function private.active_goal_id(uuid) from public, anon, authenticated;

-- The newest weight reading (an amended reading is replaced by its amendment), or null.
create function private.latest_weight_kg(p_user uuid)
returns numeric language sql stable set search_path = '' as $$
  select r.weight_kg from (
    select bm.measured_on as taken_on, bm.created_at as taken_at, bm.weight_kg
    from public.body_measurements bm
    where bm.user_id = p_user and bm.weight_kg is not null
      and not exists (select 1 from public.body_measurements newer
        where newer.user_id = bm.user_id and newer.amended_from_id = bm.id)
    union all
    select dhs.local_date, dhs.last_synced_at, dhs.weight_kg
    from public.daily_health_summaries dhs
    where dhs.user_id = p_user and dhs.weight_kg is not null
  ) r order by r.taken_on desc, r.taken_at desc limit 1;
$$;
revoke all on function private.latest_weight_kg(uuid) from public, anon, authenticated;

-- The profile fields the rules read. A proposal stores them when it is made and expires when
-- any has changed by the time it is answered.
create function private.coach_profile_check(p_user uuid)
returns jsonb language sql stable set search_path = '' as $$
  select to_jsonb(x) from (
    select p.sex, p.height_cm, p.birth_year, p.daily_activity, p.experience_level, p.equipment,
      p.avoid_patterns, p.training_days, p.session_minutes
    from public.user_profiles p where p.user_id = p_user) x;
$$;
revoke all on function private.coach_profile_check(uuid) from public, anon, authenticated;

-- True when every change-eligibility gate a proposal was built under still passes.
create function private.coach_gates_pass(p_user uuid, p_gates jsonb, p_date date)
returns boolean language plpgsql stable set search_path = '' as $$
declare
  eligibility jsonb;
  gate text;
begin
  if p_gates is null or jsonb_typeof(p_gates) <> 'array' or jsonb_array_length(p_gates) = 0 then
    return true;
  end if;
  eligibility := public.evaluate_change_eligibility(p_user, p_date);
  for gate in select jsonb_array_elements_text(p_gates) loop
    if gate not in ('nutrition_change', 'training_change')
      or coalesce((eligibility -> gate ->> 'eligible')::boolean, false) is not true then
      return false;
    end if;
  end loop;
  return true;
end $$;
revoke all on function private.coach_gates_pass(uuid, jsonb, date) from public, anon, authenticated;

create function public.persist_coach_proposal_v1(
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_rationale text,
  p_benefit text,
  p_downside text,
  p_confidence text,
  p_evidence jsonb,
  p_before jsonb,
  p_after jsonb,
  p_payload jsonb,
  p_basis jsonb,
  p_ends_on date,
  p_expires_in_hours integer,
  p_source_message_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  new_id uuid;
  new_expires timestamptz;
  nutrition jsonb := p_payload -> 'nutrition';
  summary_training jsonb;
  stored_basis jsonb;
begin
  if p_user_id is null or not exists (select 1 from public.user_accounts where id = p_user_id) then
    raise exception 'account not found' using errcode = 'P0002';
  end if;
  if p_kind is null or p_title is null or length(p_title) not between 1 and 120
    or p_rationale is null or length(p_rationale) not between 1 and 2000
    or p_benefit is null or length(p_benefit) not between 1 and 1000
    or p_downside is null or length(p_downside) not between 1 and 1000
    or p_confidence not in ('low', 'medium', 'high')
    or jsonb_typeof(p_evidence) is distinct from 'array'
    or jsonb_typeof(p_before) is distinct from 'object'
    or jsonb_typeof(p_after) is distinct from 'object'
    or jsonb_typeof(p_basis) is distinct from 'object'
    or p_expires_in_hours is null or p_expires_in_hours not between 1 and 168 then
    raise exception 'coach proposal is invalid' using errcode = '22023';
  end if;
  summary_training := jsonb_build_object('proposal_kind', p_kind, 'title', p_title);
  if not private.is_valid_coach_proposal_row(p_kind, summary_training,
    coalesce(nutrition - 'rationale', '{}'::jsonb), p_payload) then
    raise exception 'coach proposal is invalid' using errcode = '22023';
  end if;
  if p_payload ? 'training' and not private.coach_training_uses_catalog(p_payload -> 'training') then
    raise exception 'coach proposal is invalid' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.user_profiles
    where user_id = p_user_id and eligible is true and adult_attested_at is not null
  ) then
    raise exception 'eligible adult profile required' using errcode = '22023';
  end if;
  if nutrition is not null
    and (nutrition ->> 'calories')::integer < private.calorie_minimum_for(p_user_id) then
    raise exception 'calories are below the minimum' using errcode = '22023';
  end if;
  if p_payload ? 'goal' and p_payload -> 'goal' -> 'target' is not null and (
    (p_payload -> 'goal' -> 'target' ->> 'weight_kg')::numeric
      < coalesce(private.healthy_floor_weight_kg(p_user_id), 0)
    or (p_payload -> 'goal' -> 'target' ->> 'date')::date
      not between private.local_date_for(p_user_id) + 1 and private.local_date_for(p_user_id) + 1096
  ) then
    raise exception 'target is outside the healthy range' using errcode = '22023';
  end if;

  -- The health check may have changed while the proposal was being built.
  perform private.assert_screening_allows(p_user_id, p_basis ->> 'screening');
  perform private.end_ended_plan_blocks(p_user_id);
  if (p_payload ? 'training' and p_basis ->> 'training_version_id' is distinct from (
      select v.id::text from public.training_plan_versions v
      where v.user_id = p_user_id and v.status = 'active'))
    or (p_payload ? 'nutrition' and p_basis ->> 'nutrition_version_id' is distinct from (
      select n.id::text from public.nutrition_target_sets n
      where n.user_id = p_user_id and n.status = 'active'))
    or (p_payload ? 'goal' and p_basis ->> 'goal_id' is distinct from
      private.active_goal_id(p_user_id)::text) then
    raise exception 'the plan changed while the proposal was built' using errcode = '55000';
  end if;

  if not private.coach_gates_pass(p_user_id, p_basis -> 'gates', private.local_date_for(p_user_id))
  then
    raise exception 'not enough logged data for this change' using errcode = '55000';
  end if;
  -- What the rules checked, kept with the proposal: approval refuses once any has moved.
  stored_basis := p_basis || jsonb_build_object(
    'weight_check_kg', private.latest_weight_kg(p_user_id),
    'profile_check', private.coach_profile_check(p_user_id));

  -- A newer proposal replaces an open one that would change the same thing.
  update public.change_proposals set status = 'expired'
  where user_id = p_user_id and status = 'pending' and schema_version = '3.0'
    and (proposal_kind = p_kind
      or (p_payload ? 'nutrition' and proposal_payload ? 'nutrition')
      or (p_payload ? 'training' and proposal_payload ? 'training')
      or (p_payload ? 'goal' and proposal_payload ? 'goal'));

  new_expires := statement_timestamp() + make_interval(hours => p_expires_in_hours);
  insert into public.change_proposals(
    user_id, feature_snapshot_id, schema_version, proposed_training, proposed_nutrition,
    evidence, rationale, expected_benefit, downside, confidence, effective_date, expires_at,
    proposal_kind, proposal_payload, before_snapshot, after_snapshot, basis, source_message_id,
    ends_on
  ) values (
    p_user_id, null, '3.0', summary_training, coalesce(nutrition - 'rationale', '{}'::jsonb),
    p_evidence, p_rationale, p_benefit, p_downside, p_confidence,
    private.local_date_for(p_user_id), new_expires,
    p_kind, p_payload, p_before, p_after, stored_basis, p_source_message_id, p_ends_on
  ) returning id into new_id;

  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (p_user_id, 'coach_proposal_created', 'change_proposal', new_id, 'succeeded',
    jsonb_build_object('schema_version', '3.0', 'kind', p_kind));

  return jsonb_build_object('schema_version', '1.0', 'proposal_id', new_id,
    'expires_at', new_expires);
end $$;
revoke all on function public.persist_coach_proposal_v1(uuid, text, text, text, text, text, text,
  jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid) from public, anon, authenticated;
grant execute on function public.persist_coach_proposal_v1(uuid, text, text, text, text, text,
  text, jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid) to service_role;

-- 4. Read ------------------------------------------------------------------------------------------

-- True while the versions a proposal created are still the active ones: a later change that
-- replaced them cannot be undone from here without overwriting that change.
create function private.coach_proposal_is_current(p public.change_proposals)
returns boolean language sql stable set search_path = '' as $$
  select (p.applied_changes -> 'training_version_id' is null
      or p.applied_changes ->> 'training_version_id' = (
        select v.id::text from public.training_plan_versions v
        where v.user_id = p.user_id and v.status = 'active'))
    and (p.applied_changes -> 'nutrition_version_id' is null
      or p.applied_changes ->> 'nutrition_version_id' = (
        select n.id::text from public.nutrition_target_sets n
        where n.user_id = p.user_id and n.status = 'active'))
    and (p.applied_changes -> 'goal_id' is null
      or p.applied_changes ->> 'goal_id' = private.active_goal_id(p.user_id)::text);
$$;
revoke all on function private.coach_proposal_is_current(public.change_proposals)
  from public, anon, authenticated;

create function private.coach_proposal_json(p public.change_proposals)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id,
    'kind', p.proposal_kind,
    'status', case
      when p.undone_at is not null then 'undone'
      when p.status = 'accepted' then 'accepted'
      when p.status = 'rejected' then 'declined'
      when p.status = 'revision_requested' then 'changed'
      when p.status = 'expired' or p.expires_at <= statement_timestamp() then 'expired'
      else 'pending' end,
    'title', p.proposed_training -> 'title',
    'rationale', p.rationale,
    'benefit', p.expected_benefit,
    'downside', p.downside,
    'confidence', p.confidence,
    'evidence', p.evidence,
    'before', p.before_snapshot,
    'after', p.after_snapshot,
    'created_at', p.created_at,
    'expires_at', p.expires_at,
    'ends_on', p.ends_on,
    'applied_at', p.applied_at,
    'undo_until', p.undo_until,
    'undone_at', p.undone_at,
    'can_undo', p.status = 'accepted' and p.undone_at is null
      and p.undo_until > statement_timestamp() and private.coach_proposal_is_current(p),
    'source_message_id', p.source_message_id);
$$;
revoke all on function private.coach_proposal_json(public.change_proposals)
  from public, anon, authenticated;

-- The caller's Coach proposals, newest first (one proposal when p_proposal_id is given).
create function public.get_my_coach_proposals_v1(
  p_proposal_id uuid default null, p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  perform private.end_ended_plan_blocks(auth.uid());
  return jsonb_build_object('schema_version', '1.0', 'proposals', coalesce((
    select jsonb_agg(private.coach_proposal_json(c) order by c.created_at desc)
    from public.change_proposals c
    where c.id in (
      select x.id from public.change_proposals x
      where x.user_id = auth.uid() and x.schema_version = '3.0'
        and (p_proposal_id is null or x.id = p_proposal_id)
      order by x.created_at desc limit greatest(1, least(coalesce(p_limit, 10), 50)))
  ), '[]'::jsonb));
end $$;
revoke all on function public.get_my_coach_proposals_v1(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.get_my_coach_proposals_v1(uuid, integer) to authenticated;

-- 5. Answer ------------------------------------------------------------------------------------------

-- Approve writes the proposal's new version(s) with a source proposal id, the answer and an audit
-- event. Decline closes it. "change" closes it too, so the athlete's follow-up message in chat
-- starts a fresh proposal. A proposal that expired, or whose basis changed, or whose block already
-- ended is recorded as expired and reported, never applied.
create function public.respond_to_coach_proposal_v1(
  proposal_id uuid, action text, note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  proposal public.change_proposals%rowtype;
  training jsonb;
  goal_change jsonb;
  nutrition_change jsonb;
  clean_note text := nullif(btrim(respond_to_coach_proposal_v1.note), '');
  today date := private.local_date_for(auth.uid());
  previous_version public.training_plan_versions%rowtype;
  previous_nutrition public.nutrition_target_sets%rowtype;
  previous_goal public.user_goals%rowtype;
  new_plan_id uuid;
  new_version_id uuid;
  new_nutrition_id uuid;
  new_goal_id uuid;
  applied jsonb := '{}'::jsonb;
  stale text;
  new_details jsonb;
  goal_floor numeric;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if action not in ('approve', 'decline', 'change') then
    raise exception 'unknown action' using errcode = '22023';
  end if;
  if clean_note is not null and length(clean_note) > 500 then
    raise exception 'note too long' using errcode = '22023';
  end if;
  perform private.end_ended_plan_blocks(auth.uid());

  select * into proposal from public.change_proposals
  where id = respond_to_coach_proposal_v1.proposal_id and user_id = auth.uid() for update;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  if proposal.schema_version <> '3.0' then
    raise exception 'proposal is not a coach proposal' using errcode = '22023';
  end if;
  if proposal.status <> 'pending' then
    raise exception 'proposal is not pending' using errcode = '55000';
  end if;

  training := proposal.proposal_payload -> 'training';
  nutrition_change := proposal.proposal_payload -> 'nutrition';
  goal_change := proposal.proposal_payload -> 'goal';

  -- Why an open proposal can no longer be applied, or null.
  stale := case
    when proposal.expires_at <= statement_timestamp() then 'expired'
    when training is not null and proposal.basis ->> 'training_version_id' is distinct from (
      select v.id::text from public.training_plan_versions v
      where v.user_id = auth.uid() and v.status = 'active') then 'plan_changed'
    when nutrition_change is not null and proposal.basis ->> 'nutrition_version_id' is distinct from (
      select n.id::text from public.nutrition_target_sets n
      where n.user_id = auth.uid() and n.status = 'active') then 'nutrition_changed'
    when goal_change is not null and proposal.basis ->> 'goal_id' is distinct from
      private.active_goal_id(auth.uid())::text then 'goal_changed'
    when not private.coach_gates_pass(auth.uid(), proposal.basis -> 'gates', today)
      then 'not_eligible'
    when nutrition_change is not null
      and (nutrition_change ->> 'calories')::integer < private.calorie_minimum_for(auth.uid())
      then 'below_minimum'
    when training is not null and training ->> 'mode' <> 'end_block'
      and not private.coach_training_uses_catalog(training) then 'catalog_changed'
    when proposal.basis -> 'profile_check' is distinct from
      private.coach_profile_check(auth.uid()) then 'profile_changed'
    when proposal.basis ->> 'weight_check_kg' is not null
      and coalesce(abs(private.latest_weight_kg(auth.uid())
        - (proposal.basis ->> 'weight_check_kg')::numeric)
        > 0.01 * (proposal.basis ->> 'weight_check_kg')::numeric, true) then 'weight_changed'
    when training ->> 'mode' = 'block' and (training ->> 'ends_on')::date < today then 'block_over'
    when training ->> 'mode' in ('new_version', 'block') and exists (
      select 1 from public.training_plan_versions v
      where v.user_id = auth.uid() and v.status = 'active' and v.ends_on is not null)
      then 'block_running'
    when training ->> 'mode' = 'end_block' and not exists (
      select 1 from public.training_plan_versions v
      where v.user_id = auth.uid() and v.status = 'active' and v.ends_on is not null)
      then 'plan_changed'
    else null end;
  if stale is not null and action = 'approve' then
    update public.change_proposals set status = 'expired' where id = proposal.id;
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (auth.uid(), 'coach_proposal_expired', 'change_proposal', proposal.id, 'succeeded',
      jsonb_build_object('schema_version', '3.0', 'kind', proposal.proposal_kind, 'reason', stale));
    return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
      'status', 'expired', 'reason', stale, 'training_plan_version_id', null,
      'nutrition_target_set_id', null, 'goal_id', null, 'undo_until', null);
  end if;

  if action = 'approve' then
    -- A proposal built before the health check got stricter cannot be approved.
    perform private.assert_screening_allows(auth.uid(), proposal.basis ->> 'screening');

    if training is not null then
      select * into previous_version from public.training_plan_versions
      where user_id = auth.uid() and status = 'active' for update;
      applied := applied || jsonb_build_object('previous_training_version_id', previous_version.id);
      if training ->> 'mode' = 'end_block' then
        new_version_id := private.end_plan_block(previous_version.id);
        update public.training_plan_versions set source_proposal_id = proposal.id
        where id = new_version_id;
      else
        if training ->> 'mode' = 'block' then
          insert into public.training_plans(user_id, goal_id, title, source)
          select auth.uid(), p.goal_id, training ->> 'title', 'rules'
          from public.training_plans p where p.id = previous_version.plan_id
          returning id into new_plan_id;
        else
          new_plan_id := previous_version.plan_id;
        end if;
        update public.training_plan_versions set status = 'superseded'
        where user_id = auth.uid() and status = 'active';
        insert into public.training_plan_versions(
          user_id, plan_id, version_number, status, block_weeks, sessions_per_week, prescription,
          rationale, source_proposal_id, approved_at, effective_date, ends_on, block_kind,
          restores_version_id
        ) values (
          auth.uid(), new_plan_id, private.next_plan_version_number(new_plan_id), 'draft',
          (training ->> 'block_weeks')::smallint,
          jsonb_array_length(training -> 'weekly_structure')::smallint,
          previous_version.prescription, proposal.rationale, proposal.id, statement_timestamp(),
          today,
          case when training ->> 'mode' = 'block' then (training ->> 'ends_on')::date end,
          case when training ->> 'mode' = 'block' then training ->> 'block_kind' end,
          case when training ->> 'mode' = 'block' then previous_version.id end
        ) returning id into new_version_id;
        perform private.coach_insert_workouts(auth.uid(), new_version_id,
          training -> 'weekly_structure');
        update public.training_plan_versions set status = 'active' where id = new_version_id;
        if training -> 'profile' is not null then
          applied := applied || jsonb_build_object('profile_before', (
            select jsonb_build_object('training_days', to_jsonb(p.training_days),
              'session_minutes', p.session_minutes)
            from public.user_profiles p where p.user_id = auth.uid()));
          update public.user_profiles set
            training_days = array(select value::smallint
              from jsonb_array_elements_text(training -> 'profile' -> 'training_days') value),
            session_minutes = (training -> 'profile' ->> 'session_minutes')::smallint
          where user_id = auth.uid();
          applied := applied || jsonb_build_object('profile_after', jsonb_build_object(
            'training_days', training -> 'profile' -> 'training_days',
            'session_minutes', training -> 'profile' -> 'session_minutes'));
        end if;
      end if;
      applied := applied || jsonb_build_object('training_version_id', new_version_id);
    end if;

    if nutrition_change is not null then
      select * into previous_nutrition from public.nutrition_target_sets
      where user_id = auth.uid() and status = 'active' for update;
      update public.nutrition_target_sets set status = 'superseded'
      where user_id = auth.uid() and status = 'active';
      insert into public.nutrition_target_sets(
        user_id, version_number, status, calories, protein_g, carbohydrate_g, fat_g, rationale,
        source_proposal_id, approved_at, effective_date
      ) values (
        auth.uid(),
        coalesce((select max(version_number) + 1 from public.nutrition_target_sets
          where user_id = auth.uid()), 1),
        'active', (nutrition_change ->> 'calories')::integer,
        (nutrition_change ->> 'protein_g')::integer,
        (nutrition_change ->> 'carbohydrate_g')::integer,
        (nutrition_change ->> 'fat_g')::integer, nutrition_change ->> 'rationale',
        proposal.id, statement_timestamp(), today
      ) returning id into new_nutrition_id;
      applied := applied || jsonb_build_object('previous_nutrition_version_id', previous_nutrition.id,
        'nutrition_version_id', new_nutrition_id);
    end if;

    if goal_change is not null then
      select * into previous_goal from public.user_goals
      where id = private.active_goal_id(auth.uid()) for update;
      goal_floor := private.healthy_floor_weight_kg(auth.uid());
      if goal_change -> 'target' is not null and (
        (goal_change -> 'target' ->> 'weight_kg')::numeric < coalesce(goal_floor, 0)
        or (goal_change -> 'target' ->> 'date')::date not between today + 1 and today + 1096) then
        raise exception 'target is outside the healthy range' using errcode = '22023';
      end if;
      -- A new target replaces the old one; without a new target the old one stays.
      new_details := case when goal_change -> 'target' is not null
        then (previous_goal.details - private.goal_target_keys()
            - array['phase', 'phase_started_on', 'phase_ends_on'])
          || jsonb_strip_nulls(jsonb_build_object(
            'target_weight_kg', goal_change -> 'target' -> 'weight_kg',
            'target_date', goal_change -> 'target' -> 'date',
            'target_set_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))
        else previous_goal.details - array['phase', 'phase_started_on', 'phase_ends_on']
      end || jsonb_strip_nulls(jsonb_build_object(
          'phase', goal_change -> 'phase',
          'phase_started_on', goal_change -> 'phase_started_on',
          'phase_ends_on', goal_change -> 'phase_ends_on'));
      update public.user_goals set status = 'superseded' where id = previous_goal.id;
      insert into public.user_goals(
        user_id, goal_type, priority, status, details, activated_at, source_proposal_id)
      values (
        auth.uid(), (goal_change ->> 'goal_type')::public.goal_type, previous_goal.priority,
        'active', new_details,
        case when (goal_change ->> 'goal_type')::public.goal_type = previous_goal.goal_type
          then previous_goal.activated_at else statement_timestamp() end,
        proposal.id
      ) returning id into new_goal_id;
      applied := applied || jsonb_build_object('previous_goal_id', previous_goal.id,
        'goal_id', new_goal_id);
    end if;

    update public.change_proposals set status = 'accepted', applied_at = statement_timestamp(),
      undo_until = statement_timestamp() + interval '7 days', applied_changes = applied
    where id = proposal.id returning * into proposal;
    insert into public.change_responses(user_id, proposal_id, action)
    values (auth.uid(), proposal.id, 'accept');
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (auth.uid(), 'coach_proposal_accepted', 'change_proposal', proposal.id, 'succeeded',
      jsonb_build_object('schema_version', '3.0', 'kind', proposal.proposal_kind,
        'training_version_id', new_version_id, 'nutrition_version_id', new_nutrition_id,
        'goal_id', new_goal_id));
    return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
      'status', 'accepted', 'training_plan_version_id', new_version_id,
      'nutrition_target_set_id', new_nutrition_id, 'goal_id', new_goal_id,
      'undo_until', proposal.undo_until);
  end if;

  update public.change_proposals
  set status = case action when 'decline' then 'rejected' else 'revision_requested' end::public.proposal_status
  where id = proposal.id;
  insert into public.change_responses(user_id, proposal_id, action, revision_note)
  values (auth.uid(), proposal.id,
    case action when 'decline' then 'reject' else 'request_revision' end::public.proposal_response_action,
    case when action = 'change' then clean_note end);
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'coach_proposal_' || case action when 'decline' then 'declined' else 'changed' end,
    'change_proposal', proposal.id, 'succeeded',
    jsonb_build_object('schema_version', '3.0', 'kind', proposal.proposal_kind));
  return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
    'status', case action when 'decline' then 'declined' else 'changed' end,
    'training_plan_version_id', null, 'nutrition_target_set_id', null, 'goal_id', null,
    'undo_until', null);
end $$;
revoke all on function public.respond_to_coach_proposal_v1(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.respond_to_coach_proposal_v1(uuid, text, text) to authenticated;

-- 6. Undo -------------------------------------------------------------------------------------------

-- Restores what an approved proposal replaced, as new versions, within seven days of approval and
-- only while the versions it created are still the active ones. Reports "superseded" when a later
-- change replaced them and "undo_window_ended" after seven days; neither raises.
create function public.undo_coach_proposal_v1(proposal_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  proposal public.change_proposals%rowtype;
  applied jsonb;
  restored_training uuid;
  restored_nutrition uuid;
  restored_goal uuid;
  source_nutrition public.nutrition_target_sets%rowtype;
  source_goal public.user_goals%rowtype;
  undone_at_value timestamptz := statement_timestamp();
  report text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  perform private.end_ended_plan_blocks(auth.uid());
  select * into proposal from public.change_proposals
  where id = undo_coach_proposal_v1.proposal_id and user_id = auth.uid() for update;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  if proposal.schema_version <> '3.0' or proposal.status <> 'accepted' then
    raise exception 'proposal is not an approved coach proposal' using errcode = '55000';
  end if;
  report := case
    when proposal.undone_at is not null then 'undone'
    when proposal.undo_until <= undone_at_value then 'undo_window_ended'
    when not private.coach_proposal_is_current(proposal) then 'superseded'
    else null end;
  if report is not null then
    return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
      'status', report, 'training_plan_version_id', null, 'nutrition_target_set_id', null,
      'goal_id', null);
  end if;
  applied := proposal.applied_changes;

  if applied ? 'previous_training_version_id' then
    if private.current_screening_outcome(auth.uid()) = 'see_professional' then
      raise exception 'a health professional must clear this athlete first' using errcode = '55000';
    end if;
    restored_training := private.clone_plan_version(
      (applied ->> 'previous_training_version_id')::uuid, auth.uid(), proposal.id,
      'You undid a change from Coach, so your earlier plan is back.');
    -- The earlier plan may have been approved under a weaker health check.
    perform private.hold_plan_to_screening(auth.uid(), restored_training);
    -- A profile value the athlete changed since is theirs: only values still as the proposal set
    -- them go back.
    if applied ? 'profile_before' and applied ? 'profile_after' then
      update public.user_profiles p set
        training_days = case
          when to_jsonb(p.training_days) = applied -> 'profile_after' -> 'training_days'
          then array(select value::smallint
            from jsonb_array_elements_text(applied -> 'profile_before' -> 'training_days') value)
          else p.training_days end,
        session_minutes = case
          when to_jsonb(p.session_minutes) = applied -> 'profile_after' -> 'session_minutes'
          then (applied -> 'profile_before' ->> 'session_minutes')::smallint
          else p.session_minutes end
      where p.user_id = auth.uid();
    end if;
  end if;

  if applied ? 'previous_nutrition_version_id' then
    select * into source_nutrition from public.nutrition_target_sets
    where id = (applied ->> 'previous_nutrition_version_id')::uuid and user_id = auth.uid();
    update public.nutrition_target_sets set status = 'superseded'
    where user_id = auth.uid() and status = 'active';
    insert into public.nutrition_target_sets(
      user_id, version_number, status, calories, protein_g, carbohydrate_g, fat_g, rationale,
      source_proposal_id, approved_at, effective_date
    ) values (
      auth.uid(),
      (select max(version_number) + 1 from public.nutrition_target_sets where user_id = auth.uid()),
      'active', source_nutrition.calories, source_nutrition.protein_g,
      source_nutrition.carbohydrate_g, source_nutrition.fat_g,
      'You undid a change from Coach, so your earlier targets are back.', proposal.id,
      statement_timestamp(), private.local_date_for(auth.uid())
    ) returning id into restored_nutrition;
  end if;

  if applied ? 'previous_goal_id' then
    select * into source_goal from public.user_goals
    where id = (applied ->> 'previous_goal_id')::uuid and user_id = auth.uid();
    update public.user_goals set status = 'superseded'
    where user_id = auth.uid() and status = 'active' and priority = source_goal.priority;
    insert into public.user_goals(
      user_id, goal_type, priority, status, details, activated_at, source_proposal_id)
    values (auth.uid(), source_goal.goal_type, source_goal.priority, 'active',
      source_goal.details, source_goal.activated_at, proposal.id)
    returning id into restored_goal;
  end if;

  update public.change_proposals set undone_at = undone_at_value where id = proposal.id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'coach_proposal_undone', 'change_proposal', proposal.id, 'succeeded',
    jsonb_build_object('schema_version', '3.0', 'kind', proposal.proposal_kind,
      'training_version_id', restored_training, 'nutrition_version_id', restored_nutrition,
      'goal_id', restored_goal));
  return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
    'status', 'undone', 'training_plan_version_id', restored_training,
    'nutrition_target_set_id', restored_nutrition, 'goal_id', restored_goal);
end $$;
revoke all on function public.undo_coach_proposal_v1(uuid) from public, anon, authenticated;
grant execute on function public.undo_coach_proposal_v1(uuid) to authenticated;

-- 8. What the rules read ---------------------------------------------------------------------------------

-- The athlete's state for the proposal builder (_shared/coach_proposals): profile, current health
-- check outcome, the active plan with its sessions, the active nutrition target and goal, the
-- change-eligibility gates and whether today's session is done. Weight readings and next-session
-- targets come from get_goal_phase_inputs_v1 and get_progression_summary_v1. Service role only.
create function public.get_coach_proposal_inputs_v1(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  today date := private.local_date_for(p_user_id);
  eligibility jsonb;
begin
  if p_user_id is null or not exists (select 1 from public.user_accounts where id = p_user_id) then
    raise exception 'account not found' using errcode = 'P0002';
  end if;
  -- A block whose last day has passed is ended first, so it is never shown or enforced as running.
  perform private.end_ended_plan_blocks(p_user_id);
  eligibility := public.evaluate_change_eligibility(p_user_id, today);
  return jsonb_build_object(
    'schema_version', '1.0',
    'local_date', today,
    'screening', private.current_screening_outcome(p_user_id),
    'profile', (select jsonb_build_object(
        'sex', p.sex, 'birth_year', p.birth_year, 'height_cm', p.height_cm,
        'experience', p.experience_level, 'daily_activity', p.daily_activity,
        'equipment', to_jsonb(p.equipment), 'avoid_patterns', to_jsonb(p.avoid_patterns),
        'training_days', to_jsonb(p.training_days), 'session_minutes', p.session_minutes,
        'priority_muscles', to_jsonb(p.priority_muscles), 'strong_muscles', to_jsonb(p.strong_muscles))
      from public.user_profiles p where p.user_id = p_user_id),
    'plan', (select jsonb_build_object(
        'version_id', v.id, 'plan_id', v.plan_id, 'version_number', v.version_number,
        'title', tp.title, 'block_weeks', v.block_weeks, 'ends_on', v.ends_on,
        'block_kind', v.block_kind,
        'workouts', coalesce((select jsonb_agg(jsonb_build_object(
            'name', w.name, 'objective', w.objective, 'weekday', w.preferred_weekday,
            'estimated_minutes', w.estimated_minutes, 'warm_up', w.warm_up_guidance,
            'cool_down', w.cool_down_guidance,
            'exercises', coalesce((select jsonb_agg(jsonb_build_object(
                'slug', e.exercise_slug, 'name', e.display_name_snapshot, 'sets', e.set_count,
                'rep_min', e.rep_min, 'rep_max', e.rep_max, 'target_rpe', e.target_rpe,
                'rest_seconds', e.rest_seconds, 'notes', e.notes,
                'target_load_kg', e.target_load_kg) order by e.exercise_order)
              from public.planned_exercises e
              where e.planned_workout_id = w.id and e.user_id = p_user_id), '[]'::jsonb))
            order by w.workout_order)
          from public.planned_workouts w
          where w.plan_version_id = v.id and w.user_id = p_user_id), '[]'::jsonb))
      from public.training_plan_versions v
      join public.training_plans tp on tp.id = v.plan_id and tp.user_id = v.user_id
      where v.user_id = p_user_id and v.status = 'active'),
    'nutrition', (select jsonb_build_object(
        'version_id', n.id, 'calories', n.calories, 'protein_g', n.protein_g,
        'carbohydrate_g', n.carbohydrate_g, 'fat_g', n.fat_g)
      from public.nutrition_target_sets n where n.user_id = p_user_id and n.status = 'active'),
    'goal', (select jsonb_build_object(
        'id', g.id, 'goal_type', g.goal_type, 'details', g.details,
        'activated_on', (g.activated_at at time zone coalesce((
          select a.timezone from public.user_accounts a
          join pg_catalog.pg_timezone_names z on z.name = a.timezone
          where a.id = p_user_id), 'UTC'))::date)
      from public.user_goals g where g.id = private.active_goal_id(p_user_id)),
    'eligibility', jsonb_build_object(
      'training_eligible', (eligibility -> 'training_change' ->> 'eligible')::boolean,
      'training_detail', eligibility -> 'training_change' ->> 'detail',
      'nutrition_eligible', (eligibility -> 'nutrition_change' ->> 'eligible')::boolean,
      'nutrition_detail', eligibility -> 'nutrition_change' ->> 'detail'),
    'today_workout_done', exists (
      select 1 from public.workout_sessions s
      where s.user_id = p_user_id and s.local_date = today and s.state = 'completed'));
end $$;
revoke all on function public.get_coach_proposal_inputs_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_coach_proposal_inputs_v1(uuid) to service_role;

-- 9. Chat -------------------------------------------------------------------------------------------

-- An assistant message points at the proposal it introduced, so the thread (live and reloaded)
-- shows the card under the reply. Set by link_coach_proposal_v1 after the reply is stored.
alter table public.coach_messages
  add column proposal_id uuid references public.change_proposals(id) on delete set null;

create function public.link_coach_proposal_v1(
  p_user_id uuid, p_message_id uuid, p_proposal_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.coach_messages set proposal_id = p_proposal_id
  where id = p_message_id and user_id = p_user_id and role = 'assistant'
    and exists (select 1 from public.change_proposals c
      where c.id = p_proposal_id and c.user_id = p_user_id and c.schema_version = '3.0');
  if not found then raise exception 'message or proposal not found' using errcode = 'P0002'; end if;
  update public.change_proposals set source_message_id = p_message_id
  where id = p_proposal_id and user_id = p_user_id;
end $$;
revoke all on function public.link_coach_proposal_v1(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.link_coach_proposal_v1(uuid, uuid, uuid) to service_role;

-- What Coach is told about the athlete's proposals: a temporary block that is running and when it
-- ends, the goal phase and when it ends (a diet break that has ended is reported as ended, so Coach
-- raises the next step), proposals waiting for an answer, and how the recent ones were answered.
-- Service role only; the Coach context contributor reads it.
create function public.get_coach_proposals_context_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'local_date', p_local_date,
    'block', (select jsonb_build_object('title', tp.title, 'kind', v.block_kind,
        'started_on', v.effective_date, 'ends_on', v.ends_on)
      from public.training_plan_versions v
      join public.training_plans tp on tp.id = v.plan_id and tp.user_id = v.user_id
      where v.user_id = p_user_id and v.status = 'active' and v.ends_on is not null
        and v.ends_on >= p_local_date),
    'phase', (select jsonb_build_object('phase', g.details ->> 'phase',
        'started_on', g.details ->> 'phase_started_on', 'ends_on', g.details ->> 'phase_ends_on')
      from public.user_goals g where g.id = private.active_goal_id(p_user_id)
        and g.details ? 'phase'),
    'proposals', coalesce((select jsonb_agg(x.item order by x.created_at desc) from (
        select c.created_at, jsonb_build_object(
          'kind', c.proposal_kind, 'title', c.proposed_training ->> 'title',
          'status', private.coach_proposal_json(c) ->> 'status',
          'created_on', c.created_at::date, 'expires_at', c.expires_at, 'ends_on', c.ends_on) item
        from public.change_proposals c
        where c.user_id = p_user_id and c.schema_version = '3.0'
          and c.created_at > statement_timestamp() - interval '60 days'
        order by c.created_at desc limit 8) x), '[]'::jsonb));
$$;
revoke all on function public.get_coach_proposals_context_v1(uuid, date)
  from public, anon, authenticated;
grant execute on function public.get_coach_proposals_context_v1(uuid, date) to service_role;
