-- Exercise catalog v2 (B1): the coaching data later chunks need, mirrored from
-- supabase/functions/_shared/onboarding/catalog_v2.ts; catalog_v2_test.ts keeps
-- the two equal. Additive only: every new column is nullable or defaulted, no
-- existing column or row identity changes, and no current reader selects the new
-- columns, so today's plans, hub and history are unchanged.
--
-- secondary_muscles: muscles trained indirectly (never a primary muscle).
-- knee_stress, back_stress, shoulder_stress: low, moderate or high, rated with
--   the method in _shared/training/standard/joint_stress.ts; for choosing swaps
--   and range limits, never for diagnosis.
-- regressions, progressions: easier and harder forms of the same pattern.
-- substitutes: alternatives of similar difficulty (same pattern or target).
-- load_step_kg: the smallest load increase of the loading implement (per
--   dumbbell or kettlebell); null when the exercise progresses by reps.
-- exercise_role: B0's ranking role (variation or regression; null = standard).

alter table public.exercise_catalog
  add column secondary_muscles text[] not null default '{}'::text[] check (
    secondary_muscles <@ array['quads','glutes','hamstrings','chest','back','shoulders',
      'biceps','triceps','core','calves']::text[]
    and not (secondary_muscles && primary_muscles)),
  add column knee_stress text check (knee_stress in ('low','moderate','high')),
  add column back_stress text check (back_stress in ('low','moderate','high')),
  add column shoulder_stress text check (shoulder_stress in ('low','moderate','high')),
  add column regressions text[] not null default '{}'::text[]
    check (cardinality(regressions) <= 8 and not (slug = any(regressions))),
  add column progressions text[] not null default '{}'::text[]
    check (cardinality(progressions) <= 8 and not (slug = any(progressions))),
  add column substitutes text[] not null default '{}'::text[]
    check (cardinality(substitutes) <= 8 and not (slug = any(substitutes))),
  add column load_step_kg numeric(4,2) check (load_step_kg > 0 and load_step_kg <= 20),
  add column exercise_role text check (exercise_role in ('variation','regression'));

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
 ('bodyweight-squat',array['core']::text[],'moderate','low','low','{}'::text[],array['goblet-squat','kettlebell-goblet-squat']::text[],array['split-squat']::text[],null::numeric,null::text),
 ('split-squat',array['hamstrings']::text[],'moderate','low','low','{}'::text[],array['reverse-lunge']::text[],array['bodyweight-squat']::text[],null::numeric,null::text),
 ('reverse-lunge',array['hamstrings']::text[],'moderate','low','low',array['split-squat']::text[],array['dumbbell-reverse-lunge']::text[],'{}'::text[],null::numeric,null::text),
 ('glute-bridge','{}'::text[],'low','low','low','{}'::text[],array['dumbbell-hip-thrust']::text[],array['single-leg-hip-hinge']::text[],null::numeric,null::text),
 ('single-leg-hip-hinge',array['core']::text[],'low','low','low','{}'::text[],array['dumbbell-romanian-deadlift']::text[],array['glute-bridge']::text[],null::numeric,null::text),
 ('push-up',array['shoulders','core']::text[],'low','low','moderate',array['hands-elevated-push-up']::text[],'{}'::text[],array['dumbbell-floor-press','machine-chest-press']::text[],null::numeric,null::text),
 ('hands-elevated-push-up',array['shoulders','core']::text[],'low','low','low','{}'::text[],array['push-up']::text[],'{}'::text[],null::numeric,'regression'),
 ('pike-push-up','{}'::text[],'low','low','high','{}'::text[],'{}'::text[],array['dumbbell-shoulder-press']::text[],null::numeric,null::text),
 ('towel-doorway-row',array['shoulders']::text[],'low','low','low','{}'::text[],'{}'::text[],array['band-row']::text[],null::numeric,null::text),
 ('dead-bug','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['bird-dog','band-pallof-press']::text[],null::numeric,null::text),
 ('bird-dog',array['glutes']::text[],'low','low','low','{}'::text[],'{}'::text[],array['dead-bug']::text[],null::numeric,null::text),
 ('standing-calf-raise','{}'::text[],'low','low','low','{}'::text[],array['dumbbell-calf-raise']::text[],array['seated-calf-raise']::text[],null::numeric,null::text),
 ('bench-dip',array['chest','shoulders']::text[],'low','low','high','{}'::text[],'{}'::text[],array['cable-triceps-pressdown','band-triceps-pushdown']::text[],null::numeric,null::text),
 ('pull-up','{}'::text[],'low','low','moderate',array['assisted-pull-up']::text[],'{}'::text[],array['chin-up','lat-pulldown']::text[],null::numeric,null::text),
 ('chin-up','{}'::text[],'low','low','moderate',array['assisted-pull-up']::text[],'{}'::text[],array['pull-up','lat-pulldown']::text[],null::numeric,'variation'),
 ('hanging-knee-raise','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['cable-crunch']::text[],null::numeric,null::text),
 ('goblet-squat',array['core']::text[],'moderate','low','low',array['bodyweight-squat']::text[],array['barbell-back-squat','barbell-front-squat']::text[],array['kettlebell-goblet-squat','leg-press']::text[],2.5::numeric,null::text),
 ('dumbbell-romanian-deadlift',array['back']::text[],'low','moderate','low',array['single-leg-hip-hinge']::text[],array['barbell-romanian-deadlift']::text[],array['cable-pull-through']::text[],2.5::numeric,null::text),
 ('dumbbell-reverse-lunge',array['hamstrings']::text[],'moderate','low','low',array['reverse-lunge']::text[],array['barbell-reverse-lunge']::text[],array['dumbbell-step-up']::text[],2.5::numeric,null::text),
 ('dumbbell-step-up',array['hamstrings']::text[],'moderate','low','low','{}'::text[],'{}'::text[],array['dumbbell-reverse-lunge']::text[],2.5::numeric,null::text),
 ('dumbbell-floor-press',array['shoulders']::text[],'low','low','low','{}'::text[],array['dumbbell-bench-press']::text[],array['push-up']::text[],2.5::numeric,'regression'),
 ('dumbbell-bench-press',array['shoulders']::text[],'low','low','moderate',array['dumbbell-floor-press']::text[],'{}'::text[],array['barbell-bench-press','machine-chest-press','incline-dumbbell-press']::text[],2.5::numeric,null::text),
 ('incline-dumbbell-press',array['triceps']::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['dumbbell-bench-press']::text[],2.5::numeric,'variation'),
 ('one-arm-dumbbell-row',array['shoulders']::text[],'low','low','low','{}'::text[],'{}'::text[],array['chest-supported-dumbbell-row','kettlebell-row','seated-cable-row']::text[],2.5::numeric,null::text),
 ('chest-supported-dumbbell-row',array['shoulders']::text[],'low','low','low','{}'::text[],'{}'::text[],array['one-arm-dumbbell-row','machine-row','barbell-row']::text[],2.5::numeric,null::text),
 ('dumbbell-shoulder-press','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['kettlebell-press','machine-shoulder-press','barbell-overhead-press','pike-push-up']::text[],2.5::numeric,null::text),
 ('dumbbell-lateral-raise','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['cable-lateral-raise']::text[],2.5::numeric,null::text),
 ('dumbbell-rear-delt-fly',array['back']::text[],'low','low','low','{}'::text[],'{}'::text[],array['face-pull','band-pull-apart']::text[],2.5::numeric,null::text),
 ('dumbbell-curl','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['barbell-curl','cable-curl','band-curl']::text[],2.5::numeric,null::text),
 ('dumbbell-overhead-triceps-extension','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['cable-triceps-pressdown']::text[],2.5::numeric,null::text),
 ('dumbbell-pullover',array['triceps']::text[],'low','low','high','{}'::text[],'{}'::text[],'{}'::text[],2.5::numeric,null::text),
 ('dumbbell-hip-thrust','{}'::text[],'low','low','low',array['glute-bridge']::text[],array['barbell-hip-thrust']::text[],array['cable-pull-through']::text[],2.5::numeric,'variation'),
 ('dumbbell-calf-raise','{}'::text[],'low','low','low',array['standing-calf-raise']::text[],'{}'::text[],array['seated-calf-raise']::text[],2.5::numeric,null::text),
 ('dumbbell-chest-fly',array['shoulders']::text[],'low','low','high','{}'::text[],'{}'::text[],array['cable-chest-fly','pec-deck']::text[],2.5::numeric,null::text),
 ('barbell-back-squat',array['core']::text[],'high','high','moderate',array['goblet-squat','kettlebell-goblet-squat']::text[],'{}'::text[],array['barbell-front-squat','leg-press']::text[],2.5::numeric,null::text),
 ('barbell-front-squat',array['core']::text[],'high','moderate','moderate',array['goblet-squat']::text[],'{}'::text[],array['barbell-back-squat','leg-press']::text[],2.5::numeric,'variation'),
 ('barbell-romanian-deadlift',array['back']::text[],'low','high','low',array['dumbbell-romanian-deadlift']::text[],'{}'::text[],array['barbell-deadlift']::text[],2.5::numeric,null::text),
 ('barbell-deadlift',array['quads','core']::text[],'moderate','high','low','{}'::text[],'{}'::text[],array['barbell-romanian-deadlift']::text[],2.5::numeric,null::text),
 ('barbell-bench-press',array['shoulders']::text[],'low','low','high','{}'::text[],'{}'::text[],array['dumbbell-bench-press','machine-chest-press']::text[],2.5::numeric,null::text),
 ('barbell-overhead-press',array['core']::text[],'low','moderate','high','{}'::text[],'{}'::text[],array['dumbbell-shoulder-press','machine-shoulder-press']::text[],2.5::numeric,null::text),
 ('barbell-row',array['shoulders']::text[],'low','high','low','{}'::text[],'{}'::text[],array['chest-supported-dumbbell-row','machine-row','seated-cable-row']::text[],2.5::numeric,null::text),
 ('barbell-hip-thrust','{}'::text[],'low','low','low',array['dumbbell-hip-thrust']::text[],'{}'::text[],array['cable-pull-through']::text[],2.5::numeric,'variation'),
 ('barbell-reverse-lunge',array['hamstrings']::text[],'moderate','moderate','moderate',array['dumbbell-reverse-lunge']::text[],'{}'::text[],'{}'::text[],2.5::numeric,null::text),
 ('barbell-curl','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['dumbbell-curl','cable-curl']::text[],2.5::numeric,null::text),
 ('lat-pulldown','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['pull-up','chin-up','assisted-pull-up','band-lat-pulldown']::text[],2.5::numeric,null::text),
 ('seated-cable-row',array['shoulders']::text[],'low','low','low','{}'::text[],'{}'::text[],array['one-arm-dumbbell-row','barbell-row','machine-row','band-row']::text[],2.5::numeric,null::text),
 ('cable-chest-fly',array['shoulders']::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['dumbbell-chest-fly','pec-deck']::text[],2.5::numeric,null::text),
 ('cable-lateral-raise','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['dumbbell-lateral-raise']::text[],2.5::numeric,null::text),
 ('face-pull',array['back']::text[],'low','low','low','{}'::text[],'{}'::text[],array['dumbbell-rear-delt-fly','band-pull-apart']::text[],2.5::numeric,null::text),
 ('cable-triceps-pressdown','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['bench-dip','dumbbell-overhead-triceps-extension','band-triceps-pushdown']::text[],2.5::numeric,null::text),
 ('cable-curl','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['dumbbell-curl','barbell-curl','band-curl']::text[],2.5::numeric,null::text),
 ('cable-crunch','{}'::text[],'low','moderate','low','{}'::text[],'{}'::text[],array['hanging-knee-raise']::text[],2.5::numeric,null::text),
 ('cable-pull-through','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['dumbbell-romanian-deadlift','dumbbell-hip-thrust','barbell-hip-thrust','kettlebell-swing']::text[],2.5::numeric,null::text),
 ('leg-press','{}'::text[],'high','moderate','low','{}'::text[],'{}'::text[],array['goblet-squat','kettlebell-goblet-squat','barbell-back-squat','barbell-front-squat']::text[],5::numeric,null::text),
 ('leg-extension','{}'::text[],'moderate','low','low','{}'::text[],'{}'::text[],'{}'::text[],5::numeric,null::text),
 ('lying-leg-curl',array['calves']::text[],'low','low','low','{}'::text[],'{}'::text[],'{}'::text[],5::numeric,null::text),
 ('machine-chest-press',array['shoulders']::text[],'low','low','low','{}'::text[],'{}'::text[],array['push-up','dumbbell-bench-press','barbell-bench-press']::text[],5::numeric,null::text),
 ('machine-shoulder-press','{}'::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['dumbbell-shoulder-press','barbell-overhead-press','kettlebell-press']::text[],5::numeric,null::text),
 ('machine-row',array['shoulders']::text[],'low','low','low','{}'::text[],'{}'::text[],array['chest-supported-dumbbell-row','barbell-row','seated-cable-row']::text[],5::numeric,null::text),
 ('assisted-pull-up','{}'::text[],'low','low','moderate','{}'::text[],array['pull-up','chin-up']::text[],array['lat-pulldown']::text[],5::numeric,'regression'),
 ('pec-deck',array['shoulders']::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['dumbbell-chest-fly','cable-chest-fly']::text[],5::numeric,null::text),
 ('seated-calf-raise','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['standing-calf-raise','dumbbell-calf-raise']::text[],5::numeric,null::text),
 ('kettlebell-swing',array['back','core']::text[],'low','moderate','low','{}'::text[],'{}'::text[],array['cable-pull-through']::text[],4::numeric,null::text),
 ('kettlebell-goblet-squat',array['core']::text[],'moderate','low','low',array['bodyweight-squat']::text[],array['barbell-back-squat']::text[],array['goblet-squat','leg-press']::text[],4::numeric,null::text),
 ('kettlebell-press',array['core']::text[],'low','low','moderate','{}'::text[],'{}'::text[],array['dumbbell-shoulder-press','machine-shoulder-press']::text[],4::numeric,null::text),
 ('kettlebell-row',array['shoulders']::text[],'low','low','low','{}'::text[],'{}'::text[],array['one-arm-dumbbell-row']::text[],4::numeric,null::text),
 ('band-row',array['shoulders']::text[],'low','low','low','{}'::text[],'{}'::text[],array['towel-doorway-row','seated-cable-row']::text[],null::numeric,null::text),
 ('band-lat-pulldown','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['lat-pulldown']::text[],null::numeric,null::text),
 ('band-pull-apart',array['back']::text[],'low','low','low','{}'::text[],'{}'::text[],array['dumbbell-rear-delt-fly','face-pull']::text[],null::numeric,null::text),
 ('band-pallof-press','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['dead-bug']::text[],null::numeric,null::text),
 ('band-curl','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['dumbbell-curl','cable-curl']::text[],null::numeric,null::text),
 ('band-triceps-pushdown','{}'::text[],'low','low','low','{}'::text[],'{}'::text[],array['bench-dip','cable-triceps-pressdown']::text[],null::numeric,null::text)
) as v(slug, secondary_muscles, knee_stress, back_stress, shoulder_stress, regressions,
  progressions, substitutes, load_step_kg, exercise_role)
where c.slug = v.slug;

-- Every catalog row is reviewed, and every link names another catalog exercise.
-- Rows change only by migration, so this check and pgTAP guard the links.
do $$
begin
  if exists (
    select 1 from public.exercise_catalog
    where knee_stress is null or back_stress is null or shoulder_stress is null
  ) then
    raise exception 'exercise_catalog v2: a catalog row has no joint stress rating';
  end if;
  if exists (
    select 1
    from public.exercise_catalog c,
      unnest(c.regressions || c.progressions || c.substitutes) link
    where not exists (select 1 from public.exercise_catalog t where t.slug = link)
  ) then
    raise exception 'exercise_catalog v2: a link names no catalog exercise';
  end if;
end;
$$;
