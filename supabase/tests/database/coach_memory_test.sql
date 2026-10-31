begin;
select plan(161);

-- A10 part 2: Coach memory with athlete controls (migration 20261018150020).
-- Confirmed facts (versioned, athlete-written), Coach notes (server-written, capped), conversations
-- that are not remembered, raw message search, and prepare_coach_chat_v9.

insert into auth.users(id, role) values
  ('a1020000-0000-4000-8000-000000000001', 'authenticated'),
  ('a1020000-0000-4000-8000-000000000002', 'authenticated'),
  ('a1020000-0000-4000-8000-000000000003', 'authenticated');

create temporary table r(name text primary key, j jsonb);
grant all on r to authenticated, service_role;

-- Shape ----------------------------------------------------------------------------------------

select has_table('public', 'coach_facts', 'the facts table exists');
select has_table('public', 'coach_notes', 'the notes table exists');
select has_column('public', 'coach_threads', 'remember', 'a conversation can be marked not remembered');
select is((select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'coach_threads' and column_name = 'remember'),
  'true', 'and every conversation is remembered unless the athlete says otherwise');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.coach_facts'::regclass), 'facts: row-level security is on and forced');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.coach_notes'::regclass), 'notes: row-level security is on and forced');
select ok(not has_table_privilege('authenticated', 'public.coach_facts', 'insert')
    and not has_table_privilege('authenticated', 'public.coach_facts', 'update')
    and not has_table_privilege('authenticated', 'public.coach_facts', 'delete'),
  'an athlete cannot write facts except through the functions');
select ok(not has_table_privilege('authenticated', 'public.coach_notes', 'insert')
    and not has_table_privilege('authenticated', 'public.coach_notes', 'update')
    and not has_table_privilege('authenticated', 'public.coach_notes', 'delete'),
  'an athlete cannot write notes at all');
select ok(has_table_privilege('authenticated', 'public.coach_facts', 'select')
    and has_table_privilege('authenticated', 'public.coach_notes', 'select'),
  'an athlete reads their own rows');
select ok(not has_table_privilege('anon', 'public.coach_facts', 'select')
    and not has_table_privilege('anon', 'public.coach_notes', 'select'),
  'signed-out callers read nothing');
select ok(has_function_privilege('authenticated', 'public.save_coach_fact_v1(text, text, text, text, uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.reconfirm_coach_fact_v1(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.delete_coach_fact_v1(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.delete_coach_note_v1(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.forget_coach_memory_v1()', 'execute')
    and has_function_privilege('authenticated', 'public.get_my_coach_memory_v1()', 'execute')
    and has_function_privilege('authenticated', 'public.create_coach_thread_v2(text, boolean)', 'execute'),
  'the athlete controls are open to athletes');
select ok(not has_function_privilege('anon', 'public.save_coach_fact_v1(text, text, text, text, uuid)', 'execute')
    and not has_function_privilege('anon', 'public.get_my_coach_memory_v1()', 'execute')
    and not has_function_privilege('anon', 'public.forget_coach_memory_v1()', 'execute'),
  'and closed to signed-out callers');
select ok(not has_function_privilege('authenticated', 'public.persist_coach_note_v1(uuid, uuid, text, date, text, text[], text[], jsonb, jsonb, uuid[], uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.get_coach_memory_context_v1(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.coach_lookup_past_messages_v1(uuid, date, date, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.get_unnoted_coach_proposals_v1(uuid, integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.get_coach_follow_through_inputs_v1(uuid, date)', 'execute')
    and not has_function_privilege('authenticated', 'public.record_coach_note_follow_through_v1(uuid, uuid, text, date, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.prepare_coach_chat_v9(uuid, uuid, text, text, uuid, text)', 'execute'),
  'the functions the Coach server uses are closed to athletes');
select ok(has_function_privilege('service_role', 'public.persist_coach_note_v1(uuid, uuid, text, date, text, text[], text[], jsonb, jsonb, uuid[], uuid)', 'execute')
    and has_function_privilege('service_role', 'public.get_coach_memory_context_v1(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.coach_lookup_past_messages_v1(uuid, date, date, text)', 'execute')
    and has_function_privilege('service_role', 'public.prepare_coach_chat_v9(uuid, uuid, text, text, uuid, text)', 'execute'),
  'and open to the service role');

-- Facts: saving, versions, limits ------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000001';

insert into r select 'knee', public.save_coach_fact_v1('injury_limitation', 'Left Knee', '  Left knee   hurts on deep squats ');
select is((select array_agg(k order by k) from jsonb_object_keys((select j from r where name = 'knee')) k),
  array['fact', 'schema_version'], 'saving a fact answers with the fact at schema version 1.0');
select is((select array_agg(k order by k) from jsonb_object_keys((select j -> 'fact' from r where name = 'knee')) k),
  array['confirmed_at', 'id', 'kind', 'lineage_id', 'reconfirm_at', 'reconfirm_due', 'source', 'statement',
    'subject', 'version'], 'a fact carries exactly its contract keys');
select is((select j -> 'fact' ->> 'subject' from r where name = 'knee'), 'left knee',
  'the subject is stored in lower case');
select is((select j -> 'fact' ->> 'statement' from r where name = 'knee'), 'Left knee hurts on deep squats',
  'the statement is trimmed and single-spaced');
select is((select j -> 'fact' ->> 'source' from r where name = 'knee'), 'athlete_typed',
  'it is the athlete''s own typing by default');
select is((select (j -> 'fact' ->> 'version')::int from r where name = 'knee'), 1, 'it starts at version 1');
select is((select j -> 'fact' ->> 'lineage_id' from r where name = 'knee'), (select j -> 'fact' ->> 'id' from r where name = 'knee'),
  'and its lineage is its own id');
select is((select (j -> 'fact' ->> 'reconfirm_at')::timestamptz - (j -> 'fact' ->> 'confirmed_at')::timestamptz
    from r where name = 'knee'), interval '28 days', 'an injury is asked about again after 28 days');
select is((select j -> 'fact' ->> 'reconfirm_due' from r where name = 'knee'), 'false', 'and is not due yet');

insert into r select 'days', public.save_coach_fact_v1('schedule_constraint', 'days per week', 'Can train 3 days a week', 'coach_suggestion_confirmed');
select is((select (j -> 'fact' ->> 'reconfirm_at')::timestamptz - (j -> 'fact' ->> 'confirmed_at')::timestamptz
    from r where name = 'days'), interval '90 days', 'a schedule constraint after 90 days');
select is((select j -> 'fact' ->> 'source' from r where name = 'days'), 'coach_suggestion_confirmed',
  'a Coach suggestion the athlete confirmed says so');
insert into r select 'pizza', public.save_coach_fact_v1('food_like', 'pizza', 'Likes pizza');
select is((select j -> 'fact' -> 'reconfirm_at' from r where name = 'pizza'), 'null'::jsonb,
  'a taste never lapses');

insert into r select 'knee2', public.save_coach_fact_v1('injury_limitation', 'left knee', 'Left knee is sore after running too');
select is((select count(*) from public.coach_facts where user_id = 'a1020000-0000-4000-8000-000000000001'
    and kind = 'injury_limitation' and superseded_at is null), 1::bigint,
  'a second fact for the same kind and subject replaces the first');
select is((select (j -> 'fact' ->> 'version')::int from r where name = 'knee2'), 2, 'as version 2');
select is((select j -> 'fact' ->> 'lineage_id' from r where name = 'knee2'), (select j -> 'fact' ->> 'lineage_id' from r where name = 'knee'),
  'in the same lineage');
select ok((select superseded_at is not null from public.coach_facts where id = (select (j -> 'fact' ->> 'id')::uuid from r where name = 'knee')),
  'the first version is superseded, not overwritten');
select is((select statement from public.coach_facts where id = (select (j -> 'fact' ->> 'id')::uuid from r where name = 'knee')),
  'Left knee hurts on deep squats', 'and keeps its words');

insert into r select 'edit', public.save_coach_fact_v1('injury_limitation', 'knee', 'Knee is fine, only stiff in the morning', 'athlete_typed',
  (select (j -> 'fact' ->> 'id')::uuid from r where name = 'knee2'));
select is((select (j -> 'fact' ->> 'version')::int from r where name = 'edit'), 3,
  'an edit names the fact it replaces and adds a version, even under a new subject');
select is((select count(*) from public.coach_facts where lineage_id = (select (j -> 'fact' ->> 'lineage_id')::uuid from r where name = 'edit')),
  3::bigint, 'all three versions are kept');

select throws_ok($$select public.save_coach_fact_v1('goal', 'x', 'y')$$, '22023', null,
  'a kind outside the closed list is refused');
select throws_ok($$select public.save_coach_fact_v1('equipment', 'x', 'y', 'onboarding')$$, '22023', null,
  'a client cannot claim the onboarding source');
select throws_ok($$select public.save_coach_fact_v1('equipment', 'x', 'y', 'model')$$, '22023', null,
  'nor a model source');
select throws_ok($$select public.save_coach_fact_v1('equipment', '   ', 'y')$$, '22023', null,
  'a blank subject is refused');
select throws_ok($$select public.save_coach_fact_v1('equipment', 'x', '')$$, '22023', null,
  'a blank statement is refused');
select throws_ok($$select public.save_coach_fact_v1('equipment', repeat('x', 61), 'y')$$, '22023', null,
  'a subject over 60 characters is refused');
select throws_ok($$select public.save_coach_fact_v1('equipment', 'x', repeat('y', 201))$$, '22023', null,
  'a statement over 200 characters is refused');
select throws_ok($$select public.save_coach_fact_v1('equipment', 'x', 'y', 'athlete_typed', gen_random_uuid())$$, 'P0002', null,
  'a fact to replace that is not there is refused');

insert into r select 'reconfirm', public.reconfirm_coach_fact_v1((select (j -> 'fact' ->> 'id')::uuid from r where name = 'days'));
select is((select (j -> 'fact' ->> 'version')::int from r where name = 'reconfirm'), 2, 'still true adds a version');
select is((select j -> 'fact' ->> 'statement' from r where name = 'reconfirm'), 'Can train 3 days a week',
  'with the same words');
select is((select j -> 'fact' ->> 'source' from r where name = 'reconfirm'), 'coach_suggestion_confirmed',
  'and the same source');
select ok((select (j -> 'fact' ->> 'confirmed_at')::timestamptz >= (select confirmed_at from public.coach_facts
    where id = (select (j -> 'fact' ->> 'id')::uuid from r where name = 'days'))
    from r where name = 'reconfirm'), 'and a fresh confirmation date');
select throws_ok($$select public.reconfirm_coach_fact_v1(gen_random_uuid())$$, 'P0002', null,
  'a fact that is not there cannot be re-confirmed');

-- The 60-fact limit counts active facts.
insert into r select 'item ' || n, public.save_coach_fact_v1('other_preference', 'item ' || n, 'Item ' || n) from generate_series(1, 57) n;
select is((select count(*) from public.coach_facts where user_id = 'a1020000-0000-4000-8000-000000000001' and superseded_at is null),
  60::bigint, 'an athlete can hold 60 facts');
select throws_ok($$select public.save_coach_fact_v1('other_preference', 'one too many', 'Too many')$$, '54000', null,
  'and not a 61st');
select lives_ok($$select public.save_coach_fact_v1('other_preference', 'item 1', 'Item 1 changed')$$,
  'but a new version of an existing fact is not a new fact');

-- The athlete's view, audit trail, deletion ----------------------------------------------------------

insert into r select 'memory', public.get_my_coach_memory_v1();
select is((select array_agg(k order by k) from jsonb_object_keys((select j from r where name = 'memory')) k),
  array['facts', 'limits', 'notes', 'schema_version'], 'the memory view has exactly its contract keys');
select is((select jsonb_array_length(j -> 'facts') from r where name = 'memory'), 60, 'it lists active facts only');
select is((select j -> 'limits' from r where name = 'memory'),
  '{"max_facts": 60, "max_notes": 20, "note_days": 60}'::jsonb, 'and states the limits');
reset role;
select ok(exists(select 1 from public.audit_events where user_id = 'a1020000-0000-4000-8000-000000000001'
    and action_code = 'coach.fact.saved' and metadata ->> 'kind' = 'injury_limitation'),
  'saving a fact leaves an audit event');
select ok(not exists(select 1 from public.audit_events where user_id = 'a1020000-0000-4000-8000-000000000001'
    and action_code like 'coach.%' and metadata::text like '%knee%'),
  'and the event holds no words of the athlete''s');
set local role authenticated;

insert into r select 'deleted', public.delete_coach_fact_v1((select (j -> 'fact' ->> 'id')::uuid from r where name = 'edit'));
select is((select j ->> 'deleted' from r where name = 'deleted'), 'true', 'deleting a fact answers deleted');
select is((select count(*) from public.coach_facts where lineage_id = (select (j -> 'fact' ->> 'lineage_id')::uuid from r where name = 'edit')),
  0::bigint, 'and removes every version of it');
select throws_ok($$select public.delete_coach_fact_v1(gen_random_uuid())$$, 'P0002', null,
  'a fact that is not there cannot be deleted');

-- Another athlete -------------------------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000002';
select is((select count(*) from public.coach_facts), 0::bigint, 'another athlete sees none of the facts');
select is((select jsonb_array_length(public.get_my_coach_memory_v1() -> 'facts')), 0, 'nor in the memory view');
select throws_ok(format($$select public.delete_coach_fact_v1(%L)$$, (select (j -> 'fact' ->> 'id') from r where name = 'pizza')),
  'P0002', null, 'and cannot delete someone else''s fact');
select throws_ok(format($$select public.reconfirm_coach_fact_v1(%L)$$, (select (j -> 'fact' ->> 'id') from r where name = 'pizza')),
  'P0002', null, 'nor re-confirm it');
select throws_ok(format($$select public.save_coach_fact_v1('food_like', 'x', 'y', 'athlete_typed', %L)$$, (select (j -> 'fact' ->> 'id') from r where name = 'pizza')),
  'P0002', null, 'nor replace it');
select throws_ok($$insert into public.coach_facts(user_id, lineage_id, kind, subject, statement, source)
  values ('a1020000-0000-4000-8000-000000000002', gen_random_uuid(), 'equipment', 'x', 'y', 'athlete_typed')$$,
  '42501', null, 'and cannot write a row directly');

-- Conversations that are not remembered ------------------------------------------------------------------

set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000001';
insert into r select 'open', public.create_coach_thread_v2();
insert into r select 'private', public.create_coach_thread_v2('Private chat', false);
select is((select array_agg(k order by k) from jsonb_object_keys((select j from r where name = 'private')) k),
  array['remember', 'schema_version', 'thread_id'], 'a new conversation answers with exactly its contract keys');
select is((select j ->> 'remember' from r where name = 'open'), 'true', 'a conversation is remembered by default');
select is((select j ->> 'remember' from r where name = 'private'), 'false', 'unless the athlete says otherwise');
select is((select remember from public.coach_threads where id = (select (j ->> 'thread_id')::uuid from r where name = 'private')),
  false, 'and the flag is on the conversation');
select throws_ok($$select public.create_coach_thread_v2('x', null)$$, '22023', null, 'a missing flag is refused');
select throws_ok($$select public.create_coach_thread_v2('', true)$$, '22023', null, 'and so is a blank title');

reset role;
insert into public.coach_messages(id, user_id, thread_id, role, content) values
  ('a1020000-0000-4000-8000-0000000000a1', 'a1020000-0000-4000-8000-000000000001',
    (select (j ->> 'thread_id')::uuid from r where name = 'open'), 'user', 'My knee and shoulder hurt after squats'),
  ('a1020000-0000-4000-8000-0000000000a2', 'a1020000-0000-4000-8000-000000000001',
    (select (j ->> 'thread_id')::uuid from r where name = 'open'), 'assistant', 'Knee pain after squats can have many causes'),
  ('a1020000-0000-4000-8000-0000000000b1', 'a1020000-0000-4000-8000-000000000001',
    (select (j ->> 'thread_id')::uuid from r where name = 'private'), 'user', 'Privately: my knee is a secret worry');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000001';
select is((select array_agg(t ->> 'remember' order by t ->> 'title') from jsonb_array_elements(public.get_my_coach_threads() -> 'threads') t),
  array['true', 'false'], 'the conversation list tells which conversations are not remembered');
select is((select array_agg(k order by k) from jsonb_object_keys(public.get_my_coach_threads() -> 'threads' -> 0) k),
  array['id', 'last_message_at', 'remember', 'title', 'updated_at'], 'it only added the one key');

-- Notes --------------------------------------------------------------------------------------------------

reset role;
set local role service_role;

insert into r select 'note1', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001',
  (select (j ->> 'thread_id')::uuid from r where name = 'open'), 'conversation', current_date,
  'Asked about training. Mentioned pain.', array['training'], array['pain'], '[]', '[]',
  array['a1020000-0000-4000-8000-0000000000a1', 'a1020000-0000-4000-8000-0000000000a2']::uuid[]);
select is((select j ->> 'stored' from r where name = 'note1'), 'true', 'a note is stored for a remembered conversation');
select is((select message_ids from public.coach_notes where id = (select (j ->> 'note_id')::uuid from r where name = 'note1')),
  array['a1020000-0000-4000-8000-0000000000a1', 'a1020000-0000-4000-8000-0000000000a2']::uuid[],
  'with the messages it came from');
select ok((select abs(extract(epoch from expires_at - created_at) - 60 * 86400) < 1 from public.coach_notes
    where id = (select (j ->> 'note_id')::uuid from r where name = 'note1')), 'and lapses after 60 days');

insert into r select 'note_private', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001',
  (select (j ->> 'thread_id')::uuid from r where name = 'private'), 'conversation', current_date,
  'Should never be stored.', array['training'], '{}', '[]', '[]', '{}');
select is((select j ->> 'stored' from r where name = 'note_private'), 'false', 'nothing is stored for a conversation that is not remembered');
select is((select j ->> 'reason' from r where name = 'note_private'), 'not_remembered', 'and the answer says why');
select is((select count(*) from public.coach_notes where summary = 'Should never be stored.'), 0::bigint, 'no row exists');

select throws_ok($$select public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001',
    gen_random_uuid(), 'conversation', current_date, 'x', '{}', '{}', '[]', '[]', '{}')$$, 'P0002', null,
  'a conversation that is not the athlete''s is refused');
select throws_ok($$select public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001',
    null, 'conversation', current_date, 'x', '{}', '{}', '[]', '[]', '{}')$$, '22023', null,
  'a conversation note needs its conversation');
select throws_ok($$select public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001',
    null, 'summary', current_date, 'x', '{}', '{}', '[]', '[]', '{}')$$, '22023', null,
  'a note kind outside the list is refused');
select throws_ok(format($$select public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001',
    %L, 'conversation', current_date, 'x', '{}', '{}', '[]', '[]', array[%L]::uuid[])$$,
    (select j ->> 'thread_id' from r where name = 'open'), 'a1020000-0000-4000-8000-0000000000b1'),
  '22023', null, 'a note cannot link a message from another conversation');
select throws_ok($$select public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001',
    null, 'advice', current_date, 'x', array['Bad Topic'], '{}', '[]', '[]', '{}')$$, '23514', null,
  'topics must be lower-case words');

-- The cap: only the 20 newest notes stay.
insert into r select 'advice ' || n, public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date, 'Advice ' || n, '{}', '{}', '[]', '[]', '{}') from generate_series(1, 22) n;
select is((select count(*) from public.coach_notes where user_id = 'a1020000-0000-4000-8000-000000000001'), 20::bigint,
  'an athlete keeps at most 20 notes');
select ok(not exists(select 1 from public.coach_notes where summary = 'Asked about training. Mentioned pain.'),
  'and the oldest are the ones that go');

-- Decay: an expired note is dropped at the next write and is not read.
reset role;
update public.coach_notes set expires_at = now() - interval '1 day' where summary = 'Advice 22';
set local role service_role;
insert into r select 'context', public.get_coach_memory_context_v1('a1020000-0000-4000-8000-000000000001');
select is((select array_agg(k order by k) from jsonb_object_keys((select j from r where name = 'context')) k),
  array['facts', 'local_date', 'notes', 'schema_version'], 'the Coach context has exactly its contract keys');
select ok(not exists(select 1 from jsonb_array_elements((select j -> 'notes' from r where name = 'context')) n where n ->> 'summary' = 'Advice 22'),
  'an expired note is not read');
select is((select jsonb_array_length(j -> 'notes') from r where name = 'context'), 19, 'the other 19 are');
select is((select jsonb_array_length(j -> 'facts') from r where name = 'context'), 59, 'with the athlete''s active facts');
insert into r select 'advice 23', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date, 'Advice 23', '{}', '{}', '[]', '[]', '{}');
select ok(not exists(select 1 from public.coach_notes where summary = 'Advice 22'), 'the expired note is deleted by the next write');

-- Proposals the athlete answered become advice notes -----------------------------------------------------------

reset role;
insert into public.change_proposals(id, user_id, feature_snapshot_id, schema_version, proposed_training,
  proposed_nutrition, evidence, rationale, expected_benefit, downside, confidence, effective_date, expires_at,
  status, proposal_kind, proposal_payload, before_snapshot, after_snapshot, basis, source_message_id)
values ('a1020000-0000-4000-8000-0000000000c1', 'a1020000-0000-4000-8000-000000000001', null, '3.0',
  '{"proposal_kind": "nutrition_targets", "title": "Lower calories"}',
  '{"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60}', '[]', 'Why', 'Benefit',
  'Downside', 'medium', current_date, now() + interval '3 days', 'accepted', 'nutrition_targets',
  '{"nutrition": {"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60, "rationale": "Because"}}',
  '{}', '{}', '{}', 'a1020000-0000-4000-8000-0000000000a1'),
  ('a1020000-0000-4000-8000-0000000000c2', 'a1020000-0000-4000-8000-000000000001', null, '3.0',
  '{"proposal_kind": "nutrition_targets", "title": "Pending change"}',
  '{"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60}', '[]', 'Why', 'Benefit',
  'Downside', 'medium', current_date, now() + interval '3 days', 'pending', 'nutrition_targets',
  '{"nutrition": {"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60, "rationale": "Because"}}',
  '{}', '{}', '{}', null),
  ('a1020000-0000-4000-8000-0000000000c3', 'a1020000-0000-4000-8000-000000000001', null, '3.0',
  '{"proposal_kind": "nutrition_targets", "title": "Private chat change"}',
  '{"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60}', '[]', 'Why', 'Benefit',
  'Downside', 'medium', current_date, now() + interval '3 days', 'rejected', 'nutrition_targets',
  '{"nutrition": {"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60, "rationale": "Because"}}',
  '{}', '{}', '{}', 'a1020000-0000-4000-8000-0000000000b1');
set local role service_role;
insert into r select 'unnoted', public.get_unnoted_coach_proposals_v1('a1020000-0000-4000-8000-000000000001');
select is((select array_agg(p ->> 'id') from jsonb_array_elements((select j -> 'proposals' from r where name = 'unnoted')) p),
  array['a1020000-0000-4000-8000-0000000000c1'],
  'only an answered proposal from a remembered conversation is waiting for a note');
select is((select (j -> 'proposals' -> 0) - 'answered_on' from r where name = 'unnoted'),
  jsonb_build_object('id', 'a1020000-0000-4000-8000-0000000000c1', 'kind', 'nutrition_targets',
    'title', 'Lower calories', 'outcome', 'accepted', 'days_per_week', null,
    'source_message_id', 'a1020000-0000-4000-8000-0000000000a1'),
  'with the keys the note builder reads');
insert into r select 'advice', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice', current_date,
  'Coach proposed “Lower calories”; you approved it.', array['nutrition'], '{}',
  '[{"code": "nutrition_targets", "summary": "Lower calories", "outcome": "accepted"}]', '[]',
  array['a1020000-0000-4000-8000-0000000000a1']::uuid[], 'a1020000-0000-4000-8000-0000000000c1');
select is((select j ->> 'stored' from r where name = 'advice'), 'true', 'the advice note is stored');
insert into r select 'advice_again', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice', current_date,
  'Again', '{}', '{}', '[]', '[]', '{}', 'a1020000-0000-4000-8000-0000000000c1');
select is((select j ->> 'reason' from r where name = 'advice_again'), 'already_noted', 'a proposal is noted once');
select is((select count(*) from public.coach_notes where proposal_id = 'a1020000-0000-4000-8000-0000000000c1'), 1::bigint,
  'in one row');
select is(jsonb_array_length(public.get_unnoted_coach_proposals_v1('a1020000-0000-4000-8000-000000000001') -> 'proposals'), 0,
  'and it is no longer waiting');
select ok((select memory_noted_at is not null from public.change_proposals where id = 'a1020000-0000-4000-8000-0000000000c1'),
  'the proposal remembers that it was turned into a note');

-- A note the athlete deletes, or the cap drops, is not made again.
reset role;
delete from public.coach_notes where proposal_id = 'a1020000-0000-4000-8000-0000000000c1';
set local role service_role;
select is(jsonb_array_length(public.get_unnoted_coach_proposals_v1('a1020000-0000-4000-8000-000000000001') -> 'proposals'), 0,
  'a deleted advice note does not come back');

-- A proposal made in a conversation that is not remembered stays out after that conversation is deleted.
reset role;
insert into public.coach_threads(id, user_id, title, remember)
values ('a1020000-0000-4000-8000-0000000000c9', 'a1020000-0000-4000-8000-000000000001', 'Private two', false);
insert into public.coach_messages(id, user_id, thread_id, role, content)
values ('a1020000-0000-4000-8000-0000000000c8', 'a1020000-0000-4000-8000-000000000001',
  'a1020000-0000-4000-8000-0000000000c9', 'assistant', 'A private proposal');
insert into public.change_proposals(id, user_id, feature_snapshot_id, schema_version, proposed_training,
  proposed_nutrition, evidence, rationale, expected_benefit, downside, confidence, effective_date, expires_at,
  status, proposal_kind, proposal_payload, before_snapshot, after_snapshot, basis, source_message_id)
values ('a1020000-0000-4000-8000-0000000000c5', 'a1020000-0000-4000-8000-000000000001', null, '3.0',
  '{"proposal_kind": "nutrition_targets", "title": "Private two change"}',
  '{"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60}', '[]', 'Why', 'Benefit',
  'Downside', 'medium', current_date, now() + interval '3 days', 'accepted', 'nutrition_targets',
  '{"nutrition": {"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60, "rationale": "Because"}}',
  '{}', '{}', '{}', 'a1020000-0000-4000-8000-0000000000c8');
select ok(not (select source_remembered from public.change_proposals where id = 'a1020000-0000-4000-8000-0000000000c5'),
  'a proposal copies whether its conversation is remembered');
delete from public.coach_threads where id = 'a1020000-0000-4000-8000-0000000000c9';
select ok((select source_message_id is null and not source_remembered from public.change_proposals
    where id = 'a1020000-0000-4000-8000-0000000000c5'), 'and keeps it after the conversation is deleted');
set local role service_role;
select is(jsonb_array_length(public.get_unnoted_coach_proposals_v1('a1020000-0000-4000-8000-000000000001') -> 'proposals'), 0,
  'so it is never turned into a note');

-- Follow-through ---------------------------------------------------------------------------------------------

reset role;
insert into public.training_plans(id, user_id, title, source)
values ('a1020000-0000-4000-8000-0000000000d1', 'a1020000-0000-4000-8000-000000000001', 'Plan', 'imported');
insert into public.training_plan_versions(id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date)
values ('a1020000-0000-4000-8000-0000000000d2', 'a1020000-0000-4000-8000-000000000001',
  'a1020000-0000-4000-8000-0000000000d1', 1, 'active', 4, 3, '{}', 'Approved fixture', now(), current_date);
insert into public.planned_workouts(id, user_id, plan_version_id, workout_order, name, objective,
  preferred_weekday, estimated_minutes, warm_up_guidance, cool_down_guidance)
values ('a1020000-0000-4000-8000-0000000000d3', 'a1020000-0000-4000-8000-000000000001',
  'a1020000-0000-4000-8000-0000000000d2', 1, 'Push day', 'Build strength.', 1, 60, 'Warm up.', 'Cool down.');
insert into public.workout_sessions(id, user_id, plan_version_id, planned_workout_id, state, local_date,
  timezone, idempotency_key, session_effort, duration_seconds, logging_completeness, completed_at)
select v.id, 'a1020000-0000-4000-8000-000000000001', 'a1020000-0000-4000-8000-0000000000d2',
  'a1020000-0000-4000-8000-0000000000d3', v.state, current_date - v.days_ago, 'UTC', gen_random_uuid(),
  7, 3600, 1.0, case when v.state = 'completed' then now() end
from (values
  ('a1020000-0000-4000-8000-0000000000e1'::uuid, 5, 'completed'::public.workout_session_state),
  ('a1020000-0000-4000-8000-0000000000e2'::uuid, 3, 'completed'),
  ('a1020000-0000-4000-8000-0000000000e3'::uuid, 4, 'in_progress'),
  ('a1020000-0000-4000-8000-0000000000e4'::uuid, 20, 'completed')) v(id, days_ago, state);
set local role service_role;
insert into r select 'train_note', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date - 9, 'Coach proposed “Train 3 days a week”; you approved it.', '{}', '{}',
  '[{"code": "training_schedule", "summary": "Train 3 days a week", "outcome": "accepted", "kind": "train_days", "target": 3}]', '[]', '{}');
insert into r select 'checks', public.get_coach_follow_through_inputs_v1('a1020000-0000-4000-8000-000000000001', current_date);
select is((select (j -> 'checks' -> 0) - 'note_id' from r where name = 'checks'),
  jsonb_build_object('kind', 'train_days', 'target', 3, 'window_from', current_date - 8,
    'window_to', current_date - 2, 'sessions_completed', 2),
  'a checkable note reports the completed sessions of the week after it (not one still in progress, not older ones)');
select is((select jsonb_array_length(j -> 'checks') from r where name = 'checks'), 1,
  'and only notes with a checkable training target are listed');
select is(jsonb_array_length(public.get_coach_follow_through_inputs_v1('a1020000-0000-4000-8000-000000000001', current_date - 3) -> 'checks'),
  0, 'a week that has not passed is not checked yet');
insert into r select 'edge_note', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date - 7, 'Edge week', '{}', '{}',
  '[{"code": "training_schedule", "summary": "Edge", "outcome": "accepted", "kind": "train_days", "target": 2}]', '[]', '{}');
select is((select count(*) from jsonb_array_elements(public.get_coach_follow_through_inputs_v1(
    'a1020000-0000-4000-8000-000000000001', current_date) -> 'checks') c
    where c ->> 'note_id' = (select j ->> 'note_id' from r where name = 'edge_note')), 0::bigint,
  'the week after a note is checked only once its last day is over');
select is((select count(*) from jsonb_array_elements(public.get_coach_follow_through_inputs_v1(
    'a1020000-0000-4000-8000-000000000001', current_date + 1) -> 'checks') c
    where c ->> 'note_id' = (select j ->> 'note_id' from r where name = 'edge_note')), 1::bigint,
  'and the day after it is');
reset role;
delete from public.coach_notes where summary = 'Edge week';
set local role service_role;
insert into r select 'recorded', public.record_coach_note_follow_through_v1('a1020000-0000-4000-8000-000000000001',
  (select (j ->> 'note_id')::uuid from r where name = 'train_note'), 'partly', current_date, '2 of 3 sessions');
select is((select j ->> 'recorded' from r where name = 'recorded'), 'true', 'a result is recorded once');
select is((select follow_through ->> 'status' from public.coach_notes where id = (select (j ->> 'note_id')::uuid from r where name = 'train_note')),
  'partly', 'on the note');
select is(jsonb_array_length(public.get_coach_follow_through_inputs_v1('a1020000-0000-4000-8000-000000000001', current_date) -> 'checks'),
  0, 'and the note is not checked again');
select throws_ok($$select public.record_coach_note_follow_through_v1('a1020000-0000-4000-8000-000000000001',
    gen_random_uuid(), 'unknown', current_date, 'x')$$, '22023', null, 'a status outside the list is refused');

-- A commitment waiting for its check survives the cap ----------------------------------------------------------

insert into r select 'promise', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date - 1, 'Promised four days', '{}', '{}', '[]',
  '[{"text": "train 4 days this week", "kind": "train_days", "target": 4}]', '{}');
insert into r select 'filler ' || n, public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date, 'Filler ' || n, '{}', '{}', '[]', '[]', '{}') from generate_series(1, 25) n;
select is((select count(*) from public.coach_notes where summary = 'Promised four days'), 1::bigint,
  'a note awaiting its follow-through check is kept when 25 newer notes arrive');
select is((select count(*) from public.coach_notes where summary like 'Filler %'), 19::bigint,
  'and the other notes make way for it: the stored count never passes 20');
select is((select count(*) from public.coach_notes where user_id = 'a1020000-0000-4000-8000-000000000001'), 20::bigint,
  'twenty notes in all, the waiting one included');
insert into r select 'promise old', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date - 30, 'Promised long ago', '{}', '{}', '[]',
  '[{"text": "train 3 days this week", "kind": "train_days", "target": 3}]', '{}');
insert into r select 'late filler ' || n, public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date, 'Late filler ' || n, '{}', '{}', '[]', '[]', '{}') from generate_series(1, 20) n;
select is((select count(*) from public.coach_notes where summary = 'Promised long ago'), 0::bigint,
  'a promise 30 days old, past the 28 days the check looks back, is no longer protected');

-- With 20 notes already waiting for their check, a new note that is not waiting is the one dropped.
reset role;
delete from public.coach_notes where user_id = 'a1020000-0000-4000-8000-000000000001';
set local role service_role;
insert into r select 'waiting ' || n, public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date - 1, 'Waiting ' || n, '{}', '{}', '[]',
  '[{"text": "train 3 days", "kind": "train_days", "target": 3}]', '{}') from generate_series(1, 20) n;
select is((select count(*) from public.coach_notes where summary like 'Waiting %'), 20::bigint,
  'twenty notes can wait for their check');
insert into r select 'dropped', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date, 'Dropped by the cap', '{}', '{}', '[]', '[]', '{}', 'a1020000-0000-4000-8000-0000000000c2');
select is((select j - 'schema_version' from r where name = 'dropped'),
  '{"stored": false, "note_id": null, "reason": "cap"}'::jsonb,
  'a note the cap drops is reported as not stored, with the reason');
select is((select count(*) from public.coach_notes where summary = 'Dropped by the cap'), 0::bigint, 'and is not there');
select ok((select memory_noted_at is not null from public.change_proposals where id = 'a1020000-0000-4000-8000-0000000000c2'),
  'its proposal stays marked noted, so it is not tried again');
insert into r select 'invalid target', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date, 'Target out of range', '{}', '{}', '[]',
  '[{"text": "train 9 days", "kind": "train_days", "target": 9}]', '{}');
select is((select j ->> 'reason' from r where name = 'invalid target'), 'cap',
  'a commitment with no valid target is not waiting for a check, so it gets no protection');
reset role;
delete from public.coach_notes where summary in ('Promised four days') or summary like 'Filler %' or summary like 'Late filler %' or summary like 'Waiting %';
set local role service_role;

-- Raw message search ----------------------------------------------------------------------------------------

select is((select array_agg(k order by k) from jsonb_object_keys(public.coach_lookup_past_messages_v1(
    'a1020000-0000-4000-8000-000000000001', current_date - 30, current_date, 'knee')) k),
  array['coach_replies', 'from', 'lookup', 'messages', 'schema_version', 'to', 'truncated'],
  'the lookup has exactly its contract keys');
select is((select array_agg(m ->> 'message_id') from jsonb_array_elements(public.coach_lookup_past_messages_v1(
    'a1020000-0000-4000-8000-000000000001', current_date - 30, current_date, 'knee') -> 'messages') m),
  array['a1020000-0000-4000-8000-0000000000a1'],
  'it finds the athlete''s own question, not the Coach''s reply and not a conversation that is not remembered');
select is((select array_agg(k order by k) from jsonb_object_keys(public.coach_lookup_past_messages_v1(
    'a1020000-0000-4000-8000-000000000001', current_date - 30, current_date, 'knee') -> 'messages' -> 0) k),
  array['content', 'local_date', 'message_id'], 'a row has its date, its id and its words');
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1020000-0000-4000-8000-000000000001',
    current_date - 30, current_date, 'elbow shoulder') -> 'messages'), 1,
  'any of the words match');
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1020000-0000-4000-8000-000000000001',
    current_date - 30, current_date, 'secret') -> 'messages'), 0,
  'a conversation that is not remembered is never searched');
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1020000-0000-4000-8000-000000000001',
    current_date - 400, current_date - 1, 'knee') -> 'messages'), 0, 'the date range filters');
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1020000-0000-4000-8000-000000000002',
    current_date - 30, current_date, 'knee') -> 'messages'), 0, 'another athlete''s messages are never found');
select throws_ok($$select public.coach_lookup_past_messages_v1('a1020000-0000-4000-8000-000000000001',
    current_date - 30, current_date, null)$$, '22023', null, 'a search needs words');
select throws_ok($$select public.coach_lookup_past_messages_v1('a1020000-0000-4000-8000-000000000001',
    current_date - 30, current_date, '  ')$$, '22023', null, 'not blanks');
reset role;
insert into public.coach_messages(user_id, thread_id, role, content)
select 'a1020000-0000-4000-8000-000000000001', (select (j ->> 'thread_id')::uuid from r where name = 'open'),
  'user', case when n = 1 then repeat('lunges ', 80) else 'lunges again ' || n end
from generate_series(1, 14) n;
set local role service_role;
select is(jsonb_array_length(public.coach_lookup_past_messages_v1('a1020000-0000-4000-8000-000000000001',
    current_date - 30, current_date, 'lunges') -> 'messages'), 12, 'at most 12 rows come back');
select is(public.coach_lookup_past_messages_v1('a1020000-0000-4000-8000-000000000001',
    current_date - 30, current_date, 'lunges') ->> 'truncated', 'true', 'and the answer says it was cut');
select is((select max(length(m ->> 'content')) from jsonb_array_elements(public.coach_lookup_past_messages_v1(
    'a1020000-0000-4000-8000-000000000001', current_date - 30, current_date, 'lunges') -> 'messages') m),
  300, 'each row is cut to 300 characters');
select is(jsonb_array_length(public.search_coach_messages('a1020000-0000-4000-8000-000000000001', 'secret worry')), 0,
  'the older search skips conversations that are not remembered too');
select ok(jsonb_array_length(public.search_coach_messages('a1020000-0000-4000-8000-000000000001', 'knee shoulder')) >= 1,
  'and still finds the others');

-- prepare_coach_chat_v9 ----------------------------------------------------------------------------------------

-- A third athlete with few enough messages that v8 shows all of them.
reset role;
insert into public.coach_threads(id, user_id, title, remember) values
  ('a1020000-0000-4000-8000-0000000000f1', 'a1020000-0000-4000-8000-000000000003', 'Current chat', true),
  ('a1020000-0000-4000-8000-0000000000f2', 'a1020000-0000-4000-8000-000000000003', 'Open chat', true),
  ('a1020000-0000-4000-8000-0000000000f3', 'a1020000-0000-4000-8000-000000000003', 'Private chat', false);
insert into public.coach_messages(user_id, thread_id, role, content) values
  ('a1020000-0000-4000-8000-000000000003', 'a1020000-0000-4000-8000-0000000000f1', 'user', 'CURRENT_CHAT_MARKER hello'),
  ('a1020000-0000-4000-8000-000000000003', 'a1020000-0000-4000-8000-0000000000f2', 'user', 'My shoulder hurt after squats'),
  ('a1020000-0000-4000-8000-000000000003', 'a1020000-0000-4000-8000-0000000000f3', 'user', 'Privately my knee is a secret worry');
insert into public.user_preferences(user_id, category, key, value, provenance)
values ('a1020000-0000-4000-8000-000000000003', 'food', 'old', 'old preference', 'chat_statement');
set local role service_role;
insert into r select 'v8', public.prepare_coach_chat_v8('a1020000-0000-4000-8000-000000000003',
  'a1020000-0000-4000-8000-0000000000f1', 'How am I doing?', 'UTC', gen_random_uuid(), 'general');
insert into r select 'v9', public.prepare_coach_chat_v9('a1020000-0000-4000-8000-000000000003',
  'a1020000-0000-4000-8000-0000000000f1', 'How am I doing?', 'UTC', gen_random_uuid(), 'general');
select ok((select j -> 'context' ->> 'recent_other_conversations' like '%secret worry%' from r where name = 'v8'),
  'v8, which is frozen, shows another conversation''s messages whether or not it is remembered');
select ok((select j -> 'context' ? 'active_preferences' from r where name = 'v8'),
  'and still sends the older preferences');
select ok((select j -> 'context' ->> 'recent_other_conversations' not like '%secret worry%' from r where name = 'v9'),
  'v9 leaves out a conversation that is not remembered');
select ok((select j -> 'context' ->> 'recent_other_conversations' like '%shoulder hurt%' from r where name = 'v9'),
  'and keeps the ones that are');
select ok((select j -> 'context' ->> 'recent_messages' like '%CURRENT_CHAT_MARKER%' from r where name = 'v9'),
  'the conversation in hand is untouched');
select ok((select not (j -> 'context') ?| array['session_journal', 'active_preferences', 'coaching_narrative'] from r where name = 'v9'),
  'v9 drops the older preference, journal and narrative sections');
select ok((select (j -> 'context') ?& array['recent_messages', 'permitted_evidence', 'omitted_sections'] from r where name = 'v9'),
  'and keeps the rest of the athlete file');
select ok(coalesce((select not (context::text like '%secret worry%') from public.coach_context_snapshots
    where id = (select (j ->> 'coach_context_snapshot_id')::uuid from r where name = 'v9')), true),
  'the stored snapshot matches what the Coach was given');

-- Forget everything ------------------------------------------------------------------------------------------------

reset role;
insert into public.user_preferences(user_id, category, key, value, provenance)
values ('a1020000-0000-4000-8000-000000000001', 'food', 'old', 'old preference', 'chat_statement');
insert into public.coach_session_summaries(user_id, coaching_date, summary)
values ('a1020000-0000-4000-8000-000000000001', current_date, 'old summary');
reset role;
update public.coach_context_snapshots
set context = context || '{"session_journal": [{"summary": "old"}], "active_preferences": [{"value": "x"}], "coaching_narrative": {"phase": "x"}}'::jsonb
where user_id = 'a1020000-0000-4000-8000-000000000003';
select ok((select bool_and(context ?& array['session_journal', 'active_preferences', 'coaching_narrative'])
    from public.coach_context_snapshots where user_id = 'a1020000-0000-4000-8000-000000000003'),
  'a stored context holds the older memory sections');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000003';
insert into r select 'forgot3', public.forget_coach_memory_v1();
reset role;
select ok((select not bool_or(context ?| array['session_journal', 'active_preferences', 'coaching_narrative'])
    from public.coach_context_snapshots where user_id = 'a1020000-0000-4000-8000-000000000003'),
  'forgetting everything removes them from the stored contexts');
select ok((select bool_and(context_checksum = encode(extensions.digest(convert_to(context::text, 'UTF8'), 'sha256'), 'hex'))
    from public.coach_context_snapshots where user_id = 'a1020000-0000-4000-8000-000000000003'),
  'and the stored checksum still matches');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000002';
insert into r select 'rice', public.save_coach_fact_v1('food_like', 'rice', 'Likes rice');
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000001';
reset role;
insert into public.change_proposals(id, user_id, feature_snapshot_id, schema_version, proposed_training,
  proposed_nutrition, evidence, rationale, expected_benefit, downside, confidence, effective_date, expires_at,
  status, proposal_kind, proposal_payload, before_snapshot, after_snapshot, basis, source_message_id)
values ('a1020000-0000-4000-8000-0000000000c6', 'a1020000-0000-4000-8000-000000000001', null, '3.0',
  '{"proposal_kind": "nutrition_targets", "title": "Answered before forgetting"}',
  '{"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60}', '[]', 'Why', 'Benefit',
  'Downside', 'medium', current_date, now() + interval '3 days', 'accepted', 'nutrition_targets',
  '{"nutrition": {"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60, "rationale": "Because"}}',
  '{}', '{}', '{}', 'a1020000-0000-4000-8000-0000000000a1'),
  ('a1020000-0000-4000-8000-0000000000c7', 'a1020000-0000-4000-8000-000000000001', null, '3.0',
  '{"proposal_kind": "nutrition_targets", "title": "Never linked"}',
  '{"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60}', '[]', 'Why', 'Benefit',
  'Downside', 'medium', current_date, now() + interval '3 days', 'accepted', 'nutrition_targets',
  '{"nutrition": {"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60, "rationale": "Because"}}',
  '{}', '{}', '{}', null),
  ('a1020000-0000-4000-8000-0000000000ca', 'a1020000-0000-4000-8000-000000000001', null, '3.0',
  '{"proposal_kind": "nutrition_targets", "title": "Still pending at forget"}',
  '{"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60}', '[]', 'Why', 'Benefit',
  'Downside', 'medium', current_date, now() + interval '3 days', 'pending', 'nutrition_targets',
  '{"nutrition": {"calories": 2000, "protein_g": 150, "carbohydrate_g": 200, "fat_g": 60, "rationale": "Because"}}',
  '{}', '{}', '{}', 'a1020000-0000-4000-8000-0000000000a1');
select ok(not (select source_remembered from public.change_proposals where id = 'a1020000-0000-4000-8000-0000000000c7'),
  'a new proposal that was never linked to a reply counts as not remembered');
set local role service_role;
select is((select array_agg(p ->> 'id') from jsonb_array_elements(public.get_unnoted_coach_proposals_v1(
    'a1020000-0000-4000-8000-000000000001') -> 'proposals') p), array['a1020000-0000-4000-8000-0000000000c6'],
  'an answered, linked proposal is waiting for its note, and the unlinked one never is');
insert into r select 'before_note ' || n, public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date, 'Before forgetting ' || n, '{}', '{}', '[]', '[]', '{}') from generate_series(1, 2) n;
reset role;
create temporary table before_forget as
select (select count(*) from public.coach_facts where user_id = 'a1020000-0000-4000-8000-000000000001') as facts,
  (select count(*) from public.coach_notes where user_id = 'a1020000-0000-4000-8000-000000000001') as notes;
grant select on before_forget to authenticated;
select ok((select notes from before_forget) >= 2, 'notes are there to forget');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000001';
insert into r select 'forgot', public.forget_coach_memory_v1();
reset role;
set local role service_role;
select is(jsonb_array_length(public.get_unnoted_coach_proposals_v1('a1020000-0000-4000-8000-000000000001') -> 'proposals'), 0,
  'forgetting everything does not leave it to be written afterwards');
reset role;
update public.change_proposals set status = 'rejected' where id = 'a1020000-0000-4000-8000-0000000000ca';
set local role service_role;
select is(jsonb_array_length(public.get_unnoted_coach_proposals_v1('a1020000-0000-4000-8000-000000000001') -> 'proposals'), 0,
  'nor does a proposal that was still pending then and is answered or lapses later');
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000001';
select is((select array_agg(k order by k) from jsonb_object_keys((select j from r where name = 'forgot')) k),
  array['facts_deleted', 'notes_deleted', 'schema_version'], 'forgetting answers with exactly its contract keys');
select is((select j - 'schema_version' from r where name = 'forgot'),
  (select jsonb_build_object('facts_deleted', facts, 'notes_deleted', notes) from before_forget),
  'and counts every version of every fact and every note it removed');
select is((select count(*) from public.coach_facts) + (select count(*) from public.coach_notes)
    + (select count(*) from public.user_preferences) + (select count(*) from public.coach_session_summaries),
  0::bigint, 'every fact, note and older memory row is gone');
select ok((select count(*) > 0 from public.coach_messages), 'the conversations stay');
reset role;
select ok(exists(select 1 from public.audit_events where user_id = 'a1020000-0000-4000-8000-000000000001'
    and action_code = 'coach.memory.forgotten'), 'forgetting leaves an audit event');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000002';
select is((select count(*) from public.coach_facts), 1::bigint, 'and the other athlete''s memory is untouched');

-- A note goes with its note; the deletion path ------------------------------------------------------------------------

reset role;
set local role service_role;
insert into r select 'last_note', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001', null, 'advice',
  current_date, 'One note', '{}', '{}', '[]', '[]', '{}');
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1020000-0000-4000-8000-000000000001';
select is((select count(*) from public.coach_notes), 1::bigint, 'the athlete sees their note');
select throws_ok($$select public.delete_coach_note_v1(gen_random_uuid())$$, 'P0002', null, 'a note that is not there cannot be deleted');
select lives_ok(format($$select public.delete_coach_note_v1(%L)$$, (select j ->> 'note_id' from r where name = 'last_note')),
  'the athlete can delete a note');
select is((select count(*) from public.coach_notes), 0::bigint, 'and it is gone');
reset role;
set local role service_role;
insert into r select 'thread_note', public.persist_coach_note_v1('a1020000-0000-4000-8000-000000000001',
  (select (j ->> 'thread_id')::uuid from r where name = 'open'), 'conversation', current_date,
  'Thread note', array['training'], '{}', '[]', '[]', '{}');
reset role;
delete from public.coach_threads where id = (select (j ->> 'thread_id')::uuid from r where name = 'open');
select is((select count(*) from public.coach_notes where summary = 'Thread note'), 0::bigint,
  'deleting a conversation deletes the notes written from it');

insert into public.coach_facts(user_id, lineage_id, kind, subject, statement, source)
values ('a1020000-0000-4000-8000-000000000001', gen_random_uuid(), 'equipment', 'bands', 'Has bands', 'athlete_typed');
select lives_ok($$delete from auth.users where id = 'a1020000-0000-4000-8000-000000000001'$$,
  'an account can be deleted');
select is((select count(*) from public.coach_facts where user_id = 'a1020000-0000-4000-8000-000000000001')
    + (select count(*) from public.coach_notes where user_id = 'a1020000-0000-4000-8000-000000000001'),
  0::bigint, 'and its facts and notes go with it');

select * from finish();
rollback;
