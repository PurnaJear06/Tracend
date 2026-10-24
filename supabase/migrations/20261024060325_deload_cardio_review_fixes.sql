-- B5-3 and B5-4 review round 1: fixes to the deload and cardio functions, and the way B3 meets a deload.
--
-- Forward-only and additive: every function below is replaced with `create or replace` (same
-- signature, same owner, so its grants stay), and each is its latest earlier definition plus the
-- intended hunks only (pinned by deload_cardio_review_test.ts). No table, column or type changes.
--
--   H1  next_session_targets   While the active plan version is a deload week, a target never steps up:
--                              add_load becomes hold with reason deload, at the last working load. The app
--                              prefills from this target before the plan's own load.
--   H2  next_session_targets   A session logged under a deload week's plan version is marked adjusted, the way
--                              B4 marks a session done under an accepted answer: it is never evidence for a
--                              stall or for lowering a load, during the week or after it.
--   M1  training_guidance      A pending deload proposal is withheld on a day with a safety route (no proposal
--                              id, not_due, suppressed_by safety_route), like a suggested one.
--      respond_to_coach_proposal_v1   refuses (55000) to approve a deload on a day with a safety route.
--   M2  deload_rules, deload_signals   A deload proposal the athlete declined, or that ran out unanswered,
--                              holds new suggestions back for declined_cooldown_days (14) from that day:
--                              suppressed_by declined_recently. A proposal the athlete asked for through
--                              Coach and declined counts the same way (nothing tells the two apart).
--                              Only a decline or a timeout counts: a card a newer one replaced, or one
--                              expired for another reason (an audit reason other than expired), does not.
--      deload_signals         last_ended_on is the day the block-ended event was written, so a deload ended
--                              early keeps one end date (it used to move forward every day).
--   L1  cardio_week            vigorous_allowed is false when today's check-in says not available to train.
--   L2  cardio_week            vigorous_allowed needs a screening row: no row is not cleared for hard cardio.
--                              current_screening_outcome itself is unchanged (no row reads cleared elsewhere).
--   L3  cardio_rules           five more HealthKit cardio workout names.
--   L4  deload_signals         A pending deload proposal built on a plan version that is no longer current is
--                              stale, not pending: it is not offered (approval would expire it).
--
-- training_guidance computes next_session_targets (through the day adjustment and the deload signals) and
-- the screening outcome more than once per read; passing them in would change several signatures, so it is
-- left as it is. Run EXPLAIN ANALYZE on get_training_guidance_for_v1 before the Coach reads it every turn.

-- 1. The rules (M2: the cool-down after a declined or expired proposal) -----------------------------------

create or replace function private.deload_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"version":"deload-v1","weeks":1,"set_fraction":0.5,"rpe_cap":7,"performance_drop_min_exercises":2,"run_down_window_days":7,"run_down_min_days":4,"block_weeks_min":4,"block_weeks_max":8,"block_done_min_completion_pct":75,"completion_window_days":28,"recent_deload_days":28,"declined_cooldown_days":14,"active_week_windows":4,"active_week_windows_min":3}'::jsonb;
$$;
revoke all on function private.deload_rules() from public, anon, authenticated;

-- 2. Deload signals (M2, L4) ------------------------------------------------------------------------------

create or replace function private.deload_signals(p_user uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r constant jsonb := private.deload_rules();
  version public.training_plan_versions%rowtype;
  first_activation date;
  last_ended date;
  anchor date;
  weeks integer;
  reasons text[] := '{}';
  suppressed text;
  running uuid;
  pending uuid;
  declined_on date;
  tz constant text := coalesce((select a.timezone from public.user_accounts a
    join pg_catalog.pg_timezone_names z on z.name = a.timezone where a.id = p_user), 'UTC');
  dropped integer;
  run_down integer;
  completed integer;
  active_windows integer;
begin
  select * into version from public.training_plan_versions v
  where v.user_id = p_user and v.status = 'active';
  if not found then
    return jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb, 'last_ended_on', null,
      'weeks_since', null, 'proposal_id', null, 'suppressed_by', 'no_plan');
  end if;

  select cp.id into running from public.change_proposals cp
  where cp.id = version.source_proposal_id and cp.user_id = p_user
    and version.block_kind = 'intensity' and version.ends_on >= p_date
    and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload);

  select cp.id into pending from public.change_proposals cp
  where cp.user_id = p_user and cp.schema_version = '3.0' and cp.status = 'pending'
    and cp.expires_at > statement_timestamp()
    and cp.basis ->> 'training_version_id' = version.id::text
    and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)
  order by cp.created_at desc, cp.id desc limit 1;

  -- The day a deload really ended: the day the block-ended event was written (a block ended early
  -- ends that day and stays ended that day), never later than its own last day.
  select max(least(v.ends_on, coalesce((select (a.created_at at time zone tz)::date
      from public.audit_events a where a.user_id = p_user
        and a.action_code = 'coach_proposal_block_ended'
        and a.metadata ->> 'ended_version_id' = v.id::text
      order by a.created_at desc limit 1), p_date))) into last_ended
  from public.training_plan_versions v
  join public.change_proposals cp on cp.id = v.source_proposal_id and cp.user_id = v.user_id
  where v.user_id = p_user and v.block_kind = 'intensity' and v.status = 'superseded'
    and cp.undone_at is null and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload);

  -- A deload proposal the athlete declined, or that ran out unanswered, holds new suggestions back
  -- for declined_cooldown_days from that day. Only a decline or a timeout counts: a card a newer one
  -- replaced, or that expired for another reason (the plan or profile moved), did not run out.
  select max((e.happened at time zone tz)::date) into declined_on
  from (
    select cr.created_at as happened
    from public.change_proposals cp
    join public.change_responses cr on cr.proposal_id = cp.id and cr.user_id = cp.user_id
    where cp.user_id = p_user and cp.schema_version = '3.0' and cp.status = 'rejected'
      and cr.action = 'reject' and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)
    union all
    select cp.expires_at
    from public.change_proposals cp
    where cp.user_id = p_user and cp.schema_version = '3.0' and cp.status in ('pending', 'expired')
      and cp.expires_at <= statement_timestamp()
      and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)
      and not exists (select 1 from public.change_proposals n
        where n.user_id = cp.user_id and n.schema_version = '3.0'
          and n.created_at > cp.created_at and n.created_at < cp.expires_at
          and (n.proposal_kind = cp.proposal_kind or n.proposal_payload ? 'training'))
      and not exists (select 1 from public.audit_events a
        where a.user_id = cp.user_id and a.target_type = 'change_proposal' and a.target_id = cp.id
          and a.action_code = 'coach_proposal_expired'
          and a.metadata ->> 'reason' is distinct from 'expired')
  ) e;

  -- The plan's own first day: a block is a plan of its own, so only a regular version has one.
  if version.restores_version_id is null then
    select min(coalesce(v.effective_date, v.approved_at::date)) into first_activation
    from public.training_plan_versions v
    where v.user_id = p_user and v.plan_id = version.plan_id;
  end if;
  anchor := greatest(first_activation, last_ended);
  weeks := case when anchor is null then null else greatest(0, p_date - anchor) / 7 end;

  select count(distinct t ->> 'exercise_key') into dropped
  from jsonb_array_elements(private.next_session_targets(p_user)) t
  where t ->> 'action' = 'lower' and t ->> 'reason' in ('stall', 'below_range');

  select count(*) into run_down
  from generate_series(0, (r ->> 'run_down_window_days')::integer - 1) k
  where private.readiness_band_on(p_user, p_date - k) in ('amber', 'red');

  select count(*) into completed from public.workout_sessions s
  where s.user_id = p_user and s.state = 'completed'
    and s.local_date between p_date - ((r ->> 'completion_window_days')::integer - 1) and p_date;

  select count(*) into active_windows
  from generate_series(0, (r ->> 'active_week_windows')::integer - 1) w
  where exists (select 1 from public.workout_sessions s
    where s.user_id = p_user and s.state = 'completed'
      and s.local_date between p_date - (w * 7 + 6) and p_date - w * 7);

  if dropped >= (r ->> 'performance_drop_min_exercises')::integer then
    reasons := array_append(reasons, 'performance_drop');
  end if;
  if run_down >= (r ->> 'run_down_min_days')::integer then
    reasons := array_append(reasons, 'run_down');
  end if;
  if weeks is not null
     and weeks >= least((r ->> 'block_weeks_max')::integer,
       greatest((r ->> 'block_weeks_min')::integer, version.block_weeks))
     and completed * 100 >= (r ->> 'block_done_min_completion_pct')::integer
       * version.sessions_per_week * ((r ->> 'completion_window_days')::integer / 7) then
    reasons := array_append(reasons, 'block_done');
  end if;

  suppressed := case
    when running is not null then null
    when private.current_screening_outcome(p_user) = 'see_professional' then 'screening'
    when version.ends_on is not null then 'block_running'
    when last_ended is not null and p_date - last_ended < (r ->> 'recent_deload_days')::integer
      then 'recent_deload'
    when declined_on is not null
      and p_date - declined_on < (r ->> 'declined_cooldown_days')::integer then 'declined_recently'
    when active_windows < (r ->> 'active_week_windows_min')::integer then 'not_enough_training'
  end;

  return jsonb_build_object(
    'status', case
      when running is not null then 'running'
      when suppressed in ('screening', 'block_running') then 'not_due'
      when pending is not null then 'pending'
      when suppressed is not null then 'not_due'
      when cardinality(reasons) > 0 then 'suggested'
      else 'not_due' end,
    'reasons', to_jsonb(case when suppressed is not null or running is not null
      then '{}'::text[] else reasons end),
    'last_ended_on', last_ended,
    'weeks_since', weeks,
    'proposal_id', case when suppressed in ('screening', 'block_running') then null
      else coalesce(running, pending) end,
    'suppressed_by', suppressed);
end $$;
revoke all on function private.deload_signals(uuid, date) from public, anon, authenticated;

-- 3. Cardio rules (L3) --------------------------------------------------------------------------------------

create or replace function private.cardio_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"version":"cardio-v1","weekly_floor_min":150,"weekly_upper_min":300,"vigorous_counts_as":2,"easy_minutes":[20,30],"easy_hr_reserve_max_pct":60,"vigorous_sessions_max":2,"lift_separation_hours":3,"workout_cap_min":180,"window_days":7,"min_summary_days":5,"stretch_goals":["fat_loss","recomposition"],"cardio_types":["WALKING","RUNNING","BIKING","HIKING","ELLIPTICAL","ROWING","SWIMMING","STAIR_CLIMBING","STAIRS","STEP_TRAINING","HAND_CYCLING","JUMP_ROPE","CARDIO_DANCE","MIXED_CARDIO","HIGH_INTENSITY_INTERVAL_TRAINING","WHEELCHAIR_WALK_PACE","WHEELCHAIR_RUN_PACE","CROSS_COUNTRY_SKIING","PADDLE_SPORTS","SOCIAL_DANCE"]}'::jsonb;
$$;
revoke all on function private.cardio_rules() from public, anon, authenticated;

-- 4. The cardio week (L1, L2) --------------------------------------------------------------------------------

create or replace function private.cardio_week(p_user uuid, p_date date, p_band text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r constant jsonb := private.cardio_rules();
  cleared constant boolean := private.current_screening_outcome(p_user) = 'cleared';
  window_from constant date := p_date - ((r ->> 'window_days')::integer - 1);
  summary_days integer;
  observed integer;
  goal text;
begin
  select count(*) into summary_days from public.daily_health_summaries h
  where h.user_id = p_user and h.source_scope = 'healthkit'
    and h.local_date between window_from and p_date;

  if summary_days >= (r ->> 'min_summary_days')::integer then
    select coalesce(floor(sum(extract(epoch from upper(m.span) - lower(m.span))) / 60), 0)::integer
    into observed
    from (
      select unnest(range_agg(tstzrange(w.started_at, least(w.ended_at,
        w.started_at + (r ->> 'workout_cap_min')::integer * interval '1 minute')))) as span
      from public.health_workout_references w
      where w.user_id = p_user and w.local_date between window_from and p_date
        and upper(w.activity_type) in (select jsonb_array_elements_text(r -> 'cardio_types'))
    ) m;
  end if;

  select g.goal_type::text into goal from public.user_goals g
  where g.id = private.active_goal_id(p_user);

  return jsonb_build_object(
    'target_min', (r ->> 'weekly_floor_min')::integer,
    'stretch_max', case when goal in (select jsonb_array_elements_text(r -> 'stretch_goals'))
      then (r ->> 'weekly_upper_min')::integer end,
    'done_min', observed,
    'intensity_known', false,
    'vigorous_allowed', cleared
      and exists (select 1 from public.onboarding_screenings o where o.user_id = p_user)
      and coalesce(p_band = 'green', false)
      and not exists (select 1 from public.daily_check_ins c
        where c.user_id = p_user and c.local_date = p_date and c.superseded_at is null
          and c.available_to_train is false)
      and not exists (
        select 1 from jsonb_array_elements(private.joint_states(p_user, p_date)) s
        where s ->> 'state' in ('held', 'limited')),
    'vigorous_sessions_max', case when cleared then (r ->> 'vigorous_sessions_max')::integer else 0 end,
    'vigorous_counts_as', (r ->> 'vigorous_counts_as')::integer,
    'lift_separation_hours', (r ->> 'lift_separation_hours')::integer,
    'easy_hr_reserve_max', (r ->> 'easy_hr_reserve_max_pct')::integer,
    'window_from', window_from,
    'window_to', p_date);
end $$;
revoke all on function private.cardio_week(uuid, date, text) from public, anon, authenticated;

-- 5. Guidance (M1) ---------------------------------------------------------------------------------------------

create or replace function private.training_guidance(p_user uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  adjustment jsonb := private.day_adjustment_compute(p_user, p_date, true) -> 'payload';
  route text := adjustment ->> 'safety_route';
  deload jsonb := private.deload_signals(p_user, p_date);
  withheld text := case when route is not null then 'safety_route'
    when private.current_screening_outcome(p_user) = 'see_professional' then 'screening' end;
begin
  if route is not null and deload ->> 'status' in ('suggested', 'pending') then
    deload := deload || jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb,
      'proposal_id', null, 'suppressed_by', 'safety_route');
  end if;
  return jsonb_build_object('schema_version', '1.1', 'local_date', p_date,
    'safety_route', route, 'deload', deload, 'cardio_withheld', withheld,
    'cardio_week', case when withheld is null
      then private.cardio_week(p_user, p_date, adjustment ->> 'band') end);
end $$;
revoke all on function private.training_guidance(uuid, date) from public, anon, authenticated;

-- 6. B3 meets a deload (H1, H2) ------------------------------------------------------------------------------

create or replace function private.next_session_targets(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
with rules as (
  select private.progression_rules() as r
), today as (
  select private.local_date_for(p_user) as d
), deloading as (
  -- The active plan version is a deload week that has not ended (the same test as the signals' running).
  select exists (
    select 1 from public.training_plan_versions v
    join public.change_proposals cp on cp.id = v.source_proposal_id and cp.user_id = v.user_id
    where v.user_id = p_user and v.status = 'active' and v.block_kind = 'intensity'
      and v.ends_on >= (select d from today)
      and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)) as active
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
    s.local_date, s.completed_at, s.id as session_id, p.planned_exercise_id as logged_exercise_id
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
    pf.pain_flag, pf.logged_exercise_id,
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
    bool_or(t.pain_flag) as pain,
    max(t.logged_exercise_id::text)::uuid as logged_exercise_id
  from topped t
  where t.load_kg is not distinct from t.top_load
  group by t.planned_exercise_id, t.session_id, t.local_date, t.completed_at, t.top_load
), marked as (
  -- Done under an accepted answer that lists this exercise (hold_load, reduce_sets or joint_adjust,
  -- B4 and B5), or one that limits its range for a joint: not evidence for lowering its load, and its
  -- planned set count is the answer's (an easy-cardio answer keeps the plan's sets). An exercise the
  -- answer left alone is judged as ever, however easy the rest of the session was. A session done under
  -- a deload week's plan version is held to the same rule: it is a lighter week on purpose, so it is
  -- never evidence for lowering a load (its planned set count stays the plan's, so the first session
  -- after the week reads as incomplete and holds).
  select s.*, ch.listed is not null or dl.deload is not null as adjusted, ch.sets_planned
  from sessions s
  join public.workout_sessions ws on ws.id = s.session_id and ws.user_id = p_user
  left join public.day_adjustments a on a.id = ws.day_adjustment_id and a.user_id = p_user
    and a.status = 'accepted'
  left join lateral (
    select true as listed,
      case when a.kind <> 'swap_to_easy_cardio' then (c ->> 'sets_to')::integer end as sets_planned
    from jsonb_array_elements(a.changes) c
    where c ->> 'planned_exercise_id' = s.logged_exercise_id::text
      and (a.kind in ('hold_load', 'reduce_sets', 'joint_adjust')
        or c ->> 'joint_action' = 'limit') limit 1) ch on true
  left join lateral (
    select true as deload from public.training_plan_versions pv
    join public.change_proposals cp on cp.id = pv.source_proposal_id and cp.user_id = pv.user_id
    where pv.id = ws.plan_version_id and pv.user_id = p_user and pv.block_kind = 'intensity'
      and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)) dl on true
), ranked as (
  select s.*, row_number() over (partition by s.planned_exercise_id
    order by s.local_date desc, s.completed_at desc) as rn
  from marked s
), recent as (
  select r.planned_exercise_id, max(r.local_date) filter (where r.rn = 1) as latest_date,
    max(r.completed_at) filter (where r.rn = 1) as latest_completed_at,
    jsonb_agg(jsonb_build_object(
      'local_date', r.local_date, 'load_kg', r.top_load, 'sets', r.sets,
      'min_reps', r.min_reps, 'total_reps', r.total_reps, 'min_rir', r.min_rir,
      'effort_known', r.effort_known, 'pain', r.pain, 'adjusted', r.adjusted,
      'sets_planned', r.sets_planned) order by r.rn) as sess
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
  ) q
  -- During a deload week a target never steps up: a step in load becomes a hold at the last
  -- working load.
  cross join lateral (
    select case when (select active from deloading) and q.decision ->> 'action' = 'add_load'
      then q.decision || jsonb_build_object('action', 'hold', 'reason', 'deload',
        'load_kg', rc.sess -> 0 -> 'load_kg',
        'reps', least(pl.rep_max, greatest(pl.rep_min, (rc.sess -> 0 ->> 'min_reps')::integer)))
      else q.decision end as decision
  ) d
  where d.decision is not null
) x;
$$;
revoke all on function private.next_session_targets(uuid) from public, anon, authenticated;

-- 7. Approval (M1) ---------------------------------------------------------------------------------------------

create or replace function public.respond_to_coach_proposal_v1(
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
    -- A day with a safety route is never offered a deload, so one cannot be approved on it.
    if private.is_deload_proposal(proposal.proposal_kind, proposal.proposal_payload)
       and private.day_adjustment_compute(auth.uid(), today, true) -> 'payload' ->> 'safety_route'
         is not null then
      raise exception 'a deload cannot be approved on a day with a safety route'
        using errcode = '55000';
    end if;

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
