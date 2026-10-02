-- Coach intake (2026-10): the onboarding plan learns who the athlete is.
--
-- - The profile keeps how long the athlete has trained and the muscles they
--   want to bring up (at most two) or see as strong.
-- - A planned exercise can carry a starting load, set by deterministic code
--   from the athlete's reported barbell top sets; the training hub (1.5) and
--   the daily brief (1.6) return it, and the active workout pre-fills it.
-- - The coach's follow-up questions are stored per set of answers, so a retry
--   never asks the model twice.
-- - The app sends the athlete's usual months from Apple Health as monthly
--   totals for the 11 completed months before this one (never raw samples).
-- - onboarding-policy-v2 snapshots are accepted.
--
-- Forward-only and additive: new nullable columns, new tables, and functions
-- recreated from their latest versions with the same signatures.

-- Profile -------------------------------------------------------------------

alter table public.user_profiles
  add column training_years text
    check (training_years in ('under_1','1_2','3_5','over_5')),
  add column priority_muscles text[]
    check (cardinality(priority_muscles) <= 2 and priority_muscles <@ array['quads','glutes','hamstrings','chest','back','shoulders','biceps','triceps','core','calves']),
  add column strong_muscles text[]
    check (cardinality(strong_muscles) <= 3 and strong_muscles <@ array['quads','glutes','hamstrings','chest','back','shoulders','biceps','triceps','core','calves']);

-- Starting loads ------------------------------------------------------------

-- The same bounds as exercise_sets.load_kg.
alter table public.planned_exercises
  add column target_load_kg numeric(7,2) check (target_load_kg between 0 and 2000);

-- A 2.0 proposal exercise may carry start_load_kg; proposals without it stay valid.
create or replace function private.is_valid_initial_proposal_v2(training jsonb, nutrition jsonb)
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
            and (exercise -> 'start_load_kg' is null
              or private.jsonb_number_between(exercise -> 'start_load_kg', 0, 2000))
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

-- Snapshots record the policy version the plan was built under.
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

-- Approval copies starting loads and the intake answers.
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

-- Planned exercises report their starting load.
create or replace function private.planned_workout_for_date(target_user_id uuid, target_date date)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'id',w.id,'weekday',w.preferred_weekday,'name',w.name,'objective',w.objective,
    'estimated_minutes',w.estimated_minutes,'warm_up',w.warm_up_guidance,
    'cooldown_cardio',w.cool_down_guidance,
    'exercises',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'order',e.exercise_order,'name',e.display_name_snapshot,
      'set_count',e.set_count,'rep_min',e.rep_min,'rep_max',e.rep_max,
      'target_rpe',e.target_rpe,'rest_seconds',e.rest_seconds,'notes',e.notes,
      'target_load_kg',e.target_load_kg
    ) order by e.exercise_order)
    from public.planned_exercises e
    where e.planned_workout_id=w.id and e.user_id=target_user_id),'[]'::jsonb))
  from public.planned_workouts w
  join public.training_plan_versions v on v.id=w.plan_version_id and v.user_id=w.user_id
  where w.user_id=target_user_id and v.status='active'
    and w.preferred_weekday=extract(isodow from target_date)::integer
  order by w.workout_order
  limit 1;
$$;

create or replace function public.get_my_training_hub(period_days integer default 28)
returns jsonb language sql security definer set search_path='' stable as $$
with active_version as (
  select v.id,v.plan_id,v.version_number,v.block_weeks,v.sessions_per_week,
    v.rationale,p.title
  from public.training_plan_versions v
  join public.training_plans p on p.id=v.plan_id and p.user_id=v.user_id
  where v.user_id=auth.uid() and v.status='active'
  limit 1
), workouts as (
  select w.*,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'order',e.exercise_order,'name',e.display_name_snapshot,
      'set_count',e.set_count,'rep_min',e.rep_min,'rep_max',e.rep_max,
      'target_rpe',e.target_rpe,'rest_seconds',e.rest_seconds,'notes',e.notes,
      'target_load_kg',e.target_load_kg
    ) order by e.exercise_order)
    from public.planned_exercises e
    where e.planned_workout_id=w.id and e.user_id=auth.uid()),'[]'::jsonb) exercises
  from public.planned_workouts w join active_version v on v.id=w.plan_version_id
  where w.user_id=auth.uid()
), completed as (
  select s.id,s.planned_workout_id,s.local_date,s.duration_seconds,
    s.session_energy,s.session_effort,s.notes,s.completed_at,w.name
  from public.workout_sessions s
  join workouts w on w.id=s.planned_workout_id
  where s.user_id=auth.uid() and s.state='completed'
    and s.local_date >= current_date-greatest(7,least(period_days,365))+1
), progression as (
  select e.display_name_snapshot exercise,
    count(distinct s.id)::integer sessions,
    max(es.load_kg) filter(where es.completed) best_load_kg,
    max(es.repetitions) filter(where es.completed) best_repetitions,
    max(s.local_date) latest_date
  from public.workout_sessions s
  join public.exercise_performances ep on ep.workout_session_id=s.id
    and ep.user_id=s.user_id and ep.status='performed'
  join public.planned_exercises e on e.id=ep.planned_exercise_id
    and e.user_id=ep.user_id
  join public.exercise_sets es on es.exercise_performance_id=ep.id
    and es.user_id=ep.user_id
  where s.user_id=auth.uid() and s.state='completed' and es.completed
    and s.local_date >= current_date-greatest(7,least(period_days,365))+1
  group by e.display_name_snapshot
), latest_computed as (
  select dcm.scores_jsonb->'acwr' as acwr,
         dcm.scores_jsonb->'training_monotony' as monotony,
         dcm.scores_jsonb->'daily_strain' as today_strain
  from public.daily_computed_metrics dcm
  where dcm.user_id=auth.uid()
    and dcm.local_date=current_date
  order by dcm.computed_at desc
  limit 1
)
select jsonb_build_object(
  'schema_version','1.5','period_days',greatest(7,least(period_days,365)),
  'active_plan',(select jsonb_build_object(
    'id',id,'plan_id',plan_id,'title',title,'version_number',version_number,
    'block_weeks',block_weeks,'sessions_per_week',sessions_per_week,
    'rationale',rationale) from active_version),
  'workouts',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'order',workout_order,'weekday',preferred_weekday,'name',name,
    'objective',objective,'estimated_minutes',estimated_minutes,
    'warm_up',warm_up_guidance,'cooldown_cardio',cool_down_guidance,
    'exercises',exercises) order by workout_order) from workouts),'[]'::jsonb),
  'today_workout',private.planned_workout_for_date(auth.uid(),current_date),
  'recent_sessions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'workout_id',planned_workout_id,'name',name,'local_date',local_date,
    'duration_seconds',duration_seconds,'effort',session_effort,'energy',session_energy
  ) order by local_date desc) from (select * from completed order by local_date desc limit 12) r),'[]'::jsonb),
  'adherence',jsonb_build_object(
    'completed_sessions',(select count(*) from completed),
    'planned_sessions',coalesce((select sessions_per_week from active_version),0)
      * greatest(1,ceil(greatest(7,least(period_days,365))/7.0)::integer)),
  'progression',coalesce((select jsonb_agg(jsonb_build_object(
    'exercise',exercise,'sessions',sessions,'best_load_kg',best_load_kg,
    'best_repetitions',best_repetitions,'latest_date',latest_date
  ) order by latest_date desc) from progression),'[]'::jsonb),
  'completed_day_set',coalesce(
    (select jsonb_agg(distinct local_date) from completed),'[]'::jsonb),
  'computed',(select jsonb_build_object(
    'acwr',acwr,'training_monotony',monotony,'today_strain',today_strain
  ) from latest_computed)
);
$$;

create or replace function public.get_my_daily_brief(
  target_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
volatile
as $$
declare
  v_user_id uuid := auth.uid();
  v_timezone text;
  v_metrics jsonb;
begin
  if v_user_id is null then
    return jsonb_build_object('schema_version', '1.6',
                              'local_date', target_date);
  end if;

  select coalesce(dhs.timezone, 'UTC') into v_timezone
  from public.daily_health_summaries dhs
  where dhs.user_id = v_user_id
    and dhs.source_scope = 'healthkit'
  order by dhs.local_date desc
  limit 1;

  begin
    v_metrics := public.compute_daily_metrics(
      v_user_id, target_date, v_timezone
    );
  exception when others then
    v_metrics := null;
  end;

  return jsonb_build_object(
    'schema_version', '1.6',
    'local_date', target_date,
    'today_workout', private.planned_workout_for_date(v_user_id, target_date),
    'next_meal', (
      select item
      from (
        select public.get_my_nutrition_schedule(target_date) value
      ) n,
      jsonb_array_elements(value->'items') item
      where item->>'status' in ('due', 'upcoming', 'optional')
      order by (item->>'order')::integer
      limit 1
    ),
    'check_in', (
      select to_jsonb(c) - 'user_id' - 'note' - 'idempotency_key'
      from public.daily_check_ins c
      where c.user_id = v_user_id
        and c.local_date = target_date
        and c.superseded_at is null
      limit 1
    ),
    'health', (
      select jsonb_build_object(
        'local_date', d.local_date,
        'last_synced_at', d.last_synced_at,
        'present_types', d.present_types,
        'completeness', d.completeness
      )
      from public.daily_health_summaries d
      where d.user_id = v_user_id
        and d.local_date <= target_date
        and d.local_date >= target_date - 31
      order by d.local_date desc, d.last_synced_at desc
      limit 1
    ),
    'nutrition', public.get_my_daily_nutrition(target_date),
    'computed', v_metrics,
    'latest_decision', (
      select jsonb_build_object(
        'id', cd.id,
        'final_decision', cd.head_coach->>'final_decision',
        'reason', cd.head_coach->>'reason',
        'confidence', cd.confidence,
        'created_at', cd.created_at,
        'evidence', cd.evidence,
        'missing_data', cd.missing_data
      )
      from public.coach_decisions cd
      where cd.user_id = v_user_id
      order by cd.created_at desc
      limit 1
    )
  );
end;
$$;

-- Coach context ---------------------------------------------------------------

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
  -- equipment, the movement patterns they asked to avoid, and (coach intake)
  -- how long they have trained and their focus and strong muscles. Equipment
  -- is shown only for profiles written by that approval.
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
        'equipment_note', p.equipment_note,
        'training_years', p.training_years,
        'priority_muscles', case when cardinality(p.priority_muscles) > 0
          then to_jsonb(p.priority_muscles) end,
        'strong_muscles', case when cardinality(p.strong_muscles) > 0
          then to_jsonb(p.strong_muscles) end))
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

-- Follow-up questions ----------------------------------------------------------

create function private.is_valid_follow_up_questions(questions jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(questions) = 'array'
    and jsonb_array_length(questions) <= 3
    and not exists (
      select 1 from jsonb_array_elements(questions) item
      where not (
        jsonb_typeof(item) = 'object'
        and coalesce(item ->> 'category' in ('split_history','recovery_between_sessions',
          'stalled_lift','exercise_preference','schedule_flexibility','nutrition_routine'), false)
        and private.jsonb_text_between(item -> 'question', 1, 160)
        and jsonb_typeof(item -> 'choices') = 'array'
        and jsonb_array_length(item -> 'choices') <= 4
        and not exists (
          select 1 from jsonb_array_elements(item -> 'choices') choice
          where not private.jsonb_text_between(choice, 1, 40)
        )
      )
    );
$$;
revoke all on function private.is_valid_follow_up_questions(jsonb) from public, anon, authenticated;

create table public.onboarding_questions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  questions_hash text not null check (questions_hash ~ '^[0-9a-f]{64}$'),
  questions jsonb not null check (private.is_valid_follow_up_questions(questions)),
  skipped_reason text check (length(skipped_reason) between 1 and 80),
  metadata jsonb check (private.is_valid_generation_metadata(metadata)),
  created_at timestamptz not null default now(),
  unique (user_id, questions_hash)
);
alter table public.onboarding_questions enable row level security;
alter table public.onboarding_questions force row level security;
create policy onboarding_questions_own_read on public.onboarding_questions
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.onboarding_questions from anon, authenticated;
grant select on public.onboarding_questions to authenticated;

-- Called by the onboarding-plan function with the service role. A second
-- request for the same answers gets the questions the first one stored.
create function public.store_onboarding_questions(
  target_user_id uuid,
  target_questions_hash text,
  target_questions jsonb,
  target_skipped_reason text,
  target_metadata jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  stored public.onboarding_questions%rowtype;
begin
  insert into public.onboarding_questions(
    user_id, questions_hash, questions, skipped_reason, metadata
  ) values (
    target_user_id, target_questions_hash, target_questions,
    nullif(target_skipped_reason, ''), target_metadata
  )
  on conflict (user_id, questions_hash) do nothing
  returning * into stored;
  if found then
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (target_user_id, 'onboarding.questions.generated', 'onboarding_questions', stored.id,
      'succeeded', jsonb_strip_nulls(jsonb_build_object(
        'questions', jsonb_array_length(stored.questions),
        'skipped_reason', stored.skipped_reason)) || coalesce(stored.metadata, '{}'::jsonb));
  else
    select * into stored from public.onboarding_questions
      where user_id = target_user_id and questions_hash = target_questions_hash;
  end if;
  return jsonb_build_object('questions', stored.questions,
    'skipped_reason', stored.skipped_reason, 'metadata', stored.metadata);
end $$;
revoke all on function public.store_onboarding_questions(uuid, text, jsonb, text, jsonb)
from public, anon, authenticated;
grant execute on function public.store_onboarding_questions(uuid, text, jsonb, text, jsonb)
to service_role;

-- Apple Health history -----------------------------------------------------------

-- One row per completed calendar month, computed on the device. Coverage is
-- kept with each value (nights of sleep, weigh-in days, days with any data,
-- the first and last date with data), so the server decides what counts.
create table public.health_history_months (
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  workouts smallint not null check (workouts between 0 and 400),
  strength_workouts smallint not null check (strength_workouts between 0 and workouts),
  workout_minutes integer not null check (workout_minutes between 0 and 44640),
  sleep_nights smallint not null check (sleep_nights between 0 and 31),
  sleep_minutes_avg smallint check (sleep_minutes_avg between 1 and 1440),
  weight_days smallint not null check (weight_days between 0 and 31),
  weight_kg_avg numeric(5,1) check (weight_kg_avg between 25 and 350),
  data_days smallint not null check (data_days between 0 and 31),
  first_data_date date,
  last_data_date date,
  synced_at timestamptz not null default now(),
  primary key (user_id, month),
  check ((sleep_minutes_avg is null) = (sleep_nights = 0)),
  check ((weight_kg_avg is null) = (weight_days = 0)),
  check ((first_data_date is null) = (last_data_date is null)),
  check (first_data_date is null or (
    first_data_date >= month and last_data_date >= first_data_date
    and last_data_date < (month + interval '1 month')::date))
);
alter table public.health_history_months enable row level security;
alter table public.health_history_months force row level security;
create policy health_history_months_own_read on public.health_history_months
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.health_history_months from anon, authenticated;
grant select on public.health_history_months to authenticated;

-- Saves the athlete's monthly totals: only completed months in the last 12,
-- by the athlete's own calendar (user_accounts.timezone).
create function public.save_health_history(months jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  this_month date;
  row_value jsonb;
  saved integer := 0;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(months) <> 'array' or jsonb_array_length(months) > 12 then
    raise exception 'months must be a list of at most 12' using errcode = '22023';
  end if;
  this_month := date_trunc('month', private.local_date_for(auth.uid()))::date;
  for row_value in select value from jsonb_array_elements(months) loop
    if jsonb_typeof(row_value) <> 'object'
      or (row_value ->> 'month') !~ '^\d{4}-\d{2}-01$'
      or (row_value ->> 'month')::date >= this_month
      or (row_value ->> 'month')::date < (this_month - interval '12 months')::date then
      raise exception 'only completed months of the last year' using errcode = '22023';
    end if;
    insert into public.health_history_months(
      user_id, month, workouts, strength_workouts, workout_minutes, sleep_nights,
      sleep_minutes_avg, weight_days, weight_kg_avg, data_days, first_data_date, last_data_date
    ) values (
      auth.uid(), (row_value ->> 'month')::date,
      (row_value ->> 'workouts')::smallint, (row_value ->> 'strength_workouts')::smallint,
      (row_value ->> 'workout_minutes')::integer, (row_value ->> 'sleep_nights')::smallint,
      (row_value ->> 'sleep_minutes_avg')::smallint, (row_value ->> 'weight_days')::smallint,
      (row_value ->> 'weight_kg_avg')::numeric, (row_value ->> 'data_days')::smallint,
      (row_value ->> 'first_data_date')::date, (row_value ->> 'last_data_date')::date
    )
    on conflict (user_id, month) do update set
      workouts = excluded.workouts,
      strength_workouts = excluded.strength_workouts,
      workout_minutes = excluded.workout_minutes,
      sleep_nights = excluded.sleep_nights,
      sleep_minutes_avg = excluded.sleep_minutes_avg,
      weight_days = excluded.weight_days,
      weight_kg_avg = excluded.weight_kg_avg,
      data_days = excluded.data_days,
      first_data_date = excluded.first_data_date,
      last_data_date = excluded.last_data_date,
      synced_at = now();
    saved := saved + 1;
  end loop;
  return jsonb_build_object('schema_version', '1.0', 'saved', saved);
end $$;
revoke all on function public.save_health_history(jsonb) from public, anon;
grant execute on function public.save_health_history(jsonb) to authenticated;

-- AI usage ------------------------------------------------------------------------

alter table public.ai_usage_events drop constraint ai_usage_events_purpose_check;
alter table public.ai_usage_events add constraint ai_usage_events_purpose_check
  check (purpose in ('meal_vision','progress_vision','onboarding_plan','onboarding_questions'));
alter table public.ai_usage_events drop constraint ai_usage_events_model_check;
alter table public.ai_usage_events add constraint ai_usage_events_model_check check (
  (purpose not in ('onboarding_plan','onboarding_questions') and model in
    ('gemini-3.5-flash','qwen/qwen3.6-27b','qwen/qwen3.8-27b','deepseek-v4-flash'))
  or (purpose in ('onboarding_plan','onboarding_questions') and length(model) between 1 and 100)
);

create or replace function public.record_ai_usage_event(
  target_user_id uuid,run_purpose text,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric,run_latency_ms integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare event_id uuid;
begin
  if run_purpose in ('onboarding_plan','onboarding_questions') then
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
    ('daily_coaching','coach_chat','meal_vision','onboarding_plan','onboarding_questions') and created_at>=date_trunc('day',now()))
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
    count(*) filter(where purpose in ('daily_coaching','coach_chat','meal_vision','onboarding_plan','onboarding_questions')
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
