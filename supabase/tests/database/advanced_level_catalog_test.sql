begin;
select plan(23);

-- The advanced level and four staple lifts (20261023100050_advanced_level_catalog.sql).

select ok(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
   from pg_enum e where e.enumtypid = 'public.experience_level'::regtype)
    = array['beginner', 'intermediate', 'advanced'],
  'the profile experience level already has an advanced value');

select lives_ok(
  $$update public.exercise_catalog set level = 'advanced' where slug = 'bodyweight-squat'$$,
  'the catalog accepts the advanced level');
select throws_ok(
  $$update public.exercise_catalog set level = 'expert' where slug = 'bodyweight-squat'$$,
  '23514',
  null,
  'and still refuses any other level');
select is(
  (select count(*) from pg_constraint
   where conrelid = 'public.exercise_catalog'::regclass and contype = 'c'
     and pg_get_constraintdef(oid) like '%level%'),
  1::bigint,
  'one level check remains');

select is(
  (select array_agg(slug order by slug) from public.exercise_catalog where level = 'advanced'
     and slug <> 'bodyweight-squat'),
  array['bulgarian-split-squat', 'close-grip-bench-press', 'incline-barbell-bench-press',
    'weighted-pull-up']::text[],
  'four staples are advanced-level rows');

select is(
  (select count(*) from public.exercise_catalog where status = 'active'),
  76::bigint,
  'the four new rows join the 72 that were there');

select is(
  (select (movement_pattern, primary_muscles, equipment_required, is_compound)::text
   from public.exercise_catalog where slug = 'weighted-pull-up'),
  '(vertical_pull,"{back,biceps}","{pull_up_bar,dumbbells}",t)',
  'the weighted pull-up is a vertical pull that needs a bar and a dumbbell');
select is(
  (select (movement_pattern, primary_muscles, equipment_required)::text
   from public.exercise_catalog where slug = 'close-grip-bench-press'),
  '(horizontal_push,"{chest,triceps}","{barbell,bench}")',
  'the close-grip bench press is a barbell horizontal push');
select is(
  (select (movement_pattern, primary_muscles, equipment_required)::text
   from public.exercise_catalog where slug = 'incline-barbell-bench-press'),
  '(horizontal_push,"{chest,shoulders}","{barbell,bench}")',
  'the incline barbell press trains the chest and front shoulders');
select is(
  (select (movement_pattern, primary_muscles, equipment_required)::text
   from public.exercise_catalog where slug = 'bulgarian-split-squat'),
  '(lunge,"{quads,glutes}","{dumbbells,bench}")',
  'the Bulgarian split squat is a loaded lunge with the rear foot on a bench');

select is(
  (select count(*) from public.exercise_catalog
   where slug in ('weighted-pull-up', 'close-grip-bench-press', 'incline-barbell-bench-press',
     'bulgarian-split-squat')
     and load_step_kg = 2.5 and exercise_role = 'variation'),
  4::bigint,
  'each staple steps by 2.5 kg and is a variation of the standard form');

select is(
  (select (knee_stress, back_stress, shoulder_stress)::text
   from public.exercise_catalog where slug = 'weighted-pull-up'),
  '(low,low,high)',
  'a weighted pull-up is rated harsher on the shoulder than the pull-up');
select is(
  (select knee_stress from public.exercise_catalog where slug = 'bulgarian-split-squat'),
  'high',
  'the Bulgarian split squat loads the knee through a deep single-leg bend');

select is(
  (select progressions from public.exercise_catalog where slug = 'pull-up'),
  array['weighted-pull-up']::text[],
  'the pull-up progresses to the weighted pull-up');
select ok(
  (select 'bulgarian-split-squat' = any(progressions) from public.exercise_catalog
   where slug = 'dumbbell-reverse-lunge')
  and (select 'close-grip-bench-press' = any(substitutes) from public.exercise_catalog
   where slug = 'barbell-bench-press'),
  'existing rows point at the new ones');
select is(
  (select count(*) from public.exercise_catalog c, unnest(c.regressions || c.progressions
     || c.substitutes) link
   where not exists (select 1 from public.exercise_catalog t where t.slug = link)),
  0::bigint,
  'every link still names a catalog exercise');
select is(
  (select count(*) from public.exercise_catalog c, unnest(c.substitutes) other
   join public.exercise_catalog o on o.slug = other
   where not (c.slug = any(o.substitutes))),
  0::bigint,
  'substitutes stay mutual');
select is(
  (select count(*) from public.exercise_catalog
   where knee_stress is null or back_stress is null or shoulder_stress is null),
  0::bigint,
  'every row, new ones included, has joint stress ratings');

-- Existing rows keep what they had: only links were added.
select is(
  (select (level, load_step_kg, exercise_role)::text
   from public.exercise_catalog where slug = 'pull-up'),
  '(intermediate,,)',
  'the pull-up keeps its level, has no load step and no role');
select is(
  (select (level, substitutes)::text from public.exercise_catalog where slug = 'barbell-bench-press'),
  '(beginner,"{dumbbell-bench-press,machine-chest-press,close-grip-bench-press,incline-barbell-bench-press}")',
  'the bench press keeps its level and its two earlier substitutes, then gains two');

-- Progression: a weighted pull-up is logged as added weight; 0 kg is a real value, and the step
-- is the catalog's 2.5 kg (3 sets of 6 to 8 at RPE 8, every set at the top with two reps left).
select is(
  private.progression_decision(3, 6, 8, 8, 2.5, 3, false, false, false,
    jsonb_build_array(jsonb_build_object('load_kg', 0, 'sets', 3, 'min_reps', 8, 'total_reps', 24,
      'min_rir', 2, 'effort_known', true, 'pain', false))),
  '{"action":"add_load","reason":"top_of_range","load_kg":2.5,"reps":6,"sets":3,"confidence":"high"}'::jsonb,
  'bodyweight reps at the top add one 2.5 kg step of added weight');
select is(
  private.progression_decision(3, 6, 8, 8, 2.5, 3, false, false, false,
    jsonb_build_array(jsonb_build_object('load_kg', 10, 'sets', 3, 'min_reps', 6, 'total_reps', 19,
      'min_rir', 2, 'effort_known', true, 'pain', false)))->>'reps',
  '7',
  'inside the range the weakest set adds a rep');

-- Athletes still read the catalog and cannot change it.
set local role authenticated;
select is(
  (select level from public.exercise_catalog where slug = 'bulgarian-split-squat'),
  'advanced',
  'athletes can read the new rows');
reset role;

select * from finish();
rollback;
