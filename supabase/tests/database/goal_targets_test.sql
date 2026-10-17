begin;
select plan(47);

-- A has a 180 cm profile and a fat-loss goal that began on 1 June, with a stale weight in its
-- details; B has no height; C has no goal. 
insert into auth.users(id, role) values
  ('c2700000-0000-4000-8000-000000000001', 'authenticated'),
  ('c2700000-0000-4000-8000-000000000002', 'authenticated'),
  ('c2700000-0000-4000-8000-000000000003', 'authenticated');

insert into public.user_profiles(user_id, height_cm) values
  ('c2700000-0000-4000-8000-000000000001', 180),
  ('c2700000-0000-4000-8000-000000000002', null);

insert into public.user_goals(id, user_id, goal_type, priority, status, details, activated_at) values
  ('c2710000-0000-4000-8000-000000000001', 'c2700000-0000-4000-8000-000000000001', 'fat_loss', 1,
   'active', '{"description": "Aggressive fat loss", "current_weight_kg": 86.2}',
   '2026-06-01 10:00:00+00'),
  ('c2710000-0000-4000-8000-000000000002', 'c2700000-0000-4000-8000-000000000002', 'muscle_gain', 1,
   'active', '{}', '2026-06-01 10:00:00+00');

insert into public.body_measurements(id, user_id, measured_on, source, weight_kg) values
  ('c2720000-0000-4000-8000-000000000001', 'c2700000-0000-4000-8000-000000000001', '2026-06-03', 'manual', 90.0),
  ('c2720000-0000-4000-8000-000000000002', 'c2700000-0000-4000-8000-000000000001', '2026-07-02', 'manual', 60.0),
  ('c2720000-0000-4000-8000-000000000003', 'c2700000-0000-4000-8000-000000000001', '2026-10-13', 'manual', 74.8);
-- The 60 kg reading is amended to 83: only the amendment counts.
insert into public.body_measurements(id, user_id, measured_on, source, weight_kg, amended_from_id) values
  ('c2720000-0000-4000-8000-000000000004', 'c2700000-0000-4000-8000-000000000001', '2026-07-02', 'manual', 83.0,
   'c2720000-0000-4000-8000-000000000002');

-- Grants ---------------------------------------------------------------------------------------

select ok(has_function_privilege('authenticated', 'public.get_goal_target_v1()', 'execute'),
  'athletes read their target');
select ok(not has_function_privilege('anon', 'public.get_goal_target_v1()', 'execute'),
  'signed-out callers cannot read a target');
select ok(has_function_privilege('authenticated',
  'public.set_goal_target_v1(numeric, numeric, numeric, text, text, date)', 'execute'),
  'athletes set their target');
select ok(not has_function_privilege('anon',
  'public.set_goal_target_v1(numeric, numeric, numeric, text, text, date)', 'execute'),
  'signed-out callers cannot set a target');
select ok(not has_function_privilege('authenticated', 'public.get_goal_phase_inputs_v1(uuid)', 'execute'),
  'athletes cannot call the Coach inputs');
select ok(not has_function_privilege('anon', 'public.get_goal_phase_inputs_v1(uuid)', 'execute'),
  'signed-out callers cannot call the Coach inputs');
select ok(has_function_privilege('service_role', 'public.get_goal_phase_inputs_v1(uuid)', 'execute'),
  'the service role reads the Coach inputs');
select ok(not has_function_privilege('authenticated', 'private.healthy_floor_weight_kg(uuid)', 'execute'),
  'the floor calculation is private');
select ok(not has_function_privilege('authenticated', 'private.goal_target_keys()', 'execute'),
  'the key list is private');
select ok((select prosecdef from pg_proc
    where oid = 'public.set_goal_target_v1(numeric, numeric, numeric, text, text, date)'::regprocedure),
  'setting is security definer');
select is((select proconfig from pg_proc
    where oid = 'public.set_goal_target_v1(numeric, numeric, numeric, text, text, date)'::regprocedure),
  array['search_path=""'], 'with an empty search path');

-- Coach inputs (read as the service role: postgres here) ----------------------------------------

select is(public.get_goal_phase_inputs_v1('c2700000-0000-4000-8000-000000000001') ->> 'schema_version',
  '1.0', 'the Coach inputs carry a schema version');
select is((public.get_goal_phase_inputs_v1('c2700000-0000-4000-8000-000000000001') ->> 'height_cm')::numeric,
  180::numeric, 'with the height');
select is(public.get_goal_phase_inputs_v1('c2700000-0000-4000-8000-000000000001') -> 'goal' ->> 'activated_on',
  '2026-06-01', 'the date the goal began');
select is(public.get_goal_phase_inputs_v1('c2700000-0000-4000-8000-000000000001') -> 'goal' ->> 'goal_type',
  'fat_loss', 'and its type');
select is(jsonb_array_length(public.get_goal_phase_inputs_v1('c2700000-0000-4000-8000-000000000001') -> 'readings'),
  3, 'an amended reading is replaced by its amendment');
select is(public.get_goal_phase_inputs_v1('c2700000-0000-4000-8000-000000000001') -> 'readings' -> 1 ->> 'kg',
  '83.00', 'the amended value is the one returned');
select is(public.get_goal_phase_inputs_v1('c2700000-0000-4000-8000-000000000001') -> 'goal' -> 'target' ->> 'weight_kg',
  null, 'no target is reported as null');
select is(public.get_goal_phase_inputs_v1('c2700000-0000-4000-8000-000000000003') -> 'goal',
  'null'::jsonb, 'an athlete without a goal has no goal in the inputs');

-- A reads and sets a target ----------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c2700000-0000-4000-8000-000000000001';

select is(public.get_goal_target_v1() ->> 'has_target', 'false', 'no target is set at first');
select is((select array_agg(k order by k) from jsonb_object_keys(public.get_goal_target_v1()) k),
  array['goal_type', 'has_goal', 'has_target', 'min_target_weight_kg', 'schema_version', 'target'],
  'the read returns exactly the keys the app parses (add keys, never remove)');
select is((select array_agg(k order by k) from jsonb_object_keys(public.get_goal_target_v1() -> 'target') k),
  array['body_fat_pct_max', 'body_fat_pct_min', 'date', 'physique', 'physique_note', 'set_at', 'weight_kg'],
  'and exactly these target keys');
select is(public.get_goal_target_v1() ->> 'schema_version', '1.0', 'the read carries a schema version');
select is((public.get_goal_target_v1() ->> 'min_target_weight_kg')::numeric, 59.9::numeric,
  'the lowest accepted weight is BMI 18.5 at 180 cm');

select throws_ok($$select public.set_goal_target_v1()$$, '22023', null,
  'an empty target is refused');
select throws_ok($$select public.set_goal_target_v1(p_target_date => current_date + 30)$$, '22023', null,
  'a date alone is not a target');
select throws_ok($$select public.set_goal_target_v1(p_target_weight_kg => 55)$$, '22023', null,
  'a weight below the healthy floor for the height is refused');
select throws_ok($$select public.set_goal_target_v1(p_target_weight_kg => 20)$$, '22023', null,
  'an out-of-range weight is refused');
select throws_ok($$select public.set_goal_target_v1(p_body_fat_pct_min => 20, p_body_fat_pct_max => 12)$$,
  '22023', null, 'a reversed body-fat range is refused');
select throws_ok($$select public.set_goal_target_v1(p_physique => 'six_pack_by_friday')$$, '22023', null,
  'an unknown physique goal is refused');
select throws_ok($$select public.set_goal_target_v1(p_physique_note => 'abs')$$, '22023', null,
  'a note needs a physique goal');
select throws_ok($$select public.set_goal_target_v1(p_target_weight_kg => 70, p_target_date => current_date - 1)$$,
  '22023', null, 'a date in the past is refused');
select throws_ok($$select public.set_goal_target_v1(p_target_weight_kg => 70, p_target_date => current_date + 2000)$$,
  '22023', null, 'a date beyond three years is refused');

select is(public.set_goal_target_v1(p_target_weight_kg => 72, p_target_date => current_date + 120)
    -> 'target' ->> 'weight_kg', '72', 'the athlete sets a target weight');
select is(public.get_goal_target_v1() ->> 'has_target', 'true', 'and the read shows it');

select is(public.set_goal_target_v1(p_physique => 'visible_abs', p_physique_note => 'for summer',
    p_body_fat_pct_min => 10, p_body_fat_pct_max => 12) -> 'target' ->> 'weight_kg',
  null, 'setting again replaces the whole target: the weight is gone');
select is(public.get_goal_target_v1() -> 'target' ->> 'physique', 'visible_abs',
  'the physique goal is stored');

-- The athlete file keeps what it had, and an audit event is written -----------------------------

reset role;
select is((select details ->> 'current_weight_kg' from public.user_goals
    where id = 'c2710000-0000-4000-8000-000000000001'), '86.2',
  'the other goal details are untouched');
select is((select details ->> 'target_body_fat_pct_min' from public.user_goals
    where id = 'c2710000-0000-4000-8000-000000000001'), '10',
  'the target sits in the goal details the Coach athlete file already carries');
select is((select count(*) from public.audit_events where user_id = 'c2700000-0000-4000-8000-000000000001'
    and action_code = 'goal_target_set' and outcome = 'succeeded'), 2::bigint,
  'each set writes an audit event');
select is((select metadata -> 'kinds' from public.audit_events
    where user_id = 'c2700000-0000-4000-8000-000000000001' and action_code = 'goal_target_set'
    order by created_at desc, id limit 1), '["body_fat", "physique"]'::jsonb,
  'the event names the kinds of target, never the values');

-- Athletes are separate ---------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c2700000-0000-4000-8000-000000000002';

select is(public.get_goal_target_v1() ->> 'has_target', 'false', 'B does not see A''s target');
select is(public.get_goal_target_v1() -> 'min_target_weight_kg', 'null'::jsonb,
  'without a height there is no floor');
select is(public.set_goal_target_v1(p_target_weight_kg => 55) -> 'target' ->> 'weight_kg', '55',
  'and no floor check');

reset role;
select is((select details ->> 'target_weight_kg' from public.user_goals
    where id = 'c2710000-0000-4000-8000-000000000001'), null, 'A''s goal was not changed by B');

-- C has no goal -----------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c2700000-0000-4000-8000-000000000003';

select is(public.get_goal_target_v1() ->> 'has_goal', 'false', 'no goal is reported as no goal');
select throws_ok($$select public.set_goal_target_v1(p_target_weight_kg => 70)$$, '55000', null,
  'a target needs an active goal');

select * from finish();
rollback;
