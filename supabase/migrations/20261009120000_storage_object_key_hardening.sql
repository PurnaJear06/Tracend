-- Media keys must name exactly the object the app uploaded. Service-role code
-- (meal analysis, physique check, export, account deletion, retention) reads
-- these keys and calls Storage without Storage RLS, so a key is accepted only
-- in the exact form the app writes, for an object the caller owns.

create function private.is_owned_media_key(owner uuid, kind text, key text)
returns boolean language sql immutable set search_path = '' as $$
  select case kind
    when 'meal' then key ~ ('^' || owner::text
      || '/meal/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$')
    when 'progress' then key ~ ('^' || owner::text
      || '/progress/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
      || '/(front|side|back|lower)\.(jpg|jpeg|png|heic)$')
    else false
  end;
$$;
revoke all on function private.is_owned_media_key(uuid, text, text) from public, anon, authenticated;

-- New rows only: a key stays inside its owner's folder and has no segment or
-- character that Storage could resolve to another path.
alter table public.media_objects add constraint media_objects_object_key_safe check (
  object_key like (user_id::text || '/%')
  and object_key !~ '(^|/)\.{1,2}(/|$)'
  and object_key !~ '//'
  and object_key !~ '[\\%[:cntrl:]]'
) not valid;

-- The app uploads `<uid>/meal/<request id>.jpg` and then calls this with the
-- same request id, so the key is bound to the idempotency key and the object
-- must already exist under the caller's ownership.
create or replace function public.create_meal_photo_draft(
  meal_date date,meal_timezone text,meal_kind text,request_idempotency_key uuid,
  object_path text,object_content_type text,object_byte_size integer,object_checksum text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare media_id uuid; meal_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if meal_kind not in ('breakfast','lunch','dinner','snack')
    or length(meal_timezone) not between 1 and 64
    or object_path is null
    or split_part(object_path, '.', 1) <> auth.uid()::text||'/meal/'||request_idempotency_key::text
    or not private.is_owned_media_key(auth.uid(), 'meal', object_path)
    or object_content_type not in ('image/jpeg','image/png','image/heic')
    or object_byte_size not between 1 and 4194304
    or object_checksum !~ '^[0-9a-f]{64}$'
  then raise exception 'invalid meal photo draft' using errcode='22023'; end if;
  select id into meal_id from public.meals
  where user_id=auth.uid() and idempotency_key=request_idempotency_key;
  if meal_id is not null then
    return jsonb_build_object('meal_id',meal_id,'replayed',true);
  end if;
  if not exists(select 1 from storage.objects where bucket_id='meal-images'
    and name=object_path and owner_id=auth.uid()::text)
  then raise exception 'uploaded object not found' using errcode='P0002'; end if;
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

-- The key must be exactly `<uid>/progress/<set>/<pose>.<ext>`; a prefix match
-- let anything follow the pose.
create or replace function public.register_progress_photo(
  target_set_id uuid, photo_pose text, storage_key text,
  media_type text, media_bytes integer, media_checksum text
) returns uuid language plpgsql security definer set search_path='' as $$
declare media_id uuid; photo_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if photo_pose not in ('front','side','back','lower') then raise exception 'invalid pose' using errcode='22023'; end if;
  if not exists(select 1 from public.progress_photo_sets where id=target_set_id and user_id=auth.uid() and status='draft')
    then raise exception 'photo set not found' using errcode='P0002'; end if;
  if storage_key is null
    or split_part(storage_key, '.', 1) <> auth.uid()::text||'/progress/'||target_set_id::text||'/'||photo_pose
    or not private.is_owned_media_key(auth.uid(), 'progress', storage_key)
    or media_type not in ('image/jpeg','image/png','image/heic')
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

-- The app may confirm a preference only for its own account; the service role
-- keeps writing for any athlete.
create or replace function public.persist_coach_preference(
  target_user_id uuid, category text, pref_key text, pref_value text,
  provenance text
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  pref_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role'
    and (auth.uid() is null or target_user_id is distinct from auth.uid()) then
    raise exception 'not allowed' using errcode='42501';
  end if;
  if provenance not in ('onboarding','chat_statement','repeated_signal','manual') then
    raise exception 'invalid provenance' using errcode='22023';
  end if;
  if category not in ('training','food','schedule','communication','notification','lifestyle') then
    raise exception 'invalid category' using errcode='22023';
  end if;
  update public.user_preferences set superseded_at = now()
    where user_id = target_user_id and key = pref_key and superseded_at is null;
  insert into public.user_preferences(user_id, category, key, value, provenance)
  values(target_user_id, category, pref_key, pref_value, provenance) returning id into pref_id;
  return pref_id;
end $$;
