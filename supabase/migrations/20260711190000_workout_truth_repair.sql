-- Workout truth repair: preserve prescribed intent separately from observed execution.

alter table public.exercise_performances
  drop constraint if exists exercise_performances_status_check;
alter table public.exercise_performances
  alter column planned_exercise_id drop not null,
  add column if not exists performed_name text,
  add column if not exists performance_kind text not null default 'prescribed',
  add column if not exists substitution_reason text,
  add column if not exists provenance text not null default 'tracend',
  add column if not exists rest_seconds smallint,
  add constraint exercise_performances_status_check
    check (status in ('unknown','performed','skipped')) not valid,
  add constraint exercise_performances_kind_check
    check (performance_kind in ('prescribed','substituted','extra')),
  add constraint exercise_performances_performed_name_check
    check (performed_name is null or length(performed_name) between 1 and 120),
  add constraint exercise_performances_substitution_reason_check
    check (substitution_reason is null or length(substitution_reason) between 1 and 500),
  add constraint exercise_performances_provenance_check
    check (provenance in ('tracend','owner_correction','imported')),
  add constraint exercise_performances_rest_check
    check (rest_seconds is null or rest_seconds between 0 and 3600),
  add constraint exercise_performances_shape_check
    check (
      (performance_kind = 'prescribed' and planned_exercise_id is not null)
      or (performance_kind = 'substituted' and planned_exercise_id is not null and performed_name is not null and substitution_reason is not null)
      or (performance_kind = 'extra' and planned_exercise_id is null and performed_name is not null)
    );

update public.exercise_performances set status = 'unknown' where status = 'planned';
alter table public.exercise_performances
  validate constraint exercise_performances_status_check;

alter table public.workout_sessions
  add column if not exists actual_started_at timestamptz,
  add column if not exists actual_ended_at timestamptz,
  add column if not exists logging_completeness numeric(5,4),
  add column if not exists correction_status text not null default 'none',
  add constraint workout_sessions_actual_time_check
    check (actual_ended_at is null or actual_started_at is null or actual_ended_at >= actual_started_at),
  add constraint workout_sessions_logging_completeness_check
    check (logging_completeness is null or logging_completeness between 0 and 1),
  add constraint workout_sessions_correction_status_check
    check (correction_status in ('none','needs_review','corrected'));

create or replace function public.start_workout(
  p_planned_workout_id uuid,
  p_local_date date,
  p_timezone text,
  p_idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; version_id uuid; exercise record; performance_id uuid; n integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select w.plan_version_id into version_id
  from public.planned_workouts w
  join public.training_plan_versions v on v.id=w.plan_version_id and v.user_id=w.user_id
  where w.id=p_planned_workout_id and w.user_id=auth.uid() and v.status='active';
  if not found then raise exception 'planned workout not found' using errcode='P0002'; end if;

  select id into result_id from public.workout_sessions
  where user_id=auth.uid() and idempotency_key=p_idempotency_key;
  if result_id is not null then return result_id; end if;

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

  insert into public.workout_sessions(
    user_id,plan_version_id,planned_workout_id,local_date,timezone,idempotency_key,actual_started_at
  ) values(
    auth.uid(),version_id,p_planned_workout_id,p_local_date,p_timezone,p_idempotency_key,now()
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
    for n in 1..exercise.set_count loop
      insert into public.exercise_sets(user_id,exercise_performance_id,set_number)
      values(auth.uid(),performance_id,n);
    end loop;
  end loop;
  return result_id;
end $$;

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
    and (state='in_progress' or local_date=p_local_date)
  order by case state when 'in_progress' then 0 when 'completed' then 1 else 2 end, started_at desc
  limit 1;
  if not found then return null; end if;
  return jsonb_build_object(
    'session_id',target.id,'state',target.state,'revision',target.client_revision,
    'idempotency_key',target.idempotency_key,'local_date',target.local_date,
    'actual_started_at',target.actual_started_at,'actual_ended_at',target.actual_ended_at,
    'duration_seconds',target.duration_seconds,'notes',target.notes,
    'exercises',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'performance_id',p.id,'order',p.exercise_order,'status',p.status,
        'performance_kind',p.performance_kind,'performed_name',p.performed_name,
        'substitution_reason',p.substitution_reason,'pain_flag',p.pain_flag,
        'note',p.note,'rest_seconds',p.rest_seconds,
        'sets',(select coalesce(jsonb_agg(jsonb_build_object(
          'number',s.set_number,'repetitions',s.repetitions,'load_kg',s.load_kg,
          'rpe',s.rpe,'completed',s.completed
        ) order by s.set_number),'[]'::jsonb) from public.exercise_sets s where s.exercise_performance_id=p.id)
      ) order by p.exercise_order),'[]'::jsonb)
      from public.exercise_performances p where p.workout_session_id=target.id
    )
  );
end $$;

create or replace function public.sync_workout_draft(session_id uuid, client_revision integer, draft jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare session public.workout_sessions%rowtype; exercise jsonb; set_row jsonb; performance_id uuid; requested_status text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into session from public.workout_sessions where id=session_id and user_id=auth.uid() for update;
  if not found then raise exception 'session not found' using errcode='P0002'; end if;
  if session.state <> 'in_progress' then raise exception 'session is immutable' using errcode='55000'; end if;
  if client_revision <= session.client_revision then
    return jsonb_build_object('session_id',session.id,'client_revision',session.client_revision,'replayed',true);
  end if;
  if jsonb_typeof(draft->'exercises') <> 'array' then raise exception 'invalid workout draft' using errcode='22023'; end if;
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
      update public.exercise_sets set
        repetitions=nullif(set_row->>'repetitions','')::smallint,
        load_kg=nullif(set_row->>'load_kg','')::numeric,
        rpe=nullif(set_row->>'rpe','')::numeric,
        completed=coalesce((set_row->>'completed')::boolean,false)
      where exercise_performance_id=performance_id and set_number=(set_row->>'number')::smallint;
      if not found then raise exception 'unknown set number' using errcode='22023'; end if;
    end loop;
  end loop;
  update public.workout_sessions set
    client_revision=sync_workout_draft.client_revision,
    notes=coalesce(draft->>'notes',notes),updated_at=now()
  where id=session.id;
  return jsonb_build_object('session_id',session.id,'client_revision',client_revision,'replayed',false);
end $$;

create or replace function public.complete_workout(
  session_id uuid,
  client_revision integer,
  duration_seconds integer,
  session_energy smallint,
  session_effort numeric,
  notes text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare session public.workout_sessions%rowtype; completed_sets integer; total_sets integer; coverage numeric;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into session from public.workout_sessions where id=session_id and user_id=auth.uid() for update;
  if not found then raise exception 'session not found' using errcode='P0002'; end if;
  if session.state='completed' then return jsonb_build_object('session_id',session.id,'replayed',true); end if;
  if client_revision < session.client_revision then raise exception 'stale client revision' using errcode='40001'; end if;
  select count(*) filter(where s.completed),count(*) into completed_sets,total_sets
  from public.exercise_sets s join public.exercise_performances p on p.id=s.exercise_performance_id
  where p.workout_session_id=session.id;
  if completed_sets=0 then raise exception 'complete at least one set' using errcode='22023'; end if;
  coverage := completed_sets::numeric / greatest(total_sets,1);
  update public.exercise_performances p set status=case
    when p.status='skipped' then 'skipped'
    when exists(select 1 from public.exercise_sets s where s.exercise_performance_id=p.id and s.completed) then 'performed'
    else 'unknown' end
  where p.workout_session_id=session.id;
  update public.workout_sessions set
    state='completed',completed_at=now(),actual_ended_at=coalesce(actual_ended_at,now()),
    duration_seconds=complete_workout.duration_seconds,session_energy=complete_workout.session_energy,
    session_effort=complete_workout.session_effort,notes=complete_workout.notes,
    logging_completeness=coverage,client_revision=greatest(workout_sessions.client_revision,complete_workout.client_revision),updated_at=now()
  where id=session.id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'workout.completed','workout_session',session.id,'succeeded',
    jsonb_build_object('completed_sets',completed_sets,'total_sets',total_sets,'logging_completeness',coverage));
  return jsonb_build_object('session_id',session.id,'completed_sets',completed_sets,'total_sets',total_sets,'logging_completeness',coverage,'replayed',false);
end $$;

create or replace function public.correct_completed_workout(
  p_session_id uuid,
  p_actual_started_at timestamptz,
  p_actual_ended_at timestamptz,
  p_reason text,
  p_abandon_duplicate_session_id uuid default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target public.workout_sessions%rowtype; duplicate public.workout_sessions%rowtype; old_duration integer; new_duration integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) not between 3 and 500 or p_actual_ended_at <= p_actual_started_at then
    raise exception 'invalid correction' using errcode='22023';
  end if;
  select * into target from public.workout_sessions where id=p_session_id and user_id=auth.uid() and state='completed' for update;
  if not found then raise exception 'completed session not found' using errcode='P0002'; end if;
  old_duration := target.duration_seconds;
  new_duration := extract(epoch from (p_actual_ended_at-p_actual_started_at))::integer;
  insert into public.workout_amendments(user_id,workout_session_id,field_path,old_value,new_value,reason)
  values(auth.uid(),target.id,'actual_time',jsonb_build_object('started_at',target.actual_started_at,'ended_at',target.actual_ended_at,'duration_seconds',old_duration),jsonb_build_object('started_at',p_actual_started_at,'ended_at',p_actual_ended_at,'duration_seconds',new_duration),trim(p_reason));
  update public.workout_sessions set actual_started_at=p_actual_started_at,actual_ended_at=p_actual_ended_at,
    duration_seconds=new_duration,correction_status='corrected',updated_at=now() where id=target.id;
  update public.exercise_performances set status='unknown'
    where workout_session_id=target.id and status='skipped'
      and not exists(select 1 from public.exercise_sets s where s.exercise_performance_id=exercise_performances.id and s.completed);
  if p_abandon_duplicate_session_id is not null then
    select * into duplicate from public.workout_sessions where id=p_abandon_duplicate_session_id and user_id=auth.uid() and state='in_progress' for update;
    if not found or duplicate.planned_workout_id<>target.planned_workout_id or exists(
      select 1 from public.exercise_sets s join public.exercise_performances p on p.id=s.exercise_performance_id
      where p.workout_session_id=duplicate.id and (s.completed or s.repetitions is not null or s.load_kg is not null)
    ) then raise exception 'duplicate session is not safely abandonable' using errcode='22023'; end if;
    update public.workout_sessions set state='abandoned',updated_at=now() where id=duplicate.id;
    insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
    values(auth.uid(),'workout.duplicate_abandoned','workout_session',duplicate.id,'succeeded',jsonb_build_object('corrected_session_id',target.id));
  end if;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'workout.corrected','workout_session',target.id,'succeeded',jsonb_build_object('duration_seconds',new_duration));
  return jsonb_build_object('session_id',target.id,'duration_seconds',new_duration,'duplicate_abandoned',p_abandon_duplicate_session_id is not null);
end $$;

create or replace function public.get_my_workout_repair_candidates()
returns jsonb language sql security invoker set search_path='' stable as $$
  select coalesce(jsonb_agg(candidate order by (candidate->>'local_date') desc),'[]'::jsonb)
  from (
    select jsonb_build_object(
      'session_id',s.id,'local_date',s.local_date,'workout_name',w.name,
      'recorded_duration_seconds',s.duration_seconds,
      'healthkit_duration_seconds',h.workout_minutes*60,
      'recommended_started_at',coalesce(s.completed_at,now())-(h.workout_minutes||' minutes')::interval,
      'recommended_ended_at',s.completed_at,
      'blank_duplicate_session_id',(
        select d.id from public.workout_sessions d
        where d.user_id=s.user_id and d.planned_workout_id=s.planned_workout_id and d.state='in_progress'
          and not exists(select 1 from public.exercise_performances ep join public.exercise_sets es on es.exercise_performance_id=ep.id where ep.workout_session_id=d.id and (es.completed or es.repetitions is not null or es.load_kg is not null))
        order by d.started_at desc limit 1
      )
    ) candidate
    from public.workout_sessions s
    join public.planned_workouts w on w.id=s.planned_workout_id and w.user_id=s.user_id
    join public.daily_health_summaries h on h.user_id=s.user_id and h.local_date=s.local_date
    where s.user_id=auth.uid() and s.state='completed' and s.correction_status<>'corrected'
      and h.workout_minutes>=30 and coalesce(s.duration_seconds,0)<greatest(300,h.workout_minutes*30)
  ) q;
$$;

revoke all on function public.get_my_workout_session(uuid,date), public.correct_completed_workout(uuid,timestamptz,timestamptz,text,uuid), public.get_my_workout_repair_candidates() from public,anon,authenticated;
grant execute on function public.get_my_workout_session(uuid,date), public.correct_completed_workout(uuid,timestamptz,timestamptz,text,uuid), public.get_my_workout_repair_candidates() to authenticated;
