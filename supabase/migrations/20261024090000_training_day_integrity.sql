-- Training-day integrity (QA audit group A).
--
-- 1. A session logged under an older plan version no longer vanishes from Train or becomes loggable twice.
--    Coach changes, block restores, deloads and cardio blocks copy a plan's workouts under new ids
--    (private.clone_plan_version, private.coach_insert_workouts), and every reader keyed on the session's
--    planned_workout_id lost the old sessions. The copy keeps a workout's name and order, so the identity
--    of a workout across versions is its name (case and outer spaces ignored) and order, as Coach's own
--    context already matches it (completed_this_week). No lineage column is recorded, and none is added:
--    a unique index cannot span planned_workouts, and production already holds one same-day repeat.
--      get_my_training_hub 1.9   builds `completed` from every session by date, not from the active
--                                version's workouts; recent_sessions gain current_workout_id.
--      start_workout             the in-progress lookup and the already-completed check cover the identity.
--      get_my_workout_session    finds the day's session of the same workout under an earlier version.
--      get_healthkit_completion_candidate, healthkit_auto_complete_workout, day_adjustment_compute and
--                                unfinished_workouts  the same identity in their duplicate checks.
-- 2. start_workout refuses a day that has not begun for the athlete (22023). A workout done today that is
--    not the day's scheduled one takes out or swaps what a held or limited joint asks.
-- 3. get_my_training_hub reads the athlete's local date everywhere (it mixed in the database's current_date).
-- 4. One weekday rule on the server. A plan version whose workouts have no weekday at all (a Coach proposal
--    may omit them) read as rest days to every server reader of preferred_weekday: no readiness card, no
--    joint adjustment, no Apple Health completion. private.fill_workout_weekdays gives such a version its
--    weekdays, in plan order: the athlete's profile training days when they are as many as the workouts,
--    else a spread of the week. coach_insert_workouts calls it, and this migration fills the versions that
--    already exist (none in production on 2026-10-24).
--
-- Every function below is its latest earlier definition plus the hunks pinned in
-- supabase/functions/_shared/training/standard/training_day_integrity_test.ts.

-- 1. A workout's identity across plan versions -----------------------------------------------------------

create index planned_workouts_user_order on public.planned_workouts(user_id, workout_order);

create function private.workout_identity_ids(p_user uuid, p_workout uuid)
returns uuid[] language sql stable set search_path = '' as $$
  select coalesce(
    (select array_agg(o.id)
     from public.planned_workouts w
     join public.planned_workouts o on o.user_id = w.user_id and o.workout_order = w.workout_order
       and lower(btrim(o.name)) = lower(btrim(w.name))
     where w.id = p_workout and w.user_id = p_user),
    array[p_workout]);
$$;
revoke all on function private.workout_identity_ids(uuid, uuid) from public, anon, authenticated;

-- 2. Weekdays for a plan version that has none ---------------------------------------------------------

-- The training days for p_count workouts: the profile's own days when they are as many as the workouts,
-- else a spread with rest between them (two: Monday, Thursday; three: Monday, Wednesday, Friday; four:
-- Monday, Tuesday, Thursday, Friday; one, or five or more: from Monday on).
create function private.default_workout_weekdays(p_user uuid, p_count integer)
returns smallint[] language sql stable set search_path = '' as $$
  select case
    when cardinality(own.days) = p_count then own.days
    when p_count = 2 then array[1, 4]::smallint[]
    when p_count = 3 then array[1, 3, 5]::smallint[]
    when p_count = 4 then array[1, 2, 4, 5]::smallint[]
    else array(select g::smallint from generate_series(1, least(greatest(p_count, 1), 7)) g order by g)
  end
  from (select coalesce((select array(select distinct d from unnest(p.training_days) d order by d)
    from public.user_profiles p where p.user_id = p_user), '{}'::smallint[]) as days) own;
$$;
revoke all on function private.default_workout_weekdays(uuid, integer) from public, anon, authenticated;

-- Gives the workouts of a plan version their weekdays, in plan order, when none of them has one.
create function private.fill_workout_weekdays(p_version uuid)
returns void language sql set search_path = '' as $$
  update public.planned_workouts w
  set preferred_weekday = (private.default_workout_weekdays(r.user_id, r.n))[r.pos::integer]
  from (select x.id, x.user_id, (count(*) over ())::integer as n, row_number() over (order by x.workout_order) as pos
    from public.planned_workouts x where x.plan_version_id = p_version) r
  where w.id = r.id
    and not exists (select 1 from public.planned_workouts y
      where y.plan_version_id = p_version and y.preferred_weekday is not null);
$$;
revoke all on function private.fill_workout_weekdays(uuid) from public, anon, authenticated;

select private.fill_workout_weekdays(v.plan_version_id)
from (select distinct plan_version_id from public.planned_workouts where preferred_weekday is null) v;

-- The definition of 20261018120018_coach_proposals.sql plus the weekdays for a structure that has none.

create or replace function private.coach_insert_workouts(
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
  -- A structure with no weekday at all gets the athlete's training days (or the spread of the week).
  perform private.fill_workout_weekdays(p_version);
end $$;

-- 3. Starting the workout ---------------------------------------------------------------------------------
-- The definition of 20261024060025_pain_checks.sql plus the future-day refusal, the identity checks and the
-- joint rules for a workout done today that is not the day's own.

create or replace function public.start_workout(
  p_planned_workout_id uuid,
  p_local_date date,
  p_timezone text,
  p_idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; version_id uuid; exercise record; performance_id uuid; n integer;
  adjustment public.day_adjustments%rowtype; adjusted boolean := false; set_total integer;
  entry jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  -- The same lock respond_to_day_adjustment_v1 takes: an answer and a start never interleave.
  perform pg_advisory_xact_lock(hashtextextended(
    'day_adjustment:' || auth.uid()::text || coalesce(p_local_date::text, ''), 0));
  select w.plan_version_id into version_id
  from public.planned_workouts w
  join public.training_plan_versions v on v.id=w.plan_version_id and v.user_id=w.user_id
  where w.id=p_planned_workout_id and w.user_id=auth.uid() and v.status='active';
  if not found then raise exception 'planned workout not found' using errcode='P0002'; end if;

  select id into result_id from public.workout_sessions
  where user_id=auth.uid() and idempotency_key=p_idempotency_key;
  if result_id is not null then return result_id; end if;
  -- A workout is started on a day that has begun for the athlete, never on one still ahead (a repeat of a
  -- start that was answered above is not a new start).
  if p_local_date > private.local_date_for(auth.uid()) then
    raise exception 'cannot start a workout on a future day' using errcode='22023';
  end if;

  -- A session left open from an earlier day is closed first, so it is never found as today's.
  perform private.abandon_stale_workouts(auth.uid());
  select id into result_id from public.workout_sessions
  where user_id=auth.uid() and planned_workout_id = any((select private.workout_identity_ids(auth.uid(), p_planned_workout_id))) and state='in_progress'
  order by started_at desc limit 1;
  if result_id is not null then return result_id; end if;

  -- The same workout under any plan version: a Coach change, a block or a deload copies the workouts under
  -- new ids, and a day already logged stays logged.
  if exists (
    select 1 from public.workout_sessions
    where user_id=auth.uid()
      and planned_workout_id = any((select private.workout_identity_ids(auth.uid(), p_planned_workout_id)))
      and local_date=p_local_date and state='completed'
  ) then
    raise exception 'workout already completed for this coaching day' using errcode='55000';
  end if;

  -- The athlete's accepted answer for today is applied as given (it can only make the day easier);
  -- a start for any other date, from history, gets the plan as written.
  if p_local_date = private.local_date_for(auth.uid()) then
    select * into adjustment from public.day_adjustments a
    where a.user_id=auth.uid() and a.local_date=p_local_date
      and a.planned_workout_id=p_planned_workout_id and a.superseded_at is null
      and a.status='accepted';
    adjusted := found;
    -- An answer that carries joint changes is applied only while they are the ones the rules ask for now;
    -- otherwise the plan is built as written (the day's safety route is the card's business, not a rewrite
    -- of the session). An answer without joint changes is applied as given, as before.
    if adjusted and private.joint_change_keys(adjustment.changes) <> '{}'::text[]
       and private.joint_change_keys(adjustment.changes) is distinct from private.joint_change_keys(
         private.joint_changes(auth.uid(), p_planned_workout_id,
           private.joint_states(auth.uid(), p_local_date), '[]'::jsonb)) then
      adjusted := false;
    end if;
    -- A workout done today that is not the day's scheduled one has no card and no stored answer. The joint
    -- rules still take out or swap what a held or limited joint asks, as they would on the card; readiness
    -- answers belong to the scheduled workout.
    if not adjusted
       and (private.planned_workout_for_date(auth.uid(), p_local_date) ->> 'id') is distinct from p_planned_workout_id::text then
      adjustment.changes := coalesce((select jsonb_agg(c) from jsonb_array_elements(
        private.joint_changes(auth.uid(), p_planned_workout_id,
          private.joint_states(auth.uid(), p_local_date), '[]'::jsonb)) c
        where c ->> 'joint_action' in ('drop', 'swap')), '[]'::jsonb);
      adjusted := jsonb_array_length(adjustment.changes) > 0;
    end if;
  end if;

  insert into public.workout_sessions(
    user_id,plan_version_id,planned_workout_id,local_date,timezone,idempotency_key,actual_started_at,
    day_adjustment_id
  ) values(
    auth.uid(),version_id,p_planned_workout_id,p_local_date,p_timezone,p_idempotency_key,now(),
    case when adjusted then adjustment.id end
  ) returning id into result_id;

  for exercise in select * from public.planned_exercises pe
    where pe.planned_workout_id=p_planned_workout_id order by exercise_order loop
    -- What the accepted answer says about this exercise, if anything.
    entry := null;
    if adjusted then
      select c into entry from jsonb_array_elements(adjustment.changes) c
      where c ->> 'planned_exercise_id' = exercise.id::text limit 1;
    end if;
    -- An exercise the answer swaps for a gentler one is created as that exercise, a substitution made
    -- for pain (the load is not written: the athlete picks it); every other exercise is as planned.
    insert into public.exercise_performances(
      user_id,workout_session_id,planned_exercise_id,exercise_order,status,
      performance_kind,performed_name,rest_seconds,substitution_reason
    ) values(
      auth.uid(),result_id,exercise.id,exercise.exercise_order,'unknown',
      case when entry ->> 'joint_action' = 'swap' then 'substituted' else 'prescribed' end,
      case when entry ->> 'joint_action' = 'swap' then entry ->> 'swap_to_name'
        else exercise.display_name_snapshot end,
      exercise.rest_seconds,
      case when entry ->> 'joint_action' = 'swap' then 'pain' end
    ) returning id into performance_id;
    -- A left-out exercise (a joint drop) gets no sets whatever the kind: its performance stays
    -- 'unknown', never inferred as skipped. reduce_sets builds the adjusted set counts. Everything
    -- else, an easy-cardio answer included, keeps the plan's sets.
    set_total := exercise.set_count;
    if entry is not null then
      set_total := coalesce(case when entry ->> 'joint_action' = 'drop' then 0
        when adjustment.kind='reduce_sets' then (entry ->> 'sets_to')::integer end, exercise.set_count);
    end if;
    for n in 1..set_total loop
      insert into public.exercise_sets(user_id,exercise_performance_id,set_number)
      values(auth.uid(),performance_id,n);
    end loop;
  end loop;
  return result_id;
end $$;
revoke all on function public.start_workout(uuid, date, text, uuid) from public, anon, authenticated;
grant execute on function public.start_workout(uuid, date, text, uuid) to authenticated;

-- 4. Reading a day's session ------------------------------------------------------------------------------
-- The definition of 20261023150021_close_stale_workouts.sql plus the identity of the workout.

create or replace function public.get_my_workout_session(
  p_planned_workout_id uuid,
  p_local_date date
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target public.workout_sessions%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  perform private.abandon_stale_workouts(auth.uid());
  select * into target from public.workout_sessions
  -- The same workout under any plan version: a session in progress or finished that day under an earlier
  -- version is the one this workout's day holds.
  where user_id=auth.uid() and planned_workout_id = any((select private.workout_identity_ids(auth.uid(), p_planned_workout_id)))
    and state<>'abandoned'
    and (state='in_progress' or local_date=p_local_date)
  order by case state when 'in_progress' then 0 else 1 end, started_at desc
  limit 1;
  if not found then return null; end if;
  return jsonb_build_object(
    'schema_version','1.1',
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
          'rpe',s.rpe,'completed',s.completed,
          'started_at',s.started_at,'completed_at',s.completed_at,
          'rest_before_seconds',s.rest_before_seconds,'rir',s.rir,
          'timing_source',s.timing_source
        ) order by s.set_number),'[]'::jsonb) from public.exercise_sets s where s.exercise_performance_id=p.id)
      ) order by p.exercise_order),'[]'::jsonb)
      from public.exercise_performances p where p.workout_session_id=target.id
    )
  );
end $$;

revoke all on function public.get_my_workout_session(uuid, date) from public, anon, authenticated;
grant execute on function public.get_my_workout_session(uuid, date) to authenticated;

-- 5. HealthKit completion -----------------------------------------------------------------------------------
-- The definitions of 20260718110000_healthkit_candidate_per_date.sql and 20261003100000_train_redesign_data.sql
-- with the identity check in place of the exact workout id.

create or replace function public.get_healthkit_completion_candidate(
  p_local_date date
)
returns jsonb
language sql
security definer
set search_path = ''
stable
as $$
  select jsonb_build_object(
    'planned_workout_id', w.id,
    'planned_workout_name', w.name,
    'workout_count', h.workout_count,
    'workout_minutes', h.workout_minutes,
    'local_date', h.local_date
  )
  from public.planned_workouts w
  join public.training_plan_versions v
    on v.id = w.plan_version_id
    and v.user_id = w.user_id
    and v.status = 'active'
  join public.daily_health_summaries h
    on h.user_id = v.user_id
    and h.local_date = p_local_date
    and h.source_scope = 'healthkit'
    and h.workout_count > 0
  where w.user_id = auth.uid()
    and w.preferred_weekday = extract(isodow from p_local_date)::integer
    and not exists (
      select 1 from public.workout_sessions s
      where s.user_id = w.user_id
        and s.planned_workout_id = any((select private.workout_identity_ids(w.user_id, w.id)))
        and s.local_date = p_local_date
        and s.state = 'completed'
    )
  limit 1;
$$;

grant execute on function public.get_healthkit_completion_candidate(date) to authenticated;

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
      and planned_workout_id = any((select private.workout_identity_ids(v_user_id, p_planned_workout_id)))
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

revoke all on function public.healthkit_auto_complete_workout(uuid, date) from public, anon;
grant execute on function public.healthkit_auto_complete_workout(uuid, date) to authenticated;

-- 6. The day's readiness and the unfinished list ---------------------------------------------------------------
-- 20261024060025_pain_checks.sql (day_adjustment_compute) and 20261024050011_unfinished_workouts.sql
-- (unfinished_workouts) with the identity check for a day started or done.

create or replace function private.day_adjustment_compute(p_user uuid, p_date date, p_joint boolean default true)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r constant jsonb := private.readiness_rules();
  version_id uuid;
  version_block text;
  version_ends date;
  workout jsonb;
  workout_id uuid;
  check_in public.daily_check_ins%rowtype;
  sleep_minutes integer;
  recovery_score integer;
  recovery_confidence text;
  recovery_mode text;
  screening text := private.current_screening_outcome(p_user);
  targets jsonb;
  hold_c jsonb := jsonb_build_object('changes', '[]'::jsonb, 'sets_from', 0, 'sets_to', 0);
  reduce_c jsonb := hold_c;
  swap_c jsonb := hold_c;
  can_hold boolean := false;
  can_reduce boolean := false;
  unavailable text;
  assessment jsonb;
  kind text;
  chosen_c jsonb;
  options jsonb := '[]'::jsonb;
  cardio jsonb := null;
  safety text;
  band text;
  triggers text[];
  inputs jsonb;
  states jsonb;
  joint_arr jsonb := '[]'::jsonb;
  joint_c jsonb;
  exercise_options jsonb := '[]'::jsonb;
  report_route text;
  report_severe boolean;
  report_codes text[];
  states_full jsonb;
  merge_arr jsonb := '[]'::jsonb;
  joint_only boolean := false;
  hold_route text;
  hold_severe boolean;
  hold_codes text[];
begin
  select v.id, v.block_kind, v.ends_on into version_id, version_block, version_ends
  from public.training_plan_versions v where v.user_id = p_user and v.status = 'active' limit 1;
  workout := case when version_id is null then null
    else private.planned_workout_for_date(p_user, p_date) end;
  workout_id := (workout ->> 'id')::uuid;
  states_full := private.joint_states_detail(p_user, p_date);
  states := coalesce((select jsonb_agg(t.s - 'hold_codes' - 'hold_severe' order by t.n)
    from jsonb_array_elements(states_full) with ordinality as t(s, n)), '[]'::jsonb);

  select * into check_in from public.daily_check_ins c
  where c.user_id = p_user and c.local_date = p_date and c.superseded_at is null;
  select h.sleep_minutes into sleep_minutes from public.daily_health_summaries h
  where h.user_id = p_user and h.local_date = p_date and h.source_scope = 'healthkit';
  select m.recovery_score, m.data_confidence, m.scores_jsonb ->> 'recovery_mode'
  into recovery_score, recovery_confidence, recovery_mode
  from public.daily_computed_metrics m where m.user_id = p_user and m.local_date = p_date;

  unavailable := case
    when version_id is null then 'no_plan'
    when workout_id is null then 'rest_day'
    when exists (select 1 from public.workout_sessions s where s.user_id = p_user
        and s.planned_workout_id = any((select private.workout_identity_ids(p_user, workout_id))) and s.state = 'in_progress') then 'session_started'
    when exists (select 1 from public.workout_sessions s where s.user_id = p_user
        and s.planned_workout_id = any((select private.workout_identity_ids(p_user, workout_id)))
        and s.local_date = p_date and s.state = 'completed') then 'session_done'
    when version_block = 'next_session' and version_ends = p_date then 'coach_adjusted'
  end;
  -- On a day Coach already adjusted, the readiness kinds are not offered twice, but a joint that is held,
  -- limited or on watch still changes the exercises start_workout will create for that day.
  joint_only := coalesce(unavailable = 'coach_adjusted', false);

  if workout_id is not null then
    targets := private.next_session_targets(p_user);
    hold_c := private.day_adjustment_changes(p_user, workout_id, 'hold_load', targets);
    reduce_c := private.day_adjustment_changes(p_user, workout_id, 'reduce_sets', targets);
    swap_c := private.day_adjustment_changes(p_user, workout_id, 'swap_to_easy_cardio', targets);
    can_hold := jsonb_array_length(hold_c -> 'changes') > 0;
    can_reduce := (reduce_c ->> 'sets_to')::integer < (reduce_c ->> 'sets_from')::integer;
    exercise_options := private.joint_options(p_user, workout_id, states);
    joint_arr := private.joint_changes(p_user, workout_id, states, hold_c -> 'changes');
  end if;
  -- A joint that is held, limited or on watch changes the exercises it touches in every kind (the
  -- stricter value per exercise wins), and alone as the joint_adjust kind.
  -- A client that does not declare support for joint changes (p_joint false) is offered the readiness kinds
  -- as they were, without them: it could not show a left-out or swapped exercise, and what it accepts is
  -- what it was shown. joint_adjust, below, is the same for every client.
  if p_joint then merge_arr := joint_arr; end if;
  hold_c := private.day_changes_merged(hold_c, merge_arr);
  reduce_c := private.day_changes_merged(reduce_c, merge_arr);
  swap_c := private.day_changes_merged(swap_c, merge_arr);
  joint_c := private.day_changes_merged(jsonb_build_object('changes', '[]'::jsonb,
    'sets_from', (swap_c ->> 'sets_from')::integer, 'sets_to', (swap_c ->> 'sets_from')::integer),
    joint_arr);

  assessment := private.readiness_assessment(check_in.id is not null, check_in.sleep_quality::integer,
    check_in.energy::integer, check_in.soreness::integer, check_in.mood::integer,
    check_in.pain_severity::integer, check_in.available_to_train, sleep_minutes, recovery_score,
    recovery_confidence, recovery_mode, can_hold, can_reduce);
  safety := assessment ->> 'safety_route';
  band := assessment ->> 'band';
  triggers := array(select jsonb_array_elements_text(assessment -> 'triggers'));
  -- A pain report that routes out (a red flag, or a severity of 7 or more) gives the day a safety route
  -- just as a check-in pain of 7 or more does, even with no check-in, on a rest day or after the session
  -- started: from reports dated today or stored today (a phone's date can differ from the server's), and
  -- on every later day while the area stays held on an urgent or clinician_today outcome, until the
  -- athlete's own clearance; a clearance recorded later the same day ends today's route for that area too
  -- (only reports of an area still held count). A hold on a clinician outcome gives no route on later
  -- days, only a reminder in the day's words. The strictest route wins.
  select (array['clinician', 'clinician_today', 'urgent'])[max(
      case pr.outcome when 'urgent' then 3 when 'clinician_today' then 2 else 1 end)],
    coalesce(bool_or(pr.severity >= (private.pain_rules() ->> 'clinician_today_from')::integer), false)
  into report_route, report_severe
  from public.pain_reports pr
  where pr.user_id = p_user and pr.outcome in ('urgent', 'clinician_today', 'clinician')
    and (pr.local_date = p_date or private.local_day_of(p_user, pr.created_at) = p_date)
    and exists (select 1 from jsonb_array_elements(states_full) hs
      where hs ->> 'area' = pr.area and hs ->> 'state' = 'held');
  report_codes := array(select distinct 'red_flag:' || f from public.pain_reports pr,
    unnest(pr.red_flags) f
    where pr.user_id = p_user and pr.outcome in ('urgent', 'clinician_today', 'clinician')
      and (pr.local_date = p_date or private.local_day_of(p_user, pr.created_at) = p_date)
      and exists (select 1 from jsonb_array_elements(states_full) hs
        where hs ->> 'area' = pr.area and hs ->> 'state' = 'held')
    order by 1);
  select (array['clinician_today', 'urgent'])[max(case h ->> 'hold_outcome' when 'urgent' then 2 else 1 end)],
    coalesce(bool_or((h ->> 'hold_severe')::boolean), false),
    array(select distinct 'red_flag:' || c from jsonb_array_elements(states_full) h2,
      jsonb_array_elements_text(h2 -> 'hold_codes') c
      where h2 ->> 'state' = 'held' and h2 ->> 'hold_outcome' in ('urgent', 'clinician_today') order by 1)
  into hold_route, hold_severe, hold_codes
  from jsonb_array_elements(states_full) h
  where h ->> 'state' = 'held' and h ->> 'hold_outcome' in ('urgent', 'clinician_today');
  if hold_route is not null and (report_route is null
      or private.safety_route_rank(hold_route) > private.safety_route_rank(report_route)) then
    report_route := hold_route;
  end if;
  report_severe := coalesce(report_severe, false) or coalesce(hold_severe, false);
  report_codes := report_codes || coalesce(hold_codes, '{}'::text[]);
  if report_route is not null then
    if safety is null
       or private.safety_route_rank(report_route) > private.safety_route_rank(safety) then
      safety := report_route;
    end if;
    triggers := array(select distinct t from unnest(
      case when assessment ->> 'safety_route' is not null then array['pain_severe']
        else '{}'::text[] end
      || report_codes
      || case when report_severe then array['pain_severe'] else '{}'::text[] end) t order by t);
    band := 'red';
  end if;
  kind := case when unavailable is not null or safety is not null then 'none'
    else assessment ->> 'kind' end;
  -- A joint state changes the session even on a day the readiness rules ask for nothing, unless the
  -- athlete said they cannot train.
  if kind = 'none' and (unavailable is null or joint_only) and safety is null
     and coalesce(check_in.available_to_train, true)
     and jsonb_array_length(joint_c -> 'changes') > 0 then
    kind := 'joint_adjust';
  end if;

  chosen_c := case kind when 'hold_load' then hold_c when 'reduce_sets' then reduce_c
    when 'swap_to_easy_cardio' then swap_c when 'joint_adjust' then joint_c else
      jsonb_build_object('changes', '[]'::jsonb, 'sets_from', (swap_c ->> 'sets_from')::integer,
        'sets_to', (swap_c ->> 'sets_from')::integer) end;

  cardio := jsonb_build_object('minutes_min', (r -> 'easy_cardio_minutes' ->> 0)::integer,
    'minutes_max', (r -> 'easy_cardio_minutes' ->> 1)::integer, 'effort', 'easy',
    'talk_test', true, 'vigorous_allowed', false);

  -- What the athlete may choose themselves: every kind that would change today's session, unless
  -- the day is unavailable, carries a safety route or the athlete said they cannot train.
  if (unavailable is null or joint_only) and safety is null
     and coalesce(check_in.available_to_train, true) and workout_id is not null then
    if can_hold and not joint_only then
      options := options || jsonb_build_object('kind', 'hold_load',
        'explanation', private.day_adjustment_explanation(band, 'hold_load', '{}', null,
          hold_c -> 'changes', false, null),
        'sets_total_to', (hold_c ->> 'sets_to')::integer, 'changes', hold_c -> 'changes',
        'cardio', null);
    end if;
    if can_reduce and not joint_only then
      options := options || jsonb_build_object('kind', 'reduce_sets',
        'explanation', private.day_adjustment_explanation(band, 'reduce_sets', '{}', null,
          reduce_c -> 'changes', false, null),
        'sets_total_to', (reduce_c ->> 'sets_to')::integer, 'changes', reduce_c -> 'changes',
        'cardio', null);
    end if;
    if (swap_c ->> 'sets_from')::integer > 0 and not joint_only then
      options := options || jsonb_build_object('kind', 'swap_to_easy_cardio',
        'explanation', private.day_adjustment_explanation(band, 'swap_to_easy_cardio', '{}', null,
          swap_c -> 'changes', false, null),
        'sets_total_to', 0, 'changes', swap_c -> 'changes', 'cardio', cardio);
    end if;
    if jsonb_array_length(joint_c -> 'changes') > 0 then
      options := options || jsonb_build_object('kind', 'joint_adjust',
        'explanation', private.day_adjustment_explanation(band, 'joint_adjust', '{}', null,
          joint_c -> 'changes', false, null),
        'sets_total_to', (joint_c ->> 'sets_to')::integer, 'changes', joint_c -> 'changes',
        'cardio', null);
    end if;
  end if;

  inputs := jsonb_build_object('check_in_id', check_in.id, 'check_in_revision', check_in.revision,
    'sleep_minutes', sleep_minutes, 'recovery_score', recovery_score,
    'data_confidence', recovery_confidence, 'recovery_mode', recovery_mode,
    'screening', screening, 'joint_states', states);

  return jsonb_build_object(
    'plan_version_id', version_id,
    'inputs', inputs,
    'payload', jsonb_build_object(
      'schema_version', '1.1',
      'local_date', p_date,
      'band', band,
      'triggers', to_jsonb(triggers),
      'kind', kind,
      'changes', chosen_c -> 'changes',
      'explanation', private.day_adjustment_explanation(band, kind, triggers, safety,
        chosen_c -> 'changes', true, unavailable)
        || case when safety is null then private.persistent_sentence(states)
          || private.hold_reminder(states, chosen_c -> 'changes') else '' end,
      'status', case when kind = 'none' then 'none' else 'proposed' end,
      'available', unavailable is null or kind = 'joint_adjust',
      'unavailable_reason', case when kind = 'joint_adjust' then null else unavailable end,
      'safety_route', safety,
      'confidence', assessment -> 'confidence',
      'missing', assessment -> 'missing',
      'cardio', case when kind = 'swap_to_easy_cardio' then cardio end,
      'planned_workout_id', workout_id,
      'workout_name', workout ->> 'name',
      'sets_total_from', (swap_c ->> 'sets_from')::integer,
      'sets_total_to', (chosen_c ->> 'sets_to')::integer,
      'previous_answer', null,
      'answered_at', null,
      'rules_version', r ->> 'version',
      'origin', null,
      'options', options,
      'signals', jsonb_build_object('recovery_score', recovery_score,
        'recovery_confidence', recovery_confidence, 'recovery_mode', recovery_mode,
        'recovery_low', (assessment ->> 'recovery_low')::boolean, 'sleep_minutes', sleep_minutes),
      'joint_states', states,
      'exercise_joint_options', exercise_options));
end $$;

create or replace function private.unfinished_workouts(p_user uuid, p_today date)
returns table (
  session_id uuid,
  planned_workout_id uuid,
  workout_name text,
  local_date date,
  started_at timestamptz,
  client_revision integer,
  logged_sets integer,
  total_sets integer,
  first_set_at timestamptz,
  last_set_at timestamptz,
  save_by date
) language sql stable set search_path = '' as $$
  select s.id, s.planned_workout_id, w.name, s.local_date,
    coalesce(s.actual_started_at, s.started_at), s.client_revision,
    t.logged, t.total, t.first_at, t.last_at, s.local_date + 7
  from public.workout_sessions s
  join public.planned_workouts w on w.id = s.planned_workout_id and w.user_id = s.user_id
  cross join lateral (
    select count(*) filter (where e.completed)::integer as logged,
      count(*)::integer as total,
      min(coalesce(e.started_at, e.completed_at)) filter (where e.completed) as first_at,
      max(coalesce(e.completed_at, e.started_at)) filter (where e.completed) as last_at
    from public.exercise_sets e
    join public.exercise_performances p on p.id = e.exercise_performance_id
    where p.workout_session_id = s.id
  ) t
  where s.user_id = p_user
    and s.state = 'abandoned'
    and s.local_date between p_today - 28 and p_today - 1
    and t.logged > 0
    and private.workout_closed_as_stale(s.id)
    and not exists (
      select 1 from public.workout_sessions c
      where c.user_id = s.user_id and c.state = 'completed'
        and c.planned_workout_id = any((select private.workout_identity_ids(s.user_id, s.planned_workout_id)))
        and c.local_date = s.local_date);
$$;

-- 7. Training hub 1.9 -----------------------------------------------------------------------------------------
-- The 1.8 definition of 20261023140024_day_adjustments.sql plus the hunks above; every 1.8 key is still there.

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
)
select jsonb_build_object(
  'schema_version','1.9','period_days',greatest(7,least(period_days,365)),
  'local_today',(select today from local_day),
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
  'daily_load',private.daily_load(auth.uid(),(select today from local_day)),
  'next_targets',private.next_session_targets(auth.uid())
);
$$;

revoke all on function public.get_my_training_hub(integer) from public, anon, authenticated;
grant execute on function public.get_my_training_hub(integer) to authenticated;
