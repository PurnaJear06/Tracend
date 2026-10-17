begin;
select plan(96);

-- Start from a library with no embeddings, as production does right after the migration.
update private.library_chunks set embedding = null, embedding_model = null;

-- A JSON array of 384 numbers with 1 at position i and 0 elsewhere.
create function pg_temp.embedding_json(i integer)
returns jsonb language sql immutable as $$
  select to_jsonb(array(select case when g = i then 1 else 0 end from generate_series(1, 384) g))
$$;

-- Loaded content ------------------------------------------------------------------------------
select cmp_ok((select count(*) from private.library_sources), '>=', 30::bigint,
  'at least 30 sources are loaded');
select is((select count(*) from private.library_sources where btrim(licence) = ''), 0::bigint,
  'every source records its licence');
select is((select count(*) from private.library_sources where url not like 'https://%'),
  0::bigint, 'every source has a link');
select is((select count(*) from private.library_sources s
  where (select count(*) from private.library_chunks c where c.source_id = s.id) < 2),
  0::bigint, 'every source has at least two chunks');
select is((select count(*) from private.library_chunks where header not like 'Source: %Section: %.'),
  0::bigint, 'every chunk carries a source and section header');
select is((select count(*) from private.library_chunks where token_count > 512), 0::bigint,
  'every chunk fits the 512-token embedding window');
select is((select count(*) from private.library_chunks where embedding is not null), 0::bigint,
  'chunks load without embeddings');
select is((select count(*) from (select distinct unnest(region) r from private.library_sources) x
  where r not in ('global', 'US')), 0::bigint, 'regions are global or the one US guideline');
select ok(exists (select 1 from private.library_sources where doi = '10.1186/s12970-017-0177-8'
  and licence like 'CC BY%'), 'a known source loaded with its DOI and licence');
select ok((select bool_and(topics <> '{}') from private.library_sources), 'every source has topics');

-- Grants --------------------------------------------------------------------------------------
select ok((select bool_and(has_function_privilege('service_role', f, 'execute'))
  from unnest(array[
    'public.library_worker_authorized_v1(text)',
    'public.library_pending_chunks_v1(integer, uuid[])',
    'public.library_record_embed_failures_v1(uuid[])',
    'public.library_store_embeddings_v1(text, jsonb)',
    'public.library_record_run_v1(timestamptz, boolean, integer, integer, text)',
    'public.library_status_v1()'
  ]) f), 'the service role can run every library worker function');
select ok((select bool_and(not has_function_privilege('anon', f, 'execute')
    and not has_function_privilege('authenticated', f, 'execute'))
  from unnest(array[
    'public.library_worker_authorized_v1(text)',
    'public.library_pending_chunks_v1(integer, uuid[])',
    'public.library_record_embed_failures_v1(uuid[])',
    'public.library_store_embeddings_v1(text, jsonb)',
    'public.library_record_run_v1(timestamptz, boolean, integer, integer, text)',
    'public.library_status_v1()'
  ]) f), 'visitors and app users can run none of them');
select ok((select bool_and(not has_function_privilege('service_role', f, 'execute')
    and not has_function_privilege('anon', f, 'execute')
    and not has_function_privilege('authenticated', f, 'execute'))
  from unnest(array[
    'private.library_replace_source(jsonb, jsonb)',
    'private.library_worker_secret()',
    'private.library_embed_kick()'
  ]) f), 'the loader, the secret and the trigger are not callable by any API role');
select ok((select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('library_worker_authorized_v1',
    'library_pending_chunks_v1', 'library_store_embeddings_v1', 'library_record_run_v1',
    'library_record_embed_failures_v1', 'library_status_v1')), 'the worker functions are security definer');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.proname like 'library\_%'
    and p.proconfig is distinct from array['search_path=""']), 0::bigint,
  'every library function pins an empty search_path');

-- Cron ----------------------------------------------------------------------------------------
select is((select count(*) from cron.job where jobname = 'tracend-library-embed'), 1::bigint,
  'one cron job triggers the embedder');
select is((select schedule from cron.job where jobname = 'tracend-library-embed'), '* * * * *',
  'it runs every minute');
select is((select command from cron.job where jobname = 'tracend-library-embed'),
  'select private.library_embed_kick()', 'and calls the trigger function');

-- Worker secret ---------------------------------------------------------------------------------
select ok(length(private.library_worker_secret()) >= 32, 'the database creates a long worker secret');
select is(private.library_worker_secret(), private.library_worker_secret(), 'the secret is stable');
select is((select count(*) from vault.secrets where name = 'library_worker_secret'), 1::bigint,
  'and kept once in Vault');
select ok(public.library_worker_authorized_v1(private.library_worker_secret()),
  'the secret authorises the worker');
select ok(not public.library_worker_authorized_v1('wrong'), 'a wrong secret does not');
select ok(not public.library_worker_authorized_v1(''), 'an empty secret does not');
select ok(not public.library_worker_authorized_v1(null), 'a missing secret does not');

-- Embed target ------------------------------------------------------------------------------------
-- The kick posts only to a URL an operator stored in Vault. net.http_request_queue is pg_net's
-- queue: a post made inside this transaction is visible here and rolled back with it.
create temporary table queue_before(n bigint);
insert into queue_before select count(*) from net.http_request_queue;

select is((select count(*) from vault.secrets where name = 'library_embed_url'), 0::bigint,
  'a fresh database has no embed URL');
select lives_ok($$select private.library_embed_kick()$$, 'the kick runs without a URL');
select is((select count(*) from net.http_request_queue), (select n from queue_before),
  'and posts nothing while no URL is stored');

select throws_ok($$select private.library_set_embed_url(null)$$, '22023', null, 'a missing URL is refused');
select throws_ok($$select private.library_set_embed_url('http://abcdefghijklmnopqrst.supabase.co/functions/v1/library-embed')$$,
  '22023', null, 'a plain http URL is refused');
select throws_ok($$select private.library_set_embed_url('https://abcdefghijklmnopqrs.supabase.co/functions/v1/library-embed')$$,
  '22023', null, 'a project reference of 19 letters is refused');
select throws_ok($$select private.library_set_embed_url('https://ABCDEFGHIJKLMNOPQRST.supabase.co/functions/v1/library-embed')$$,
  '22023', null, 'and one in capitals');
select throws_ok($$select private.library_set_embed_url('https://abcdefghijklmnopqrst.supabase.co.example.com/functions/v1/library-embed')$$,
  '22023', null, 'another host is refused');
select throws_ok($$select private.library_set_embed_url('https://abcdefghijklmnopqrst.supabase.co/functions/v1/health-check')$$,
  '22023', null, 'another function is refused');
select throws_ok($$select private.library_set_embed_url('https://abcdefghijklmnopqrst.supabase.co/functions/v1/library-embed/')$$,
  '22023', null, 'and a trailing slash');
select is((select count(*) from vault.secrets where name = 'library_embed_url'), 0::bigint,
  'a refused URL stores nothing');

select lives_ok($$select private.library_set_embed_url('https://abcdefghijklmnopqrst.supabase.co/functions/v1/library-embed')$$,
  'a project URL is accepted');
select is((select decrypted_secret from vault.decrypted_secrets where name = 'library_embed_url'),
  'https://abcdefghijklmnopqrst.supabase.co/functions/v1/library-embed', 'and stored in Vault');
update queue_before set n = (select count(*) from net.http_request_queue);
select lives_ok($$select private.library_embed_kick()$$, 'the kick runs with a URL');
select is((select count(*) from net.http_request_queue), (select n + 1 from queue_before),
  'and posts once while chunks wait');
select is((select url from net.http_request_queue order by id desc limit 1),
  'https://abcdefghijklmnopqrst.supabase.co/functions/v1/library-embed', 'to the stored URL');

select lives_ok($$select private.library_set_embed_url('https://tsrqponmlkjihgfedcba.supabase.co/functions/v1/library-embed')$$,
  'setting the URL again is accepted');
select is((select count(*) from vault.secrets where name = 'library_embed_url'), 1::bigint,
  'and keeps one secret');
select is((select decrypted_secret from vault.decrypted_secrets where name = 'library_embed_url'),
  'https://tsrqponmlkjihgfedcba.supabase.co/functions/v1/library-embed', 'with the new value');

select vault.update_secret((select id from vault.secrets where name = 'library_embed_url'), ' ');
update queue_before set n = (select count(*) from net.http_request_queue);
select lives_ok($$select private.library_embed_kick()$$, 'the kick runs with a blank URL');
select is((select count(*) from net.http_request_queue), (select n from queue_before),
  'and posts nothing');

-- Failed attempts: the kick stops once every waiting chunk has failed 5 times.
select private.library_set_embed_url('https://abcdefghijklmnopqrst.supabase.co/functions/v1/library-embed');
update private.library_chunks set embed_attempts = 5 where embedding is null;
update queue_before set n = (select count(*) from net.http_request_queue);
select lives_ok($$select private.library_embed_kick()$$, 'the kick runs when every waiting chunk has given up');
select is((select count(*) from net.http_request_queue), (select n from queue_before),
  'and posts nothing');
update private.library_chunks set embed_attempts = 4
  where id = (select id from private.library_chunks where embedding is null limit 1);
select lives_ok($$select private.library_embed_kick()$$, 'the kick runs when one chunk has an attempt left');
select is((select count(*) from net.http_request_queue), (select n + 1 from queue_before),
  'and posts again');
update private.library_chunks set embed_attempts = 0;

select ok(has_function_privilege('service_role', 'private.library_set_embed_url(text)', 'execute'),
  'the service role can set the embed URL');
select ok(not has_function_privilege('anon', 'private.library_set_embed_url(text)', 'execute'),
  'visitors cannot');
select ok(not has_function_privilege('authenticated', 'private.library_set_embed_url(text)', 'execute'),
  'and neither can app users');

-- Pending chunks ----------------------------------------------------------------------------------
select is((select count(*) from public.library_pending_chunks_v1(3)), 3::bigint, 'a batch is as large as asked');
select is((select count(*) from public.library_pending_chunks_v1(0)), 1::bigint, 'a batch is at least one');
select is((select count(*) from public.library_pending_chunks_v1(null)),
  least(25, (select count(*) from private.library_chunks)), 'a missing size means 25');
select is((select count(*) from public.library_pending_chunks_v1(100000)),
  least(200, (select count(*) from private.library_chunks)), 'a batch is at most 200');
select ok((select bool_and(input_text = c.header || E'\n' || c.body)
  from public.library_pending_chunks_v1(50) p join private.library_chunks c on c.id = p.chunk_id),
  'the text to embed is the header, a line break and the body');
select is((select array_agg(chunk_id order by chunk_id) from public.library_pending_chunks_v1(10)),
  (select array_agg(chunk_id order by chunk_id) from public.library_pending_chunks_v1(10)),
  'the order is stable between calls');

-- Failed attempts -------------------------------------------------------------------------------------
create temp table poison as select chunk_id from public.library_pending_chunks_v1(1);
select ok(not exists (select 1 from public.library_pending_chunks_v1(200, array[(select chunk_id from poison)])
  where chunk_id = (select chunk_id from poison)), 'a chunk the caller excludes is not offered');
select ok(exists (select 1 from public.library_pending_chunks_v1(200, array[(select chunk_id from poison)])),
  'and the other chunks still are');
select public.library_record_embed_failures_v1(array[(select chunk_id from poison)]) from generate_series(1, 4);
select is((select embed_attempts from private.library_chunks where id = (select chunk_id from poison)), 4,
  'four failures are counted');
select is((select count(*) from public.library_pending_chunks_v1(200) where chunk_id = (select chunk_id from poison)),
  1::bigint, 'and the chunk is still offered');
select is(public.library_record_embed_failures_v1(array[(select chunk_id from poison)]), 1,
  'the fifth failure reports the chunk as given up');
select is((select embed_attempts from private.library_chunks where id = (select chunk_id from poison)), 5,
  'five failures are counted');
select ok((select embed_failed_at is not null from private.library_chunks where id = (select chunk_id from poison)),
  'with the time of the last one');
select is((select count(*) from public.library_pending_chunks_v1(200) where chunk_id = (select chunk_id from poison)),
  0::bigint, 'a chunk that failed five times is no longer offered');
select is(public.library_record_embed_failures_v1(array[(select chunk_id from poison)]), 0,
  'and a further failure is not reported again');
select is(public.library_record_embed_failures_v1(null), 0, 'no chunks is no failures');
update private.library_chunks set embed_attempts = 0, embed_failed_at = null;
select is((select count(*) from public.library_pending_chunks_v1(200) where chunk_id = (select chunk_id from poison)),
  1::bigint, 'resetting the count offers the chunk again');

-- Storing embeddings -------------------------------------------------------------------------------
create temp table first_chunk as
  select chunk_id from public.library_pending_chunks_v1(1);
select is(public.library_store_embeddings_v1('gte-small',
  jsonb_build_array(jsonb_build_object('chunk_id', (select chunk_id from first_chunk),
    'embedding', pg_temp.embedding_json(7)))), 1, 'one embedding is stored');
select is((select embedding_model from private.library_chunks where id = (select chunk_id from first_chunk)),
  'gte-small', 'with its model name');
select is(public.library_store_embeddings_v1('gte-small',
  jsonb_build_array(jsonb_build_object('chunk_id', (select chunk_id from first_chunk),
    'embedding', pg_temp.embedding_json(9)))), 0, 'storing again changes nothing');
select ok((select embedding = (pg_temp.embedding_json(7)::text)::extensions.vector
  from private.library_chunks where id = (select chunk_id from first_chunk)),
  'and the first embedding stays');
select is(public.library_store_embeddings_v1('gte-small',
  jsonb_build_array(jsonb_build_object('chunk_id', gen_random_uuid(),
    'embedding', pg_temp.embedding_json(1)))), 0, 'an unknown chunk is ignored');
select is((select count(*) from public.library_pending_chunks_v1(200) where chunk_id = (select chunk_id from first_chunk)),
  0::bigint, 'an embedded chunk is no longer pending');
select throws_ok($$select public.library_store_embeddings_v1('gte-small',
  jsonb_build_array(jsonb_build_object('chunk_id', gen_random_uuid(), 'embedding', '[1,2,3]'::jsonb)))$$,
  '22000', null, 'a vector of the wrong size is refused');
create temp table next_chunk as select chunk_id from public.library_pending_chunks_v1(1);
select throws_ok($$select public.library_store_embeddings_v1('gte-small',
  jsonb_build_array(jsonb_build_object('chunk_id', (select chunk_id from next_chunk))))$$,
  '22023', null, 'an item without an embedding is refused');
select throws_ok($$select public.library_store_embeddings_v1('gte-small',
  jsonb_build_array(jsonb_build_object('chunk_id', (select chunk_id from next_chunk), 'embedding', null)))$$,
  '22023', null, 'and one with a null embedding');
select throws_ok($$select public.library_store_embeddings_v1('gte-small',
  jsonb_build_array(jsonb_build_object('embedding', pg_temp.embedding_json(2))))$$,
  '22023', null, 'and one without a chunk');
select throws_ok($$select public.library_store_embeddings_v1('gte-small', jsonb_build_array(
  jsonb_build_object('chunk_id', (select chunk_id from next_chunk), 'embedding', pg_temp.embedding_json(2)),
  jsonb_build_object('chunk_id', gen_random_uuid())))$$,
  '22023', null, 'a batch with one bad item is refused');
select is((select embedding is null from private.library_chunks where id = (select chunk_id from next_chunk)),
  true, 'and stores none of it');
select throws_ok($$select public.library_store_embeddings_v1('  ', '[]'::jsonb)$$, '22023', null,
  'a blank model name is refused');
select throws_ok($$select public.library_store_embeddings_v1('gte-small', '{}'::jsonb)$$, '22023', null,
  'items that are not an array are refused');
select ok(exists (select 1 from public.search_library_v1(null, (pg_temp.embedding_json(7)::text)::public.library_embedding, 1, null)
  where chunk_id = (select chunk_id from first_chunk)),
  'search finds the stored embedding as its nearest match');

-- The loader keeps valid embeddings -------------------------------------------------------------------
create temp table sample as
  select s.id,
    jsonb_build_object('slug', s.manifest_key, 'title', s.title, 'authors', to_jsonb(s.authors),
      'year', s.year, 'doi', s.doi, 'url', s.url, 'licence', s.licence, 'region', to_jsonb(s.region),
      'topics', to_jsonb(s.topics), 'evidence_level', s.evidence_level, 'kind', s.kind) as source_data,
    (select jsonb_agg(jsonb_build_object('ordinal', c.ordinal, 'section', c.section, 'header', c.header,
      'body', c.body, 'token_count', c.token_count) order by c.ordinal)
     from private.library_chunks c where c.source_id = s.id) as chunk_data
  from private.library_sources s where s.doi = '10.1186/s12970-017-0177-8';
create temp table sample_chunks as
  select id from private.library_chunks where source_id = (select id from sample);
select public.library_store_embeddings_v1('gte-small',
  (select jsonb_agg(jsonb_build_object('chunk_id', id, 'embedding', pg_temp.embedding_json(3))) from sample_chunks
   where id not in (select chunk_id from first_chunk)));
select is(private.library_replace_source((select source_data from sample), (select chunk_data from sample)),
  (select id from sample), 'loading a source again returns the same source');
select is((select count(*) from private.library_chunks where source_id = (select id from sample)
  and id in (select id from sample_chunks)), (select count(*) from sample_chunks),
  'unchanged chunks keep their rows');
select ok((select bool_and(embedding is not null) from private.library_chunks where id in (select id from sample_chunks)
  and id not in (select chunk_id from first_chunk)), 'and their embeddings');
select is((select count(*) from private.library_sources where doi = '10.1186/s12970-017-0177-8'), 1::bigint,
  'the source is not duplicated');

select private.library_replace_source((select source_data from sample),
  jsonb_set((select chunk_data from sample), '{0,body}', to_jsonb('A changed body.'::text)));
select is((select count(*) from private.library_chunks where id in (select id from sample_chunks)), 0::bigint,
  'a changed chunk replaces the source''s chunks');
select is((select count(*) from private.library_chunks where source_id = (select id from sample) and embedding is null),
  (select count(*) from private.library_chunks where source_id = (select id from sample)),
  'and the new chunks wait for embedding');
select is((select body from private.library_chunks where source_id = (select id from sample) and ordinal = 0),
  'A changed body.', 'with the new text');

-- Runs ------------------------------------------------------------------------------------------------
select ok(public.library_record_run_v1(now() - interval '1 minute', true, 2, 10, null) is not null,
  'a finished run is recorded');
select is((select status from private.library_ingest_runs order by started_at desc limit 1), 'succeeded',
  'as succeeded');
select ok(public.library_record_run_v1(now() + interval '1 hour', false, 1, 0, 'boom') is not null,
  'a failed run with a start time in the future is recorded');
select is(((public.library_status_v1() ->> 'sources')::bigint), (select count(*) from private.library_sources),
  'the status counts sources');

select * from finish();
rollback;
