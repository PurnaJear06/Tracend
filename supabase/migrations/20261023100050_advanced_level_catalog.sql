-- Advanced experience level and four advanced staple lifts in the exercise catalog.
--
-- Additive and safe for the deployed app and Edge Functions:
--   * The catalog's level check is widened, never narrowed: 'advanced' joins 'beginner' and
--     'intermediate'. public.experience_level (user_profiles.experience_level) already has
--     'advanced', so no other constraint changes.
--   * Four new rows are inserted, all level 'advanced', so an advanced athlete is offered them and
--     athletes of the levels below are not (the Edge Function filters by level). A build that
--     still reads the old two-level filter would offer them to intermediates until the new
--     function deploys, which is harmless: they are valid catalog exercises.
--   * Seven existing rows gain links to the new rows (a progression, a substitute); no link is
--     removed or renamed. The links are mirrored: a progression lists its regression, a
--     substitute lists its substitute.
-- The rows mirror supabase/functions/_shared/onboarding/catalog.ts and catalog_v2.ts;
-- catalog_test.ts and catalog_v2_test.ts keep them equal. Joint stress ratings are in-house
-- (_shared/training/standard/joint_stress.ts).

do $$
declare
  existing text;
begin
  select conname into existing
  from pg_constraint
  where conrelid = 'public.exercise_catalog'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%level%'
    and pg_get_constraintdef(oid) like '%intermediate%';
  if existing is not null then
    execute format('alter table public.exercise_catalog drop constraint %I', existing);
  end if;
end;
$$;

alter table public.exercise_catalog
  add constraint exercise_catalog_level_check
  check (level in ('beginner','intermediate','advanced'));

insert into public.exercise_catalog(
  slug,name,movement_pattern,primary_muscles,equipment_required,level,is_compound
) values
 ('weighted-pull-up','Weighted pull-up','vertical_pull',array['back','biceps']::text[],array['pull_up_bar','dumbbells']::text[],'advanced',true),
 ('close-grip-bench-press','Close-grip bench press','horizontal_push',array['chest','triceps']::text[],array['barbell','bench']::text[],'advanced',true),
 ('incline-barbell-bench-press','Incline barbell bench press','horizontal_push',array['chest','shoulders']::text[],array['barbell','bench']::text[],'advanced',true),
 ('bulgarian-split-squat','Bulgarian split squat','lunge',array['quads','glutes']::text[],array['dumbbells','bench']::text[],'advanced',true);

-- Catalog v2 columns for the four new rows and the links of the seven rows that point at them.
update public.exercise_catalog c set
  secondary_muscles = v.secondary_muscles,
  knee_stress = v.knee_stress,
  back_stress = v.back_stress,
  shoulder_stress = v.shoulder_stress,
  regressions = v.regressions,
  progressions = v.progressions,
  substitutes = v.substitutes,
  load_step_kg = v.load_step_kg,
  exercise_role = v.exercise_role
from (values
 ('weighted-pull-up','{}'::text[],'low','low','high',array['pull-up','chin-up']::text[],'{}'::text[],array['lat-pulldown']::text[],2.5::numeric,'variation'),
 ('close-grip-bench-press',array['shoulders']::text[],'low','low','high','{}'::text[],'{}'::text[],array['barbell-bench-press','incline-barbell-bench-press']::text[],2.5::numeric,'variation'),
 ('incline-barbell-bench-press',array['triceps']::text[],'low','low','high','{}'::text[],'{}'::text[],array['barbell-bench-press','close-grip-bench-press','incline-dumbbell-press']::text[],2.5::numeric,'variation'),
 ('bulgarian-split-squat',array['hamstrings']::text[],'high','low','low',array['dumbbell-reverse-lunge']::text[],'{}'::text[],array['dumbbell-step-up']::text[],2.5::numeric,'variation'),
 ('dumbbell-reverse-lunge',array['hamstrings']::text[],'moderate','low','low',array['reverse-lunge']::text[],array['barbell-reverse-lunge','bulgarian-split-squat']::text[],array['dumbbell-step-up']::text[],2.5::numeric,null::text),
 ('dumbbell-step-up',array['hamstrings']::text[],'moderate','low','low','{}'::text[],'{}'::text[],array['dumbbell-reverse-lunge','bulgarian-split-squat']::text[],2.5::numeric,null::text),
 ('incline-dumbbell-press',array['triceps']::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['dumbbell-bench-press','incline-barbell-bench-press']::text[],2.5::numeric,'variation'),
 ('barbell-bench-press',array['shoulders']::text[],'low','low','high','{}'::text[],'{}'::text[],array['dumbbell-bench-press','machine-chest-press','close-grip-bench-press','incline-barbell-bench-press']::text[],2.5::numeric,null::text),
 ('pull-up','{}'::text[],'low','low','moderate',array['assisted-pull-up']::text[],array['weighted-pull-up']::text[],array['chin-up','lat-pulldown']::text[],null::numeric,null::text),
 ('chin-up','{}'::text[],'low','low','moderate',array['assisted-pull-up']::text[],array['weighted-pull-up']::text[],array['pull-up','lat-pulldown']::text[],null::numeric,'variation'),
 ('lat-pulldown','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['pull-up','chin-up','assisted-pull-up','band-lat-pulldown','weighted-pull-up']::text[],2.5::numeric,null::text)
) as v(slug, secondary_muscles, knee_stress, back_stress, shoulder_stress, regressions,
  progressions, substitutes, load_step_kg, exercise_role)
where c.slug = v.slug;

-- Every catalog row is still reviewed, and every link still names another catalog exercise.
do $$
begin
  if exists (
    select 1 from public.exercise_catalog
    where knee_stress is null or back_stress is null or shoulder_stress is null
  ) then
    raise exception 'exercise_catalog: a catalog row has no joint stress rating';
  end if;
  if exists (
    select 1
    from public.exercise_catalog c,
      unnest(c.regressions || c.progressions || c.substitutes) link
    where not exists (select 1 from public.exercise_catalog t where t.slug = link)
  ) then
    raise exception 'exercise_catalog: a link names no catalog exercise';
  end if;
end;
$$;
