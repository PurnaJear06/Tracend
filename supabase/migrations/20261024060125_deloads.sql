-- B5-3: deloads (server side, rules version deload-v1).
--
-- A deload is one lighter week: the same exercises on the same days, half the sets, loads held,
-- effort at 7 or lower, then the regular plan returns by itself. It is persistent, so it goes
-- through the Coach proposal path (A8): a card, the athlete's approval, a new plan version, an audit
-- event, an undo for seven days. Nothing here applies a deload. This migration only works out when
-- one could help and says so; the athlete (or a talk with Coach) decides.
--
--   1. private.deload_rules()                 every number of the rules, in one place
--   2. private.is_deload_proposal             tells a deload block from another effort block
--   3. private.readiness_band_on              the readiness band a past day had (check-in days only)
--   4. private.deload_signals                 the three reasons, the suppressions, the status
--   5. private.training_guidance              what the Train screen and Coach are told (schema 1.0)
--   6. public.get_my_training_guidance_v1     the athlete's own today
--      public.get_training_guidance_for_v1    the same for the service role (Coach context)
--
-- The week's own numbers (length, set fraction, effort cap) are applied by the A8 builder
-- (_shared/coach_proposals/training.ts, from _shared/training/standard/deload.ts); they are kept
-- here too so one drift test pins both sides to the same values. Everything is additive: new
-- functions only. A deload never overrides a safety route or a joint that is held or limited: those
-- apply to the day's session on top of whatever plan is active (strictest wins), and a day with a
-- safety route is never offered a deload.

-- 1. The rules ----------------------------------------------------------------------------------------
-- weeks, set_fraction and rpe_cap describe the week and are applied by the builder. The rest decide
-- when one is suggested:
--   performance_drop   at least performance_drop_min_exercises exercises whose current B3 target is
--                      lower because of a stall or two sessions below the range
--   run_down           readiness band amber or red on at least run_down_min_days of the last
--                      run_down_window_days local days that have a check-in
--   block_done         weeks since the later of the plan's first activation and the last deload's end
--                      reached clamp(block_weeks, block_weeks_min, block_weeks_max), with at least
--                      block_done_min_completion_pct of the sessions the plan asks for completed in
--                      the last completion_window_days
-- Suppressed (no suggestion) while another block or a deload runs, within recent_deload_days of the
-- end of the last deload, under see_professional, and when fewer than active_week_windows_min of the
-- last active_week_windows weeks had a completed session (nothing to deload from).

create function private.deload_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"version":"deload-v1","weeks":1,"set_fraction":0.5,"rpe_cap":7,"performance_drop_min_exercises":2,"run_down_window_days":7,"run_down_min_days":4,"block_weeks_min":4,"block_weeks_max":8,"block_done_min_completion_pct":75,"completion_window_days":28,"recent_deload_days":28,"active_week_windows":4,"active_week_windows_min":3}'::jsonb;
$$;
revoke all on function private.deload_rules() from public, anon, authenticated;

-- 2. A deload block -----------------------------------------------------------------------------------
-- An effort block (intensity_or_phase with a level) is a deload when its payload says so
-- (training.intensity_level). A block approved before the builder wrote that key is recognised by the
-- title the builder gave it, "Deload until <date>".

create function private.is_deload_proposal(p_kind text, p_payload jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p_kind = 'intensity_or_phase'
    and coalesce(p_payload #>> '{training,intensity_level}',
      case when p_payload #>> '{training,title}' like 'Deload until %' then 'deload' end) = 'deload',
    false);
$$;
revoke all on function private.is_deload_proposal(text, jsonb) from public, anon, authenticated;

-- 3. The band a past day had ---------------------------------------------------------------------------
-- The same assessment today's adjustment runs, on that day's current check-in, that day's sleep and the
-- stored recovery score (nothing is scored here). Null when the day has no check-in.

create function private.readiness_band_on(p_user uuid, p_day date)
returns text language sql stable security definer set search_path = '' as $$
  select private.readiness_assessment(true, c.sleep_quality::integer, c.energy::integer,
    c.soreness::integer, c.mood::integer, c.pain_severity::integer, c.available_to_train,
    (select h.sleep_minutes from public.daily_health_summaries h
      where h.user_id = p_user and h.local_date = p_day and h.source_scope = 'healthkit'),
    m.recovery_score, m.data_confidence, m.scores_jsonb ->> 'recovery_mode', false, false) ->> 'band'
  from public.daily_check_ins c
  left join public.daily_computed_metrics m on m.user_id = c.user_id and m.local_date = c.local_date
  where c.user_id = p_user and c.local_date = p_day and c.superseded_at is null;
$$;
revoke all on function private.readiness_band_on(uuid, date) from public, anon, authenticated;

-- 4. Signals ---------------------------------------------------------------------------------------------
-- Returns {status, reasons, last_ended_on, weeks_since, proposal_id, suppressed_by}:
--   status         running    a deload block is the active plan version (proposal_id is its proposal)
--                  pending    the athlete has an open, unexpired deload proposal (proposal_id)
--                  suggested  at least one reason, nothing suppresses it
--                  not_due    otherwise
--   reasons        performance_drop, run_down, block_done (empty while suppressed or running)
--   last_ended_on  the day the newest deload ended (an early end counts as ending today); an undone
--                  deload never ran and is not counted
--   weeks_since    whole weeks since the later of the plan's first activation and last_ended_on
--   suppressed_by  screening, block_running, recent_deload, not_enough_training, no_plan or null
-- Screening (see_professional) and another running block also hide an open proposal: it can no longer
-- be approved. A recent deload or too little training only stops a new suggestion; a proposal the
-- athlete asked for stays visible.

create function private.deload_signals(p_user uuid, p_date date)
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
    and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)
  order by cp.created_at desc, cp.id desc limit 1;

  select max(least(v.ends_on, p_date)) into last_ended
  from public.training_plan_versions v
  join public.change_proposals cp on cp.id = v.source_proposal_id and cp.user_id = v.user_id
  where v.user_id = p_user and v.block_kind = 'intensity' and v.status = 'superseded'
    and cp.undone_at is null and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload);

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

-- 5. What the athlete and Coach are told -------------------------------------------------------------------
-- {schema_version, local_date, safety_route, deload}. A day with a safety route (a pain of 7 or more, a
-- red flag, a held area on an urgent or same-day outcome) is never offered a deload; the day
-- adjustment's own route decides. Read-only: it stores nothing and makes no scores.

create function private.training_guidance(p_user uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  adjustment jsonb := private.day_adjustment_compute(p_user, p_date, true) -> 'payload';
  route text := adjustment ->> 'safety_route';
  deload jsonb := private.deload_signals(p_user, p_date);
begin
  if false and route is not null and deload ->> 'status' = 'suggested' then
    deload := deload || jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb,
      'suppressed_by', 'safety_route');
  end if;
  return jsonb_build_object('schema_version', '1.0', 'local_date', p_date,
    'safety_route', route, 'deload', deload);
end $$;
revoke all on function private.training_guidance(uuid, date) from public, anon, authenticated;

-- 6. The two readers ------------------------------------------------------------------------------------------

create function public.get_my_training_guidance_v1(local_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if get_my_training_guidance_v1.local_date is distinct from private.local_date_for(uid) then
    raise exception 'only today can be read' using errcode = '22023';
  end if;
  return private.training_guidance(uid, get_my_training_guidance_v1.local_date);
end $$;
revoke all on function public.get_my_training_guidance_v1(date) from public, anon, authenticated;
grant execute on function public.get_my_training_guidance_v1(date) to authenticated;

create function public.get_training_guidance_for_v1(p_user_id uuid, p_local_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if p_user_id is null or p_local_date is distinct from private.local_date_for(p_user_id) then
    raise exception 'only the athlete''s own today can be read' using errcode = '22023';
  end if;
  return private.training_guidance(p_user_id, p_local_date);
end $$;
revoke all on function public.get_training_guidance_for_v1(uuid, date) from public, anon, authenticated;
grant execute on function public.get_training_guidance_for_v1(uuid, date) to service_role;
