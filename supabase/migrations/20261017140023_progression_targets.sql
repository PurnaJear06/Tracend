-- B3: next-session targets from the sets actually logged; training hub 1.7.
--
-- 1. private.progression_rules()      the rule numbers, in one place
-- 2. private.progression_decision()   the pure decision for one exercise
-- 3. private.next_session_targets()   the targets for an athlete's active plan
-- 4. public.get_progression_summary_v1(uuid)   service role only, for Coach context
-- 5. public.get_my_training_hub 1.7   adds next_targets; every 1.6 key is unchanged
--
-- The targets are arithmetic on logged sets: weight, reps, reps in reserve and
-- completion. Heart rate is not an input anywhere (D9). The decision applies
-- double progression: reps rise inside the plan's range first, and the load
-- rises by one step of the exercise's loading implement (exercise_catalog.
-- load_step_kg, never more) only when every working set reached the top of the
-- range with at least the planned reps in reserve. A shortfall, a grinding set,
-- pain, a skipped session or time away holds the target or lowers it. A pain flag
-- on a later performance holds the target even when no set was logged that day.
-- An assisted exercise (assisted-* slug or "assisted ..." name) logs machine help
-- as its load, as get_my_exercise_history ranks it: less help is harder and 0 is
-- unassisted, so progressing reduces the help (never below 0) and lowering adds
-- it. An exercise without logged sets gets no target and keeps the plan's
-- prescription.

create function private.progression_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"hold_after_gap_days":14,"lower_after_gap_days":28,"lookback_days":180,"reps_added_per_session":1}'::jsonb;
$$;
revoke all on function private.progression_rules() from public, anon, authenticated;

-- p_sessions: up to three logged sessions of the exercise, latest first. Each is
-- {load_kg, sets, min_reps, total_reps, min_rir, effort_known, pain, local_date}
-- describing the working sets (completed, at the session's top load; for an
-- assisted exercise the least help). p_pain_since: pain was flagged on a later
-- performance of the exercise, even one with no completed set.
-- Returns null without a session, else {action, reason, load_kg, reps, sets, confidence}.
create function private.progression_decision(
  p_set_count integer,
  p_rep_min integer,
  p_rep_max integer,
  p_target_rpe numeric,
  p_step_kg numeric,
  p_gap_days integer,
  p_skipped_since boolean,
  p_pain_since boolean,
  p_assisted boolean,
  p_sessions jsonb
) returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  rules constant jsonb := private.progression_rules();
  s1 jsonb := p_sessions -> 0;
  s2 jsonb := p_sessions -> 1;
  s3 jsonb := p_sessions -> 2;
  v_load numeric := nullif(s1 ->> 'load_kg', '')::numeric;
  v_sets integer := (s1 ->> 'sets')::integer;
  v_min_reps integer := (s1 ->> 'min_reps')::integer;
  v_min_rir integer := nullif(s1 ->> 'min_rir', '')::integer;
  v_step numeric := case when p_step_kg > 0 then p_step_kg end;
  v_rir_target integer := case when p_target_rpe is null then 2
    else greatest(0, least(5, round(10 - p_target_rpe)::integer)) end;
  v_can_lower boolean;
  v_hold_reps integer;
  v_action text;
  v_reason text;
  v_load_out numeric;
  v_reps integer;
  v_lower_load numeric;
begin
  if p_sessions is null or jsonb_typeof(p_sessions) <> 'array'
     or jsonb_array_length(p_sessions) = 0 then
    return null;
  end if;
  -- Assisted: lowering adds help (always possible); otherwise the load must stay above 0.
  v_can_lower := v_load is not null and v_step is not null
    and (coalesce(p_assisted, false) or v_load - v_step > 0);
  v_lower_load := case when coalesce(p_assisted, false) then v_load + v_step else v_load - v_step end;
  v_hold_reps := least(p_rep_max, greatest(p_rep_min, v_min_reps));
  v_load_out := v_load;
  v_reps := v_hold_reps;

  if coalesce((s1 ->> 'pain')::boolean, false) or coalesce(p_pain_since, false) then
    v_action := 'hold'; v_reason := 'pain';
  elsif p_gap_days >= (rules ->> 'lower_after_gap_days')::integer and v_can_lower then
    v_action := 'lower'; v_reason := 'away';
    v_load_out := v_lower_load; v_reps := p_rep_min;
  elsif p_gap_days >= (rules ->> 'hold_after_gap_days')::integer then
    v_action := 'hold'; v_reason := 'away';
  elsif p_skipped_since then
    v_action := 'hold'; v_reason := 'skipped';
  elsif v_min_reps < p_rep_min then
    if s2 is not null and (s2 ->> 'min_reps')::integer < p_rep_min
       and nullif(s2 ->> 'load_kg', '')::numeric is not distinct from v_load and v_can_lower then
      v_action := 'lower'; v_reason := 'below_range';
      v_load_out := v_lower_load; v_reps := p_rep_min;
    else
      v_action := 'hold'; v_reason := 'below_range'; v_reps := p_rep_min;
    end if;
  elsif s3 is not null and v_min_reps < p_rep_max
        and nullif(s2 ->> 'load_kg', '')::numeric is not distinct from v_load
        and nullif(s3 ->> 'load_kg', '')::numeric is not distinct from v_load
        and (s1 ->> 'total_reps')::integer <= (s3 ->> 'total_reps')::integer then
    if v_can_lower then
      v_action := 'lower'; v_reason := 'stall';
      v_load_out := v_lower_load; v_reps := p_rep_min;
    else
      v_action := 'hold'; v_reason := 'stall';
    end if;
  elsif v_sets < p_set_count then
    v_action := 'hold'; v_reason := 'incomplete';
  elsif v_min_rir is not null and v_min_rir < v_rir_target then
    v_action := 'hold'; v_reason := 'effort';
  elsif v_min_reps >= p_rep_max then
    if v_step is not null and v_load is not null and (not coalesce(p_assisted, false) or v_load > 0) then
      v_action := 'add_load'; v_reason := 'top_of_range';
      v_load_out := case when coalesce(p_assisted, false) then greatest(0, v_load - v_step)
        else v_load + v_step end;
      v_reps := p_rep_min;
    else
      v_action := 'hold'; v_reason := 'top_no_step'; v_reps := p_rep_max;
    end if;
  else
    v_action := 'add_reps'; v_reason := 'within_range';
    v_reps := least(p_rep_max, v_min_reps + (rules ->> 'reps_added_per_session')::integer);
  end if;

  return jsonb_build_object(
    'action', v_action, 'reason', v_reason,
    'load_kg', v_load_out, 'reps', v_reps, 'sets', p_set_count,
    'confidence', case when coalesce((s1 ->> 'effort_known')::boolean, false)
      then 'high' else 'low' end);
end $$;
revoke all on function private.progression_decision(
  integer, integer, integer, numeric, numeric, integer, boolean, boolean, boolean, jsonb)
  from public, anon, authenticated;

-- One target per exercise of the athlete's active plan that has logged sets in
-- the lookback window. The history key matches get_my_exercise_history: the
-- catalog slug, else the exercise name; a substitution or an extra never
-- joins a catalog exercise because a name matches.
create function private.next_session_targets(p_user uuid)
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
    c.load_step_kg as step_kg
  from public.training_plan_versions v
  join public.planned_workouts w on w.plan_version_id = v.id and w.user_id = v.user_id
  join public.planned_exercises e on e.planned_workout_id = w.id and e.user_id = w.user_id
  left join public.exercise_catalog c on c.slug = e.exercise_slug
  where v.user_id = p_user and v.status = 'active'
), perf as (
  select pl.planned_exercise_id, pl.assisted, p.id as performance_id, p.status, p.pain_flag,
    s.local_date, s.completed_at, s.id as session_id
  from planned pl
  join public.exercise_performances p on p.user_id = p_user
  left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
  join public.workout_sessions s on s.id = p.workout_session_id and s.user_id = p.user_id
    and s.state = 'completed'
    and s.local_date >= (select d from today) - (select (r ->> 'lookback_days')::integer from rules)
  where (pl.exercise_slug is not null and p.exercise_slug = pl.exercise_slug)
    or (pl.exercise_slug is not null and p.exercise_slug is null
        and p.performance_kind = 'prescribed'
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.catalog_name_key)
    or (pl.exercise_slug is null and p.exercise_slug is null
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.name_key)
), logged as (
  select pf.planned_exercise_id, pf.assisted, pf.session_id, pf.local_date, pf.completed_at,
    pf.pain_flag,
    -- Assisted: the load is machine help and 0 is unassisted, so it is kept.
    case when pf.assisted then es.load_kg else nullif(es.load_kg, 0) end as load_kg,
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

-- The same targets for Coach context (the server reads them with the service role).
create function public.get_progression_summary_v1(p_user_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('schema_version', '1.0',
    'targets', private.next_session_targets(p_user_id));
$$;
revoke all on function public.get_progression_summary_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_progression_summary_v1(uuid) to service_role;

-- Training hub 1.7. The body below is the 1.6 definition from
-- 20261004090000_exercise_muscle_references.sql, unchanged except the schema
-- version and the one new key, next_targets.
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
  'schema_version','1.7','period_days',greatest(7,least(period_days,365)),
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
  'daily_load',private.daily_load(auth.uid(),private.local_date_for(auth.uid())),
  'next_targets',private.next_session_targets(auth.uid())
);
$$;
