-- Training guidance 1.2 (additive) and three fixes found in review of the Train card (PR #178).
--
-- Forward-only: each function is replaced with `create or replace` (same signature, same owner, so its
-- grants stay) and is its latest earlier definition plus the intended hunks only (pinned by
-- deload_origin_test.ts).
--
--   deload_signals   adds proposal_origin ('tracend' when the proposal carries the DELOAD_SIGNALS evidence
--                    the rules' suggestion adds, else 'coach': the athlete asked Coach for it) and ends_on
--                    (the last day of a running deload) to the deload part. A deload the athlete undid now
--                    holds new suggestions back for declined_cooldown_days from the day it was undone, as a
--                    declined one does (suppressed_by declined_recently).
--   training_guidance  schema_version 1.2; a route day also clears proposal_origin.
--   persist_coach_proposal_v1  takes a per-athlete transaction lock before it replaces an open proposal and
--                    stores the new one, so two stores cannot interleave.
--   persist_suggested_deload_v1  (new, service role only) the store the rules' deload suggestion uses: under
--                    the same lock it refuses (SQLSTATE TP001) when a current plan change the athlete has
--                    not answered is open, because storing a training proposal would expire it, then calls
--                    persist_coach_proposal_v1. The check and the store cannot be split by another store.

-- 1. Deload signals --------------------------------------------------------------------------------------------

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

-- 2. Guidance 1.2 ----------------------------------------------------------------------------------------------

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
      'proposal_id', null, 'proposal_origin', null, 'suppressed_by', 'safety_route');
  end if;
  return jsonb_build_object('schema_version', '1.2', 'local_date', p_date,
    'safety_route', route, 'deload', deload, 'cardio_withheld', withheld,
    'cardio_week', case when withheld is null
      then private.cardio_week(p_user, p_date, adjustment ->> 'band') end);
end $$;
revoke all on function private.training_guidance(uuid, date) from public, anon, authenticated;

-- 3. One store at a time per athlete ---------------------------------------------------------------------------

create or replace function public.persist_coach_proposal_v1(
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_rationale text,
  p_benefit text,
  p_downside text,
  p_confidence text,
  p_evidence jsonb,
  p_before jsonb,
  p_after jsonb,
  p_payload jsonb,
  p_basis jsonb,
  p_ends_on date,
  p_expires_in_hours integer,
  p_source_message_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  new_id uuid;
  new_expires timestamptz;
  nutrition jsonb := p_payload -> 'nutrition';
  summary_training jsonb;
  stored_basis jsonb;
begin
  if p_user_id is null or not exists (select 1 from public.user_accounts where id = p_user_id) then
    raise exception 'account not found' using errcode = 'P0002';
  end if;
  -- One proposal is stored at a time per athlete: replacing an open one (below) must not race a second
  -- store (two taps, or a tap and Coach), which could leave two open proposals.
  perform pg_advisory_xact_lock(hashtextextended('tracend.coach_proposal_store:' || p_user_id::text, 0));
  if p_kind is null or p_title is null or length(p_title) not between 1 and 120
    or p_rationale is null or length(p_rationale) not between 1 and 2000
    or p_benefit is null or length(p_benefit) not between 1 and 1000
    or p_downside is null or length(p_downside) not between 1 and 1000
    or p_confidence not in ('low', 'medium', 'high')
    or jsonb_typeof(p_evidence) is distinct from 'array'
    or jsonb_typeof(p_before) is distinct from 'object'
    or jsonb_typeof(p_after) is distinct from 'object'
    or jsonb_typeof(p_basis) is distinct from 'object'
    or p_expires_in_hours is null or p_expires_in_hours not between 1 and 168 then
    raise exception 'coach proposal is invalid' using errcode = '22023';
  end if;
  summary_training := jsonb_build_object('proposal_kind', p_kind, 'title', p_title);
  if not private.is_valid_coach_proposal_row(p_kind, summary_training,
    coalesce(nutrition - 'rationale', '{}'::jsonb), p_payload) then
    raise exception 'coach proposal is invalid' using errcode = '22023';
  end if;
  if p_payload ? 'training' and not private.coach_training_uses_catalog(p_payload -> 'training') then
    raise exception 'coach proposal is invalid' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.user_profiles
    where user_id = p_user_id and eligible is true and adult_attested_at is not null
  ) then
    raise exception 'eligible adult profile required' using errcode = '22023';
  end if;
  if nutrition is not null
    and (nutrition ->> 'calories')::integer < private.calorie_minimum_for(p_user_id) then
    raise exception 'calories are below the minimum' using errcode = '22023';
  end if;
  if p_payload ? 'goal' and p_payload -> 'goal' -> 'target' is not null and (
    (p_payload -> 'goal' -> 'target' ->> 'weight_kg')::numeric
      < coalesce(private.healthy_floor_weight_kg(p_user_id), 0)
    or (p_payload -> 'goal' -> 'target' ->> 'date')::date
      not between private.local_date_for(p_user_id) + 1 and private.local_date_for(p_user_id) + 1096
  ) then
    raise exception 'target is outside the healthy range' using errcode = '22023';
  end if;

  -- The health check may have changed while the proposal was being built.
  perform private.assert_screening_allows(p_user_id, p_basis ->> 'screening');
  perform private.end_ended_plan_blocks(p_user_id);
  if (p_payload ? 'training' and p_basis ->> 'training_version_id' is distinct from (
      select v.id::text from public.training_plan_versions v
      where v.user_id = p_user_id and v.status = 'active'))
    or (p_payload ? 'nutrition' and p_basis ->> 'nutrition_version_id' is distinct from (
      select n.id::text from public.nutrition_target_sets n
      where n.user_id = p_user_id and n.status = 'active'))
    or (p_payload ? 'goal' and p_basis ->> 'goal_id' is distinct from
      private.active_goal_id(p_user_id)::text) then
    raise exception 'the plan changed while the proposal was built' using errcode = '55000';
  end if;

  if not private.coach_gates_pass(p_user_id, p_basis -> 'gates', private.local_date_for(p_user_id))
  then
    raise exception 'not enough logged data for this change' using errcode = '55000';
  end if;
  -- What the rules checked, kept with the proposal: approval refuses once any has moved.
  stored_basis := p_basis || jsonb_build_object(
    'weight_check_kg', private.latest_weight_kg(p_user_id),
    'profile_check', private.coach_profile_check(p_user_id));

  -- A newer proposal replaces an open one that would change the same thing.
  update public.change_proposals set status = 'expired'
  where user_id = p_user_id and status = 'pending' and schema_version = '3.0'
    and (proposal_kind = p_kind
      or (p_payload ? 'nutrition' and proposal_payload ? 'nutrition')
      or (p_payload ? 'training' and proposal_payload ? 'training')
      or (p_payload ? 'goal' and proposal_payload ? 'goal'));

  new_expires := statement_timestamp() + make_interval(hours => p_expires_in_hours);
  insert into public.change_proposals(
    user_id, feature_snapshot_id, schema_version, proposed_training, proposed_nutrition,
    evidence, rationale, expected_benefit, downside, confidence, effective_date, expires_at,
    proposal_kind, proposal_payload, before_snapshot, after_snapshot, basis, source_message_id,
    ends_on
  ) values (
    p_user_id, null, '3.0', summary_training, coalesce(nutrition - 'rationale', '{}'::jsonb),
    p_evidence, p_rationale, p_benefit, p_downside, p_confidence,
    private.local_date_for(p_user_id), new_expires,
    p_kind, p_payload, p_before, p_after, stored_basis, p_source_message_id, p_ends_on
  ) returning id into new_id;

  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (p_user_id, 'coach_proposal_created', 'change_proposal', new_id, 'succeeded',
    jsonb_build_object('schema_version', '3.0', 'kind', p_kind));

  return jsonb_build_object('schema_version', '1.0', 'proposal_id', new_id,
    'expires_at', new_expires);
end $$;

-- 4. The rules' deload store ---------------------------------------------------------------------------------

-- Storing any training proposal expires every open one. A change the athlete asked Coach for and has not
-- answered is theirs to answer first, so the rules' own suggestion refuses to store over it. Only a change
-- built on the plan that is active now counts: one built on an older plan could never be approved, and an
-- unanswered deload is the one a new deload replaces. The refusal and the store are one transaction under
-- the store lock, so a Coach proposal stored in between cannot be expired unseen.
create or replace function public.persist_suggested_deload_v1(
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_rationale text,
  p_benefit text,
  p_downside text,
  p_confidence text,
  p_evidence jsonb,
  p_before jsonb,
  p_after jsonb,
  p_payload jsonb,
  p_basis jsonb,
  p_ends_on date,
  p_expires_in_hours integer,
  p_source_message_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('tracend.coach_proposal_store:' || p_user_id::text, 0));
  if exists (
    select 1 from public.change_proposals cp
    where cp.user_id = p_user_id and cp.schema_version = '3.0' and cp.status = 'pending'
      and cp.expires_at > statement_timestamp()
      and cp.proposal_payload ? 'training'
      and not private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)
      and cp.basis ->> 'training_version_id' = (
        select v.id::text from public.training_plan_versions v
        where v.user_id = p_user_id and v.status = 'active')
  ) then
    raise exception 'another change is waiting for an answer' using errcode = 'TP001';
  end if;
  return public.persist_coach_proposal_v1(p_user_id, p_kind, p_title, p_rationale, p_benefit, p_downside,
    p_confidence, p_evidence, p_before, p_after, p_payload, p_basis, p_ends_on, p_expires_in_hours,
    p_source_message_id);
end $$;
revoke all on function public.persist_suggested_deload_v1(uuid, text, text, text, text, text, text,
  jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid) from public, anon, authenticated;
grant execute on function public.persist_suggested_deload_v1(uuid, text, text, text, text, text,
  text, jsonb, jsonb, jsonb, jsonb, jsonb, date, integer, uuid) to service_role;
