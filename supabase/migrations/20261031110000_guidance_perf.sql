-- Guidance performance (M3 of the deload and cardio review): get_training_guidance_for_v1 took about
-- 1.7 s on a cold connection and 0.25 to 0.7 s on a warm one, with next to no data behind it.
--
-- The cost was one line, repeated. Every function that reads the athlete's time zone checked it with
-- `join pg_catalog.pg_timezone_names z on z.name = a.timezone`. That view lists all the zones the server
-- knows by reading the tz database, about 56 ms on every call (the first call on a connection also loads the
-- files), and Postgres cannot push the name filter into it. One guidance read made four or five such calls
-- (the date check, next_session_targets twice, deload_signals, local_day_of); the Coach tools' local_day
-- made one per row.
--
-- The fix keeps the same test, "the stored name is a zone the server knows, else UTC", and answers it from
-- a small table of the names (private.timezone_names, filled here from the view) first. A name not in the
-- table (a new zone after a tz update, a case variant, an abbreviation) still goes to the view, so the
-- answer is the view's answer in every case, only fast for every name an athlete can store (set_my_timezone
-- stores nothing else). Nothing else changes: each function below is its latest earlier definition with the
-- join replaced by private.known_timezone (pinned by guidance_perf_test.ts), and the results are the same.
--
--   private.timezone_names   new table: the zone names, one row each
--   private.known_timezone   new: true when the name is a zone the server knows
--   private.local_date_for   private.local_day_of   private.local_day   private.user_timezone
--   private.deload_signals   the join becomes private.known_timezone
--
-- next_session_targets reads today through local_date_for, so it gets faster with no change of its own. The
-- functions that still join the view directly (the hub, the workout functions, the goal date in the Coach
-- plan context) are left to the changes that replace them.

-- 1. The zone names ----------------------------------------------------------------------------------------

create table private.timezone_names (
  name text primary key
);
alter table private.timezone_names enable row level security;
alter table private.timezone_names force row level security;
revoke all on private.timezone_names from public, anon, authenticated;

insert into private.timezone_names (name)
select z.name from pg_catalog.pg_timezone_names z;

-- A name in the table is a name in the view. Any other name is asked of the view itself, so the answer
-- never differs from the view's; the CASE keeps the slow read to the names the table does not hold.
create function private.known_timezone(zone text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from private.timezone_names t where t.name = zone) then true
    else exists (select 1 from pg_catalog.pg_timezone_names z where z.name = zone) end;
$$;
revoke all on function private.known_timezone(text) from public, anon, authenticated;

-- 2. The readers of the athlete's time zone ----------------------------------------------------------------

create or replace function private.local_date_for(target_user_id uuid)
returns date language sql stable set search_path = '' as $$
  select (statement_timestamp() at time zone coalesce((
    select a.timezone from public.user_accounts a
    where a.id = target_user_id and private.known_timezone(a.timezone)), 'UTC'))::date;
$$;

create or replace function private.local_day_of(p_user uuid, p_at timestamptz)
returns date language sql stable set search_path = '' as $$
  select (p_at at time zone coalesce((
    select a.timezone from public.user_accounts a
    where a.id = p_user and private.known_timezone(a.timezone)), 'UTC'))::date;
$$;

create or replace function private.local_day(p_user uuid, p_at timestamptz)
returns date language sql stable set search_path = '' as $$
  select (p_at at time zone coalesce((
    select a.timezone from public.user_accounts a
    where a.id = p_user and private.known_timezone(a.timezone)), 'UTC'))::date;
$$;

create or replace function private.user_timezone(p_user uuid)
returns text language sql stable set search_path = '' as $$
  select coalesce((
    select a.timezone from public.user_accounts a
    where a.id = p_user and private.known_timezone(a.timezone)), 'UTC');
$$;

-- 3. Deload signals ----------------------------------------------------------------------------------------

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
    where a.id = p_user and private.known_timezone(a.timezone)), 'UTC');
  dropped integer;
  run_down integer;
  completed integer;
  active_windows integer;
begin
  select * into version from public.training_plan_versions v
  where v.user_id = p_user and v.status = 'active';
  if not found then
    return jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb, 'last_ended_on', null,
      'weeks_since', null, 'proposal_id', null, 'proposal_origin', null, 'ends_on', null,
      'suppressed_by', 'no_plan');
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
  -- replaced, or that expired for another reason (the plan or profile moved), did not run out. An
  -- undone deload counts the same, from the day it was undone (the athlete took it back).
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
    union all
    select cp.undone_at
    from public.change_proposals cp
    where cp.user_id = p_user and cp.schema_version = '3.0' and cp.undone_at is not null
      and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)
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
    -- Who made the proposal: only the rules' suggestion (training-proposals) carries DELOAD_SIGNALS in
    -- its evidence, so any other deload proposal is one the athlete asked Coach for.
    'proposal_origin', case when suppressed in ('screening', 'block_running') then null
      else (select case when cp.evidence @> '[{"code": "DELOAD_SIGNALS"}]'::jsonb
          then 'tracend' else 'coach' end
        from public.change_proposals cp
        where cp.id = coalesce(running, pending) and cp.user_id = p_user) end,
    'ends_on', case when running is not null then version.ends_on end,
    'suppressed_by', suppressed);
end $$;
revoke all on function private.deload_signals(uuid, date) from public, anon, authenticated;
