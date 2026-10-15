begin;
select plan(10);

select is(
  (select count(*) from public.exercise_catalog
   where knee_stress is null or back_stress is null or shoulder_stress is null),
  0::bigint,
  'every catalog exercise has knee, back and shoulder stress ratings');

select is(
  (select count(*) from public.exercise_catalog c,
     unnest(c.regressions || c.progressions || c.substitutes) link
   where not exists (select 1 from public.exercise_catalog t where t.slug = link)),
  0::bigint,
  'every regression, progression and substitute names a catalog exercise');

select is(
  (select count(*) from public.exercise_catalog c, unnest(c.progressions) harder
   join public.exercise_catalog h on h.slug = harder
   where not (c.slug = any(h.regressions)) or h.movement_pattern <> c.movement_pattern),
  0::bigint,
  'progressions and regressions mirror each other within a movement pattern');

select is(
  (select count(*) from public.exercise_catalog c, unnest(c.substitutes) other
   join public.exercise_catalog o on o.slug = other
   where not (c.slug = any(o.substitutes))),
  0::bigint,
  'substitutes are mutual');

select is(
  (select load_step_kg from public.exercise_catalog where slug = 'barbell-back-squat'),
  2.5::numeric(4,2),
  'a barbell exercise steps by 2.5 kg');

select ok(
  (select load_step_kg is null and exercise_role is null
   from public.exercise_catalog where slug = 'pull-up')
  and (select exercise_role = 'regression'
   from public.exercise_catalog where slug = 'assisted-pull-up'),
  'bodyweight exercises have no load step and B0 roles are stored');

select throws_ok(
  $$update public.exercise_catalog set substitutes = array['push-up'] where slug = 'push-up'$$,
  '23514',
  null,
  'an exercise cannot link to itself');

select throws_ok(
  $$update public.exercise_catalog set secondary_muscles = array['chest'] where slug = 'push-up'$$,
  '23514',
  null,
  'a secondary muscle cannot also be primary');

set local role authenticated;
select is(
  (select substitutes from public.exercise_catalog where slug = 'push-up'),
  array['dumbbell-floor-press','machine-chest-press']::text[],
  'athletes can read the v2 columns');
reset role;

select ok(
  not has_table_privilege('anon', 'public.exercise_catalog', 'select'),
  'anonymous callers cannot read the catalog');

select * from finish();
rollback;
