-- Menstrual-cycle support, the data foundation (cycle support v1, PR 1) -----------------------------
--
-- An athlete may opt in to cycle tracking. She says how her cycle works (a status and, optionally,
-- her usual cycle length), logs period days (or allows them from Apple Health), and the app and
-- Coach read one deterministic cycle state from the database. The state explains her recovery and
-- weight; it never changes a plan or a target.
--
--   1. public.cycle_settings          one row per athlete: tracking on or off, status, usual length,
--                                     Apple Health reading
--   2. public.cycle_day_logs          one row per athlete and day: flow, cramps, start flag, source
--   3. private.cycle_data_consent_granted   her newest `cycle_data` consent record is a grant
--   4. private.cycle_state            the cycle engine (docs/ALGORITHMS.md, section 9): periods,
--                                     cycle starts, lengths, typical length, expected range, phase,
--                                     confidence and the two flags, for one athlete on one local date
--   5. private.cycle_answer           the answer every reader gets (schema_version 1.0)
--   6. public.get_my_cycle_v1, set_my_cycle_settings_v1, log_cycle_day_v1, import_cycle_days_v1,
--      delete_my_cycle_data_v1        the athlete's own reads and writes (authenticated)
--   7. public.coach_cycle_state_v1    Coach's read (service role only)
--
-- Both tables are read-only for the athlete; every write goes through the functions above. Audit
-- events name the fields that changed and never carry a status or a flow value, because audit rows
-- outlive "Delete my cycle data". Everything is additive: old app builds never call these
-- functions. The tables are exported by privacy-export and removed with the account.

-- 1-2. Tables ----------------------------------------------------------------------------------------

create table public.cycle_settings (
  user_id uuid primary key references public.user_accounts (id) on delete cascade,
  tracking_enabled boolean not null default false,
  status text check (status in ('regular', 'irregular', 'hormonal_contraception', 'no_periods')),
  typical_cycle_days smallint check (typical_cycle_days between 15 and 60),
  apple_health_enabled boolean not null default false,
  tracking_enabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cycle_settings_tracking_has_status check (not tracking_enabled or status is not null),
  constraint cycle_settings_tracking_has_time
    check (not tracking_enabled or tracking_enabled_at is not null),
  constraint cycle_settings_apple_health_needs_tracking
    check (not apple_health_enabled or tracking_enabled)
);

comment on table public.cycle_settings is
  'The athlete''s cycle-tracking choice: tracking on or off, her status, her usual cycle length (optional) and whether period days are read from Apple Health. tracking_enabled_at is the last time tracking was turned on; the long-gap flag never counts days before it. Written only by set_my_cycle_settings_v1 and delete_my_cycle_data_v1.';

create table public.cycle_day_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  local_date date not null,
  flow text check (flow in ('spotting', 'light', 'medium', 'heavy', 'unspecified')),
  cramps text check (cramps in ('none', 'mild', 'strong')),
  is_start boolean not null default false,
  source text not null check (source in ('manual', 'apple_health')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cycle_day_logs_one_per_day unique (user_id, local_date),
  constraint cycle_day_logs_start_is_bleeding
    check (not is_start or (flow is not null and flow <> 'spotting')),
  constraint cycle_day_logs_apple_health_shape check (source = 'manual'
    or (flow in ('light', 'medium', 'heavy', 'unspecified') and cramps is null))
);

comment on table public.cycle_day_logs is
  'One day of the athlete''s cycle log. flow null means she said there was no bleeding that day; such a manual row also keeps Apple Health from writing that date. is_start marks the first day of a period (HealthKit isStartOfCycle, or the date she gave for her last period). Written only by log_cycle_day_v1 (source manual) and import_cycle_days_v1 (source apple_health, never over a manual row).';

alter table public.cycle_settings enable row level security;
alter table public.cycle_settings force row level security;
alter table public.cycle_day_logs enable row level security;
alter table public.cycle_day_logs force row level security;
create policy cycle_settings_own_read on public.cycle_settings
  for select to authenticated using (user_id = (select auth.uid()));
create policy cycle_day_logs_own_read on public.cycle_day_logs
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.cycle_settings, public.cycle_day_logs from anon, authenticated;
grant select on public.cycle_settings, public.cycle_day_logs to authenticated;

-- 3. Consent -----------------------------------------------------------------------------------------

-- Any notice version counts, as for health data: a new page version is asked again by the app.
create function private.cycle_data_consent_granted(target_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select c.action = 'granted' from public.consent_records c
    where c.user_id = target_user_id and c.consent_type = 'cycle_data'
    order by c.created_at desc, c.id desc limit 1), false);
$$;
revoke all on function private.cycle_data_consent_granted(uuid)
  from public, anon, authenticated, service_role;

-- 4. The cycle engine --------------------------------------------------------------------------------

-- The median of a list of day counts (the mean of the two middle values for an even count).
create function private.cycle_median(p_values integer[])
returns numeric language sql immutable set search_path = '' as $$
  select (percentile_cont(0.5) within group (order by v))::numeric from unnest(p_values) v;
$$;
revoke all on function private.cycle_median(integer[]) from public, anon, authenticated, service_role;

-- The cycle state of one athlete on one local date, from her settings and the days logged up to
-- that date: {"state": {...}, "cycles": [...]}. The rules and their constants are documented in
-- docs/ALGORITHMS.md, section 9, and pinned by supabase/tests/database/cycle_engine_test.sql.
create function private.cycle_state(p_user_id uuid, p_local_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  settings public.cycle_settings%rowtype;
  run_first date[];
  run_last date[];
  run_days integer[];
  run_heavy boolean[];
  run_flag boolean[];
  run_count integer;
  starts date[] := '{}';
  start_count integer;
  previous_start date;
  last_start date;
  lengths integer[] := '{}';
  used_lengths integer[] := '{}';
  used_flags boolean[] := '{}';
  others integer[];
  used_count integer;
  spread integer := 0;
  typical integer;
  effective_regular boolean;
  margin integer;
  v_cycle_day integer;
  v_period_day integer;
  v_phase text;
  v_confidence text;
  v_expected_from date;
  v_expected_to date;
  v_late_days integer;
  v_no_period_long boolean := false;
  v_weight_window boolean := false;
  anchor date;
  v_cycles jsonb := '[]'::jsonb;
begin
  if p_user_id is null or p_local_date is null then
    raise exception 'an athlete and a date are required' using errcode = '22023';
  end if;
  select * into settings from public.cycle_settings s where s.user_id = p_user_id;
  if not found or not settings.tracking_enabled then
    return jsonb_build_object(
      'state', jsonb_build_object('cycle_day', null, 'period_day', null, 'phase', null,
        'confidence', null, 'expected_from', null, 'expected_to', null, 'late_days', null,
        'no_period_long', false, 'weight_water_window', false),
      'cycles', '[]'::jsonb);
  end if;

  -- Periods: runs of bleeding days (any flow but spotting) whose gaps are at most 2 days.
  select coalesce(array_agg(r.first_day order by r.first_day), '{}'),
    coalesce(array_agg(r.last_day order by r.first_day), '{}'),
    coalesce(array_agg(r.day_count order by r.first_day), '{}'),
    coalesce(array_agg(r.has_heavy order by r.first_day), '{}'),
    coalesce(array_agg(r.has_flag order by r.first_day), '{}')
  into run_first, run_last, run_days, run_heavy, run_flag
  from (
    select min(g.local_date) as first_day, max(g.local_date) as last_day,
      count(*)::integer as day_count, bool_or(g.flow in ('medium', 'heavy')) as has_heavy,
      bool_or(g.is_start) as has_flag
    from (
      select m.local_date, m.flow, m.is_start, sum(m.new_run) over (order by m.local_date) as run_no
      from (
        select l.local_date, l.flow, l.is_start,
          case when l.local_date - lag(l.local_date) over (order by l.local_date) <= 3
            then 0 else 1 end as new_run
        from public.cycle_day_logs l
        where l.user_id = p_user_id and l.local_date <= p_local_date
          and l.flow is not null and l.flow <> 'spotting'
      ) m
    ) g
    group by g.run_no
  ) r;
  run_count := coalesce(array_length(run_first, 1), 0);

  -- The latest run is ongoing while its last bleeding day is at most 2 days ago, unless she said
  -- there was no bleeding today. On hormonal contraception (or with no periods) any bleed counts.
  if run_count > 0 and run_last[run_count] >= p_local_date - 2
    and not exists (select 1 from public.cycle_day_logs l
      where l.user_id = p_user_id and l.local_date = p_local_date and l.flow is null) then
    v_period_day := p_local_date - run_first[run_count] + 1;
  end if;

  if settings.status in ('hormonal_contraception', 'no_periods') then
    v_weight_window := coalesce(v_period_day between 1 and 3, false);
    return jsonb_build_object(
      'state', jsonb_build_object('cycle_day', null, 'period_day', v_period_day, 'phase', null,
        'confidence', null, 'expected_from', null, 'expected_to', null, 'late_days', null,
        'no_period_long', false, 'weight_water_window', v_weight_window),
      'cycles', '[]'::jsonb);
  end if;

  -- Cycle starts: a period at least 15 days after the previous start with 2 or more bleeding days
  -- or one medium or heavy day; or a period with a day flagged as a start, at least 10 days after
  -- the previous start (closer than that it is a duplicate). Anything else is bleeding inside the
  -- cycle.
  for i in 1 .. run_count loop
    if (previous_start is null and (run_flag[i] or run_days[i] >= 2 or run_heavy[i]))
      or (previous_start is not null and (
        (run_first[i] - previous_start >= 15 and (run_days[i] >= 2 or run_heavy[i]))
        or (run_flag[i] and run_first[i] - previous_start >= 10))) then
      starts := starts || run_first[i];
      previous_start := run_first[i];
    end if;
  end loop;
  start_count := coalesce(array_length(starts, 1), 0);
  last_start := starts[start_count];

  -- A bleed that is not a start yet (one light day, say) counts as a period day only when it could
  -- become a start: at least 15 days after the last one.
  if v_period_day is not null and last_start is not null
    and run_first[run_count] <> last_start and run_first[run_count] - last_start < 15 then
    v_period_day := null;
  end if;

  -- Completed cycle lengths. A length is used when it is 15 to 60 days and not within 5 days of
  -- twice the median of the other such lengths (a month whose period was not logged); that test
  -- needs at least two other lengths.
  for i in 1 .. start_count - 1 loop
    lengths := lengths || (starts[i + 1] - starts[i]);
  end loop;
  for i in 1 .. start_count - 1 loop
    if lengths[i] between 15 and 60 then
      select coalesce(array_agg(x.len), '{}') into others
      from unnest(lengths) with ordinality x(len, n)
      where x.n <> i and x.len between 15 and 60;
      used_flags := used_flags || (not (coalesce(array_length(others, 1), 0) >= 2
        and abs(lengths[i] - 2 * private.cycle_median(others)) <= 5));
    else
      used_flags := used_flags || false;
    end if;
  end loop;

  -- The last (up to) 6 used lengths give the typical length and the spread.
  select coalesce(array_agg(x.len order by x.n), '{}') into used_lengths
  from (
    select u.len, u.n from unnest(lengths, used_flags) with ordinality u(len, ok, n)
    where u.ok order by u.n desc limit 6
  ) x;
  used_count := coalesce(array_length(used_lengths, 1), 0);
  if used_count >= 2 then
    typical := round(private.cycle_median(used_lengths))::integer;
    spread := (select max(v) - min(v) from unnest(used_lengths) v);
  else
    typical := settings.typical_cycle_days;
  end if;

  -- Stated regular is read as irregular when 3 or more used lengths spread over more than 9 days
  -- (FIGO). The stored status never changes.
  effective_regular := settings.status = 'regular' and not (used_count >= 3 and spread > 9);

  if last_start is not null then
    v_cycle_day := p_local_date - last_start + 1;
    if typical is not null then
      if effective_regular then
        margin := greatest(2, ceil(spread / 2.0)::integer);
      elsif used_count >= 3 then
        margin := greatest(4, ceil(spread / 2.0)::integer);
      end if;
      if margin is not null then
        v_expected_from := last_start + typical - margin;
        v_expected_to := last_start + typical + margin;
      end if;
    end if;
    if effective_regular and typical is not null then
      if v_period_day is not null then
        v_phase := 'period';
      elsif p_local_date <= v_expected_to then
        v_phase := case when v_cycle_day >= typical - 13 then 'second_half' else 'first_half' end;
      else
        v_late_days := p_local_date - v_expected_to;
      end if;
    end if;
  end if;

  v_confidence := case
    when start_count >= 2 and not used_flags[start_count - 1] then 'low'
    when used_count >= 3 and spread <= 5 then 'high'
    when used_count >= 2 then 'medium'
    else 'low' end;

  -- No period for 90 days (regular) or 180 days (irregular), counted from the later of the last
  -- start, a later bleed that could be a start, and the day tracking was last turned on; only after
  -- at least two logged periods.
  if start_count >= 2 then
    anchor := greatest(last_start,
      case when run_first[run_count] - last_start >= 15 then run_first[run_count] end,
      private.local_day_of(p_user_id, settings.tracking_enabled_at));
    v_no_period_long := p_local_date - anchor
      >= case settings.status when 'regular' then 90 else 180 end;
  end if;

  v_weight_window := coalesce(p_local_date between v_expected_from - 5 and v_expected_from - 1, false)
    or coalesce(v_period_day between 1 and 3, false);

  select coalesce(jsonb_agg(jsonb_build_object('start_date', c.start_date,
      'length_days', c.length_days, 'used', c.used) order by c.n), '[]'::jsonb)
  into v_cycles
  from (
    select x.start_date, x.n, lengths[x.n] as length_days, coalesce(used_flags[x.n], false) as used
    from unnest(starts) with ordinality x(start_date, n)
    order by x.n desc limit 7
  ) c;

  return jsonb_build_object(
    'state', jsonb_build_object('cycle_day', v_cycle_day, 'period_day', v_period_day,
      'phase', v_phase, 'confidence', v_confidence, 'expected_from', v_expected_from,
      'expected_to', v_expected_to, 'late_days', v_late_days, 'no_period_long', v_no_period_long,
      'weight_water_window', v_weight_window),
    'cycles', v_cycles);
end $$;
revoke all on function private.cycle_state(uuid, date) from public, anon, authenticated, service_role;

-- 5. The cycle answer --------------------------------------------------------------------------------

-- Every reader gets this shape (test/contract/fixtures/my_cycle_v1_0_*.json): every key always
-- present, recent_days ascending and only the days in [p_recent_from, p_recent_to].
create function private.cycle_answer(
  p_user_id uuid, p_local_date date, p_recent_from date, p_recent_to date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  settings public.cycle_settings%rowtype;
  engine jsonb := private.cycle_state(p_user_id, p_local_date);
begin
  select * into settings from public.cycle_settings s where s.user_id = p_user_id;
  return jsonb_build_object(
    'schema_version', '1.0',
    'tracking_enabled', coalesce(settings.tracking_enabled, false),
    'status', settings.status,
    'typical_cycle_days', settings.typical_cycle_days,
    'apple_health_enabled', coalesce(settings.apple_health_enabled, false),
    'state', engine -> 'state',
    'recent_days', case when coalesce(settings.tracking_enabled, false) then coalesce((
      select jsonb_agg(jsonb_build_object('local_date', l.local_date, 'flow', l.flow,
          'cramps', l.cramps, 'is_start', l.is_start, 'source', l.source) order by l.local_date)
      from public.cycle_day_logs l
      where l.user_id = p_user_id and l.local_date between p_recent_from and p_recent_to),
      '[]'::jsonb) else '[]'::jsonb end,
    'cycles', engine -> 'cycles');
end $$;
revoke all on function private.cycle_answer(uuid, date, date, date)
  from public, anon, authenticated, service_role;

-- 6. The athlete's reads and writes ----------------------------------------------------------------
--
-- Each answers with the cycle answer for her local date (recent_days: the last 60 days, and
-- tomorrow, which she may log when her phone's date is ahead of her account's time zone). Errors:
-- 42501 signed out or an inactive account; 22023 a bad input; P0403 a missing consent or a
-- feature that is off (message cycle_consent_required, health_consent_required,
-- cycle_tracking_off or apple_health_off).

create function public.get_my_cycle_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  today date;
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  today := private.local_date_for(uid);
  return private.cycle_answer(uid, today, today - 59, today + 1);
end $$;
revoke all on function public.get_my_cycle_v1() from public, anon;
grant execute on function public.get_my_cycle_v1() to authenticated;

-- Turning tracking on needs a granted cycle_data consent and a status; reading Apple Health also
-- needs a granted health_data consent. Turning tracking off keeps the logged days (deleting them is
-- delete_my_cycle_data_v1) and turns Apple Health reading off. An actual change leaves one audit
-- event naming the changed fields.
create function public.set_my_cycle_settings_v1(
  p_tracking_enabled boolean, p_status text, p_typical_cycle_days integer,
  p_apple_health_enabled boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  previous public.cycle_settings%rowtype;
  apple boolean;
  changed text[] := '{}';
  today date;
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_tracking_enabled is null or p_apple_health_enabled is null then
    raise exception 'tracking and Apple Health must be on or off' using errcode = '22023';
  end if;
  if p_status is not null
    and p_status <> all (array['regular', 'irregular', 'hormonal_contraception', 'no_periods']) then
    raise exception 'unknown cycle status' using errcode = '22023';
  end if;
  if p_tracking_enabled and p_status is null then
    raise exception 'tracking needs a cycle status' using errcode = '22023';
  end if;
  if p_typical_cycle_days is not null and p_typical_cycle_days not between 15 and 60 then
    raise exception 'a cycle length is 15 to 60 days' using errcode = '22023';
  end if;
  apple := p_tracking_enabled and p_apple_health_enabled;
  if p_tracking_enabled and not private.cycle_data_consent_granted(uid) then
    raise exception 'cycle_consent_required' using errcode = 'P0403';
  end if;
  if apple and not private.health_data_consent_granted(uid) then
    raise exception 'health_consent_required' using errcode = 'P0403';
  end if;
  perform 1 from public.user_accounts a
    where a.id = uid and a.account_status = 'active' for update;
  if not found then
    raise exception 'active account required' using errcode = '42501';
  end if;

  select * into previous from public.cycle_settings s where s.user_id = uid;
  if coalesce(previous.tracking_enabled, false) <> p_tracking_enabled then
    changed := changed || 'tracking_enabled'::text;
  end if;
  if previous.status is distinct from p_status then
    changed := changed || 'status'::text;
  end if;
  if previous.typical_cycle_days is distinct from p_typical_cycle_days then
    changed := changed || 'typical_cycle_days'::text;
  end if;
  if coalesce(previous.apple_health_enabled, false) <> apple then
    changed := changed || 'apple_health_enabled'::text;
  end if;

  if cardinality(changed) > 0 then
    insert into public.cycle_settings as s (
      user_id, tracking_enabled, status, typical_cycle_days, apple_health_enabled,
      tracking_enabled_at
    ) values (
      uid, p_tracking_enabled, p_status, p_typical_cycle_days, apple,
      case when p_tracking_enabled then now() end
    )
    on conflict (user_id) do update set
      tracking_enabled = excluded.tracking_enabled,
      status = excluded.status,
      typical_cycle_days = excluded.typical_cycle_days,
      apple_health_enabled = excluded.apple_health_enabled,
      tracking_enabled_at = case when excluded.tracking_enabled and not s.tracking_enabled
        then now() else s.tracking_enabled_at end,
      updated_at = now();
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (uid, 'cycle.settings.changed', 'cycle_settings', uid, 'succeeded',
      jsonb_build_object('schema_version', '1.0', 'changed', to_jsonb(changed)));
  end if;

  today := private.local_date_for(uid);
  return private.cycle_answer(uid, today, today - 59, today + 1);
end $$;
revoke all on function public.set_my_cycle_settings_v1(boolean, text, integer, boolean)
  from public, anon;
grant execute on function public.set_my_cycle_settings_v1(boolean, text, integer, boolean)
  to authenticated;

-- One day, from the last 400 days up to tomorrow. A null flow says there was no bleeding that day.
-- The day is stored as manual and replaces an Apple Health row for that date. No audit event: it is
-- her own log, written often.
create function public.log_cycle_day_v1(
  p_local_date date, p_flow text, p_cramps text, p_is_start boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  today date;
  start_flag constant boolean := coalesce(p_is_start, false);
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  today := private.local_date_for(uid);
  if p_local_date is null or p_local_date not between today - 400 and today + 1 then
    raise exception 'a day from the last 400 days up to tomorrow' using errcode = '22023';
  end if;
  if p_flow is not null
    and p_flow <> all (array['spotting', 'light', 'medium', 'heavy', 'unspecified']) then
    raise exception 'unknown flow' using errcode = '22023';
  end if;
  if p_cramps is not null and p_cramps <> all (array['none', 'mild', 'strong']) then
    raise exception 'unknown cramps' using errcode = '22023';
  end if;
  if start_flag and (p_flow is null or p_flow = 'spotting') then
    raise exception 'a period starts with bleeding' using errcode = '22023';
  end if;
  if not exists (select 1 from public.cycle_settings s
    where s.user_id = uid and s.tracking_enabled) then
    raise exception 'cycle_tracking_off' using errcode = 'P0403';
  end if;
  if not private.cycle_data_consent_granted(uid) then
    raise exception 'cycle_consent_required' using errcode = 'P0403';
  end if;
  perform 1 from public.user_accounts a where a.id = uid and a.account_status = 'active';
  if not found then
    raise exception 'active account required' using errcode = '42501';
  end if;

  insert into public.cycle_day_logs (user_id, local_date, flow, cramps, is_start, source)
  values (uid, p_local_date, p_flow, p_cramps, start_flag, 'manual')
  on conflict on constraint cycle_day_logs_one_per_day do update set
    flow = excluded.flow,
    cramps = excluded.cramps,
    is_start = excluded.is_start,
    source = 'manual',
    updated_at = now();

  return private.cycle_answer(uid, today, today - 59, today + 1);
end $$;
revoke all on function public.log_cycle_day_v1(date, text, text, boolean) from public, anon;
grant execute on function public.log_cycle_day_v1(date, text, text, boolean) to authenticated;

-- The period days Apple Health holds for a window of at most 400 days ending no later than
-- tomorrow. The window is the truth for Apple Health rows: days in p_days are written (cramps
-- null), Apple Health rows in the window that are not in p_days are removed. A manual row is never
-- touched, so a day she corrected stays corrected. Answers {schema_version, imported, removed}:
-- imported counts the rows added or changed.
create function public.import_cycle_days_v1(p_from date, p_to date, p_days jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  today date;
  item jsonb;
  item_date date;
  settings public.cycle_settings%rowtype;
  imported integer;
  removed integer;
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  today := private.local_date_for(uid);
  if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 400 or p_to > today + 1 then
    raise exception 'a window of at most 400 days ending no later than tomorrow'
      using errcode = '22023';
  end if;
  if jsonb_typeof(p_days) is distinct from 'array' or jsonb_array_length(p_days) > 400 then
    raise exception 'days must be a list of at most 400' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(p_days) loop
    if jsonb_typeof(item) <> 'object' then
      raise exception 'each day is {local_date, flow, is_start}' using errcode = '22023';
    end if;
    if exists (select 1 from jsonb_object_keys(item) k
      where k <> all (array['local_date', 'flow', 'is_start'])) then
      raise exception 'each day is {local_date, flow, is_start}' using errcode = '22023';
    end if;
    if jsonb_typeof(item -> 'local_date') is distinct from 'string'
      or (item ->> 'local_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'a day needs a YYYY-MM-DD date' using errcode = '22023';
    end if;
    begin
      item_date := (item ->> 'local_date')::date;
    exception when others then
      raise exception 'a day needs a real date' using errcode = '22023';
    end;
    if item_date not between p_from and p_to then
      raise exception 'every day must be inside the window' using errcode = '22023';
    end if;
    if jsonb_typeof(item -> 'flow') is distinct from 'string'
      or (item ->> 'flow') <> all (array['light', 'medium', 'heavy', 'unspecified']) then
      raise exception 'unknown flow' using errcode = '22023';
    end if;
    if jsonb_typeof(item -> 'is_start') is distinct from 'boolean' then
      raise exception 'is_start must be true or false' using errcode = '22023';
    end if;
  end loop;
  if (select count(distinct d.value ->> 'local_date') from jsonb_array_elements(p_days) d)
    <> jsonb_array_length(p_days) then
    raise exception 'a day appears twice' using errcode = '22023';
  end if;

  select * into settings from public.cycle_settings s where s.user_id = uid;
  if not coalesce(settings.tracking_enabled, false) then
    raise exception 'cycle_tracking_off' using errcode = 'P0403';
  end if;
  if not settings.apple_health_enabled then
    raise exception 'apple_health_off' using errcode = 'P0403';
  end if;
  if not private.cycle_data_consent_granted(uid) then
    raise exception 'cycle_consent_required' using errcode = 'P0403';
  end if;
  if not private.health_data_consent_granted(uid) then
    raise exception 'health_consent_required' using errcode = 'P0403';
  end if;
  perform 1 from public.user_accounts a where a.id = uid and a.account_status = 'active';
  if not found then
    raise exception 'active account required' using errcode = '42501';
  end if;

  -- One import per athlete at a time, so two syncs cannot interleave their window deletes.
  perform pg_advisory_xact_lock(hashtextextended('tracend.cycle_import:' || uid::text, 0));

  delete from public.cycle_day_logs l
  where l.user_id = uid and l.source = 'apple_health' and l.local_date between p_from and p_to
    and not exists (select 1 from jsonb_array_elements(p_days) d
      where (d.value ->> 'local_date')::date = l.local_date);
  get diagnostics removed = row_count;

  insert into public.cycle_day_logs as l (user_id, local_date, flow, cramps, is_start, source)
  select uid, (d.value ->> 'local_date')::date, d.value ->> 'flow', null,
    (d.value ->> 'is_start')::boolean, 'apple_health'
  from jsonb_array_elements(p_days) d
  on conflict on constraint cycle_day_logs_one_per_day do update set
    flow = excluded.flow,
    is_start = excluded.is_start,
    updated_at = now()
  where l.source = 'apple_health'
    and (l.flow, l.is_start) is distinct from (excluded.flow, excluded.is_start);
  get diagnostics imported = row_count;

  return jsonb_build_object('schema_version', '1.0', 'imported', imported, 'removed', removed);
end $$;
revoke all on function public.import_cycle_days_v1(date, date, jsonb) from public, anon;
grant execute on function public.import_cycle_days_v1(date, date, jsonb) to authenticated;

-- "Delete my cycle data": every logged day and the settings row go, a withdrawal of the cycle_data
-- consent is recorded (so turning tracking on again asks again), and one audit event without values.
create function public.delete_my_cycle_data_v1()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  today date;
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  delete from public.cycle_day_logs l where l.user_id = uid;
  delete from public.cycle_settings s where s.user_id = uid;
  insert into public.consent_records(user_id, consent_type, notice_version, action, source)
  values (uid, 'cycle_data', '2026-11-27', 'withdrawn', 'ios_app');
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (uid, 'cycle.data.deleted', 'cycle_settings', uid, 'succeeded',
    jsonb_build_object('schema_version', '1.0'));
  today := private.local_date_for(uid);
  return private.cycle_answer(uid, today, today - 59, today + 1);
end $$;
revoke all on function public.delete_my_cycle_data_v1() from public, anon;
grant execute on function public.delete_my_cycle_data_v1() to authenticated;

-- 7. Coach's read ------------------------------------------------------------------------------------

-- The cycle answer for one athlete on the coaching date, with the last 14 days ending that date.
-- Coach renders it only under an AI notice that names cycle data; that gate lives in Coach.
create function public.coach_cycle_state_v1(p_user_id uuid, p_local_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if p_user_id is null or p_local_date is null then
    raise exception 'an athlete and a date are required' using errcode = '22023';
  end if;
  return private.cycle_answer(p_user_id, p_local_date, p_local_date - 13, p_local_date);
end $$;
revoke all on function public.coach_cycle_state_v1(uuid, date) from public, anon, authenticated;
grant execute on function public.coach_cycle_state_v1(uuid, date) to service_role;
