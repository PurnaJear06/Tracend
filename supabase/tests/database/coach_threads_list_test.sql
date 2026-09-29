-- A2 thread list (migration 20260929090000).
--
-- get_my_coach_threads lists the caller's active threads that contain at
-- least one message, newest message first:
--   1. The response carries schema_version 1.0.
--   2. Only active threads with messages are listed, newest first. The empty
--      thread with the newest last_message_at (the old launch-time winner),
--      the archived thread and the other user's thread are not listed.
--   3. Each entry carries id, title, last_message_at and updated_at.
--   4. A caller whose only thread is empty gets an empty list.
--   5-7. Only authenticated callers may execute it.

begin;
select plan(7);

insert into auth.users(id, role) values
  ('c2a20000-0001-4001-8001-0000000000a1', 'authenticated'),
  ('c2a20000-0002-4001-8001-0000000000a2', 'authenticated'),
  ('c2a20000-0003-4001-8001-0000000000a3', 'authenticated');

insert into public.coach_threads(id, user_id, title, status, last_message_at) values
  ('c2a2c000-0001-4001-8001-000000000001', 'c2a20000-0001-4001-8001-0000000000a1',
    'Older with messages', 'active', now() - interval '2 days'),
  ('c2a2c000-0002-4001-8001-000000000002', 'c2a20000-0001-4001-8001-0000000000a1',
    'Newer with messages', 'active', now() - interval '1 day'),
  ('c2a2c000-0003-4001-8001-000000000003', 'c2a20000-0001-4001-8001-0000000000a1',
    'New conversation', 'active', now()),
  ('c2a2c000-0004-4001-8001-000000000004', 'c2a20000-0001-4001-8001-0000000000a1',
    'Archived with messages', 'archived', now()),
  ('c2a2c000-0005-4001-8001-000000000005', 'c2a20000-0002-4001-8001-0000000000a2',
    'Other user with messages', 'active', now()),
  ('c2a2c000-0006-4001-8001-000000000006', 'c2a20000-0003-4001-8001-0000000000a3',
    'New conversation', 'active', now());

insert into public.coach_messages(user_id, thread_id, role, content) values
  ('c2a20000-0001-4001-8001-0000000000a1', 'c2a2c000-0001-4001-8001-000000000001',
    'user', 'First question'),
  ('c2a20000-0001-4001-8001-0000000000a1', 'c2a2c000-0002-4001-8001-000000000002',
    'user', 'Second question'),
  ('c2a20000-0001-4001-8001-0000000000a1', 'c2a2c000-0002-4001-8001-000000000002',
    'assistant', 'An answer'),
  ('c2a20000-0001-4001-8001-0000000000a1', 'c2a2c000-0004-4001-8001-000000000004',
    'user', 'Archived question'),
  ('c2a20000-0002-4001-8001-0000000000a2', 'c2a2c000-0005-4001-8001-000000000005',
    'user', 'Other user question');

set local role authenticated;
set local "request.jwt.claim.sub" = 'c2a20000-0001-4001-8001-0000000000a1';

-- 1.
select is(
  public.get_my_coach_threads()->>'schema_version',
  '1.0',
  'the thread list carries schema_version 1.0');

-- 2.
select is(
  (select jsonb_agg(thread->>'title' order by position)
   from jsonb_array_elements(public.get_my_coach_threads()->'threads')
     with ordinality as listed(thread, position)),
  '["Newer with messages", "Older with messages"]'::jsonb,
  'only active threads with messages are listed, newest message first');

-- 3.
select is(
  (select array_agg(key order by key)
   from jsonb_object_keys(public.get_my_coach_threads()->'threads'->0) as key),
  array['id', 'last_message_at', 'title', 'updated_at'],
  'each thread carries id, title, last_message_at and updated_at');

-- 4.
set local "request.jwt.claim.sub" = 'c2a20000-0003-4001-8001-0000000000a3';
select is(
  public.get_my_coach_threads()->'threads',
  '[]'::jsonb,
  'a caller whose only thread is empty gets an empty list');

reset role;

-- 5-7.
select ok(
  has_function_privilege('authenticated', 'public.get_my_coach_threads()', 'execute'),
  'authenticated callers may list their threads');
select ok(
  not has_function_privilege('anon', 'public.get_my_coach_threads()', 'execute'),
  'anon cannot list threads');
select ok(
  not has_function_privilege('public', 'public.get_my_coach_threads()', 'execute'),
  'public cannot list threads');

select * from finish();
rollback;
