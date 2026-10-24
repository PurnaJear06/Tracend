begin;
select no_plan();

-- B5-1: the pain check. The outcome table and its boundaries, the table's constraints and privacy, the
-- check-in that carries a pain check, the workout chip, and the audit trail. How reports become a
-- joint's state is in joint_states_test.sql; what a state changes in today's session is in
-- joint_rules_test.sql and joint_swap_sweep_test.sql.

insert into auth.users(id, role) values
  ('b5000000-0000-4000-8000-000000000001', 'authenticated'),
  ('b5000000-0000-4000-8000-000000000002', 'authenticated'),
  ('b5000000-0000-4000-8000-000000000003', 'authenticated'),
  ('b5000000-0000-4000-8000-000000000004', 'authenticated'),
  ('b5000000-0000-4000-8000-000000000005', 'authenticated');

create temporary table t as
  select private.local_date_for('b5000000-0000-4000-8000-000000000001') as today;
grant select on t to authenticated;

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid, true);
end $$;

-- A complete check-in payload with the extra keys merged in.
create function pg_temp.payload(p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3,
    "available_to_train": true}'::jsonb || p_extra;
$$;

-- Shape and privileges ----------------------------------------------------------------------------------

select has_table('public', 'pain_reports', 'the reports table exists');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.pain_reports'::regclass), 'row-level security is on and forced');
select ok(has_table_privilege('authenticated', 'public.pain_reports', 'select')
  and not has_table_privilege('authenticated', 'public.pain_reports', 'insert')
  and not has_table_privilege('authenticated', 'public.pain_reports', 'update')
  and not has_table_privilege('authenticated', 'public.pain_reports', 'delete')
  and not has_table_privilege('anon', 'public.pain_reports', 'select'),
  'athletes read their reports and cannot write them; signed-out callers read nothing');
select ok(has_function_privilege('authenticated',
    'public.record_pain_check_v1(date, text, text, integer, text, text[], boolean, uuid, uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.record_pain_check_v1(date, text, text, integer, text, text[], boolean, uuid, uuid)', 'execute'),
  'athletes record a workout pain check; signed-out callers cannot');
select ok(has_function_privilege('authenticated', 'public.save_daily_check_in(date, text, uuid, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.save_daily_check_in(date, text, uuid, jsonb)', 'execute'),
  'the check-in keeps its grants');
select ok(has_function_privilege('service_role', 'public.get_readiness_context_v1(uuid, date)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_readiness_context_v1(uuid, date)', 'execute')
  and not has_function_privilege('anon', 'public.get_readiness_context_v1(uuid, date)', 'execute'),
  'only the service role reads the Coach context view');
select ok((select bool_and(prosecdef and proconfig = array['search_path=""']) from pg_proc
    where oid in (
      'public.record_pain_check_v1(date, text, text, integer, text, text[], boolean, uuid, uuid)'::regprocedure,
      'public.save_daily_check_in(date, text, uuid, jsonb)'::regprocedure,
      'public.get_readiness_context_v1(uuid, date)'::regprocedure)),
  'all three are security definer with an empty search path');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = any(array['pain_rules', 'pain_red_flag_codes',
      'pain_outcome', 'insert_pain_report', 'joint_states', 'joint_rules', 'stress_rank', 'level_rank',
      'joint_action_rank', 'safety_route_rank', 'range_note_code', 'joint_swap', 'joint_options',
      'joint_changes', 'merge_day_changes', 'day_changes_merged', 'joint_sentence',
      'persistent_sentence', 'joint_states_detail', 'joint_caps', 'local_day_of', 'joint_change_keys',
      'hold_reminder'])), 23::bigint, 'the twenty-three private helpers exist');
select ok(not (select bool_or(has_function_privilege('authenticated', p.oid, 'execute')
        or has_function_privilege('anon', p.oid, 'execute'))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = any(array['pain_rules', 'pain_red_flag_codes',
      'pain_outcome', 'insert_pain_report', 'joint_states', 'joint_rules', 'stress_rank', 'level_rank',
      'joint_action_rank', 'safety_route_rank', 'range_note_code', 'joint_swap', 'joint_options',
      'joint_changes', 'merge_day_changes', 'day_changes_merged', 'joint_sentence',
      'persistent_sentence', 'joint_states_detail', 'joint_caps', 'local_day_of', 'joint_change_keys',
      'hold_reminder'])), 'and none of them is callable by an athlete or a signed-out caller');

-- The outcome table ---------------------------------------------------------------------------------------

select is(private.pain_red_flag_codes(), array['bladder_bowel_saddle', 'cannot_bear_or_move',
  'chest_or_breath', 'dislocated_or_cannot_lift', 'fever_unwell', 'locks_gives_way', 'night_pain',
  'numb_weak_limb', 'pop_or_sudden', 'rapid_swelling'], 'the red-flag list is closed and has ten codes');

-- Severity alone (no red-flag question asked, or none chosen).
select is((select count(*) from (values
    (0, null::text[], 'clear'), (1, null, 'watch'), (3, null, 'watch'), (4, null, 'modify'),
    (6, null, 'modify'), (7, null, 'clinician_today'), (10, null, 'clinician_today'),
    (0, '{}', 'clear'), (1, '{}', 'watch'), (3, '{}', 'watch'), (4, '{}', 'modify'),
    (6, '{}', 'modify'), (7, '{}', 'clinician_today'), (10, '{}', 'clinician_today')
  ) v(sev, flags, expected) where private.pain_outcome(v.sev, v.flags) is distinct from v.expected),
  0::bigint, 'severity alone: 0 clear, 1 to 3 watch, 4 to 6 modify, 7 or more clinician today');

-- Every red-flag code at every boundary severity: urgent and clinician_today codes decide the outcome
-- whatever the severity; a clinician code gives way to the severity rule at 7 or more.
select is((select count(*) from (values
      ('bladder_bowel_saddle', 'urgent'), ('chest_or_breath', 'urgent'),
      ('numb_weak_limb', 'clinician_today'), ('pop_or_sudden', 'clinician_today'),
      ('cannot_bear_or_move', 'clinician_today'), ('rapid_swelling', 'clinician_today'),
      ('dislocated_or_cannot_lift', 'clinician_today'), ('locks_gives_way', 'clinician'),
      ('fever_unwell', 'clinician'), ('night_pain', 'clinician')) c(code, class)
    cross join (values (0), (1), (3), (4), (6), (7), (10)) s(sev)
    where private.pain_outcome(s.sev, array[c.code]) is distinct from
      case when c.class = 'urgent' then 'urgent'
        when c.class = 'clinician_today' or s.sev >= 7 then 'clinician_today'
        else 'clinician' end),
  0::bigint, 'each of the ten codes routes as listed at severities 0, 1, 3, 4, 6, 7 and 10');
select is(private.pain_outcome(2, array['night_pain', 'rapid_swelling']), 'clinician_today',
  'two flags: the stricter outcome wins');
select is(private.pain_outcome(2, array['night_pain', 'bladder_bowel_saddle', 'rapid_swelling']), 'urgent',
  'and an urgent flag beats them all');
select is(private.pain_outcome(2, array['night_pain', 'fever_unwell']), 'clinician',
  'two clinician flags stay clinician');
select is(private.pain_outcome(9, array['night_pain']), 'clinician_today',
  'a clinician flag with severity 7 or more is clinician today');
select is(private.pain_outcome(0, array['fever_unwell']), 'clinician',
  'a red flag routes out even with a severity of 0');

-- A threshold one step weaker is caught by the table above.
create function pg_temp.weak_outcome(p_severity integer, p_red_flags text[]) returns text language sql as $$
  select case
    when 'urgent' = any(array(select case f when 'bladder_bowel_saddle' then 'urgent'
      when 'chest_or_breath' then 'urgent' end from unnest(coalesce(p_red_flags, '{}')) f)) then 'urgent'
    when p_severity >= 8 then 'clinician_today'
    when p_severity >= 5 then 'modify'
    when p_severity >= 2 then 'watch' else 'clear' end;
$$;
select ok((select count(*) from (values (1, 'watch'), (4, 'modify'), (6, 'modify'), (7, 'clinician_today'))
    v(sev, expected) where pg_temp.weak_outcome(v.sev, null) is distinct from v.expected) > 0,
  'a rule with the bands moved up by one fails the table');

-- Table constraints --------------------------------------------------------------------------------------

select throws_ok($$insert into public.pain_reports(user_id, local_date, source, area, severity, outcome)
  values ('b5000000-0000-4000-8000-000000000001', current_date, 'workout', 'knee', 8, 'watch')$$,
  '23514', null, 'a stored outcome that disagrees with its answers is refused');
select throws_ok($$insert into public.pain_reports(user_id, local_date, source, area, severity, red_flags, outcome)
  values ('b5000000-0000-4000-8000-000000000001', current_date, 'workout', 'knee', 3, '{made_up}', 'watch')$$,
  '23514', null, 'a red flag outside the list is refused');
select throws_ok($$insert into public.pain_reports(user_id, local_date, source, area, severity, outcome)
  values ('b5000000-0000-4000-8000-000000000001', current_date, 'workout', 'knee', 11, 'clinician_today')$$,
  '23514', null, 'a severity above 10 is refused');
select throws_ok($$insert into public.pain_reports(user_id, local_date, source, area, severity, outcome)
  values ('b5000000-0000-4000-8000-000000000001', current_date, 'workout', 'neck', 3, 'watch')$$,
  '23514', null, 'an unknown area is refused');
select throws_ok($$insert into public.pain_reports(user_id, local_date, source, area, severity, pattern, outcome)
  values ('b5000000-0000-4000-8000-000000000001', current_date, 'workout', 'knee', 3, 'sometimes', 'watch')$$,
  '23514', null, 'an unknown pattern is refused');
select throws_ok($$insert into public.pain_reports(user_id, local_date, source, area, severity, outcome)
  values ('b5000000-0000-4000-8000-000000000001', current_date, 'gym', 'knee', 3, 'watch')$$,
  '23514', null, 'an unknown source is refused');

-- The check-in that carries a pain check ----------------------------------------------------------------

select pg_temp.as_user('b5000000-0000-4000-8000-000000000004');

-- An older build sends none of the pain keys: the check-in is saved and no report is made.
select public.save_daily_check_in((select today from t), 'UTC', 'b5200000-0000-4000-8000-000000000001',
  pg_temp.payload('{"pain_severity": 5}'));
select is((select count(*) from public.daily_check_ins where user_id = 'b5000000-0000-4000-8000-000000000004'),
  1::bigint, 'an older build''s check-in is saved');
select is((select count(*) from public.pain_reports where user_id = 'b5000000-0000-4000-8000-000000000004'),
  0::bigint, 'and makes no report');

-- A new build: area, pattern and the red-flag answer.
create temporary table saved(name text, id uuid);
insert into saved select 'knee', public.save_daily_check_in((select today from t), 'UTC',
  'b5200000-0000-4000-8000-000000000002',
  pg_temp.payload('{"pain_severity": 5, "pain_area": "knee", "pain_pattern": "movement", "pain_red_flags": []}'));
select is((select array[r.area, r.severity::text, r.pattern, r.outcome, r.source, r.cleared_by_clinician::text,
      r.red_flags::text, (r.check_in_id = s.id)::text]
    from public.pain_reports r join saved s on s.name = 'knee'
    where r.user_id = 'b5000000-0000-4000-8000-000000000004'),
  array['knee', '5', 'movement', 'modify', 'check_in', 'false', '{}', 'true'],
  'a pain of 5 in the knee when moving, no red flag: modify, tied to the check-in');
select is((select metadata from public.audit_events
    where user_id = 'b5000000-0000-4000-8000-000000000004' and action_code = 'pain_check_recorded'),
  '{"area": "knee", "source": "check_in", "outcome": "modify"}'::jsonb,
  'the audit event carries the source, the area and the outcome and nothing else');

-- Saving the same check-in again changes nothing.
select is(public.save_daily_check_in((select today from t), 'UTC', 'b5200000-0000-4000-8000-000000000002',
    pg_temp.payload('{"pain_severity": 9, "pain_area": "back", "pain_red_flags": ["night_pain"]}')),
  (select id from saved where name = 'knee'), 'a repeated key returns the first check-in');
select is((select count(*) from public.pain_reports where user_id = 'b5000000-0000-4000-8000-000000000004'),
  1::bigint, 'and adds no report');
select is((select count(*) from public.audit_events
    where user_id = 'b5000000-0000-4000-8000-000000000004' and action_code = 'pain_check_recorded'),
  1::bigint, 'or audit event');

-- A later check-in the same day: its own report; the earlier report stays on record.
select public.save_daily_check_in((select today from t), 'UTC', 'b5200000-0000-4000-8000-000000000003',
  pg_temp.payload('{"pain_severity": 8, "pain_area": "back",
    "pain_red_flags": ["night_pain", "bladder_bowel_saddle"]}'));
select is((select array[r.area, r.severity::text, r.outcome, r.red_flags::text]
    from public.pain_reports r where r.user_id = 'b5000000-0000-4000-8000-000000000004' and r.area = 'back'),
  array['back', '8', 'urgent', '{bladder_bowel_saddle,night_pain}'],
  'a red flag in the back: urgent, the codes stored sorted');
select is((select count(*) from public.pain_reports where user_id = 'b5000000-0000-4000-8000-000000000004'),
  2::bigint, 'the earlier report is not replaced');

-- Follow-ups for areas that were already active ride on the same check-in.
select public.save_daily_check_in((select today from t), 'UTC', 'b5200000-0000-4000-8000-000000000004',
  pg_temp.payload('{"pain_severity": 4, "pain_area": "other", "pain_pattern": null,
    "pain_red_flags": ["night_pain"],
    "pain_followups": [{"area": "knee", "severity": 2}, {"area": "shoulder", "severity": 0,
      "cleared_by_clinician": false}]}'));
select is((select array_agg(r.area || ':' || r.severity || ':' || r.outcome order by r.area)
    from public.pain_reports r
    where r.user_id = 'b5000000-0000-4000-8000-000000000004'
      and r.check_in_id = (select c.id from public.daily_check_ins c
        where c.user_id = 'b5000000-0000-4000-8000-000000000004' and c.superseded_at is null)),
  array['knee:2:watch', 'other:4:clinician', 'shoulder:0:clear'],
  'the main area and each follow-up get a report: a clinician flag, a watch and a clear');
select is((select r.red_flags from public.pain_reports r
    where r.user_id = 'b5000000-0000-4000-8000-000000000004' and r.area = 'knee' and r.severity = 2),
  null::text[],
  'a follow-up asks no red-flag question, so its flags are null (judged by severity alone)');

-- A held area's follow-up can say a clinician cleared it.
select public.save_daily_check_in((select today from t), 'UTC', 'b5200000-0000-4000-8000-000000000005',
  pg_temp.payload('{"pain_severity": 2, "pain_area": "shoulder", "pain_red_flags": [],
    "pain_cleared_by_clinician": true}'));
select is((select r.cleared_by_clinician from public.pain_reports r
    where r.user_id = 'b5000000-0000-4000-8000-000000000004' and r.area = 'shoulder' and r.severity = 2), true,
  'the clearance the athlete states is stored');

-- A pain check in a check-in is for the server's today or yesterday; a phone a day ahead is stored under today.
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()) - 2, 'UTC',
    'b5200000-0000-4000-8000-000000000031',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": "knee", "pain_red_flags": []}'::jsonb)$$,
  '22023', null, 'a pain check in a check-in two days old is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()) + 2, 'UTC',
    'b5200000-0000-4000-8000-000000000032',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": "knee", "pain_red_flags": []}'::jsonb)$$,
  '22023', null, 'and one two days ahead');
select public.save_daily_check_in((select today from t) + 1, 'UTC', 'b5200000-0000-4000-8000-000000000033',
  pg_temp.payload('{"pain_severity": 9, "pain_area": "back", "pain_red_flags": ["numb_weak_limb"]}'));
select is((select r.local_date from public.pain_reports r
    where r.user_id = 'b5000000-0000-4000-8000-000000000004' and r.severity = 9),
  (select today from t), 'a check-in from a phone a day ahead keeps its pain report on the server''s today');

-- Refused: nothing is dropped silently, and a refused check-in saves nothing.
create temporary table before(c bigint, p bigint);
insert into before select (select count(*) from public.daily_check_ins
    where user_id = 'b5000000-0000-4000-8000-000000000004'),
  (select count(*) from public.pain_reports where user_id = 'b5000000-0000-4000-8000-000000000004');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000011',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_pattern": "movement"}'::jsonb)$$,
  '22023', null, 'a new build''s pain with no area is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000012',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 0, "pain_area": "knee", "pain_red_flags": []}'::jsonb)$$,
  '22023', null, 'an area with no pain is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000013',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": "knee"}'::jsonb)$$,
  '22023', null, 'pain with an area but no red-flag answer is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000014',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": "knee", "pain_red_flags": ["made_up"]}'::jsonb)$$,
  '22023', null, 'a red flag outside the list is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000015',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 0, "pain_red_flags": ["night_pain"]}'::jsonb)$$,
  '22023', null, 'red flags with no area are refused, never dropped');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000016',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": 7, "pain_red_flags": []}'::jsonb)$$,
  '22023', null, 'an area that is not text is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000017',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": "neck", "pain_red_flags": []}'::jsonb)$$,
  '22023', null, 'an unknown area is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000018',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": "knee", "pain_red_flags": [], "pain_pattern": "sometimes"}'::jsonb)$$,
  '22023', null, 'an unknown pattern is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000019',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": "knee", "pain_red_flags": [],
      "pain_cleared_by_clinician": "yes"}'::jsonb)$$,
  '22023', null, 'a clearance that is not true or false is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000020',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_severity": 4, "pain_area": "knee", "pain_red_flags": [],
      "pain_followups": [{"area": "knee", "severity": 1}]}'::jsonb)$$,
  '22023', null, 'one report per area: a follow-up for the main area is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000021',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_followups": [{"area": "knee", "severity": 1}, {"area": "knee", "severity": 2}]}'::jsonb)$$,
  '22023', null, 'and so is the same area twice among the follow-ups');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000022',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_followups": [{"area": "knee", "severity": 11}]}'::jsonb)$$,
  '22023', null, 'a follow-up severity above 10 is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000023',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_followups": [{"area": "knee", "severity": 2.5}]}'::jsonb)$$,
  '22023', null, 'and a fractional one');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000024',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_followups": [{"severity": 2}]}'::jsonb)$$,
  '22023', null, 'a follow-up with no area is refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000025',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true,
      "pain_followups": "knee"}'::jsonb)$$,
  '22023', null, 'follow-ups that are not a list are refused');
select throws_ok($$select public.save_daily_check_in(private.local_date_for(auth.uid()), 'UTC',
    'b5200000-0000-4000-8000-000000000026',
    '{"sleep_quality": 3, "energy": 3, "soreness": 3, "hunger": 3, "mood": 3, "available_to_train": true}'::jsonb
      || '{"pain_followups": [{"area": "knee", "severity": 2, "cleared_by_clinician": "maybe"}]}'::jsonb)$$,
  '22023', null, 'a follow-up clearance that is not true or false is refused');
select is((select (select count(*) from public.daily_check_ins
        where user_id = 'b5000000-0000-4000-8000-000000000004') - b.c from before b), 0::bigint,
  'a refused check-in saves nothing');
select is((select (select count(*) from public.pain_reports
        where user_id = 'b5000000-0000-4000-8000-000000000004') - b.p from before b), 0::bigint,
  'and leaves no report');

-- A check-in with no pain and no pain keys is unchanged (a new build with nothing to report too).
select public.save_daily_check_in((select today from t), 'UTC', 'b5200000-0000-4000-8000-000000000030',
  pg_temp.payload('{"pain_severity": 0, "pain_red_flags": []}'));
select is((select count(*) from public.pain_reports where user_id = 'b5000000-0000-4000-8000-000000000004'),
  (select b.p + 0 from before b), 'a new build with no pain makes no report');

-- The workout's pain chip -----------------------------------------------------------------------------------

create temporary table w(uid uuid primary key, version_id uuid, workout_id uuid, e1 uuid);
grant select on w to authenticated;
create function pg_temp.make_athlete(p_uid uuid, p_shift integer default 0) returns void language plpgsql as $$
declare
  pl uuid := gen_random_uuid(); v uuid := gen_random_uuid(); wo uuid := gen_random_uuid();
  a uuid := gen_random_uuid();
  wd integer := ((extract(isodow from private.local_date_for(p_uid))::integer - 1 + p_shift) % 7) + 1;
begin
  insert into public.training_plans(id, user_id, title, source) values (pl, p_uid, 'Strength', 'imported');
  insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
    sessions_per_week, prescription, rationale, approved_at, effective_date)
  values (v, p_uid, pl, 1, 'active', 6, 1, '{}', 'Approved', now(), current_date);
  insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
    preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
  values (wo, p_uid, v, 1, 'Lower A', 'Press', wd, 50, 'Warm up', 'Cool down');
  insert into public.planned_exercises(id, user_id, planned_workout_id, exercise_order,
    display_name_snapshot, set_count, rep_min, rep_max, target_rpe, rest_seconds, exercise_slug)
  values (a, p_uid, wo, 1, 'Barbell bench press', 4, 5, 8, 8, 120, 'barbell-bench-press');
  insert into w values (p_uid, v, wo, a);
end $$;

select pg_temp.make_athlete('b5000000-0000-4000-8000-000000000003');
select pg_temp.make_athlete('b5000000-0000-4000-8000-000000000005');

select pg_temp.as_user('b5000000-0000-4000-8000-000000000003');
select public.start_workout((select workout_id from w where uid = 'b5000000-0000-4000-8000-000000000003'),
  (select today from t), 'UTC', 'b5300000-0000-4000-8000-000000000001');
select pg_temp.as_user('b5000000-0000-4000-8000-000000000005');
select public.start_workout((select workout_id from w where uid = 'b5000000-0000-4000-8000-000000000005'),
  (select today from t), 'UTC', 'b5300000-0000-4000-8000-000000000002');
select pg_temp.as_user('b5000000-0000-4000-8000-000000000003');

create temporary table chip(name text, j jsonb);
insert into chip select 'knee5', public.record_pain_check_v1((select today from t), 'workout', 'knee', 5,
  'movement', '{}', false, null, 'b5400000-0000-4000-8000-000000000001');
select is((select array(select k from jsonb_object_keys(j) k order by k) from chip where name = 'knee5'),
  array['area_state', 'id', 'outcome', 'schema_version'], 'the result has exactly its four keys');
select is((select array[j ->> 'schema_version', j ->> 'outcome', j ->> 'area_state'] from chip where name = 'knee5'),
  array['1.0', 'modify', 'limited'], 'a 5 in the knee: modify, and the knee is limited');

-- The same key again returns the same report.
insert into chip select 'knee5_again', public.record_pain_check_v1((select today from t), 'workout', 'knee', 9,
  'rest', array['night_pain'], false, null, 'b5400000-0000-4000-8000-000000000001');
select is((select j from chip where name = 'knee5_again'), (select j from chip where name = 'knee5'),
  'a repeated key returns the first answer, not the new values');
select is((select count(*) from public.pain_reports
    where user_id = 'b5000000-0000-4000-8000-000000000003'), 1::bigint, 'and stores nothing more');
select is((select metadata from public.audit_events
    where user_id = 'b5000000-0000-4000-8000-000000000003' and action_code = 'pain_check_recorded'),
  '{"area": "knee", "source": "workout", "outcome": "modify"}'::jsonb, 'with one audit event of codes only');

-- Outcomes and the area's state, one area each so that reports never tie on time.
insert into chip select 'back8', public.record_pain_check_v1((select today from t) - 1, 'workout', 'back', 8,
  null, null, false, null, 'b5400000-0000-4000-8000-000000000002');
select is((select array[j ->> 'outcome', j ->> 'area_state'] from chip where name = 'back8'),
  array['clinician_today', 'held'], 'a 8 with no red-flag question asked: clinician today, the back is held');
insert into chip select 'shoulder3', public.record_pain_check_v1((select today from t), 'workout', 'shoulder', 3,
  null, '{}', false, null, 'b5400000-0000-4000-8000-000000000003');
select is((select array[j ->> 'outcome', j ->> 'area_state'] from chip where name = 'shoulder3'),
  array['watch', 'watch'], 'a 3 in the shoulder: watch');
insert into chip select 'other2', public.record_pain_check_v1((select today from t), 'workout', 'other', 2,
  null, array['locks_gives_way'], false, null, 'b5400000-0000-4000-8000-000000000004');
select is((select array[j ->> 'outcome', j ->> 'area_state'] from chip where name = 'other2'),
  array['clinician', 'held'], 'a red flag on a mild pain still holds the area');
select is((select array_agg(r.area order by r.area) from public.pain_reports r
    where r.user_id = 'b5000000-0000-4000-8000-000000000003' and r.outcome in ('clinician_today', 'clinician')),
  array['back', 'other'], 'the reports kept the outcomes');

-- The athlete's own performance may be named; another athlete's may not.
insert into chip select 'perf', public.record_pain_check_v1((select today from t), 'workout', 'knee', 4,
  'movement', '{}', false,
  (select p.id from public.exercise_performances p where p.user_id = 'b5000000-0000-4000-8000-000000000003'
    limit 1), 'b5400000-0000-4000-8000-000000000005');
select is((select j ->> 'outcome' from chip where name = 'perf'), 'modify', 'a report may name the exercise it was made on');
select ok((select r.exercise_performance_id is not null from public.pain_reports r
    where r.id = ((select j ->> 'id' from chip where name = 'perf')::uuid)), 'and keeps the link');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 4,
    'movement', '{}', false,
    (select p.id from public.exercise_performances p
      where p.user_id = 'b5000000-0000-4000-8000-000000000005' limit 1),
    'b5400000-0000-4000-8000-000000000006')$$,
  '22023', null, 'another athlete''s exercise is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'check_in', 'knee', 4,
    'movement', '{}', false,
    (select p.id from public.exercise_performances p
      where p.user_id = auth.uid() limit 1),
    'b5400000-0000-4000-8000-000000000007')$$,
  '22023', null, 'and an exercise belongs only to a workout report');

-- Bad values.
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()) + 2, 'workout', 'knee', 4,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000008')$$, '22023', null,
  'a date two days ahead of the server is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()) - 2, 'workout', 'knee', 4,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000021')$$, '22023', null,
  'and so is one two days behind: only today and yesterday go in');
insert into chip select 'ahead', public.record_pain_check_v1((select today from t) + 1, 'workout', 'other', 9,
  null, array['night_pain'], false, null, 'b5400000-0000-4000-8000-000000000022');
select is((select r.local_date from public.pain_reports r where r.id = (select (j ->> 'id')::uuid from chip
    where name = 'ahead')), (select today from t),
  'a phone a day ahead of the server is stored under the server''s today, and the red flag is kept');
select throws_ok($$select public.record_pain_check_v1(null, 'workout', 'knee', 4, null, null, false, null,
    'b5400000-0000-4000-8000-000000000009')$$, '22023', null, 'no date is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'gym', 'knee', 4,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000010')$$, '22023', null, 'an unknown source is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 4,
    null, null, false, null, null)$$, '22023', null, 'no key is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'neck', 4,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000011')$$, '22023', null, 'an unknown area is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 11,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000012')$$, '22023', null, 'a severity of 11 is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', -1,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000013')$$, '22023', null, 'and one below 0');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', null,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000014')$$, '22023', null, 'and no severity');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 4,
    'sometimes', null, false, null, 'b5400000-0000-4000-8000-000000000015')$$, '22023', null, 'an unknown pattern is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 4,
    null, array['made_up'], false, null, 'b5400000-0000-4000-8000-000000000016')$$, '22023', null,
  'a red flag outside the list is refused');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 4,
    null, null, null, null, 'b5400000-0000-4000-8000-000000000017')$$, '22023', null, 'a missing clearance answer is refused');

-- A stuck client cannot fill the table: forty reports a day, then P0001.
select pg_temp.as_user('b5000000-0000-4000-8000-000000000002');
insert into public.pain_reports(user_id, local_date, source, area, severity, outcome)
select 'b5000000-0000-4000-8000-000000000002', (select today from t), 'workout', 'knee', 2, 'watch'
from generate_series(1, 40);
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 2,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000018')$$, 'P0001', null,
  'the forty-first report of a day is refused');
select lives_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()) - 1, 'workout', 'knee', 2,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000019')$$,
  'yesterday has its own forty, and no other day can be used to get round the limit');
select lives_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'back', 3,
    null, array['night_pain'], false, null, 'b5400000-0000-4000-8000-000000000023')$$,
  'a report that routes out is stored however many came before it');
select lives_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 9,
    null, null, false, null, 'b5400000-0000-4000-8000-000000000024')$$,
  'so is a pain of 7 or more');
select throws_ok($$select public.record_pain_check_v1(private.local_date_for(auth.uid()), 'workout', 'knee', 2,
    null, null, true, null, 'b5400000-0000-4000-8000-000000000025')$$, 'P0001', null,
  'and those do not use up the limit: it counts only the reports that do not route out');
select is((select count(*) from public.pain_reports where user_id = 'b5000000-0000-4000-8000-000000000002'
    and local_date = (select today from t) and outcome not in ('urgent', 'clinician_today', 'clinician')),
  40::bigint, 'forty reports that do not route out are on file for the day');

-- Two calls with one key take turns (a second call finds the first's report and replays it).
select ok((select prosrc like '%pg_advisory_xact_lock(hashtextextended(%pain_check:%'
    from pg_proc where oid = 'public.record_pain_check_v1(date, text, text, integer, text, text[], boolean, uuid, uuid)'::regprocedure)
  and (select position('pg_advisory_xact_lock' in prosrc) < position('select * into report' in prosrc)
    from pg_proc where oid = 'public.record_pain_check_v1(date, text, text, integer, text, text[], boolean, uuid, uuid)'::regprocedure),
  'the key''s lock is taken before the replay lookup');

select pg_temp.as_user('');
select throws_ok($$select public.record_pain_check_v1(current_date, 'workout', 'knee', 2, null, null, false, null,
    'b5400000-0000-4000-8000-000000000020')$$, '42501', null, 'a caller with no identity cannot record');

-- Privacy -------------------------------------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'b5000000-0000-4000-8000-000000000001';
select is((select count(*) from public.pain_reports), 0::bigint, 'an athlete with no reports sees none, never another''s');
set local "request.jwt.claim.sub" = 'b5000000-0000-4000-8000-000000000004';
select ok((select count(*) from public.pain_reports) > 0
  and (select bool_and(user_id = 'b5000000-0000-4000-8000-000000000004') from public.pain_reports),
  'an athlete sees only their own reports');
reset role;

select throws_ok($$insert into public.pain_reports(user_id, local_date, source, check_in_id, area, severity, outcome)
  select 'b5000000-0000-4000-8000-000000000001', current_date, 'check_in', c.id, 'knee', 2, 'watch'
  from public.daily_check_ins c where c.user_id = 'b5000000-0000-4000-8000-000000000004' limit 1$$,
  '23503', null, 'a report cannot point at another athlete''s check-in');
select throws_ok($$insert into public.pain_reports(user_id, local_date, source, check_in_id, area, severity, outcome)
  select c.user_id, current_date, 'check_in', c.id, 'back', 8, 'urgent'
  from public.daily_check_ins c where c.user_id = 'b5000000-0000-4000-8000-000000000004'
    and c.superseded_at is null limit 1$$,
  '23514', null, 'and one with an outcome that disagrees is refused even for the right athlete');
select throws_ok($$insert into public.pain_reports(user_id, local_date, source, check_in_id, area, severity, outcome)
  select c.user_id, current_date, 'check_in', r.check_in_id, r.area, 2, 'watch'
  from public.pain_reports r join public.daily_check_ins c on c.id = r.check_in_id
  where r.user_id = 'b5000000-0000-4000-8000-000000000004' and r.check_in_id is not null limit 1$$,
  '23505', null, 'a check-in carries one report per area');

delete from auth.users where id = 'b5000000-0000-4000-8000-000000000004';
select is((select count(*) from public.pain_reports where user_id = 'b5000000-0000-4000-8000-000000000004'),
  0::bigint, 'deleting the account deletes its pain reports');
select ok((select count(*) from public.pain_reports where user_id = 'b5000000-0000-4000-8000-000000000003') > 0,
  'and leaves another athlete''s');

select * from finish();
rollback;
