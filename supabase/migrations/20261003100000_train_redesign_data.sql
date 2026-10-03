-- Train redesign data. Additive only: new columns, new functions, and new
-- fields on get_my_training_hub (schema 1.6). Nothing is removed or renamed.
--
-- 1. Completion and effort provenance on workout_sessions, backfilled from
--    audit action codes (never from notes).
-- 2. Stable exercise identity on exercise_performances (catalog slug).
-- 3. complete_workout_v2: the athlete's own session effort. The original
--    complete_workout keeps working for installed builds and records that its
--    effort was the app's default.
-- 4. abandon_workout: discard an in-progress workout.
-- 5. get_my_exercise_history 1.0: last time, best set and heaviest set per
--    session for up to 20 exercises.
-- 6. get_my_training_hub 1.6: plan dates and progression rule, exercise
--    muscles, completion source, and 28 days of day-level load.
-- 7. get_my_workout_session reports the provenance and ignores discarded
--    sessions.

-- 1. Provenance --------------------------------------------------------------

alter table public.workout_sessions
  add column completion_source text
    check (completion_source in ('manual', 'healthkit')),
  add column session_effort_source text
    check (session_effort_source in ('athlete', 'legacy_default', 'healthkit_default')),
  add constraint workout_sessions_completion_source_state_check
    check (completion_source is null or state = 'completed');

update public.workout_sessions s
set completion_source = 'healthkit', session_effort_source = 'healthkit_default'
where s.state = 'completed'
  and exists (
    select 1 from public.audit_events a
    where a.user_id = s.user_id and a.target_type = 'workout_session'
      and a.target_id = s.id and a.action_code = 'workout.auto_completed');

update public.workout_sessions s
set completion_source = 'manual'
where s.state = 'completed' and s.completion_source is null
  and exists (
    select 1 from public.audit_events a
    where a.user_id = s.user_id and a.target_type = 'workout_session'
      and a.target_id = s.id and a.action_code = 'workout.completed');

-- Every effort stored before this migration came from the app's fixed default
-- (8 for logged workouts) or the Apple Health default (5, set above).
update public.workout_sessions
set session_effort_source = 'legacy_default'
where state = 'completed' and session_effort is not null and session_effort_source is null;

-- 2. Stable exercise identity -------------------------------------------------

alter table public.exercise_performances
  add column exercise_slug text references public.exercise_catalog(slug);

create index exercise_performances_user_slug
  on public.exercise_performances(user_id, exercise_slug)
  where exercise_slug is not null;

-- A performance carries its catalog slug only while it is the prescribed
-- exercise. A substitution or an extra exercise is something else, so it has
-- none and its history is keyed by name.
create function private.exercise_performance_slug()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.performance_kind = 'prescribed' and new.planned_exercise_id is not null then
    select pe.exercise_slug into new.exercise_slug
    from public.planned_exercises pe
    where pe.id = new.planned_exercise_id and pe.user_id = new.user_id;
  else
    new.exercise_slug := null;
  end if;
  return new;
end $$;
revoke all on function private.exercise_performance_slug() from public, anon, authenticated;

create trigger exercise_performance_slug
  before insert or update of performance_kind, planned_exercise_id
  on public.exercise_performances
  for each row execute function private.exercise_performance_slug();

update public.exercise_performances p
set exercise_slug = pe.exercise_slug
from public.planned_exercises pe
where pe.id = p.planned_exercise_id and pe.user_id = p.user_id
  and p.performance_kind = 'prescribed' and pe.exercise_slug is not null;

-- Lowercase, trimmed, inner spaces collapsed: the legacy key for performances
-- without a slug.
create function private.exercise_name_key(raw text)
returns text language sql immutable set search_path = '' as $$
  select nullif(regexp_replace(lower(btrim(coalesce(raw, ''))), '\s+', ' ', 'g'), '');
$$;
revoke all on function private.exercise_name_key(text) from public, anon, authenticated;

-- 3. Completion -----------------------------------------------------------------

create function private.complete_workout_session(
  p_session_id uuid,
  p_client_revision integer,
  p_duration_seconds integer,
  p_session_energy smallint,
  p_session_effort numeric,
  p_notes text,
  p_effort_source text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session public.workout_sessions%rowtype; completed_sets integer; total_sets integer;
  coverage numeric; capped_duration integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into session from public.workout_sessions
    where id = p_session_id and user_id = auth.uid() for update;
  if not found then raise exception 'session not found' using errcode = 'P0002'; end if;
  if session.state = 'completed' then
    return jsonb_build_object('session_id', session.id, 'replayed', true);
  end if;
  if session.state = 'abandoned' then
    raise exception 'session was discarded' using errcode = '55000';
  end if;
  if p_client_revision < session.client_revision then
    raise exception 'stale client revision' using errcode = '40001';
  end if;
  select count(*) filter (where s.completed), count(*) into completed_sets, total_sets
  from public.exercise_sets s
  join public.exercise_performances p on p.id = s.exercise_performance_id
  where p.workout_session_id = session.id;
  if completed_sets = 0 then raise exception 'complete at least one set' using errcode = '22023'; end if;
  coverage := completed_sets::numeric / greatest(total_sets, 1);
  capped_duration := least(p_duration_seconds, 10800);
  update public.exercise_performances p set status = case
    when p.status = 'skipped' then 'skipped'
    when exists (select 1 from public.exercise_sets s
                 where s.exercise_performance_id = p.id and s.completed) then 'performed'
    else 'unknown' end
  where p.workout_session_id = session.id;
  update public.workout_sessions set
    state = 'completed', completed_at = now(), actual_ended_at = coalesce(actual_ended_at, now()),
    duration_seconds = capped_duration, session_energy = p_session_energy,
    session_effort = p_session_effort, notes = p_notes,
    completion_source = 'manual', session_effort_source = p_effort_source,
    logging_completeness = coverage,
    client_revision = greatest(workout_sessions.client_revision, p_client_revision),
    updated_at = now()
  where id = session.id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'workout.completed', 'workout_session', session.id, 'succeeded',
    jsonb_build_object('completed_sets', completed_sets, 'total_sets', total_sets,
      'logging_completeness', coverage, 'effort_source', p_effort_source));
  return jsonb_build_object('session_id', session.id, 'completed_sets', completed_sets,
    'total_sets', total_sets, 'logging_completeness', coverage, 'replayed', false);
end $$;
revoke all on function private.complete_workout_session(uuid, integer, integer, smallint, numeric, text, text)
  from public, anon, authenticated;

-- Installed builds send a fixed effort; record it as the default it is.
create or replace function public.complete_workout(
  session_id uuid,
  client_revision integer,
  duration_seconds integer,
  session_energy smallint,
  session_effort numeric,
  notes text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return private.complete_workout_session(complete_workout.session_id,
    complete_workout.client_revision, complete_workout.duration_seconds,
    complete_workout.session_energy, complete_workout.session_effort,
    complete_workout.notes, 'legacy_default');
end $$;

-- The athlete rates the whole workout from 1 to 10. Energy is optional.
create function public.complete_workout_v2(
  session_id uuid,
  client_revision integer,
  duration_seconds integer,
  session_effort numeric,
  notes text,
  session_energy smallint default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if complete_workout_v2.session_effort is null
    or complete_workout_v2.session_effort not between 1 and 10
    or complete_workout_v2.session_effort <> round(complete_workout_v2.session_effort) then
    raise exception 'session effort must be a whole number from 1 to 10' using errcode = '22023';
  end if;
  result := private.complete_workout_session(complete_workout_v2.session_id,
    complete_workout_v2.client_revision, complete_workout_v2.duration_seconds,
    complete_workout_v2.session_energy, complete_workout_v2.session_effort,
    coalesce(complete_workout_v2.notes, ''), 'athlete');
  return jsonb_build_object('schema_version', '1.0') || result;
end $$;
revoke all on function public.complete_workout_v2(uuid, integer, integer, numeric, text, smallint)
  from public, anon, authenticated;
grant execute on function public.complete_workout_v2(uuid, integer, integer, numeric, text, smallint)
  to authenticated;

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

  if exists (
    select 1 from public.workout_sessions
    where user_id = v_user_id
      and planned_workout_id = p_planned_workout_id
      and local_date = p_local_date
      and state = 'completed'
  ) then
    return jsonb_build_object('session_id', null, 'replayed', true);
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

-- 4. Discard ----------------------------------------------------------------------

-- The rows stay for the audit trail; every read of training history counts
-- completed sessions only, so a discarded workout never shows up.
create function public.abandon_workout(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare session public.workout_sessions%rowtype; logged_sets integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into session from public.workout_sessions
    where id = p_session_id and user_id = auth.uid() for update;
  if not found then raise exception 'session not found' using errcode = 'P0002'; end if;
  if session.state = 'abandoned' then
    return jsonb_build_object('schema_version', '1.0', 'session_id', session.id,
      'state', 'abandoned', 'replayed', true);
  end if;
  if session.state = 'completed' then
    raise exception 'a completed workout cannot be discarded' using errcode = '22023';
  end if;
  select count(*) filter (where s.completed) into logged_sets
  from public.exercise_sets s
  join public.exercise_performances p on p.id = s.exercise_performance_id
  where p.workout_session_id = session.id;
  update public.workout_sessions
    set state = 'abandoned', actual_ended_at = coalesce(actual_ended_at, now()), updated_at = now()
    where id = session.id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'workout.abandoned', 'workout_session', session.id, 'succeeded',
    jsonb_build_object('completed_sets', logged_sets));
  return jsonb_build_object('schema_version', '1.0', 'session_id', session.id,
    'state', 'abandoned', 'replayed', false);
end $$;
revoke all on function public.abandon_workout(uuid) from public, anon, authenticated;
grant execute on function public.abandon_workout(uuid) to authenticated;

-- 5. Exercise history ----------------------------------------------------------------

-- Keys are catalog slugs or exercise names. A slug key matches performances
-- with that slug, plus older performances without one whose name equals the
-- catalog name. A name key matches performances without a slug by name only,
-- so two different catalog exercises never merge. Completed sessions and
-- completed sets only.
create function public.get_my_exercise_history(p_keys text[], p_sessions integer default 8)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare keys text[]; session_limit integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_keys is null or cardinality(p_keys) = 0 then
    raise exception 'at least one exercise key is required' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_keys) k where k is null or length(btrim(k)) not between 1 and 120) then
    raise exception 'each exercise key must be 1 to 120 characters' using errcode = '22023';
  end if;
  select array_agg(distinct btrim(k)) into keys from unnest(p_keys) k;
  if cardinality(keys) > 20 then
    raise exception 'at most 20 exercise keys' using errcode = '22023';
  end if;
  session_limit := greatest(1, least(coalesce(p_sessions, 8), 12));

  return jsonb_build_object(
    'schema_version', '1.0',
    'sessions_limit', session_limit,
    'exercises', coalesce((
      with requested as (
        select k as key, c.slug, private.exercise_name_key(k) as name_key,
          private.exercise_name_key(c.name) as catalog_name_key
        from unnest(keys) k
        left join public.exercise_catalog c on c.slug = k
      ), matched as (
        select r.key, s.id as session_id, s.local_date, s.completed_at,
          p.exercise_order, es.set_number, es.load_kg, es.repetitions, es.rpe
        from requested r
        join public.exercise_performances p on p.user_id = auth.uid()
        left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
        join public.workout_sessions s on s.id = p.workout_session_id and s.user_id = p.user_id
          and s.state = 'completed'
        join public.exercise_sets es on es.exercise_performance_id = p.id and es.user_id = p.user_id
          and es.completed and es.repetitions > 0
        where p.status <> 'skipped'
          and (
            (r.slug is not null and p.exercise_slug = r.slug)
            or (p.exercise_slug is null
                and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
                    in (r.name_key, r.catalog_name_key))
          )
      ), kinds as (
        select key, case when bool_or(load_kg > 0) then 'load' else 'reps' end as kind
        from matched group by key
      ), ranked as (
        select m.*, k.kind,
          row_number() over (partition by m.key, m.session_id
            order by case when k.kind = 'load' then m.load_kg end desc nulls last,
                     m.repetitions desc, m.set_number) as in_session_rank,
          row_number() over (partition by m.key
            order by case when k.kind = 'load' then m.load_kg end desc nulls last,
                     m.repetitions desc, m.local_date, m.completed_at) as overall_rank
        from matched m join kinds k on k.key = m.key
        where k.kind = 'reps' or m.load_kg > 0
      ), latest as (
        select distinct on (key) key, session_id, local_date
        from matched
        order by key, local_date desc, completed_at desc
      ), tops as (
        select key, session_id, local_date, completed_at, load_kg, repetitions,
          row_number() over (partition by key order by local_date desc, completed_at desc) as recency
        from ranked where in_session_rank = 1
      )
      select jsonb_agg(jsonb_build_object(
        'key', r.key,
        'kind', k.kind,
        'last_session', (
          select jsonb_build_object('session_id', l.session_id, 'local_date', l.local_date,
            'sets', (select jsonb_agg(jsonb_build_object(
                'set_number', m.set_number, 'load_kg', m.load_kg,
                'repetitions', m.repetitions, 'rpe', m.rpe)
              order by m.exercise_order, m.set_number)
              from matched m where m.key = l.key and m.session_id = l.session_id))
          from latest l where l.key = r.key),
        'best_set', (
          select jsonb_build_object('kind', b.kind, 'load_kg', b.load_kg,
            'repetitions', b.repetitions, 'local_date', b.local_date)
          from ranked b where b.key = r.key and b.overall_rank = 1),
        'top_sets', coalesce((
          select jsonb_agg(jsonb_build_object('local_date', t.local_date,
              'load_kg', t.load_kg, 'repetitions', t.repetitions)
            order by t.local_date desc, t.completed_at desc)
          from tops t where t.key = r.key and t.recency <= session_limit), '[]'::jsonb)
      ) order by r.key)
      from requested r left join kinds k on k.key = r.key
    ), '[]'::jsonb)
  );
end $$;
revoke all on function public.get_my_exercise_history(text[], integer) from public, anon, authenticated;
grant execute on function public.get_my_exercise_history(text[], integer) to authenticated;

-- 6. Day-level load ---------------------------------------------------------------------

-- 28 local days ending today. Strain is ALGORITHMS §4 (effort x minutes / 10,
-- sessions of 3 hours or less), the same sum compute_daily_metrics uses. A
-- day is easy, moderate or hard against the athlete's own effort-reported
-- training days in the 28 days before it (33rd and 67th percentiles, ties to
-- the lower class). With fewer than 8 such days, fixed cut-offs apply. A day
-- whose effort was a default has no level: Tracend does not know how hard it
-- was.
create function private.daily_load(target_user_id uuid, target_date date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with per_day as (
    select g::date as local_date,
      count(s.id)::integer as sessions,
      coalesce(sum(s.session_effort * s.duration_seconds / 600.0)
        filter (where s.session_effort is not null and s.duration_seconds is not null
                  and s.duration_seconds <= 10800), 0) as strain,
      coalesce(sum(s.duration_seconds)
        filter (where s.duration_seconds is not null and s.duration_seconds <= 10800), 0) as seconds,
      count(s.id) > 0 and bool_and(coalesce(s.session_effort_source = 'athlete', false)) as reported
    from generate_series(target_date - 55, target_date, interval '1 day') g
    left join public.workout_sessions s
      on s.user_id = target_user_id and s.state = 'completed' and s.local_date = g::date
    group by g::date
  ), classified as (
    select d.*,
      ref.n as reference_days, ref.p33, ref.p67
    from per_day d
    cross join lateral (
      select count(*) as n,
        percentile_disc(0.33) within group (order by r.strain) as p33,
        percentile_disc(0.67) within group (order by r.strain) as p67
      from per_day r
      where r.local_date between d.local_date - 28 and d.local_date - 1
        and r.sessions > 0 and r.reported and r.strain > 0
    ) ref
    where d.local_date > target_date - 28
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'local_date', local_date,
    'recorded', sessions > 0,
    'strain', round(strain, 1),
    'minutes', round(seconds / 60.0)::integer,
    'sessions', sessions,
    'effort_reported', reported,
    'level', case
      when sessions = 0 then 'rest'
      when not reported or strain = 0 then null
      when reference_days >= 8 then case
        when strain <= p33 then 'easy'
        when strain <= p67 then 'moderate'
        else 'hard' end
      when strain < 20 then 'easy'
      when strain <= 40 then 'moderate'
      else 'hard' end,
    'reference', case when reference_days >= 8 then 'personal' else 'fixed' end
  ) order by local_date), '[]'::jsonb)
  from classified;
$$;
revoke all on function private.daily_load(uuid, date) from public, anon, authenticated;

-- 7. Training hub 1.6 --------------------------------------------------------------------

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
      'primary_muscles',coalesce(to_jsonb(c.primary_muscles),'[]'::jsonb)
    ) order by e.exercise_order)
    from public.planned_exercises e
    left join public.exercise_catalog c on c.slug=e.exercise_slug
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

-- 8. Workout session -------------------------------------------------------------------------

create or replace function public.get_my_workout_session(
  p_planned_workout_id uuid,
  p_local_date date
)
returns jsonb language plpgsql security invoker set search_path='' stable as $$
declare target public.workout_sessions%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into target from public.workout_sessions
  where user_id=auth.uid() and planned_workout_id=p_planned_workout_id
    and state<>'abandoned'
    and (state='in_progress' or local_date=p_local_date)
  order by case state when 'in_progress' then 0 else 1 end, started_at desc
  limit 1;
  if not found then return null; end if;
  return jsonb_build_object(
    'session_id',target.id,'state',target.state,'revision',target.client_revision,
    'idempotency_key',target.idempotency_key,'local_date',target.local_date,
    'actual_started_at',target.actual_started_at,'actual_ended_at',target.actual_ended_at,
    'duration_seconds',target.duration_seconds,'notes',target.notes,
    'completion_source',target.completion_source,
    'session_effort',target.session_effort,
    'session_effort_source',target.session_effort_source,
    'exercises',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'performance_id',p.id,'order',p.exercise_order,'status',p.status,
        'performance_kind',p.performance_kind,'performed_name',p.performed_name,
        'exercise_slug',p.exercise_slug,
        'substitution_reason',p.substitution_reason,'pain_flag',p.pain_flag,
        'note',p.note,'rest_seconds',p.rest_seconds,
        'sets',(select coalesce(jsonb_agg(jsonb_build_object(
          'number',s.set_number,'repetitions',s.repetitions,'load_kg',s.load_kg,
          'rpe',s.rpe,'completed',s.completed
        ) order by s.set_number),'[]'::jsonb) from public.exercise_sets s where s.exercise_performance_id=p.id)
      ) order by p.exercise_order),'[]'::jsonb)
      from public.exercise_performances p where p.workout_session_id=target.id
    )
  );
end $$;
