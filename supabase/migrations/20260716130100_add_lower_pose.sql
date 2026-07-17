alter table public.progress_photos drop constraint progress_photos_pose_check;
alter table public.progress_photos add constraint progress_photos_pose_check
  check (pose in ('front','side','back','lower'));

alter table public.media_objects drop constraint media_objects_purpose_check;
alter table public.media_objects add constraint media_objects_purpose_check
  check (purpose in ('meal_analysis','progress_front','progress_side','progress_back','progress_lower'));

create or replace function public.register_progress_photo(
  target_set_id uuid, photo_pose text, storage_key text,
  media_type text, media_bytes integer, media_checksum text
) returns uuid language plpgsql security definer set search_path='' as $$
declare media_id uuid; photo_id uuid; expected_prefix text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if photo_pose not in ('front','side','back','lower') then raise exception 'invalid pose' using errcode='22023'; end if;
  if not exists(select 1 from public.progress_photo_sets where id=target_set_id and user_id=auth.uid() and status='draft')
    then raise exception 'photo set not found' using errcode='P0002'; end if;
  expected_prefix:=auth.uid()::text||'/progress/'||target_set_id::text||'/'||photo_pose||'.';
  if storage_key not like expected_prefix||'%' or media_type not in ('image/jpeg','image/png','image/heic')
    or media_bytes not between 1 and 10485760 or media_checksum !~ '^[0-9a-f]{64}$'
    then raise exception 'invalid media metadata' using errcode='22023'; end if;
  if not exists(select 1 from storage.objects where bucket_id='progress-photos' and name=storage_key and owner_id=auth.uid()::text)
    then raise exception 'uploaded object not found' using errcode='P0002'; end if;
  insert into public.media_objects(user_id,purpose,object_key,content_type,byte_size,checksum,retention_deadline,retention_exempt)
  values(auth.uid(),'progress_'||photo_pose,storage_key,media_type,media_bytes,media_checksum,'infinity',true)
  returning id into media_id;
  insert into public.progress_photos(user_id,photo_set_id,media_object_id,pose,quality_status)
  values(auth.uid(),target_set_id,media_id,photo_pose,'accepted') returning id into photo_id;
  if (select count(*) from public.progress_photos where photo_set_id=target_set_id and user_id=auth.uid())=4
    then update public.progress_photo_sets set status='complete' where id=target_set_id and user_id=auth.uid(); end if;
  return photo_id;
end $$;

revoke all on function public.register_progress_photo(uuid,text,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.register_progress_photo(uuid,text,text,text,integer,text) to authenticated;
