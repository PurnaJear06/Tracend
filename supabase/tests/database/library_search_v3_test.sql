begin;
select plan(40);

-- search_library_v3, the content digest, the library version, retiring a source and the version on
-- a Coach answer (migration 20261018170044). The fixtures assume an empty library.
delete from private.library_sources;

-- A 384-dimension vector with 1 at position i and 0 elsewhere.
create function pg_temp.vec(i integer)
returns extensions.vector language sql immutable as $$
  select array(select case when g = i then 1 else 0 end from generate_series(1, 384) g)::real[]::extensions.vector
$$;

-- Access ------------------------------------------------------------------------------------------
select ok(has_function_privilege('service_role',
  'public.search_library_v3(text, public.library_embedding, text, integer, jsonb, uuid)', 'execute'),
  'Edge Functions can run the v3 search');
select ok(not has_function_privilege('anon',
  'public.search_library_v3(text, public.library_embedding, text, integer, jsonb, uuid)', 'execute'),
  'visitors cannot');
select ok(not has_function_privilege('authenticated',
  'public.search_library_v3(text, public.library_embedding, text, integer, jsonb, uuid)', 'execute'),
  'app users cannot');
select ok((select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p
  where p.oid = 'public.search_library_v3(text, public.library_embedding, text, integer, jsonb, uuid)'::regprocedure),
  'the v3 search is security definer with an empty search_path');
select ok(to_regprocedure('public.search_library_v2(text, public.library_embedding, integer, jsonb, uuid)') is not null,
  'v2 stays for the deployed Coach chat');
select ok((select bool_and(not has_function_privilege('service_role', f, 'execute')
    and not has_function_privilege('anon', f, 'execute')
    and not has_function_privilege('authenticated', f, 'execute'))
  from unnest(array[
    'private.library_retire_source(text)',
    'private.library_version()',
    'private.library_source_digest(uuid)'
  ]) f), 'no API role can retire a source or call the digest helpers');

-- Fixture -----------------------------------------------------------------------------------------
insert into private.library_sources (id, manifest_key, title, year, url, licence, region, topics, evidence_level, kind)
values
  ('00000000-0000-4000-8000-0000000004a1', 'test-strength', 'Strength source', 2020,
    'https://example.test/strength', 'CC BY 4.0', '{global}', '{strength}', 'meta-analysis', 'paper'),
  ('00000000-0000-4000-8000-0000000004a2', 'test-other-model', 'Other model source', 2021,
    'https://example.test/other', 'CC BY 4.0', '{global}', '{strength}', 'narrative review', 'paper'),
  ('00000000-0000-4000-8000-0000000004a3', 'test-india', 'India source', 2024,
    'https://example.test/india', 'CC BY 4.0', '{IN}', '{nutrition}', 'guideline', 'guideline');
insert into private.library_chunks (id, source_id, ordinal, section, body, token_count, embedding, embedding_model)
values
  ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-0000000004a1', 0, 'Results',
    'Creatine loading raised muscle stores.', 8, pg_temp.vec(1), 'gte-small'),
  ('00000000-0000-4000-8000-000000000402', '00000000-0000-4000-8000-0000000004a1', 1, 'Limits',
    'Sleep and recovery notes.', 6, pg_temp.vec(2), 'gte-small'),
  ('00000000-0000-4000-8000-000000000403', '00000000-0000-4000-8000-0000000004a2', 0, 'Results',
    'Creatine timing around training.', 6, pg_temp.vec(1), 'other-model'),
  ('00000000-0000-4000-8000-000000000404', '00000000-0000-4000-8000-0000000004a3', 0, 'Guidance',
    'Creatine guidance for athletes in India.', 8, pg_temp.vec(1), 'gte-small');

insert into auth.users(id, role) values
  ('00000000-0000-4000-8000-0000000004c1', 'authenticated'),
  ('00000000-0000-4000-8000-0000000004c2', 'authenticated');
update public.user_accounts set timezone = 'Asia/Kolkata' where id = '00000000-0000-4000-8000-0000000004c1';

-- Search ------------------------------------------------------------------------------------------
create temp table hybrid on commit drop as
select * from public.search_library_v3('creatine', pg_temp.vec(1), 'gte-small', 8, null);
create temp table nearest on commit drop as
select * from public.search_library_v3('', pg_temp.vec(1), 'gte-small', 8, null);
create temp table words on commit drop as
select * from public.search_library_v3('creatine', null, null, 8, null);

select is(
  (select array_agg(k order by k collate "C") from jsonb_object_keys(
    (select to_jsonb(h) from hybrid h limit 1)) k),
  array['body', 'chunk_id', 'evidence_level', 'header', 'kind', 'library_version', 'schema_version',
    'score', 'section', 'source_id', 'source_key', 'text_rank', 'title', 'url', 'vector_distance', 'year'],
  'a v3 row has exactly the contract keys');
select ok((select bool_and(schema_version = 3) from hybrid), 'every row carries schema_version 3');
select ok((select abs(vector_distance) < 1e-6 from nearest where chunk_id = '00000000-0000-4000-8000-000000000401'),
  'an identical embedding is at cosine distance 0');
select ok((select abs(vector_distance - 1) < 1e-6 from nearest where chunk_id = '00000000-0000-4000-8000-000000000402'),
  'an orthogonal one is at distance 1');
select is((select count(*) from nearest where chunk_id = '00000000-0000-4000-8000-000000000403'), 0::bigint,
  'a chunk embedded with another model is never compared with the question');
select ok((select vector_distance is null from hybrid where chunk_id = '00000000-0000-4000-8000-000000000403'),
  'and a text hit on it carries no distance');
select ok((select text_rank > 0 from hybrid where chunk_id = '00000000-0000-4000-8000-000000000401'),
  'a chunk holding the terms has a positive text rank');
select ok((select text_rank = 0 from hybrid where chunk_id = '00000000-0000-4000-8000-000000000402'),
  'a vector-only hit has text rank 0');
select ok((select bool_and(text_rank is null) from nearest), 'without searchable terms the text rank is null');
select ok((select bool_and(vector_distance is null) from words), 'without an embedding the distance is null');
select throws_ok($$select * from public.search_library_v3('creatine', pg_temp.vec(1), null, 8, null)$$,
  '22023', 'query_embedding_model is required with an embedding', 'an embedding needs its model');
select is((select evidence_level || ' / ' || kind from hybrid where chunk_id = '00000000-0000-4000-8000-000000000401'),
  'meta-analysis / paper', 'rows carry the evidence level and kind');
select ok((select bool_and(library_version = private.library_version()) and bool_and(library_version ~ '^[0-9a-f]{16}$')
  from hybrid), 'every row carries the current library version');
select is((select count(*) from public.search_library_v3('creatine', null, null, 8, null,
    '00000000-0000-4000-8000-0000000004c2') where source_key = 'test-india'), 0::bigint,
  'an athlete outside India does not see the India source');
select is((select count(*) from public.search_library_v3('creatine', null, null, 8, null,
    '00000000-0000-4000-8000-0000000004c1') where source_key = 'test-india'), 1::bigint,
  'an athlete in India does');

-- Content digest and version ----------------------------------------------------------------------
select is((select count(*) from private.library_sources where content_sha256 is null
    or content_sha256 !~ '^[0-9a-f]{64}$'), 0::bigint, 'every source has a content digest');
select is((select content_sha256 from private.library_sources where id = '00000000-0000-4000-8000-0000000004a1'),
  private.library_source_digest('00000000-0000-4000-8000-0000000004a1'), 'it is the digest of what is stored');

create temp table before_change on commit drop as
select (select content_sha256 from private.library_sources where id = '00000000-0000-4000-8000-0000000004a1') as digest,
  private.library_version() as version;
update private.library_chunks set embedding = null, embedding_model = null, embed_attempts = 2
where id = '00000000-0000-4000-8000-000000000402';
select is((select content_sha256 from private.library_sources where id = '00000000-0000-4000-8000-0000000004a1'),
  (select digest from before_change), 'embedding state does not change the digest');
select is(private.library_version(), (select version from before_change), 'or the version');
update private.library_chunks set body = 'Sleep, recovery and rest notes.'
where id = '00000000-0000-4000-8000-000000000402';
select isnt((select content_sha256 from private.library_sources where id = '00000000-0000-4000-8000-0000000004a1'),
  (select digest from before_change), 'a changed chunk changes the source digest');
select isnt(private.library_version(), (select version from before_change), 'and the library version');
update private.library_sources set title = 'Strength source, revised' where id = '00000000-0000-4000-8000-0000000004a2';
select is((select content_sha256 from private.library_sources where id = '00000000-0000-4000-8000-0000000004a2'),
  private.library_source_digest('00000000-0000-4000-8000-0000000004a2'), 'a changed source field refreshes it too');

-- Loading and retiring ----------------------------------------------------------------------------
create temp table before_load on commit drop as select private.library_version() as version;
create temp table loaded on commit drop as
select private.library_replace_source(
  '{"slug":"test-loaded","title":"Loaded source","authors":["A"],"year":2022,"doi":null,"url":"https://example.test/loaded","licence":"CC BY 4.0","region":["global"],"topics":["sleep"],"evidence_level":"trial","kind":"paper"}'::jsonb,
  '[{"ordinal":0,"section":"S","header":"Source: A 2022. Section: S.","body":"One.","token_count":3},{"ordinal":1,"section":"S","header":"Source: A 2022. Section: S.","body":"Two.","token_count":3}]'::jsonb
) as id;
select is((select content_sha256 from private.library_sources where id = (select id from loaded)),
  private.library_source_digest((select id from loaded)), 'the loader leaves a current digest');
create temp table after_load on commit drop as select private.library_version() as version;
select private.library_replace_source(
  '{"slug":"test-loaded","title":"Loaded source","authors":["A"],"year":2022,"doi":null,"url":"https://example.test/loaded","licence":"CC BY 4.0","region":["global"],"topics":["sleep"],"evidence_level":"trial","kind":"paper"}'::jsonb,
  '[{"ordinal":0,"section":"S","header":"Source: A 2022. Section: S.","body":"One.","token_count":3},{"ordinal":1,"section":"S","header":"Source: A 2022. Section: S.","body":"Two.","token_count":3}]'::jsonb
);
select is(private.library_version(), (select version from after_load), 'loading the same content again keeps the version');
select is(private.library_retire_source('test-loaded'), true, 'retiring a source reports that it was removed');
select is((select count(*) from private.library_chunks where source_id = (select id from loaded)), 0::bigint,
  'with its chunks');
select is(private.library_retire_source('test-loaded'), false, 'retiring it again is harmless');
select is(private.library_version(), (select version from before_load),
  'and the version is back to the library without it');
select throws_ok($$select private.library_retire_source('Not A Key')$$, '22023', null,
  'a retire needs a manifest key');

-- The version on a Coach answer -------------------------------------------------------------------
insert into public.coach_threads(id, user_id, title, status) values
  ('00000000-0000-4000-8000-0000000004d1', '00000000-0000-4000-8000-0000000004c2', 'Chat', 'active');
insert into public.coach_messages(id, user_id, thread_id, role, content) values
  ('00000000-0000-4000-8000-0000000004e1', '00000000-0000-4000-8000-0000000004c2',
   '00000000-0000-4000-8000-0000000004d1', 'assistant', 'A reply');
select lives_ok($$update public.coach_messages set library_version = '0123456789abcdef'
    where id = '00000000-0000-4000-8000-0000000004e1'$$, 'a library version is stored on the answer');
select throws_ok($$update public.coach_messages set library_version = 'not a version'
    where id = '00000000-0000-4000-8000-0000000004e1'$$, '23514', null, 'anything else is refused');
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-4000-8000-0000000004c2';
select throws_ok($$update public.coach_messages set library_version = 'fedcba9876543210'$$, '42501', null,
  'the app cannot write it');
reset role;

-- Mixed embedding models ----------------------------------------------------------------------------
-- Forty chunks of an older model sit exactly on the question, nearer than every gte-small chunk. An
-- index scan (forced here by turning sequential scans off) would fill its candidate list with them
-- and the model filter would then leave nothing; the exact scan finds the gte-small chunks.
insert into private.library_sources (id, manifest_key, title, year, url, licence, region, topics, evidence_level, kind)
select ('00000000-0000-4000-8000-0000000005' || lpad(g::text, 2, '0'))::uuid, 'test-old-model-' || g,
  'Old model source ' || g, 2019, 'https://example.test/old' || g, 'CC BY 4.0', '{global}', '{strength}',
  'narrative review', 'paper'
from generate_series(1, 40) g;
insert into private.library_chunks (source_id, ordinal, section, body, token_count, embedding, embedding_model)
select ('00000000-0000-4000-8000-0000000005' || lpad(g::text, 2, '0'))::uuid, 0, 'Results',
  'Older notes ' || g || '.', 4, pg_temp.vec(3), 'old-model'
from generate_series(1, 40) g;
set local enable_seqscan = off;
create temp table mixed on commit drop as
select * from public.search_library_v3('', pg_temp.vec(3), 'gte-small', 8, null);
reset enable_seqscan;
select ok((select count(*) >= 1 and bool_and(vector_distance is not null) from mixed),
  'old-model vectors nearer than the question never crowd out the current model''s nearest rows');
select ok((select bool_and(source_key not like 'test-old-model-%') from mixed),
  'and none of them is returned');

select * from finish();
rollback;
