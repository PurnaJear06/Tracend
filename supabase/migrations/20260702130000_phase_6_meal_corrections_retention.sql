alter table public.media_objects
  drop constraint media_objects_lifecycle_status_check,
  add constraint media_objects_lifecycle_status_check
    check (lifecycle_status in ('active', 'pending_deletion', 'deleted')),
  add column retention_exempt boolean not null default false;

create index media_objects_retention_due
  on public.media_objects(retention_deadline, created_at)
  where lifecycle_status = 'active' and not retention_exempt;

create function public.confirm_fixture_meal_v2(
  target_meal_id uuid,
  candidate_payload jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  meal public.meals%rowtype;
  candidate jsonb;
  candidate_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into meal
  from public.meals
  where id = target_meal_id and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'meal not found' using errcode = 'P0002';
  end if;
  if meal.status = 'confirmed' then
    return meal.id;
  end if;
  if meal.source <> 'fixture_analysis'
    or jsonb_typeof(candidate_payload) <> 'array'
    or jsonb_array_length(candidate_payload) not between 1 and 30
  then
    raise exception 'invalid confirmation' using errcode = '22023';
  end if;

  for candidate in select value from jsonb_array_elements(candidate_payload)
  loop
    begin
      candidate_id := (candidate ->> 'id')::uuid;
    exception when others then
      raise exception 'invalid candidate' using errcode = '22023';
    end;

    if length(coalesce(candidate ->> 'name', '')) not between 1 and 120
      or length(coalesce(candidate ->> 'serving_label', '')) not between 1 and 80
    then
      raise exception 'invalid candidate' using errcode = '22023';
    end if;

    update public.meal_analysis_candidates
    set food_label = candidate ->> 'name',
        serving_label = candidate ->> 'serving_label',
        calories = (candidate ->> 'calories')::numeric,
        protein_g = (candidate ->> 'protein_g')::numeric,
        carbohydrate_g = (candidate ->> 'carbohydrate_g')::numeric,
        fat_g = (candidate ->> 'fat_g')::numeric,
        selected = true
    where id = candidate_id
      and meal_id = meal.id
      and user_id = auth.uid();

    if not found then
      raise exception 'candidate not found' using errcode = 'P0002';
    end if;
  end loop;

  update public.meal_analysis_candidates
  set selected = false
  where meal_id = meal.id
    and user_id = auth.uid()
    and id not in (
      select (value ->> 'id')::uuid
      from jsonb_array_elements(candidate_payload)
    );

  insert into public.meal_items(
    user_id, meal_id, name_snapshot, serving_label, calories,
    protein_g, carbohydrate_g, fat_g, confirmed_at
  )
  select user_id, meal_id, food_label, serving_label, calories,
    protein_g, carbohydrate_g, fat_g, now()
  from public.meal_analysis_candidates
  where meal_id = meal.id and selected;

  update public.meals
  set status = 'confirmed', confirmed_at = now()
  where id = meal.id;

  update public.media_objects
  set retention_deadline = least(retention_deadline, now() + interval '30 days')
  where id = meal.media_object_id
    and user_id = auth.uid()
    and not retention_exempt;

  insert into public.audit_events(
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    auth.uid(), 'meal.fixture.confirmed', 'meal', meal.id, 'succeeded',
    jsonb_build_object('item_count', jsonb_array_length(candidate_payload), 'schema_version', 2)
  );
  return meal.id;
end
$$;

create function public.delete_my_meal(target_meal_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  meal public.meals%rowtype;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into meal
  from public.meals
  where id = target_meal_id and user_id = auth.uid()
  for update;

  if not found then
    return true;
  end if;

  update public.media_objects
  set retention_deadline = least(retention_deadline, now())
  where id = meal.media_object_id
    and user_id = auth.uid()
    and not retention_exempt;

  delete from public.meals
  where id = meal.id and user_id = auth.uid();

  insert into public.audit_events(
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    auth.uid(), 'meal.deleted', 'meal', meal.id, 'succeeded',
    jsonb_build_object('was_confirmed', meal.status = 'confirmed')
  );
  return true;
end
$$;

create function public.claim_expired_meal_media(batch_size integer default 50)
returns table(media_object_id uuid, object_key text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if batch_size not between 1 and 100 then
    raise exception 'invalid batch size' using errcode = '22023';
  end if;

  return query
  with due as (
    select id
    from public.media_objects
    where lifecycle_status = 'active'
      and not retention_exempt
      and retention_deadline <= now()
    order by retention_deadline, created_at
    for update skip locked
    limit batch_size
  )
  update public.media_objects media
  set lifecycle_status = 'pending_deletion'
  from due
  where media.id = due.id
  returning media.id, media.object_key;
end
$$;

create function public.complete_meal_media_retention(
  target_media_object_id uuid,
  deletion_succeeded boolean
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  update public.media_objects
  set lifecycle_status = case when deletion_succeeded then 'deleted' else 'active' end,
      deleted_at = case when deletion_succeeded then now() else null end,
      retention_deadline = case
        when deletion_succeeded then retention_deadline
        else now() + interval '1 hour'
      end
  where id = target_media_object_id
    and lifecycle_status = 'pending_deletion'
  returning user_id into owner_id;

  if owner_id is not null then
    insert into public.audit_events(
      user_id, action_code, target_type, target_id, outcome, metadata
    ) values (
      owner_id, 'media.meal.retention', 'media_object', target_media_object_id,
      case when deletion_succeeded then 'succeeded' else 'rejected' end,
      '{}'::jsonb
    );
  end if;
end
$$;

revoke all on function public.confirm_fixture_meal_v2(uuid, jsonb),
  public.delete_my_meal(uuid), public.claim_expired_meal_media(integer),
  public.complete_meal_media_retention(uuid, boolean)
  from public, anon, authenticated, service_role;

grant execute on function public.confirm_fixture_meal_v2(uuid, jsonb),
  public.delete_my_meal(uuid) to authenticated;
grant execute on function public.claim_expired_meal_media(integer),
  public.complete_meal_media_retention(uuid, boolean) to service_role;
