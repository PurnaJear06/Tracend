-- Exercise catalog v1: the only exercises an onboarding plan may use
-- (AI_SAFETY_SPEC §11). Global reference data, read-only to athletes. The rows
-- mirror supabase/functions/_shared/onboarding/catalog.ts; a Deno test keeps
-- them equal. Exercises are never deleted, only retired, so plans that use
-- one keep their reference.

create table public.exercise_catalog (
  slug text primary key check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) <= 80),
  name text not null check (length(name) between 1 and 120),
  movement_pattern text not null check (movement_pattern in (
    'squat','lunge','hinge','horizontal_push','vertical_push','horizontal_pull','vertical_pull',
    'core','calves','biceps','triceps','lateral_raise','rear_delts','chest_fly',
    'quads_isolation','hamstring_curl')),
  primary_muscles text[] not null check (
    cardinality(primary_muscles) between 1 and 4
    and primary_muscles <@ array['quads','glutes','hamstrings','chest','back','shoulders',
      'biceps','triceps','core','calves']::text[]),
  equipment_required text[] not null check (
    equipment_required <@ array['dumbbells','barbell','bench','cables','machines',
      'pull_up_bar','kettlebells','bands']::text[]),
  level text not null check (level in ('beginner','intermediate')),
  is_compound boolean not null,
  status text not null default 'active' check (status in ('active','retired')),
  retired_at timestamptz,
  catalog_version text not null default 'catalog-v1' check (length(catalog_version) between 1 and 32),
  check ((status = 'retired') = (retired_at is not null))
);

alter table public.exercise_catalog enable row level security;
alter table public.exercise_catalog force row level security;
create policy exercise_catalog_read on public.exercise_catalog for select to authenticated using (true);
revoke all on public.exercise_catalog from public, anon, authenticated;
grant select on public.exercise_catalog to authenticated;

insert into public.exercise_catalog(
  slug,name,movement_pattern,primary_muscles,equipment_required,level,is_compound
) values
 ('bodyweight-squat','Bodyweight squat','squat',array['quads','glutes']::text[],'{}'::text[],'beginner',true),
 ('split-squat','Split squat','lunge',array['quads','glutes']::text[],'{}'::text[],'beginner',true),
 ('reverse-lunge','Reverse lunge','lunge',array['quads','glutes']::text[],'{}'::text[],'beginner',true),
 ('glute-bridge','Glute bridge','hinge',array['glutes','hamstrings']::text[],'{}'::text[],'beginner',true),
 ('single-leg-hip-hinge','Single-leg hip hinge','hinge',array['hamstrings','glutes']::text[],'{}'::text[],'beginner',true),
 ('push-up','Push-up','horizontal_push',array['chest','triceps']::text[],'{}'::text[],'beginner',true),
 ('hands-elevated-push-up','Hands-elevated push-up','horizontal_push',array['chest','triceps']::text[],'{}'::text[],'beginner',true),
 ('pike-push-up','Pike push-up','vertical_push',array['shoulders','triceps']::text[],'{}'::text[],'intermediate',true),
 ('towel-doorway-row','Towel doorway row','horizontal_pull',array['back','biceps']::text[],'{}'::text[],'beginner',true),
 ('dead-bug','Dead bug','core',array['core']::text[],'{}'::text[],'beginner',false),
 ('bird-dog','Bird dog','core',array['core']::text[],'{}'::text[],'beginner',false),
 ('standing-calf-raise','Standing calf raise','calves',array['calves']::text[],'{}'::text[],'beginner',false),
 ('bench-dip','Bench dip','triceps',array['triceps']::text[],array['bench']::text[],'beginner',false),
 ('pull-up','Pull-up','vertical_pull',array['back','biceps']::text[],array['pull_up_bar']::text[],'intermediate',true),
 ('chin-up','Chin-up','vertical_pull',array['back','biceps']::text[],array['pull_up_bar']::text[],'intermediate',true),
 ('hanging-knee-raise','Hanging knee raise','core',array['core']::text[],array['pull_up_bar']::text[],'beginner',false),
 ('goblet-squat','Goblet squat','squat',array['quads','glutes']::text[],array['dumbbells']::text[],'beginner',true),
 ('dumbbell-romanian-deadlift','Dumbbell Romanian deadlift','hinge',array['hamstrings','glutes']::text[],array['dumbbells']::text[],'beginner',true),
 ('dumbbell-reverse-lunge','Dumbbell reverse lunge','lunge',array['quads','glutes']::text[],array['dumbbells']::text[],'beginner',true),
 ('dumbbell-step-up','Dumbbell step-up','lunge',array['quads','glutes']::text[],array['dumbbells','bench']::text[],'beginner',true),
 ('dumbbell-floor-press','Dumbbell floor press','horizontal_push',array['chest','triceps']::text[],array['dumbbells']::text[],'beginner',true),
 ('dumbbell-bench-press','Dumbbell bench press','horizontal_push',array['chest','triceps']::text[],array['dumbbells','bench']::text[],'beginner',true),
 ('incline-dumbbell-press','Incline dumbbell press','horizontal_push',array['chest','shoulders']::text[],array['dumbbells','bench']::text[],'beginner',true),
 ('one-arm-dumbbell-row','One-arm dumbbell row','horizontal_pull',array['back','biceps']::text[],array['dumbbells']::text[],'beginner',true),
 ('chest-supported-dumbbell-row','Chest-supported dumbbell row','horizontal_pull',array['back','biceps']::text[],array['dumbbells','bench']::text[],'beginner',true),
 ('dumbbell-shoulder-press','Dumbbell shoulder press','vertical_push',array['shoulders','triceps']::text[],array['dumbbells']::text[],'beginner',true),
 ('dumbbell-lateral-raise','Dumbbell lateral raise','lateral_raise',array['shoulders']::text[],array['dumbbells']::text[],'beginner',false),
 ('dumbbell-rear-delt-fly','Dumbbell rear delt fly','rear_delts',array['shoulders']::text[],array['dumbbells']::text[],'beginner',false),
 ('dumbbell-curl','Dumbbell curl','biceps',array['biceps']::text[],array['dumbbells']::text[],'beginner',false),
 ('dumbbell-overhead-triceps-extension','Dumbbell overhead triceps extension','triceps',array['triceps']::text[],array['dumbbells']::text[],'beginner',false),
 ('dumbbell-pullover','Dumbbell pullover','vertical_pull',array['back','chest']::text[],array['dumbbells','bench']::text[],'intermediate',false),
 ('dumbbell-hip-thrust','Dumbbell hip thrust','hinge',array['glutes','hamstrings']::text[],array['dumbbells','bench']::text[],'beginner',true),
 ('dumbbell-calf-raise','Dumbbell calf raise','calves',array['calves']::text[],array['dumbbells']::text[],'beginner',false),
 ('dumbbell-chest-fly','Dumbbell chest fly','chest_fly',array['chest']::text[],array['dumbbells','bench']::text[],'beginner',false),
 ('barbell-back-squat','Barbell back squat','squat',array['quads','glutes']::text[],array['barbell']::text[],'beginner',true),
 ('barbell-front-squat','Barbell front squat','squat',array['quads','glutes']::text[],array['barbell']::text[],'intermediate',true),
 ('barbell-romanian-deadlift','Barbell Romanian deadlift','hinge',array['hamstrings','glutes']::text[],array['barbell']::text[],'beginner',true),
 ('barbell-deadlift','Barbell deadlift','hinge',array['back','hamstrings','glutes']::text[],array['barbell']::text[],'intermediate',true),
 ('barbell-bench-press','Barbell bench press','horizontal_push',array['chest','triceps']::text[],array['barbell','bench']::text[],'beginner',true),
 ('barbell-overhead-press','Barbell overhead press','vertical_push',array['shoulders','triceps']::text[],array['barbell']::text[],'beginner',true),
 ('barbell-row','Barbell row','horizontal_pull',array['back','biceps']::text[],array['barbell']::text[],'beginner',true),
 ('barbell-hip-thrust','Barbell hip thrust','hinge',array['glutes','hamstrings']::text[],array['barbell','bench']::text[],'beginner',true),
 ('barbell-reverse-lunge','Barbell reverse lunge','lunge',array['quads','glutes']::text[],array['barbell']::text[],'intermediate',true),
 ('barbell-curl','Barbell curl','biceps',array['biceps']::text[],array['barbell']::text[],'beginner',false),
 ('lat-pulldown','Lat pulldown','vertical_pull',array['back','biceps']::text[],array['cables']::text[],'beginner',true),
 ('seated-cable-row','Seated cable row','horizontal_pull',array['back','biceps']::text[],array['cables']::text[],'beginner',true),
 ('cable-chest-fly','Cable chest fly','chest_fly',array['chest']::text[],array['cables']::text[],'beginner',false),
 ('cable-lateral-raise','Cable lateral raise','lateral_raise',array['shoulders']::text[],array['cables']::text[],'beginner',false),
 ('face-pull','Face pull','rear_delts',array['shoulders']::text[],array['cables']::text[],'beginner',false),
 ('cable-triceps-pressdown','Cable triceps pressdown','triceps',array['triceps']::text[],array['cables']::text[],'beginner',false),
 ('cable-curl','Cable curl','biceps',array['biceps']::text[],array['cables']::text[],'beginner',false),
 ('cable-crunch','Cable crunch','core',array['core']::text[],array['cables']::text[],'beginner',false),
 ('cable-pull-through','Cable pull-through','hinge',array['glutes','hamstrings']::text[],array['cables']::text[],'beginner',true),
 ('leg-press','Leg press','squat',array['quads','glutes']::text[],array['machines']::text[],'beginner',true),
 ('leg-extension','Leg extension','quads_isolation',array['quads']::text[],array['machines']::text[],'beginner',false),
 ('lying-leg-curl','Lying leg curl','hamstring_curl',array['hamstrings']::text[],array['machines']::text[],'beginner',false),
 ('machine-chest-press','Machine chest press','horizontal_push',array['chest','triceps']::text[],array['machines']::text[],'beginner',true),
 ('machine-shoulder-press','Machine shoulder press','vertical_push',array['shoulders','triceps']::text[],array['machines']::text[],'beginner',true),
 ('machine-row','Chest-supported machine row','horizontal_pull',array['back','biceps']::text[],array['machines']::text[],'beginner',true),
 ('assisted-pull-up','Assisted pull-up','vertical_pull',array['back','biceps']::text[],array['machines']::text[],'beginner',true),
 ('pec-deck','Pec deck','chest_fly',array['chest']::text[],array['machines']::text[],'beginner',false),
 ('seated-calf-raise','Seated calf raise','calves',array['calves']::text[],array['machines']::text[],'beginner',false),
 ('kettlebell-swing','Kettlebell swing','hinge',array['glutes','hamstrings']::text[],array['kettlebells']::text[],'intermediate',true),
 ('kettlebell-goblet-squat','Kettlebell goblet squat','squat',array['quads','glutes']::text[],array['kettlebells']::text[],'beginner',true),
 ('kettlebell-press','Kettlebell press','vertical_push',array['shoulders','triceps']::text[],array['kettlebells']::text[],'beginner',true),
 ('kettlebell-row','Kettlebell row','horizontal_pull',array['back','biceps']::text[],array['kettlebells']::text[],'beginner',true),
 ('band-row','Band row','horizontal_pull',array['back','biceps']::text[],array['bands']::text[],'beginner',true),
 ('band-lat-pulldown','Band lat pulldown','vertical_pull',array['back','biceps']::text[],array['bands']::text[],'beginner',true),
 ('band-pull-apart','Band pull-apart','rear_delts',array['shoulders']::text[],array['bands']::text[],'beginner',false),
 ('band-pallof-press','Band Pallof press','core',array['core']::text[],array['bands']::text[],'beginner',false),
 ('band-curl','Band curl','biceps',array['biceps']::text[],array['bands']::text[],'beginner',false),
 ('band-triceps-pushdown','Band triceps pushdown','triceps',array['triceps']::text[],array['bands']::text[],'beginner',false);

-- Planned exercises from an onboarding plan record their catalog entry.
-- Existing rows (generic seed, imported plan) have none.
alter table public.planned_exercises
  add column exercise_slug text references public.exercise_catalog(slug);
