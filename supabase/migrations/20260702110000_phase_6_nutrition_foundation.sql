create type public.meal_status as enum ('draft', 'confirmed', 'discarded');
create type public.meal_source as enum ('manual', 'fixture_analysis');

create table public.user_foods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  name text not null check (length(name) between 1 and 120),
  serving_label text not null check (length(serving_label) between 1 and 80),
  calories numeric(8,2) not null check (calories between 0 and 5000),
  protein_g numeric(7,2) not null check (protein_g between 0 and 500),
  carbohydrate_g numeric(7,2) not null check (carbohydrate_g between 0 and 1000),
  fat_g numeric(7,2) not null check (fat_g between 0 and 500),
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  unique(id,user_id)
);

create table public.media_objects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  purpose text not null check (purpose='meal_analysis'),
  object_key text not null check (length(object_key) between 10 and 300),
  content_type text not null check (content_type in ('image/jpeg','image/png','image/heic')),
  byte_size integer not null check (byte_size between 1 and 10485760),
  checksum text not null check (checksum ~ '^[0-9a-f]{64}$'),
  lifecycle_status text not null default 'active' check (lifecycle_status in ('active','deleted')),
  retention_deadline timestamptz not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique(user_id,object_key), unique(id,user_id)
);

create table public.meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  local_date date not null,
  timezone text not null check (length(timezone) between 1 and 64),
  meal_type text not null check (meal_type in ('breakfast','lunch','dinner','snack')),
  source public.meal_source not null,
  status public.meal_status not null,
  idempotency_key uuid not null,
  media_object_id uuid,
  note text not null default '' check (length(note)<=1000),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key(media_object_id,user_id) references public.media_objects(id,user_id),
  unique(user_id,idempotency_key), unique(id,user_id),
  check((status='confirmed')=(confirmed_at is not null))
);

create table public.meal_analysis_candidates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  meal_id uuid not null,
  candidate_order smallint not null check(candidate_order between 1 and 30),
  food_label text not null check(length(food_label) between 1 and 120),
  serving_label text not null check(length(serving_label) between 1 and 80),
  calories numeric(8,2) not null check(calories between 0 and 5000),
  protein_g numeric(7,2) not null check(protein_g between 0 and 500),
  carbohydrate_g numeric(7,2) not null check(carbohydrate_g between 0 and 1000),
  fat_g numeric(7,2) not null check(fat_g between 0 and 500),
  confidence text not null check(confidence in ('low','medium','high')),
  selected boolean not null default true,
  foreign key(meal_id,user_id) references public.meals(id,user_id) on delete cascade,
  unique(meal_id,candidate_order), unique(id,user_id)
);

create table public.meal_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  meal_id uuid not null,
  user_food_id uuid,
  name_snapshot text not null check(length(name_snapshot) between 1 and 120),
  serving_label text not null check(length(serving_label) between 1 and 80),
  calories numeric(8,2) not null check(calories between 0 and 5000),
  protein_g numeric(7,2) not null check(protein_g between 0 and 500),
  carbohydrate_g numeric(7,2) not null check(carbohydrate_g between 0 and 1000),
  fat_g numeric(7,2) not null check(fat_g between 0 and 500),
  confirmed_at timestamptz not null,
  foreign key(meal_id,user_id) references public.meals(id,user_id) on delete cascade,
  foreign key(user_food_id,user_id) references public.user_foods(id,user_id),
  unique(id,user_id)
);

create index meals_user_date on public.meals(user_id,local_date desc,created_at desc);
create index meal_items_meal on public.meal_items(meal_id);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('meal-images','meal-images',false,10485760,array['image/jpeg','image/png','image/heic'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
 allowed_mime_types=excluded.allowed_mime_types;

alter table public.user_foods enable row level security; alter table public.user_foods force row level security;
alter table public.media_objects enable row level security; alter table public.media_objects force row level security;
alter table public.meals enable row level security; alter table public.meals force row level security;
alter table public.meal_analysis_candidates enable row level security; alter table public.meal_analysis_candidates force row level security;
alter table public.meal_items enable row level security; alter table public.meal_items force row level security;
create policy user_foods_own_read on public.user_foods for select to authenticated using(user_id=(select auth.uid()));
create policy media_objects_own_read on public.media_objects for select to authenticated using(user_id=(select auth.uid()));
create policy meals_own_read on public.meals for select to authenticated using(user_id=(select auth.uid()));
create policy meal_candidates_own_read on public.meal_analysis_candidates for select to authenticated using(user_id=(select auth.uid()));
create policy meal_items_own_read on public.meal_items for select to authenticated using(user_id=(select auth.uid()));
create policy meal_images_insert_own on storage.objects for insert to authenticated with check(
 bucket_id='meal-images' and (storage.foldername(name))[1]=(select auth.uid())::text and
 (storage.foldername(name))[2]='meal');
create policy meal_images_read_own on storage.objects for select to authenticated using(
 bucket_id='meal-images' and owner_id=(select auth.uid()::text));
create policy meal_images_delete_own on storage.objects for delete to authenticated using(
 bucket_id='meal-images' and owner_id=(select auth.uid()::text));

revoke all on public.user_foods,public.media_objects,public.meals,
 public.meal_analysis_candidates,public.meal_items from anon,authenticated;
grant select on public.user_foods,public.media_objects,public.meals,
 public.meal_analysis_candidates,public.meal_items to authenticated;

create function public.save_manual_meal(
  meal_date date, meal_timezone text, meal_kind text,
  request_idempotency_key uuid, item_payload jsonb, meal_note text default ''
) returns uuid language plpgsql security definer set search_path='' as $$
declare meal_id uuid; item jsonb; food_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select id into meal_id from public.meals where user_id=auth.uid() and idempotency_key=request_idempotency_key;
  if meal_id is not null then return meal_id; end if;
  if meal_kind not in ('breakfast','lunch','dinner','snack') or length(meal_timezone) not between 1 and 64
    or jsonb_typeof(item_payload)<>'array' or jsonb_array_length(item_payload) not between 1 and 20
  then raise exception 'invalid meal' using errcode='22023'; end if;
  insert into public.meals(user_id,local_date,timezone,meal_type,source,status,idempotency_key,note,confirmed_at)
   values(auth.uid(),meal_date,meal_timezone,meal_kind,'manual','confirmed',request_idempotency_key,coalesce(meal_note,''),now()) returning id into meal_id;
  for item in select value from jsonb_array_elements(item_payload) loop
    if length(coalesce(item->>'name','')) not between 1 and 120 or length(coalesce(item->>'serving_label','')) not between 1 and 80
    then raise exception 'invalid meal item' using errcode='22023'; end if;
    insert into public.user_foods(user_id,name,serving_label,calories,protein_g,carbohydrate_g,fat_g)
      values(auth.uid(),item->>'name',item->>'serving_label',(item->>'calories')::numeric,(item->>'protein_g')::numeric,(item->>'carbohydrate_g')::numeric,(item->>'fat_g')::numeric) returning id into food_id;
    insert into public.meal_items(user_id,meal_id,user_food_id,name_snapshot,serving_label,calories,protein_g,carbohydrate_g,fat_g,confirmed_at)
      values(auth.uid(),meal_id,food_id,item->>'name',item->>'serving_label',(item->>'calories')::numeric,(item->>'protein_g')::numeric,(item->>'carbohydrate_g')::numeric,(item->>'fat_g')::numeric,now());
  end loop;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
    values(auth.uid(),'meal.manual.confirmed','meal',meal_id,'succeeded',jsonb_build_object('item_count',jsonb_array_length(item_payload)));
  return meal_id;
end $$;

create function public.create_fixture_meal(
  meal_date date, meal_timezone text, meal_kind text, request_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare meal_id uuid;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 select id into meal_id from public.meals where user_id=auth.uid() and idempotency_key=request_idempotency_key;
 if meal_id is not null then return meal_id; end if;
 insert into public.meals(user_id,local_date,timezone,meal_type,source,status,idempotency_key)
 values(auth.uid(),meal_date,meal_timezone,meal_kind,'fixture_analysis','draft',request_idempotency_key) returning id into meal_id;
 insert into public.meal_analysis_candidates(user_id,meal_id,candidate_order,food_label,serving_label,calories,protein_g,carbohydrate_g,fat_g,confidence) values
 (auth.uid(),meal_id,1,'Rice bowl','1 bowl',520,24,72,14,'medium'),
 (auth.uid(),meal_id,2,'Greek yogurt','150 g',130,15,8,4,'high');
 return meal_id;
end $$;

create function public.confirm_fixture_meal(target_meal_id uuid, selected_candidate_ids uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare meal public.meals%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 select * into meal from public.meals where id=target_meal_id and user_id=auth.uid() for update;
 if not found then raise exception 'meal not found' using errcode='P0002'; end if;
 if meal.status='confirmed' then return meal.id; end if;
 if meal.source<>'fixture_analysis' or cardinality(selected_candidate_ids)=0 then raise exception 'invalid confirmation' using errcode='22023'; end if;
 if exists(select 1 from unnest(selected_candidate_ids) i where not exists(select 1 from public.meal_analysis_candidates c where c.id=i and c.meal_id=meal.id and c.user_id=auth.uid()))
 then raise exception 'candidate not found' using errcode='P0002'; end if;
 insert into public.meal_items(user_id,meal_id,name_snapshot,serving_label,calories,protein_g,carbohydrate_g,fat_g,confirmed_at)
 select user_id,meal_id,food_label,serving_label,calories,protein_g,carbohydrate_g,fat_g,now()
 from public.meal_analysis_candidates where meal_id=meal.id and id=any(selected_candidate_ids);
 update public.meals set status='confirmed',confirmed_at=now() where id=meal.id;
 insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
 values(auth.uid(),'meal.fixture.confirmed','meal',meal.id,'succeeded',jsonb_build_object('item_count',cardinality(selected_candidate_ids)));
 return meal.id;
end $$;

create function public.get_my_daily_nutrition(target_date date)
returns jsonb language sql security definer set search_path='' stable as $$
 select jsonb_build_object('local_date',target_date,'calories',coalesce(sum(i.calories),0),
  'protein_g',coalesce(sum(i.protein_g),0),'carbohydrate_g',coalesce(sum(i.carbohydrate_g),0),
  'fat_g',coalesce(sum(i.fat_g),0),'confirmed_meals',count(distinct m.id))
 from public.meals m join public.meal_items i on i.meal_id=m.id and i.user_id=m.user_id
 where m.user_id=auth.uid() and m.local_date=target_date and m.status='confirmed';
$$;

revoke all on function public.save_manual_meal(date,text,text,uuid,jsonb,text),
 public.create_fixture_meal(date,text,text,uuid),public.confirm_fixture_meal(uuid,uuid[]),
 public.get_my_daily_nutrition(date) from public,anon,authenticated;
grant execute on function public.save_manual_meal(date,text,text,uuid,jsonb,text),
 public.create_fixture_meal(date,text,text,uuid),public.confirm_fixture_meal(uuid,uuid[]),
 public.get_my_daily_nutrition(date) to authenticated;
