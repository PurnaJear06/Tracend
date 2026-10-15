-- Per-set heart rate (coaching platform Contract 4, chunk C2).
--
-- 1. public.exercise_set_heart_rate holds one summary row per set: heart rate at the start, the
--    peak, the end, the drop 30 and 60 seconds after the end, how much of the set and the
--    following minute had samples (coverage, 0 to 1), the sample count and where the samples came
--    from. The phone computes the summary from Apple Health; raw samples never leave it.
-- 2. persist_set_heart_rate_v1 saves the summaries of one of the caller's own workouts, one row
--    per set, replacing the earlier row when the phone reads again (Watch samples can arrive
--    after the workout). Invalid values raise 22023.
-- 3. get_my_set_heart_rate_v1 returns a workout's summaries keyed by exercise order and set number.
-- Heart rate never changes a load or a prescription (program decision D9). Everything is additive.

-- 1. Table ------------------------------------------------------------------------------------

create table public.exercise_set_heart_rate (
  exercise_set_id uuid primary key,
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  start_bpm smallint,
  peak_bpm smallint,
  end_bpm smallint,
  drop_30s_bpm smallint,
  drop_60s_bpm smallint,
  coverage numeric(4, 3) not null,
  sample_count integer not null,
  source text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (exercise_set_id, user_id)
    references public.exercise_sets(id, user_id) on delete cascade,
  constraint exercise_set_heart_rate_bpm_check check (
    (start_bpm is null or start_bpm between 30 and 250)
    and (peak_bpm is null or peak_bpm between 30 and 250)
    and (end_bpm is null or end_bpm between 30 and 250)),
  constraint exercise_set_heart_rate_drop_check check (
    (drop_30s_bpm is null or drop_30s_bpm between -220 and 220)
    and (drop_60s_bpm is null or drop_60s_bpm between -220 and 220)),
  constraint exercise_set_heart_rate_peak_check check (
    (start_bpm is null or peak_bpm is null or peak_bpm >= start_bpm)
    and (end_bpm is null or peak_bpm is null or peak_bpm >= end_bpm)),
  constraint exercise_set_heart_rate_coverage_check check (coverage between 0 and 1),
  constraint exercise_set_heart_rate_samples_check check (sample_count between 1 and 5000),
  constraint exercise_set_heart_rate_source_check check (source in ('watch_workout', 'background'))
);

comment on table public.exercise_set_heart_rate is
  'Heart-rate summary of one set, computed on the phone from Apple Health samples. Never raw samples.';
comment on column public.exercise_set_heart_rate.coverage is
  'Share (0 to 1) of the set and the following 60 seconds that has heart-rate samples.';
comment on column public.exercise_set_heart_rate.source is
  'watch_workout: a Watch workout was sampling every few seconds; background: sparser samples.';

alter table public.exercise_set_heart_rate enable row level security;
alter table public.exercise_set_heart_rate force row level security;
create policy exercise_set_heart_rate_own_read on public.exercise_set_heart_rate
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.exercise_set_heart_rate from anon, authenticated;
grant select on public.exercise_set_heart_rate to authenticated;

-- 2. Save -------------------------------------------------------------------------------------

-- A whole or fractional JSON number between low and high. A missing key or JSON null is null
-- unless the value is required.
create function private.set_heart_rate_value(
  value jsonb, low numeric, high numeric, field text, required boolean, whole boolean)
returns numeric language plpgsql immutable set search_path = '' as $$
declare number numeric;
begin
  if value is null or jsonb_typeof(value) = 'null' then
    if required then
      raise exception '% is required', field using errcode = '22023';
    end if;
    return null;
  end if;
  if jsonb_typeof(value) <> 'number' then
    raise exception '% must be a number', field using errcode = '22023';
  end if;
  number := (value #>> '{}')::numeric;
  if (whole and number <> trunc(number)) or number < low or number > high then
    raise exception '% must be from % to %', field, low, high using errcode = '22023';
  end if;
  return number;
end $$;
revoke all on function private.set_heart_rate_value(jsonb, numeric, numeric, text, boolean, boolean)
  from public, anon, authenticated;

create function public.persist_set_heart_rate_v1(session_id uuid, summaries jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  target public.workout_sessions%rowtype; item jsonb; stored_set uuid; saved integer := 0;
  start_value smallint; peak_value smallint; end_value smallint; drop_30_value smallint;
  drop_60_value smallint; coverage_value numeric; samples_value integer; source_value text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into target from public.workout_sessions w
  where w.id = persist_set_heart_rate_v1.session_id and w.user_id = auth.uid();
  if not found then raise exception 'session not found' using errcode = 'P0002'; end if;
  if target.state = 'abandoned' then raise exception 'session was discarded' using errcode = '55000'; end if;
  if jsonb_typeof(summaries) <> 'array' or jsonb_array_length(summaries) not between 1 and 100 then
    raise exception 'summaries must be a list of 1 to 100 sets' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(summaries) loop
    if jsonb_typeof(item) <> 'object' then
      raise exception 'each summary must be an object' using errcode = '22023';
    end if;
    select s.id into stored_set
    from public.exercise_sets s
    join public.exercise_performances p on p.id = s.exercise_performance_id and p.user_id = s.user_id
    where p.workout_session_id = target.id and s.user_id = auth.uid() and s.completed
      and p.exercise_order = private.set_heart_rate_value(item->'exercise_order', 1, 100, 'exercise_order', true, true)
      and s.set_number = private.set_heart_rate_value(item->'set_number', 1, 20, 'set_number', true, true);
    if stored_set is null then raise exception 'unknown or unfinished set' using errcode = '22023'; end if;
    start_value := private.set_heart_rate_value(item->'start_bpm', 30, 250, 'start_bpm', false, true);
    peak_value := private.set_heart_rate_value(item->'peak_bpm', 30, 250, 'peak_bpm', false, true);
    end_value := private.set_heart_rate_value(item->'end_bpm', 30, 250, 'end_bpm', false, true);
    drop_30_value := private.set_heart_rate_value(item->'drop_30s_bpm', -220, 220, 'drop_30s_bpm', false, true);
    drop_60_value := private.set_heart_rate_value(item->'drop_60s_bpm', -220, 220, 'drop_60s_bpm', false, true);
    coverage_value := private.set_heart_rate_value(item->'coverage', 0, 1, 'coverage', true, false);
    samples_value := private.set_heart_rate_value(item->'sample_count', 1, 5000, 'sample_count', true, true);
    if jsonb_typeof(item->'source') is distinct from 'string'
       or item->>'source' not in ('watch_workout', 'background') then
      raise exception 'source must be watch_workout or background' using errcode = '22023';
    end if;
    source_value := item->>'source';
    if peak_value < start_value or peak_value < end_value then
      raise exception 'the peak cannot be below the start or the end' using errcode = '22023';
    end if;
    insert into public.exercise_set_heart_rate as h(
      exercise_set_id, user_id, start_bpm, peak_bpm, end_bpm, drop_30s_bpm, drop_60s_bpm,
      coverage, sample_count, source)
    values (stored_set, auth.uid(), start_value, peak_value, end_value, drop_30_value,
      drop_60_value, coverage_value, samples_value, source_value)
    on conflict (exercise_set_id) do update set
      start_bpm = excluded.start_bpm, peak_bpm = excluded.peak_bpm, end_bpm = excluded.end_bpm,
      drop_30s_bpm = excluded.drop_30s_bpm, drop_60s_bpm = excluded.drop_60s_bpm,
      coverage = excluded.coverage, sample_count = excluded.sample_count,
      source = excluded.source, updated_at = now();
    saved := saved + 1;
  end loop;
  return jsonb_build_object('schema_version', '1.0', 'session_id', target.id, 'saved', saved);
end $$;
revoke all on function public.persist_set_heart_rate_v1(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.persist_set_heart_rate_v1(uuid, jsonb) to authenticated;

-- 3. Read -------------------------------------------------------------------------------------

-- The summaries of one of the caller's workouts; row-level security limits the rows to their own.
create function public.get_my_set_heart_rate_v1(session_id uuid)
returns jsonb language plpgsql security invoker set search_path = '' stable as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'schema_version', '1.0',
    'session_id', get_my_set_heart_rate_v1.session_id,
    'sets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'exercise_order', p.exercise_order, 'set_number', s.set_number,
        'start_bpm', h.start_bpm, 'peak_bpm', h.peak_bpm, 'end_bpm', h.end_bpm,
        'drop_30s_bpm', h.drop_30s_bpm, 'drop_60s_bpm', h.drop_60s_bpm,
        'coverage', h.coverage, 'sample_count', h.sample_count, 'source', h.source)
        order by p.exercise_order, s.set_number)
      from public.exercise_set_heart_rate h
      join public.exercise_sets s on s.id = h.exercise_set_id
      join public.exercise_performances p on p.id = s.exercise_performance_id
      where p.workout_session_id = get_my_set_heart_rate_v1.session_id
    ), '[]'::jsonb));
end $$;
revoke all on function public.get_my_set_heart_rate_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_my_set_heart_rate_v1(uuid) to authenticated;
