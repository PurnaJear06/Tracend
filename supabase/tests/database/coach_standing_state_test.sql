begin;
select plan(72);

-- Coach standing state (20261101200000): a break is approved state (training_pauses, an overlay), one
-- availability helper answers "can this athlete train today?", the brief, the hub, the readiness card and
-- the daily decision honour it, and the Coach reads it through get_coach_standing_state_v1.

create function pg_temp.u(n integer) returns uuid language sql immutable as $$
  select ('c5000000-0000-4000-8000-00000000000' || n)::uuid;
$$;

create function pg_temp.athlete(uid uuid) returns void language plpgsql as $$
begin
  insert into auth.users(id, role) values (uid, 'authenticated');
  insert into public.user_profiles(user_id, adult_attested_at, eligible, experience_level,
    training_days, session_minutes)
  values (uid, now(), true, 'beginner', array[2,5]::smallint[], 45);
end $$;

create function pg_temp.check_in(uid uuid, d date, available boolean) returns void language sql as $$
  insert into public.daily_check_ins(user_id, local_date, timezone, revision, idempotency_key,
    sleep_quality, energy, soreness, hunger, mood, pain_severity, available_to_train)
  values (uid, d, 'UTC', 1, gen_random_uuid(), 5, 5, 1, 3, 5, 0, available);
$$;

create function pg_temp.store_pause(uid uuid, s date, e date) returns uuid language sql as $$
  select (public.persist_coach_proposal_v1(uid, 'training_pause', 'Break', 'You want a rest.',
    'Rest.', 'Some fitness may fade.', 'high',
    '[{"code":"ATHLETE_REQUEST","label":"You asked for a break.","source":"athlete"}]',
    '{"rows":[{"label":"Training","value":"Your plan as usual"}]}',
    '{"rows":[{"label":"Break","value":"A few days"}]}',
    jsonb_build_object('pause', jsonb_build_object('start_date', s, 'end_date', e, 'reason', 'rest')),
    '{"training_version_id":null,"nutrition_version_id":null,"goal_id":null,"screening":"cleared","gates":[]}',
    e, 24) ->> 'proposal_id')::uuid;
$$;

select pg_temp.athlete(pg_temp.u(1));
select pg_temp.athlete(pg_temp.u(2));
select pg_temp.athlete(pg_temp.u(3));
select pg_temp.athlete(pg_temp.u(4));
create temporary table t as select private.local_date_for(pg_temp.u(1)) as today;
create temporary table r(name text primary key, j jsonb);
create temporary table p(name text primary key, id uuid);
grant select on t to authenticated;
grant all on r, p to authenticated;

-- 1. The table: owner read, no client writes ------------------------------------------------------------

select has_table('public'::name, 'training_pauses'::name, 'training_pauses exists');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.training_pauses'::regclass), 'row level security is on and forced');
select ok(has_table_privilege('authenticated', 'public.training_pauses', 'select')
    and not has_table_privilege('authenticated', 'public.training_pauses', 'insert')
    and not has_table_privilege('authenticated', 'public.training_pauses', 'update')
    and not has_table_privilege('authenticated', 'public.training_pauses', 'delete')
    and not has_table_privilege('anon', 'public.training_pauses', 'select'),
  'the athlete may only read; writes go through the functions');
select throws_ok($$insert into public.training_pauses(user_id, start_date, end_date, reason, source)
    values (pg_temp.u(1), current_date, current_date + 50, 'rest', 'athlete')$$,
  '23514', null, 'a break of more than 42 days is refused by the table');
select throws_ok($$insert into public.training_pauses(user_id, start_date, end_date, reason, source)
    values (pg_temp.u(1), current_date, current_date, 'rest', 'coach')$$,
  '23514', null, 'a Coach break names its proposal');

-- 2. Who may call what ----------------------------------------------------------------------------------

select ok(has_function_privilege('authenticated', 'public.start_training_pause_v1(date, date, text)', 'execute')
    and has_function_privilege('authenticated', 'public.end_training_pause_v1(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.start_training_pause_v1(date, date, text)', 'execute')
    and not has_function_privilege('anon', 'public.end_training_pause_v1(uuid)', 'execute'),
  'a signed-in athlete sets and ends their own break; a signed-out caller cannot');
select ok(has_function_privilege('service_role', 'public.get_coach_standing_state_v1(uuid, date)', 'execute')
    and not has_function_privilege('authenticated', 'public.get_coach_standing_state_v1(uuid, date)', 'execute')
    and has_function_privilege('service_role', 'public.get_training_pause_inputs_v1(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.get_training_pause_inputs_v1(uuid)', 'execute'),
  'only the service role reads the standing state and the break inputs');
select ok(not (select bool_or(has_function_privilege('authenticated', p.oid, 'execute')
      or has_function_privilege('anon', p.oid, 'execute'))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = any(array['availability_on', 'is_paused_on',
      'paused_days', 'training_pause_problem', 'insert_training_pause', 'end_training_pause',
      'pause_last_day', 'training_pause_json', 'is_valid_coach_pause'])),
  'the private helpers are not callable by the app');
select ok((select bool_and(prosecdef and proconfig = array['search_path=""']) from pg_proc
    where oid in ('public.start_training_pause_v1(date, date, text)'::regprocedure,
      'public.end_training_pause_v1(uuid)'::regprocedure,
      'public.get_coach_standing_state_v1(uuid, date)'::regprocedure,
      'public.get_training_pause_inputs_v1(uuid)'::regprocedure,
      'private.availability_on(uuid, date, boolean)'::regprocedure)),
  'the new functions are security definer with an empty search path');
select hasnt_function('public'::name, 'persist_coach_session_summary',
  array['uuid', 'date', 'text', 'uuid', 'uuid[]'], 'the dead summaries writer is gone');

-- 3. The athlete's own tap ------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000001';
insert into r select 'started', public.start_training_pause_v1((select today from t) + 1,
  (select today from t) + 15, ' Need a rest ');
select is((select j ->> 'status' from r where name = 'started'), 'started', 'a 15-day break from tomorrow starts');
insert into r select 'past', public.start_training_pause_v1((select today from t) - 1, (select today from t) + 2);
insert into r select 'far', public.start_training_pause_v1((select today from t) + 3, (select today from t) + 5);
insert into r select 'long', public.start_training_pause_v1((select today from t), (select today from t) + 42);
insert into r select 'backwards', public.start_training_pause_v1((select today from t) + 2, (select today from t) + 1);
insert into r select 'overlap', public.start_training_pause_v1((select today from t) + 2, (select today from t) + 20);
insert into r select 'note', public.start_training_pause_v1((select today from t), (select today from t), repeat('x', 141));
select is((select array_agg(j ->> 'refusal' order by name) from r
    where name in ('backwards', 'far', 'long', 'note', 'overlap', 'past')),
  array['dates_invalid', 'pause_start_too_far', 'pause_too_long', 'note_too_long', 'pause_overlaps',
    'pause_start_past'],
  'every refusal names its rule');
select is((select count(*)::integer from r where name in ('past', 'far', 'long', 'backwards', 'overlap', 'note')
    and j ->> 'status' = 'refused' and j -> 'pause_id' = 'null'::jsonb), 6, 'and writes nothing');
select is((select count(*)::integer from public.training_pauses), 1, 'the athlete sees only their own break');
reset role;
insert into p select 'a_break', (j ->> 'pause_id')::uuid from r where name = 'started';
select is((select array[reason, note, source, (end_date - start_date + 1)::text] from public.training_pauses
    where id = (select id from p where name = 'a_break')),
  array['rest', 'Need a rest', 'athlete', '15'], 'the row keeps the reason, the athlete''s words and the dates');
select is((select count(*)::integer from public.audit_events where target_id = (select id from p where name = 'a_break')
    and action_code = 'training_pause_started'), 1, 'and an audit event');
-- A break starting today and 42 days long is the longest allowed.
set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000002';
insert into r select 'b_longest', public.start_training_pause_v1((select today from t) + 2, (select today from t) + 43);
reset role;
select is((select j ->> 'status' from r where name = 'b_longest'), 'started', '42 days from two days ahead is allowed');
set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from public.training_pauses), 1,
  'another athlete''s break is not in the first athlete''s rows');
reset role;

-- 4. Availability ---------------------------------------------------------------------------------------

select is(private.availability_on(pg_temp.u(1), (select today from t) + 3, false) ->> 'status', 'paused',
  'a day inside the break is paused');
select is(private.availability_on(pg_temp.u(1), (select today from t) + 3, false) -> 'pause' ->> 'end_date',
  ((select today from t) + 15)::text, 'with the break''s last day');
select is((select array[j ->> 'status', j -> 'pause' ->> 'running']
    from (select private.availability_on(pg_temp.u(1), (select today from t), false) j) x),
  array['available', 'false'], 'the day before it is available, with the break ahead');
select is(private.availability_on(pg_temp.u(1), (select today from t) + 16, false) ->> 'status', 'available',
  'the plan resumes by itself the day after the last day');
select is(private.availability_on(pg_temp.u(1), (select today from t) + 16, false) -> 'return_from_pause' ->> 'last_paused_day',
  ((select today from t) + 15)::text, 'and the first day back says so');
select ok(private.availability_on(pg_temp.u(1), (select today from t) + 30, false) -> 'return_from_pause' = 'null'::jsonb,
  'not after a week');
select pg_temp.check_in(pg_temp.u(3), (select today from t) - 1, false);
select pg_temp.check_in(pg_temp.u(3), (select today from t), false);
select is((select array[j ->> 'status', j ->> 'unavailable_today', j ->> 'offer_break']
    from (select private.availability_on(pg_temp.u(3), (select today from t), true) j) x),
  array['unavailable_today', 'true', 'true'],
  'a can''t-train check-in makes today unavailable, and two in a row offer a break');
select is(private.availability_on(pg_temp.u(3), (select today from t) - 1, true) ->> 'offer_break', 'false',
  'one alone offers nothing');
select is(private.availability_on(pg_temp.u(1), (select today from t) + 3, true) ->> 'safety_route', null,
  'no safety route without a pain report');
select is((select array_agg(d order by d) from private.paused_days(pg_temp.u(1), (select today from t),
    (select today from t) + 2) d), array[(select today from t) + 1, (select today from t) + 2],
  'the paused days are the break''s days only');

-- 5. Ending early ---------------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000001';
insert into r select 'cancel', public.end_training_pause_v1((select id from p where name = 'a_break'));
insert into r select 'again', public.end_training_pause_v1((select id from p where name = 'a_break'));
insert into r select 'today', public.start_training_pause_v1((select today from t), (select today from t) + 3);
reset role;
select is((select j ->> 'status' from r where name = 'cancel'), 'cancelled', 'a break not begun is cancelled');
select is((select j ->> 'status' from r where name = 'again'), 'not_running', 'ending it again changes nothing');
select is(private.availability_on(pg_temp.u(1), (select today from t) + 3, false) ->> 'status', 'available',
  'a cancelled break covers no day');
select ok(private.availability_on(pg_temp.u(1), (select today from t) + 16, false) -> 'return_from_pause' = 'null'::jsonb,
  'and has no first day back');
select is(private.availability_on(pg_temp.u(1), (select today from t), false) ->> 'status', 'paused',
  'a break from today makes today paused');
set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000001';
insert into r select 'early', public.end_training_pause_v1(((select j from r where name = 'today') ->> 'pause_id')::uuid);
reset role;
select is((select array[j ->> 'status', j ->> 'ended_on'] from r where name = 'early'),
  array['ended', ((select today from t))::text], 'End break early ends it today');
select is(private.availability_on(pg_temp.u(1), (select today from t), false) ->> 'status', 'available',
  'so today is available again');
select is((select count(*)::integer from public.audit_events where user_id = pg_temp.u(1)
    and action_code = 'training_pause_ended'), 2, 'each end is audited');
set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000002';
select throws_ok($$select public.end_training_pause_v1((select id from p where name = 'a_break'))$$,
  'P0002', 'break not found', 'another athlete cannot end it');
reset role;

-- 6. A Coach proposal: store, approve, undo -------------------------------------------------------------

select is((public.get_training_pause_inputs_v1(pg_temp.u(4)) ->> 'local_date'), ((select today from t))::text,
  'the inputs carry the athlete''s date');
insert into p select 'proposal', pg_temp.store_pause(pg_temp.u(4), (select today from t), (select today from t) + 4);
select is((select proposal_kind || ' ' || status::text from public.change_proposals
    where id = (select id from p where name = 'proposal')), 'training_pause pending',
  'a break proposal is stored pending, with no profile or plan behind it');
select throws_ok($$select public.persist_coach_proposal_v1(pg_temp.u(4), 'training_pause', 'Break', 'r', 'b', 'd',
    'high', '[]', '{"rows":[]}', '{"rows":[]}',
    '{"pause":{"start_date":"2026-11-01","end_date":"2026-11-02","reason":"rest"},"training":{"mode":"end_block"}}',
    '{"screening":"cleared","gates":[]}', null, 24)$$,
  '22023', 'coach proposal is invalid', 'a break carries nothing but the break');
select throws_ok($$select public.persist_coach_proposal_v1(pg_temp.u(4), 'training_pause', 'Break', 'r', 'b', 'd',
    'high', '[]', '{"rows":[]}', '{"rows":[]}',
    '{"pause":{"start_date":"2026-11-01","end_date":"2026-11-02","reason":"plateau"}}',
    '{"screening":"cleared","gates":[]}', null, 24)$$,
  '22023', 'coach proposal is invalid', 'a break''s reason is from its own list');
set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000004';
insert into r select 'approved', public.respond_to_coach_proposal_v1((select id from p where name = 'proposal'), 'approve');
reset role;
select is((select j ->> 'status' from r where name = 'approved'), 'accepted', 'one tap approves it');
select is((select array[source, start_date::text, end_date::text] from public.training_pauses
    where source_proposal_id = (select id from p where name = 'proposal')),
  array['coach', ((select today from t))::text, ((select today from t) + 4)::text],
  'approval writes the break as an overlay row');
select is((select count(*)::integer from public.training_plan_versions where user_id = pg_temp.u(4)), 0,
  'and no plan version');
select ok((select applied_changes ? 'pause_id' from public.change_proposals where id = (select id from p where name = 'proposal')),
  'the proposal remembers the break it wrote');
select is((select count(*)::integer from public.audit_events where user_id = pg_temp.u(4)
    and action_code in ('coach_proposal_accepted', 'training_pause_started')), 2,
  'the approval and the break are both audited');
select is(private.availability_on(pg_temp.u(4), (select today from t), false) ->> 'status', 'paused',
  'the athlete is on a break today');
select is((private.coach_proposal_json(c) ->> 'can_undo') from public.change_proposals c
    where id = (select id from p where name = 'proposal'), 'true', 'it can be undone');
-- A second break over the first is refused when it is stored.
select throws_ok($$select pg_temp.store_pause(pg_temp.u(4), (select today from t) + 2, (select today from t) + 6)$$,
  '55000', 'the break no longer fits', 'a break over another is refused');
set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000004';
insert into r select 'undone', public.undo_coach_proposal_v1((select id from p where name = 'proposal'));
reset role;
select is((select j ->> 'status' from r where name = 'undone'), 'undone', 'undo works as for any proposal');
select is((select array[end_reason, ended_on::text] from public.training_pauses
    where source_proposal_id = (select id from p where name = 'proposal')),
  array['undone', ((select today from t))::text], 'it ends the break, keeping the row');
select is(private.availability_on(pg_temp.u(4), (select today from t), false) ->> 'status', 'available',
  'today is available again');
select ok(private.availability_on(pg_temp.u(4), (select today from t) + 1, false) -> 'return_from_pause' = 'null'::jsonb,
  'an undone break has no first day back');
-- Approval re-checks the dates: a break that now overlaps another expires.
insert into p select 'late', pg_temp.store_pause(pg_temp.u(4), (select today from t) + 1, (select today from t) + 3);
do $$ begin
  perform private.insert_training_pause(pg_temp.u(4), (select today from t) + 2, (select today from t) + 2,
    'rest', null, 'athlete', null);
end $$;
set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000004';
insert into r select 'late', public.respond_to_coach_proposal_v1((select id from p where name = 'late'), 'approve');
reset role;
select is((select array[j ->> 'status', j ->> 'reason'] from r where name = 'late'),
  array['expired', 'pause_overlaps'], 'a break that overlaps one set since expires on approval');

-- 7. The brief and the hub carry it, additively ---------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'c5000000-0000-4000-8000-000000000002';
insert into r select 'hub', public.get_my_training_hub(28);
insert into r select 'brief', public.get_my_daily_brief((select today from t) + 3);
reset role;
select is((select j ->> 'schema_version' from r where name = 'hub'), '1.10', 'hub 1.10');
select ok((select j ? 'availability' and j ? 'paused_days' and j -> 'adherence' ? 'paused_sessions'
    and j ? 'active_plan' and j ? 'next_targets' from r where name = 'hub'), 'the hub adds its keys and keeps the old ones');
select is((select j -> 'paused_days' ->> 0 from r where name = 'hub'), ((select today from t) + 2)::text,
  'the paused days start with the break');
select is((select j -> 'availability' -> 'pause' ->> 'running' from r where name = 'hub'), 'false',
  'and the break ahead is in the availability');
select is((select j ->> 'schema_version' from r where name = 'brief'), '1.9', 'brief 1.9');
select is((select j -> 'availability' ->> 'status' from r where name = 'brief'), 'paused',
  'the brief for a day in the break says paused');

-- 8. The readiness card and its Coach view --------------------------------------------------------------

select is(private.day_adjustment_explanation('amber', 'none', array['not_available'], null, '[]', true, null),
  'Rest day: you said you can''t train today.', 'an unavailable day reads as a rest the athlete chose');
select is(private.day_adjustment_explanation('unknown', 'none', array['paused'], null, '[]', true, null),
  'Rest day: you''re on a break, so no session is due today.', 'a day in a break reads as a rest day');
select is(public.get_readiness_context_v1(pg_temp.u(3), (select today from t)) ->> 'athlete_unavailable', 'true',
  'the Coach view says the athlete cannot train today');
select is(public.get_readiness_context_v1(pg_temp.u(1), (select today from t)) ->> 'athlete_unavailable', 'false',
  'and false otherwise');

-- 9. The Coach's standing state -------------------------------------------------------------------------

insert into r select 'standing', public.get_coach_standing_state_v1(pg_temp.u(3), (select today from t));
select is((select j -> 'availability' ->> 'status' from r where name = 'standing'), 'unavailable_today',
  'the standing state carries today''s availability');
select is((select j -> 'unavailable_days' from r where name = 'standing'),
  jsonb_build_array((select today from t) - 1, (select today from t)), 'and the days the athlete could not train');
select ok((select j ? 'joint_areas' and j ? 'goal' and j ? 'decisions' and j ? 'breaks' and j ? 'paused_days'
    and j ->> 'schema_version' = '1.0' from r where name = 'standing'), 'with every part of its contract');
select is((select jsonb_array_length(public.get_coach_standing_state_v1(pg_temp.u(4), (select today from t)) -> 'decisions')),
  1, 'the answered proposals of the last 14 days are its decisions (an expired one is not)');

-- 10. The daily decision rests as chosen ----------------------------------------------------------------

insert into r select 'decide_unavailable', private.prepare_daily_coaching_core(pg_temp.u(3), (select today from t),
  'UTC', gen_random_uuid(), true);
select is((select array[j ->> 'policy_outcome', (j -> 'permitted_evidence' ? 'ATHLETE_UNAVAILABLE_TODAY')::text]
    from r where name = 'decide_unavailable'), array['rest_as_chosen', 'true'],
  'a can''t-train check-in rests as chosen, with its evidence code');
insert into r select 'decide_paused', private.prepare_daily_coaching_core(pg_temp.u(2), (select today from t) + 3,
  'UTC', gen_random_uuid(), true);
select is((select array[j ->> 'policy_outcome', (j -> 'permitted_evidence' ? 'TRAINING_PAUSED')::text]
    from r where name = 'decide_paused'), array['rest_as_chosen', 'true'],
  'a day in a break rests as chosen, even with no check-in');
select is((select permitted_actions from public.policy_evaluations
    where id = ((select j from r where name = 'decide_paused') ->> 'policy_evaluation_id')::uuid),
  array['REST_AS_CHOSEN', 'MAINTAIN_TARGETS', 'PRIORITIZE_PROTEIN'], 'and proceeding as planned is not permitted');
select lives_ok($$select public.persist_daily_coaching_result_v2(pg_temp.u(3),
    ((select j from r where name = 'decide_unavailable') ->> 'feature_snapshot_id')::uuid,
    ((select j from r where name = 'decide_unavailable') ->> 'policy_evaluation_id')::uuid,
    gen_random_uuid(),
    jsonb_build_object('schema_version', '1.0', 'decision_kind', 'daily', 'local_date', (select today from t),
      'training', '{"action":"REST_AS_CHOSEN","summary":"Rest today.","today_adjustments":[]}'::jsonb,
      'nutrition', '{"action":"MAINTAIN_TARGETS","summary":"Keep the targets.","today_adjustments":[]}'::jsonb,
      'head_coach', '{"final_decision":"Rest today, as you chose.","reason":"Your check-in."}'::jsonb,
      'evidence', '[{"code":"ATHLETE_UNAVAILABLE_TODAY","label":"You said you cannot train","source":"policy_evaluation"},
        {"code":"TRAINING_PAUSED","label":"On a break","source":"policy_evaluation"}]'::jsonb,
      'confidence', 'high', 'missing_data', '[]'::jsonb, 'risk_flags', '[]'::jsonb,
      'change_proposals', '[]'::jsonb),
    0, 'mock', 'deterministic-mock-v2', 0, 0, 0)$$,
  'a decision may cite the two new evidence codes');

select * from finish();
rollback;
