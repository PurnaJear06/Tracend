create type public.workout_session_state as enum ('in_progress', 'completed', 'abandoned');

create table public.planned_workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  plan_version_id uuid not null,
  workout_order smallint not null check (workout_order between 1 and 7),
  name text not null check (length(name) between 1 and 120),
  objective text not null check (length(objective) between 1 and 500),
  preferred_weekday smallint check (preferred_weekday between 1 and 7),
  estimated_minutes smallint not null check (estimated_minutes between 15 and 180),
  warm_up_guidance text not null check (length(warm_up_guidance) between 1 and 500),
  cool_down_guidance text not null check (length(cool_down_guidance) between 1 and 500),
  foreign key (plan_version_id, user_id)
    references public.training_plan_versions(id, user_id) on delete cascade,
  unique (plan_version_id, workout_order), unique (id, user_id)
);

create table public.planned_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  planned_workout_id uuid not null,
  exercise_order smallint not null check (exercise_order between 1 and 30),
  display_name_snapshot text not null check (length(display_name_snapshot) between 1 and 120),
  set_count smallint not null check (set_count between 1 and 12),
  rep_min smallint not null check (rep_min between 1 and 100),
  rep_max smallint not null check (rep_max between rep_min and 100),
  target_rpe numeric(3,1) check (target_rpe between 1 and 10),
  rest_seconds smallint not null check (rest_seconds between 15 and 600),
  notes text not null default '' check (length(notes) <= 500),
  foreign key (planned_workout_id, user_id)
    references public.planned_workouts(id, user_id) on delete cascade,
  unique (planned_workout_id, exercise_order), unique (id, user_id)
);

create table public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  plan_version_id uuid not null, planned_workout_id uuid not null,
  local_date date not null, timezone text not null check (length(timezone) between 1 and 64),
  state public.workout_session_state not null default 'in_progress',
  idempotency_key uuid not null, client_revision integer not null default 0 check (client_revision >= 0),
  started_at timestamptz not null default now(), completed_at timestamptz,
  duration_seconds integer check (duration_seconds between 0 and 86400),
  session_energy smallint check (session_energy between 1 and 5),
  session_effort numeric(3,1) check (session_effort between 1 and 10),
  notes text not null default '' check (length(notes) <= 2000), updated_at timestamptz not null default now(),
  foreign key (plan_version_id, user_id) references public.training_plan_versions(id, user_id),
  foreign key (planned_workout_id, user_id) references public.planned_workouts(id, user_id),
  unique (user_id, idempotency_key), unique (id, user_id),
  check ((state = 'completed') = (completed_at is not null))
);
create unique index workout_sessions_one_open on public.workout_sessions(user_id, planned_workout_id) where state = 'in_progress';
create index workout_sessions_user_date on public.workout_sessions(user_id, local_date desc);

create table public.exercise_performances (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.user_accounts(id) on delete cascade,
  workout_session_id uuid not null, planned_exercise_id uuid not null,
  exercise_order smallint not null check (exercise_order between 1 and 30),
  status text not null default 'planned' check (status in ('planned','performed','skipped')),
  pain_flag boolean not null default false, note text not null default '' check (length(note) <= 1000),
  foreign key (workout_session_id, user_id) references public.workout_sessions(id, user_id) on delete cascade,
  foreign key (planned_exercise_id, user_id) references public.planned_exercises(id, user_id),
  unique (workout_session_id, exercise_order), unique (id, user_id)
);

create table public.exercise_sets (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.user_accounts(id) on delete cascade,
  exercise_performance_id uuid not null, set_number smallint not null check (set_number between 1 and 20),
  repetitions smallint check (repetitions between 0 and 100), load_kg numeric(7,2) check (load_kg between 0 and 2000),
  rpe numeric(3,1) check (rpe between 1 and 10), completed boolean not null default false,
  foreign key (exercise_performance_id, user_id) references public.exercise_performances(id, user_id) on delete cascade,
  unique (exercise_performance_id, set_number), unique (id, user_id)
);

create table public.workout_amendments (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.user_accounts(id) on delete cascade,
  workout_session_id uuid not null, field_path text not null check (length(field_path) between 1 and 160),
  old_value jsonb not null, new_value jsonb not null, reason text not null check (length(reason) between 1 and 500),
  created_at timestamptz not null default now(),
  foreign key (workout_session_id, user_id) references public.workout_sessions(id, user_id)
);

create table public.daily_check_ins (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.user_accounts(id) on delete cascade,
  local_date date not null, timezone text not null check (length(timezone) between 1 and 64),
  revision integer not null check (revision > 0), idempotency_key uuid not null,
  sleep_quality smallint not null check (sleep_quality between 1 and 5), energy smallint not null check (energy between 1 and 5),
  soreness smallint not null check (soreness between 1 and 5), hunger smallint not null check (hunger between 1 and 5),
  mood smallint not null check (mood between 1 and 5), pain_severity smallint not null default 0 check (pain_severity between 0 and 10),
  available_to_train boolean not null, note text not null default '' check (length(note) <= 1000),
  superseded_at timestamptz, created_at timestamptz not null default now(),
  unique (user_id, idempotency_key), unique (user_id, local_date, revision), unique (id, user_id)
);
create unique index daily_check_ins_one_current on public.daily_check_ins(user_id, local_date) where superseded_at is null;

create function private.seed_workouts_for_plan_version(target_version_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare session_count integer; i integer; workout_id uuid; names text[] := array['Push day','Pull day','Leg day','Upper day','Lower day'];
begin
  select sessions_per_week into session_count from public.training_plan_versions
  where id = target_version_id and user_id = target_user_id and status = 'active';
  if not found then raise exception 'active plan version not found' using errcode = 'P0002'; end if;
  for i in 1..session_count loop
    insert into public.planned_workouts(user_id,plan_version_id,workout_order,name,objective,preferred_weekday,estimated_minutes,warm_up_guidance,cool_down_guidance)
    values(target_user_id,target_version_id,i,names[1 + ((i - 1) % 5)],'Build repeatable strength while keeping fatigue measurable.',least(7,1 + ((i - 1) * 2)),60,
      'Complete five minutes of easy movement and two progressive warm-up sets.','Finish with easy movement and record pain or unusual fatigue.')
    on conflict (plan_version_id,workout_order) do update set name=excluded.name returning id into workout_id;
    if i % 3 = 1 then
      insert into public.planned_exercises(user_id,planned_workout_id,exercise_order,display_name_snapshot,set_count,rep_min,rep_max,target_rpe,rest_seconds) values
      (target_user_id,workout_id,1,'Incline dumbbell press',3,8,10,8,120),(target_user_id,workout_id,2,'Machine chest press',3,10,12,8,120),(target_user_id,workout_id,3,'Cable lateral raise',3,12,15,9,75),(target_user_id,workout_id,4,'Rope pressdown',3,10,12,8,75) on conflict do nothing;
    elsif i % 3 = 2 then
      insert into public.planned_exercises(user_id,planned_workout_id,exercise_order,display_name_snapshot,set_count,rep_min,rep_max,target_rpe,rest_seconds) values
      (target_user_id,workout_id,1,'Lat pulldown',3,8,10,8,120),(target_user_id,workout_id,2,'Seated cable row',3,10,12,8,120),(target_user_id,workout_id,3,'Romanian deadlift',3,8,10,8,150) on conflict do nothing;
    else
      insert into public.planned_exercises(user_id,planned_workout_id,exercise_order,display_name_snapshot,set_count,rep_min,rep_max,target_rpe,rest_seconds) values
      (target_user_id,workout_id,1,'Leg press',3,8,10,8,150),(target_user_id,workout_id,2,'Romanian deadlift',3,8,10,8,150),(target_user_id,workout_id,3,'Cable lateral raise',3,12,15,9,75) on conflict do nothing;
    end if;
  end loop;
end; $$;
revoke all on function private.seed_workouts_for_plan_version(uuid,uuid) from public,anon,authenticated;
do $$ declare v record; begin for v in select id,user_id from public.training_plan_versions where status='active' loop perform private.seed_workouts_for_plan_version(v.id,v.user_id); end loop; end $$;
create function private.seed_active_plan_workouts_trigger() returns trigger language plpgsql security definer set search_path='' as $$ begin if new.status='active' then perform private.seed_workouts_for_plan_version(new.id,new.user_id); end if; return new; end $$;
revoke all on function private.seed_active_plan_workouts_trigger() from public,anon,authenticated;
create trigger training_plan_version_seed_workouts after insert on public.training_plan_versions for each row execute function private.seed_active_plan_workouts_trigger();

create function public.start_workout(p_planned_workout_id uuid, p_local_date date, p_timezone text, p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; version_id uuid; exercise record; performance_id uuid; n integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select w.plan_version_id into version_id from public.planned_workouts w join public.training_plan_versions v on v.id=w.plan_version_id and v.user_id=w.user_id
  where w.id=p_planned_workout_id and w.user_id=auth.uid() and v.status='active';
  if not found then raise exception 'planned workout not found' using errcode='P0002'; end if;
  select id into result_id from public.workout_sessions s where s.user_id=auth.uid() and s.idempotency_key=p_idempotency_key;
  if result_id is not null then return result_id; end if;
  insert into public.workout_sessions(user_id,plan_version_id,planned_workout_id,local_date,timezone,idempotency_key)
  values(auth.uid(),version_id,p_planned_workout_id,p_local_date,p_timezone,p_idempotency_key)
  on conflict (user_id,planned_workout_id) where state='in_progress' do update set updated_at=now() returning id into result_id;
  for exercise in select * from public.planned_exercises pe where pe.planned_workout_id=p_planned_workout_id order by exercise_order loop
    insert into public.exercise_performances(user_id,workout_session_id,planned_exercise_id,exercise_order)
    values(auth.uid(),result_id,exercise.id,exercise.exercise_order) on conflict do nothing returning id into performance_id;
    if performance_id is null then select id into performance_id from public.exercise_performances where workout_session_id=result_id and exercise_order=exercise.exercise_order; end if;
    for n in 1..exercise.set_count loop insert into public.exercise_sets(user_id,exercise_performance_id,set_number) values(auth.uid(),performance_id,n) on conflict do nothing; end loop;
  end loop; return result_id;
end $$;

create function public.sync_workout_draft(session_id uuid, client_revision integer, draft jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare session public.workout_sessions%rowtype; exercise jsonb; set_row jsonb; performance_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into session from public.workout_sessions where id=session_id and user_id=auth.uid() for update;
  if not found then raise exception 'session not found' using errcode='P0002'; end if;
  if session.state <> 'in_progress' then raise exception 'session is immutable' using errcode='55000'; end if;
  if client_revision <= session.client_revision then return jsonb_build_object('session_id',session.id,'client_revision',session.client_revision,'replayed',true); end if;
  if jsonb_typeof(draft->'exercises') <> 'array' then raise exception 'invalid workout draft' using errcode='22023'; end if;
  for exercise in select value from jsonb_array_elements(draft->'exercises') loop
    select id into performance_id from public.exercise_performances where workout_session_id=session.id and exercise_order=(exercise->>'order')::smallint;
    if performance_id is null then raise exception 'unknown exercise order' using errcode='22023'; end if;
    update public.exercise_performances set pain_flag=coalesce((exercise->>'pain_flag')::boolean,pain_flag),note=coalesce(exercise->>'note',note) where id=performance_id;
    for set_row in select value from jsonb_array_elements(coalesce(exercise->'sets','[]'::jsonb)) loop
      update public.exercise_sets set repetitions=nullif(set_row->>'repetitions','')::smallint,load_kg=nullif(set_row->>'load_kg','')::numeric,rpe=nullif(set_row->>'rpe','')::numeric,completed=coalesce((set_row->>'completed')::boolean,false)
      where exercise_performance_id=performance_id and set_number=(set_row->>'number')::smallint;
      if not found then raise exception 'unknown set number' using errcode='22023'; end if;
    end loop;
  end loop;
  update public.workout_sessions set client_revision=sync_workout_draft.client_revision,notes=coalesce(draft->>'notes',notes),updated_at=now() where id=session.id;
  return jsonb_build_object('session_id',session.id,'client_revision',client_revision,'replayed',false);
end $$;

create function public.complete_workout(session_id uuid, client_revision integer, duration_seconds integer, session_energy smallint, session_effort numeric, notes text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare session public.workout_sessions%rowtype; completed_sets integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into session from public.workout_sessions where id=session_id and user_id=auth.uid() for update;
  if not found then raise exception 'session not found' using errcode='P0002'; end if;
  if session.state='completed' then return jsonb_build_object('session_id',session.id,'replayed',true); end if;
  if client_revision < session.client_revision then raise exception 'stale client revision' using errcode='40001'; end if;
  select count(*) into completed_sets from public.exercise_sets s join public.exercise_performances p on p.id=s.exercise_performance_id where p.workout_session_id=session.id and s.completed;
  if completed_sets=0 then raise exception 'complete at least one set' using errcode='22023'; end if;
  update public.workout_sessions set state='completed',completed_at=now(),duration_seconds=complete_workout.duration_seconds,session_energy=complete_workout.session_energy,session_effort=complete_workout.session_effort,notes=complete_workout.notes,client_revision=greatest(workout_sessions.client_revision,complete_workout.client_revision),updated_at=now() where id=session.id;
  update public.exercise_performances p set status=case when exists(select 1 from public.exercise_sets s where s.exercise_performance_id=p.id and s.completed) then 'performed' else 'skipped' end where p.workout_session_id=session.id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata) values(auth.uid(),'workout.completed','workout_session',session.id,'succeeded',jsonb_build_object('completed_sets',completed_sets));
  return jsonb_build_object('session_id',session.id,'completed_sets',completed_sets,'replayed',false);
end $$;

create function public.save_daily_check_in(local_date date, timezone text, idempotency_key uuid, payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; next_revision integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select id into result_id from public.daily_check_ins c where c.user_id=auth.uid() and c.idempotency_key=save_daily_check_in.idempotency_key;
  if result_id is not null then return result_id; end if;
  if not (payload ?& array['sleep_quality','energy','soreness','hunger','mood','available_to_train']) then raise exception 'incomplete check-in' using errcode='22023'; end if;
  select coalesce(max(revision),0)+1 into next_revision from public.daily_check_ins c where c.user_id=auth.uid() and c.local_date=save_daily_check_in.local_date;
  update public.daily_check_ins c set superseded_at=now() where c.user_id=auth.uid() and c.local_date=save_daily_check_in.local_date and superseded_at is null;
  insert into public.daily_check_ins(user_id,local_date,timezone,revision,idempotency_key,sleep_quality,energy,soreness,hunger,mood,pain_severity,available_to_train,note)
  values(auth.uid(),local_date,timezone,next_revision,idempotency_key,(payload->>'sleep_quality')::smallint,(payload->>'energy')::smallint,(payload->>'soreness')::smallint,(payload->>'hunger')::smallint,(payload->>'mood')::smallint,coalesce((payload->>'pain_severity')::smallint,0),(payload->>'available_to_train')::boolean,coalesce(payload->>'note','')) returning id into result_id;
  return result_id;
end $$;

alter table public.planned_workouts enable row level security; alter table public.planned_workouts force row level security;
alter table public.planned_exercises enable row level security; alter table public.planned_exercises force row level security;
alter table public.workout_sessions enable row level security; alter table public.workout_sessions force row level security;
alter table public.exercise_performances enable row level security; alter table public.exercise_performances force row level security;
alter table public.exercise_sets enable row level security; alter table public.exercise_sets force row level security;
alter table public.workout_amendments enable row level security; alter table public.workout_amendments force row level security;
alter table public.daily_check_ins enable row level security; alter table public.daily_check_ins force row level security;
create policy planned_workouts_own_read on public.planned_workouts for select to authenticated using(user_id=(select auth.uid()));
create policy planned_exercises_own_read on public.planned_exercises for select to authenticated using(user_id=(select auth.uid()));
create policy workout_sessions_own_read on public.workout_sessions for select to authenticated using(user_id=(select auth.uid()));
create policy exercise_performances_own_read on public.exercise_performances for select to authenticated using(user_id=(select auth.uid()));
create policy exercise_sets_own_read on public.exercise_sets for select to authenticated using(user_id=(select auth.uid()));
create policy workout_amendments_own_read on public.workout_amendments for select to authenticated using(user_id=(select auth.uid()));
create policy daily_check_ins_own_read on public.daily_check_ins for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.planned_workouts,public.planned_exercises,public.workout_sessions,public.exercise_performances,public.exercise_sets,public.workout_amendments,public.daily_check_ins from anon,authenticated;
grant select on public.planned_workouts,public.planned_exercises,public.workout_sessions,public.exercise_performances,public.exercise_sets,public.workout_amendments,public.daily_check_ins to authenticated;
revoke all on function public.start_workout(uuid,date,text,uuid),public.sync_workout_draft(uuid,integer,jsonb),public.complete_workout(uuid,integer,integer,smallint,numeric,text),public.save_daily_check_in(date,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.start_workout(uuid,date,text,uuid),public.sync_workout_draft(uuid,integer,jsonb),public.complete_workout(uuid,integer,integer,smallint,numeric,text),public.save_daily_check_in(date,text,uuid,jsonb) to authenticated;
