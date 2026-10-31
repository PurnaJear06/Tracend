-- Coach standing state: a training break becomes approved state that every surface honours, and the
-- Coach always knows the athlete's standing state.
--
-- Today's check-in can say "I can't train today", and an athlete can tell Coach "I'm taking 15 days
-- off". Before this migration the first was one cell in a table the Coach read past, while the card,
-- the plan and the daily decision all said "train as planned"; the second had nowhere to live.
--
-- 1. training_pauses: a break the athlete approved, an overlay like day_adjustments. It never changes
--    a plan version, so the plan simply resumes after the break's last day. Owner read, no client
--    writes; rows are written only by the functions below. A break that ends early or is undone keeps
--    its row and records when and why it ended (ended_at, ended_on, end_reason).
-- 2. private.availability_on(user, date): the one answer to "can this athlete train on this day?":
--    available, unavailable_today (today's check-in), paused (with the break) or safety_route. Every
--    reader below uses it.
-- 3. start_training_pause_v1 / end_training_pause_v1: the athlete's own taps on Today and Train (no
--    model). Validation: real dates, 1 to 42 days, a start from today to two days ahead, no overlap.
-- 4. Coach proposals gain the kind training_pause. The rules build it (no profile gate: a break computes
--    no numbers), the athlete approves it with one tap through respond_to_coach_proposal_v1, which writes
--    the break and an audit event, and undo_coach_proposal_v1 ends it within seven days.
-- 5. get_my_daily_brief 1.9 and get_my_training_hub 1.10 carry the availability (and the hub the paused
--    days, with paused sessions left out of adherence). Additive: every earlier key is still there.
-- 6. The readiness card: an unavailable day reads "Rest day: you said you can't train today"; a day in a
--    break reads as a rest day and offers no change; get_readiness_context_v1 tells the Coach whether the
--    athlete said they cannot train.
-- 7. The daily decision: a new policy outcome rest_as_chosen with the evidence codes
--    ATHLETE_UNAVAILABLE_TODAY and TRAINING_PAUSED, so a day in a break or a can't-train check-in never
--    proceeds as planned.
-- 8. get_coach_standing_state_v1: what the Coach's standing-state block is built from (service role).
-- 9. The dead coach_session_summaries writer and read are removed. The table stays: dropping it is a
--    later cleanup migration (the privacy export and account deletion still cover it).
--
-- Every redefinition is the latest earlier definition plus the intended hunks only, pinned by
-- supabase/functions/_shared/training/standard/coach_standing_state_migration_test.ts.

-- 1. Breaks ------------------------------------------------------------------------------------------

create table public.training_pauses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  start_date date not null,
  end_date date not null,
  reason text not null check (reason in ('rest', 'travel', 'time', 'fatigue', 'illness_recovery',
    'injury_caution', 'athlete_request', 'preference')),
  note text check (note is null or length(note) between 1 and 140),
  source text not null check (source in ('athlete', 'coach')),
  source_proposal_id uuid,
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_on date,
  end_reason text check (end_reason in ('ended_early', 'undone')),
  foreign key (source_proposal_id, user_id) references public.change_proposals (id, user_id),
  unique (id, user_id),
  check (end_date >= start_date and end_date - start_date <= 41),
  check ((ended_at is null) = (ended_on is null) and (ended_at is null) = (end_reason is null)),
  check (ended_on is null or ended_on >= start_date),
  check ((source = 'coach') = (source_proposal_id is not null))
);

create index training_pauses_user_dates on public.training_pauses (user_id, start_date);

comment on table public.training_pauses is
  'Training breaks the athlete approved (a tap on Today or Train, or a Coach proposal they approved). An overlay: no plan version changes, and the plan resumes after the break. end_date is the last day of the break as approved; a break ended early or undone keeps its row and its last day becomes ended_on - 1.';
comment on column public.training_pauses.note is
  'The athlete''s own words about the break, as they wrote them.';

alter table public.training_pauses enable row level security;
alter table public.training_pauses force row level security;
create policy training_pauses_own_read on public.training_pauses
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.training_pauses from anon, authenticated;
grant select on public.training_pauses to authenticated;

-- The last day a break covers: its approved end date, or the day before it was ended early or undone
-- (earlier than start_date when it was ended before it began, so it covers no day).
create function private.pause_last_day(p_end date, p_ended_on date)
returns date language sql immutable set search_path = '' as $$
  select case when p_ended_on is null then p_end else least(p_end, p_ended_on - 1) end;
$$;
revoke all on function private.pause_last_day(date, date) from public, anon, authenticated;

create function private.is_paused_on(p_user uuid, p_date date)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.training_pauses p
    where p.user_id = p_user and p.start_date <= p_date
      and private.pause_last_day(p.end_date, p.ended_on) >= p_date);
$$;
revoke all on function private.is_paused_on(uuid, date) from public, anon, authenticated;

-- Every day from p_from to p_to that a break covers.
create function private.paused_days(p_user uuid, p_from date, p_to date)
returns setof date language sql stable security definer set search_path = '' as $$
  select distinct d::date from public.training_pauses p,
    generate_series(greatest(p.start_date, p_from)::timestamp,
      least(private.pause_last_day(p.end_date, p.ended_on), p_to)::timestamp, interval '1 day') d
  where p.user_id = p_user and p.start_date <= p_to
    and private.pause_last_day(p.end_date, p.ended_on) >= p_from
  order by 1;
$$;
revoke all on function private.paused_days(uuid, date, date) from public, anon, authenticated;

-- Why a break from p_start to p_end (its last day) cannot be set on p_today, or null.
create function private.training_pause_problem(p_user uuid, p_start date, p_end date, p_today date)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when p_start is null or p_end is null or p_end < p_start then 'dates_invalid'
    when p_start < p_today then 'pause_start_past'
    when p_start > p_today + 2 then 'pause_start_too_far'
    when p_end - p_start + 1 > 42 then 'pause_too_long'
    when exists (select 1 from public.training_pauses p
      where p.user_id = p_user
        and private.pause_last_day(p.end_date, p.ended_on) >= p.start_date
        and p.start_date <= p_end
        and private.pause_last_day(p.end_date, p.ended_on) >= p_start) then 'pause_overlaps'
  end;
$$;
revoke all on function private.training_pause_problem(uuid, date, date, date)
  from public, anon, authenticated;

create function private.training_pause_json(p public.training_pauses, p_running boolean)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'start_date', p.start_date,
    'end_date', private.pause_last_day(p.end_date, p.ended_on), 'reason', p.reason, 'note', p.note,
    'source', p.source, 'running', p_running);
$$;
revoke all on function private.training_pause_json(public.training_pauses, boolean)
  from public, anon, authenticated;

-- Writes a validated break and its audit event. Callers hold the athlete's break lock.
create function private.insert_training_pause(
  p_user uuid, p_start date, p_end date, p_reason text, p_note text, p_source text, p_proposal uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  new_id uuid;
begin
  insert into public.training_pauses(user_id, start_date, end_date, reason, note, source,
    source_proposal_id)
  values (p_user, p_start, p_end, p_reason, p_note, p_source, p_proposal)
  returning id into new_id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (p_user, 'training_pause_started', 'training_pause', new_id, 'succeeded',
    jsonb_build_object('schema_version', '1.0', 'source', p_source, 'start_date', p_start,
      'end_date', p_end, 'proposal_id', p_proposal));
  return new_id;
end $$;
revoke all on function private.insert_training_pause(uuid, date, date, text, text, text, uuid)
  from public, anon, authenticated;

-- Ends a break on p_today: a running break stops covering today, one not begun yet is cancelled. A break
-- already over or already ended reports not_running and changes nothing.
create function private.end_training_pause(p_user uuid, p_pause uuid, p_reason text, p_today date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  pause public.training_pauses%rowtype;
  ended date;
begin
  select * into pause from public.training_pauses
  where id = p_pause and user_id = p_user for update;
  if not found then raise exception 'break not found' using errcode = 'P0002'; end if;
  if pause.ended_on is not null or pause.end_date < p_today then
    return jsonb_build_object('schema_version', '1.0', 'status', 'not_running',
      'pause_id', pause.id, 'ended_on', pause.ended_on);
  end if;
  ended := greatest(pause.start_date, p_today);
  update public.training_pauses
  set ended_at = statement_timestamp(), ended_on = ended, end_reason = p_reason
  where id = pause.id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (p_user, 'training_pause_ended', 'training_pause', pause.id, 'succeeded',
    jsonb_build_object('schema_version', '1.0', 'reason', p_reason, 'ended_on', ended));
  return jsonb_build_object('schema_version', '1.0',
    'status', case when pause.start_date > p_today then 'cancelled' else 'ended' end,
    'pause_id', pause.id, 'ended_on', ended);
end $$;
revoke all on function private.end_training_pause(uuid, uuid, text, date)
  from public, anon, authenticated;

-- 2. Availability ------------------------------------------------------------------------------------

-- Whether the athlete can train on p_date, from what they approved and said:
--   status             safety_route (a referral on the readiness card; only when p_safety), paused (a
--                      break covers the day), unavailable_today (that day's check-in said they cannot
--                      train) or available, in that order of precedence
--   pause              the break covering the day, else the next one ahead
--   return_from_pause  the break that ended in the 7 days before, while no session has been finished
--                      since it ended: the first day back
--   offer_break        that day's and the day before's check-ins both said they cannot train, and no
--                      break is running or ahead: Today offers to set one (the athlete taps)
-- The safety route reads the whole readiness card, so the brief and the hub, which show the card next
-- to it, pass p_safety false.
create function private.availability_on(p_user uuid, p_date date, p_safety boolean default true)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  running public.training_pauses%rowtype;
  upcoming public.training_pauses%rowtype;
  previous public.training_pauses%rowtype;
  last_day date;
  back jsonb;
  today_available boolean;
  yesterday_available boolean;
  route text;
begin
  select * into running from public.training_pauses p
  where p.user_id = p_user and p.start_date <= p_date
    and private.pause_last_day(p.end_date, p.ended_on) >= p_date
  order by p.created_at desc limit 1;
  if running.id is null then
    select * into upcoming from public.training_pauses p
    where p.user_id = p_user and p.start_date > p_date and p.ended_on is null
    order by p.start_date limit 1;
    select * into previous from public.training_pauses p
    where p.user_id = p_user and p.end_reason is distinct from 'undone'
      and private.pause_last_day(p.end_date, p.ended_on) >= p.start_date
      and private.pause_last_day(p.end_date, p.ended_on) < p_date
    order by private.pause_last_day(p.end_date, p.ended_on) desc limit 1;
    if previous.id is not null then
      last_day := private.pause_last_day(previous.end_date, previous.ended_on);
      if p_date - last_day <= 7 and not exists (
        select 1 from public.workout_sessions s
        where s.user_id = p_user and s.state = 'completed'
          and s.local_date > last_day and s.local_date <= p_date) then
        back := jsonb_build_object('pause_id', previous.id, 'last_paused_day', last_day);
      end if;
    end if;
  end if;
  select c.available_to_train into today_available from public.daily_check_ins c
  where c.user_id = p_user and c.local_date = p_date and c.superseded_at is null;
  select c.available_to_train into yesterday_available from public.daily_check_ins c
  where c.user_id = p_user and c.local_date = p_date - 1 and c.superseded_at is null;
  if p_safety then
    route := private.day_adjustment_compute(p_user, p_date, true) -> 'payload' ->> 'safety_route';
  end if;
  return jsonb_build_object(
    'schema_version', '1.0',
    'local_date', p_date,
    'status', case when route is not null then 'safety_route'
      when running.id is not null then 'paused'
      when today_available is false then 'unavailable_today'
      else 'available' end,
    'unavailable_today', coalesce(today_available is false, false),
    'safety_route', route,
    'paused', running.id is not null,
    'pause', case when running.id is not null then private.training_pause_json(running, true)
      when upcoming.id is not null then private.training_pause_json(upcoming, false) end,
    'return_from_pause', back,
    'offer_break', coalesce(today_available is false and yesterday_available is false, false)
      and running.id is null and upcoming.id is null);
end $$;
revoke all on function private.availability_on(uuid, date, boolean) from public, anon, authenticated;

-- 3. The athlete's own taps -----------------------------------------------------------------------------

-- Sets a break from Today or Train. A refused break returns the reason and writes nothing.
create function public.start_training_pause_v1(
  p_start_date date, p_end_date date, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  clean_note text := nullif(btrim(p_note), '');
  problem text;
  new_id uuid;
begin
  if me is null then raise exception 'authentication required' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('tracend.training_pause:' || me::text, 0));
  problem := case when clean_note is not null and length(clean_note) > 140 then 'note_too_long'
    else private.training_pause_problem(me, p_start_date, p_end_date, private.local_date_for(me)) end;
  if problem is null then
    new_id := private.insert_training_pause(me, p_start_date, p_end_date, 'rest', clean_note,
      'athlete', null);
  end if;
  return jsonb_build_object('schema_version', '1.0',
    'status', case when problem is null then 'started' else 'refused' end,
    'pause_id', new_id, 'start_date', p_start_date, 'end_date', p_end_date, 'refusal', problem);
end $$;
revoke all on function public.start_training_pause_v1(date, date, text) from public, anon, authenticated;
grant execute on function public.start_training_pause_v1(date, date, text) to authenticated;

-- Ends a break early (or cancels one not begun): "End break early", and the Undo right after setting one.
create function public.end_training_pause_v1(p_pause_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'authentication required' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('tracend.training_pause:' || me::text, 0));
  return private.end_training_pause(me, p_pause_id, 'ended_early', private.local_date_for(me));
end $$;
revoke all on function public.end_training_pause_v1(uuid) from public, anon, authenticated;
grant execute on function public.end_training_pause_v1(uuid) to authenticated;

-- 4. Coach proposals: training_pause ------------------------------------------------------------------

-- The pause part of a payload: the break as the rules built it.
create function private.is_valid_coach_pause(pause jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(jsonb_typeof(pause) = 'object'
    and pause ->> 'start_date' ~ '^\d{4}-\d{2}-\d{2}$'
    and pause ->> 'end_date' ~ '^\d{4}-\d{2}-\d{2}$'
    and pause ->> 'reason' in ('rest', 'travel', 'time', 'fatigue', 'illness_recovery',
      'injury_caution', 'athlete_request', 'preference')
    and (coalesce(jsonb_typeof(pause -> 'note'), 'null') = 'null'
      or private.jsonb_text_between(pause -> 'note', 1, 140)), false);
$$;
revoke all on function private.is_valid_coach_pause(jsonb) from public, anon, authenticated;

-- What the rules read to build a break (service role): the athlete's date, the health check outcome and
-- the breaks that are running or ahead.
create function public.get_training_pause_inputs_v1(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  today date;
begin
  if p_user_id is null or not exists (select 1 from public.user_accounts where id = p_user_id) then
    raise exception 'account not found' using errcode = 'P0002';
  end if;
  today := private.local_date_for(p_user_id);
  return jsonb_build_object('schema_version', '1.0', 'local_date', today,
    'screening', private.current_screening_outcome(p_user_id),
    'pauses', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'start_date', p.start_date,
        'last_day', private.pause_last_day(p.end_date, p.ended_on)) order by p.start_date)
      from public.training_pauses p
      where p.user_id = p_user_id
        and private.pause_last_day(p.end_date, p.ended_on) >= greatest(p.start_date, today)),
      '[]'::jsonb));
end $$;
revoke all on function public.get_training_pause_inputs_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_training_pause_inputs_v1(uuid) to service_role;

comment on column public.change_proposals.proposal_kind is
  'Coach proposals (schema 3.0): temporary_block, training_schedule, exercise_swap, intensity_or_phase, goal_or_phase, nutrition_targets, next_session_adjustment or training_pause.';
comment on column public.change_proposals.proposal_payload is
  'What approval writes: {training?, nutrition?, goal?} or {pause}. Every number and date was checked by rules (_shared/coach_proposals); the model chose only the kind and its closed-vocabulary parameters.';

-- 7. The daily decision's new outcome (used by prepare_daily_coaching_core below) ------------------------

alter type public.policy_outcome add value if not exists 'rest_as_chosen';

-- 8. What the Coach's standing-state block is built from --------------------------------------------------

-- Service role. The athlete's standing state on their own day: availability (with the safety route), the
-- held and limited joint areas, whether pain of 4 or more was reported on a check-in in the last 7 days,
-- the goal and its phase, the last 3 proposals the athlete approved, declined or undid in 14 days, the
-- breaks of the last 14 days and ahead, and the days a break covers or a check-in said they could not
-- train (28 days back; breaks also 13 days ahead), which the plan and the watch-outs never count as due
-- or missed.
create function public.get_coach_standing_state_v1(p_user_id uuid, p_local_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if p_user_id is null or not exists (select 1 from public.user_accounts where id = p_user_id) then
    raise exception 'account not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'schema_version', '1.0',
    'local_date', p_local_date,
    'availability', private.availability_on(p_user_id, p_local_date, true),
    'joint_areas', coalesce((select jsonb_agg(jsonb_build_object('area', s ->> 'area',
        'state', s ->> 'state') order by s ->> 'state', s ->> 'area')
      from jsonb_array_elements(private.joint_states(p_user_id, p_local_date)) s
      where s ->> 'state' in ('held', 'limited')), '[]'::jsonb),
    'recent_pain', exists (select 1 from public.daily_check_ins c
      where c.user_id = p_user_id and c.superseded_at is null
        and c.local_date between p_local_date - 6 and p_local_date and c.pain_severity >= 4),
    'goal', (select jsonb_build_object('goal_type', g.goal_type, 'phase', g.details ->> 'phase',
        'phase_ends_on', g.details ->> 'phase_ends_on')
      from public.user_goals g where g.id = private.active_goal_id(p_user_id)),
    'decisions', coalesce((select jsonb_agg(x.d order by x.happened desc) from (
        select jsonb_build_object('kind', c.proposal_kind,
            'title', c.proposed_training ->> 'title',
            'status', case when c.undone_at is not null then 'undone'
              when c.status = 'accepted' then 'approved' else 'declined' end,
            'on', private.local_day(p_user_id, coalesce(c.undone_at, c.applied_at, r.created_at,
              c.created_at)),
            'ends_on', c.ends_on) as d,
          coalesce(c.undone_at, c.applied_at, r.created_at, c.created_at) as happened
        from public.change_proposals c
        left join public.change_responses r on r.proposal_id = c.id and r.user_id = c.user_id
        where c.user_id = p_user_id and c.schema_version = '3.0'
          and c.status in ('accepted', 'rejected')
          and private.local_day(p_user_id, coalesce(c.undone_at, c.applied_at, r.created_at,
            c.created_at)) between p_local_date - 13 and p_local_date
        order by 2 desc limit 3) x), '[]'::jsonb),
    'breaks', coalesce((select jsonb_agg(x.b order by x.starts desc) from (
        select jsonb_build_object('start_date', p.start_date,
            'last_day', private.pause_last_day(p.end_date, p.ended_on), 'end_date', p.end_date,
            'source', p.source, 'ended', p.end_reason, 'ended_on', p.ended_on) as b,
          p.start_date as starts
        from public.training_pauses p
        where p.user_id = p_user_id and p.end_reason is distinct from 'undone'
          and private.pause_last_day(p.end_date, p.ended_on) >= p.start_date
          and private.pause_last_day(p.end_date, p.ended_on) >= p_local_date - 13
        order by p.start_date desc limit 3) x), '[]'::jsonb),
    'paused_days', coalesce((select jsonb_agg(d order by d)
      from private.paused_days(p_user_id, p_local_date - 28, p_local_date + 13) d), '[]'::jsonb),
    'unavailable_days', coalesce((select jsonb_agg(c.local_date order by c.local_date)
      from public.daily_check_ins c
      where c.user_id = p_user_id and c.superseded_at is null and c.available_to_train is false
        and c.local_date between p_local_date - 28 and p_local_date), '[]'::jsonb));
end $$;
revoke all on function public.get_coach_standing_state_v1(uuid, date) from public, anon, authenticated;
grant execute on function public.get_coach_standing_state_v1(uuid, date) to service_role;

-- 9. The dead summaries writer -----------------------------------------------------------------------------

-- Nothing in the app or the Edge Functions has called it since coach_notes replaced the journal; the table
-- stays until a later cleanup migration.
drop function public.persist_coach_session_summary(uuid, date, text, uuid, uuid[]);

-- Redefinitions ---------------------------------------------------------------------------------------------

-- R1. Proposal rows accept a break (20261018120018 plus the pause part).
create or replace function private.is_valid_coach_proposal_row(
  kind text, training jsonb, nutrition jsonb, payload jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select kind in ('temporary_block', 'training_schedule', 'exercise_swap', 'intensity_or_phase',
      'goal_or_phase', 'nutrition_targets', 'next_session_adjustment', 'training_pause')
    and jsonb_typeof(training) = 'object'
    and jsonb_typeof(nutrition) = 'object'
    and jsonb_typeof(payload) = 'object'
    and (payload ? 'training' or payload ? 'nutrition' or payload ? 'goal' or payload ? 'pause')
    and ((kind = 'training_pause') = (payload ? 'pause'))
    and (not payload ? 'pause' or (payload - 'pause' = '{}'::jsonb
      and private.is_valid_coach_pause(payload -> 'pause')))
    and (not payload ? 'training' or private.is_valid_coach_training(payload -> 'training'))
    and (not payload ? 'nutrition' or private.is_valid_coach_nutrition(payload -> 'nutrition'))
    and (not payload ? 'goal' or private.is_valid_coach_goal(payload -> 'goal'));
$$;
revoke all on function private.is_valid_coach_proposal_row(text, jsonb, jsonb, jsonb)
  from public, anon, authenticated;

-- R2. A proposal whose break was ended or is over is no longer current (20261018120018 plus the break).
create or replace function private.coach_proposal_is_current(p public.change_proposals)
returns boolean language sql stable set search_path = '' as $$
  select (p.applied_changes -> 'training_version_id' is null
      or p.applied_changes ->> 'training_version_id' = (
        select v.id::text from public.training_plan_versions v
        where v.user_id = p.user_id and v.status = 'active'))
    and (p.applied_changes -> 'nutrition_version_id' is null
      or p.applied_changes ->> 'nutrition_version_id' = (
        select n.id::text from public.nutrition_target_sets n
        where n.user_id = p.user_id and n.status = 'active'))
    and (p.applied_changes -> 'goal_id' is null
      or p.applied_changes ->> 'goal_id' = private.active_goal_id(p.user_id)::text)
    and (p.applied_changes -> 'pause_id' is null or exists (
      select 1 from public.training_pauses t
      where t.id = (p.applied_changes ->> 'pause_id')::uuid and t.user_id = p.user_id
        and t.ended_on is null and t.end_date >= private.local_date_for(p.user_id)));
$$;
revoke all on function private.coach_proposal_is_current(public.change_proposals)
  from public, anon, authenticated;

-- R3. Storing a break proposal (20261024060425 plus the break checks).
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
  -- A break computes nothing and only rests, so the health check never holds one back.
  if not p_payload ? 'pause' then
    perform private.assert_screening_allows(p_user_id, p_basis ->> 'screening');
  end if;
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
  -- A break must still fit when it is stored: dates from today to two days ahead, at most 42 days and
  -- no overlap with another break.
  if p_payload ? 'pause' and private.training_pause_problem(p_user_id,
      (p_payload -> 'pause' ->> 'start_date')::date, (p_payload -> 'pause' ->> 'end_date')::date,
      private.local_date_for(p_user_id)) is not null then
    raise exception 'the break no longer fits' using errcode = '55000';
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
revoke all on function public.persist_coach_proposal_v1(uuid, text, text, text, text, text, text, jsonb,
  jsonb, jsonb, jsonb, jsonb, date, integer, uuid) from public, anon, authenticated;
grant execute on function public.persist_coach_proposal_v1(uuid, text, text, text, text, text, text, jsonb,
  jsonb, jsonb, jsonb, jsonb, date, integer, uuid) to service_role;

-- R4. Approving a break writes it with its audit event (20261024060325 plus the break hunks).
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
  pause_change jsonb;
  new_pause_id uuid;
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
  pause_change := proposal.proposal_payload -> 'pause';
  -- Breaks are set one at a time per athlete (start_training_pause_v1 holds the same lock).
  if pause_change is not null then
    perform pg_advisory_xact_lock(hashtextextended('tracend.training_pause:' || auth.uid()::text, 0));
  end if;

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
    when pause_change is null and proposal.basis -> 'profile_check' is distinct from
      private.coach_profile_check(auth.uid()) then 'profile_changed'
    when pause_change is null and proposal.basis ->> 'weight_check_kg' is not null
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
    when pause_change is not null and (pause_change ->> 'start_date')::date < today then 'dates_passed'
    when pause_change is not null and private.training_pause_problem(auth.uid(),
      (pause_change ->> 'start_date')::date, (pause_change ->> 'end_date')::date, today) is not null
      then 'pause_overlaps'
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
    -- A break only rests, so the health check never holds one back.
    if pause_change is null then
      perform private.assert_screening_allows(auth.uid(), proposal.basis ->> 'screening');
    end if;
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

    if pause_change is not null then
      new_pause_id := private.insert_training_pause(auth.uid(), (pause_change ->> 'start_date')::date,
        (pause_change ->> 'end_date')::date, pause_change ->> 'reason', pause_change ->> 'note',
        'coach', proposal.id);
      applied := applied || jsonb_build_object('pause_id', new_pause_id);
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
        'goal_id', new_goal_id, 'pause_id', new_pause_id));
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

-- R5. Undoing a break ends it (20261018120018 plus the break hunks).
create or replace function public.undo_coach_proposal_v1(proposal_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  proposal public.change_proposals%rowtype;
  applied jsonb;
  restored_training uuid;
  restored_nutrition uuid;
  restored_goal uuid;
  source_nutrition public.nutrition_target_sets%rowtype;
  source_goal public.user_goals%rowtype;
  undone_at_value timestamptz := statement_timestamp();
  report text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  perform private.end_ended_plan_blocks(auth.uid());
  select * into proposal from public.change_proposals
  where id = undo_coach_proposal_v1.proposal_id and user_id = auth.uid() for update;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  if proposal.schema_version <> '3.0' or proposal.status <> 'accepted' then
    raise exception 'proposal is not an approved coach proposal' using errcode = '55000';
  end if;
  report := case
    when proposal.undone_at is not null then 'undone'
    when proposal.undo_until <= undone_at_value then 'undo_window_ended'
    when not private.coach_proposal_is_current(proposal) then 'superseded'
    else null end;
  if report is not null then
    return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
      'status', report, 'training_plan_version_id', null, 'nutrition_target_set_id', null,
      'goal_id', null);
  end if;
  applied := proposal.applied_changes;

  if applied ? 'previous_training_version_id' then
    if private.current_screening_outcome(auth.uid()) = 'see_professional' then
      raise exception 'a health professional must clear this athlete first' using errcode = '55000';
    end if;
    restored_training := private.clone_plan_version(
      (applied ->> 'previous_training_version_id')::uuid, auth.uid(), proposal.id,
      'You undid a change from Coach, so your earlier plan is back.');
    -- The earlier plan may have been approved under a weaker health check.
    perform private.hold_plan_to_screening(auth.uid(), restored_training);
    -- A profile value the athlete changed since is theirs: only values still as the proposal set
    -- them go back.
    if applied ? 'profile_before' and applied ? 'profile_after' then
      update public.user_profiles p set
        training_days = case
          when to_jsonb(p.training_days) = applied -> 'profile_after' -> 'training_days'
          then array(select value::smallint
            from jsonb_array_elements_text(applied -> 'profile_before' -> 'training_days') value)
          else p.training_days end,
        session_minutes = case
          when to_jsonb(p.session_minutes) = applied -> 'profile_after' -> 'session_minutes'
          then (applied -> 'profile_before' ->> 'session_minutes')::smallint
          else p.session_minutes end
      where p.user_id = auth.uid();
    end if;
  end if;

  if applied ? 'previous_nutrition_version_id' then
    select * into source_nutrition from public.nutrition_target_sets
    where id = (applied ->> 'previous_nutrition_version_id')::uuid and user_id = auth.uid();
    update public.nutrition_target_sets set status = 'superseded'
    where user_id = auth.uid() and status = 'active';
    insert into public.nutrition_target_sets(
      user_id, version_number, status, calories, protein_g, carbohydrate_g, fat_g, rationale,
      source_proposal_id, approved_at, effective_date
    ) values (
      auth.uid(),
      (select max(version_number) + 1 from public.nutrition_target_sets where user_id = auth.uid()),
      'active', source_nutrition.calories, source_nutrition.protein_g,
      source_nutrition.carbohydrate_g, source_nutrition.fat_g,
      'You undid a change from Coach, so your earlier targets are back.', proposal.id,
      statement_timestamp(), private.local_date_for(auth.uid())
    ) returning id into restored_nutrition;
  end if;

  if applied ? 'previous_goal_id' then
    select * into source_goal from public.user_goals
    where id = (applied ->> 'previous_goal_id')::uuid and user_id = auth.uid();
    update public.user_goals set status = 'superseded'
    where user_id = auth.uid() and status = 'active' and priority = source_goal.priority;
    insert into public.user_goals(
      user_id, goal_type, priority, status, details, activated_at, source_proposal_id)
    values (auth.uid(), source_goal.goal_type, source_goal.priority, 'active',
      source_goal.details, source_goal.activated_at, proposal.id)
    returning id into restored_goal;
  end if;

  if applied ? 'pause_id' then
    perform pg_advisory_xact_lock(hashtextextended('tracend.training_pause:' || auth.uid()::text, 0));
    perform private.end_training_pause(auth.uid(), (applied ->> 'pause_id')::uuid, 'undone',
      private.local_date_for(auth.uid()));
  end if;

  update public.change_proposals set undone_at = undone_at_value where id = proposal.id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'coach_proposal_undone', 'change_proposal', proposal.id, 'succeeded',
    jsonb_build_object('schema_version', '3.0', 'kind', proposal.proposal_kind,
      'training_version_id', restored_training, 'nutrition_version_id', restored_nutrition,
      'goal_id', restored_goal, 'pause_id', applied -> 'pause_id'));
  return jsonb_build_object('schema_version', '1.0', 'proposal_id', proposal.id,
    'status', 'undone', 'training_plan_version_id', restored_training,
    'nutrition_target_set_id', restored_nutrition, 'goal_id', restored_goal);
end $$;
revoke all on function public.undo_coach_proposal_v1(uuid) from public, anon, authenticated;
grant execute on function public.undo_coach_proposal_v1(uuid) to authenticated;

-- R6. Daily brief 1.9: the day's availability (20261004160000 plus the hunks).
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
        'planned', exists (
          select 1
          from public.planned_workouts w
          join public.training_plan_versions pv
            on pv.id = w.plan_version_id and pv.user_id = w.user_id
          where w.user_id = v_user_id
            and pv.status = 'active'
            and w.preferred_weekday = extract(isodow from d.day)::integer)
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

-- R7. Training hub 1.10: the availability, the paused days, and paused sessions left out of adherence
-- (20261024090000 plus the hunks; every 1.9 key is still there).
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
), paused_sessions as (
  -- Planned sessions on days a break covers: neither due nor missed, so left out of adherence.
  select count(*)::integer as n
  from private.paused_days(auth.uid(),
    (select today from local_day)-greatest(7,least(period_days,365))+1,
    (select today from local_day)) d
  join workouts w on w.preferred_weekday=extract(isodow from d)::integer
)
select jsonb_build_object(
  'schema_version','1.10','period_days',greatest(7,least(period_days,365)),
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
    'planned_sessions',greatest(0,coalesce((select sessions_per_week from active_version),0)
      * greatest(1,ceil(greatest(7,least(period_days,365))/7.0)::integer)
      - (select n from paused_sessions)),
    'paused_sessions',(select n from paused_sessions)),
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
    (select today from local_day)+13) d),'[]'::jsonb)
);
$$;

revoke all on function public.get_my_training_hub(integer) from public, anon, authenticated;
grant execute on function public.get_my_training_hub(integer) to authenticated;

-- R8. The card's words for a rest the athlete chose (20261024060025 plus the hunks).
create or replace function private.day_adjustment_explanation(
  p_band text, p_kind text, p_triggers text[], p_safety_route text, p_changes jsonb,
  p_with_reasons boolean, p_unavailable text
) returns text language plpgsql immutable set search_path = '' as $$
declare
  r constant jsonb := private.readiness_rules();
  codes constant text[] := array['sleep_very_poor', 'sleep_poor', 'sleep_short', 'energy_very_low',
    'energy_low', 'very_sore', 'sore', 'mood_very_low', 'pain_moderate', 'recovery_low'];
  phrases constant text[] := array['you slept very poorly', 'you slept poorly',
    'you slept under 6 hours', 'your energy is very low', 'your energy is low', 'you''re very sore',
    'you''re sore', 'your mood is very low', 'you have some pain', 'your recovery reads low'];
  parts text[] := '{}';
  reasons text := '';
  action text;
  note text := '';
  cut integer;
  loads boolean;
  i integer;
  n integer;
  joint_text text;
begin
  if p_safety_route is not null then
    return case p_safety_route
      when 'pain_referral' then 'Pain of 7 or more is too high to train through. Rest the area and see a doctor or physio before you train it again.'
      when 'urgent' then 'What you described needs urgent care. Call your local emergency number or go to an emergency department now. Tracend won''t suggest any training until you''ve been seen.'
      when 'clinician_today' then 'Please see a doctor or physio today, before you train this area again. Tracend leaves training aside for today.'
      else 'Please book a doctor or physio before you train this area again. Tracend leaves training aside for today.' end;
  end if;
  if 'pain_mild' = any(p_triggers) then
    note := ' Keep any pain at 3 or below, and stop if it builds from set to set.';
  end if;

  -- A kind speaks for itself: its sentence depends on the kind and its changes, never on the band
  -- (an adjustment the athlete chose themselves may come with no check-in at all).
  if p_kind <> 'none' then
    select count(*) filter (where (c ->> 'sets_to')::integer < (c ->> 'sets_from')::integer
        and coalesce(c ->> 'joint_action', '') <> 'drop'),
      coalesce(bool_or(c ->> 'load_note' is not null), false)
    into cut, loads
    from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb)) c;

    action := case p_kind
      when 'hold_load' then case when loads
        then 'Keep last time''s weights instead of adding more.'
        else 'Repeat last time''s reps instead of adding more.' end
      when 'reduce_sets' then 'One set fewer on ' || cut
        || case when cut = 1 then ' exercise' else ' exercises' end
        || case when loads then ' and last time''s weights.' else '.' end
      when 'joint_adjust' then ''
      else format('Try %s to %s minutes of easy walking, cycling or swimming at a pace you can talk through. It keeps you moving without adding strain.',
        r -> 'easy_cardio_minutes' -> 0, r -> 'easy_cardio_minutes' -> 1) end;

    if p_with_reasons and p_kind <> 'joint_adjust' then
      for i in 1..array_length(codes, 1) loop
        if codes[i] = any(p_triggers) then parts := parts || phrases[i]; end if;
      end loop;
      n := coalesce(array_length(parts, 1), 0);
      if n = 1 then reasons := parts[1];
      elsif n >= 2 then
        reasons := array_to_string(parts[1:n - 1], ', ') || ' and ' || parts[n];
      end if;
    end if;
    joint_text := private.joint_sentence(p_changes);
    return case when reasons <> ''
      then upper(left(reasons, 1)) || substr(reasons, 2) || '. ' else '' end || action
      || case when joint_text = '' then '' when action = '' then joint_text
        else ' ' || joint_text end || note;
  end if;

  if p_unavailable is not null then
    return case p_unavailable
      when 'no_plan' then 'You have no active plan to adjust.'
      when 'rest_day' then 'No session is planned today. Nothing in your plan changes.'
      when 'session_started' then 'Today''s session is under way.'
      when 'session_done' then 'Today''s session is done.'
      else 'Coach already adjusted today''s session.' end;
  end if;
  if 'paused' = any(p_triggers) then
    return 'Rest day: you''re on a break, so no session is due today.';
  end if;
  if p_band = 'unknown' then
    return case when 'recovery_low' = any(p_triggers)
      then 'Your recovery reads low. Check in and Tracend will say whether to adjust today.'
      else 'Check in to see if today''s session needs adjusting.' end;
  end if;
  if 'not_available' = any(p_triggers) then
    return 'Rest day: you said you can''t train today.';
  end if;

  for i in 1..array_length(codes, 1) loop
    if codes[i] = any(p_triggers) then parts := parts || phrases[i]; end if;
  end loop;
  n := coalesce(array_length(parts, 1), 0);
  if n = 1 then reasons := parts[1];
  elsif n >= 2 then
    reasons := array_to_string(parts[1:n - 1], ', ') || ' and ' || parts[n];
  end if;
  if p_band = 'green' then
    return case when 'recovery_low' = any(p_triggers)
      then 'Your recovery reads low, but your check-in looks fine. You can train as planned or choose a lighter session.'
      else 'Your check-in looks fine. Train as planned.' end || note;
  end if;
  return case when n = 0 then 'Nothing in today''s session needs to change.'
    else upper(left(reasons, 1)) || substr(reasons, 2)
      || '. Nothing in today''s session needs to change.' end || note;
end $$;
revoke all on function private.day_adjustment_explanation(text, text, text[], text, jsonb, boolean, text)
  from public, anon, authenticated;

-- R9. A day in a break offers no readiness change; a held or limited joint still shapes a session the
-- athlete chooses to do (20261024090000 plus the hunks).
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
  paused boolean := private.is_paused_on(p_user, p_date);
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
        and s.planned_workout_id = any((select private.workout_identity_ids(p_user, workout_id))::uuid[]) and s.state = 'in_progress') then 'session_started'
    when exists (select 1 from public.workout_sessions s where s.user_id = p_user
        and s.planned_workout_id = any((select private.workout_identity_ids(p_user, workout_id))::uuid[])
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
  -- A day in a break the athlete approved is a rest they chose.
  if paused then triggers := triggers || array['paused']; end if;
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
  kind := case when unavailable is not null or safety is not null or paused then 'none'
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
revoke all on function private.day_adjustment_compute(uuid, date, boolean) from public, anon, authenticated;

-- R10. The Coach is told whether the athlete said they cannot train (20261024060025 plus one key).
create or replace function public.get_readiness_context_v1(p_user_id uuid, p_local_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  computed jsonb;
  payload jsonb;
  cur public.day_adjustments%rowtype;
  presented jsonb;
begin
  if p_user_id is null or p_local_date is distinct from private.local_date_for(p_user_id) then
    raise exception 'only the athlete''s own today can be read' using errcode = '22023';
  end if;
  computed := private.day_adjustment_compute(p_user_id, p_local_date, true);
  payload := computed -> 'payload';
  select * into cur from public.day_adjustments a
  where a.user_id = p_user_id and a.local_date = p_local_date and a.superseded_at is null;
  presented := private.day_adjustment_present(cur, payload,
    private.day_adjustment_stands(cur, payload), computed -> 'inputs');
  return jsonb_build_object(
    'schema_version', '1.0',
    'local_date', p_local_date,
    'band', presented -> 'band',
    'kind', presented -> 'kind',
    'status', presented -> 'status',
    'available', presented -> 'available',
    'unavailable_reason', presented -> 'unavailable_reason',
    'safety_route', presented -> 'safety_route',
    'triggers', coalesce((select jsonb_agg(t.value)
      from jsonb_array_elements_text(presented -> 'triggers') t(value)
      where t.value not like 'red_flag:%'), '[]'::jsonb),
    'confidence', presented -> 'confidence',
    'joint_states', coalesce((select jsonb_agg(jsonb_build_object('area', s -> 'area',
        'state', s -> 'state', 'persistent', s -> 'persistent'))
      from jsonb_array_elements(presented -> 'joint_states') s), '[]'::jsonb),
    'rules_version', presented -> 'rules_version',
    'athlete_unavailable', coalesce(presented -> 'triggers' ? 'not_available', false));
end $$;
revoke all on function public.get_readiness_context_v1(uuid, date) from public, anon, authenticated;
grant execute on function public.get_readiness_context_v1(uuid, date) to service_role;

-- R11. The daily decision rests as chosen on a day in a break or after a can't-train check-in
-- (20261017170019 plus the hunks).
create or replace function private.prepare_daily_coaching_core(
  target_user_id uuid,
  coaching_date date,
  coaching_timezone text,
  request_idempotency_key uuid,
  for_chat boolean
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  snapshot_id uuid; policy_id uuid; existing_run public.model_runs%rowtype;
  check_in public.daily_check_ins%rowtype; health public.daily_health_summaries%rowtype;
  plan_id uuid; target_id uuid; snapshot_features jsonb; evidence text[] := '{}';
  missing text[] := '{}'; outcome public.policy_outcome; rules text[] := '{}';
  snapshot_hash text; metrics_jsonb jsonb; eligibility_jsonb jsonb;
  paused boolean;
begin
  if target_user_id is null or not exists(select 1 from public.user_accounts where id=target_user_id)
  then raise exception 'account not found' using errcode='P0002'; end if;
  if length(coaching_timezone) not between 1 and 64
  then raise exception 'invalid timezone' using errcode='22023'; end if;
  select * into existing_run from public.model_runs
    where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if found then
    return jsonb_build_object('replayed',true,'model_run_id',existing_run.id);
  end if;
  if not for_chat and (select count(*) from public.model_runs where user_id=target_user_id and provider<>'mock'
      and created_at >= date_trunc('day',now())) >= 30
  then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
  select id into plan_id from public.training_plan_versions
    where user_id=target_user_id and status='active' limit 1;
  select id into target_id from public.nutrition_target_sets
    where user_id=target_user_id and status='active' limit 1;
  if not for_chat and (plan_id is null or target_id is null)
  then raise exception 'approved plan required' using errcode='22023'; end if;
  select * into check_in from public.daily_check_ins
    where user_id=target_user_id and local_date=coaching_date and superseded_at is null;
  select * into health from public.daily_health_summaries
    where user_id=target_user_id and local_date=coaching_date and source_scope='healthkit';

  begin
    metrics_jsonb := public.compute_daily_metrics(target_user_id, coaching_date, coaching_timezone);
  exception when others then
    metrics_jsonb := null;
  end;
  eligibility_jsonb := public.evaluate_change_eligibility(target_user_id, coaching_date);

  if check_in.id is null then
    missing := array['recovery_check_in']; outcome := 'request_data';
    rules := array['CHECK_IN_REQUIRED'];
  elsif check_in.pain_severity >= 7 then
    outcome := 'escalate'; rules := array['PAIN_SAFETY_THRESHOLD'];
  else
    outcome := 'maintain_only'; rules := array['INSUFFICIENT_CHANGE_EVIDENCE'];
  end if;
  if health.id is null then missing := missing || array['health_context']; end if;
  -- A rest the athlete chose (a break they approved, or today's check-in saying they cannot train)
  -- is honoured: the decision rests as chosen and never proceeds with the planned session.
  -- Escalation keeps its precedence.
  paused := private.is_paused_on(target_user_id, coaching_date);
  if outcome <> 'escalate' and (paused or check_in.available_to_train is false) then
    outcome := 'rest_as_chosen';
    rules := array[case when paused then 'TRAINING_PAUSED' else 'ATHLETE_UNAVAILABLE_TODAY' end];
  end if;

  evidence := public.derive_daily_coaching_evidence(
    metrics_jsonb,
    check_in.id is not null,
    check_in.pain_severity,
    health.id is not null
  );
  if outcome = 'rest_as_chosen' then evidence := evidence || rules; end if;

  snapshot_features := jsonb_build_object(
    'local_date',coaching_date,'timezone',coaching_timezone,
    'active_plan_version_id',plan_id,'active_nutrition_target_id',target_id,
    'check_in',case when check_in.id is null then null else jsonb_build_object(
      'sleep_quality',check_in.sleep_quality,'energy',check_in.energy,
      'soreness',check_in.soreness,'hunger',check_in.hunger,'mood',check_in.mood,
      'pain_severity',check_in.pain_severity,'available_to_train',check_in.available_to_train) end,
    'health_present_types',coalesce(to_jsonb(health.present_types),'[]'::jsonb)
  );

  snapshot_features := snapshot_features ||
    coalesce(metrics_jsonb, jsonb_build_object('scores_unavailable', true));
  snapshot_features := snapshot_features || jsonb_build_object('eligibility', eligibility_jsonb);

  snapshot_hash := encode(extensions.digest(convert_to(snapshot_features::text,'UTF8'),'sha256'),'hex');
  insert into public.feature_snapshots(user_id,trigger_kind,schema_version,feature_engine_version,features,coverage,missing_data,data_hash)
    values(target_user_id,'daily','2.0','daily-v2',snapshot_features,
      jsonb_build_object('check_in',check_in.id is not null,'health',health.id is not null),missing,snapshot_hash)
    on conflict(user_id,data_hash) do update set data_hash=excluded.data_hash returning id into snapshot_id;
  insert into public.policy_evaluations(user_id,feature_snapshot_id,policy_version,outcome,rule_codes,permitted_actions,prohibited_actions)
    values(target_user_id,snapshot_id,'daily-v1',outcome,rules,
      case outcome when 'escalate' then array['ESCALATE'] when 'rest_as_chosen' then array['REST_AS_CHOSEN','MAINTAIN_TARGETS','PRIORITIZE_PROTEIN'] when 'request_data' then array['GATHER_DATA','MAINTAIN_TARGETS'] else array['PROCEED_AS_PLANNED','GATHER_DATA','MAINTAIN_TARGETS'] end,
      array['PERSISTENT_CHANGE']) returning id into policy_id;
  return jsonb_build_object('replayed',false,'feature_snapshot_id',snapshot_id,
    'policy_evaluation_id',policy_id,'policy_outcome',outcome,
    'permitted_evidence',evidence,'missing_data',missing);
end $$;
revoke all on function private.prepare_daily_coaching_core(uuid,date,text,uuid,boolean)
  from public, anon, authenticated;

-- R12. A daily decision may cite the two new codes (20261015120011 plus the codes).
create or replace function public.persist_daily_coaching_result_v2(
  target_user_id uuid,snapshot_id uuid,policy_id uuid,request_idempotency_key uuid,
  decision_payload jsonb,run_latency_ms integer,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric
) returns jsonb language plpgsql security definer set search_path='' as $$
declare run_id uuid; decision_id uuid; policy public.policy_evaluations%rowtype;
begin
  select * into policy from public.policy_evaluations where id=policy_id and user_id=target_user_id and feature_snapshot_id=snapshot_id;
  if not found then raise exception 'policy not found' using errcode='P0002'; end if;
  if run_provider not in ('mock','gemini','groq','deepseek','anthropic') or length(run_model) not between 1 and 120
    or run_input_units not between 0 and 1000000 or run_output_units not between 0 and 100000
    or run_estimated_cost_usd < 0 or run_estimated_cost_usd > 100
  then raise exception 'invalid provider metadata' using errcode='22023'; end if;
  if jsonb_typeof(decision_payload)<>'object' or decision_payload->>'schema_version'<>'1.0'
    or decision_payload->>'decision_kind'<>'daily' or jsonb_array_length(decision_payload->'change_proposals')<>0
  then raise exception 'invalid decision' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(decision_payload->'evidence') e where not (e->>'code'=any(array[
    'APPROVED_PLAN_ACTIVE','CHECK_IN_SAFETY_ESCALATION','HEALTH_CONTEXT_AVAILABLE',
    'RECOVERY_WITHIN_BASELINE','RECOVERY_BELOW_BASELINE','CHECK_IN_RECOVERY_MIXED',
    'SLEEP_QUALITY_GOOD','SLEEP_QUALITY_POOR',
    'TRAINING_LOAD_OPTIMAL','TRAINING_LOAD_ELEVATED',
    'WEIGHT_TRENDING_DOWN','WEIGHT_TRENDING_UP','WEIGHT_STABLE',
    'NUTRITION_ON_TRACK','NUTRITION_BEHIND',
    'DATA_CONFIDENCE_HIGH','DATA_CONFIDENCE_LOW',
    'ATHLETE_UNAVAILABLE_TODAY','TRAINING_PAUSED'])))
  then raise exception 'unsupported evidence' using errcode='22023'; end if;
  insert into public.model_runs(user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,provider,model,prompt_version,schema_version,status,validation_status,input_units,output_units,estimated_cost_usd,latency_ms)
  values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'daily_coaching',run_provider,run_model,'daily-v1','1.0','succeeded','passed',run_input_units,run_output_units,run_estimated_cost_usd,run_latency_ms)
  on conflict(user_id,idempotency_key) do update set idempotency_key=excluded.idempotency_key returning id into run_id;
  select id into decision_id from public.coach_decisions where model_run_id=run_id;
  if decision_id is null then
    insert into public.coach_decisions(user_id,feature_snapshot_id,policy_evaluation_id,model_run_id,decision_kind,local_date,schema_version,training,nutrition,head_coach,evidence,confidence,missing_data,risk_flags,valid_until)
    values(target_user_id,snapshot_id,policy_id,run_id,'daily',(decision_payload->>'local_date')::date,'1.0',decision_payload->'training',decision_payload->'nutrition',decision_payload->'head_coach',decision_payload->'evidence',decision_payload->>'confidence',array(select jsonb_array_elements_text(decision_payload->'missing_data')),array(select jsonb_array_elements_text(decision_payload->'risk_flags')),now()+interval '24 hours') returning id into decision_id;
    insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
    values(target_user_id,'coach.decision.created','coach_decision',decision_id,'succeeded',jsonb_build_object('policy_outcome',policy.outcome,'schema_version','1.0','provider',run_provider,'model',run_model));
  end if;
  return jsonb_build_object('decision_id',decision_id,'model_run_id',run_id,'replayed',false);
end $$;

-- R13. prepare_coach_chat_v5 no longer reads coach_session_summaries (20260719090000 minus the read;
-- v9 already left the journal out of every chat context).
create or replace function public.prepare_coach_chat_v5(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  prepared jsonb; c jsonb; coaching_date date;
  snapshot_id uuid; checksum text; ctx_kind text;
  narrative jsonb; preferences jsonb;
  context_len integer;
begin
  prepared := public.prepare_coach_chat_v4(target_user_id, target_thread_id,
    question, coaching_timezone, request_idempotency_key, context_kind);
  if coalesce((prepared->>'replayed')::boolean, false) then return prepared; end if;

  c := prepared->'context';
  coaching_date := coalesce((c->>'coaching_date')::date, current_date);

  c := c || jsonb_build_object('schema_version', '4.0');

select coalesce(jsonb_build_object(
    'active', (select jsonb_build_object('phase', phase, 'headline', headline, 'since', since)
      from public.coach_narrative_entries where user_id = target_user_id
        and until is null order by since desc limit 1),
    'recent', (select coalesce(jsonb_agg(entry), '[]'::jsonb) from (
      select jsonb_build_object('phase', phase, 'headline', headline, 'since', since, 'until', until) entry
      from public.coach_narrative_entries where user_id = target_user_id
        and (until is not null or id = (select id from public.coach_narrative_entries
          where user_id = target_user_id and until is null order by since desc limit 1))
      order by since desc limit 4) s)
    ), jsonb_build_object('active', '{}'::jsonb, 'recent', '[]'::jsonb)) into narrative;
  c := c || jsonb_build_object('coaching_narrative', narrative);

  select coalesce(jsonb_agg(pref), '[]'::jsonb) into preferences
    from (
      select jsonb_build_object('id', id, 'category', category, 'key', key, 'value', value, 'provenance', provenance) pref
      from public.user_preferences
      where user_id = target_user_id and superseded_at is null
      order by category, key
    ) s;
  c := c || jsonb_build_object('active_preferences', preferences);

  -- Budget guard: if the fully assembled context exceeds 40K chars, trim
  -- the highest-volume arrays to keep the Edge Function's 32K budget
  -- reachable after key-abbreviation compaction and Tier 1-3 trimming.
  context_len := length(c::text);
  if context_len > 40000 then
    c := c || jsonb_build_object(
      'recent_messages',
      (select coalesce(jsonb_agg(elem), '[]'::jsonb)
       from (select jsonb_array_elements(c->'recent_messages') elem limit 10) s),
      'recent_other_conversations',
      (select coalesce(jsonb_agg(elem), '[]'::jsonb)
       from (select jsonb_array_elements(c->'recent_other_conversations') elem limit 10) s),
      'context_trimming_applied', true
    );
  end if;

  checksum := encode(extensions.digest(convert_to(c::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.coach_context_snapshots(user_id, thread_id, schema_version, trigger_kind,
    coaching_date, context, context_checksum)
  values(target_user_id, target_thread_id, '4.0', 'chat', coaching_date, c, checksum)
  returning id into snapshot_id;
  return prepared || jsonb_build_object('context', c, 'coach_context_snapshot_id', snapshot_id);
end $$;
revoke all on function public.prepare_coach_chat_v5(uuid,uuid,text,text,uuid,text)
  from public, anon, authenticated;
grant execute on function public.prepare_coach_chat_v5(uuid,uuid,text,text,uuid,text)
  to service_role;
