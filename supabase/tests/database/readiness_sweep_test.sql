begin;
select no_plan();

-- B4-1: the readiness rules, row by row and swept. Part 1 is the pure assessment (no table is read);
-- part 2 is what each kind changes, over a matrix of plans and logged results.

-- Part 1: the assessment ---------------------------------------------------------------------------

-- (has check-in, sleep quality, energy, soreness, mood, pain, can train, sleep minutes, recovery
-- score, recovery confidence, recovery mode, can hold, can reduce)
create function pg_temp.assess(p_sq integer default 3, p_en integer default 3, p_so integer default 3,
  p_mo integer default 3, p_pain integer default 0, p_avail boolean default true,
  p_sleep integer default null, p_rec integer default null, p_conf text default 'high',
  p_mode text default 'night', p_hold boolean default true, p_reduce boolean default true,
  p_check_in boolean default true)
returns jsonb language sql as $$
  select private.readiness_assessment(p_check_in, p_sq, p_en, p_so, p_mo, p_pain, p_avail, p_sleep,
    p_rec, p_conf, p_mode, p_hold, p_reduce)
$$;

-- Each source of points alone.
select is(pg_temp.assess() ->> 'band', 'green', 'a check-in with nothing to report is green');
select is(pg_temp.assess() ->> 'kind', 'none', 'and proposes nothing');
select is((pg_temp.assess(p_sq => 1) ->> 'points')::integer, 2, 'very poor sleep is 2');
select is((pg_temp.assess(p_sq => 2) ->> 'points')::integer, 1, 'poor sleep is 1');
select is((pg_temp.assess(p_en => 1) ->> 'points')::integer, 2, 'very low energy is 2');
select is((pg_temp.assess(p_en => 2) ->> 'points')::integer, 1, 'low energy is 1');
select is((pg_temp.assess(p_so => 5) ->> 'points')::integer, 2, 'very sore is 2');
select is((pg_temp.assess(p_so => 4) ->> 'points')::integer, 1, 'sore is 1');
select is((pg_temp.assess(p_mo => 1) ->> 'points')::integer, 1, 'very low mood is 1');
select is((pg_temp.assess(p_mo => 2) ->> 'points')::integer, 0, 'low mood is not a point');
select is((pg_temp.assess(p_pain => 4) ->> 'points')::integer, 2, 'pain of 4 is 2');
select is((pg_temp.assess(p_pain => 6) ->> 'points')::integer, 2, 'pain of 6 is 2');
select is((pg_temp.assess(p_pain => 3) ->> 'points')::integer, 0, 'pain of 3 is a note only');
select is(pg_temp.assess(p_pain => 3) -> 'triggers', '["pain_mild"]'::jsonb, 'named pain_mild');
select is(pg_temp.assess(p_pain => 1) -> 'triggers', '["pain_mild"]'::jsonb, 'from 1');
select is(pg_temp.assess(p_pain => 0) -> 'triggers', '[]'::jsonb, 'and not at 0');
select is((pg_temp.assess(p_sleep => 359) ->> 'points')::integer, 1, 'under 360 minutes of sleep is 1');
select is((pg_temp.assess(p_sleep => 360) ->> 'points')::integer, 0, '360 minutes is not');
select is((pg_temp.assess(p_sleep => 1) ->> 'points')::integer, 1, 'one minute is a recorded night');
select is((pg_temp.assess(p_sleep => 0) ->> 'points')::integer, 0, 'zero means nothing was recorded');
select is(pg_temp.assess(p_sleep => 0) -> 'missing', '["sleep", "recovery"]'::jsonb, 'and sleep is missing');
select is((pg_temp.assess(p_sleep => 961) ->> 'points')::integer, 0, 'more than 960 is not a night of sleep');
select is(pg_temp.assess(p_sleep => 961) -> 'missing', '["sleep", "recovery"]'::jsonb, 'it is missing');
select is(pg_temp.assess(p_sleep => 960) -> 'missing', '["recovery"]'::jsonb, '960 is a night');
select is((pg_temp.assess(p_sleep => null) ->> 'points')::integer, 0, 'no sleep value is no point');

-- The recovery score never counts alone (D9) and counts next to a point from the check-in.
select is((pg_temp.assess(p_rec => 20) ->> 'points')::integer, 0, 'recovery 20 alone is no point');
select is(pg_temp.assess(p_rec => 20) ->> 'band', 'green', 'the band stays green');
select is(pg_temp.assess(p_rec => 20) ->> 'kind', 'none', 'and nothing is proposed');
select is(pg_temp.assess(p_rec => 20) -> 'triggers', '["recovery_low"]'::jsonb, 'but it is reported');
select is(pg_temp.assess(p_rec => 20) -> 'recovery_low', 'true'::jsonb, 'and flagged');
select is((pg_temp.assess(p_rec => 20, p_sq => 2) ->> 'points')::integer, 2,
  'next to poor sleep it adds its point');
select is((pg_temp.assess(p_rec => 34, p_sq => 2) ->> 'points')::integer, 2, '34 is low');
select is((pg_temp.assess(p_rec => 35, p_sq => 2) ->> 'points')::integer, 1, '35 is not');
select is((pg_temp.assess(p_rec => 20, p_conf => 'medium', p_sq => 2) ->> 'points')::integer, 2,
  'medium confidence counts');
select is((pg_temp.assess(p_rec => 20, p_conf => 'low', p_sq => 2) ->> 'points')::integer, 1,
  'low confidence does not');
select is((pg_temp.assess(p_rec => 20, p_conf => 'cold_start', p_sq => 2) ->> 'points')::integer, 1,
  'neither does a cold start');
select is((pg_temp.assess(p_rec => 20, p_sleep => 300) ->> 'points')::integer, 1,
  'sleep under six hours is not a point from the check-in, so the recovery adds nothing to it');
select is((pg_temp.assess(p_rec => 20, p_pain => 5) ->> 'points')::integer, 3,
  'pain of 4 to 6 counts as a point from the check-in');
select is((pg_temp.assess(p_rec => 20, p_pain => 3) ->> 'points')::integer, 0,
  'pain of 1 to 3 does not');

-- Bands and kinds by points.
select is(pg_temp.assess(p_sq => 2) -> 'kind', '"hold_load"'::jsonb, '1 point holds the loads');
select is(pg_temp.assess(p_sq => 2) ->> 'band', 'amber', 'amber');
select is(pg_temp.assess(p_sq => 2, p_en => 2) -> 'kind', '"reduce_sets"'::jsonb, '2 points: one set fewer');
select is(pg_temp.assess(p_sq => 1, p_en => 2) -> 'kind', '"reduce_sets"'::jsonb, '3 points: one set fewer');
select is(pg_temp.assess(p_sq => 1, p_en => 2) ->> 'band', 'amber', 'still amber');
select is(pg_temp.assess(p_sq => 1, p_en => 1) -> 'kind', '"swap_to_easy_cardio"'::jsonb,
  '4 points: easy cardio');
select is(pg_temp.assess(p_sq => 1, p_en => 1) ->> 'band', 'red', 'red');
select is(pg_temp.assess(p_sq => 1, p_en => 1, p_so => 5, p_mo => 1, p_pain => 5, p_sleep => 200)
  -> 'kind', '"swap_to_easy_cardio"'::jsonb, 'and more points stay there');

-- Fallbacks: a kind that would change nothing falls back to the milder one.
select is(pg_temp.assess(p_sq => 2, p_hold => false) -> 'kind', '"none"'::jsonb,
  '1 point with nothing to hold proposes nothing');
select is(pg_temp.assess(p_sq => 2, p_hold => false) ->> 'band', 'amber', 'but the band stays amber');
select is(pg_temp.assess(p_sq => 2, p_en => 2, p_reduce => false) -> 'kind', '"hold_load"'::jsonb,
  'when no set can go, 2 points hold the loads');
select is(pg_temp.assess(p_sq => 2, p_en => 2, p_reduce => false, p_hold => false) -> 'kind', '"none"'::jsonb,
  'and with nothing to hold, nothing');
select is(pg_temp.assess(p_sq => 1, p_en => 1, p_reduce => false, p_hold => false) -> 'kind',
  '"swap_to_easy_cardio"'::jsonb, 'easy cardio needs neither');

-- The gates.
select is(pg_temp.assess(p_pain => 7) ->> 'safety_route', 'pain_referral', 'pain of 7 routes out');
select is(pg_temp.assess(p_pain => 7) ->> 'kind', 'none', 'with no kind');
select is(pg_temp.assess(p_pain => 7) -> 'triggers', '["pain_severe"]'::jsonb, 'and one reason');
select is(pg_temp.assess(p_pain => 6) -> 'safety_route', 'null'::jsonb, 'pain of 6 does not');
select is(pg_temp.assess(p_pain => 10, p_sq => 1, p_en => 1) ->> 'kind', 'none',
  'pain routes out whatever else is reported');
select is(pg_temp.assess(p_pain => 8, p_avail => false) ->> 'safety_route', 'pain_referral',
  'and even when the athlete said they cannot train');
select is(pg_temp.assess(p_check_in => false) ->> 'band', 'unknown', 'no check-in: unknown');
select is(pg_temp.assess(p_check_in => false) ->> 'kind', 'none', 'nothing proposed');
select is(pg_temp.assess(p_check_in => false) -> 'triggers', '["no_check_in"]'::jsonb, 'the missing check-in');
select is(pg_temp.assess(p_check_in => false) -> 'confidence', 'null'::jsonb, 'with no confidence');
select is(pg_temp.assess(p_check_in => false, p_rec => 20) -> 'triggers', '["no_check_in", "recovery_low"]'::jsonb,
  'a low recovery without a check-in asks for the check-in');
select is(pg_temp.assess(p_check_in => false, p_rec => 20) ->> 'kind', 'none', 'and proposes nothing');
select is(pg_temp.assess(p_check_in => false, p_rec => 20, p_sq => 1, p_en => 1, p_pain => 9) ->> 'kind', 'none',
  'old check-in values are not read without a check-in');
select is(pg_temp.assess(p_avail => false, p_sq => 1, p_en => 1) ->> 'kind', 'none',
  'an athlete who cannot train gets no kind');
select is(pg_temp.assess(p_avail => false, p_sq => 1, p_en => 1) ->> 'band', 'red', 'but the band is from the points');
select is(pg_temp.assess(p_avail => false, p_sq => 1, p_en => 1) -> 'triggers',
  '["not_available", "sleep_very_poor", "energy_very_low"]'::jsonb, 'with the reason first');

-- Confidence.
select is(pg_temp.assess(p_sleep => 480, p_rec => 60) ->> 'confidence', 'high', 'check-in, sleep and a night recovery: high');
select is(pg_temp.assess(p_sleep => 480, p_rec => 60, p_mode => 'morning') ->> 'confidence', 'medium',
  'a morning estimate is medium at best');
select is(pg_temp.assess(p_sleep => 480, p_rec => 60, p_conf => 'medium') ->> 'confidence', 'medium',
  'a medium recovery is medium');
select is(pg_temp.assess(p_sleep => 480) ->> 'confidence', 'medium', 'sleep alone is medium');
select is(pg_temp.assess(p_rec => 60) ->> 'confidence', 'medium', 'recovery alone is medium');
select is(pg_temp.assess() ->> 'confidence', 'low', 'the check-in alone is low');
select is(pg_temp.assess(p_rec => 60, p_conf => 'low') ->> 'confidence', 'low', 'a low-confidence recovery is not a signal');
select is(pg_temp.assess() -> 'missing', '["sleep", "recovery"]'::jsonb, 'and both are missing');

-- Swept: sleep quality, energy and mood 1 to 3 (4 and 5 score like 3), soreness 3 to 5, pain
-- 0/1/3/4/6/7/10, can train, sleep minutes, and recovery with its confidence.
create temporary table sweep as
select sq, en, so, mo, pain, avail, sleep, rec, conf,
  private.readiness_assessment(true, sq, en, so, mo, pain, avail, sleep, rec, conf, 'night', true, true) a
from generate_series(1, 3) sq, generate_series(1, 3) en, generate_series(3, 5) so,
  generate_series(1, 3) mo, unnest(array[0, 1, 3, 4, 6, 7, 10]) pain, unnest(array[true, false]) avail,
  unnest(array[null, 0, 300, 359, 360, 480]::integer[]) sleep,
  (values (null::integer, 'low'), (20, 'low'), (20, 'medium'), (20, 'high'), (34, 'high'),
    (35, 'high'), (60, 'high')) rc(rec, conf);
alter table sweep add column kind text, add column band text, add column route text,
  add column points integer, add column subj integer, add column trig jsonb;
update sweep set kind = a ->> 'kind', band = a ->> 'band', route = a ->> 'safety_route',
  points = (a ->> 'points')::integer, subj = (a ->> 'subjective_points')::integer, trig = a -> 'triggers';
create index on sweep (sq, en, so, mo, pain, avail, sleep, rec, conf);

select is((select count(*) from sweep), 47628::bigint, 'the sweep has every combination');
select is((select count(*) from sweep where pain >= 7 and (kind <> 'none' or route is distinct from 'pain_referral')),
  0::bigint, '(a) pain of 7 or more always gives no kind and a safety route');
select is((select count(*) from sweep where pain < 7 and route is not null), 0::bigint,
  'and nothing below 7 does');
select is((select count(*) from sweep s join sweep w
    on w.en = s.en and w.so = s.so and w.mo = s.mo and w.pain = s.pain and w.avail = s.avail
      and w.sleep is not distinct from s.sleep and w.rec is not distinct from s.rec and w.conf = s.conf
      and w.sq = s.sq - 1
    where private.readiness_rank(w.kind, w.route) < private.readiness_rank(s.kind, s.route)),
  0::bigint, '(b) worse sleep never gives a less strict kind');
select is((select count(*) from sweep s join sweep w
    on w.sq = s.sq and w.so = s.so and w.mo = s.mo and w.pain = s.pain and w.avail = s.avail
      and w.sleep is not distinct from s.sleep and w.rec is not distinct from s.rec and w.conf = s.conf
      and w.en = s.en - 1
    where private.readiness_rank(w.kind, w.route) < private.readiness_rank(s.kind, s.route)),
  0::bigint, 'worse energy never does');
select is((select count(*) from sweep s join sweep w
    on w.sq = s.sq and w.en = s.en and w.mo = s.mo and w.pain = s.pain and w.avail = s.avail
      and w.sleep is not distinct from s.sleep and w.rec is not distinct from s.rec and w.conf = s.conf
      and w.so = s.so + 1
    where private.readiness_rank(w.kind, w.route) < private.readiness_rank(s.kind, s.route)),
  0::bigint, 'more soreness never does');
select is((select count(*) from sweep s join sweep w
    on w.sq = s.sq and w.en = s.en and w.so = s.so and w.pain = s.pain and w.avail = s.avail
      and w.sleep is not distinct from s.sleep and w.rec is not distinct from s.rec and w.conf = s.conf
      and w.mo = s.mo - 1
    where private.readiness_rank(w.kind, w.route) < private.readiness_rank(s.kind, s.route)),
  0::bigint, 'a lower mood never does');
select is((select count(*) from sweep s join sweep w
    on w.sq = s.sq and w.en = s.en and w.so = s.so and w.mo = s.mo and w.avail = s.avail
      and w.sleep is not distinct from s.sleep and w.rec is not distinct from s.rec and w.conf = s.conf
      and w.pain > s.pain
    where private.readiness_rank(w.kind, w.route) < private.readiness_rank(s.kind, s.route)),
  0::bigint, 'more pain never does');
select is((select count(*) from sweep s join sweep w
    on w.sq = s.sq and w.en = s.en and w.so = s.so and w.mo = s.mo and w.pain = s.pain
      and w.avail = s.avail and w.rec is not distinct from s.rec and w.conf = s.conf
      and w.sleep < s.sleep and s.sleep > 0 and w.sleep > 0
    where private.readiness_rank(w.kind, w.route) < private.readiness_rank(s.kind, s.route)),
  0::bigint, 'less sleep never does');
select is((select count(*) from sweep s join sweep w
    on w.sq = s.sq and w.en = s.en and w.so = s.so and w.mo = s.mo and w.pain = s.pain
      and w.avail = s.avail and w.sleep is not distinct from s.sleep and w.conf = s.conf
      and w.rec < s.rec
    where private.readiness_rank(w.kind, w.route) < private.readiness_rank(s.kind, s.route)),
  0::bigint, 'a lower recovery score never does');
select is((select count(*) from sweep where subj = 0 and not (trig ? 'sleep_short') and kind <> 'none'),
  0::bigint, '(c) with no point from the check-in and no short sleep, nothing is proposed whatever the recovery');
select is((select count(*) from sweep where not avail and kind <> 'none'), 0::bigint,
  '(e) an athlete who cannot train never gets a kind');
select is((select count(*) from sweep where kind <> 'none' and jsonb_array_length(trig) = 0), 0::bigint,
  '(f) a kind always has a reason');
select is((select count(*) from sweep where pain < 7 and avail and (
    (points = 0 and (band, kind) is distinct from ('green', 'none'))
    or (points = 1 and (band, kind) is distinct from ('amber', 'hold_load'))
    or (points in (2, 3) and (band, kind) is distinct from ('amber', 'reduce_sets'))
    or (points >= 4 and (band, kind) is distinct from ('red', 'swap_to_easy_cardio')))),
  0::bigint, 'the band and the kind follow the points');
select is((select count(*) from sweep where pain < 7 and points <> subj
    + (case when trig ? 'sleep_short' then 1 else 0 end)
    + (case when trig ? 'recovery_low' and subj >= 1 then 1 else 0 end)),
  0::bigint, 'and the points are the sum of their sources');

-- Part 2: what a kind changes ---------------------------------------------------------------------------
-- 1,800 exercises: sets 1/2/3/4/6 x ranges 5-8 and 10-15 x RPE none/5/6/7.5/9 x last fewest reps
-- (below the range, at its bottom, one under its top, at its top) x reps in reserve none/1/3 x
-- loaded/assisted/bodyweight. Each has a logged session and the real B3 decision; a workout of up to
-- 30 of them is adjusted in every kind.

insert into auth.users(id, role) values ('b4a00000-0000-4000-8000-000000000001', 'authenticated');
insert into public.training_plans(id, user_id, title, source)
values ('b4a10000-0000-4000-8000-000000000001', 'b4a00000-0000-4000-8000-000000000001', 'Sweep', 'imported');

create temporary table cfg as
select row_number() over (order by sets, rmin, rpe, lri, rir, kindl) as n, sets, rmin, rmax, rpe, lri, rir,
  kindl, gen_random_uuid() as id,
  case lri when 0 then rmin - 1 when 1 then rmin when 2 then rmax - 1 else rmax end as last_reps,
  case kindl when 'loaded' then 60 when 'assisted' then 20 end::numeric as load,
  case kindl when 'loaded' then 2.5 when 'assisted' then 5 end::numeric as step
from unnest(array[1, 2, 3, 4, 6]) sets, (values (5, 8), (10, 15)) rr(rmin, rmax),
  unnest(array[null, 5, 6, 7.5, 9]::numeric[]) rpe, unnest(array[0, 1, 2, 3]) lri,
  unnest(array[null, 1, 3]::integer[]) rir, unnest(array['loaded', 'assisted', 'bodyweight']) kindl;
alter table cfg add column v integer, add column w integer, add column o integer;
update cfg set v = (n - 1) / 210 + 1, w = ((n - 1) % 210) / 30 + 1, o = (n - 1) % 30 + 1;
select is((select count(*) from cfg), 1800::bigint, 'the matrix has 1,800 exercises');

create temporary table ver as select distinct v, gen_random_uuid() as id from cfg;
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale)
select id, 'b4a00000-0000-4000-8000-000000000001', 'b4a10000-0000-4000-8000-000000000001', v, 'archived',
  6, 7, '{}', 'Sweep' from ver;
create temporary table wo as select distinct c.v, c.w, gen_random_uuid() as id from cfg c;
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
select wo.id, 'b4a00000-0000-4000-8000-000000000001', ver.id, wo.w, 'Sweep ' || wo.v || '.' || wo.w,
  'Sweep', wo.w, 60, 'Warm up', 'Cool down' from wo join ver on ver.v = wo.v;
insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
  display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
select c.id, 'b4a00000-0000-4000-8000-000000000001', wo.id, c.o, 'Sweep exercise ' || c.n, c.sets, c.rmin,
  c.rmax, c.rpe, 60, case c.kindl when 'loaded' then 'barbell-bench-press'
    when 'assisted' then 'assisted-pull-up' end
from cfg c join wo on wo.v = c.v and wo.w = c.w;

create temporary table tg as
select c.*, wo.id as workout_id,
  jsonb_build_object('planned_exercise_id', c.id, 'exercise_key', 'x', 'name', 'Sweep exercise ' || c.n)
  || d.decision || jsonb_build_object('basis', jsonb_build_object('last_date', current_date - 3,
    'recent', jsonb_build_array(jsonb_build_object('load_kg', c.load, 'sets', c.sets,
      'min_reps', c.last_reps, 'total_reps', c.last_reps * c.sets, 'min_rir', c.rir,
      'effort_known', c.rir is not null, 'pain', false, 'adjusted', false, 'sets_planned', null)))) as target,
  d.decision ->> 'action' as action, (d.decision ->> 'load_kg')::numeric as target_load
from cfg c join wo on wo.v = c.v and wo.w = c.w
cross join lateral (select private.progression_decision(c.sets, c.rmin, c.rmax, c.rpe, c.step, 3, false,
  false, c.kindl = 'assisted', jsonb_build_array(jsonb_build_object('load_kg', c.load, 'sets', c.sets,
    'min_reps', c.last_reps, 'total_reps', c.last_reps * c.sets, 'min_rir', c.rir,
    'effort_known', c.rir is not null, 'pain', false, 'adjusted', false, 'sets_planned', null))) as decision) d;

create temporary table res as
select k.kind, wo.id as workout_id, wo.v, wo.w,
  private.day_adjustment_changes('b4a00000-0000-4000-8000-000000000001', wo.id, k.kind,
    (select jsonb_agg(t.target) from tg t where t.workout_id = wo.id)) as r
from wo cross join (values ('hold_load'), ('reduce_sets'), ('swap_to_easy_cardio')) k(kind);
create temporary table ent as
select res.kind, res.workout_id as res_workout_id, e as entry, t.*
from res cross join lateral jsonb_array_elements(res.r -> 'changes') e
join tg t on t.id = (e ->> 'planned_exercise_id')::uuid;

select is((select count(*) from res), 180::bigint, 'every workout is adjusted in every kind');
select is((select sum(jsonb_array_length(r -> 'changes')) from res), (select count(*) from ent),
  'every change names a planned exercise');
select is((select count(*) from ent where res_workout_id <> workout_id), 0::bigint,
  'of its own workout');
select is((select count(*) from ent where (entry ->> 'sets_from')::integer <> sets
    or entry ->> 'name' <> 'Sweep exercise ' || n or (entry ->> 'exercise_order')::integer <> o),
  0::bigint, 'a change repeats the plan''s sets, name and order');
select is((select count(*) from ent where kind <> 'swap_to_easy_cardio'
    and ((entry ->> 'sets_to')::integer > sets or (entry ->> 'sets_to')::integer < 1)),
  0::bigint, 'sets never go up and never reach zero outside the cardio swap');
select is((select count(*) from ent where kind = 'hold_load' and (entry ->> 'sets_to')::integer <> sets),
  0::bigint, 'holding loads keeps every set');
select is((select count(*) from ent where kind = 'reduce_sets'
    and (entry ->> 'sets_to')::integer <> case when sets >= 3 then sets - 1 else sets end),
  0::bigint, 'one set fewer applies from three sets');
select is((select count(*) from ent where kind = 'swap_to_easy_cardio' and (entry ->> 'sets_to')::integer <> 0),
  0::bigint, 'easy cardio takes every set');
select is((select count(*) from ent where kind = 'swap_to_easy_cardio'), (select count(*) from tg),
  'and lists every exercise');
select is((select count(*) from ent where kind = 'hold_load'),
  (select count(*) from tg where action in ('add_load', 'add_reps')),
  'holding loads lists exactly the exercises B3 would progress');
select is((select count(*) from ent where kind <> 'swap_to_easy_cardio'
    and entry -> 'load_kg_to' <> 'null'::jsonb
    and (entry ->> 'load_kg_to')::numeric is distinct from load),
  0::bigint, 'a held load is the last logged one');
select is((select count(*) from ent where kind <> 'swap_to_easy_cardio' and kindl = 'loaded'
    and (entry ->> 'load_kg_to')::numeric > target_load),
  0::bigint, 'a held load is never above the target');
select is((select count(*) from ent where kind <> 'swap_to_easy_cardio' and kindl = 'assisted'
    and (entry ->> 'load_kg_to')::numeric < target_load),
  0::bigint, 'and a held assistance is never below it');
select is((select count(*) from ent where kind <> 'swap_to_easy_cardio' and kindl = 'bodyweight'
    and entry -> 'load_kg_to' <> 'null'::jsonb), 0::bigint, 'a bodyweight exercise gets no load');
select is((select count(*) from ent where kind <> 'swap_to_easy_cardio' and action in ('add_load', 'add_reps')
    and kindl <> 'bodyweight' and entry -> 'load_kg_to' = 'null'::jsonb), 0::bigint,
  'a loaded exercise that was to progress gets its held load');
select is((select count(*) from ent where kind <> 'swap_to_easy_cardio'
    and ((entry ->> 'reps_to')::integer not between rmin and rmax)),
  0::bigint, 'held reps sit inside the range');
select is((select count(*) from ent where kind = 'reduce_sets' and rpe is not null
    and not ((entry ->> 'rpe_to')::numeric <= rpe and ((entry ->> 'rpe_to')::numeric >= 6
      or (entry ->> 'rpe_to')::numeric = rpe))),
  0::bigint, 'effort drops by one point, not below 6 and never above the plan''s');
select is((select count(*) from ent where kind = 'reduce_sets' and rpe is not null
    and rpe >= 7 and (entry ->> 'rpe_to')::numeric <> rpe - 1), 0::bigint, 'by exactly one point from 7');
select is((select count(*) from ent where (kind <> 'reduce_sets' or rpe is null)
    and entry -> 'rpe_to' <> 'null'::jsonb), 0::bigint, 'effort changes only in the lighter session, and only when the plan has one');
select is((select count(*) from ent where kind = 'reduce_sets'
    and (entry ->> 'sets_to')::integer = sets and action not in ('add_load', 'add_reps')
    and (entry -> 'rpe_to' = 'null'::jsonb or (entry ->> 'rpe_to')::numeric = rpe)),
  0::bigint, 'a lighter-session entry always changes something');
select is((select count(*) from res r where (r.r ->> 'sets_from')::integer <> (
      select sum(t.sets) from tg t where t.workout_id = r.workout_id)
    or (r.r ->> 'sets_to')::integer <> (select sum(coalesce((
        select (e ->> 'sets_to')::integer from jsonb_array_elements(r.r -> 'changes') e
        where e ->> 'planned_exercise_id' = t.id::text), t.sets)) from tg t
      where t.workout_id = r.workout_id)),
  0::bigint, 'the set totals add up');
select is((select count(*) from res where kind = 'reduce_sets'
    and (r ->> 'sets_to')::integer < (r ->> 'sets_from')::integer), (select count(*) from res where kind = 'reduce_sets'
    and exists (select 1 from tg where tg.workout_id = res.workout_id and sets >= 3)),
  'a lighter session removes a set exactly when an exercise has three or more');

select * from finish();
rollback;
