-- Advanced experience level and four advanced staple lifts in the exercise catalog.
--
-- Additive and safe for the deployed app and Edge Functions:
--   * The catalog's level check is widened, never narrowed: 'advanced' joins 'beginner' and
--     'intermediate'. public.experience_level (user_profiles.experience_level) already has
--     'advanced', so no other constraint changes.
--   * Four new rows are inserted, all level 'advanced', so an advanced athlete is offered them and
--     athletes of the levels below are not (the Edge Function filters by level). A build that
--     still reads the old two-level filter would offer them to intermediates until the new
--     function deploys, which is harmless: they are valid catalog exercises.
--   * Seven existing rows gain links to the new rows (a progression, a substitute); no link is
--     removed or renamed. The links are mirrored: a progression lists its regression, a
--     substitute lists its substitute.
-- The rows mirror supabase/functions/_shared/onboarding/catalog.ts and catalog_v2.ts;
-- catalog_test.ts and catalog_v2_test.ts keep them equal. Joint stress ratings are in-house
-- (_shared/training/standard/joint_stress.ts).
--
-- Also in this migration:
--   * exercise_catalog.added_load: the load logged for the exercise is weight added to the body, so
--     progression treats no load and 0 as "none added" and the first step is 2.5 kg (weighted
--     pull-up). Default false, so no other exercise changes.
--   * private.next_session_targets: a lift planned more than once with different rep ranges (an
--     advanced plan's heavy and light days) keeps one history per range; a plan without such a
--     repeat produces the targets it did before. Because history is matched by range, an athlete
--     who moves from an intermediate plan (one range per lift) to an advanced plan (a lift on a
--     heavy and a light day) has no target for a split lift's day until that day has been logged
--     once under its own range; the lift's earlier sets, logged in the other range, are not read
--     as the new day's history. That day keeps the plan's prescription: a missing target lowers
--     confidence and is never filled from another day's sets.
--   * get_coach_plan_state_v1 1.2 adds `experience`.
--   * get_coach_proposal_inputs_v1 1.1 adds `planned_exercise_id` to every plan exercise, so a
--     next-session adjustment matches its target on the planned exercise and not on the slug.

do $$
declare
  existing text;
begin
  select conname into existing
  from pg_constraint
  where conrelid = 'public.exercise_catalog'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%level%'
    and pg_get_constraintdef(oid) like '%intermediate%';
  if existing is not null then
    execute format('alter table public.exercise_catalog drop constraint %I', existing);
  end if;
end;
$$;

alter table public.exercise_catalog
  add constraint exercise_catalog_level_check
  check (level in ('beginner','intermediate','advanced'));

insert into public.exercise_catalog(
  slug,name,movement_pattern,primary_muscles,equipment_required,level,is_compound
) values
 ('weighted-pull-up','Weighted pull-up','vertical_pull',array['back','biceps']::text[],array['pull_up_bar','dumbbells']::text[],'advanced',true),
 ('close-grip-bench-press','Close-grip bench press','horizontal_push',array['chest','triceps']::text[],array['barbell','bench']::text[],'advanced',true),
 ('incline-barbell-bench-press','Incline barbell bench press','horizontal_push',array['chest','shoulders']::text[],array['barbell','bench']::text[],'advanced',true),
 ('bulgarian-split-squat','Bulgarian split squat','lunge',array['quads','glutes']::text[],array['dumbbells','bench']::text[],'advanced',true);

-- Catalog v2 columns for the four new rows and the links of the seven rows that point at them.
update public.exercise_catalog c set
  secondary_muscles = v.secondary_muscles,
  knee_stress = v.knee_stress,
  back_stress = v.back_stress,
  shoulder_stress = v.shoulder_stress,
  regressions = v.regressions,
  progressions = v.progressions,
  substitutes = v.substitutes,
  load_step_kg = v.load_step_kg,
  exercise_role = v.exercise_role
from (values
 ('weighted-pull-up','{}'::text[],'low','low','high',array['pull-up','chin-up']::text[],'{}'::text[],array['lat-pulldown']::text[],2.5::numeric,'variation'),
 ('close-grip-bench-press',array['shoulders']::text[],'low','low','high','{}'::text[],'{}'::text[],array['barbell-bench-press','incline-barbell-bench-press']::text[],2.5::numeric,'variation'),
 ('incline-barbell-bench-press',array['triceps']::text[],'low','low','high','{}'::text[],'{}'::text[],array['barbell-bench-press','close-grip-bench-press','incline-dumbbell-press']::text[],2.5::numeric,'variation'),
 ('bulgarian-split-squat',array['hamstrings']::text[],'high','low','low',array['dumbbell-reverse-lunge']::text[],'{}'::text[],array['dumbbell-step-up']::text[],2.5::numeric,'variation'),
 ('dumbbell-reverse-lunge',array['hamstrings']::text[],'moderate','low','low',array['reverse-lunge']::text[],array['barbell-reverse-lunge','bulgarian-split-squat']::text[],array['dumbbell-step-up']::text[],2.5::numeric,null::text),
 ('dumbbell-step-up',array['hamstrings']::text[],'moderate','low','low','{}'::text[],'{}'::text[],array['dumbbell-reverse-lunge','bulgarian-split-squat']::text[],2.5::numeric,null::text),
 ('incline-dumbbell-press',array['triceps']::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['dumbbell-bench-press','incline-barbell-bench-press']::text[],2.5::numeric,'variation'),
 ('barbell-bench-press',array['shoulders']::text[],'low','low','high','{}'::text[],'{}'::text[],array['dumbbell-bench-press','machine-chest-press','close-grip-bench-press','incline-barbell-bench-press']::text[],2.5::numeric,null::text),
 ('pull-up','{}'::text[],'low','low','moderate',array['assisted-pull-up']::text[],array['weighted-pull-up']::text[],array['chin-up','lat-pulldown']::text[],null::numeric,null::text),
 ('chin-up','{}'::text[],'low','low','moderate',array['assisted-pull-up']::text[],array['weighted-pull-up']::text[],array['pull-up','lat-pulldown']::text[],null::numeric,'variation'),
 ('lat-pulldown','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['pull-up','chin-up','assisted-pull-up','band-lat-pulldown','weighted-pull-up']::text[],2.5::numeric,null::text)
) as v(slug, secondary_muscles, knee_stress, back_stress, shoulder_stress, regressions,
  progressions, substitutes, load_step_kg, exercise_role)
where c.slug = v.slug;

-- Every catalog row is still reviewed, and every link still names another catalog exercise.
do $$
begin
  if exists (
    select 1 from public.exercise_catalog
    where knee_stress is null or back_stress is null or shoulder_stress is null
  ) then
    raise exception 'exercise_catalog: a catalog row has no joint stress rating';
  end if;
  if exists (
    select 1
    from public.exercise_catalog c,
      unnest(c.regressions || c.progressions || c.substitutes) link
    where not exists (select 1 from public.exercise_catalog t where t.slug = link)
  ) then
    raise exception 'exercise_catalog: a link names no catalog exercise';
  end if;
end;
$$;

-- Added load and the version of the new rows ------------------------------------------------------

alter table public.exercise_catalog
  add column added_load boolean not null default false;

update public.exercise_catalog set added_load = true where slug = 'weighted-pull-up';

update public.exercise_catalog set catalog_version = 'catalog-v2'
where slug in ('weighted-pull-up', 'close-grip-bench-press', 'incline-barbell-bench-press',
  'bulgarian-split-squat');

-- Progression targets: one history per rep range, and added load -----------------------------------
-- Redefines the function of 20261017140023_progression_targets.sql. Same signature and result
-- shape. Changes: `split_range` in the planned CTE and the performance match; `added_load` in the
-- logged CTE. Everything else is as it was.

create or replace function private.next_session_targets(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
with rules as (
  select private.progression_rules() as r
), today as (
  select private.local_date_for(p_user) as d
), planned as (
  select e.id as planned_exercise_id, w.workout_order, e.exercise_order,
    e.exercise_slug, e.display_name_snapshot as name,
    e.set_count, e.rep_min, e.rep_max, e.target_rpe,
    private.exercise_name_key(e.display_name_snapshot) as name_key,
    private.exercise_name_key(c.name) as catalog_name_key,
    coalesce(e.exercise_slug like 'assisted-%',
      private.exercise_name_key(e.display_name_snapshot) like 'assisted %') as assisted,
    c.load_step_kg as step_kg,
    coalesce(c.added_load, false) as added_load,
    -- The same lift planned more than once with different rep ranges (an advanced plan's heavy
    -- and light days): each range keeps its own history, so a heavy 100 kg x 9 is never read
    -- as a light day's 100 kg x 10.
    e.exercise_slug is not null and exists (
      select 1 from public.planned_exercises o
      join public.planned_workouts ow on ow.id = o.planned_workout_id and ow.user_id = o.user_id
      where ow.plan_version_id = v.id and o.user_id = e.user_id
        and o.exercise_slug = e.exercise_slug
        and (o.rep_min, o.rep_max) is distinct from (e.rep_min, e.rep_max)) as split_range
  from public.training_plan_versions v
  join public.planned_workouts w on w.plan_version_id = v.id and w.user_id = v.user_id
  join public.planned_exercises e on e.planned_workout_id = w.id and e.user_id = w.user_id
  left join public.exercise_catalog c on c.slug = e.exercise_slug
  where v.user_id = p_user and v.status = 'active'
), perf as (
  select pl.planned_exercise_id, pl.assisted, pl.added_load, p.id as performance_id, p.status, p.pain_flag,
    s.local_date, s.completed_at, s.id as session_id
  from planned pl
  join public.exercise_performances p on p.user_id = p_user
  left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
  join public.workout_sessions s on s.id = p.workout_session_id and s.user_id = p.user_id
    and s.state = 'completed'
    and s.local_date >= (select d from today) - (select (r ->> 'lookback_days')::integer from rules)
  where ((pl.exercise_slug is not null and p.exercise_slug = pl.exercise_slug)
    or (pl.exercise_slug is not null and p.exercise_slug is null
        and p.performance_kind = 'prescribed'
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.catalog_name_key)
    or (pl.exercise_slug is null and p.exercise_slug is null
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.name_key))
    -- A lift planned with several ranges counts only the performances logged against a planned
    -- exercise with this range, whichever plan version it came from.
    and (not pl.split_range
      or (pe.rep_min is not distinct from pl.rep_min and pe.rep_max is not distinct from pl.rep_max))
), logged as (
  select pf.planned_exercise_id, pf.assisted, pf.session_id, pf.local_date, pf.completed_at,
    pf.pain_flag,
    -- Assisted: the load is machine help and 0 is unassisted, so it is kept. Added load (a weighted
    -- pull-up): the load is the weight added to the body, so no load and 0 both mean none added,
    -- a real starting point for the first step.
    case when pf.assisted then es.load_kg
      when pf.added_load then coalesce(es.load_kg, 0)
      else nullif(es.load_kg, 0) end as load_kg,
    es.repetitions,
    case when es.rir is not null then es.rir::integer
      when es.rpe is not null then greatest(0, least(5, round(10 - es.rpe)::integer)) end as rir
  from perf pf
  join public.exercise_sets es on es.exercise_performance_id = pf.performance_id
    and es.user_id = p_user and es.completed and es.repetitions > 0
  where pf.status <> 'skipped' and (not pf.assisted or es.load_kg is not null)
), topped as (
  -- The top load is the heaviest; for an assisted exercise the least help.
  select l.*, case when l.assisted
      then min(l.load_kg) over (partition by l.planned_exercise_id, l.session_id)
      else max(l.load_kg) over (partition by l.planned_exercise_id, l.session_id) end as top_load
  from logged l
), sessions as (
  select t.planned_exercise_id, t.session_id, t.local_date, t.completed_at, t.top_load,
    count(*)::integer as sets,
    min(t.repetitions)::integer as min_reps,
    sum(t.repetitions)::integer as total_reps,
    min(t.rir) as min_rir,
    count(t.rir) = count(*) as effort_known,
    bool_or(t.pain_flag) as pain
  from topped t
  where t.load_kg is not distinct from t.top_load
  group by t.planned_exercise_id, t.session_id, t.local_date, t.completed_at, t.top_load
), ranked as (
  select s.*, row_number() over (partition by s.planned_exercise_id
    order by s.local_date desc, s.completed_at desc) as rn
  from sessions s
), recent as (
  select r.planned_exercise_id, max(r.local_date) filter (where r.rn = 1) as latest_date,
    max(r.completed_at) filter (where r.rn = 1) as latest_completed_at,
    jsonb_agg(jsonb_build_object(
      'local_date', r.local_date, 'load_kg', r.top_load, 'sets', r.sets,
      'min_reps', r.min_reps, 'total_reps', r.total_reps, 'min_rir', r.min_rir,
      'effort_known', r.effort_known, 'pain', r.pain) order by r.rn) as sess
  from ranked r where r.rn <= 3 group by r.planned_exercise_id
)
select coalesce(jsonb_agg(x.target order by x.workout_order, x.exercise_order), '[]'::jsonb)
from (
  select pl.workout_order, pl.exercise_order,
    jsonb_build_object('planned_exercise_id', pl.planned_exercise_id,
      'exercise_key', coalesce(pl.exercise_slug, pl.name_key), 'name', pl.name)
    || d.decision
    || jsonb_build_object('basis', jsonb_build_object(
      'last_date', rc.latest_date, 'recent', rc.sess)) as target
  from planned pl
  join recent rc on rc.planned_exercise_id = pl.planned_exercise_id
  cross join lateral (
    select private.progression_decision(pl.set_count, pl.rep_min, pl.rep_max, pl.target_rpe,
      pl.step_kg, (select d from today) - rc.latest_date,
      exists (select 1 from perf sk where sk.planned_exercise_id = pl.planned_exercise_id
        and sk.status = 'skipped'
        and (sk.local_date, sk.completed_at) > (rc.latest_date, rc.latest_completed_at)),
      -- (workout_sessions.completed_at is never null for a completed session: a check
      -- constraint ties them, so the row comparisons are never null.)
      -- Pain on a later performance counts even when no set was logged that day.
      exists (select 1 from perf pn where pn.planned_exercise_id = pl.planned_exercise_id
        and pn.pain_flag
        and (pn.local_date, pn.completed_at) > (rc.latest_date, rc.latest_completed_at)),
      pl.assisted,
      rc.sess) as decision
  ) d
  where d.decision is not null
) x;
$$;
revoke all on function private.next_session_targets(uuid) from public, anon, authenticated;

-- Coach plan state 1.2 ----------------------------------------------------------------------------
-- The definition of 20261018190042_coach_schedule.sql plus the athlete's level.

create or replace function public.get_coach_plan_state_v1(p_user_id uuid, p_local_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with active as (
    select v.id as version_id, v.version_number, v.sessions_per_week, p.title, v.ends_on,
      v.restores_version_id
    from public.training_plan_versions v
    join public.training_plans p on p.id = v.plan_id and p.user_id = v.user_id
    where v.user_id = p_user_id and v.status = 'active' limit 1
  )
  select jsonb_build_object(
    'schema_version', '1.2',
    'local_date', p_local_date,
    'weekday', extract(isodow from p_local_date)::integer,
    -- Equipment counts only once the athlete answered the intake that asks for it.
    'equipment', (select case when pr.daily_activity is not null then to_jsonb(pr.equipment) end
      from public.user_profiles pr where pr.user_id = p_user_id),
    'avoid_patterns', (select to_jsonb(pr.avoid_patterns)
      from public.user_profiles pr where pr.user_id = p_user_id),
    -- The athlete's level (beginner, intermediate, advanced; null when never recorded): Coach
    -- offers alternatives from the exercises that level is offered.
    'experience', (select to_jsonb(pr.experience_level)
      from public.user_profiles pr where pr.user_id = p_user_id),
    'plan', (select jsonb_build_object('title', a.title, 'version_number', a.version_number,
      'sessions_per_week', a.sessions_per_week) from active a),
    'sessions', private.coach_plan_sessions(p_user_id, (select a.version_id from active a)),
    -- When the active version is a temporary block, the sessions the athlete returns to after its
    -- last day: the schedule after `ends_on` is these, not the block's.
    'after_block', (select jsonb_build_object('ends_on', a.ends_on,
        'version_number', r.version_number,
        'sessions', private.coach_plan_sessions(p_user_id, r.id))
      from active a join public.training_plan_versions r
        on r.id = a.restores_version_id and r.user_id = p_user_id
      where a.ends_on is not null),
    -- A session finished under an earlier plan version still counts this week: it carries the
    -- workout's name, day and order so it can be matched to the active plan's workouts.
    'completed_this_week', coalesce((select jsonb_agg(jsonb_build_object(
        'planned_workout_id', s.planned_workout_id, 'local_date', s.local_date,
        'name', cw.name, 'weekday', cw.preferred_weekday, 'order', cw.workout_order)
        order by s.local_date)
      from public.workout_sessions s
      join public.planned_workouts cw on cw.id = s.planned_workout_id and cw.user_id = s.user_id
      where s.user_id = p_user_id and s.state = 'completed'
        and s.local_date between p_local_date - (extract(isodow from p_local_date)::integer - 1)
          and p_local_date), '[]'::jsonb),
    -- Yesterday's and today's finished sessions whatever the calendar week, each with the sets
    -- it logged per exercise: the week-ahead schedule needs yesterday on a Monday, and
    -- completed_this_week stops at Monday.
    'recent_completed', coalesce((select jsonb_agg(jsonb_build_object(
        'planned_workout_id', s.planned_workout_id, 'local_date', s.local_date, 'name', cw.name,
        'exercises', private.coach_session_exercises(p_user_id, s.id))
        order by s.local_date)
      from public.workout_sessions s
      join public.planned_workouts cw on cw.id = s.planned_workout_id and cw.user_id = s.user_id
      where s.user_id = p_user_id and s.state = 'completed'
        and s.local_date between p_local_date - 1 and p_local_date), '[]'::jsonb),
    'progression', public.get_progression_summary_v1(p_user_id));
$$;

-- Coach proposal inputs 1.1 ------------------------------------------------------------------------
-- The definition of 20261018120018_coach_proposals.sql plus the planned exercise id on every plan
-- exercise. A lift planned on two days with different rep ranges (an advanced plan's heavy and
-- light days) has one next-session target per planned exercise, so a next-session adjustment must
-- match its target on the planned exercise and not on the lift's slug. Additive: no key is removed
-- or renamed, and the Edge Function reads an older payload without the id as having no target.

create or replace function public.get_coach_proposal_inputs_v1(p_user_id uuid)
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
    'schema_version', '1.1',
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
                'planned_exercise_id', e.id, 'slug', e.exercise_slug, 'name', e.display_name_snapshot,
                'sets', e.set_count,
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
