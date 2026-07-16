create table public.health_workout_references (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  sample_id_hash text not null check (sample_id_hash ~ '^[0-9a-f]{64}$'),
  source_id_hash text not null check (source_id_hash ~ '^[0-9a-f]{64}$'),
  activity_type text not null check (length(activity_type) between 1 and 80),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_seconds integer not null check (duration_seconds between 1 and 86400),
  energy_kcal numeric(8,2) check (energy_kcal between 0 and 30000),
  local_date date not null,
  last_synced_at timestamptz not null default now(),
  unique(user_id,sample_id_hash), unique(id,user_id),
  check(ended_at>started_at)
);
create index health_workout_references_user_date on public.health_workout_references(user_id,local_date desc);

create table public.workout_reconciliations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  workout_session_id uuid not null,
  health_workout_reference_id uuid not null,
  status text not null check(status in ('suggested','confirmed','rejected','conflict')),
  confidence numeric(5,4) not null check(confidence between 0 and 1),
  overlap_seconds integer not null check(overlap_seconds>=0),
  duration_difference_seconds integer not null check(duration_difference_seconds>=0),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key(workout_session_id,user_id) references public.workout_sessions(id,user_id),
  foreign key(health_workout_reference_id,user_id) references public.health_workout_references(id,user_id),
  unique(workout_session_id,health_workout_reference_id), unique(id,user_id),
  check((status='confirmed')=(confirmed_at is not null))
);

alter table public.health_workout_references enable row level security;
alter table public.health_workout_references force row level security;
alter table public.workout_reconciliations enable row level security;
alter table public.workout_reconciliations force row level security;
create policy health_workout_references_own_read on public.health_workout_references for select to authenticated using(user_id=(select auth.uid()));
create policy workout_reconciliations_own_read on public.workout_reconciliations for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.health_workout_references,public.workout_reconciliations from anon,authenticated;
grant select on public.health_workout_references,public.workout_reconciliations to authenticated;

create function public.persist_health_workouts(target_user_id uuid,workout_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb; accepted integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  if jsonb_typeof(workout_payload)<>'array' or jsonb_array_length(workout_payload)>100 then raise exception 'invalid workout payload' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(workout_payload) loop
    if coalesce(item->>'sample_id_hash','')!~'^[0-9a-f]{64}$' or coalesce(item->>'source_id_hash','')!~'^[0-9a-f]{64}$'
      or length(coalesce(item->>'activity_type','')) not between 1 and 80
      or (item->>'ended_at')::timestamptz <= (item->>'started_at')::timestamptz then
      raise exception 'invalid health workout' using errcode='22023';
    end if;
    insert into public.health_workout_references(user_id,sample_id_hash,source_id_hash,activity_type,started_at,ended_at,duration_seconds,energy_kcal,local_date)
    values(target_user_id,item->>'sample_id_hash',item->>'source_id_hash',item->>'activity_type',(item->>'started_at')::timestamptz,(item->>'ended_at')::timestamptz,(item->>'duration_seconds')::integer,nullif(item->>'energy_kcal','')::numeric,(item->>'local_date')::date)
    on conflict(user_id,sample_id_hash) do update set activity_type=excluded.activity_type,started_at=excluded.started_at,ended_at=excluded.ended_at,duration_seconds=excluded.duration_seconds,energy_kcal=excluded.energy_kcal,last_synced_at=now();
    accepted:=accepted+1;
  end loop;
  insert into public.workout_reconciliations(user_id,workout_session_id,health_workout_reference_id,status,confidence,overlap_seconds,duration_difference_seconds)
  select target_user_id,s.id,h.id,
    case when abs(coalesce(s.duration_seconds,h.duration_seconds)-h.duration_seconds)>900 then 'conflict' else 'suggested' end,
    greatest(0,least(1,
      (case when s.local_date=h.local_date then .45 else 0 end)+
      (case when h.activity_type in ('TRADITIONAL_STRENGTH_TRAINING','FUNCTIONAL_STRENGTH_TRAINING','OTHER') then .25 else .05 end)+
      (case when abs(coalesce(s.duration_seconds,h.duration_seconds)-h.duration_seconds)<=900 then .30 when abs(coalesce(s.duration_seconds,h.duration_seconds)-h.duration_seconds)<=1800 then .15 else 0 end)
    )),
    greatest(0,extract(epoch from least(coalesce(s.actual_ended_at,s.completed_at),h.ended_at)-greatest(coalesce(s.actual_started_at,s.started_at),h.started_at))::integer),
    abs(coalesce(s.duration_seconds,h.duration_seconds)-h.duration_seconds)
  from public.workout_sessions s join public.health_workout_references h on h.user_id=s.user_id and h.local_date=s.local_date
  where s.user_id=target_user_id and s.state='completed'
  on conflict(workout_session_id,health_workout_reference_id) do update set confidence=excluded.confidence,overlap_seconds=excluded.overlap_seconds,duration_difference_seconds=excluded.duration_difference_seconds,status=case when workout_reconciliations.status in ('confirmed','rejected') then workout_reconciliations.status else excluded.status end;
  return jsonb_build_object('accepted_count',accepted);
end $$;

create function public.respond_workout_reconciliation(p_reconciliation_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path='' as $$
declare target public.workout_reconciliations%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into target from public.workout_reconciliations where id=p_reconciliation_id and user_id=auth.uid() for update;
  if not found then raise exception 'reconciliation not found' using errcode='P0002'; end if;
  update public.workout_reconciliations set status=case when p_accept then 'confirmed' else 'rejected' end,confirmed_at=case when p_accept then now() else null end where id=target.id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),case when p_accept then 'workout.reconciliation_confirmed' else 'workout.reconciliation_rejected' end,'workout_reconciliation',target.id,'succeeded','{}'::jsonb);
end $$;
create function public.persist_health_sync_v2(
  target_user_id uuid,sync_idempotency_key uuid,request_start date,request_end date,
  request_types text[],response_types text[],summary_payload jsonb,workout_payload jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; workout_result jsonb;
begin
  if auth.role()<>'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  result:=public.persist_health_sync(target_user_id,sync_idempotency_key,request_start,request_end,request_types,response_types,summary_payload);
  workout_result:=public.persist_health_workouts(target_user_id,workout_payload);
  return result||jsonb_build_object('workout_reference_count',(workout_result->>'accepted_count')::integer);
end $$;
revoke all on function public.persist_health_workouts(uuid,jsonb),public.persist_health_sync_v2(uuid,uuid,date,date,text[],text[],jsonb,jsonb),public.respond_workout_reconciliation(uuid,boolean) from public,anon,authenticated;
grant execute on function public.persist_health_workouts(uuid,jsonb) to service_role;
grant execute on function public.persist_health_sync_v2(uuid,uuid,date,date,text[],text[],jsonb,jsonb) to service_role;
grant execute on function public.respond_workout_reconciliation(uuid,boolean) to authenticated;
