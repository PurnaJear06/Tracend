begin;
select no_plan();

-- B5-1: the swap a joint rule picks and the changes a joint state makes. Worked examples (hand-derived
-- from the catalog), then sweeps: every catalog exercise x joint x equipment set x level x movements to
-- avoid x stress ceiling for the swap, and every exercise of the catalog under every combination of
-- states for the three joints for the changes. A swap that allows an equal stress, or ignores the
-- athlete's equipment, is shown to fail the sweep.

-- Worked examples --------------------------------------------------------------------------------------------

create function pg_temp.all_equipment() returns text[] language sql as $$
  select array['dumbbells', 'barbell', 'bench', 'cables', 'machines', 'pull_up_bar', 'kettlebells', 'bands'];
$$;

select is(private.joint_swap('barbell-bench-press', 'shoulder', 'low', pg_temp.all_equipment(), 'intermediate',
    null, null),
  '{"slug": "machine-chest-press", "name": "Machine chest press"}'::jsonb,
  'the bench press, shoulder, a gentler substitute first: the machine press');
select is(private.joint_swap('barbell-bench-press', 'shoulder', 'low', array['dumbbells', 'bench'],
    'intermediate', null, null),
  '{"slug": "dumbbell-floor-press", "name": "Dumbbell floor press"}'::jsonb,
  'with dumbbells and a bench only: the same pattern, a regression, by slug among equals');
select is(private.joint_swap('barbell-bench-press', 'shoulder', 'low', '{}', 'intermediate', null, null),
  '{"slug": "hands-elevated-push-up", "name": "Hands-elevated push-up"}'::jsonb,
  'with no equipment: the hands-elevated push-up');
select is(private.joint_swap('barbell-bench-press', 'shoulder', 'low', pg_temp.all_equipment(), 'intermediate',
    null, array['machine-chest-press']),
  '{"slug": "dumbbell-floor-press", "name": "Dumbbell floor press"}'::jsonb,
  'an exercise already in the session is never offered');
select is(private.joint_swap('barbell-bench-press', 'shoulder', 'low', pg_temp.all_equipment(), 'intermediate',
    array['horizontal_push'], null),
  '{"slug": "band-triceps-pushdown", "name": "Band triceps pushdown"}'::jsonb,
  'a movement the athlete avoids is never offered: the next that shares a muscle');
select is(private.joint_swap('barbell-front-squat', 'knee', 'moderate', '{}', 'intermediate', null, null),
  '{"slug": "bodyweight-squat", "name": "Bodyweight squat"}'::jsonb,
  'a limited knee with no equipment: the bodyweight squat, as gentle as moderate allows');
select is(private.joint_swap('barbell-deadlift', 'back', 'moderate', pg_temp.all_equipment(), 'beginner',
    null, null),
  '{"slug": "cable-pull-through", "name": "Cable pull-through"}'::jsonb,
  'the deadlift for a sore back: the gentlest hinge, standard form first, by slug');
select is(private.joint_swap('barbell-back-squat', 'knee', 'moderate', pg_temp.all_equipment(), 'intermediate',
    null, null),
  '{"slug": "goblet-squat", "name": "Goblet squat"}'::jsonb,
  'the back squat for a limited knee: its first regression');
select is(private.joint_swap('standing-calf-raise', 'knee', 'low', pg_temp.all_equipment(), 'advanced', null, null),
  null::jsonb, 'nothing is gentler than a low-stress exercise');
select is(private.joint_swap(null, 'knee', 'low', pg_temp.all_equipment(), 'advanced', null, null), null::jsonb,
  'an exercise with no catalog entry has nothing to anchor a swap on');
select is(private.joint_swap('made-up-lift', 'knee', 'low', pg_temp.all_equipment(), 'advanced', null, null),
  null::jsonb, 'nor an unknown one');
select is(private.joint_swap('barbell-bench-press', 'shoulder', null, pg_temp.all_equipment(), 'advanced', null, null),
  null::jsonb, 'no ceiling, no swap');
select is(private.joint_swap('barbell-bench-press', 'shoulder', 'low', pg_temp.all_equipment(), null, null, null),
  '{"slug": "machine-chest-press", "name": "Machine chest press"}'::jsonb,
  'an athlete with no recorded level is treated as a beginner, never above');
select is(private.joint_swap('barbell-bench-press', 'shoulder', 'low', pg_temp.all_equipment(), 'advanced', null,
    null, '{"knee": "low", "back": "low"}'),
  '{"slug": "machine-chest-press", "name": "Machine chest press"}'::jsonb, 'a cap the candidate meets changes nothing');
select is(private.joint_swap('barbell-front-squat', 'knee', 'moderate', pg_temp.all_equipment(), 'advanced', null,
    null, '{"back": "low", "shoulder": "low"}'),
  '{"slug": "goblet-squat", "name": "Goblet squat"}'::jsonb, 'goblet squat is low on the back and shoulder');
select is(private.joint_swap('barbell-front-squat', 'knee', 'moderate', pg_temp.all_equipment(), 'advanced', null,
    array['goblet-squat'], '{"back": "low"}'),
  '{"slug": "bodyweight-squat", "name": "Bodyweight squat"}'::jsonb,
  'excluding the regression gives the next in order: the same pattern, by slug');
select is(private.joint_swap('barbell-deadlift', 'knee', 'moderate', pg_temp.all_equipment(), 'advanced', null,
    null),
  '{"slug": "barbell-romanian-deadlift", "name": "Barbell Romanian deadlift"}'::jsonb,
  'the deadlift for a limited knee: the Romanian deadlift, low on the knee (and as hard on the back as the original)');
select is(private.joint_swap('barbell-deadlift', 'knee', 'moderate', pg_temp.all_equipment(), 'advanced', null,
    null, '{"back": "low"}'),
  '{"slug": "cable-pull-through", "name": "Cable pull-through"}'::jsonb,
  'with a sore back too, the cap on the back skips it for a hinge that is low on the back');

-- Range cues ------------------------------------------------------------------------------------------------------

select is(private.range_note_code('knee', 'squat'), 'knee_squat_depth', 'knee and squat');
select is(private.range_note_code('back', 'hinge'), 'back_hinge_range', 'back and hinge');
select is(private.range_note_code('shoulder', 'horizontal_push'), 'shoulder_press_depth', 'shoulder and a press');
select is(private.range_note_code('shoulder', 'calves'), 'generic_pain_free', 'any other pair gets the generic cue');
select is(private.range_note_code('knee', null), 'generic_pain_free', 'and so does an unknown pattern');

-- The swap sweep -----------------------------------------------------------------------------------------------------

create function pg_temp.rank_at(c public.exercise_catalog, p_joint text) returns integer language sql as $$
  select private.stress_rank(case p_joint when 'knee' then c.knee_stress when 'back' then c.back_stress
    else c.shoulder_stress end);
$$;

-- Whether r is an acceptable swap for o on a joint with this ceiling, equipment, level and avoided patterns.
create function pg_temp.acceptable(o public.exercise_catalog, r public.exercise_catalog, p_joint text,
  p_max text, p_eq text[], p_level text, p_avoid text[]) returns boolean language sql as $$
  select r.slug <> o.slug and r.status = 'active'
    and pg_temp.rank_at(r, p_joint) < pg_temp.rank_at(o, p_joint)
    and pg_temp.rank_at(r, p_joint) <= private.stress_rank(p_max)
    and private.stress_rank(r.knee_stress) <= private.stress_rank(o.knee_stress)
    and private.stress_rank(r.back_stress) <= private.stress_rank(o.back_stress)
    and private.stress_rank(r.shoulder_stress) <= private.stress_rank(o.shoulder_stress)
    and r.equipment_required <@ p_eq
    and private.level_rank(r.level) <= private.level_rank(p_level)
    and (p_avoid is null or r.movement_pattern <> all (p_avoid))
    and (r.slug = any(o.substitutes) or r.slug = any(o.regressions)
      or r.movement_pattern = o.movement_pattern or r.primary_muscles && o.primary_muscles);
$$;

create temporary table sweep as
select c.slug, j.joint, e.eq, l.level, a.avoid, m.max_stress,
  private.joint_swap(c.slug, j.joint, m.max_stress, e.eq, l.level, a.avoid, null) as result
from public.exercise_catalog c
cross join (values ('knee'), ('back'), ('shoulder')) j(joint)
cross join (values ('{}'::text[]), (array['dumbbells']), (array['dumbbells', 'bench']),
  (array['barbell', 'bench']), (array['machines']), (array['cables', 'bands']),
  (array['dumbbells', 'barbell', 'bench', 'cables', 'machines', 'pull_up_bar', 'kettlebells', 'bands'])) e(eq)
cross join (values ('beginner'), ('intermediate'), ('advanced')) l(level)
cross join lateral (values (null::text[]), (array[c.movement_pattern])) a(avoid)
cross join (values ('low'), ('moderate')) m(max_stress)
where c.status = 'active';

select cmp_ok((select count(*) from sweep), '>', 10000::bigint, 'the sweep covers more than ten thousand cases');
select is((select count(*) from sweep s join public.exercise_catalog o on o.slug = s.slug
    join public.exercise_catalog r on r.slug = s.result ->> 'slug'
    where not pg_temp.acceptable(o, r, s.joint, s.max_stress, s.eq, s.level, s.avoid)
      or s.result ->> 'name' <> r.name), 0::bigint,
  'every swap is gentler on the joint, within the ceiling, never harsher elsewhere, within equipment and level, '
  'a movement the athlete does not avoid, related to the original and not the original');
select is((select count(*) from sweep s join public.exercise_catalog o on o.slug = s.slug
    where s.result is null and exists (select 1 from public.exercise_catalog r
      where pg_temp.acceptable(o, r, s.joint, s.max_stress, s.eq, s.level, s.avoid))), 0::bigint,
  'and when there is none the catalog has no acceptable exercise at all');
select is((select count(*) from sweep s join public.exercise_catalog o on o.slug = s.slug
    join public.exercise_catalog r on r.slug = s.result ->> 'slug'
    where s.max_stress = 'moderate' and o.slug is not null
      and pg_temp.rank_at(o, s.joint) = 3 and pg_temp.rank_at(r, s.joint) = 3), 0::bigint,
  'a high-stress exercise is never swapped for another high-stress one');
select is((select count(*) from sweep s join public.exercise_catalog o on o.slug = s.slug
    where o.knee_stress is null or o.back_stress is null or o.shoulder_stress is null), 0::bigint,
  'every catalog exercise is rated on every joint, so none is unrated in the sweep');
select cmp_ok((select count(*) from sweep where result is not null), '>', 1000::bigint,
  'and swaps are found often enough for the sweep to mean something');

-- The sweep catches a weaker rule: the same query with a copy of the function that allows an equal stress, or
-- ignores the athlete's equipment, produces results the checks above refuse.
create function pg_temp.mutant_swap(p_slug text, p_joint text, p_max_stress text, p_equipment text[],
  p_level text, p_avoid text[], p_equal boolean, p_ignore_equipment boolean) returns jsonb language sql as $$
  with o as (select c.* from public.exercise_catalog c where c.slug = p_slug),
  cand as (
    select c.slug, c.name,
      case when c.slug = any(o.substitutes) then 1 when c.slug = any(o.regressions) then 2
        when c.movement_pattern = o.movement_pattern then 3
        when c.primary_muscles && o.primary_muscles then 4 end as tier,
      private.stress_rank(case p_joint when 'knee' then c.knee_stress when 'back' then c.back_stress
        else c.shoulder_stress end) as joint_rank,
      private.stress_rank(case p_joint when 'knee' then o.knee_stress when 'back' then o.back_stress
        else o.shoulder_stress end) as original_rank,
      private.stress_rank(c.knee_stress) <= private.stress_rank(o.knee_stress)
        and private.stress_rank(c.back_stress) <= private.stress_rank(o.back_stress)
        and private.stress_rank(c.shoulder_stress) <= private.stress_rank(o.shoulder_stress) as never_harsher,
      c.is_compound = o.is_compound as same_compound,
      case c.exercise_role when 'variation' then 1 when 'regression' then 2 else 0 end as role_order
    from public.exercise_catalog c cross join o
    where c.status = 'active' and c.slug <> o.slug
      and (p_ignore_equipment or c.equipment_required <@ coalesce(p_equipment, '{}'::text[]))
      and private.level_rank(c.level) <= private.level_rank(coalesce(p_level, 'beginner'))
      and (p_avoid is null or c.movement_pattern <> all (p_avoid))
  )
  select jsonb_build_object('slug', slug, 'name', name) from cand
  where tier is not null and joint_rank <= private.stress_rank(p_max_stress)
    and (joint_rank < original_rank or (p_equal and joint_rank <= original_rank))
    and never_harsher
  order by tier, joint_rank, same_compound desc, role_order, slug limit 1;
$$;

select is((select count(*) from sweep s join public.exercise_catalog o on o.slug = s.slug
    cross join lateral (select pg_temp.mutant_swap(s.slug, s.joint, s.max_stress, s.eq, s.level, s.avoid,
      false, false) as result) mine
    where mine.result is distinct from s.result), 0::bigint,
  'an independent reimplementation of the rule agrees with the function on every case');
select cmp_ok((select count(*) from sweep s join public.exercise_catalog o on o.slug = s.slug
    cross join lateral (select pg_temp.mutant_swap(s.slug, s.joint, s.max_stress, s.eq, s.level, s.avoid,
      true, false) as result) mutant
    join public.exercise_catalog r on r.slug = mutant.result ->> 'slug'
    where not pg_temp.acceptable(o, r, s.joint, s.max_stress, s.eq, s.level, s.avoid)), '>', 0::bigint,
  'a rule that allows an equal stress produces swaps the sweep refuses');
select cmp_ok((select count(*) from sweep s join public.exercise_catalog o on o.slug = s.slug
    cross join lateral (select pg_temp.mutant_swap(s.slug, s.joint, s.max_stress, s.eq, s.level, s.avoid,
      false, true) as result) mutant
    join public.exercise_catalog r on r.slug = mutant.result ->> 'slug'
    where not pg_temp.acceptable(o, r, s.joint, s.max_stress, s.eq, s.level, s.avoid)), '>', 0::bigint,
  'and one that ignores the athlete''s equipment does too');

-- The changes sweep: every exercise of the catalog under every combination of states --------------------------

insert into auth.users(id, role) values ('b5900000-0000-4000-8000-000000000001', 'authenticated');

do $$
declare
  u constant uuid := 'b5900000-0000-4000-8000-000000000001';
  pl uuid := gen_random_uuid();
  v uuid := gen_random_uuid();
  i integer;
  wo uuid;
begin
  insert into public.user_profiles(user_id, experience_level, equipment)
  values (u, 'advanced', array['dumbbells', 'barbell', 'bench', 'cables', 'machines', 'pull_up_bar',
    'kettlebells', 'bands']);
  insert into public.training_plans(id, user_id, title, source) values (pl, u, 'Everything', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, u, pl, 1, 'active', 6, 3, '{}', 'Approved', now(), current_date);
  for i in 1..3 loop
    wo := gen_random_uuid();
    insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
      preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
    values (wo, u, v, i, 'Day ' || i, 'Everything', i, 90, 'Warm up', 'Cool down');
    insert into public.planned_exercises(user_id, planned_workout_id, exercise_order,
      display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
    select u, wo, (x.rn - 1) % 30 + 1, x.name, 3, 8, 12, case when x.rn % 2 = 0 then 8 else null end, 60, x.slug
    from (select c.slug, c.name, row_number() over (order by c.slug) as rn
      from public.exercise_catalog c where c.status = 'active') x
    where (x.rn - 1) / 30 = i - 1;
  end loop;
end $$;

select cmp_ok((select count(*) from public.planned_exercises where user_id = 'b5900000-0000-4000-8000-000000000001'),
  '=', (select count(*) from public.exercise_catalog where status = 'active'),
  'the test plan holds every active catalog exercise exactly once');

create temporary table combos as
select row_number() over () as cid, k.s as knee, b.s as back, h.s as shoulder
from (values ('none'), ('watch'), ('limited'), ('held')) k(s),
  (values ('none'), ('watch'), ('limited'), ('held')) b(s),
  (values ('none'), ('watch'), ('limited'), ('held')) h(s);

create temporary table chg as
select cb.cid, wo.id as wid, e as entry
from combos cb
cross join (select w.id from public.planned_workouts w
  where w.user_id = 'b5900000-0000-4000-8000-000000000001') wo
cross join lateral jsonb_array_elements(private.joint_changes('b5900000-0000-4000-8000-000000000001', wo.id,
  (select coalesce(jsonb_agg(jsonb_build_object('area', v.a, 'state', v.st)), '[]'::jsonb)
   from (values ('knee', cb.knee), ('back', cb.back), ('shoulder', cb.shoulder)) v(a, st)
   where v.st <> 'none'), '[]'::jsonb)) e;

-- The swaps offered to the in-workout pain chip are always low stress on the joint.
select cmp_ok((select count(*) from public.planned_workouts w
    cross join lateral jsonb_array_elements(private.joint_options('b5900000-0000-4000-8000-000000000001', w.id)) e
    cross join (values ('knee'), ('back'), ('shoulder')) j(joint)
    where w.user_id = 'b5900000-0000-4000-8000-000000000001' and e -> 'joint_options' -> j.joint <> 'null'::jsonb),
  '>', 20::bigint, 'the chip has swap options to offer across the catalog');
select is((select count(*) from public.planned_workouts w
    cross join lateral jsonb_array_elements(private.joint_options('b5900000-0000-4000-8000-000000000001', w.id)) e
    cross join (values ('knee'), ('back'), ('shoulder')) j(joint)
    join public.planned_exercises pe on pe.id = (e ->> 'planned_exercise_id')::uuid
    join public.exercise_catalog o on o.slug = pe.exercise_slug
    join public.exercise_catalog r on r.slug = e -> 'joint_options' -> j.joint ->> 'slug'
    where w.user_id = 'b5900000-0000-4000-8000-000000000001'
      and not (pg_temp.rank_at(r, j.joint) = 1 and pg_temp.rank_at(r, j.joint) < pg_temp.rank_at(o, j.joint))),
  0::bigint, 'and every one is low stress on its joint and gentler than the exercise');

-- What the rule table asks of each exercise, written out independently of the function.
create function pg_temp.asked(p_state text, p_stress text) returns integer language sql as $$
  select case p_state
    when 'held' then case when p_stress in ('high', 'moderate') then 2 else 0 end
    when 'limited' then case p_stress when 'high' then 2 when 'moderate' then 1 else 0 end
    when 'watch' then case when p_stress = 'high' then 1 else 0 end
    else 0 end;
$$;

create temporary table want as
select cb.cid, pe.planned_workout_id as wid, pe.id as pid, pe.exercise_slug, pe.exercise_order,
  greatest(pg_temp.asked(cb.knee, c.knee_stress), pg_temp.asked(cb.back, c.back_stress),
    pg_temp.asked(cb.shoulder, c.shoulder_stress)) as asked
from combos cb
cross join public.planned_exercises pe
join public.exercise_catalog c on c.slug = pe.exercise_slug
where pe.user_id = 'b5900000-0000-4000-8000-000000000001';

select cmp_ok((select count(*) from chg), '>', 1000::bigint, 'the changes sweep covers a lot of ground');
select is((select count(*) from want w
    left join chg x on x.cid = w.cid and x.wid = w.wid
      and (x.entry ->> 'planned_exercise_id')::uuid = w.pid
    where (w.asked > 0) <> (x.entry is not null)), 0::bigint,
  'an exercise is changed exactly when the rule table asks for it');
select is((select count(*) from want w
    join chg x on x.cid = w.cid and x.wid = w.wid and (x.entry ->> 'planned_exercise_id')::uuid = w.pid
    where (w.asked = 1 and x.entry ->> 'joint_action' <> 'limit')
      or (w.asked = 2 and x.entry ->> 'joint_action' not in ('swap', 'drop'))), 0::bigint,
  'and by the action it asks for (a swap that finds no candidate becomes a drop)');
select is((select count(*) from chg x
    where (x.entry ->> 'sets_to')::integer > (x.entry ->> 'sets_from')::integer
      or ((x.entry ->> 'joint_action') = 'drop') <> ((x.entry ->> 'sets_to')::integer = 0)
      or ((x.entry ->> 'joint_action') <> 'drop' and (x.entry ->> 'sets_to') <> (x.entry ->> 'sets_from'))),
  0::bigint, 'a change never adds sets, only a left-out exercise has none, and every other keeps its sets');
select is((select count(*) from chg x
    where (x.entry ->> 'joint_action') = 'limit' and (
      x.entry ->> 'range_note_code' is null or (x.entry ->> 'rpe_to')::numeric > 7
      or x.entry ->> 'swap_to_slug' is not null)), 0::bigint,
  'a limit always has its cue, effort of 7 or lower and no swap');
select is((select count(*) from chg x
    where (x.entry ->> 'joint_action') = 'swap' and (
      x.entry ->> 'swap_to_slug' is null or x.entry ->> 'swap_to_name' is null
      or x.entry ->> 'range_note_code' is not null or (x.entry ->> 'rpe_to') is not null)), 0::bigint,
  'a swap names its exercise and carries no cue or effort');
select is((select count(*) from chg x
    where (x.entry ->> 'joint_action') = 'drop' and (
      x.entry ->> 'swap_to_slug' is not null or x.entry ->> 'range_note_code' is not null
      or x.entry ->> 'load_note' is not null or x.entry ->> 'rpe_to' is not null)), 0::bigint,
  'a left-out exercise carries nothing else');
select is((select count(*) from chg x where x.entry ->> 'joint_action' is null or x.entry ->> 'joint' is null
    or x.entry ->> 'joint_state' is null), 0::bigint, 'every change names its action, joint and state');

-- Swaps: gentler on the joint than the exercise, never harsher, within the ceilings, and never a repeat.
select is((select count(*) from chg x
    join public.planned_exercises pe on pe.id = (x.entry ->> 'planned_exercise_id')::uuid
    join public.exercise_catalog o on o.slug = pe.exercise_slug
    join public.exercise_catalog r on r.slug = x.entry ->> 'swap_to_slug'
    join combos cb on cb.cid = x.cid
    where x.entry ->> 'joint_action' = 'swap' and not (
      r.status = 'active' and r.slug <> o.slug
      and pg_temp.rank_at(r, x.entry ->> 'joint') < pg_temp.rank_at(o, x.entry ->> 'joint')
      and private.stress_rank(r.knee_stress) <= private.stress_rank(o.knee_stress)
      and private.stress_rank(r.back_stress) <= private.stress_rank(o.back_stress)
      and private.stress_rank(r.shoulder_stress) <= private.stress_rank(o.shoulder_stress)
      and pg_temp.rank_at(r, x.entry ->> 'joint') <= case x.entry ->> 'joint_state'
        when 'held' then 1 else 2 end
      -- another sore joint: low for held or limited, at most moderate for watch
      and (cb.knee = 'none' or x.entry ->> 'joint' = 'knee'
        or private.stress_rank(r.knee_stress) <= case cb.knee when 'watch' then 2 else 1 end)
      and (cb.back = 'none' or x.entry ->> 'joint' = 'back'
        or private.stress_rank(r.back_stress) <= case cb.back when 'watch' then 2 else 1 end)
      and (cb.shoulder = 'none' or x.entry ->> 'joint' = 'shoulder'
        or private.stress_rank(r.shoulder_stress) <= case cb.shoulder when 'watch' then 2 else 1 end))),
  0::bigint, 'every swap in every combination meets the rules');
select is((select count(*) from (
    select x.cid, x.wid, x.entry ->> 'swap_to_slug' as target, count(*) as n from chg x
    where x.entry ->> 'swap_to_slug' is not null group by 1, 2, 3 having count(*) > 1) d), 0::bigint,
  'no two swaps in one session go to the same exercise');
select is((select count(*) from chg x
    join public.planned_exercises pe on pe.planned_workout_id = x.wid
      and pe.exercise_slug = x.entry ->> 'swap_to_slug'), 0::bigint,
  'and none goes to an exercise already in the session');

-- Monotone: worse states never ask for less.
create temporary table got as
select w.cid, w.wid, w.pid,
  case when x.entry is null then 0 when x.entry ->> 'joint_action' = 'limit' then 1 else 2 end as klass
from want w left join chg x on x.cid = w.cid and x.wid = w.wid
  and (x.entry ->> 'planned_exercise_id')::uuid = w.pid;
create function pg_temp.sr(p text) returns integer language sql as $$
  select case p when 'none' then 0 when 'watch' then 1 when 'limited' then 2 else 3 end;
$$;
select is((select count(*) from combos a join combos b on pg_temp.sr(a.knee) <= pg_temp.sr(b.knee)
      and pg_temp.sr(a.back) <= pg_temp.sr(b.back) and pg_temp.sr(a.shoulder) <= pg_temp.sr(b.shoulder)
    join got ga on ga.cid = a.cid join got gb on gb.cid = b.cid and gb.wid = ga.wid and gb.pid = ga.pid
    where ga.klass > gb.klass), 0::bigint,
  'a worse state for any joint never asks for less of any exercise');

select * from finish();
rollback;
