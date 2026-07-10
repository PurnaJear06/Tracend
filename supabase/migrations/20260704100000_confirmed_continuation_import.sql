alter table public.body_measurements
  add column superseded_at timestamptz,
  add column correction_reason text check (
    correction_reason is null or length(correction_reason) between 1 and 240
  );

create or replace function public.get_my_progress_summary()
returns jsonb language sql security definer set search_path='' stable as $$
with ordered as (
  select measured_on,weight_kg,waist_cm,
   row_number() over(order by measured_on,created_at) ascending_rank,
   row_number() over(order by measured_on desc,created_at desc) descending_rank
  from public.body_measurements
  where user_id=auth.uid() and superseded_at is null
), stats as (
 select count(distinct measured_on)::integer observation_days
 from public.body_measurements
 where user_id=auth.uid() and superseded_at is null
), valueset as (
 select stats.observation_days observation_count,
  max(weight_kg) filter(where descending_rank=1) current_weight_kg,
  max(weight_kg) filter(where ascending_rank=1) first_weight_kg,
  max(waist_cm) filter(where descending_rank=1) current_waist_cm,
  max(waist_cm) filter(where ascending_rank=1 and waist_cm is not null) first_waist_cm,
  min(measured_on) first_date,max(measured_on) latest_date
 from stats left join ordered on true group by stats.observation_days
)
select jsonb_build_object(
 'schema_version','1.0','observation_count',coalesce(observation_count,0),
 'current_weight_kg',current_weight_kg,
 'weight_change_kg',case when observation_count>=2 then current_weight_kg-first_weight_kg end,
 'current_waist_cm',current_waist_cm,
 'waist_change_cm',case when observation_count>=2 and current_waist_cm is not null and first_waist_cm is not null then current_waist_cm-first_waist_cm end,
 'first_date',first_date,'latest_date',latest_date,
 'trend_status',case when coalesce(observation_count,0)<2 then 'not_enough_data' else 'available' end,
 'weekly_review_status',case when coalesce(observation_count,0)<2 then 'gather_data' else 'ready' end)
from valueset;
$$;

create function public.import_confirmed_continuation(
  target_user_id uuid,
  profile_payload jsonb,
  goal_payload jsonb,
  training_payload jsonb,
  nutrition_payload jsonb,
  measurements_payload jsonb,
  supersede_measurement_ids uuid[] default '{}'
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  new_goal_id uuid;
  new_plan_id uuid;
  new_plan_version_id uuid;
  new_target_id uuid;
  workout_payload jsonb;
  exercise_payload jsonb;
  new_workout_id uuid;
  workout_count integer := 0;
  exercise_count integer := 0;
  measurement_count integer := 0;
  next_target_version integer;
begin
  if target_user_id is null or not exists(
    select 1 from public.user_accounts where id=target_user_id
  ) then raise exception 'account not found' using errcode='P0002'; end if;
  if jsonb_typeof(profile_payload)<>'object'
    or profile_payload->>'experience_level' not in ('beginner','intermediate','advanced')
    or (profile_payload->>'height_cm')::numeric not between 100 and 250
    or (profile_payload->>'session_minutes')::integer not between 15 and 180
    or jsonb_typeof(profile_payload->'training_days')<>'array'
    or jsonb_array_length(profile_payload->'training_days') not between 1 and 7
  then raise exception 'invalid profile import' using errcode='22023'; end if;
  if jsonb_typeof(goal_payload)<>'object'
    or goal_payload->>'goal_type' not in ('fat_loss','muscle_gain','recomposition','strength','aesthetic')
    or jsonb_typeof(goal_payload->'details')<>'object'
  then raise exception 'invalid goal import' using errcode='22023'; end if;
  if jsonb_typeof(training_payload)<>'object'
    or length(training_payload->>'title') not between 1 and 120
    or (training_payload->>'block_weeks')::integer not between 1 and 24
    or jsonb_typeof(training_payload->'weekly_structure')<>'array'
    or jsonb_array_length(training_payload->'weekly_structure') not between 1 and 7
    or length(training_payload->>'rationale') not between 1 and 2000
  then raise exception 'invalid training import' using errcode='22023'; end if;
  if jsonb_typeof(nutrition_payload)<>'object'
    or (nutrition_payload->>'calories')::integer not between 1000 and 6000
    or (nutrition_payload->>'protein_g')::integer not between 30 and 400
    or (nutrition_payload->>'carbohydrate_g')::integer not between 20 and 1000
    or (nutrition_payload->>'fat_g')::integer not between 20 and 300
    or length(nutrition_payload->>'rationale') not between 1 and 2000
  then raise exception 'invalid nutrition import' using errcode='22023'; end if;
  if jsonb_typeof(measurements_payload)<>'array'
    or jsonb_array_length(measurements_payload) not between 1 and 20
  then raise exception 'invalid measurements import' using errcode='22023'; end if;

  update public.user_profiles set
    experience_level=(profile_payload->>'experience_level')::public.experience_level,
    height_cm=(profile_payload->>'height_cm')::numeric,
    training_days=array(
      select value::smallint from jsonb_array_elements_text(profile_payload->'training_days')
    ),
    session_minutes=(profile_payload->>'session_minutes')::smallint,
    updated_at=statement_timestamp(),row_version=row_version+1
  where user_id=target_user_id;

  update public.user_goals set status='superseded'
  where user_id=target_user_id and status='active';
  insert into public.user_goals(
    user_id,goal_type,priority,status,details,activated_at)
  values(
    target_user_id,(goal_payload->>'goal_type')::public.goal_type,1,'active',
    goal_payload->'details',statement_timestamp())
  returning id into new_goal_id;

  update public.training_plan_versions set status='superseded'
  where user_id=target_user_id and status='active';
  update public.nutrition_target_sets set status='superseded'
  where user_id=target_user_id and status='active';

  insert into public.training_plans(user_id,goal_id,title,source)
  values(target_user_id,new_goal_id,training_payload->>'title','imported')
  returning id into new_plan_id;
  insert into public.training_plan_versions(
    user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
    prescription,rationale,approved_at,effective_date)
  values(
    target_user_id,new_plan_id,1,'active',
    (training_payload->>'block_weeks')::smallint,
    jsonb_array_length(training_payload->'weekly_structure')::smallint,
    training_payload-'weekly_structure'-'title'-'block_weeks'-'rationale',
    training_payload->>'rationale',statement_timestamp(),
    (training_payload->>'effective_date')::date)
  returning id into new_plan_version_id;

  for workout_payload in select value from jsonb_array_elements(
    training_payload->'weekly_structure'
  ) loop
    if (workout_payload->>'workout_order')::integer not between 1 and 7
      or length(workout_payload->>'name') not between 1 and 120
      or length(workout_payload->>'objective') not between 1 and 500
      or (workout_payload->>'estimated_minutes')::integer not between 15 and 180
      or jsonb_typeof(workout_payload->'exercises')<>'array'
      or jsonb_array_length(workout_payload->'exercises') not between 1 and 30
    then raise exception 'invalid workout import' using errcode='22023'; end if;
    insert into public.planned_workouts(
      user_id,plan_version_id,workout_order,name,objective,preferred_weekday,
      estimated_minutes,warm_up_guidance,cool_down_guidance)
    values(
      target_user_id,new_plan_version_id,
      (workout_payload->>'workout_order')::smallint,workout_payload->>'name',
      workout_payload->>'objective',(workout_payload->>'preferred_weekday')::smallint,
      (workout_payload->>'estimated_minutes')::smallint,
      workout_payload->>'warm_up_guidance',workout_payload->>'cool_down_guidance')
    returning id into new_workout_id;
    workout_count := workout_count + 1;
    for exercise_payload in select value from jsonb_array_elements(
      workout_payload->'exercises'
    ) loop
      if (exercise_payload->>'exercise_order')::integer not between 1 and 30
        or length(exercise_payload->>'name') not between 1 and 120
        or (exercise_payload->>'sets')::integer not between 1 and 12
        or (exercise_payload->>'rep_min')::integer not between 1 and 100
        or (exercise_payload->>'rep_max')::integer not between
          (exercise_payload->>'rep_min')::integer and 100
        or (exercise_payload->>'target_rpe')::numeric not between 1 and 10
        or (exercise_payload->>'rest_seconds')::integer not between 15 and 600
      then raise exception 'invalid exercise import' using errcode='22023'; end if;
      insert into public.planned_exercises(
        user_id,planned_workout_id,exercise_order,display_name_snapshot,
        set_count,rep_min,rep_max,target_rpe,rest_seconds,notes)
      values(
        target_user_id,new_workout_id,
        (exercise_payload->>'exercise_order')::smallint,exercise_payload->>'name',
        (exercise_payload->>'sets')::smallint,(exercise_payload->>'rep_min')::smallint,
        (exercise_payload->>'rep_max')::smallint,(exercise_payload->>'target_rpe')::numeric,
        (exercise_payload->>'rest_seconds')::smallint,
        coalesce(exercise_payload->>'notes',''));
      exercise_count := exercise_count + 1;
    end loop;
  end loop;

  select coalesce(max(version_number),0)+1 into next_target_version
  from public.nutrition_target_sets where user_id=target_user_id;
  insert into public.nutrition_target_sets(
    user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
    rationale,approved_at,effective_date)
  values(
    target_user_id,next_target_version,'active',
    (nutrition_payload->>'calories')::integer,
    (nutrition_payload->>'protein_g')::integer,
    (nutrition_payload->>'carbohydrate_g')::integer,
    (nutrition_payload->>'fat_g')::integer,nutrition_payload->>'rationale',
    statement_timestamp(),(nutrition_payload->>'effective_date')::date)
  returning id into new_target_id;

  update public.body_measurements set
    superseded_at=statement_timestamp(),
    correction_reason='Replaced owner-confirmed setup fixture'
  where user_id=target_user_id and id=any(supersede_measurement_ids)
    and superseded_at is null;
  for exercise_payload in select value from jsonb_array_elements(measurements_payload) loop
    if (exercise_payload->>'measured_on')::date > current_date
      or (exercise_payload->>'weight_kg')::numeric not between 25 and 350
    then raise exception 'invalid measurement import' using errcode='22023'; end if;
    insert into public.body_measurements(
      user_id,measured_on,source,weight_kg,protocol_version)
    values(
      target_user_id,(exercise_payload->>'measured_on')::date,'manual',
      (exercise_payload->>'weight_kg')::numeric,'owner-import-v1');
    measurement_count := measurement_count + 1;
  end loop;

  insert into public.audit_events(
    user_id,action_code,target_type,target_id,outcome,metadata)
  values(
    target_user_id,'owner.confirmed_context_imported','training_plan_version',
    new_plan_version_id,'succeeded',jsonb_build_object(
      'schema_version','1.0','workout_count',workout_count,
      'exercise_count',exercise_count,'measurement_count',measurement_count,
      'nutrition_target_id',new_target_id));
  return jsonb_build_object(
    'plan_version_id',new_plan_version_id,'nutrition_target_id',new_target_id,
    'goal_id',new_goal_id,'workout_count',workout_count,
    'exercise_count',exercise_count,'measurement_count',measurement_count);
end $$;

revoke all on function public.import_confirmed_continuation(
  uuid,jsonb,jsonb,jsonb,jsonb,jsonb,uuid[])
from public,anon,authenticated;
grant execute on function public.import_confirmed_continuation(
  uuid,jsonb,jsonb,jsonb,jsonb,jsonb,uuid[])
to service_role;

revoke all on function public.get_my_progress_summary()
from public,anon,authenticated;
grant execute on function public.get_my_progress_summary() to authenticated;
