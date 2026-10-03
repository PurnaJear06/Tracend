-- Older plans predate the exercise catalog: their planned exercises carry no
-- slug, so the hub returns no primary muscles and Train's muscle map has
-- nothing to show. Link each planned exercise whose name is exactly a catalog
-- exercise's name, compared with the exercise history key (lowercased,
-- trimmed, inner spaces collapsed). A name that matches no catalog exercise,
-- or more than one, stays unlinked: no muscles are guessed. The approved
-- prescription (sets, reps, load, order, names) is unchanged.

create function private.link_planned_exercises_to_catalog()
returns integer language plpgsql security definer set search_path = '' as $$
declare
  linked integer;
begin
  with matches as (
    select pe.id, min(c.slug) as slug
    from public.planned_exercises pe
    join public.exercise_catalog c
      on private.exercise_name_key(c.name)
         = private.exercise_name_key(pe.display_name_snapshot)
    where pe.exercise_slug is null
    group by pe.id
    having count(*) = 1
  )
  update public.planned_exercises pe
  set exercise_slug = m.slug
  from matches m
  where pe.id = m.id;
  get diagnostics linked = row_count;

  -- Prescribed performances of a newly linked exercise share its history key.
  update public.exercise_performances p
  set exercise_slug = pe.exercise_slug
  from public.planned_exercises pe
  where pe.id = p.planned_exercise_id and pe.user_id = p.user_id
    and p.performance_kind = 'prescribed'
    and p.exercise_slug is null and pe.exercise_slug is not null;

  return linked;
end $$;
revoke all on function private.link_planned_exercises_to_catalog()
  from public, anon, authenticated;

select private.link_planned_exercises_to_catalog();
