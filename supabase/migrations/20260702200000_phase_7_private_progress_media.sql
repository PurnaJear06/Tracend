create function public.begin_progress_photo_set(
  capture_date date, timing text
) returns uuid language plpgsql security definer set search_path='' as $$
declare set_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if length(timing) not between 1 and 120 then raise exception 'invalid timing context' using errcode='22023'; end if;
  if not exists (
    select 1 from public.consent_records c where c.user_id=auth.uid()
      and c.consent_type='progress_photo_storage' and c.action='granted'
      and c.created_at=(select max(x.created_at) from public.consent_records x
        where x.user_id=c.user_id and x.consent_type=c.consent_type)
  ) then raise exception 'progress photo storage consent required' using errcode='42501'; end if;
  insert into public.progress_photo_sets(user_id,captured_on,capture_protocol_version,timing_context)
  values(auth.uid(),capture_date,'standard-v1',timing) returning id into set_id;
  return set_id;
end $$;

create function public.register_progress_photo(
  target_set_id uuid, photo_pose text, storage_key text,
  media_type text, media_bytes integer, media_checksum text
) returns uuid language plpgsql security definer set search_path='' as $$
declare media_id uuid; photo_id uuid; expected_prefix text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if photo_pose not in ('front','side','back') then raise exception 'invalid pose' using errcode='22023'; end if;
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
  if (select count(*) from public.progress_photos where photo_set_id=target_set_id and user_id=auth.uid())=3
    then update public.progress_photo_sets set status='complete' where id=target_set_id and user_id=auth.uid(); end if;
  return photo_id;
end $$;

create function public.delete_my_progress_photo_set(target_set_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare media_ids uuid[];
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if not exists(select 1 from public.progress_photo_sets where id=target_set_id and user_id=auth.uid())
    then return true; end if;
  select coalesce(array_agg(media_object_id),'{}') into media_ids from public.progress_photos
    where photo_set_id=target_set_id and user_id=auth.uid();
  delete from public.progress_photo_sets where id=target_set_id and user_id=auth.uid();
  delete from public.media_objects where id=any(media_ids) and user_id=auth.uid();
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'progress.photo_set.deleted','progress_photo_set',target_set_id,'succeeded','{}');
  return true;
end $$;

revoke all on function public.begin_progress_photo_set(date,text),
 public.register_progress_photo(uuid,text,text,text,integer,text),
 public.delete_my_progress_photo_set(uuid) from public,anon,authenticated;
grant execute on function public.begin_progress_photo_set(date,text),
 public.register_progress_photo(uuid,text,text,text,integer,text),
 public.delete_my_progress_photo_set(uuid) to authenticated;
