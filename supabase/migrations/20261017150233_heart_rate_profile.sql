-- Heart-rate profile (coaching platform chunk C3, migration code 33).
--
-- 1. public.sleeping_heart_rate_nights holds one derived row per athlete and night: the median and
--    lowest heart rate while asleep, how many readings, how long asleep and how much of the night
--    had readings. The phone computes it from Apple Health; raw samples never leave it. It is in
--    SHADOW MODE (program decision D10): stored and exported, read by no score. The recovery score,
--    the readiness line and the Coach do not use it until a later reviewed change.
-- 2. persist_sleeping_heart_rate_v1 saves up to 14 nights of the caller, replacing a night read
--    again. A night with an invalid value is skipped and counted, so one bad night does not lose
--    the others; a request that is not a list of 1 to 14 nights raises 22023.
-- 3. The heart-rate profile (resting heart rate, estimated maximum, zones, recovery after sets) is
--    computed on demand from stored values by deterministic code (Dart in the app, TypeScript for
--    the Coach). get_my_heart_rate_inputs_v1 returns what that code needs for the caller, and
--    get_heart_rate_inputs_v1 returns the same for the Coach (service role only). Neither returns
--    sleeping heart rate.
-- Heart rate never changes a load or a prescription (D9). Everything is additive.

-- 1. Table ------------------------------------------------------------------------------------

create table public.sleeping_heart_rate_nights (
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  local_date date not null,
  median_bpm smallint not null,
  lowest_bpm smallint not null,
  sample_count integer not null,
  asleep_minutes integer not null,
  coverage numeric(4, 3) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, local_date),
  constraint sleeping_heart_rate_bpm_check check (
    median_bpm between 30 and 200 and lowest_bpm between 30 and 200 and lowest_bpm <= median_bpm),
  constraint sleeping_heart_rate_samples_check check (sample_count between 1 and 20000),
  constraint sleeping_heart_rate_asleep_check check (asleep_minutes between 1 and 1440),
  constraint sleeping_heart_rate_coverage_check check (coverage between 0 and 1)
);

comment on table public.sleeping_heart_rate_nights is
  'SHADOW MODE (D10): sleeping heart rate per night, computed on the phone. No score, readiness line or Coach context reads it until a later reviewed change.';
comment on column public.sleeping_heart_rate_nights.local_date is
  'The local date the night ends on, the same day Apple Health sleep is attributed to.';
comment on column public.sleeping_heart_rate_nights.lowest_bpm is
  'The lowest mean heart rate of any 10-minute slot of the night that holds at least 2 readings, never a single reading.';
comment on column public.sleeping_heart_rate_nights.coverage is
  'Share (0 to 1) of the 10-minute slots of the night that have heart-rate readings.';

alter table public.sleeping_heart_rate_nights enable row level security;
alter table public.sleeping_heart_rate_nights force row level security;
create policy sleeping_heart_rate_nights_own_read on public.sleeping_heart_rate_nights
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.sleeping_heart_rate_nights from anon, authenticated;
grant select on public.sleeping_heart_rate_nights to authenticated;

-- 2. Save -------------------------------------------------------------------------------------

create function public.persist_sleeping_heart_rate_v1(nights jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  item jsonb; night_date date; median_value smallint; lowest_value smallint; samples_value integer;
  asleep_value integer; coverage_value numeric; saved integer := 0; skipped integer := 0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if nights is null or jsonb_typeof(nights) <> 'array' or jsonb_array_length(nights) not between 1 and 14 then
    raise exception 'nights must be a list of 1 to 14 nights' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(nights) loop
    begin
      if jsonb_typeof(item) <> 'object' then
        raise exception 'each night must be an object' using errcode = '22023';
      end if;
      if jsonb_typeof(item->'local_date') is distinct from 'string'
         or item->>'local_date' !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'local_date must be a date' using errcode = '22023';
      end if;
      begin
        night_date := (item->>'local_date')::date;
      exception when others then
        raise exception 'local_date must be a date' using errcode = '22023';
      end;
      if night_date > current_date + 1 or night_date < current_date - 400 then
        raise exception 'local_date is out of range' using errcode = '22023';
      end if;
      median_value := private.set_heart_rate_value(item->'median_bpm', 30, 200, 'median_bpm', true, true);
      lowest_value := private.set_heart_rate_value(item->'lowest_bpm', 30, 200, 'lowest_bpm', true, true);
      samples_value := private.set_heart_rate_value(item->'sample_count', 1, 20000, 'sample_count', true, true);
      asleep_value := private.set_heart_rate_value(item->'asleep_minutes', 1, 1440, 'asleep_minutes', true, true);
      coverage_value := private.set_heart_rate_value(item->'coverage', 0, 1, 'coverage', true, false);
      if lowest_value > median_value then
        raise exception 'the lowest cannot be above the median' using errcode = '22023';
      end if;
      insert into public.sleeping_heart_rate_nights as n(
        user_id, local_date, median_bpm, lowest_bpm, sample_count, asleep_minutes, coverage)
      values (auth.uid(), night_date, median_value, lowest_value, samples_value, asleep_value,
        coverage_value)
      on conflict (user_id, local_date) do update set
        median_bpm = excluded.median_bpm, lowest_bpm = excluded.lowest_bpm,
        sample_count = excluded.sample_count, asleep_minutes = excluded.asleep_minutes,
        coverage = excluded.coverage, updated_at = now();
      saved := saved + 1;
    exception when sqlstate '22023' then
      skipped := skipped + 1;
    end;
  end loop;
  return jsonb_build_object('schema_version', '1.0', 'saved', saved, 'skipped', skipped);
end $$;
revoke all on function public.persist_sleeping_heart_rate_v1(jsonb) from public, anon, authenticated;
grant execute on function public.persist_sleeping_heart_rate_v1(jsonb) to authenticated;

-- 3. Profile inputs ---------------------------------------------------------------------------

-- What the profile maths needs for one athlete on one date: the birth year, the resting heart
-- rate of the last 14 days (Apple Health values between 30 and 120), the recovery sets and the
-- ten highest trusted set peaks of the last 365 days for the observed maximum.
-- Recovery sets are the per-set summaries the recovery trend can use (a 60 second drop, an end
-- heart rate and 60%+ coverage), newest first, from the last 28 days and the 28 days before. Each
-- window is capped at 200 on its own, after the filter, so a high-volume athlete's recent sets
-- cannot crowd out the prior window and unusable rows do not use up the cap. A peak is trusted
-- (Watch workout, 8+ readings, 60%+ coverage, 120 bpm up to the age ceiling, 210 with no age)
-- BEFORE the limit, so untrusted higher peaks cannot crowd out a valid lower one. The ceiling here
-- is the Tanaka formula plus 20 plus 1 (a superset of the exact check, which the profile code
-- applies on the rounded formula); the code stays the single judge of the exact value. Discarded
-- workouts are left out. No sleeping heart rate (shadow mode).
create function private.heart_rate_inputs(target_user uuid, as_of date)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'as_of', as_of,
    'birth_year', (select p.birth_year from public.user_profiles p where p.user_id = target_user),
    'resting', coalesce((
      select jsonb_agg(jsonb_build_object('local_date', d.local_date, 'bpm', d.resting_heart_rate_bpm)
        order by d.local_date)
      from public.daily_health_summaries d
      where d.user_id = target_user and d.source_scope = 'healthkit'
        and d.local_date between as_of - 13 and as_of
        and d.resting_heart_rate_bpm between 30 and 120), '[]'::jsonb),
    'sets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'local_date', r.local_date, 'start_bpm', r.start_bpm, 'peak_bpm', r.peak_bpm,
        'end_bpm', r.end_bpm, 'drop_30s_bpm', r.drop_30s_bpm, 'drop_60s_bpm', r.drop_60s_bpm,
        'coverage', r.coverage, 'sample_count', r.sample_count, 'source', r.source)
        order by r.local_date desc, r.exercise_set_id)
      from (
        select u.* from (
          select w.local_date, h.*,
            row_number() over (
              partition by (w.local_date >= as_of - 27)
              order by w.local_date desc, h.exercise_set_id) as window_rank
          from public.exercise_set_heart_rate h
          join public.exercise_sets s on s.id = h.exercise_set_id and s.user_id = h.user_id
          join public.exercise_performances p on p.id = s.exercise_performance_id and p.user_id = s.user_id
          join public.workout_sessions w on w.id = p.workout_session_id and w.user_id = p.user_id
          where h.user_id = target_user and w.state <> 'abandoned'
            and w.local_date between as_of - 55 and as_of
            and h.drop_60s_bpm is not null and h.end_bpm is not null and h.coverage >= 0.6
        ) u
        where u.window_rank <= 200) r), '[]'::jsonb),
    'peak_candidates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'local_date', r.local_date, 'start_bpm', r.start_bpm, 'peak_bpm', r.peak_bpm,
        'end_bpm', r.end_bpm, 'drop_30s_bpm', r.drop_30s_bpm, 'drop_60s_bpm', r.drop_60s_bpm,
        'coverage', r.coverage, 'sample_count', r.sample_count, 'source', r.source)
        order by r.peak_bpm desc, r.local_date desc, r.exercise_set_id)
      from (
        select w.local_date, h.*
        from public.exercise_set_heart_rate h
        join public.exercise_sets s on s.id = h.exercise_set_id and s.user_id = h.user_id
        join public.exercise_performances p on p.id = s.exercise_performance_id and p.user_id = s.user_id
        join public.workout_sessions w on w.id = p.workout_session_id and w.user_id = p.user_id
        where h.user_id = target_user and w.state <> 'abandoned' and h.peak_bpm is not null
          and w.local_date between as_of - 364 and as_of
          and h.source = 'watch_workout' and h.sample_count >= 8 and h.coverage >= 0.6
          and h.peak_bpm between 120 and coalesce((
            select 229 - 0.7 * (extract(year from as_of) - prof.birth_year)
            from public.user_profiles prof
            where prof.user_id = target_user
              and extract(year from as_of) - prof.birth_year between 16 and 90), 210)
        order by h.peak_bpm desc, w.local_date desc, h.exercise_set_id
        limit 10) r), '[]'::jsonb));
$$;
revoke all on function private.heart_rate_inputs(uuid, date) from public, anon, authenticated;

create function public.get_my_heart_rate_inputs_v1(local_date date default null)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare as_of date := coalesce(get_my_heart_rate_inputs_v1.local_date, current_date);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if as_of > current_date + 2 or as_of < current_date - 2 then
    raise exception 'local_date is out of range' using errcode = '22023';
  end if;
  return private.heart_rate_inputs(auth.uid(), as_of);
end $$;
revoke all on function public.get_my_heart_rate_inputs_v1(date) from public, anon, authenticated;
grant execute on function public.get_my_heart_rate_inputs_v1(date) to authenticated;

-- The Coach's read (Contract 7 contributor `heart_rate_profile`): the same object for any athlete,
-- callable by the service role only.
create function public.get_heart_rate_inputs_v1(target_user uuid, local_date date)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
begin
  if target_user is null or get_heart_rate_inputs_v1.local_date is null then
    raise exception 'target_user and local_date are required' using errcode = '22023';
  end if;
  return private.heart_rate_inputs(target_user, get_heart_rate_inputs_v1.local_date);
end $$;
revoke all on function public.get_heart_rate_inputs_v1(uuid, date) from public, anon, authenticated;
grant execute on function public.get_heart_rate_inputs_v1(uuid, date) to service_role;
