begin;
select plan(14);

-- The app's data summary stays in the conversation the Coach reads (migration 20261018210031).
-- prepare_coach_chat_v10 wraps v9 and rebuilds recent_messages with the summaries in, marked.

insert into auth.users(id, role) values
  ('a1910000-0000-4000-8000-000000000001', 'authenticated');

insert into public.coach_threads(id, user_id, title) values
  ('a1910000-0000-4000-8000-0000000000f1', 'a1910000-0000-4000-8000-000000000001', 'Chat');
insert into public.coach_messages(user_id, thread_id, role, content, answer_source, created_at) values
  ('a1910000-0000-4000-8000-000000000001', 'a1910000-0000-4000-8000-0000000000f1', 'user',
    'How is my weight trending?', null, now() - interval '3 minutes'),
  ('a1910000-0000-4000-8000-000000000001', 'a1910000-0000-4000-8000-0000000000f1', 'assistant',
    'SUMMARY_MARKER Latest weight: 78.4 kg. 4-week trend: -0.35 kg/week.', 'data_summary',
    now() - interval '3 minutes'),
  ('a1910000-0000-4000-8000-000000000001', 'a1910000-0000-4000-8000-0000000000f1', 'user',
    'Thanks, and my sleep?', null, now() - interval '2 minutes'),
  ('a1910000-0000-4000-8000-000000000001', 'a1910000-0000-4000-8000-0000000000f1', 'assistant',
    'MODEL_MARKER Your sleep is steady.', 'model', now() - interval '2 minutes');

-- A question the athlete sent again after it failed: marked superseded, its summary follows it.
insert into public.coach_messages(user_id, thread_id, role, content, answer_source, safety_state, created_at) values
  ('a1910000-0000-4000-8000-000000000001', 'a1910000-0000-4000-8000-0000000000f1', 'user',
    'SUPERSEDED_MARKER how is my protein?', null, 'unavailable', now() - interval '1 minute'),
  ('a1910000-0000-4000-8000-000000000001', 'a1910000-0000-4000-8000-0000000000f1', 'assistant',
    'ORPHAN_SUMMARY_MARKER Protein target: 150 g.', 'data_summary', 'unavailable', now() - interval '1 minute');

select has_function('public'::name, 'prepare_coach_chat_v10',
  array['uuid', 'uuid', 'text', 'text', 'uuid', 'text'], 'v10 exists');
select ok(has_function_privilege('service_role',
    'public.prepare_coach_chat_v10(uuid, uuid, text, text, uuid, text)', 'execute')
  and not has_function_privilege('authenticated',
    'public.prepare_coach_chat_v10(uuid, uuid, text, text, uuid, text)', 'execute')
  and not has_function_privilege('anon',
    'public.prepare_coach_chat_v10(uuid, uuid, text, text, uuid, text)', 'execute'),
  'only the service role may call it');

create temporary table r(name text primary key, j jsonb);
grant all on r to service_role;
set local role service_role;
insert into r select 'v9', public.prepare_coach_chat_v9('a1910000-0000-4000-8000-000000000001',
  'a1910000-0000-4000-8000-0000000000f1', 'And my protein?', 'UTC', gen_random_uuid(), 'general');
insert into r select 'v10', public.prepare_coach_chat_v10('a1910000-0000-4000-8000-000000000001',
  'a1910000-0000-4000-8000-0000000000f1', 'And my protein?', 'UTC', gen_random_uuid(), 'general');

select ok((select j -> 'context' ->> 'recent_messages' not like '%SUMMARY_MARKER%' from r where name = 'v9'),
  'v9, which is frozen, leaves the data summary out of the thread');
select ok((select j -> 'context' ->> 'recent_messages' like '%SUMMARY_MARKER%' from r where name = 'v10'),
  'v10 puts the data summary in the thread');
select is((select e ->> 'answer_source' from r, jsonb_array_elements(j -> 'context' -> 'recent_messages') e
    where name = 'v10' and e ->> 'content' like 'SUMMARY_MARKER%'),
  'data_summary', 'and marks it as the app''s summary');
select is((select count(*)::int from r, jsonb_array_elements(j -> 'context' -> 'recent_messages') e
    where name = 'v10' and e ? 'answer_source'),
  2, 'no other message carries the mark');
select is((select jsonb_agg(e ->> 'role' order by ord) from r,
    jsonb_array_elements(j -> 'context' -> 'recent_messages') with ordinality as t(e, ord)
    where name = 'v10'),
  '["user", "assistant", "user", "assistant", "user", "assistant"]'::jsonb,
  'the thread reads in order, each question before its reply');
select is((select e ->> 'safety_state' from r, jsonb_array_elements(j -> 'context' -> 'recent_messages') e
    where name = 'v10' and e ->> 'content' like 'SUPERSEDED_MARKER%'),
  'unavailable', 'a superseded question carries its state, so the reader can drop it');
select is((select count(*)::int from r, jsonb_array_elements(j -> 'context' -> 'recent_messages') e
    where name = 'v10' and e ? 'safety_state'),
  1, 'and no other message does, the summaries included');
select is((select e ->> 'answer_source' from r, jsonb_array_elements(j -> 'context' -> 'recent_messages') e
    where name = 'v10' and e ->> 'content' like 'ORPHAN_SUMMARY_MARKER%'),
  'data_summary', 'the summary that followed it is marked, so the reader can drop it with the question');
select is((select j -> 'context' ->> 'schema_version' from r where name = 'v10'), '8.1',
  'the context schema version moves from 8.0 to 8.1');
select ok((select (j -> 'context') ?& array['permitted_evidence', 'omitted_sections', 'coaching_date']
    from r where name = 'v10'),
  'the rest of the athlete file is kept');
select ok(coalesce((select context = (select j -> 'context' from r where name = 'v10')
      and context_checksum = encode(extensions.digest(convert_to(context::text, 'UTF8'), 'sha256'), 'hex')
    from public.coach_context_snapshots
    where id = (select (j ->> 'coach_context_snapshot_id')::uuid from r where name = 'v10')), true),
  'the stored snapshot matches what the Coach was given');
select ok((select (j ->> 'coach_context_snapshot_id') is not null from r where name = 'v10'),
  'a snapshot was stored for the turn');

select * from finish();
rollback;
