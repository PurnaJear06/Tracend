alter type public.consent_type add value if not exists 'progress_photo_storage';
alter type public.consent_type add value if not exists 'progress_photo_ai';

alter table public.media_objects drop constraint media_objects_purpose_check;
alter table public.media_objects add constraint media_objects_purpose_check
  check (purpose in ('meal_analysis','progress_front','progress_side','progress_back'));

create table public.body_measurements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  measured_on date not null,
  source text not null check (source in ('manual','healthkit')),
  weight_kg numeric(5,2) not null check (weight_kg between 25 and 350),
  waist_cm numeric(5,2) check (waist_cm between 30 and 250),
  chest_cm numeric(5,2) check (chest_cm between 30 and 250),
  hip_cm numeric(5,2) check (hip_cm between 30 and 250),
  arm_cm numeric(5,2) check (arm_cm between 10 and 100),
  thigh_cm numeric(5,2) check (thigh_cm between 20 and 150),
  protocol_version text not null default 'manual-v1' check (length(protocol_version) between 1 and 32),
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  amended_from_id uuid,
  foreign key(amended_from_id,user_id) references public.body_measurements(id,user_id),
  unique(id,user_id)
);

create table public.progress_photo_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  captured_on date not null,
  capture_protocol_version text not null check (capture_protocol_version='standard-v1'),
  timing_context text not null check (length(timing_context) between 1 and 120),
  processing_consent boolean not null default false,
  notes text not null default '' check (length(notes) <= 500),
  status text not null default 'draft' check (status in ('draft','complete')),
  created_at timestamptz not null default now(),
  unique(id,user_id)
);

create table public.progress_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  photo_set_id uuid not null,
  media_object_id uuid not null,
  pose text not null check (pose in ('front','side','back')),
  quality_status text not null default 'pending' check (quality_status in ('pending','accepted','retake')),
  created_at timestamptz not null default now(),
  foreign key(photo_set_id,user_id) references public.progress_photo_sets(id,user_id) on delete cascade,
  foreign key(media_object_id,user_id) references public.media_objects(id,user_id),
  unique(photo_set_id,pose), unique(id,user_id)
);

create table public.progress_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  review_week date not null,
  schema_version text not null check (schema_version='1.0'),
  summary jsonb not null check (jsonb_typeof(summary)='object'),
  acknowledged_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id,review_week), unique(id,user_id)
);

create index body_measurements_user_date on public.body_measurements(user_id,measured_on desc,created_at desc);
create index progress_photo_sets_user_date on public.progress_photo_sets(user_id,captured_on desc);
create index progress_reviews_user_week on public.progress_reviews(user_id,review_week desc);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('progress-photos','progress-photos',false,10485760,array['image/jpeg','image/png','image/heic'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
 allowed_mime_types=excluded.allowed_mime_types;

alter table public.body_measurements enable row level security; alter table public.body_measurements force row level security;
alter table public.progress_photo_sets enable row level security; alter table public.progress_photo_sets force row level security;
alter table public.progress_photos enable row level security; alter table public.progress_photos force row level security;
alter table public.progress_reviews enable row level security; alter table public.progress_reviews force row level security;

create policy body_measurements_own_read on public.body_measurements for select to authenticated using(user_id=(select auth.uid()));
create policy progress_photo_sets_own_read on public.progress_photo_sets for select to authenticated using(user_id=(select auth.uid()));
create policy progress_photos_own_read on public.progress_photos for select to authenticated using(user_id=(select auth.uid()));
create policy progress_reviews_own_read on public.progress_reviews for select to authenticated using(user_id=(select auth.uid()));
create policy progress_photos_insert_own on storage.objects for insert to authenticated with check(
 bucket_id='progress-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and
 (storage.foldername(name))[2]='progress');
create policy progress_photos_read_own on storage.objects for select to authenticated using(
 bucket_id='progress-photos' and owner_id=(select auth.uid()::text));
create policy progress_photos_delete_own on storage.objects for delete to authenticated using(
 bucket_id='progress-photos' and owner_id=(select auth.uid()::text));

revoke all on public.body_measurements,public.progress_photo_sets,public.progress_photos,public.progress_reviews from anon,authenticated;
grant select on public.body_measurements,public.progress_photo_sets,public.progress_photos,public.progress_reviews to authenticated;

create function public.save_body_measurement(
  measurement_date date, weight_kg numeric, waist_cm numeric default null,
  chest_cm numeric default null, hip_cm numeric default null,
  arm_cm numeric default null, thigh_cm numeric default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare measurement_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  insert into public.body_measurements(user_id,measured_on,source,weight_kg,waist_cm,chest_cm,hip_cm,arm_cm,thigh_cm)
  values(auth.uid(),measurement_date,'manual',weight_kg,waist_cm,chest_cm,hip_cm,arm_cm,thigh_cm)
  returning id into measurement_id;
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'progress.measurement.recorded','body_measurement',measurement_id,'succeeded','{}'::jsonb);
  return measurement_id;
end $$;

create function public.get_my_progress_summary()
returns jsonb language sql security definer set search_path='' stable as $$
with ordered as (
  select measured_on,weight_kg,waist_cm,
   row_number() over(order by measured_on,created_at) ascending_rank,
   row_number() over(order by measured_on desc,created_at desc) descending_rank,
   count(*) over() observation_count
  from public.body_measurements where user_id=auth.uid()
), valueset as (
 select max(observation_count)::integer observation_count,
  max(weight_kg) filter(where descending_rank=1) current_weight_kg,
  max(weight_kg) filter(where ascending_rank=1) first_weight_kg,
  max(waist_cm) filter(where descending_rank=1) current_waist_cm,
  max(waist_cm) filter(where ascending_rank=1 and waist_cm is not null) first_waist_cm,
  min(measured_on) first_date,max(measured_on) latest_date
 from ordered
)
select jsonb_build_object(
 'schema_version','1.0','observation_count',coalesce(observation_count,0),
 'current_weight_kg',current_weight_kg,
 'weight_change_kg',case when observation_count>=2 then current_weight_kg-first_weight_kg end,
 'current_waist_cm',current_waist_cm,
 'waist_change_cm',case when observation_count>=2 and current_waist_cm is not null and first_waist_cm is not null then current_waist_cm-first_waist_cm end,
 'first_date',first_date,'latest_date',latest_date,
 'trend_status',case when coalesce(observation_count,0)<2 then 'not_enough_data' else 'available' end,
 'weekly_review_status',case when coalesce(observation_count,0)<2 then 'gather_data' else 'ready' end)
from valueset;
$$;

revoke all on function public.save_body_measurement(date,numeric,numeric,numeric,numeric,numeric,numeric),
 public.get_my_progress_summary() from public,anon,authenticated;
grant execute on function public.save_body_measurement(date,numeric,numeric,numeric,numeric,numeric,numeric),
 public.get_my_progress_summary() to authenticated;
