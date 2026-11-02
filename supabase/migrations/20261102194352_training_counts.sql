-- Training counts: compliant lifters keep their loads, a new plan does not start behind, and one workout is
-- completed once a day.
--
-- 1. private.progression_decision: the effort check compares the lowest reps left with the hard edge of the
--    target's band (RPE 7.5 is "about 2-3 reps left", as the plan says, so 2 or 3 is on target; it used to
--    round to 3, held every set logged at 2 and then read the holds as a stall and cut the load). A session
--    that followed a hold is a stall only when reps per set fell, not when they repeated what was asked.
-- 2. private.training_started_on: the first day of the athlete's first plan. Days before it are neither
--    due nor missed, like the rest days of 20261101200000 (a break, a can't-train check-in):
--      get_my_daily_brief 1.9          the week's days before it are not planned (no shape change).
--      get_my_training_hub 1.11        planned_sessions leaves out the sessions before it, and the hub
--                                      returns it as training_started_on (additive).
--      generate_weekly_progress_review planned sessions start at it and leave out rest days; a week with
--                                      nothing due reads 100% (nothing missed), not "no plan".
--      get_coach_plan_state_v1 1.4     returns it, so Coach never calls a session before it undone.
-- 3. healthkit_auto_complete_workout takes start_workout's day lock, so a double tap on "Mark complete"
--    records one session; the repeat returns that session.
--
-- Every redefinition is its latest earlier definition plus the hunks pinned in
-- supabase/functions/_shared/training/standard/training_counts_migration_test.ts.

-- 1. Progression: the band's hard edge, and holds are not stalls -------------------------------------------

create or replace function private.progression_decision(
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
  -- The hard edge of the target's reps-left band (10 - RPE): RPE 7.5 is 2 to 3 reps left, so 2 or 3
  -- is on target and only fewer than 2 is harder than planned (RPE 7: 3, RPE 8: 2, RPE 8.5: 1).
  v_rir_target integer := case when p_target_rpe is null then 2
    else greatest(0, least(5, floor(10 - p_target_rpe)::integer)) end;
  v_can_lower boolean;
  v_hold_reps integer;
  v_action text;
  v_reason text;
  v_load_out numeric;
  v_reps integer;
  v_lower_load numeric;
  v_followed_hold boolean := false;
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
  -- Whether the session before the latest or the latest one followed a hold, as worked out from the
  -- sessions before each: repeating what a hold asked for is not a stall, so then only fewer reps
  -- per set is.
  if s3 is not null then
    v_followed_hold := private.progression_decision(p_set_count, p_rep_min, p_rep_max,
        p_target_rpe, p_step_kg,
        coalesce((s2 ->> 'local_date')::date - (s3 ->> 'local_date')::date, 0), false, false,
        p_assisted, jsonb_build_array(s3)) ->> 'action' = 'hold'
      or private.progression_decision(p_set_count, p_rep_min, p_rep_max,
        p_target_rpe, p_step_kg,
        coalesce((s1 ->> 'local_date')::date - (s2 ->> 'local_date')::date, 0), false, false,
        p_assisted, jsonb_build_array(s2, s3)) ->> 'action' = 'hold';
  end if;

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
       and nullif(s2 ->> 'load_kg', '')::numeric is not distinct from v_load and v_can_lower
       and not coalesce((s1 ->> 'adjusted')::boolean, false)
       and not coalesce((s2 ->> 'adjusted')::boolean, false) then
      v_action := 'lower'; v_reason := 'below_range';
      v_load_out := v_lower_load; v_reps := p_rep_min;
    else
      v_action := 'hold'; v_reason := 'below_range'; v_reps := p_rep_min;
    end if;
  elsif v_sets < coalesce((s1 ->> 'sets_planned')::integer, p_set_count)
        or coalesce((s1 ->> 'sets_planned')::integer, 1) = 0 then
    v_action := 'hold'; v_reason := 'incomplete';
  -- A cut-short session is not a stall (handled above); the comparison is reps per set.
  elsif s3 is not null and v_min_reps < p_rep_max
        and not coalesce((s1 ->> 'adjusted')::boolean, false)
        and not coalesce((s2 ->> 'adjusted')::boolean, false)
        and not coalesce((s3 ->> 'adjusted')::boolean, false)
        and nullif(s2 ->> 'load_kg', '')::numeric is not distinct from v_load
        and nullif(s3 ->> 'load_kg', '')::numeric is not distinct from v_load
        and ((s1 ->> 'total_reps')::integer * (s3 ->> 'sets')::integer
            < (s3 ->> 'total_reps')::integer * (s1 ->> 'sets')::integer
          or (not v_followed_hold
            and (s1 ->> 'total_reps')::integer * (s3 ->> 'sets')::integer
              = (s3 ->> 'total_reps')::integer * (s1 ->> 'sets')::integer)) then
    if v_can_lower then
      v_action := 'lower'; v_reason := 'stall';
      v_load_out := v_lower_load; v_reps := p_rep_min;
    else
      v_action := 'hold'; v_reason := 'stall';
    end if;
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

-- 2. The first day of training ------------------------------------------------------------------------------

-- The first day of the athlete's first plan: the earliest effective date of any version that was ever active.
-- A Coach change or a new block starts a later version, and the days before it stay due. Null before any plan.
create function private.training_started_on(p_user uuid)
returns date language sql stable security definer set search_path = '' as $$
  select min(coalesce(v.effective_date, private.local_day(p_user, v.approved_at)))
  from public.training_plan_versions v
  where v.user_id = p_user and v.status in ('active', 'superseded');
$$;
revoke all on function private.training_started_on(uuid) from public, anon, authenticated;

-- R1. The brief's week (20261101200000 plus the hunk; schema 1.9 unchanged).
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
  v_week_start date := target_date - (extract(isodow from target_date)::integer - 1);
begin
  if v_user_id is null then
    return jsonb_build_object('schema_version', '1.9',
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
    'schema_version', '1.9',
    'availability', private.availability_on(v_user_id, target_date, false),
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
    ),
    'recovery_previous', (
      select m.recovery_score
      from public.daily_computed_metrics m
      where m.user_id = v_user_id
        and m.local_date = target_date - 1
    ),
    'plan', (
      select jsonb_build_object(
        'title', p.title,
        'version_number', v.version_number,
        'block_weeks', v.block_weeks,
        'week_number', greatest(1,
          (target_date - coalesce(v.effective_date, v.approved_at::date)) / 7 + 1)
      )
      from public.training_plan_versions v
      join public.training_plans p on p.id = v.plan_id and p.user_id = v.user_id
      where v.user_id = v_user_id
        and v.status = 'active'
      order by v.version_number desc
      limit 1
    ),
    'week', (
      select jsonb_agg(jsonb_build_object(
        'local_date', d.day,
        'recovery', case
          when d.day = target_date then coalesce(
            (v_metrics->'scores'->>'recovery')::integer, m.recovery_score)
          else m.recovery_score end,
        'strain', case
          when d.day = target_date then coalesce(
            (v_metrics->'scores'->>'daily_strain')::numeric, m.daily_strain)
          else m.daily_strain end,
        'trained', exists (
          select 1 from public.workout_sessions s
          where s.user_id = v_user_id
            and s.local_date = d.day
            and s.state = 'completed'),
        -- A day the athlete chose not to train (a break, or a can't-train check-in) is not planned
        -- unless a session was logged on it (it then counts as planned and trained, as in the hub's
        -- adherence); paused says which days a break covers. A day before the athlete's first plan
        -- began was never due either.
        'paused', private.is_paused_on(v_user_id, d.day),
        'planned', (not private.is_rest_day(v_user_id, d.day) or exists (
          select 1 from public.workout_sessions s
          where s.user_id = v_user_id
            and s.local_date = d.day
            and s.state = 'completed')) and exists (
          select 1
          from public.planned_workouts w
          join public.training_plan_versions pv
            on pv.id = w.plan_version_id and pv.user_id = w.user_id
          where w.user_id = v_user_id
            and pv.status = 'active'
            and w.preferred_weekday = extract(isodow from d.day)::integer
            and d.day >= private.training_started_on(v_user_id))
      ) order by d.day)
      from (
        select (v_week_start + offs)::date as day
        from generate_series(0, 6) offs
      ) d
      left join public.daily_computed_metrics m
        on m.user_id = v_user_id and m.local_date = d.day
    ),
    'today_session', (
      select jsonb_build_object(
        'state', s.state,
        'exercises', coalesce((
          select jsonb_agg(jsonb_build_object(
            'order', p.exercise_order,
            'completed_sets', (
              select count(*) from public.exercise_sets es
              where es.exercise_performance_id = p.id and es.completed)
          ) order by p.exercise_order)
          from public.exercise_performances p
          where p.workout_session_id = s.id
        ), '[]'::jsonb)
      )
      from public.workout_sessions s
      where s.user_id = v_user_id
        and s.local_date = target_date
        and s.state <> 'abandoned'
      order by s.started_at desc
      limit 1
    )
  );
end;
$$;

-- R2. Training hub 1.11 (20261101200000 plus the hunks; every 1.10 key is still there).
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
), local_day as (
  select private.local_date_for(auth.uid()) as today
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
  -- Every finished session in the window, whichever plan version it was done under: a Coach change, a
  -- block or a deload copies the workouts under new ids, and the sessions logged before stay done.
  -- current_workout_id is the active version's workout with the same name and order, when it has one.
  select s.id,s.planned_workout_id,s.local_date,s.duration_seconds,
    s.session_energy,s.session_effort,s.notes,s.completed_at,w.name,
    s.completion_source,s.session_effort_source,
    (select aw.id from workouts aw where aw.workout_order=w.workout_order
      and lower(btrim(aw.name))=lower(btrim(w.name)) limit 1) current_workout_id
  from public.workout_sessions s
  join public.planned_workouts w on w.id=s.planned_workout_id and w.user_id=s.user_id
  where s.user_id=auth.uid() and s.state='completed'
    and s.local_date >= (select today from local_day)-greatest(7,least(period_days,365))+1
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
    and s.local_date >= (select today from local_day)-greatest(7,least(period_days,365))+1
  group by e.display_name_snapshot
), latest_computed as (
  select dcm.scores_jsonb->'acwr' as acwr,
         dcm.scores_jsonb->'training_monotony' as monotony,
         dcm.scores_jsonb->'daily_strain' as today_strain
  from public.daily_computed_metrics dcm
  where dcm.user_id=auth.uid()
    and dcm.local_date=(select today from local_day)
  order by dcm.computed_at desc
  limit 1
), started as (
  select private.training_started_on(auth.uid()) as d
), before_start as (
  -- Planned sessions on days before the athlete's first plan began: never due and never missed, so
  -- left out of adherence (a plan approved on a Thursday does not start the week behind).
  select count(*)::integer as sessions
  from (select g::date as d from generate_series(
      ((select today from local_day)-greatest(7,least(period_days,365))+1)::timestamp,
      (select today from local_day)::timestamp, interval '1 day') g) x
  join workouts w on w.preferred_weekday=extract(isodow from x.d)::integer
  where x.d < (select d from started)
    and not exists (select 1 from completed c where c.local_date=x.d)
), rest_sessions as (
  -- Planned sessions on days the athlete chose not to train (a break, or a can't-train check-in):
  -- neither due nor missed, so left out of adherence. A day a session was logged on stays planned,
  -- so done never passes planned.
  select count(*) filter (where private.is_paused_on(auth.uid(),x.d))::integer as paused,
    count(*) filter (where not private.is_paused_on(auth.uid(),x.d))::integer as unavailable
  from (select g::date as d from generate_series(
      ((select today from local_day)-greatest(7,least(period_days,365))+1)::timestamp,
      (select today from local_day)::timestamp, interval '1 day') g) x
  join workouts w on w.preferred_weekday=extract(isodow from x.d)::integer
  where private.is_rest_day(auth.uid(),x.d) and x.d >= (select d from started)
    and not exists (select 1 from completed c where c.local_date=x.d)
)
select jsonb_build_object(
  'schema_version','1.11','period_days',greatest(7,least(period_days,365)),
  'local_today',(select today from local_day),
  'training_started_on',(select d from started),
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
  'today_workout',private.planned_workout_for_date(auth.uid(),(select today from local_day)),
  'recent_sessions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'workout_id',planned_workout_id,'current_workout_id',current_workout_id,'name',name,'local_date',local_date,
    'duration_seconds',duration_seconds,'effort',session_effort,'energy',session_energy,
    'completion_source',completion_source,'effort_source',session_effort_source
  ) order by local_date desc) from (select * from completed order by local_date desc limit 12) r),'[]'::jsonb),
  'adherence',jsonb_build_object(
    'completed_sessions',(select count(*) from completed),
    'planned_sessions',greatest(0,coalesce((select sessions_per_week from active_version),0)
      * greatest(1,ceil(greatest(7,least(period_days,365))/7.0)::integer)
      - (select paused+unavailable from rest_sessions) - (select sessions from before_start)),
    'paused_sessions',(select paused from rest_sessions),
    'unavailable_sessions',(select unavailable from rest_sessions)),
  'progression',coalesce((select jsonb_agg(jsonb_build_object(
    'exercise',exercise,'sessions',sessions,'best_load_kg',best_load_kg,
    'best_repetitions',best_repetitions,'latest_date',latest_date
  ) order by latest_date desc) from progression),'[]'::jsonb),
  'completed_day_set',coalesce(
    (select jsonb_agg(distinct local_date) from completed),'[]'::jsonb),
  'computed',(select jsonb_build_object(
    'acwr',acwr,'training_monotony',monotony,'today_strain',today_strain
  ) from latest_computed),
  'daily_load',private.daily_load(auth.uid(),(select today from local_day)),
  'next_targets',private.next_session_targets(auth.uid()),
  'availability',private.availability_on(auth.uid(),(select today from local_day),false),
  'paused_days',coalesce((select jsonb_agg(d order by d) from private.paused_days(auth.uid(),
    (select today from local_day)-greatest(7,least(period_days,365))+1,
    (select today from local_day)+13) d),'[]'::jsonb),
  'unavailable_days',coalesce((select jsonb_agg(c.local_date order by c.local_date)
    from public.daily_check_ins c
    where c.user_id=auth.uid() and c.superseded_at is null and c.available_to_train is false
      and c.local_date between (select today from local_day)-greatest(7,least(period_days,365))+1
        and (select today from local_day)),'[]'::jsonb)
);
$$;

revoke all on function public.get_my_training_hub(integer) from public, anon, authenticated;
grant execute on function public.get_my_training_hub(integer) to authenticated;

-- R3. The weekly review's planned sessions (20260702223000 plus the hunks).
create or replace function private.generate_weekly_progress_review(target_job_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.weekly_review_jobs%rowtype;
  account public.user_accounts%rowtype;
  week_end date;
  planned_sessions integer := 0;
  completed_workouts integer := 0;
  completed_sets integer := 0;
  check_in_days integer := 0;
  meal_days integer := 0;
  health_days integer := 0;
  measurement_days integer := 0;
  average_energy numeric;
  average_soreness numeric;
  features jsonb;
  coverage jsonb;
  missing text[] := '{}';
  snapshot_hash text;
  snapshot_id uuid;
  review_id uuid;
  outcome_code text;
  adherence_percent integer;
  has_plan boolean;
begin
  select * into job from public.weekly_review_jobs
  where id = target_job_id for update;
  if not found then
    raise exception 'weekly review job not found' using errcode = 'P0002';
  end if;
  if job.status = 'completed' then
    select id into review_id from public.progress_reviews
    where user_id = job.user_id and review_week = job.review_week;
    return review_id;
  end if;
  select * into account from public.user_accounts
  where id = job.user_id and account_status = 'active'
    and onboarding_state = 'completed';
  if not found then
    update public.weekly_review_jobs
    set status = 'cancelled', updated_at = now(),
        sanitized_error_code = 'account_ineligible'
    where id = job.id;
    return null;
  end if;

  week_end := job.review_week + 6;
  update public.weekly_review_jobs
  set status = 'processing', attempts = attempts + 1,
      started_at = now(), updated_at = now()
  where id = job.id;

  select coalesce(max(sessions_per_week), 0) into planned_sessions
  from public.training_plan_versions
  where user_id = job.user_id and status = 'active';
  -- Days before the athlete's first plan began and days they chose not to train (a break, a
  -- can't-train check-in) were never due: their planned sessions are left out, unless a session was
  -- logged that day.
  has_plan := planned_sessions > 0;
  select greatest(0, planned_sessions - count(*)::integer) into planned_sessions
  from generate_series(job.review_week::timestamp, week_end::timestamp, interval '1 day') g
  join public.planned_workouts w on w.user_id = job.user_id
    and w.preferred_weekday = extract(isodow from g)::integer
  join public.training_plan_versions v on v.id = w.plan_version_id and v.user_id = w.user_id
    and v.status = 'active'
  where (g::date < private.training_started_on(job.user_id)
      or private.is_rest_day(job.user_id, g::date))
    and not exists (select 1 from public.workout_sessions s where s.user_id = job.user_id
      and s.local_date = g::date and s.state = 'completed');
  select count(*) into completed_workouts from public.workout_sessions
  where user_id = job.user_id and state = 'completed'
    and local_date between job.review_week and week_end;
  select count(*) into completed_sets
  from public.exercise_sets s
  join public.exercise_performances p on p.id = s.exercise_performance_id
  join public.workout_sessions w on w.id = p.workout_session_id
  where w.user_id = job.user_id and w.state = 'completed' and s.completed
    and w.local_date between job.review_week and week_end;
  select count(distinct local_date), round(avg(energy), 1), round(avg(soreness), 1)
  into check_in_days, average_energy, average_soreness
  from public.daily_check_ins
  where user_id = job.user_id and superseded_at is null
    and local_date between job.review_week and week_end;
  select count(distinct local_date) into meal_days from public.meals
  where user_id = job.user_id and status = 'confirmed'
    and local_date between job.review_week and week_end;
  select count(distinct local_date) into health_days
  from public.daily_health_summaries
  where user_id = job.user_id
    and local_date between job.review_week and week_end;
  select count(distinct measured_on) into measurement_days
  from public.body_measurements
  where user_id = job.user_id
    and measured_on between job.review_week and week_end;

  if not has_plan then
    missing := array_append(missing, 'active_training_plan');
    adherence_percent := 0;
  elsif planned_sessions = 0 then
    -- Nothing was due this week, so nothing was missed.
    adherence_percent := 100;
  else
    adherence_percent := least(100, round(completed_workouts * 100.0 / planned_sessions));
  end if;
  if check_in_days = 0 then missing := array_append(missing, 'recovery_check_ins'); end if;
  if meal_days = 0 then missing := array_append(missing, 'confirmed_nutrition'); end if;
  if health_days = 0 then missing := array_append(missing, 'health_context'); end if;
  outcome_code := case
    when completed_workouts = 0 then 'gather_execution_data'
    when check_in_days = 0 then 'training_logged_recovery_missing'
    else 'week_observed'
  end;

  features := jsonb_build_object(
    'review_week', job.review_week,
    'week_end', week_end,
    'timezone', account.timezone,
    'training', jsonb_build_object(
      'planned_sessions', planned_sessions,
      'completed_workouts', completed_workouts,
      'completed_sets', completed_sets,
      'adherence_percent', adherence_percent
    ),
    'recovery', jsonb_build_object(
      'check_in_days', check_in_days,
      'average_energy', average_energy,
      'average_soreness', average_soreness,
      'health_days', health_days
    ),
    'nutrition', jsonb_build_object('confirmed_days', meal_days),
    'progress', jsonb_build_object('measurement_days', measurement_days)
  );
  coverage := jsonb_build_object(
    'training', completed_workouts > 0,
    'recovery', check_in_days > 0,
    'nutrition', meal_days > 0,
    'health', health_days > 0,
    'measurements', measurement_days > 0
  );
  snapshot_hash := encode(
    extensions.digest(convert_to(features::text, 'UTF8'), 'sha256'), 'hex'
  );
  insert into public.feature_snapshots(
    user_id, trigger_kind, schema_version, feature_engine_version,
    features, coverage, missing_data, data_hash
  ) values (
    job.user_id, 'weekly', '1.0', 'weekly-deterministic-v2',
    features, coverage, missing, snapshot_hash
  ) on conflict(user_id, data_hash) do update
    set data_hash = excluded.data_hash
  returning id into snapshot_id;

  insert into public.progress_reviews(
    user_id, review_week, schema_version, summary,
    feature_snapshot_id, generation_kind
  ) values (
    job.user_id, job.review_week, '1.0',
    jsonb_build_object(
      'outcome_code', outcome_code,
      'training', features->'training',
      'recovery', features->'recovery',
      'nutrition', features->'nutrition',
      'progress', features->'progress',
      'missing_data', to_jsonb(missing),
      'unchanged', jsonb_build_object(
        'approved_plan', true,
        'nutrition_targets', true,
        'reason_code', 'no_persistent_change_from_weekly_review'
      ),
      'next_focus_code', case
        when completed_workouts = 0 then 'complete_next_planned_workout'
        when check_in_days = 0 then 'record_recovery_check_in'
        when meal_days = 0 then 'confirm_nutrition'
        else 'continue_approved_plan'
      end,
      'proposal_ids', '[]'::jsonb
    ), snapshot_id, 'deterministic'
  ) on conflict(user_id, review_week) do update
    set summary = excluded.summary,
        feature_snapshot_id = excluded.feature_snapshot_id,
        generation_kind = excluded.generation_kind
  returning id into review_id;

  update public.weekly_review_jobs
  set status = 'completed', completed_at = now(), updated_at = now(),
      sanitized_error_code = null
  where id = job.id;
  insert into public.audit_events(
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    job.user_id, 'progress.weekly_review.created', 'progress_review',
    review_id, 'succeeded', jsonb_build_object(
      'review_week', job.review_week, 'schema_version', '1.0',
      'generation_kind', 'deterministic'
    )
  );
  return review_id;
end
$$;

revoke all on function private.generate_weekly_progress_review(uuid)
  from public, anon, authenticated, service_role;

-- R4. Coach plan state 1.4 (20261024050011 plus the hunks; a reader of 1.3 ignores the new key).
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
    'schema_version', '1.4',
    'local_date', p_local_date,
    'weekday', extract(isodow from p_local_date)::integer,
    -- The first day of the athlete's first plan: a session on an earlier day was never due.
    'training_started_on', private.training_started_on(p_user_id),
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
    -- Workouts logged but not finished that the athlete has not answered: not done, and not missed
    -- either. `offerable` is whether the athlete can still save or discard it (7 days).
    'unfinished', coalesce((select jsonb_agg(jsonb_build_object(
        'planned_workout_id', u.planned_workout_id, 'local_date', u.local_date,
        'name', u.workout_name, 'logged_sets', u.logged_sets,
        'offerable', u.save_by >= p_local_date)
        order by u.local_date)
      from private.unfinished_workouts(p_user_id, p_local_date) u), '[]'::jsonb),
    'progression', public.get_progression_summary_v1(p_user_id));
$$;

-- 3. One Apple Health completion a day --------------------------------------------------------------------

-- R5. 20261024090000 plus the hunks.
create or replace function public.healthkit_auto_complete_workout(
  p_planned_workout_id uuid,
  p_local_date date
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid;
  v_plan_version_id uuid;
  v_duration_seconds integer;
  v_session_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'authentication required';
  end if;
  -- The lock start_workout takes for the day: a second tap waits for the first and then finds its
  -- session, so one workout is never completed twice for one day.
  perform pg_advisory_xact_lock(hashtextextended(
    'day_adjustment:' || v_user_id::text || coalesce(p_local_date::text, ''), 0));

  select v.id into v_plan_version_id
  from public.planned_workouts w
  join public.training_plan_versions v
    on v.id = w.plan_version_id and v.user_id = w.user_id
  where w.id = p_planned_workout_id
    and w.user_id = v_user_id
    and v.status = 'active'
    and w.preferred_weekday = extract(isodow from p_local_date)::integer;

  if v_plan_version_id is null then
    raise exception 'planned workout not found, not in active plan, or not scheduled for this weekday';
  end if;

  select id into v_session_id from public.workout_sessions
    where user_id = v_user_id
      and planned_workout_id = any((select private.workout_identity_ids(v_user_id, p_planned_workout_id))::uuid[])
      and local_date = p_local_date
      and state = 'completed'
    order by completed_at limit 1;
  if v_session_id is not null then
    return jsonb_build_object('session_id', v_session_id, 'replayed', true);
  end if;

  select coalesce(h.workout_minutes, 0) * 60 into v_duration_seconds
  from public.daily_health_summaries h
  where h.user_id = v_user_id
    and h.local_date = p_local_date
    and h.source_scope = 'healthkit'
  limit 1;

  if v_duration_seconds is null or v_duration_seconds = 0 then
    raise exception 'no HealthKit workout data available for this date';
  end if;

  insert into public.workout_sessions (
    user_id, plan_version_id, planned_workout_id,
    local_date, timezone, state, idempotency_key,
    started_at, completed_at, actual_started_at, actual_ended_at,
    duration_seconds, session_effort, notes,
    completion_source, session_effort_source
  ) values (
    v_user_id, v_plan_version_id, p_planned_workout_id,
    p_local_date, 'UTC', 'completed',
    gen_random_uuid(),
    now() - make_interval(secs := v_duration_seconds), now(),
    now() - make_interval(secs := v_duration_seconds), now(),
    v_duration_seconds,
    5,
    'Marked complete from Apple Health evidence',
    'healthkit', 'healthkit_default'
  )
  returning id into v_session_id;

  insert into public.audit_events (
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    v_user_id, 'workout.auto_completed',
    'workout_session', v_session_id, 'succeeded',
    jsonb_build_object(
      'source', 'healthkit',
      'planned_workout_id', p_planned_workout_id,
      'local_date', p_local_date,
      'duration_seconds', v_duration_seconds,
      'effort', 5
    )
  );

  return jsonb_build_object(
    'session_id', v_session_id,
    'replayed', false,
    'effort', 5
  );
end;
$$;

revoke all on function public.healthkit_auto_complete_workout(uuid, date) from public, anon;
grant execute on function public.healthkit_auto_complete_workout(uuid, date) to authenticated;
