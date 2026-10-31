-- QA audit groups G and H (2026-10-31). Additive and forward-only; every change is safe for the
-- currently installed Flutter app and Edge Functions.
--
-- 1. The legacy onboarding and fixture-meal RPCs are no longer executable by the app roles. The
--    current app approves a plan with respond_to_onboarding_proposal_v2 (which enforces the health
--    check) and confirms meals with confirm_analyzed_meal; nothing calls the old ones.
--    persist_coach_preference has no caller in the app or any Edge Function (the service role keeps
--    its own grant).
-- 2. user_accounts.onboarding_state can no longer be written by the signed-in role. Approval sets
--    `completed` inside respond_to_onboarding_proposal_v2, and saving the first onboarding draft now
--    moves `not_started` to `in_progress` in the database, so the app's second write goes away.
-- 3. Body-fat targets get a sex-aware floor, the same style as the weight floor: 5% for men, and
--    12% for women and for anyone whose sex is not known (the more conservative figure). Both goal
--    target functions return it as min_target_body_fat_pct (schema_version 1.1).
-- 4. get_my_daily_nutrition and create_meal_photo_draft return schema_version.

-- 1. Retire the legacy path ---------------------------------------------------------------------

revoke all on function public.respond_to_onboarding_proposal(uuid, public.proposal_response_action)
  from public, anon, authenticated;
revoke all on function public.create_fixture_meal(date, text, text, uuid)
  from public, anon, authenticated;
revoke all on function public.confirm_fixture_meal(uuid, uuid[])
  from public, anon, authenticated;
revoke all on function public.confirm_fixture_meal_v2(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.persist_coach_preference(uuid, text, text, text, text)
  from public, anon, authenticated;

-- 2. onboarding_state is the database's to set --------------------------------------------------

revoke insert (onboarding_state), update (onboarding_state) on public.user_accounts
  from authenticated;

create function private.mark_onboarding_started()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.user_accounts set onboarding_state = 'in_progress'
  where id = new.user_id and onboarding_state = 'not_started';
  return new;
end $$;
revoke all on function private.mark_onboarding_started() from public, anon, authenticated;

create trigger onboarding_drafts_mark_started
  after insert or update on public.onboarding_drafts
  for each row execute function private.mark_onboarding_started();

-- 3. Body-fat floor -----------------------------------------------------------------------------

-- The lowest body-fat percentage accepted as a target. Widely cited essential-fat figures (about
-- 5% for men and 12% for women); with no sex on record the higher figure applies.
create function private.body_fat_floor_pct(target_user_id uuid)
returns numeric language sql stable set search_path = '' as $$
  select case coalesce((select p.sex from public.user_profiles p where p.user_id = target_user_id),
    'unspecified') when 'male' then 5 else 12 end;
$$;
revoke all on function private.body_fat_floor_pct(uuid) from public, anon, authenticated;

create or replace function public.get_goal_target_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  goal public.user_goals%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into goal from public.user_goals g
  where g.user_id = auth.uid() and g.status = 'active'
  order by g.priority, g.activated_at desc nulls last limit 1;
  if not found then
    return jsonb_build_object('schema_version', '1.1', 'has_goal', false, 'has_target', false,
      'goal_type', null, 'target', private.goal_target_json('{}'::jsonb),
      'min_target_weight_kg', private.healthy_floor_weight_kg(auth.uid()),
      'min_target_body_fat_pct', private.body_fat_floor_pct(auth.uid()));
  end if;
  return jsonb_build_object('schema_version', '1.1', 'has_goal', true,
    'has_target', goal.details ? 'target_weight_kg'
      or goal.details ? 'target_body_fat_pct_min' or goal.details ? 'target_body_fat_pct_max'
      or goal.details ? 'target_physique',
    'goal_type', goal.goal_type,
    'target', private.goal_target_json(goal.details),
    'min_target_weight_kg', private.healthy_floor_weight_kg(auth.uid()),
    'min_target_body_fat_pct', private.body_fat_floor_pct(auth.uid()));
end $$;

create or replace function public.set_goal_target_v1(
  p_target_weight_kg numeric default null,
  p_body_fat_pct_min numeric default null,
  p_body_fat_pct_max numeric default null,
  p_physique text default null,
  p_physique_note text default null,
  p_target_date date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  goal public.user_goals%rowtype;
  floor_kg numeric;
  fat_floor numeric;
  today date;
  note text := nullif(btrim(p_physique_note), '');
  kinds text[] := '{}';
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_target_weight_kg is null and p_body_fat_pct_min is null and p_body_fat_pct_max is null
    and p_physique is null then
    raise exception 'a target needs a weight, a body-fat range or a physique goal'
      using errcode = '22023';
  end if;
  if p_target_weight_kg is not null and p_target_weight_kg not between 30 and 300 then
    raise exception 'target weight is out of range' using errcode = '22023';
  end if;
  if (p_body_fat_pct_min is not null and p_body_fat_pct_min not between 3 and 60)
    or (p_body_fat_pct_max is not null and p_body_fat_pct_max not between 3 and 60)
    or (p_body_fat_pct_min is not null and p_body_fat_pct_max is not null
      and p_body_fat_pct_min > p_body_fat_pct_max) then
    raise exception 'body-fat range is invalid' using errcode = '22023';
  end if;
  fat_floor := private.body_fat_floor_pct(auth.uid());
  if (p_body_fat_pct_min is not null and p_body_fat_pct_min < fat_floor)
    or (p_body_fat_pct_max is not null and p_body_fat_pct_max < fat_floor) then
    raise exception 'body-fat target is below the healthy range for you' using errcode = '22023';
  end if;
  if p_physique is not null and p_physique not in ('visible_abs', 'more_definition',
    'athletic_build', 'bigger_muscles', 'stronger', 'lean_and_toned', 'other') then
    raise exception 'unknown physique goal' using errcode = '22023';
  end if;
  if note is not null and (p_physique is null or char_length(note) > 120) then
    raise exception 'physique note needs a physique goal and at most 120 characters'
      using errcode = '22023';
  end if;
  today := private.local_date_for(auth.uid());
  if p_target_date is not null and (p_target_date <= today or p_target_date > today + 1096) then
    raise exception 'target date must be within the next three years' using errcode = '22023';
  end if;
  floor_kg := private.healthy_floor_weight_kg(auth.uid());
  if p_target_weight_kg is not null and floor_kg is not null and p_target_weight_kg < floor_kg then
    raise exception 'target weight is below the healthy range for this height' using errcode = '22023';
  end if;

  select * into goal from public.user_goals g
  where g.user_id = auth.uid() and g.status = 'active'
  order by g.priority, g.activated_at desc nulls last limit 1 for update;
  if not found then
    raise exception 'there is no active goal' using errcode = '55000';
  end if;

  update public.user_goals g set details = (g.details - private.goal_target_keys())
    || jsonb_strip_nulls(jsonb_build_object(
      'target_weight_kg', p_target_weight_kg,
      'target_body_fat_pct_min', p_body_fat_pct_min,
      'target_body_fat_pct_max', p_body_fat_pct_max,
      'target_physique', p_physique,
      'target_physique_note', note,
      'target_date', p_target_date,
      'target_set_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))
  where g.id = goal.id returning * into goal;

  if p_target_weight_kg is not null then kinds := array_append(kinds, 'weight'); end if;
  if p_body_fat_pct_min is not null or p_body_fat_pct_max is not null then
    kinds := array_append(kinds, 'body_fat');
  end if;
  if p_physique is not null then kinds := array_append(kinds, 'physique'); end if;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'goal_target_set', 'user_goal', goal.id, 'succeeded',
    jsonb_build_object('schema_version', '1.0', 'kinds', to_jsonb(kinds),
      'has_date', p_target_date is not null));

  return jsonb_build_object('schema_version', '1.1', 'has_goal', true, 'has_target', true,
    'goal_type', goal.goal_type, 'target', private.goal_target_json(goal.details),
    'min_target_weight_kg', floor_kg, 'min_target_body_fat_pct', fat_floor);
end $$;

-- 4. schema_version on the meal functions ------------------------------------------------------

create or replace function public.get_my_daily_nutrition(target_date date)
returns jsonb language sql security definer set search_path='' stable as $$
 select jsonb_build_object('schema_version','1.0','local_date',target_date,
  'calories',coalesce(sum(i.calories),0),
  'protein_g',coalesce(sum(i.protein_g),0),'carbohydrate_g',coalesce(sum(i.carbohydrate_g),0),
  'fat_g',coalesce(sum(i.fat_g),0),'confirmed_meals',count(distinct m.id))
 from public.meals m join public.meal_items i on i.meal_id=m.id and i.user_id=m.user_id
 where m.user_id=auth.uid() and m.local_date=target_date and m.status='confirmed';
$$;

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
    return jsonb_build_object('schema_version','1.0','meal_id',meal_id,'replayed',true);
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
  return jsonb_build_object('schema_version','1.0','meal_id',meal_id,'media_id',media_id,
    'object_path',object_path,'replayed',false);
end $$;
