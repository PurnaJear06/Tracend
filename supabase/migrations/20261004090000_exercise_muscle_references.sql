-- Reviewed muscles for planned exercise names that are not catalog entries.
--
-- Plans approved before the exercise catalog name their exercises freely
-- ("Pull-Ups or Lat Pulldown", "Reverse Pec Deck"), so most carry no slug and
-- the Train muscle map had nothing to show. The catalog stays unchanged: it is
-- also the list an onboarding plan may choose from (AI_SAFETY_SPEC §11), and
-- linking a name to a different catalog exercise would merge their history.
-- Instead, each name below was reviewed by hand and given its primary muscle
-- groups in the catalog's own vocabulary. The training hub reads a planned
-- exercise's muscles from its catalog entry when it has one, otherwise from
-- this list by the exercise history key (lowercased, trimmed, spaces
-- collapsed). A name on neither list has no muscles; nothing is inferred at
-- run time. Adding a name means adding a reviewed row in a migration.

create table public.exercise_muscle_references (
  name_key text primary key,
  name text not null check (length(name) between 1 and 120),
  primary_muscles text[] not null check (
    cardinality(primary_muscles) between 1 and 4
    and primary_muscles <@ array['quads','glutes','hamstrings','chest','back','shoulders',
      'biceps','triceps','core','calves']::text[]),
  created_at timestamptz not null default now(),
  check (name_key = private.exercise_name_key(name))
);

alter table public.exercise_muscle_references enable row level security;
alter table public.exercise_muscle_references force row level security;
revoke all on public.exercise_muscle_references from public, anon, authenticated;

insert into public.exercise_muscle_references(name_key, name, primary_muscles)
select private.exercise_name_key(r.name), r.name, r.muscles
from (values
  ('Behind-Body Cable Lateral Raise', array['shoulders']),
  ('Bulgarian Split Squat', array['quads','glutes']),
  ('Cable Crunch or Hanging Knee Raise', array['core']),
  ('Chest-Focused Dips or Decline Machine Press', array['chest','triceps']),
  ('Chest-Supported Row', array['back','biceps']),
  ('Cross-Body Cable Triceps Extension', array['triceps']),
  ('Decline Machine Press or Chest-Focused Dips', array['chest','triceps']),
  ('EZ-Bar Curl', array['biceps']),
  ('Flat Machine Press or Barbell Bench', array['chest','triceps']),
  ('Hack Squat or High-Bar Squat', array['quads','glutes']),
  ('Hammer Curl', array['biceps']),
  ('High-to-Low Cable Fly', array['chest']),
  ('Incline Cable Fly or Pec Deck', array['chest']),
  ('Incline DB Press', array['chest','shoulders']),
  ('Incline Machine Press', array['chest','shoulders']),
  ('Lean-Away Cable Lateral Raise', array['shoulders']),
  ('Leg Press — Medium Stance', array['quads','glutes']),
  ('Leg Press — Quad Focus', array['quads','glutes']),
  ('Machine Lateral Raise', array['shoulders']),
  ('Neutral-Grip or Wide-Grip Lat Pulldown', array['back','biceps']),
  ('One-Arm Cable Lat Pulldown', array['back','biceps']),
  ('Overhead Rope Triceps Extension', array['triceps']),
  ('Plank or Cable Crunch', array['core']),
  ('Pull-Ups or Lat Pulldown', array['back','biceps']),
  ('Push-Ups', array['chest','triceps']),
  ('Rear Delt Cable Fly', array['shoulders']),
  ('Reverse Lunge or Bulgarian Split Squat', array['quads','glutes']),
  ('Reverse Pec Deck', array['shoulders']),
  ('Romanian Deadlift', array['hamstrings','glutes']),
  ('Rope Pushdown', array['triceps']),
  ('Seated DB or Machine Shoulder Press', array['shoulders','triceps']),
  ('Seated Leg Curl', array['hamstrings']),
  ('Seated or Lying Leg Curl', array['hamstrings']),
  ('Straight-Arm Pulldown', array['back'])
) as r(name, muscles);

-- The hub: muscles from the catalog entry, else from the reviewed list.
create or replace function public.get_my_training_hub(period_days integer default 28)
returns jsonb language sql security definer set search_path='' stable as $$
with active_version as (
  select v.id,v.plan_id,v.version_number,v.block_weeks,v.sessions_per_week,
    v.rationale,p.title,v.approved_at,v.effective_date,
    nullif(btrim(v.prescription->>'progression'),'') progression_rule
  from public.training_plan_versions v
  join public.training_plans p on p.id=v.plan_id and p.user_id=v.user_id
  where v.user_id=auth.uid() and v.status='active'
  limit 1
), athlete_zone as (
  select coalesce((select a.timezone from public.user_accounts a
    join pg_catalog.pg_timezone_names z on z.name=a.timezone
    where a.id=auth.uid()),'UTC') tz
), workouts as (
  select w.*,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'order',e.exercise_order,'name',e.display_name_snapshot,
      'set_count',e.set_count,'rep_min',e.rep_min,'rep_max',e.rep_max,
      'target_rpe',e.target_rpe,'rest_seconds',e.rest_seconds,'notes',e.notes,
      'target_load_kg',e.target_load_kg,'exercise_slug',e.exercise_slug,
      'primary_muscles',coalesce(to_jsonb(c.primary_muscles),to_jsonb(r.primary_muscles),'[]'::jsonb)
    ) order by e.exercise_order)
    from public.planned_exercises e
    left join public.exercise_catalog c on c.slug=e.exercise_slug
    left join public.exercise_muscle_references r on e.exercise_slug is null
      and r.name_key=private.exercise_name_key(e.display_name_snapshot)
    where e.planned_workout_id=w.id and e.user_id=auth.uid()),'[]'::jsonb) exercises
  from public.planned_workouts w join active_version v on v.id=w.plan_version_id
  where w.user_id=auth.uid()
), completed as (
  select s.id,s.planned_workout_id,s.local_date,s.duration_seconds,
    s.session_energy,s.session_effort,s.notes,s.completed_at,w.name,
    s.completion_source,s.session_effort_source
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
  'schema_version','1.6','period_days',greatest(7,least(period_days,365)),
  'local_today',private.local_date_for(auth.uid()),
  'active_plan',(select jsonb_build_object(
    'id',id,'plan_id',plan_id,'title',title,'version_number',version_number,
    'block_weeks',block_weeks,'sessions_per_week',sessions_per_week,
    'rationale',rationale,
    'effective_date',coalesce(effective_date,
      (approved_at at time zone (select tz from athlete_zone))::date),
    'approved_on',(approved_at at time zone (select tz from athlete_zone))::date,
    'progression_rule',progression_rule) from active_version),
  'workouts',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'order',workout_order,'weekday',preferred_weekday,'name',name,
    'objective',objective,'estimated_minutes',estimated_minutes,
    'warm_up',warm_up_guidance,'cooldown_cardio',cool_down_guidance,
    'exercises',exercises) order by workout_order) from workouts),'[]'::jsonb),
  'today_workout',private.planned_workout_for_date(auth.uid(),current_date),
  'recent_sessions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'workout_id',planned_workout_id,'name',name,'local_date',local_date,
    'duration_seconds',duration_seconds,'effort',session_effort,'energy',session_energy,
    'completion_source',completion_source,'effort_source',session_effort_source
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
  ) from latest_computed),
  'daily_load',private.daily_load(auth.uid(),private.local_date_for(auth.uid()))
);
$$;
