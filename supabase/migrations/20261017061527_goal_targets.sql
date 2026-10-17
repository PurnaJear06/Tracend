-- B7: goals can have an end point, and Coach can review the phase. Additive only.
--
-- 1. public.set_goal_target_v1(...)   athlete sets a target on the active goal (RLS-safe RPC)
-- 2. public.get_goal_target_v1()      the active goal's target, and the lowest accepted weight
-- 3. public.get_goal_phase_inputs_v1(uuid)   service role only, for the Coach goal-phase review
--
-- The target is stored in user_goals.details under keys beside the existing target_weight_kg
-- (onboarding already writes that key), so the athlete file Coach reads and older app builds see
-- it with no further change:
--   target_weight_kg, target_body_fat_pct_min, target_body_fat_pct_max, target_physique,
--   target_physique_note, target_date, target_set_at
-- Only the athlete sets a target (Architecture rule 2): the function runs as the signed-in user's
-- auth.uid() and the model has no path to it. Every call writes an audit event.

create function private.goal_target_keys()
returns text[] language sql immutable set search_path = '' as $$
  select array['target_weight_kg', 'target_body_fat_pct_min', 'target_body_fat_pct_max',
    'target_physique', 'target_physique_note', 'target_date', 'target_set_at'];
$$;
revoke all on function private.goal_target_keys() from public, anon, authenticated;

-- The lowest weight accepted as a target for this athlete: BMI 18.5, the bottom of the healthy
-- range, at their height. Null when no height is known.
create function private.healthy_floor_weight_kg(target_user_id uuid)
returns numeric language sql stable set search_path = '' as $$
  select round(18.5 * (p.height_cm / 100) * (p.height_cm / 100), 1)
  from public.user_profiles p
  where p.user_id = target_user_id and p.height_cm is not null;
$$;
revoke all on function private.healthy_floor_weight_kg(uuid) from public, anon, authenticated;

create function private.goal_target_json(goal_details jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'weight_kg', goal_details -> 'target_weight_kg',
    'body_fat_pct_min', goal_details -> 'target_body_fat_pct_min',
    'body_fat_pct_max', goal_details -> 'target_body_fat_pct_max',
    'physique', goal_details -> 'target_physique',
    'physique_note', goal_details -> 'target_physique_note',
    'date', goal_details -> 'target_date',
    'set_at', goal_details -> 'target_set_at');
$$;
revoke all on function private.goal_target_json(jsonb) from public, anon, authenticated;

-- 2. Read ---------------------------------------------------------------------------------------

create function public.get_goal_target_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  goal public.user_goals%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into goal from public.user_goals g
  where g.user_id = auth.uid() and g.status = 'active'
  order by g.priority, g.activated_at desc nulls last limit 1;
  if not found then
    return jsonb_build_object('schema_version', '1.0', 'has_goal', false, 'has_target', false,
      'goal_type', null, 'target', private.goal_target_json('{}'::jsonb),
      'min_target_weight_kg', private.healthy_floor_weight_kg(auth.uid()));
  end if;
  return jsonb_build_object('schema_version', '1.0', 'has_goal', true,
    'has_target', goal.details ? 'target_weight_kg'
      or goal.details ? 'target_body_fat_pct_min' or goal.details ? 'target_body_fat_pct_max'
      or goal.details ? 'target_physique',
    'goal_type', goal.goal_type,
    'target', private.goal_target_json(goal.details),
    'min_target_weight_kg', private.healthy_floor_weight_kg(auth.uid()));
end $$;
revoke all on function public.get_goal_target_v1() from public, anon, authenticated;
grant execute on function public.get_goal_target_v1() to authenticated;

-- 1. Write --------------------------------------------------------------------------------------

-- Replaces the active goal's target with exactly what is passed (a null leaves that part unset).
-- At least one of weight, body fat or physique is required; a date alone is not a target.
create function public.set_goal_target_v1(
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

  if p_target_weight_kg is not null then kinds := kinds || 'weight'; end if;
  if p_body_fat_pct_min is not null or p_body_fat_pct_max is not null then
    kinds := kinds || 'body_fat';
  end if;
  if p_physique is not null then kinds := kinds || 'physique'; end if;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'goal_target_set', 'user_goal', goal.id, 'succeeded',
    jsonb_build_object('schema_version', '1.0', 'kinds', to_jsonb(kinds),
      'has_date', p_target_date is not null));

  return jsonb_build_object('schema_version', '1.0', 'has_goal', true, 'has_target', true,
    'goal_type', goal.goal_type, 'target', private.goal_target_json(goal.details),
    'min_target_weight_kg', floor_kg);
end $$;
revoke all on function public.set_goal_target_v1(numeric, numeric, numeric, text, text, date)
  from public, anon, authenticated;
grant execute on function public.set_goal_target_v1(numeric, numeric, numeric, text, text, date)
  to authenticated;

-- 3. Coach goal-phase inputs --------------------------------------------------------------------

-- The active goal, its target, the height and every current weight reading (an amended reading
-- is replaced by its amendment). The phase summary and the review are computed in TypeScript
-- (supabase/functions/_shared/training/goal_phase); this only reads.
create function public.get_goal_phase_inputs_v1(p_user_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'height_cm', (select p.height_cm from public.user_profiles p where p.user_id = p_user_id),
    'goal', (select jsonb_build_object(
        'goal_type', g.goal_type,
        'activated_on', (g.activated_at at time zone coalesce((
          select a.timezone from public.user_accounts a
          join pg_catalog.pg_timezone_names z on z.name = a.timezone
          where a.id = p_user_id), 'UTC'))::date,
        'target', private.goal_target_json(g.details))
      from public.user_goals g
      where g.user_id = p_user_id and g.status = 'active'
      order by g.priority, g.activated_at desc nulls last limit 1),
    'readings', (select coalesce(jsonb_agg(jsonb_build_object('date', r.measured_on, 'kg', r.weight_kg)
        order by r.measured_on, r.created_at), '[]'::jsonb)
      from (select bm.measured_on, bm.created_at, bm.weight_kg
        from public.body_measurements bm
        where bm.user_id = p_user_id
          and not exists (select 1 from public.body_measurements newer
            where newer.user_id = bm.user_id and newer.amended_from_id = bm.id)
        order by bm.measured_on desc, bm.created_at desc limit 400) r));
$$;
revoke all on function public.get_goal_phase_inputs_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_goal_phase_inputs_v1(uuid) to service_role;
