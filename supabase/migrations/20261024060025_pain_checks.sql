-- B5-1: the pain check, red flags and joint rules (server side).
--
-- An athlete who has pain says where it is, how strong, when it hurts and whether any of a short
-- list of red flags applies. The database works out the outcome from those answers alone (no model,
-- no free text) and keeps it: a stored outcome can never disagree with its answers. A red flag or a
-- pain of 7 or more routes out: no training advice, a referral, and the area is held until the
-- athlete says a clinician has cleared it. Pain of 4 to 6 limits the area for a week, pain of 1 to 3
-- puts it on watch. A joint that is held, limited or on watch changes today's session through the
-- same day adjustment B4 built: a lower-stress swap from the catalog, a shorter pain-free range with
-- the load held, or leaving the exercise out. Nothing here diagnoses or prescribes rehab.
--
--   1. private.pain_rules, pain_red_flag_codes, pain_outcome        the rules and the outcome table
--   2. public.pain_reports                                          the athlete's answers and outcomes
--   3. private.insert_pain_report                                   one writer for both entry points
--   4. public.save_daily_check_in                                   the check-in may carry a pain check
--   5. public.record_pain_check_v1                                  the workout's pain or discomfort chip
--   6. private.joint_states                                         held / limited / watch per area
--   7. private.joint_rules, stress and level ranks, joint_swap, range_note_code, joint_options,
--      joint_changes, merge_day_changes, day_changes_merged         what a joint state changes today
--   8. day_adjustments: the joint_adjust kind, the safety routes, joint changes in every kind
--      (private.readiness_rank, day_adjustment_explanation, day_adjustment_compute,
--      day_adjustment_stands, day_adjustment_present), payload schema 1.1
--   9. public.start_workout                                         a left-out exercise gets no sets
--  10. private.next_session_targets                                 a joint accommodation never lowers a load
--  11. public.get_readiness_context_v1                              the read-only view for Coach context
--
-- Everything is additive: a new table, new functions, and redefinitions that keep every earlier
-- behaviour for an athlete with no pain report. Old app builds send no pain keys and see the
-- payload's old keys unchanged.

-- 1. The rules ----------------------------------------------------------------------------------------
-- Severity runs 0 to 10. A red flag always routes out, whatever the severity. Outcomes, strictest
-- first: urgent, clinician_today, clinician (all three hold the area), then modify (4 to 6, the area
-- is limited), watch (1 to 3) and clear (0). A report that did not ask about red flags (red_flags is
-- null: an older build, or a workout check that asks severity only) is judged by severity alone, and
-- 7 or more is clinician_today. A held area ends only when the athlete says a clinician cleared it
-- (cleared_by_clinician with a severity of 3 or less and no red flag), and then it is on watch for
-- 7 days; a new symptom always wins. An area's state lapses 7 days after its newest report. Every
-- number here is in-house (owner decision O8) except the red-flag questions, which follow the
-- published red-flag lists named in _shared/training/joints/rules.ts.

create function private.pain_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"version":"pain-v1","clinician_today_from":7,"modify_from":4,"watch_from":1,"clearance_max_severity":3,"lapse_days":7,"persistent_days":14,"persistent_min_severity":4,"reports_per_day":40,"red_flags":{"bladder_bowel_saddle":"urgent","chest_or_breath":"urgent","numb_weak_limb":"clinician_today","pop_or_sudden":"clinician_today","cannot_bear_or_move":"clinician_today","rapid_swelling":"clinician_today","dislocated_or_cannot_lift":"clinician_today","locks_gives_way":"clinician","fever_unwell":"clinician","night_pain":"clinician"}}'::jsonb;
$$;
revoke all on function private.pain_rules() from public, anon, authenticated;

create function private.pain_red_flag_codes()
returns text[] language sql immutable set search_path = '' as $$
  select array(select k from jsonb_object_keys(private.pain_rules() -> 'red_flags') k order by k);
$$;
revoke all on function private.pain_red_flag_codes() from public, anon, authenticated;

-- The outcome of one report. Pure: the same answers always give the same outcome.
create function private.pain_outcome(p_severity integer, p_red_flags text[])
returns text language sql immutable set search_path = '' as $$
  with r as (select private.pain_rules() as j)
  select case
    when exists (select 1 from unnest(coalesce(p_red_flags, '{}'::text[])) f, r
      where r.j -> 'red_flags' ->> f = 'urgent') then 'urgent'
    when p_severity >= (select (j ->> 'clinician_today_from')::integer from r)
      or exists (select 1 from unnest(coalesce(p_red_flags, '{}'::text[])) f, r
        where r.j -> 'red_flags' ->> f = 'clinician_today') then 'clinician_today'
    when exists (select 1 from unnest(coalesce(p_red_flags, '{}'::text[])) f, r
      where r.j -> 'red_flags' ->> f = 'clinician') then 'clinician'
    when p_severity >= (select (j ->> 'modify_from')::integer from r) then 'modify'
    when p_severity >= (select (j ->> 'watch_from')::integer from r) then 'watch'
    else 'clear' end;
$$;
revoke all on function private.pain_outcome(integer, text[]) from public, anon, authenticated;

-- 2. The reports --------------------------------------------------------------------------------------

create table public.pain_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  local_date date not null,
  source text not null check (source in ('check_in', 'workout')),
  check_in_id uuid,
  exercise_performance_id uuid,
  area text not null check (area in ('knee', 'back', 'shoulder', 'other')),
  severity smallint not null check (severity between 0 and 10),
  pattern text check (pattern in ('movement', 'rest')),
  red_flags text[] check (
    red_flags is null
    or (cardinality(red_flags) <= 10 and red_flags <@ private.pain_red_flag_codes())),
  cleared_by_clinician boolean not null default false,
  outcome text not null check (
    outcome in ('urgent', 'clinician_today', 'clinician', 'modify', 'watch', 'clear')),
  idempotency_key uuid,
  created_at timestamptz not null default now(),
  foreign key (check_in_id, user_id) references public.daily_check_ins (id, user_id),
  foreign key (exercise_performance_id, user_id)
    references public.exercise_performances (id, user_id),
  unique (id, user_id),
  unique (check_in_id, area),
  check (check_in_id is null or source = 'check_in'),
  check (exercise_performance_id is null or source = 'workout'),
  constraint pain_reports_outcome_matches_answers check (
    outcome = private.pain_outcome(severity::integer, red_flags))
);

create unique index pain_reports_idempotency
  on public.pain_reports (user_id, idempotency_key) where idempotency_key is not null;
create index pain_reports_user_area_newest
  on public.pain_reports (user_id, area, local_date desc, created_at desc);

comment on table public.pain_reports is
  'The athlete''s pain checks (rules pain-v1): area, severity, pattern, the red-flag answers and the outcome the database worked out from them. Append-only; the newest report per area sets the area''s state. Restricted health data.';
comment on column public.pain_reports.red_flags is
  'Codes from private.pain_red_flag_codes(). An empty array: the athlete chose "none of these". Null: the question was not asked (an older build, or a check that asks severity only).';
comment on column public.pain_reports.cleared_by_clinician is
  'The athlete says a doctor or physio has cleared them to train this area. Self-attested; only meaningful on a follow-up for a held area.';
comment on column public.pain_reports.outcome is
  'Computed by private.pain_outcome from severity and red_flags; a constraint keeps it equal.';

alter table public.pain_reports enable row level security;
alter table public.pain_reports force row level security;
create policy pain_reports_own_read on public.pain_reports
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.pain_reports from anon, authenticated;
grant select on public.pain_reports to authenticated;

-- 3. One writer ---------------------------------------------------------------------------------------
-- Validates and stores one report and records the audit event (codes only: source, area, outcome).
-- Errors: 22023 an unknown area, pattern or red-flag code, or a severity outside 0 to 10; P0001 too
-- many reports today.

create function private.insert_pain_report(
  p_user uuid, p_date date, p_source text, p_check_in uuid, p_performance uuid, p_area text,
  p_severity integer, p_pattern text, p_flags text[], p_cleared boolean, p_key uuid
) returns public.pain_reports language plpgsql security definer set search_path = '' as $$
declare
  flags text[];
  created public.pain_reports%rowtype;
begin
  if p_area is null or p_area <> all (array['knee', 'back', 'shoulder', 'other']) then
    raise exception 'unknown pain area' using errcode = '22023';
  end if;
  if p_severity is null or p_severity not between 0 and 10 then
    raise exception 'pain severity must be 0 to 10' using errcode = '22023';
  end if;
  if p_pattern is not null and p_pattern <> all (array['movement', 'rest']) then
    raise exception 'unknown pain pattern' using errcode = '22023';
  end if;
  if p_cleared is null then
    raise exception 'cleared_by_clinician must be true or false' using errcode = '22023';
  end if;
  if p_flags is not null then
    if exists (select 1 from unnest(p_flags) f where f is null or f <> all (private.pain_red_flag_codes())) then
      raise exception 'unknown red flag' using errcode = '22023';
    end if;
    flags := array(select distinct f from unnest(p_flags) f order by f);
  end if;
  if (select count(*) from public.pain_reports r where r.user_id = p_user and r.local_date = p_date)
     >= (private.pain_rules() ->> 'reports_per_day')::integer then
    raise exception 'too many pain reports today' using errcode = 'P0001';
  end if;

  insert into public.pain_reports(user_id, local_date, source, check_in_id, exercise_performance_id,
    area, severity, pattern, red_flags, cleared_by_clinician, outcome, idempotency_key)
  values (p_user, p_date, p_source, p_check_in, p_performance, p_area, p_severity, p_pattern, flags,
    p_cleared, private.pain_outcome(p_severity, flags), p_key)
  returning * into created;

  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (p_user, 'pain_check_recorded', 'pain_report', created.id, 'succeeded',
    jsonb_build_object('source', p_source, 'area', p_area, 'outcome', created.outcome));
  return created;
end $$;
revoke all on function private.insert_pain_report(
  uuid, date, text, uuid, uuid, text, integer, text, text[], boolean, uuid)
  from public, anon, authenticated;

-- 4. The check-in -------------------------------------------------------------------------------------
-- The definition of 20260701120000_phase_3_workout_check_in.sql plus the optional pain check. A build
-- that asks the pain questions sends pain_area, pain_pattern, pain_red_flags (an array: empty is "none
-- of these"), pain_cleared_by_clinician and pain_followups (a list of {area, severity,
-- cleared_by_clinician} for areas that were already limited, held or on watch). Any of those keys marks
-- a new build, and then a pain above 0 needs an area and the red-flag answer, and flags need an area:
-- nothing is dropped silently (22023). A build that sends none of them behaves exactly as before.

create or replace function public.save_daily_check_in(local_date date, timezone text, idempotency_key uuid, payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; next_revision integer;
  new_build boolean; pain integer; main_area text; main_flags text[]; main_pattern text;
  main_cleared boolean := false; follow jsonb; follow_areas text[] := '{}'; follow_area text;
  follow_severity integer; follow_cleared boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select id into result_id from public.daily_check_ins c where c.user_id=auth.uid() and c.idempotency_key=save_daily_check_in.idempotency_key;
  if result_id is not null then return result_id; end if;
  if not (payload ?& array['sleep_quality','energy','soreness','hunger','mood','available_to_train']) then raise exception 'incomplete check-in' using errcode='22023'; end if;

  new_build := payload ?| array['pain_area','pain_pattern','pain_red_flags','pain_cleared_by_clinician','pain_followups'];
  if new_build then
    pain := coalesce((payload->>'pain_severity')::integer, 0);
    if jsonb_typeof(payload->'pain_area') = 'string' then
      main_area := payload->>'pain_area';
    elsif payload->'pain_area' is not null and jsonb_typeof(payload->'pain_area') <> 'null' then
      raise exception 'pain_area must be text' using errcode='22023';
    end if;
    if main_area is null then
      if pain > 0 then raise exception 'pain needs an area' using errcode='22023'; end if;
      if (payload->'pain_red_flags' is not null and jsonb_typeof(payload->'pain_red_flags') <> 'null'
            and payload->'pain_red_flags' <> '[]'::jsonb)
         or (payload->'pain_pattern' is not null and jsonb_typeof(payload->'pain_pattern') <> 'null')
         or (payload->'pain_cleared_by_clinician' is not null
            and payload->'pain_cleared_by_clinician' not in ('null'::jsonb, 'false'::jsonb)) then
        raise exception 'pain answers need an area' using errcode='22023';
      end if;
    else
      if pain < 1 then raise exception 'a pain area needs a pain above 0' using errcode='22023'; end if;
      if jsonb_typeof(payload->'pain_red_flags') is distinct from 'array' then
        raise exception 'pain_red_flags must be a list' using errcode='22023';
      end if;
      if exists (select 1 from jsonb_array_elements(payload->'pain_red_flags') f
          where jsonb_typeof(f) is distinct from 'string') then
        raise exception 'pain_red_flags must be a list of codes' using errcode='22023';
      end if;
      main_flags := array(select jsonb_array_elements_text(payload->'pain_red_flags'));
      if payload->'pain_pattern' is not null and jsonb_typeof(payload->'pain_pattern') = 'string' then
        main_pattern := payload->>'pain_pattern';
      elsif payload->'pain_pattern' is not null and jsonb_typeof(payload->'pain_pattern') <> 'null' then
        raise exception 'pain_pattern must be text' using errcode='22023';
      end if;
      if payload->'pain_cleared_by_clinician' is not null
         and jsonb_typeof(payload->'pain_cleared_by_clinician') <> 'null' then
        if jsonb_typeof(payload->'pain_cleared_by_clinician') is distinct from 'boolean' then
          raise exception 'pain_cleared_by_clinician must be true or false' using errcode='22023';
        end if;
        main_cleared := (payload->>'pain_cleared_by_clinician')::boolean;
      end if;
    end if;
    if payload->'pain_followups' is not null and jsonb_typeof(payload->'pain_followups') <> 'null' then
      if jsonb_typeof(payload->'pain_followups') is distinct from 'array' then
        raise exception 'pain_followups must be a list' using errcode='22023';
      end if;
      follow_areas := case when main_area is null then '{}'::text[] else array[main_area] end;
      for follow in select value from jsonb_array_elements(payload->'pain_followups') loop
        if jsonb_typeof(follow) is distinct from 'object'
           or jsonb_typeof(follow->'area') is distinct from 'string'
           or jsonb_typeof(follow->'severity') is distinct from 'number'
           or (follow->>'severity')::numeric <> trunc((follow->>'severity')::numeric)
           or (follow->'cleared_by_clinician' is not null
              and jsonb_typeof(follow->'cleared_by_clinician') not in ('boolean', 'null')) then
          raise exception 'a pain follow-up needs an area and a whole severity' using errcode='22023';
        end if;
        follow_area := follow->>'area';
        if follow_area = any(follow_areas) then
          raise exception 'one pain report per area in a check-in' using errcode='22023';
        end if;
        follow_areas := follow_areas || follow_area;
      end loop;
    end if;
  end if;

  select coalesce(max(revision),0)+1 into next_revision from public.daily_check_ins c where c.user_id=auth.uid() and c.local_date=save_daily_check_in.local_date;
  update public.daily_check_ins c set superseded_at=now() where c.user_id=auth.uid() and c.local_date=save_daily_check_in.local_date and superseded_at is null;
  insert into public.daily_check_ins(user_id,local_date,timezone,revision,idempotency_key,sleep_quality,energy,soreness,hunger,mood,pain_severity,available_to_train,note)
  values(auth.uid(),local_date,timezone,next_revision,idempotency_key,(payload->>'sleep_quality')::smallint,(payload->>'energy')::smallint,(payload->>'soreness')::smallint,(payload->>'hunger')::smallint,(payload->>'mood')::smallint,coalesce((payload->>'pain_severity')::smallint,0),(payload->>'available_to_train')::boolean,coalesce(payload->>'note','')) returning id into result_id;

  if main_area is not null then
    perform private.insert_pain_report(auth.uid(), save_daily_check_in.local_date, 'check_in',
      result_id, null, main_area, pain, main_pattern, main_flags, main_cleared, null);
  end if;
  if new_build and payload->'pain_followups' is not null
     and jsonb_typeof(payload->'pain_followups') = 'array' then
    for follow in select value from jsonb_array_elements(payload->'pain_followups') loop
      follow_severity := ((follow->>'severity')::numeric)::integer;
      follow_cleared := coalesce((follow->>'cleared_by_clinician')::boolean, false);
      perform private.insert_pain_report(auth.uid(), save_daily_check_in.local_date, 'check_in',
        result_id, null, follow->>'area', follow_severity, null, null, follow_cleared, null);
    end loop;
  end if;
  return result_id;
end $$;

-- 5. The workout's pain chip --------------------------------------------------------------------------
-- A pain check made during a workout (the "Pain or discomfort" chip). Idempotent by key. source is
-- 'workout' (a check made outside a check-in may use 'check_in'); a performance, when given, must be
-- the athlete's own and goes with 'workout' only. The date is the athlete's own day, never a future
-- one. Returns {schema_version, id, outcome, area_state}. Errors: 42501 signed out; 22023 a bad
-- value, a future date or a performance that is not theirs; P0001 too many reports today.

create function public.record_pain_check_v1(
  local_date date, source text, area text, severity integer, pattern text, red_flags text[],
  cleared_by_clinician boolean, exercise_performance_id uuid, idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  report public.pain_reports%rowtype;
  state text;
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if record_pain_check_v1.idempotency_key is null then
    raise exception 'an idempotency key is required' using errcode = '22023';
  end if;
  select * into report from public.pain_reports r
  where r.user_id = uid and r.idempotency_key = record_pain_check_v1.idempotency_key;
  if not found then
    if record_pain_check_v1.local_date is null
       or record_pain_check_v1.local_date > private.local_date_for(uid) then
      raise exception 'a pain check is for today or earlier' using errcode = '22023';
    end if;
    if record_pain_check_v1.source is null
       or record_pain_check_v1.source <> all (array['check_in', 'workout']) then
      raise exception 'unknown source' using errcode = '22023';
    end if;
    if record_pain_check_v1.exercise_performance_id is not null and (
         record_pain_check_v1.source <> 'workout'
         or not exists (select 1 from public.exercise_performances p
           where p.id = record_pain_check_v1.exercise_performance_id and p.user_id = uid)) then
      raise exception 'that exercise is not yours to report on' using errcode = '22023';
    end if;
    report := private.insert_pain_report(uid, record_pain_check_v1.local_date,
      record_pain_check_v1.source, null, record_pain_check_v1.exercise_performance_id,
      record_pain_check_v1.area, record_pain_check_v1.severity, record_pain_check_v1.pattern,
      record_pain_check_v1.red_flags, record_pain_check_v1.cleared_by_clinician,
      record_pain_check_v1.idempotency_key);
  end if;
  select s ->> 'state' into state
  from jsonb_array_elements(private.joint_states(uid, report.local_date)) s
  where s ->> 'area' = report.area;
  return jsonb_build_object('schema_version', '1.0', 'id', report.id, 'outcome', report.outcome,
    'area_state', coalesce(state, 'none'));
end $$;
revoke all on function public.record_pain_check_v1(
  date, text, text, integer, text, text[], boolean, uuid, uuid) from public, anon, authenticated;
grant execute on function public.record_pain_check_v1(
  date, text, text, integer, text, text[], boolean, uuid, uuid) to authenticated;

-- 6. Joint states -------------------------------------------------------------------------------------
-- Per area (knee, back, shoulder, other), from its reports up to p_date, newest first (by day, then by
-- when the report was stored):
--   held        the newest report with a held outcome (urgent, clinician_today, clinician) is not
--               followed by a clearance: a report with cleared_by_clinician, a severity of 3 or less
--               and no red flag. A held area ends only by clearance.
--   limited     otherwise, the newest report is 7 days old at most and has a severity of 4 to 6.
--   watch       the same with a severity of 1 to 3; also 7 days after a clearance, whatever the severity
--               the clearance carried (a later report of 0 ends it).
--   none        no report, a report older than 7 days, or a newest report of 0.
-- persistent: the area is limited or held and either it has been held for 14 days or more, or its
-- current episode (the reports after the newest report of 0 or the newest clearance) holds at least two
-- reports of severity 4 or more, the first at least 14 days ago.
-- Returns [{area, state, since, severity, persistent}] for the areas not at none. since is the day the
-- hold began (held) or the day of the newest report (limited, watch); severity is the newest report's.

create function private.joint_states(p_user uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r constant jsonb := private.pain_rules();
  held constant text[] := array['urgent', 'clinician_today', 'clinician'];
  joint_area text;
  newest public.pain_reports%rowtype;
  latest_hold public.pain_reports%rowtype;
  clearance public.pain_reports%rowtype;
  boundary public.pain_reports%rowtype;
  has_hold boolean;
  has_clearance boolean;
  has_boundary boolean;
  state text;
  since date;
  hold_start date;
  strong_reports integer;
  first_strong date;
  persistent boolean;
  found_states jsonb := '[]'::jsonb;
begin
  foreach joint_area in array array['knee', 'back', 'shoulder', 'other'] loop
    select * into newest from public.pain_reports p
    where p.user_id = p_user and p.area = joint_area and p.local_date <= p_date
    order by p.local_date desc, p.created_at desc, p.id desc limit 1;
    if not found then continue; end if;

    select * into latest_hold from public.pain_reports p
    where p.user_id = p_user and p.area = joint_area and p.local_date <= p_date
      and p.outcome = any(held)
    order by p.local_date desc, p.created_at desc, p.id desc limit 1;
    has_hold := found;

    select * into clearance from public.pain_reports p
    where p.user_id = p_user and p.area = joint_area and p.local_date <= p_date
      and p.cleared_by_clinician
      and p.severity <= (r ->> 'clearance_max_severity')::integer
      and coalesce(cardinality(p.red_flags), 0) = 0
      and exists (select 1 from public.pain_reports h
        where h.user_id = p_user and h.area = joint_area and h.local_date <= p_date
          and h.outcome = any(held)
          and (h.local_date, h.created_at, h.id) < (p.local_date, p.created_at, p.id))
    order by p.local_date desc, p.created_at desc, p.id desc limit 1;
    has_clearance := found;

    state := 'none';
    since := null;
    hold_start := null;
    if has_hold and not (has_clearance
        and (clearance.local_date, clearance.created_at, clearance.id)
          > (latest_hold.local_date, latest_hold.created_at, latest_hold.id)) then
      state := 'held';
      select min(p.local_date) into hold_start from public.pain_reports p
      where p.user_id = p_user and p.area = joint_area and p.local_date <= p_date
        and p.outcome = any(held)
        and (not has_clearance
          or (p.local_date, p.created_at, p.id)
            > (clearance.local_date, clearance.created_at, clearance.id));
      since := hold_start;
    elsif p_date - newest.local_date <= (r ->> 'lapse_days')::integer then
      if has_clearance and newest.id = clearance.id then
        state := 'watch';
      elsif newest.severity >= (r ->> 'modify_from')::integer then
        state := 'limited';
      elsif newest.severity >= (r ->> 'watch_from')::integer then
        state := 'watch';
      end if;
      if state <> 'none' then since := newest.local_date; end if;
    end if;
    if state = 'none' then continue; end if;

    select * into boundary from public.pain_reports p
    where p.user_id = p_user and p.area = joint_area and p.local_date <= p_date
      and (p.outcome = 'clear' or (has_clearance and p.id = clearance.id))
    order by p.local_date desc, p.created_at desc, p.id desc limit 1;
    has_boundary := found;
    select count(*), min(p.local_date) into strong_reports, first_strong
    from public.pain_reports p
    where p.user_id = p_user and p.area = joint_area and p.local_date <= p_date
      and p.severity >= (r ->> 'persistent_min_severity')::integer
      and (not has_boundary
        or (p.local_date, p.created_at, p.id)
          > (boundary.local_date, boundary.created_at, boundary.id));
    persistent := state in ('limited', 'held') and (
      (state = 'held' and p_date - hold_start >= (r ->> 'persistent_days')::integer)
      or (strong_reports >= 2
        and p_date - first_strong >= (r ->> 'persistent_days')::integer));

    found_states := found_states || jsonb_build_object('area', joint_area, 'state', state,
      'since', since, 'severity', newest.severity, 'persistent', persistent);
  end loop;
  return found_states;
end $$;
revoke all on function private.joint_states(uuid, date) from public, anon, authenticated;

-- 7. What a joint state changes in today's session ---------------------------------------------------
-- Ratings are the catalog's knee_stress, back_stress and shoulder_stress (B1, in-house). An exercise
-- with no catalog link is treated as moderate on every joint, so missing data lowers what is allowed
-- and never raises it. Per exercise the strictest action over the three joints wins (drop, then swap,
-- then limit; then the more restricted state; then the higher stress; then knee, back, shoulder):
--   held     high or moderate   swap to a low-stress exercise, else drop (no sets)
--   limited  high               swap to a low or moderate one, else drop
--   limited  moderate           limit: keep the exercise with a pain-free range note, last load held,
--                               effort at 7 or lower
--   watch    high               limit
--   anything else (low stress, watch with moderate) is left as planned.
-- A swap keeps the sets, reps and effort and carries no starting load. A candidate comes from the
-- exercise's substitutes, then its regressions, then the same movement pattern, then a shared primary
-- muscle, and must be strictly gentler on the joint, never harsher on any joint, within the athlete's
-- equipment and level, not a movement they avoid, not already in today's session, and gentle enough on
-- every other joint that is held, limited or on watch.

create function private.joint_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"version":"joint-v1","actions":{"held":{"high":"swap","moderate":"swap"},"limited":{"high":"swap","moderate":"limit"},"watch":{"high":"limit"}},"swap_max_stress":{"held":"low","limited":"moderate"},"other_joint_cap":{"held":"low","limited":"low","watch":"moderate"},"options_max_stress":"low","limit_rpe_max":7,"unrated_stress":"moderate"}'::jsonb;
$$;
revoke all on function private.joint_rules() from public, anon, authenticated;

create function private.stress_rank(p_stress text)
returns integer language sql immutable set search_path = '' as $$
  select case p_stress when 'low' then 1 when 'moderate' then 2 when 'high' then 3 end;
$$;
revoke all on function private.stress_rank(text) from public, anon, authenticated;

create function private.level_rank(p_level text)
returns integer language sql immutable set search_path = '' as $$
  select case p_level when 'beginner' then 1 when 'intermediate' then 2 when 'advanced' then 3 end;
$$;
revoke all on function private.level_rank(text) from public, anon, authenticated;

-- How strict an action is: none 0, limit 1, swap 2, drop 3.
create function private.joint_action_rank(p_action text)
returns integer language sql immutable set search_path = '' as $$
  select case p_action when 'limit' then 1 when 'swap' then 2 when 'drop' then 3 else 0 end;
$$;
revoke all on function private.joint_action_rank(text) from public, anon, authenticated;

-- How strict a safety route is: urgent 4, clinician_today 3, pain_referral 2, clinician 1.
create function private.safety_route_rank(p_route text)
returns integer language sql immutable set search_path = '' as $$
  select case p_route when 'urgent' then 4 when 'clinician_today' then 3 when 'pain_referral' then 2
    when 'clinician' then 1 else 0 end;
$$;
revoke all on function private.safety_route_rank(text) from public, anon, authenticated;

-- The range-limit cue for a joint and a movement pattern (coaching cues, not rehab). Any other pair
-- gets the generic one.
create function private.range_note_code(p_joint text, p_pattern text)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_joint = 'knee' and p_pattern = 'squat' then 'knee_squat_depth'
    when p_joint = 'knee' and p_pattern = 'lunge' then 'knee_lunge_depth'
    when p_joint = 'knee' and p_pattern = 'quads_isolation' then 'knee_extension_partial'
    when p_joint = 'back' and p_pattern = 'hinge' then 'back_hinge_range'
    when p_joint = 'back' and p_pattern = 'squat' then 'back_squat_depth'
    when p_joint = 'back' and p_pattern = 'core' then 'back_core_neutral'
    when p_joint = 'back' and p_pattern = 'vertical_push' then 'back_press_seated'
    when p_joint = 'shoulder' and p_pattern = 'vertical_push' then 'shoulder_press_height'
    when p_joint = 'shoulder' and p_pattern = 'horizontal_push' then 'shoulder_press_depth'
    when p_joint = 'shoulder' and p_pattern = 'chest_fly' then 'shoulder_fly_stretch'
    when p_joint = 'shoulder' and p_pattern = 'vertical_pull' then 'shoulder_pull_range'
    when p_joint = 'shoulder' and p_pattern = 'lateral_raise' then 'shoulder_raise_height'
    else 'generic_pain_free' end;
$$;
revoke all on function private.range_note_code(text, text) from public, anon, authenticated;

-- A gentler catalog exercise for p_slug on p_joint, as {slug, name}, or null when none qualifies (or
-- when the exercise has no catalog entry to anchor on). p_caps: {joint: highest stress} for the other
-- joints. Order: substitutes, regressions, same pattern, shared muscle; then gentler on the joint; then
-- the same compound-ness; then a standard form before a variation before a regression; then slug.
create function private.joint_swap(
  p_slug text, p_joint text, p_max_stress text, p_equipment text[], p_level text,
  p_avoid text[], p_exclude text[], p_caps jsonb default '{}'::jsonb
) returns jsonb language sql stable security definer set search_path = '' as $$
with o as (
  select c.* from public.exercise_catalog c where c.slug = p_slug
), cand as (
  select c.slug, c.name,
    case when c.slug = any(o.substitutes) then 1
      when c.slug = any(o.regressions) then 2
      when c.movement_pattern = o.movement_pattern then 3
      when c.primary_muscles && o.primary_muscles then 4 end as tier,
    private.stress_rank(case p_joint when 'knee' then c.knee_stress when 'back' then c.back_stress
      else c.shoulder_stress end) as joint_rank,
    private.stress_rank(case p_joint when 'knee' then o.knee_stress when 'back' then o.back_stress
      else o.shoulder_stress end) as original_joint_rank,
    private.stress_rank(c.knee_stress) as knee_rank, private.stress_rank(c.back_stress) as back_rank,
    private.stress_rank(c.shoulder_stress) as shoulder_rank,
    private.stress_rank(o.knee_stress) as o_knee, private.stress_rank(o.back_stress) as o_back,
    private.stress_rank(o.shoulder_stress) as o_shoulder,
    c.is_compound = o.is_compound as same_compound,
    case c.exercise_role when 'variation' then 1 when 'regression' then 2 else 0 end as role_order
  from public.exercise_catalog c cross join o
  where c.status = 'active' and c.slug <> o.slug
    and c.equipment_required <@ coalesce(p_equipment, '{}'::text[])
    and private.level_rank(c.level) <= private.level_rank(coalesce(p_level, 'beginner'))
    and (p_avoid is null or c.movement_pattern <> all (p_avoid))
    and (p_exclude is null or c.slug <> all (p_exclude))
)
select jsonb_build_object('slug', slug, 'name', name) from cand
where tier is not null
  and joint_rank <= private.stress_rank(p_max_stress) and joint_rank < original_joint_rank
  and knee_rank <= o_knee and back_rank <= o_back and shoulder_rank <= o_shoulder
  and (p_caps ->> 'knee' is null or knee_rank <= private.stress_rank(p_caps ->> 'knee'))
  and (p_caps ->> 'back' is null or back_rank <= private.stress_rank(p_caps ->> 'back'))
  and (p_caps ->> 'shoulder' is null or shoulder_rank <= private.stress_rank(p_caps ->> 'shoulder'))
order by tier, joint_rank, same_compound desc, role_order, slug
limit 1;
$$;
revoke all on function private.joint_swap(text, text, text, text[], text, text[], text[], jsonb)
  from public, anon, authenticated;

-- Per exercise of the workout, the gentlest swap on each joint (low stress, strictly gentler), so the
-- app can offer one the moment a pain check says to stop an exercise, even offline.
-- [{exercise_order, planned_exercise_id, name, joint_options: {knee, back, shoulder}}], each joint
-- {slug, name} or null.
create function private.joint_options(p_user uuid, p_workout uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  jr constant jsonb := private.joint_rules();
  equipment text[];
  lvl text;
  avoid text[];
  session_slugs text[];
begin
  select p.equipment, p.experience_level::text, p.avoid_patterns into equipment, lvl, avoid
  from public.user_profiles p where p.user_id = p_user;
  session_slugs := array(select e.exercise_slug from public.planned_exercises e
    where e.planned_workout_id = p_workout and e.user_id = p_user and e.exercise_slug is not null);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'exercise_order', e.exercise_order, 'planned_exercise_id', e.id,
      'name', e.display_name_snapshot,
      'joint_options', jsonb_build_object(
        'knee', private.joint_swap(e.exercise_slug, 'knee', jr ->> 'options_max_stress', equipment,
          lvl, avoid, session_slugs),
        'back', private.joint_swap(e.exercise_slug, 'back', jr ->> 'options_max_stress', equipment,
          lvl, avoid, session_slugs),
        'shoulder', private.joint_swap(e.exercise_slug, 'shoulder', jr ->> 'options_max_stress',
          equipment, lvl, avoid, session_slugs))) order by e.exercise_order)
    from public.planned_exercises e
    where e.planned_workout_id = p_workout and e.user_id = p_user), '[]'::jsonb);
end $$;
revoke all on function private.joint_options(uuid, uuid) from public, anon, authenticated;

-- The exercises of the workout a joint state changes, as change entries (the keys of
-- private.day_adjustment_changes plus joint_action, joint, joint_state, swap_to_slug, swap_to_name
-- and range_note_code). p_states: private.joint_states; p_hold: the hold_load changes, whose load and
-- rep fields a limited exercise keeps.
create function private.joint_changes(p_user uuid, p_workout uuid, p_states jsonb, p_hold jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  jr constant jsonb := private.joint_rules();
  states jsonb;
  equipment text[];
  lvl text;
  avoid text[];
  taken text[];
  entries jsonb := '[]'::jsonb;
  e record;
  joint text;
  joint_state text;
  stress text;
  action text;
  score integer;
  best_score integer;
  best_joint text;
  best_state text;
  best_action text;
  caps jsonb;
  other text;
  other_state text;
  candidate jsonb;
  hold_entry jsonb;
begin
  states := coalesce((select jsonb_object_agg(s ->> 'area', s ->> 'state')
    from jsonb_array_elements(coalesce(p_states, '[]'::jsonb)) s
    where s ->> 'area' in ('knee', 'back', 'shoulder')), '{}'::jsonb);
  if states = '{}'::jsonb then
    return entries;
  end if;
  select p.equipment, p.experience_level::text, p.avoid_patterns into equipment, lvl, avoid
  from public.user_profiles p where p.user_id = p_user;
  taken := array(select x.exercise_slug from public.planned_exercises x
    where x.planned_workout_id = p_workout and x.user_id = p_user and x.exercise_slug is not null);

  for e in
    select pe.id, pe.exercise_order, pe.display_name_snapshot as name, pe.set_count, pe.target_rpe,
      pe.exercise_slug, c.movement_pattern, c.knee_stress, c.back_stress, c.shoulder_stress
    from public.planned_exercises pe
    left join public.exercise_catalog c on c.slug = pe.exercise_slug
    where pe.planned_workout_id = p_workout and pe.user_id = p_user
    order by pe.exercise_order
  loop
    best_score := 0;
    best_joint := null;
    foreach joint in array array['knee', 'back', 'shoulder'] loop
      joint_state := states ->> joint;
      continue when joint_state is null;
      stress := coalesce(case joint when 'knee' then e.knee_stress when 'back' then e.back_stress
        else e.shoulder_stress end, jr ->> 'unrated_stress');
      action := jr -> 'actions' -> joint_state ->> stress;
      continue when action is null;
      score := private.joint_action_rank(action) * 100
        + case joint_state when 'held' then 30 when 'limited' then 20 else 10 end
        + private.stress_rank(stress);
      if score > best_score then
        best_score := score; best_joint := joint; best_state := joint_state; best_action := action;
      end if;
    end loop;
    continue when best_joint is null;

    candidate := null;
    if best_action = 'swap' then
      caps := '{}'::jsonb;
      foreach other in array array['knee', 'back', 'shoulder'] loop
        other_state := states ->> other;
        if other <> best_joint and other_state is not null then
          caps := caps || jsonb_build_object(other, jr -> 'other_joint_cap' ->> other_state);
        end if;
      end loop;
      candidate := private.joint_swap(e.exercise_slug, best_joint,
        jr -> 'swap_max_stress' ->> best_state, equipment, lvl, avoid, taken, caps);
      if candidate is null then
        best_action := 'drop';
      else
        taken := taken || (candidate ->> 'slug');
      end if;
    end if;

    hold_entry := case when best_action = 'limit' then (
      select h from jsonb_array_elements(coalesce(p_hold, '[]'::jsonb)) h
      where h ->> 'planned_exercise_id' = e.id::text limit 1) end;
    entries := entries || jsonb_build_object(
      'exercise_order', e.exercise_order,
      'planned_exercise_id', e.id,
      'name', e.name,
      'sets_from', e.set_count,
      'sets_to', case when best_action = 'drop' then 0 else e.set_count end,
      'load_note', hold_entry -> 'load_note',
      'load_kg_from', hold_entry -> 'load_kg_from',
      'load_kg_to', hold_entry -> 'load_kg_to',
      'reps_from', hold_entry -> 'reps_from',
      'reps_to', hold_entry -> 'reps_to',
      'rpe_to', case when best_action = 'limit' then
        least((jr ->> 'limit_rpe_max')::numeric, coalesce(e.target_rpe, (jr ->> 'limit_rpe_max')::numeric)) end,
      'joint_action', best_action,
      'joint', best_joint,
      'joint_state', best_state,
      'swap_to_slug', candidate ->> 'slug',
      'swap_to_name', candidate ->> 'name',
      'range_note_code', case when best_action = 'limit'
        then private.range_note_code(best_joint, e.movement_pattern) end);
  end loop;
  return entries;
end $$;
revoke all on function private.joint_changes(uuid, uuid, jsonb, jsonb) from public, anon, authenticated;

-- A kind's changes with the joint changes laid over them: one entry per exercise, the stricter value
-- for each field (fewer sets, lower effort); a swapped or left-out exercise carries no load or reps,
-- and a left-out one no effort target. p_joint empty returns p_base as it is.
create function private.merge_day_changes(p_base jsonb, p_joint jsonb)
returns jsonb language sql immutable set search_path = '' as $$
with b as (
  select x, (x ->> 'exercise_order')::integer as o from jsonb_array_elements(coalesce(p_base, '[]'::jsonb)) x
), j as (
  select x, (x ->> 'exercise_order')::integer as o from jsonb_array_elements(coalesce(p_joint, '[]'::jsonb)) x
), u as (
  select coalesce(b.o, j.o) as o, b.x as bx, j.x as jx from b full join j on b.o = j.o
), m as (
  select u.o, case when u.jx is null then u.bx else
    coalesce(u.bx, u.jx) || jsonb_build_object(
      'sets_to', least((coalesce(u.bx, u.jx) ->> 'sets_to')::integer, (u.jx ->> 'sets_to')::integer),
      'load_note', case when u.jx ->> 'joint_action' in ('swap', 'drop') then null
        else coalesce(u.bx, u.jx) -> 'load_note' end,
      'load_kg_from', case when u.jx ->> 'joint_action' in ('swap', 'drop') then null
        else coalesce(u.bx, u.jx) -> 'load_kg_from' end,
      'load_kg_to', case when u.jx ->> 'joint_action' in ('swap', 'drop') then null
        else coalesce(u.bx, u.jx) -> 'load_kg_to' end,
      'reps_from', case when u.jx ->> 'joint_action' in ('swap', 'drop') then null
        else coalesce(u.bx, u.jx) -> 'reps_from' end,
      'reps_to', case when u.jx ->> 'joint_action' in ('swap', 'drop') then null
        else coalesce(u.bx, u.jx) -> 'reps_to' end,
      'rpe_to', case when u.jx ->> 'joint_action' = 'drop' then null
        else least(nullif(coalesce(u.bx, u.jx) ->> 'rpe_to', '')::numeric,
          nullif(u.jx ->> 'rpe_to', '')::numeric) end,
      'joint_action', u.jx -> 'joint_action', 'joint', u.jx -> 'joint',
      'joint_state', u.jx -> 'joint_state', 'swap_to_slug', u.jx -> 'swap_to_slug',
      'swap_to_name', u.jx -> 'swap_to_name', 'range_note_code', u.jx -> 'range_note_code')
    end as entry
  from u
)
select coalesce(jsonb_agg(m.entry order by m.o), '[]'::jsonb) from m;
$$;
revoke all on function private.merge_day_changes(jsonb, jsonb) from public, anon, authenticated;

-- The {changes, sets_from, sets_to} object of private.day_adjustment_changes with the joint changes
-- merged in; the set totals are over the whole workout.
create function private.day_changes_merged(p_changes jsonb, p_joint jsonb)
returns jsonb language sql immutable set search_path = '' as $$
with m as (
  select private.merge_day_changes(p_changes -> 'changes', p_joint) as changes
)
select jsonb_build_object('changes', m.changes, 'sets_from', (p_changes ->> 'sets_from')::integer,
  'sets_to', (p_changes ->> 'sets_from')::integer - coalesce((
    select sum((x ->> 'sets_from')::integer - (x ->> 'sets_to')::integer)
    from jsonb_array_elements(m.changes) x), 0)::integer)
from m;
$$;
revoke all on function private.day_changes_merged(jsonb, jsonb) from public, anon, authenticated;

-- 8. The day adjustment learns about joints -----------------------------------------------------------
-- Payload schema 1.1 (keys are only added; every 1.0 key keeps its meaning):
--   * kind 'joint_adjust': the changes of a joint state alone, for a day the readiness rules ask for
--     nothing (also offered among options whenever there are joint changes). The athlete answers it with
--     the same one tap and Undo.
--   * every kind's changes carry the joint changes on the exercises a joint touches: joint_action
--     (swap, limit, drop), joint, joint_state, swap_to_slug, swap_to_name, range_note_code. An exercise
--     no joint touches carries none of these keys.
--   * joint_states [{area, state, since, severity, persistent}] and exercise_joint_options (the gentlest
--     swap per joint for each exercise of today's session, for the in-workout pain chip).
--   * safety_route also takes urgent, clinician_today and clinician, from today's pain reports; the
--     strictest of those and a check-in pain of 7 or more wins. Trigger codes red_flag:<code> name the
--     red flags behind it.
-- A stored answer stands only while it still covers every joint change the rules now ask for.
-- The athlete's answer may be any kind, joint_adjust included, so the two kind constraints widen.

alter table public.day_adjustments
  drop constraint day_adjustments_kind_check,
  drop constraint day_adjustments_rules_kind_check,
  add constraint day_adjustments_kind_check check (
    kind in ('hold_load', 'reduce_sets', 'swap_to_easy_cardio', 'joint_adjust')),
  add constraint day_adjustments_rules_kind_check check (
    rules_kind in ('none', 'hold_load', 'reduce_sets', 'swap_to_easy_cardio', 'joint_adjust'));

-- The words for what the joints change: which joints are in which state, then how many exercises were
-- swapped, kept in a pain-free range or left out. Fixed sentences; no condition is named.
create function private.joint_sentence(p_changes jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare
  joints constant text[] := array['knee', 'back', 'shoulder'];
  labels constant text[] := array['knee', 'lower back', 'shoulder'];
  phrases constant jsonb := '{"held":"is resting until you have been seen","limited":"needs a lighter touch this week","watch":"is on watch"}'::jsonb;
  areas text[] := '{}';
  items text[] := '{}';
  st text;
  i integer;
  n integer;
  swaps integer;
  limits integer;
  drops integer;
  head text;
  tail text;
begin
  for i in 1..3 loop
    select c ->> 'joint_state' into st
    from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb)) c
    where c ->> 'joint' = joints[i] limit 1;
    if st is not null then
      areas := areas || ('your ' || labels[i] || ' ' || (phrases ->> st));
    end if;
  end loop;
  n := coalesce(array_length(areas, 1), 0);
  if n = 0 then return ''; end if;
  head := case when n = 1 then areas[1]
    else array_to_string(areas[1:n - 1], ', ') || ' and ' || areas[n] end;
  head := upper(left(head, 1)) || substr(head, 2) || '.';
  select count(*) filter (where c ->> 'joint_action' = 'swap'),
    count(*) filter (where c ->> 'joint_action' = 'limit'),
    count(*) filter (where c ->> 'joint_action' = 'drop')
  into swaps, limits, drops from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb)) c;
  if swaps > 0 then
    items := items || format('%s %s swapped', swaps, case when swaps = 1 then 'exercise' else 'exercises' end);
  end if;
  if limits > 0 then
    items := items || format('%s %s kept in a pain-free range', limits,
      case when limits = 1 then 'exercise' else 'exercises' end);
  end if;
  if drops > 0 then
    items := items || format('%s %s left out today', drops, case when drops = 1 then 'exercise' else 'exercises' end);
  end if;
  n := coalesce(array_length(items, 1), 0);
  if n = 0 then return head; end if;
  tail := case when n = 1 then items[1]
    else array_to_string(items[1:n - 1], ', ') || ' and ' || items[n] end;
  return head || ' ' || tail || '.';
end $$;
revoke all on function private.joint_sentence(jsonb) from public, anon, authenticated;

-- The line for pain that has lasted two weeks (a leading space, or nothing).
create function private.persistent_sentence(p_states jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare
  names text[] := '{}';
  s jsonb;
  n integer;
  joined text;
begin
  for s in select x from jsonb_array_elements(coalesce(p_states, '[]'::jsonb)) x
    where coalesce((x ->> 'persistent')::boolean, false) loop
    names := names || case s ->> 'area' when 'knee' then 'your knee pain'
      when 'back' then 'your lower back pain' when 'shoulder' then 'your shoulder pain'
      else 'your pain' end;
  end loop;
  n := coalesce(array_length(names, 1), 0);
  if n = 0 then return ''; end if;
  joined := case when n = 1 then names[1]
    else array_to_string(names[1:n - 1], ', ') || ' and ' || names[n] end;
  return ' ' || upper(left(joined, 1)) || substr(joined, 2)
    || case when n = 1 then ' has' else ' have' end
    || ' lasted two weeks. Please see a physio or doctor.';
end $$;
revoke all on function private.persistent_sentence(jsonb) from public, anon, authenticated;


-- Strictness: a joint accommodation sits between 'nothing' and 'hold the loads'.
create or replace function private.readiness_rank(p_kind text, p_safety_route text)
returns integer language sql immutable set search_path = '' as $$
  select case when p_safety_route is not null then 5
    else case p_kind when 'joint_adjust' then 1 when 'hold_load' then 2 when 'reduce_sets' then 3
      when 'swap_to_easy_cardio' then 4 else 0 end end;
$$;

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
  if p_band = 'unknown' then
    return case when 'recovery_low' = any(p_triggers)
      then 'Your recovery reads low. Check in and Tracend will say whether to adjust today.'
      else 'Check in to see if today''s session needs adjusting.' end;
  end if;
  if 'not_available' = any(p_triggers) then
    return 'You said you can''t train today. Nothing in your plan changes.';
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

create or replace function private.day_adjustment_compute(p_user uuid, p_date date)
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
begin
  select v.id, v.block_kind, v.ends_on into version_id, version_block, version_ends
  from public.training_plan_versions v where v.user_id = p_user and v.status = 'active' limit 1;
  workout := case when version_id is null then null
    else private.planned_workout_for_date(p_user, p_date) end;
  workout_id := (workout ->> 'id')::uuid;
  states := private.joint_states(p_user, p_date);

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
        and s.planned_workout_id = workout_id and s.state = 'in_progress') then 'session_started'
    when exists (select 1 from public.workout_sessions s where s.user_id = p_user
        and s.planned_workout_id = workout_id and s.local_date = p_date
        and s.state = 'completed') then 'session_done'
    when version_block = 'next_session' and version_ends = p_date then 'coach_adjusted'
  end;

  if workout_id is not null then
    targets := private.next_session_targets(p_user);
    hold_c := private.day_adjustment_changes(p_user, workout_id, 'hold_load', targets);
    reduce_c := private.day_adjustment_changes(p_user, workout_id, 'reduce_sets', targets);
    swap_c := private.day_adjustment_changes(p_user, workout_id, 'swap_to_easy_cardio', targets);
    can_hold := jsonb_array_length(hold_c -> 'changes') > 0;
    can_reduce := (reduce_c ->> 'sets_to')::integer < (reduce_c ->> 'sets_from')::integer;
    exercise_options := private.joint_options(p_user, workout_id);
    joint_arr := private.joint_changes(p_user, workout_id, states, hold_c -> 'changes');
  end if;
  -- A joint that is held, limited or on watch changes the exercises it touches in every kind (the
  -- stricter value per exercise wins), and alone as the joint_adjust kind.
  hold_c := private.day_changes_merged(hold_c, joint_arr);
  reduce_c := private.day_changes_merged(reduce_c, joint_arr);
  swap_c := private.day_changes_merged(swap_c, joint_arr);
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
  -- Today's pain reports with a red flag, or a severity of 7 or more, route out just as a check-in pain
  -- of 7 or more does, even with no check-in, on a rest day or after the session started. The
  -- stricter route wins.
  select (array['clinician', 'clinician_today', 'urgent'])[max(
      case pr.outcome when 'urgent' then 3 when 'clinician_today' then 2 else 1 end)],
    coalesce(bool_or(pr.severity >= (private.pain_rules() ->> 'clinician_today_from')::integer), false)
  into report_route, report_severe
  from public.pain_reports pr
  where pr.user_id = p_user and pr.local_date = p_date
    and pr.outcome in ('urgent', 'clinician_today', 'clinician');
  if report_route is not null then
    report_codes := array(select distinct 'red_flag:' || f from public.pain_reports pr,
      unnest(pr.red_flags) f
      where pr.user_id = p_user and pr.local_date = p_date
        and pr.outcome in ('urgent', 'clinician_today', 'clinician') order by 1);
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
  if kind = 'none' and unavailable is null and safety is null
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
  if unavailable is null and safety is null and coalesce(check_in.available_to_train, true)
     and workout_id is not null then
    if can_hold then
      options := options || jsonb_build_object('kind', 'hold_load',
        'explanation', private.day_adjustment_explanation(band, 'hold_load', '{}', null,
          hold_c -> 'changes', false, null),
        'sets_total_to', (hold_c ->> 'sets_to')::integer, 'changes', hold_c -> 'changes',
        'cardio', null);
    end if;
    if can_reduce then
      options := options || jsonb_build_object('kind', 'reduce_sets',
        'explanation', private.day_adjustment_explanation(band, 'reduce_sets', '{}', null,
          reduce_c -> 'changes', false, null),
        'sets_total_to', (reduce_c ->> 'sets_to')::integer, 'changes', reduce_c -> 'changes',
        'cardio', null);
    end if;
    if (swap_c ->> 'sets_from')::integer > 0 then
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
        || case when safety is null then private.persistent_sentence(states) else '' end,
      'status', case when kind = 'none' then 'none' else 'proposed' end,
      'available', unavailable is null,
      'unavailable_reason', unavailable,
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

create or replace function private.day_adjustment_stands(p_row public.day_adjustments, p_payload jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select p_row.id is not null
    and p_payload ->> 'safety_route' is null
    and p_row.planned_workout_id::text = p_payload ->> 'planned_workout_id'
    and (p_payload ->> 'unavailable_reason' in ('session_started', 'session_done')
      or (private.readiness_rank(p_payload ->> 'kind', null)
          <= greatest(private.readiness_rank(p_row.rules_kind, null),
            private.readiness_rank(p_row.kind, null))
        and not exists (
          select 1 from jsonb_array_elements(coalesce((
            select o -> 'changes' from jsonb_array_elements(p_payload -> 'options') o
            where o ->> 'kind' = 'joint_adjust' limit 1), '[]'::jsonb)) c
          where private.joint_action_rank(c ->> 'joint_action') > coalesce((
            select max(private.joint_action_rank(s ->> 'joint_action'))
            from jsonb_array_elements(p_row.changes) s
            where s ->> 'planned_exercise_id' = c ->> 'planned_exercise_id'), 0))));
$$;

create or replace function private.day_adjustment_present(
  p_row public.day_adjustments, p_payload jsonb, p_stands boolean, p_inputs jsonb
) returns jsonb language sql immutable set search_path = '' as $$
  select case
    when p_row.id is null or p_payload ->> 'safety_route' is not null then p_payload
    when p_stands then p_payload || jsonb_build_object(
      'status', p_row.status, 'kind', p_row.kind, 'changes', p_row.changes, 'cardio', p_row.cardio,
      'sets_total_to', (p_payload ->> 'sets_total_from')::integer - coalesce((
        select sum((c ->> 'sets_from')::integer - (c ->> 'sets_to')::integer)
        from jsonb_array_elements(p_row.changes) c), 0)::integer,
      'explanation', private.day_adjustment_explanation(p_payload ->> 'band', p_row.kind,
        array(select jsonb_array_elements_text(p_payload -> 'triggers')), null, p_row.changes,
        p_row.origin = 'proposed', null) || private.persistent_sentence(p_payload -> 'joint_states'),
      'origin', p_row.origin, 'answered_at', p_row.answered_at)
    when p_row.planned_workout_id::text = p_payload ->> 'planned_workout_id'
      then p_payload || jsonb_build_object('previous_answer', jsonb_build_object(
        'kind', p_row.kind, 'status', p_row.status, 'answered_at', p_row.answered_at,
        'reason', case when p_row.inputs ->> 'check_in_id' is distinct from p_inputs ->> 'check_in_id'
          then 'check_in' else 'new_data' end))
    else p_payload end;
$$;

-- 9. Starting the workout ---------------------------------------------------------------------------
-- The definition of 20261023150021_close_stale_workouts.sql plus: an exercise the accepted answer leaves
-- out for a joint gets no sets, whatever the kind.

create or replace function public.start_workout(
  p_planned_workout_id uuid,
  p_local_date date,
  p_timezone text,
  p_idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; version_id uuid; exercise record; performance_id uuid; n integer;
  adjustment public.day_adjustments%rowtype; adjusted boolean := false; set_total integer;
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

  -- A session left open from an earlier day is closed first, so it is never found as today's.
  perform private.abandon_stale_workouts(auth.uid());
  select id into result_id from public.workout_sessions
  where user_id=auth.uid() and planned_workout_id=p_planned_workout_id and state='in_progress'
  order by started_at desc limit 1;
  if result_id is not null then return result_id; end if;

  if exists (
    select 1 from public.workout_sessions
    where user_id=auth.uid() and planned_workout_id=p_planned_workout_id
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
    insert into public.exercise_performances(
      user_id,workout_session_id,planned_exercise_id,exercise_order,status,
      performance_kind,performed_name,rest_seconds
    ) values(
      auth.uid(),result_id,exercise.id,exercise.exercise_order,'unknown',
      'prescribed',exercise.display_name_snapshot,exercise.rest_seconds
    ) returning id into performance_id;
    set_total := exercise.set_count;
    if adjusted then
      -- A left-out exercise (a joint drop) gets no sets whatever the kind: its performance stays
      -- 'unknown', never inferred as skipped. reduce_sets builds the adjusted set counts. Everything
      -- else, an easy-cardio answer included, keeps the plan's sets.
      select case when c ->> 'joint_action' = 'drop' then 0
        when adjustment.kind='reduce_sets' then (c ->> 'sets_to')::integer end into set_total
      from jsonb_array_elements(adjustment.changes) c
      where c ->> 'planned_exercise_id' = exercise.id::text;
      set_total := coalesce(set_total, exercise.set_count);
    end if;
    for n in 1..set_total loop
      insert into public.exercise_sets(user_id,exercise_performance_id,set_number)
      values(auth.uid(),performance_id,n);
    end loop;
  end loop;
  return result_id;
end $$;

-- 10. B3 meets the joint adjustment -----------------------------------------------------------------

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
  -- answer left alone is judged as ever, however easy the rest of the session was.
  select s.*, ch.listed is not null as adjusted, ch.sets_planned
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
  ) d
  where d.decision is not null
) x;
$$;

-- 11. The read-only view for Coach context -----------------------------------------------------------
-- What the Coach may be told about today's session: the band, the kind, the status, the safety route
-- and each joint's state, as codes, never the athlete's answers as text. Service role only. Only the
-- athlete's own local today can be read (22023). It reads what is stored and makes no scores.

create function public.get_readiness_context_v1(p_user_id uuid, p_local_date date)
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
  computed := private.day_adjustment_compute(p_user_id, p_local_date);
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
    'rules_version', presented -> 'rules_version');
end $$;
revoke all on function public.get_readiness_context_v1(uuid, date) from public, anon, authenticated;
grant execute on function public.get_readiness_context_v1(uuid, date) to service_role;
