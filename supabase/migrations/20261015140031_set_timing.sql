-- Set timing and reps left (coaching platform Contract 2, chunk C1).
--
-- 1. exercise_sets gains five nullable columns: started_at, completed_at, rest_before_seconds
--    (the rest actually taken before the set, 0-3600), rir (reps in reserve 0-5, 5 meaning
--    "5 or more") and timing_source ('app' or 'watch').
-- 2. sync_workout_draft keeps its signature and behaviour. Each set may carry the five keys; a
--    missing key keeps the stored value (installed builds send none), an explicit null clears it.
--    Invalid values raise 22023. A time more than 10 minutes in the future, or more than 10
--    minutes before the session's recorded start, is refused (22023); the 10 minutes allow for a
--    phone clock that differs from the server's. repetitions, load_kg, rpe and completed keep
--    their existing rule (written as sent, blank when absent).
-- 3. get_my_workout_session 1.1 and get_my_exercise_history 1.1 return the new set fields.
--    Both changes are additive.

-- 1. Columns ----------------------------------------------------------------------------------

alter table public.exercise_sets
  add column started_at timestamptz,
  add column completed_at timestamptz,
  add column rest_before_seconds integer,
  add column rir smallint,
  add column timing_source text,
  add constraint exercise_sets_timing_order_check
    check (started_at is null or completed_at is null or completed_at >= started_at),
  add constraint exercise_sets_rest_before_check
    check (rest_before_seconds is null or rest_before_seconds between 0 and 3600),
  add constraint exercise_sets_rir_check
    check (rir is null or rir between 0 and 5),
  add constraint exercise_sets_timing_source_check
    check (timing_source is null or timing_source in ('app', 'watch'));

comment on column public.exercise_sets.started_at is
  'When the set began: the end of the rest before it, or the athlete''s first edit of the set.';
comment on column public.exercise_sets.completed_at is 'When the set was ticked.';
comment on column public.exercise_sets.rest_before_seconds is
  'Rest actually taken before this set, from the previous set''s tick to this set''s start.';
comment on column public.exercise_sets.rir is 'Reps in reserve, 0 to 5; 5 means 5 or more.';
comment on column public.exercise_sets.timing_source is 'Who recorded the times: app or watch.';

-- 2. Draft sync -------------------------------------------------------------------------------

-- A set time from a draft: an ISO 8601 string with a time zone, at most 10 minutes ahead of
-- now and at most 10 minutes before the session's start. JSON null clears the time.
create function private.workout_set_time(value jsonb, session_start timestamptz)
returns timestamptz language plpgsql stable set search_path = '' as $$
declare parsed timestamptz;
begin
  if jsonb_typeof(value) = 'null' then return null; end if;
  if jsonb_typeof(value) <> 'string'
     or value #>> '{}' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}(:?\d{2})?)$' then
    raise exception 'set times are ISO 8601 with a time zone' using errcode = '22023';
  end if;
  begin
    parsed := (value #>> '{}')::timestamptz;
  exception when others then
    raise exception 'set time is not a real time' using errcode = '22023';
  end;
  if parsed > now() + interval '10 minutes' then
    raise exception 'set time is in the future' using errcode = '22023';
  end if;
  if parsed < session_start - interval '10 minutes' then
    raise exception 'set time is before the workout started' using errcode = '22023';
  end if;
  return parsed;
end $$;
revoke all on function private.workout_set_time(jsonb, timestamptz) from public, anon, authenticated;

-- A whole JSON number between low and high. JSON null clears the value.
create function private.workout_set_whole_number(value jsonb, low integer, high integer, field text)
returns integer language plpgsql immutable set search_path = '' as $$
declare number numeric;
begin
  if jsonb_typeof(value) = 'null' then return null; end if;
  if jsonb_typeof(value) <> 'number' then
    raise exception '% must be a number', field using errcode = '22023';
  end if;
  number := value::numeric;
  if number <> trunc(number) or number < low or number > high then
    raise exception '% must be a whole number from % to %', field, low, high using errcode = '22023';
  end if;
  return number::integer;
end $$;
revoke all on function private.workout_set_whole_number(jsonb, integer, integer, text)
  from public, anon, authenticated;

create or replace function public.sync_workout_draft(session_id uuid, client_revision integer, draft jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare session public.workout_sessions%rowtype; exercise jsonb; set_row jsonb; performance_id uuid;
  requested_status text; stored public.exercise_sets%rowtype; session_start timestamptz;
  next_started timestamptz; next_completed timestamptz; next_rest integer; next_rir integer;
  next_source text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into session from public.workout_sessions where id=session_id and user_id=auth.uid() for update;
  if not found then raise exception 'session not found' using errcode='P0002'; end if;
  if session.state <> 'in_progress' then raise exception 'session is immutable' using errcode='55000'; end if;
  if client_revision <= session.client_revision then
    return jsonb_build_object('session_id',session.id,'client_revision',session.client_revision,'replayed',true);
  end if;
  if jsonb_typeof(draft->'exercises') <> 'array' then raise exception 'invalid workout draft' using errcode='22023'; end if;
  session_start := coalesce(session.actual_started_at, session.started_at);
  for exercise in select value from jsonb_array_elements(draft->'exercises') loop
    select id into performance_id from public.exercise_performances
    where workout_session_id=session.id and exercise_order=(exercise->>'order')::smallint;
    if performance_id is null then raise exception 'unknown exercise order' using errcode='22023'; end if;
    requested_status := coalesce(exercise->>'status','unknown');
    if requested_status not in ('unknown','performed','skipped') then raise exception 'invalid exercise status' using errcode='22023'; end if;
    update public.exercise_performances set
      status=requested_status,
      pain_flag=coalesce((exercise->>'pain_flag')::boolean,pain_flag),
      note=coalesce(exercise->>'note',note),
      rest_seconds=coalesce(nullif(exercise->>'rest_seconds','')::smallint,rest_seconds),
      performance_kind=coalesce(exercise->>'performance_kind',performance_kind),
      performed_name=coalesce(nullif(exercise->>'performed_name',''),performed_name),
      substitution_reason=coalesce(nullif(exercise->>'substitution_reason',''),substitution_reason)
    where id=performance_id;
    for set_row in select value from jsonb_array_elements(coalesce(exercise->'sets','[]'::jsonb)) loop
      select * into stored from public.exercise_sets
      where exercise_performance_id=performance_id and set_number=(set_row->>'number')::smallint
      for update;
      if not found then raise exception 'unknown set number' using errcode='22023'; end if;
      next_started := case when set_row ? 'started_at'
        then private.workout_set_time(set_row->'started_at', session_start) else stored.started_at end;
      next_completed := case when set_row ? 'completed_at'
        then private.workout_set_time(set_row->'completed_at', session_start) else stored.completed_at end;
      next_rest := case when set_row ? 'rest_before_seconds'
        then private.workout_set_whole_number(set_row->'rest_before_seconds', 0, 3600, 'rest_before_seconds')
        else stored.rest_before_seconds end;
      next_rir := case when set_row ? 'rir'
        then private.workout_set_whole_number(set_row->'rir', 0, 5, 'rir') else stored.rir end;
      next_source := stored.timing_source;
      if set_row ? 'timing_source' then
        if jsonb_typeof(set_row->'timing_source') = 'null' then
          next_source := null;
        elsif set_row->'timing_source' in ('"app"'::jsonb, '"watch"'::jsonb) then
          next_source := set_row->>'timing_source';
        else
          raise exception 'timing_source must be app or watch' using errcode='22023';
        end if;
      end if;
      if next_completed < next_started then
        raise exception 'a set cannot end before it starts' using errcode='22023';
      end if;
      update public.exercise_sets set
        repetitions=nullif(set_row->>'repetitions','')::smallint,
        load_kg=nullif(set_row->>'load_kg','')::numeric,
        rpe=nullif(set_row->>'rpe','')::numeric,
        completed=coalesce((set_row->>'completed')::boolean,false),
        started_at=next_started,
        completed_at=next_completed,
        rest_before_seconds=next_rest,
        rir=next_rir,
        timing_source=next_source
      where id=stored.id;
    end loop;
  end loop;
  update public.workout_sessions set
    client_revision=sync_workout_draft.client_revision,
    notes=coalesce(draft->>'notes',notes),updated_at=now()
  where id=session.id;
  return jsonb_build_object('session_id',session.id,'client_revision',client_revision,'replayed',false);
end $$;

-- 3. Reads ------------------------------------------------------------------------------------

create or replace function public.get_my_workout_session(
  p_planned_workout_id uuid,
  p_local_date date
)
returns jsonb language plpgsql security invoker set search_path='' stable as $$
declare target public.workout_sessions%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into target from public.workout_sessions
  where user_id=auth.uid() and planned_workout_id=p_planned_workout_id
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

-- Unchanged from 1.0 except the version and the last session's set fields: rir, started_at,
-- completed_at, rest_before_seconds and timing_source.
create or replace function public.get_my_exercise_history(p_keys text[], p_sessions integer default 8)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare keys text[]; session_limit integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_keys is null or cardinality(p_keys) = 0 then
    raise exception 'at least one exercise key is required' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_keys) k where k is null or length(btrim(k)) not between 1 and 120) then
    raise exception 'each exercise key must be 1 to 120 characters' using errcode = '22023';
  end if;
  select array_agg(distinct btrim(k)) into keys from unnest(p_keys) k;
  if cardinality(keys) > 20 then
    raise exception 'at most 20 exercise keys' using errcode = '22023';
  end if;
  session_limit := greatest(1, least(coalesce(p_sessions, 8), 12));

  return jsonb_build_object(
    'schema_version', '1.1',
    'sessions_limit', session_limit,
    'exercises', coalesce((
      with requested as (
        select k as key, c.slug, private.exercise_name_key(k) as name_key,
          private.exercise_name_key(c.name) as catalog_name_key,
          coalesce(c.slug like 'assisted-%',
            private.exercise_name_key(k) like 'assisted %') as assisted
        from unnest(keys) k
        left join public.exercise_catalog c on c.slug = k
      ), matched as (
        select r.key, r.assisted, s.id as session_id, s.local_date, s.completed_at,
          p.exercise_order, es.set_number, es.load_kg, es.repetitions, es.rpe, es.rir,
          es.started_at as set_started_at, es.completed_at as set_completed_at,
          es.rest_before_seconds, es.timing_source
        from requested r
        join public.exercise_performances p on p.user_id = auth.uid()
        left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
        join public.workout_sessions s on s.id = p.workout_session_id and s.user_id = p.user_id
          and s.state = 'completed'
        join public.exercise_sets es on es.exercise_performance_id = p.id and es.user_id = p.user_id
          and es.completed and es.repetitions > 0
        where p.status <> 'skipped'
          and (
            (r.slug is not null and p.exercise_slug = r.slug)
            -- A catalog exercise takes older unslugged rows by name only when they were
            -- prescribed; a substitution or an extra never joins it because a name matches.
            or (r.slug is not null and p.exercise_slug is null and p.performance_kind = 'prescribed'
                and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
                    = r.catalog_name_key)
            or (r.slug is null and p.exercise_slug is null
                and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
                    = r.name_key)
          )
      ), kinds as (
        select key, case when assisted then 'assistance'
            when bool_or(load_kg > 0) then 'load' else 'reps' end as kind
        from matched group by key, assisted
      ), ranked as (
        select m.*, k.kind,
          row_number() over (partition by m.key, m.session_id
            order by case when k.kind = 'load' then m.load_kg end desc nulls last,
                     case when k.kind = 'assistance' then m.load_kg end asc nulls last,
                     m.repetitions desc, m.set_number) as in_session_rank,
          row_number() over (partition by m.key
            order by case when k.kind = 'load' then m.load_kg end desc nulls last,
                     case when k.kind = 'assistance' then m.load_kg end asc nulls last,
                     m.repetitions desc, m.local_date, m.completed_at) as overall_rank
        from matched m join kinds k on k.key = m.key
        where k.kind = 'reps'
          or (k.kind = 'load' and m.load_kg > 0)
          or (k.kind = 'assistance' and m.load_kg is not null)
      ), latest as (
        select distinct on (key) key, session_id, local_date
        from matched
        order by key, local_date desc, completed_at desc
      ), tops as (
        select key, session_id, local_date, completed_at, load_kg, repetitions,
          row_number() over (partition by key order by local_date desc, completed_at desc) as recency
        from ranked where in_session_rank = 1
      )
      select jsonb_agg(jsonb_build_object(
        'key', r.key,
        'kind', k.kind,
        'last_session', (
          select jsonb_build_object('session_id', l.session_id, 'local_date', l.local_date,
            'sets', (select jsonb_agg(jsonb_build_object(
                'set_number', m.set_number, 'load_kg', m.load_kg,
                'repetitions', m.repetitions, 'rpe', m.rpe, 'rir', m.rir,
                'started_at', m.set_started_at, 'completed_at', m.set_completed_at,
                'rest_before_seconds', m.rest_before_seconds,
                'timing_source', m.timing_source)
              order by m.exercise_order, m.set_number)
              from matched m where m.key = l.key and m.session_id = l.session_id))
          from latest l where l.key = r.key),
        'best_set', (
          select jsonb_build_object('kind', b.kind, 'load_kg', b.load_kg,
            'repetitions', b.repetitions, 'local_date', b.local_date)
          from ranked b where b.key = r.key and b.overall_rank = 1),
        'top_sets', coalesce((
          select jsonb_agg(jsonb_build_object('local_date', t.local_date,
              'load_kg', t.load_kg, 'repetitions', t.repetitions)
            order by t.local_date desc, t.completed_at desc)
          from tops t where t.key = r.key and t.recency <= session_limit), '[]'::jsonb)
      ) order by r.key)
      from requested r left join kinds k on k.key = r.key
    ), '[]'::jsonb)
  );
end $$;
