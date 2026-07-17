begin;
select plan(36);

select has_table('public'::name, 'coach_narrative_entries'::name, 'coach_narrative_entries table exists');
select has_table('public'::name, 'user_preferences'::name, 'user_preferences table exists');
select has_table('public'::name, 'coach_session_summaries'::name, 'coach_session_summaries table exists');

select has_column('public'::name, 'coach_narrative_entries'::name, 'phase', 'phase column');
select has_column('public'::name, 'coach_narrative_entries'::name, 'headline', 'headline column');
select has_column('public'::name, 'coach_narrative_entries'::name, 'since', 'since column');
select has_column('public'::name, 'coach_narrative_entries'::name, 'until', 'until column');
select has_column('public'::name, 'coach_narrative_entries'::name, 'cause_snapshot_ids', 'cause_snapshot_ids column');
select has_column('public'::name, 'coach_narrative_entries'::name, 'superseded_by', 'superseded_by column');

select has_column('public'::name, 'user_preferences'::name, 'category', 'preference category column');
select has_column('public'::name, 'user_preferences'::name, 'key', 'preference key column');
select has_column('public'::name, 'user_preferences'::name, 'value', 'preference value column');
select has_column('public'::name, 'user_preferences'::name, 'provenance', 'provenance column');
select has_column('public'::name, 'user_preferences'::name, 'superseded_at', 'superseded_at column');

select has_column('public'::name, 'coach_session_summaries'::name, 'coaching_date', 'coaching_date column');
select has_column('public'::name, 'coach_session_summaries'::name, 'summary', 'summary column');
select has_column('public'::name, 'coach_session_summaries'::name, 'key_snapshot_ids', 'key_snapshot_ids column');

select has_index('public'::name, 'coach_narrative_entries'::name, 'coach_narrative_entries_user_active', 'narrative active index');
select has_index('public'::name, 'user_preferences'::name, 'user_preferences_owner_key_active', 'preferences unique active index');
select has_index('public'::name, 'coach_session_summaries'::name, 'coach_session_summaries_user_date', 'session summaries date index');

select has_column('public'::name, 'coach_messages'::name, 'search_vector', 'coach_messages FTS column');
select has_index('public'::name, 'coach_messages'::name, 'coach_messages_fts', 'coach_messages FTS index');

select ok(
  exists(select 1 from pg_catalog.pg_policies p join pg_catalog.pg_class c on c.oid=p.polrelid where c.relname='coach_narrative_entries' and p.polname='coach_narrative_entries_own_read'),
  'coach_narrative_entries RLS policy enabled'
);
select ok(
  (select relforcerowsecurity from pg_catalog.pg_class where relname='coach_narrative_entries') = true,
  'coach_narrative_entries RLS forced'
);
select ok(
  exists(select 1 from pg_catalog.pg_policies p join pg_catalog.pg_class c on c.oid=p.polrelid where c.relname='user_preferences' and p.polname='user_preferences_own_read'),
  'user_preferences RLS policy enabled'
);
select ok(
  (select relforcerowsecurity from pg_catalog.pg_class where relname='user_preferences') = true,
  'user_preferences RLS forced'
);
select ok(
  exists(select 1 from pg_catalog.pg_policies p join pg_catalog.pg_class c on c.oid=p.polrelid where c.relname='coach_session_summaries' and p.polname='coach_session_summaries_own_read'),
  'coach_session_summaries RLS policy enabled'
);
select ok(
  (select relforcerowsecurity from pg_catalog.pg_class where relname='coach_session_summaries') = true,
  'coach_session_summaries RLS forced'
);

select has_function('public'::name, 'prepare_coach_chat_v5', ARRAY['uuid','uuid','text','text','uuid','text'], 'prepare_coach_chat_v5 exists');
select has_function('public'::name, 'persist_coach_narrative_entry', ARRAY['uuid','text','text','date','uuid[]'], 'persist_coach_narrative_entry exists');
select has_function('public'::name, 'persist_coach_preference', ARRAY['uuid','text','text','text','text'], 'persist_coach_preference exists');
select has_function('public'::name, 'persist_coach_session_summary', ARRAY['uuid','date','text','uuid','uuid[]'], 'persist_coach_session_summary exists');
select has_function('public'::name, 'search_coach_messages', ARRAY['uuid','text','integer'], 'search_coach_messages exists');

select ok(
  not has_function_privilege('anon', 'public.prepare_coach_chat_v5(uuid,uuid,text,text,uuid,text)', 'execute'),
  'v5 not executable by anon'
);
select ok(
  not has_function_privilege('authenticated', 'public.prepare_coach_chat_v5(uuid,uuid,text,text,uuid,text)', 'execute'),
  'v5 not executable by authenticated'
);
select ok(
  has_function_privilege('service_role', 'public.prepare_coach_chat_v5(uuid,uuid,text,text,uuid,text)', 'execute'),
  'v5 executable by service_role'
);

select ok(
  not has_function_privilege('anon', 'public.persist_coach_preference(uuid,text,text,text,text)', 'execute'),
  'persist_coach_preference not executable by anon'
);
select ok(
  not has_function_privilege('authenticated', 'public.persist_coach_preference(uuid,text,text,text,text)', 'execute'),
  'persist_coach_preference not executable by authenticated'
);

select finish();
