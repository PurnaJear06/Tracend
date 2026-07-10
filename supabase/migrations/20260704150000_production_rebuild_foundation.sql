create table public.coach_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  title text not null check (length(title) between 1 and 120),
  status text not null default 'active' check (status in ('active','archived')),
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,user_id)
);

create table public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  thread_id uuid not null,
  role text not null check (role in ('user','assistant')),
  content text not null check (length(content) between 1 and 12000),
  evidence jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence)='array'),
  missing_data text[] not null default '{}',
  safety_state text not null default 'allowed'
    check (safety_state in ('allowed','limited','refused','unavailable')),
  idempotency_key uuid,
  created_at timestamptz not null default now(),
  foreign key(thread_id,user_id) references public.coach_threads(id,user_id)
    on delete cascade,
  unique(id,user_id)
);

create unique index coach_messages_idempotency
on public.coach_messages(user_id,idempotency_key)
where idempotency_key is not null;
create index coach_threads_user_recent
on public.coach_threads(user_id,last_message_at desc);
create index coach_messages_thread_recent
on public.coach_messages(thread_id,created_at desc);

create table public.nutrition_schedule_versions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  status public.version_status not null,
  title text not null check (length(title) between 1 and 120),
  rationale text not null check (length(rationale) between 1 and 1000),
  approved_at timestamptz,
  effective_date date not null,
  created_at timestamptz not null default now(),
  unique(user_id,version_number),
  unique(id,user_id)
);

create unique index nutrition_schedule_one_active
on public.nutrition_schedule_versions(user_id)
where status='active';

create table public.nutrition_schedule_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  schedule_version_id uuid not null,
  item_order smallint not null check (item_order between 1 and 12),
  slot_key text not null check (slot_key in (
    'pre_workout','post_workout','lunch','snack','dinner','optional_curd'
  )),
  label text not null check (length(label) between 1 and 80),
  local_time time not null,
  window_minutes smallint not null default 60 check (window_minutes between 15 and 240),
  foods jsonb not null check (jsonb_typeof(foods)='array' and jsonb_array_length(foods)>0),
  optional boolean not null default false,
  reminder_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key(schedule_version_id,user_id)
    references public.nutrition_schedule_versions(id,user_id) on delete cascade,
  unique(schedule_version_id,item_order),
  unique(schedule_version_id,slot_key),
  unique(id,user_id)
);

alter table public.meals add column nutrition_schedule_item_id uuid;
alter table public.meals add constraint meals_schedule_item_owner_fk
  foreign key(nutrition_schedule_item_id,user_id)
  references public.nutrition_schedule_items(id,user_id);

alter table public.model_runs drop constraint if exists model_runs_purpose_check;
alter table public.model_runs add constraint model_runs_purpose_check
  check (purpose in ('daily_coaching','coach_chat'));
alter table public.model_runs drop constraint if exists model_runs_prompt_version_check;
alter table public.model_runs add constraint model_runs_prompt_version_check
  check (prompt_version in ('daily-v1','coach-chat-v1'));

create table public.ai_usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  purpose text not null check (purpose in ('meal_vision','progress_vision')),
  provider text not null check (provider='gemini'),
  model text not null check (model in ('gemini-3.5-flash','gemini-3.1-flash-lite')),
  input_units integer not null check (input_units between 0 and 1000000),
  output_units integer not null check (output_units between 0 and 100000),
  estimated_cost_usd numeric(10,6) not null check (estimated_cost_usd between 0 and 100),
  latency_ms integer not null check (latency_ms between 0 and 120000),
  created_at timestamptz not null default now()
);
create index ai_usage_events_user_created on public.ai_usage_events(user_id,created_at desc);

alter table public.coach_threads enable row level security;
alter table public.coach_threads force row level security;
alter table public.coach_messages enable row level security;
alter table public.coach_messages force row level security;
alter table public.nutrition_schedule_versions enable row level security;
alter table public.nutrition_schedule_versions force row level security;
alter table public.nutrition_schedule_items enable row level security;
alter table public.nutrition_schedule_items force row level security;
alter table public.ai_usage_events enable row level security;
alter table public.ai_usage_events force row level security;

create policy coach_threads_own_read on public.coach_threads
for select to authenticated using(user_id=(select auth.uid()));
create policy coach_messages_own_read on public.coach_messages
for select to authenticated using(user_id=(select auth.uid()));
create policy nutrition_schedule_versions_own_read
on public.nutrition_schedule_versions for select to authenticated
using(user_id=(select auth.uid()));
create policy nutrition_schedule_items_own_read
on public.nutrition_schedule_items for select to authenticated
using(user_id=(select auth.uid()));
create policy ai_usage_events_own_read on public.ai_usage_events
for select to authenticated using(user_id=(select auth.uid()));

revoke all on public.coach_threads,public.coach_messages,
  public.nutrition_schedule_versions,public.nutrition_schedule_items
  ,public.ai_usage_events
from anon,authenticated;
grant select on public.coach_threads,public.coach_messages,
  public.nutrition_schedule_versions,public.nutrition_schedule_items
  ,public.ai_usage_events
to authenticated;

create function public.create_coach_thread(thread_title text default 'New conversation')
returns uuid language plpgsql security definer set search_path='' as $$
declare thread_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  if length(trim(thread_title)) not between 1 and 120 then
    raise exception 'invalid title' using errcode='22023';
  end if;
  insert into public.coach_threads(user_id,title)
  values(auth.uid(),trim(thread_title)) returning id into thread_id;
  return thread_id;
end $$;

create function public.delete_coach_thread(target_thread_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare deleted_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  delete from public.coach_threads
  where id=target_thread_id and user_id=auth.uid() returning id into deleted_id;
  if deleted_id is null then
    raise exception 'thread not found' using errcode='P0002';
  end if;
  insert into public.audit_events(
    user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'coach.thread.deleted','coach_thread',deleted_id,
    'succeeded',jsonb_build_object('schema_version','1.0'));
  return true;
end $$;

create function public.get_my_training_hub(period_days integer default 28)
returns jsonb language sql security definer set search_path='' stable as $$
with active_version as (
  select v.id,v.plan_id,v.version_number,v.block_weeks,v.sessions_per_week,
    v.rationale,p.title
  from public.training_plan_versions v
  join public.training_plans p on p.id=v.plan_id and p.user_id=v.user_id
  where v.user_id=auth.uid() and v.status='active'
  limit 1
), workouts as (
  select w.*,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'order',e.exercise_order,'name',e.display_name_snapshot,
      'set_count',e.set_count,'rep_min',e.rep_min,'rep_max',e.rep_max,
      'target_rpe',e.target_rpe,'rest_seconds',e.rest_seconds,'notes',e.notes
    ) order by e.exercise_order)
    from public.planned_exercises e
    where e.planned_workout_id=w.id and e.user_id=auth.uid()),'[]'::jsonb) exercises
  from public.planned_workouts w join active_version v on v.id=w.plan_version_id
  where w.user_id=auth.uid()
), completed as (
  select s.id,s.planned_workout_id,s.local_date,s.duration_seconds,
    s.session_energy,s.session_effort,s.notes,s.completed_at,w.name
  from public.workout_sessions s
  join workouts w on w.id=s.planned_workout_id
  where s.user_id=auth.uid() and s.state='completed'
    and s.local_date >= current_date-greatest(7,least(period_days,365))+1
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
    and s.local_date >= current_date-greatest(7,least(period_days,365))+1
  group by e.display_name_snapshot
)
select jsonb_build_object(
  'schema_version','1.0','period_days',greatest(7,least(period_days,365)),
  'active_plan',(select jsonb_build_object(
    'id',id,'plan_id',plan_id,'title',title,'version_number',version_number,
    'block_weeks',block_weeks,'sessions_per_week',sessions_per_week,
    'rationale',rationale) from active_version),
  'workouts',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'order',workout_order,'weekday',preferred_weekday,'name',name,
    'objective',objective,'estimated_minutes',estimated_minutes,
    'warm_up',warm_up_guidance,'cooldown_cardio',cool_down_guidance,
    'exercises',exercises) order by workout_order) from workouts),'[]'::jsonb),
  'today_workout',(select jsonb_build_object(
    'id',id,'weekday',preferred_weekday,'name',name,'objective',objective,
    'estimated_minutes',estimated_minutes,'warm_up',warm_up_guidance,
    'cooldown_cardio',cool_down_guidance,'exercises',exercises)
    from workouts where preferred_weekday=extract(isodow from current_date)::integer limit 1),
  'recent_sessions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'workout_id',planned_workout_id,'name',name,'local_date',local_date,
    'duration_seconds',duration_seconds,'effort',session_effort,'energy',session_energy
  ) order by local_date desc) from (select * from completed order by local_date desc limit 12) r),'[]'::jsonb),
  'adherence',jsonb_build_object(
    'completed_sessions',(select count(*) from completed),
    'planned_sessions',coalesce((select sessions_per_week from active_version),0)
      * greatest(1,ceil(greatest(7,least(period_days,365))/7.0)::integer)),
  'progression',coalesce((select jsonb_agg(jsonb_build_object(
    'exercise',exercise,'sessions',sessions,'best_load_kg',best_load_kg,
    'best_repetitions',best_repetitions,'latest_date',latest_date
  ) order by latest_date desc) from progression),'[]'::jsonb)
);
$$;

create function public.get_my_nutrition_schedule(target_date date default current_date)
returns jsonb language sql security definer set search_path='' stable as $$
with active as (
  select * from public.nutrition_schedule_versions
  where user_id=auth.uid() and status='active' limit 1
), logged as (
  select nutrition_schedule_item_id,min(created_at) logged_at
  from public.meals where user_id=auth.uid() and local_date=target_date
    and status='confirmed' and nutrition_schedule_item_id is not null
  group by nutrition_schedule_item_id
)
select jsonb_build_object(
  'schema_version','1.0','local_date',target_date,
  'version',(select jsonb_build_object('id',id,'version_number',version_number,
    'title',title,'effective_date',effective_date) from active),
  'items',coalesce((select jsonb_agg(jsonb_build_object(
    'id',i.id,'order',i.item_order,'slot_key',i.slot_key,'label',i.label,
    'local_time',to_char(i.local_time,'HH24:MI'),'window_minutes',i.window_minutes,
    'foods',i.foods,'optional',i.optional,'reminder_enabled',i.reminder_enabled,
    'status',case when l.logged_at is not null then 'logged'
      when current_date<>target_date then case when target_date<current_date then 'skipped' else 'upcoming' end
      when localtime < i.local_time-(i.window_minutes||' minutes')::interval then 'upcoming'
      when localtime <= i.local_time+(i.window_minutes||' minutes')::interval then 'due'
      when i.optional then 'optional' else 'skipped' end
  ) order by i.item_order)
  from public.nutrition_schedule_items i
  join active a on a.id=i.schedule_version_id
  left join logged l on l.nutrition_schedule_item_id=i.id),'[]'::jsonb)
);
$$;

create function public.activate_my_nutrition_schedule(
  schedule_title text, schedule_rationale text, effective_on date,
  schedule_items jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare next_version integer; version_id uuid; item jsonb; item_count integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if length(schedule_title) not between 1 and 120
    or length(schedule_rationale) not between 1 and 1000
    or jsonb_typeof(schedule_items)<>'array'
    or jsonb_array_length(schedule_items) not between 1 and 12
  then raise exception 'invalid schedule' using errcode='22023'; end if;
  select coalesce(max(version_number),0)+1 into next_version
  from public.nutrition_schedule_versions where user_id=auth.uid();
  update public.nutrition_schedule_versions set status='superseded'
  where user_id=auth.uid() and status='active';
  insert into public.nutrition_schedule_versions(
    user_id,version_number,status,title,rationale,approved_at,effective_date)
  values(auth.uid(),next_version,'active',schedule_title,schedule_rationale,now(),effective_on)
  returning id into version_id;
  for item in select value from jsonb_array_elements(schedule_items) loop
    item_count:=item_count+1;
    insert into public.nutrition_schedule_items(
      user_id,schedule_version_id,item_order,slot_key,label,local_time,
      window_minutes,foods,optional,reminder_enabled)
    values(auth.uid(),version_id,item_count,item->>'slot_key',item->>'label',
      (item->>'local_time')::time,coalesce((item->>'window_minutes')::smallint,60),
      item->'foods',coalesce((item->>'optional')::boolean,false),
      coalesce((item->>'reminder_enabled')::boolean,true));
  end loop;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'nutrition.schedule.activated','nutrition_schedule_version',version_id,
    'succeeded',jsonb_build_object('version_number',next_version,'item_count',item_count));
  return version_id;
end $$;

create function public.get_my_daily_brief(target_date date default current_date)
returns jsonb language sql security definer set search_path='' stable as $$
with training as (select public.get_my_training_hub(28) value),
nutrition as (select public.get_my_nutrition_schedule(target_date) value),
next_meal as (
  select item from nutrition,jsonb_array_elements(value->'items') item
  where item->>'status' in ('due','upcoming','optional')
  order by (item->>'order')::integer limit 1
)
select jsonb_build_object(
  'schema_version','1.0','local_date',target_date,
  'today_workout',(select value->'today_workout' from training),
  'next_meal',(select item from next_meal),
  'check_in',(select to_jsonb(c)-'user_id'-'note'-'idempotency_key'
    from public.daily_check_ins c where c.user_id=auth.uid()
      and c.local_date=target_date and c.superseded_at is null limit 1),
  'health',(select jsonb_build_object('last_synced_at',last_synced_at,
    'present_types',present_types,'completeness',completeness)
    from public.daily_health_summaries where user_id=auth.uid()
      and local_date=target_date order by last_synced_at desc limit 1),
  'nutrition',public.get_my_daily_nutrition(target_date),
  'latest_decision',(select jsonb_build_object('id',id,'final_decision',head_coach->>'final_decision',
    'reason',head_coach->>'reason','confidence',confidence,'created_at',created_at,
    'evidence',evidence,'missing_data',missing_data)
    from public.coach_decisions where user_id=auth.uid()
    order by created_at desc limit 1)
);
$$;

create function public.save_scheduled_manual_meal(
  meal_date date,meal_timezone text,meal_kind text,
  request_idempotency_key uuid,item_payload jsonb,schedule_item_id uuid,
  meal_note text default ''
) returns uuid language plpgsql security definer set search_path='' as $$
declare meal_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if not exists(select 1 from public.nutrition_schedule_items i
    join public.nutrition_schedule_versions v on v.id=i.schedule_version_id and v.user_id=i.user_id
    where i.id=schedule_item_id and i.user_id=auth.uid() and v.status='active')
  then raise exception 'schedule item not found' using errcode='P0002'; end if;
  meal_id:=public.save_manual_meal(meal_date,meal_timezone,meal_kind,
    request_idempotency_key,item_payload,meal_note);
  update public.meals set nutrition_schedule_item_id=schedule_item_id
  where id=meal_id and user_id=auth.uid();
  return meal_id;
end $$;

create function public.get_my_ai_budget_state()
returns jsonb language sql security definer set search_path='' stable as $$
with usage as (
  select coalesce(sum(estimated_cost_usd),0) monthly_cost,
    count(*) filter(where purpose in ('daily_coaching','coach_chat')
      and created_at>=date_trunc('day',now())) today_requests
  from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=auth.uid() and created_at>=date_trunc('month',now())
    union all
    select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=auth.uid() and created_at>=date_trunc('month',now())
  ) all_usage
)
select jsonb_build_object(
  'period','current_month','estimated_cost_usd',monthly_cost,
  'warning_threshold_usd',3,'hard_stop_usd',5,
  'warning',monthly_cost>=3,'blocked',monthly_cost>=5,
  'today_requests',today_requests,'daily_limit',30)
from usage;
$$;

create function public.record_ai_usage_event(
  target_user_id uuid,run_purpose text,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,
  run_estimated_cost_usd numeric,run_latency_ms integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare event_id uuid;
begin
  if run_purpose not in ('meal_vision','progress_vision')
    or run_provider<>'gemini'
    or run_model not in ('gemini-3.5-flash','gemini-3.1-flash-lite')
  then raise exception 'invalid usage event' using errcode='22023'; end if;
  insert into public.ai_usage_events(
    user_id,purpose,provider,model,input_units,output_units,
    estimated_cost_usd,latency_ms)
  values(target_user_id,run_purpose,run_provider,run_model,run_input_units,
    run_output_units,run_estimated_cost_usd,run_latency_ms)
  returning id into event_id;
  return event_id;
end $$;

create function public.create_meal_photo_draft(
  meal_date date,meal_timezone text,meal_kind text,request_idempotency_key uuid,
  object_path text,object_content_type text,object_byte_size integer,object_checksum text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare media_id uuid; meal_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if meal_kind not in ('breakfast','lunch','dinner','snack')
    or length(meal_timezone) not between 1 and 64
    or object_path not like auth.uid()::text||'/meal/%'
    or object_content_type not in ('image/jpeg','image/png','image/heic')
    or object_byte_size not between 1 and 4194304
    or object_checksum !~ '^[0-9a-f]{64}$'
  then raise exception 'invalid meal photo draft' using errcode='22023'; end if;
  select id into meal_id from public.meals
  where user_id=auth.uid() and idempotency_key=request_idempotency_key;
  if meal_id is not null then
    return jsonb_build_object('meal_id',meal_id,'replayed',true);
  end if;
  insert into public.media_objects(
    user_id,purpose,object_key,content_type,byte_size,checksum,retention_deadline)
  values(auth.uid(),'meal_analysis',object_path,object_content_type,
    object_byte_size,object_checksum,now()+interval '7 days')
  returning id into media_id;
  insert into public.meals(
    user_id,local_date,timezone,meal_type,source,status,idempotency_key,media_object_id)
  values(auth.uid(),meal_date,meal_timezone,meal_kind,'photo_analysis','draft',
    request_idempotency_key,media_id) returning id into meal_id;
  return jsonb_build_object('meal_id',meal_id,'media_id',media_id,'object_path',object_path,'replayed',false);
end $$;

create function public.persist_meal_photo_candidates(
  target_user_id uuid,target_meal_id uuid,candidates jsonb,
  run_provider text,run_model text
) returns integer language plpgsql security definer set search_path='' as $$
declare meal public.meals%rowtype; item jsonb; item_count integer:=0;
begin
  select * into meal from public.meals where id=target_meal_id
    and user_id=target_user_id for update;
  if not found then raise exception 'meal not found' using errcode='P0002'; end if;
  if meal.source<>'photo_analysis' or meal.status<>'draft'
    or jsonb_typeof(candidates)<>'array'
    or jsonb_array_length(candidates) not between 1 and 20
    or run_provider<>'gemini' or run_model not in ('gemini-3.5-flash','gemini-3.1-flash-lite')
  then raise exception 'invalid meal analysis' using errcode='22023'; end if;
  delete from public.meal_analysis_candidates where meal_id=target_meal_id;
  for item in select value from jsonb_array_elements(candidates) loop
    item_count:=item_count+1;
    insert into public.meal_analysis_candidates(
      user_id,meal_id,candidate_order,food_label,serving_label,calories,
      protein_g,carbohydrate_g,fat_g,confidence)
    values(target_user_id,target_meal_id,item_count,item->>'name',item->>'serving_label',
      (item->>'calories')::numeric,(item->>'protein_g')::numeric,
      (item->>'carbohydrate_g')::numeric,(item->>'fat_g')::numeric,
      item->>'confidence');
  end loop;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(target_user_id,'meal.photo.candidates_created','meal',target_meal_id,
    'succeeded',jsonb_build_object('candidate_count',item_count,
      'provider',run_provider,'model',run_model));
  return item_count;
end $$;

create function public.confirm_analyzed_meal(
  target_meal_id uuid,candidate_payload jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare meal public.meals%rowtype; candidate jsonb; candidate_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into meal from public.meals
  where id=target_meal_id and user_id=auth.uid() for update;
  if not found then raise exception 'meal not found' using errcode='P0002'; end if;
  if meal.status='confirmed' then return meal.id; end if;
  if meal.source not in ('fixture_analysis','photo_analysis')
    or jsonb_typeof(candidate_payload)<>'array'
    or jsonb_array_length(candidate_payload) not between 1 and 30
  then raise exception 'invalid confirmation' using errcode='22023'; end if;
  for candidate in select value from jsonb_array_elements(candidate_payload) loop
    begin candidate_id:=(candidate->>'id')::uuid;
    exception when others then raise exception 'invalid candidate' using errcode='22023'; end;
    if length(coalesce(candidate->>'name','')) not between 1 and 120
      or length(coalesce(candidate->>'serving_label','')) not between 1 and 80
    then raise exception 'invalid candidate' using errcode='22023'; end if;
    update public.meal_analysis_candidates set
      food_label=candidate->>'name',serving_label=candidate->>'serving_label',
      calories=(candidate->>'calories')::numeric,
      protein_g=(candidate->>'protein_g')::numeric,
      carbohydrate_g=(candidate->>'carbohydrate_g')::numeric,
      fat_g=(candidate->>'fat_g')::numeric,selected=true
    where id=candidate_id and meal_id=meal.id and user_id=auth.uid();
    if not found then raise exception 'candidate not found' using errcode='P0002'; end if;
  end loop;
  update public.meal_analysis_candidates set selected=false
  where meal_id=meal.id and user_id=auth.uid() and id not in (
    select (value->>'id')::uuid from jsonb_array_elements(candidate_payload));
  insert into public.meal_items(
    user_id,meal_id,name_snapshot,serving_label,calories,protein_g,
    carbohydrate_g,fat_g,confirmed_at)
  select user_id,meal_id,food_label,serving_label,calories,protein_g,
    carbohydrate_g,fat_g,now() from public.meal_analysis_candidates
  where meal_id=meal.id and selected;
  update public.meals set status='confirmed',confirmed_at=now() where id=meal.id;
  update public.media_objects set retention_deadline=least(retention_deadline,now()+interval '30 days')
  where id=meal.media_object_id and user_id=auth.uid() and not retention_exempt;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'meal.analysis.confirmed','meal',meal.id,'succeeded',
    jsonb_build_object('item_count',jsonb_array_length(candidate_payload),
      'schema_version',3,'source',meal.source));
  return meal.id;
end $$;

create function public.prepare_coach_chat(
  target_user_id uuid,target_thread_id uuid,question text,
  coaching_timezone text,request_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare monthly_cost numeric; today_requests integer; existing_message uuid;
  prepared jsonb; schedule jsonb; context_payload jsonb;
begin
  if target_user_id is null or not exists(select 1 from public.coach_threads
    where id=target_thread_id and user_id=target_user_id and status='active')
  then raise exception 'thread not found' using errcode='P0002'; end if;
  if length(trim(question)) not between 1 and 2000
    or length(coaching_timezone) not between 1 and 64
  then raise exception 'invalid chat request' using errcode='22023'; end if;
  select id into existing_message from public.coach_messages
  where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if existing_message is not null then
    return jsonb_build_object('replayed',true,'user_message_id',existing_message);
  end if;
  select coalesce(sum(estimated_cost_usd),0),
    count(*) filter(where purpose in ('daily_coaching','coach_chat')
      and created_at>=date_trunc('day',now()))
  into monthly_cost,today_requests from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=target_user_id and created_at>=date_trunc('month',now())
    union all
    select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=target_user_id and created_at>=date_trunc('month',now())
  ) all_usage;
  if monthly_cost>=5 then
    raise exception 'monthly cost limit reached' using errcode='P0001';
  end if;
  if today_requests>=30 then
    raise exception 'daily rate limit reached' using errcode='P0001';
  end if;
  select jsonb_build_object(
    'feature_snapshot_id',s.id,'policy_evaluation_id',p.id,
    'policy_outcome',p.outcome,
    'permitted_evidence',case p.outcome
      when 'escalate' then jsonb_build_array('APPROVED_PLAN_ACTIVE','CHECK_IN_SAFETY_ESCALATION','HEALTH_CONTEXT_AVAILABLE')
      when 'request_data' then jsonb_build_array('APPROVED_PLAN_ACTIVE','HEALTH_CONTEXT_AVAILABLE')
      else jsonb_build_array('APPROVED_PLAN_ACTIVE','RECOVERY_WITHIN_BASELINE','CHECK_IN_RECOVERY_MIXED','HEALTH_CONTEXT_AVAILABLE') end,
    'missing_data',to_jsonb(s.missing_data)) into prepared
  from public.feature_snapshots s join public.policy_evaluations p
    on p.feature_snapshot_id=s.id and p.user_id=s.user_id
  where s.user_id=target_user_id and s.trigger_kind='daily'
    and s.created_at>=date_trunc('day',now())
  order by s.created_at desc limit 1;
  if prepared is null then
    prepared:=public.prepare_daily_coaching(
      target_user_id,current_date,coaching_timezone,gen_random_uuid());
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'slot_key',i.slot_key,'label',i.label,'local_time',to_char(i.local_time,'HH24:MI'),
    'foods',i.foods,'optional',i.optional) order by i.item_order),'[]'::jsonb)
  into schedule from public.nutrition_schedule_items i
  join public.nutrition_schedule_versions v on v.id=i.schedule_version_id
    and v.user_id=i.user_id
  where i.user_id=target_user_id and v.status='active';
  context_payload:=jsonb_build_object(
    'active_plan',(select jsonb_build_object('title',p.title,
      'version_number',v.version_number,'sessions_per_week',v.sessions_per_week,
      'rationale',v.rationale) from public.training_plan_versions v
      join public.training_plans p on p.id=v.plan_id and p.user_id=v.user_id
      where v.user_id=target_user_id and v.status='active' limit 1),
    'nutrition_targets',(select jsonb_build_object('calories',calories,
      'protein_g',protein_g,'carbohydrate_g',carbohydrate_g,'fat_g',fat_g)
      from public.nutrition_target_sets where user_id=target_user_id
      and status='active' limit 1),
    'nutrition_schedule',schedule,
    'latest_check_in',(select jsonb_build_object('local_date',local_date,
      'sleep_quality',sleep_quality,'energy',energy,'soreness',soreness,
      'hunger',hunger,'mood',mood,'pain_severity',pain_severity,
      'available_to_train',available_to_train)
      from public.daily_check_ins where user_id=target_user_id
      and superseded_at is null order by local_date desc limit 1),
    'recent_execution',(select coalesce(jsonb_agg(row_data),'[]'::jsonb) from (
      select jsonb_build_object('local_date',s.local_date,'workout',w.name,
        'duration_seconds',s.duration_seconds,'effort',s.session_effort) row_data
      from public.workout_sessions s join public.planned_workouts w
        on w.id=s.planned_workout_id and w.user_id=s.user_id
      where s.user_id=target_user_id and s.state='completed'
      order by s.local_date desc limit 8) execution),
    'latest_decision',(select jsonb_build_object(
      'final_decision',head_coach->>'final_decision','reason',head_coach->>'reason',
      'evidence',evidence,'missing_data',missing_data,'confidence',confidence)
      from public.coach_decisions where user_id=target_user_id
      order by created_at desc limit 1),
    'recent_messages',(select coalesce(jsonb_agg(message order by created_at),'[]'::jsonb)
      from (select jsonb_build_object('role',role,'content',content) message,created_at
        from public.coach_messages where user_id=target_user_id
        and thread_id=target_thread_id order by created_at desc limit 20) recent),
    'permitted_evidence',prepared->'permitted_evidence',
    'missing_data',prepared->'missing_data');
  if length(context_payload::text)>16000 then
    raise exception 'chat context too large' using errcode='22023';
  end if;
  return jsonb_build_object('replayed',false,
    'feature_snapshot_id',prepared->>'feature_snapshot_id',
    'policy_evaluation_id',prepared->>'policy_evaluation_id',
    'policy_outcome',prepared->>'policy_outcome','context',context_payload,
    'budget_warning',monthly_cost>=3);
end $$;

create function public.persist_coach_chat_result(
  target_user_id uuid,target_thread_id uuid,question text,
  request_idempotency_key uuid,snapshot_id uuid,policy_id uuid,
  answer_payload jsonb,run_latency_ms integer,run_provider text,run_model text,
  run_input_units integer,run_output_units integer,run_estimated_cost_usd numeric
) returns jsonb language plpgsql security definer set search_path='' as $$
declare user_message_id uuid; assistant_message_id uuid; run_id uuid;
begin
  if not exists(select 1 from public.coach_threads where id=target_thread_id
    and user_id=target_user_id and status='active')
  then raise exception 'thread not found' using errcode='P0002'; end if;
  if not exists(select 1 from public.policy_evaluations where id=policy_id
    and user_id=target_user_id and feature_snapshot_id=snapshot_id)
  then raise exception 'policy not found' using errcode='P0002'; end if;
  if jsonb_typeof(answer_payload)<>'object'
    or length(answer_payload->>'answer') not between 1 and 12000
    or jsonb_typeof(answer_payload->'evidence')<>'array'
    or jsonb_typeof(answer_payload->'missing_data')<>'array'
    or answer_payload->>'safety_state' not in ('allowed','limited','refused','unavailable')
    or run_provider not in ('mock','gemini') or length(run_model) not between 1 and 120
    or run_input_units not between 0 and 1000000
    or run_output_units not between 0 and 100000
    or run_estimated_cost_usd not between 0 and 100
  then raise exception 'invalid chat result' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(answer_payload->'evidence') e
    where not (e ? 'code' and e ? 'label' and e ? 'source'))
  then raise exception 'invalid evidence' using errcode='22023'; end if;
  insert into public.coach_messages(
    user_id,thread_id,role,content,idempotency_key)
  values(target_user_id,target_thread_id,'user',trim(question),request_idempotency_key)
  on conflict(user_id,idempotency_key) where idempotency_key is not null
  do update set idempotency_key=excluded.idempotency_key returning id into user_message_id;
  select id into run_id from public.model_runs
  where user_id=target_user_id and idempotency_key=request_idempotency_key;
  if run_id is null then
    insert into public.model_runs(
      user_id,feature_snapshot_id,policy_evaluation_id,idempotency_key,purpose,
      provider,model,prompt_version,schema_version,status,validation_status,
      input_units,output_units,estimated_cost_usd,latency_ms)
    values(target_user_id,snapshot_id,policy_id,request_idempotency_key,'coach_chat',
      run_provider,run_model,'coach-chat-v1','1.0','succeeded','passed',
      run_input_units,run_output_units,run_estimated_cost_usd,run_latency_ms)
    returning id into run_id;
    insert into public.coach_messages(
      user_id,thread_id,role,content,evidence,missing_data,safety_state)
    values(target_user_id,target_thread_id,'assistant',answer_payload->>'answer',
      answer_payload->'evidence',array(select jsonb_array_elements_text(
        answer_payload->'missing_data')),answer_payload->>'safety_state')
    returning id into assistant_message_id;
    update public.coach_threads set last_message_at=now(),updated_at=now(),
      title=case when title='New conversation' then left(trim(question),80) else title end
    where id=target_thread_id and user_id=target_user_id;
  else
    select id into assistant_message_id from public.coach_messages
    where user_id=target_user_id and thread_id=target_thread_id and role='assistant'
      and created_at>=(select created_at from public.model_runs where id=run_id)
    order by created_at limit 1;
  end if;
  return jsonb_build_object('user_message_id',user_message_id,
    'assistant_message_id',assistant_message_id,'model_run_id',run_id);
end $$;

do $$
declare account record; version_id uuid;
begin
  for account in select id from public.user_accounts loop
    if not exists(select 1 from public.nutrition_schedule_versions
      where user_id=account.id and status='active') then
      insert into public.nutrition_schedule_versions(
        user_id,version_number,status,title,rationale,approved_at,effective_date)
      values(account.id,1,'active','Owner confirmed meal schedule',
        'Initial schedule from the confirmed nutrition plan.',now(),current_date)
      returning id into version_id;
      insert into public.nutrition_schedule_items(
        user_id,schedule_version_id,item_order,slot_key,label,local_time,
        window_minutes,foods,optional,reminder_enabled) values
      (account.id,version_id,1,'pre_workout','Pre-workout','07:45',45,
        '[{"name":"Pre-workout meal","quantity":"Use confirmed plan quantity"}]',false,true),
      (account.id,version_id,2,'post_workout','Post-workout','10:00',60,
        '[{"name":"Post-workout meal","quantity":"Use confirmed plan quantity"}]',false,true),
      (account.id,version_id,3,'lunch','Lunch','12:30',60,
        '[{"name":"Lunch","quantity":"Use confirmed plan quantity"}]',false,true),
      (account.id,version_id,4,'snack','Snack','16:30',60,
        '[{"name":"Snack","quantity":"Use confirmed plan quantity"}]',false,true),
      (account.id,version_id,5,'dinner','Dinner','20:00',75,
        '[{"name":"Dinner","quantity":"Use confirmed plan quantity"}]',false,true),
      (account.id,version_id,6,'optional_curd','Optional curd','22:00',60,
        '[{"name":"Curd","quantity":"Optional plan serving"}]',true,false);
    end if;
  end loop;
end $$;

revoke all on function public.create_coach_thread(text),
  public.delete_coach_thread(uuid),public.get_my_training_hub(integer),
  public.get_my_nutrition_schedule(date),
  public.activate_my_nutrition_schedule(text,text,date,jsonb),
  public.get_my_daily_brief(date),public.get_my_ai_budget_state(),
  public.save_scheduled_manual_meal(date,text,text,uuid,jsonb,uuid,text),
  public.create_meal_photo_draft(date,text,text,uuid,text,text,integer,text),
  public.persist_meal_photo_candidates(uuid,uuid,jsonb,text,text),
  public.confirm_analyzed_meal(uuid,jsonb),
  public.record_ai_usage_event(uuid,text,text,text,integer,integer,numeric,integer),
  public.prepare_coach_chat(uuid,uuid,text,text,uuid),
  public.persist_coach_chat_result(uuid,uuid,text,uuid,uuid,uuid,jsonb,
    integer,text,text,integer,integer,numeric)
from public,anon,authenticated;
grant execute on function public.create_coach_thread(text),
  public.delete_coach_thread(uuid),public.get_my_training_hub(integer),
  public.get_my_nutrition_schedule(date),
  public.activate_my_nutrition_schedule(text,text,date,jsonb),
  public.get_my_daily_brief(date),public.get_my_ai_budget_state(),
  public.save_scheduled_manual_meal(date,text,text,uuid,jsonb,uuid,text)
to authenticated;
grant execute on function public.prepare_coach_chat(uuid,uuid,text,text,uuid),
  public.persist_coach_chat_result(uuid,uuid,text,uuid,uuid,uuid,jsonb,
    integer,text,text,integer,integer,numeric)
to service_role;
grant execute on function public.create_meal_photo_draft(
  date,text,text,uuid,text,text,integer,text) to authenticated;
grant execute on function public.confirm_analyzed_meal(uuid,jsonb) to authenticated;
grant execute on function public.persist_meal_photo_candidates(
  uuid,uuid,jsonb,text,text) to service_role;
grant execute on function public.record_ai_usage_event(
  uuid,text,text,text,integer,integer,numeric,integer) to service_role;
