begin;
select plan(66);

-- The ranking fixtures below assume an empty library; E2's migration loads the real sources.
delete from private.library_sources;

-- A 384-dimension vector with weight w at position i and (1 - w) at position j.
create function pg_temp.vec(i integer, j integer default null, w real default 1)
returns extensions.vector language sql immutable as $$
  select array(
    select case when g = i then w when g = j then 1 - w else 0 end
    from generate_series(1, 384) g
  )::real[]::extensions.vector
$$;

-- Extension, tables, indexes --------------------------------------------------------------
select ok(exists (
  select 1 from pg_extension x join pg_namespace n on n.oid = x.extnamespace
  where x.extname = 'vector' and n.nspname = 'extensions'
), 'pgvector is installed in the extensions schema');

select ok((select bool_and(c.relrowsecurity and c.relforcerowsecurity)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private'
    and c.relname in ('library_sources', 'library_chunks', 'library_ingest_runs')
  having count(*) = 3), 'all three library tables have forced row level security');
select is((select count(*) from pg_policies
  where schemaname = 'private' and tablename like 'library\_%'), 0::bigint,
  'and no policies, so no API role sees a row');

select ok((select a.atttypmod = 384 and t.typname = 'vector'
  from pg_attribute a join pg_type t on t.oid = a.atttypid
  where a.attrelid = 'private.library_chunks'::regclass and a.attname = 'embedding'),
  'chunk embeddings are 384-dimension vectors');
select ok((select a.attgenerated = 's'
  from pg_attribute a
  where a.attrelid = 'private.library_chunks'::regclass and a.attname = 'fts'),
  'the full-text column is generated and stored');
select ok(exists (select 1 from pg_indexes where schemaname = 'private' and tablename = 'library_chunks'
  and indexdef like '%USING hnsw (embedding %vector_cosine_ops)%'),
  'an HNSW cosine index covers the embeddings');
select ok(exists (select 1 from pg_indexes where schemaname = 'private' and tablename = 'library_chunks'
  and indexdef like '%USING gin (fts)%'), 'a GIN index covers the full-text column');
select ok(exists (select 1 from pg_indexes where schemaname = 'private' and tablename = 'library_chunks'
  and indexdef like '%USING btree (source_id, ordinal)%'), 'a btree index leads with source_id');

-- Access ----------------------------------------------------------------------------------
select ok(not has_schema_privilege('anon', 'private', 'usage'), 'visitors cannot reach the private schema');
select ok(not has_schema_privilege('authenticated', 'private', 'usage'), 'app users cannot reach the private schema');
select ok(not has_table_privilege('anon', 'private.library_chunks', 'select'), 'visitors cannot read chunks');
select ok(not has_table_privilege('authenticated', 'private.library_chunks', 'select'), 'app users cannot read chunks');
select ok(not has_table_privilege('authenticated', 'private.library_sources', 'insert'), 'app users cannot add sources');
select ok(not has_table_privilege('authenticated', 'private.library_ingest_runs', 'select'), 'app users cannot read ingest runs');
select ok(not has_table_privilege('service_role', 'private.library_chunks', 'select'),
  'the service role reads chunks only through the search function');

select ok(has_function_privilege('service_role',
  'public.search_library_v1(text, public.library_embedding, integer, jsonb)', 'execute'),
  'Edge Functions can search the library');
select ok(not has_function_privilege('anon',
  'public.search_library_v1(text, public.library_embedding, integer, jsonb)', 'execute'), 'visitors cannot search');
select ok(not has_function_privilege('authenticated',
  'public.search_library_v1(text, public.library_embedding, integer, jsonb)', 'execute'), 'app users cannot search');
select ok((select proacl is not null from pg_proc
  where oid = 'public.search_library_v1(text, public.library_embedding, integer, jsonb)'::regprocedure)
  and not exists (
  select 1 from pg_proc p, aclexplode(p.proacl) a
  where p.oid = 'public.search_library_v1(text, public.library_embedding, integer, jsonb)'::regprocedure
    and a.grantee = 0 and a.privilege_type = 'EXECUTE'
), 'PUBLIC holds no execute grant');
select ok((select p.prosecdef and p.proconfig @> array['search_path=""']
  from pg_proc p where p.oid = 'public.search_library_v1(text, public.library_embedding, integer, jsonb)'::regprocedure),
  'the search function is security definer with an empty search_path');

set local role authenticated;
select throws_ok($$select count(*) from private.library_chunks$$, '42501', null,
  'an app user querying chunks is refused');
reset role;

-- Fixture ---------------------------------------------------------------------------------
insert into private.library_sources (id, manifest_key, title, year, url, licence, region, topics, kind)
values
  ('00000000-0000-4000-8000-0000000000a1', 'test-strength', 'Strength source', 2020,
    'https://example.test/strength', 'CC BY 4.0', '{global}', '{strength,supplements}', 'paper'),
  ('00000000-0000-4000-8000-0000000000a2', 'test-nutrition-in', 'Nutrition source (India)', 2024,
    'https://example.test/nutrition', 'Open Government Licence', '{IN}', '{nutrition,supplements}', 'guideline'),
  ('00000000-0000-4000-8000-0000000000a3', 'test-sleep-us', 'Sleep source (US)', 2022,
    'https://example.test/sleep', 'In-house summary', '{US}', '{sleep}', 'summary');

insert into private.library_chunks (id, source_id, ordinal, section, header, body, token_count, embedding, embedding_model)
values
  -- Found by both searches: second by text, second by vector.
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 0, 'Results',
    'Strength source: results', 'Creatine loading raised muscle stores within a week.', 12, pg_temp.vec(1, 2, 0.7), 'gte-small'),
  -- Keyword only: the best text match, never embedded.
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000a2', 0, 'Supplements',
    'Creatine loading', 'Creatine loading protocols: creatine loading for five days, then a daily dose. Creatine loading is optional.',
    24, null, null),
  -- Vector only: the nearest embedding, no shared words.
  ('00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-0000000000a3', 0, 'Sleep',
    'Sleep source: sleep', 'Sleep extension improved sprint times in athletes.', 10, pg_temp.vec(1), 'gte-small'),
  ('00000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-0000000000a3', 1, 'Sleep',
    'Sleep source: sleep', 'Creatine and sleep deprivation in shift workers.', 9, pg_temp.vec(3), 'gte-small');

-- Filler chunks so more than 8 candidates exist.
insert into private.library_chunks (source_id, ordinal, header, body, token_count, embedding, embedding_model)
select '00000000-0000-4000-8000-0000000000a1', n, 'Strength source: methods',
  'Bench press technique cue number ' || n || '.', 8, pg_temp.vec(10 + n), 'gte-small'
from generate_series(1, 6) n;

select ok((select fts @@ to_tsquery('english', 'results') and fts @@ to_tsquery('english', 'raised')
  from private.library_chunks where id = '00000000-0000-4000-8000-000000000001'),
  'the generated full-text column indexes header and body');

-- Ranking ---------------------------------------------------------------------------------
set local role service_role;

create temp table hits on commit drop as
select row_number() over () as place, r.*
from public.search_library_v1('creatine loading', pg_temp.vec(1), 8, null) r;

select is((select chunk_id from hits where place = 1), '00000000-0000-4000-8000-000000000001'::uuid,
  'a chunk found by both searches ranks first');
select ok(abs((select score from hits where place = 1) - (1.0 / 62 + 1.0 / 62)) < 1e-9,
  'its score is the sum of both reciprocal ranks with k = 60');
select ok(exists (select 1 from hits where chunk_id = '00000000-0000-4000-8000-000000000002'),
  'a keyword-only chunk without an embedding is found');
select ok(exists (select 1 from hits where chunk_id = '00000000-0000-4000-8000-000000000003'),
  'a vector-only chunk without shared words is found');
select ok((select bool_and(score <= previous_score)
  from (select score, lag(score) over (order by place) as previous_score from hits) s
  where previous_score is not null), 'rows come best first');
select is((select count(*) from hits), 8::bigint, 'eight rows when more candidates exist');
select ok((select bool_and(schema_version = 1) from hits), 'every row carries schema_version 1');
select is((select title from hits where place = 1), 'Strength source', 'rows carry the source title');
select is((select year from hits where place = 1), 2020::smallint, 'and its year');
select is((select url from hits where place = 1), 'https://example.test/strength', 'and its link');
select is((select section from hits where place = 1), 'Results', 'and the chunk section');
select is((select header from hits where place = 1), 'Strength source: results', 'and the context header');

select is(
  (select array_agg(k order by k collate "C") from jsonb_object_keys(
    (select to_jsonb(r) from public.search_library_v1('creatine', null, 1, null) r)) k),
  array['body', 'chunk_id', 'header', 'schema_version', 'score', 'section', 'source_id', 'title', 'url', 'year'],
  'the row has exactly the contract keys plus schema_version');

-- match_count
select is((select count(*) from public.search_library_v1('creatine loading', pg_temp.vec(1), 2, null)), 2::bigint,
  'match_count limits the rows');
select is((select count(*) from public.search_library_v1('creatine loading', pg_temp.vec(1), 100, null)), 8::bigint,
  'match_count is capped at 8');
select is((select count(*) from public.search_library_v1('creatine loading', pg_temp.vec(1), 0, null)), 1::bigint,
  'match_count below 1 returns one row');
select is((select count(*) from public.search_library_v1('creatine loading', pg_temp.vec(1), null, null)), 8::bigint,
  'a null match_count means 8');

-- Full-text only and vector only
select is(
  array(select chunk_id from public.search_library_v1('creatine loading', null, 8, null)),
  array['00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001']::uuid[],
  'with no embedding only full-text matches return, best text match first');
select is(
  array(select chunk_id from public.search_library_v1('', pg_temp.vec(1), 3, null)),
  array['00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000004']::uuid[],
  'with empty text the nearest embeddings return, nearest first');
select is((select count(*) from public.search_library_v1('  ', null, 8, null)), 0::bigint,
  'no text and no embedding returns nothing');
select is((select count(*) from public.search_library_v1('the and of', null, 8, null)), 0::bigint,
  'a query of stop words alone returns nothing');
select is((select count(*) from public.search_library_v1('-creatine', null, 8, null)), 0::bigint,
  'a query of negations alone returns nothing');
select is(
  (select chunk_id from public.search_library_v1('creatine loading' || repeat(' the', 300) || ' bench', null, 1, null)),
  '00000000-0000-4000-8000-000000000002'::uuid,
  'only the first 1000 characters of a long query are used (the trailing word is ignored)');

-- Filters
select is(
  array(select chunk_id from public.search_library_v1('creatine', null, 8, '{"region": ["IN"]}')),
  array['00000000-0000-4000-8000-000000000002']::uuid[],
  'a region filter keeps only sources for that region');
select is(
  array(select chunk_id from public.search_library_v1('', pg_temp.vec(1), 8, '{"topics": ["sleep"]}')),
  array['00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000004']::uuid[],
  'a topics filter applies to vector search too');
select is((select count(*) from public.search_library_v1('creatine', null, 8, '{"region": ["global", "US"], "topics": ["supplements"]}')),
  1::bigint, 'region and topics filters combine');
select is((select count(*) from public.search_library_v1('creatine', null, 8, '{"region": [], "topics": null}')),
  3::bigint, 'empty or null filter arrays do not filter');
select throws_ok($$select * from public.search_library_v1('creatine', null, 8, '{"regions": ["IN"]}')$$,
  '22023', 'unknown filter: regions', 'an unknown filter key is refused');
select throws_ok($$select * from public.search_library_v1('creatine', null, 8, '{"region": "IN"}')$$,
  '22023', 'filter region must be an array of text', 'a filter that is not an array is refused');
select throws_ok($$select * from public.search_library_v1('creatine', '[1,2,3]', 8, null)$$,
  '22000', 'expected 384 dimensions, not 3', 'an embedding of the wrong size is refused');
select throws_ok($$select * from public.search_library_v1('creatine', '[1,2,3]'::extensions.vector, 8, null)$$,
  '22000', 'expected 384 dimensions, not 3', 'a vector value of the wrong size is refused too');

reset role;

-- Constraints -----------------------------------------------------------------------------
select throws_ok($$insert into private.library_sources (manifest_key, title, licence, region, kind)
  values ('bad-empty-region', 'T', 'CC BY 4.0', '{}', 'paper')$$, '23514', null, 'a source needs at least one region');
select throws_ok($$insert into private.library_sources (manifest_key, title, licence, kind)
  values ('bad-no-region', 'T', 'CC BY 4.0', 'paper')$$, '23502', null, 'region has no default');
select throws_ok($$insert into private.library_sources (manifest_key, title, licence, region, kind)
  values ('bad-lower-region', 'T', 'CC BY 4.0', '{in}', 'paper')$$, '23514', null, 'regions are upper-case codes');
select throws_ok($$insert into private.library_sources (manifest_key, title, licence, region, kind)
  values ('bad-null-region', 'T', 'CC BY 4.0', array['global', null], 'paper')$$, '23514', null, 'a null region entry is refused');
select throws_ok($$insert into private.library_sources (manifest_key, title, licence, region, kind)
  values ('bad-name-region', 'T', 'CC BY 4.0', '{India}', 'paper')$$, '23514', null, 'regions are codes, not names');
select lives_ok($$insert into private.library_sources (manifest_key, title, licence, region, kind)
  values ('ok-region', 'T', 'CC BY 4.0', '{global,IN,GB}', 'paper')$$, 'global and two-letter codes are accepted');
select throws_ok($$insert into private.library_chunks (source_id, ordinal, body, token_count, embedding)
  values ('00000000-0000-4000-8000-0000000000a1', 99, 'x', 1, pg_temp.vec(1))$$, '23514', null,
  'an embedding needs its model');
select throws_ok($$insert into private.library_chunks (source_id, ordinal, body, token_count, embedding_model)
  values ('00000000-0000-4000-8000-0000000000a1', 99, 'x', 1, 'gte-small')$$, '23514', null,
  'a model without an embedding is refused');

-- Dump-safe signatures ----------------------------------------------------------------------
-- `supabase db dump` drops every GRANT/REVOKE line that names a quoted identifier from its
-- excluded-schema list after ON (CLI 2.101.0 dump script). A restored dump then leaves such a
-- function with Supabase's default grants. A function's GRANT line holds its name and its input
-- arguments' names and types, so none of them may come from (or be named like) those schemas.
create temp table dump_excluded on commit drop as
select '^(information_schema|pg_*|_analytics|_realtime|_supavisor|auth|etl|extensions|pgbouncer|realtime|storage|supabase_functions|supabase_migrations|cron|dbdev|graphql|graphql_public|net|pgmq|pgsodium|pgsodium_masks|pgtle|repack|tiger|tiger_data|timescaledb_*|_timescaledb_*|topology|vault)$'::text as pattern;
select is(
  (select array_agg(distinct p.oid::regprocedure::text order by p.oid::regprocedure::text)
   from pg_proc p
   join pg_namespace fn on fn.oid = p.pronamespace
   cross join lateral unnest(p.proargtypes::oid[]) as arg(type_oid)
   join pg_type t on t.oid = arg.type_oid
   join pg_namespace tn on tn.oid = t.typnamespace
   where fn.nspname in ('public', 'private') and tn.nspname ~ (select pattern from dump_excluded)),
  null,
  'no public or private function takes an argument whose type lives in a dump-excluded schema');
select is(
  (select array_agg(distinct p.oid::regprocedure::text order by p.oid::regprocedure::text)
   from pg_proc p
   join pg_namespace fn on fn.oid = p.pronamespace
   cross join lateral unnest(coalesce(p.proargnames, '{}'), coalesce(p.proargmodes, '{}'))
     as arg(arg_name, arg_mode)
   where fn.nspname in ('public', 'private')
     and (arg.arg_mode is null or arg.arg_mode in ('i', 'b', 'v'))
     and arg.arg_name ~ (select pattern from dump_excluded)),
  null,
  'no public or private function has an input argument named like a dump-excluded schema');
select is(
  (select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
   from pg_proc p join pg_namespace fn on fn.oid = p.pronamespace
   where fn.nspname in ('public', 'private') and p.proname ~ (select pattern from dump_excluded)),
  null,
  'no public or private function is named like a dump-excluded schema');
select is(
  (select array_agg(n.nspname || '.' || c.relname order by n.nspname, c.relname)
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'private') and c.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
     and c.relname ~ (select pattern from dump_excluded)),
  null,
  'no public or private table, view or sequence is named like a dump-excluded schema');

-- Deleting a source removes its chunks.
delete from private.library_sources where id = '00000000-0000-4000-8000-0000000000a3';
select is((select count(*) from private.library_chunks where source_id = '00000000-0000-4000-8000-0000000000a3'),
  0::bigint, 'deleting a source deletes its chunks');

select * from finish();
rollback;
