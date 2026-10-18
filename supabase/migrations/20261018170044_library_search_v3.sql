-- Research library search, version 3, and library versioning (coaching platform program, E3
-- production pass, migration code 44) -------------------------------------------------------
--
-- Additive. search_library_v2 stays for the Coach chat build that is deployed now; the Edge
-- Functions in this commit call v3.
--
--   1. public.search_library_v3: v2's hybrid search, plus per row the cosine distance to the
--      question (vector_distance), the full-text rank (text_rank), the source's evidence level and
--      kind, and the library version. Vector search is exact (no index scan) and uses only chunks embedded with the model that
--      embedded the question (query_embedding_model), so a re-embedding with another model never
--      compares vectors from two models. Coach chat drops rows past a calibrated relevance floor
--      (supabase/functions/_shared/library/retrieval.ts), so the distances come back raw.
--   2. private.library_sources.content_sha256: a digest of what the loader stored for a source
--      (its fields and its chunks' text), kept current by triggers whatever path writes the rows.
--      private.library_version() digests every source's key and content_sha256 into 16 hex
--      characters: two databases with the same library report the same version.
--   3. public.coach_messages.library_version: the library version a Coach answer was shown
--      excerpts from, written by coach-chat with the turn trace (service role; nothing in the app
--      writes it).
--   4. private.library_retire_source(key): removes a source that left supabase/library/index.ts,
--      with its chunks. Content migrations call it (build_migration.ts --retire), as they call
--      library_replace_source for sources that are added or changed.
--   5. private.library_replace_source is redefined to compare and write token_count too, so the
--      loader and the digest agree.

-- 2. Content digest -----------------------------------------------------------------------------

alter table private.library_sources
  add column content_sha256 text check (content_sha256 ~ '^[0-9a-f]{64}$');

-- The digest of one source as the loader stores it: the fields library_replace_source writes and
-- each chunk's ordinal, section, header, body and token count. Embeddings, attempts and timestamps
-- are left out: they change without the content changing. A migration that adds a content column
-- to the loader adds it here too.
create function private.library_source_digest(target_source_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select encode(sha256(convert_to(jsonb_build_object(
    'source', jsonb_build_object(
      'manifest_key', s.manifest_key, 'title', s.title, 'authors', to_jsonb(s.authors),
      'year', s.year, 'doi', s.doi, 'url', s.url, 'licence', s.licence,
      'region', to_jsonb(s.region), 'topics', to_jsonb(s.topics),
      'evidence_level', s.evidence_level, 'kind', s.kind
    ),
    'chunks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ordinal', c.ordinal, 'section', c.section, 'header', c.header, 'body', c.body,
        'token_count', c.token_count
      ) order by c.ordinal)
      from private.library_chunks c where c.source_id = s.id
    ), '[]'::jsonb)
  )::text, 'UTF8')), 'hex')
  from private.library_sources s
  where s.id = target_source_id
$$;
revoke all on function private.library_source_digest(uuid)
  from public, anon, authenticated, service_role;

create function private.library_sources_refresh_digest()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update private.library_sources s
  set content_sha256 = private.library_source_digest(s.id)
  where s.id = new.id;
  return null;
end
$$;
revoke all on function private.library_sources_refresh_digest()
  from public, anon, authenticated, service_role;

create function private.library_chunks_refresh_digest()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    update private.library_sources s
    set content_sha256 = private.library_source_digest(s.id)
    where s.id = old.source_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    update private.library_sources s
    set content_sha256 = private.library_source_digest(s.id)
    where s.id = new.source_id;
  end if;
  return null;
end
$$;
revoke all on function private.library_chunks_refresh_digest()
  from public, anon, authenticated, service_role;

-- Content columns only: storing an embedding or counting a failed attempt does not touch the
-- digest, and the digest's own update does not fire its trigger again.
create trigger library_sources_digest
after insert or update of manifest_key, title, authors, year, doi, url, licence, region, topics,
  evidence_level, kind
on private.library_sources
for each row execute function private.library_sources_refresh_digest();

create trigger library_chunks_digest
after insert or delete or update of source_id, ordinal, section, header, body, token_count
on private.library_chunks
for each row execute function private.library_chunks_refresh_digest();

update private.library_sources s set content_sha256 = private.library_source_digest(s.id);

-- The library version: the first 16 hex characters of a digest over every source's key and
-- content digest, in key order. It changes exactly when a source is added, changed or retired.
create function private.library_version()
returns text
language sql
stable
set search_path = ''
as $$
  select left(encode(sha256(convert_to(coalesce(
    string_agg(s.manifest_key || ':' || coalesce(s.content_sha256, ''), ',' order by s.manifest_key),
    ''
  ), 'UTF8')), 'hex'), 16)
  from private.library_sources s
$$;
revoke all on function private.library_version() from public, anon, authenticated, service_role;

-- The loader and the digest agree. The digest (above) covers each chunk's token_count, but the
-- loader compared only ordinal, section, header and body, so a re-load that changed only a token
-- count wrote nothing and the stored rows no longer matched the library files. Redefined here
-- (same signature, same grants): a change to the text re-writes the chunks as before (their
-- embeddings are then made again); a change to token counts alone updates them in place, since
-- the embedding does not depend on the count. Each write refreshes the digest through its trigger.
create or replace function private.library_replace_source(source_data jsonb, chunk_data jsonb)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  sid uuid;
begin
  insert into private.library_sources (
    manifest_key, title, authors, year, doi, url, licence, region, topics, evidence_level, kind
  )
  values (
    source_data ->> 'slug',
    source_data ->> 'title',
    array(select jsonb_array_elements_text(source_data -> 'authors')),
    (source_data ->> 'year')::smallint,
    source_data ->> 'doi',
    source_data ->> 'url',
    source_data ->> 'licence',
    array(select jsonb_array_elements_text(source_data -> 'region')),
    array(select jsonb_array_elements_text(source_data -> 'topics')),
    source_data ->> 'evidence_level',
    source_data ->> 'kind'
  )
  on conflict (manifest_key) do update set
    title = excluded.title,
    authors = excluded.authors,
    year = excluded.year,
    doi = excluded.doi,
    url = excluded.url,
    licence = excluded.licence,
    region = excluded.region,
    topics = excluded.topics,
    evidence_level = excluded.evidence_level,
    kind = excluded.kind
  returning id into sid;

  if (
    select coalesce(jsonb_agg(jsonb_build_object(
      'ordinal', c.ordinal, 'section', c.section, 'header', c.header, 'body', c.body
    ) order by c.ordinal), '[]'::jsonb)
    from private.library_chunks c where c.source_id = sid
  ) is distinct from (
    select coalesce(jsonb_agg(jsonb_build_object(
      'ordinal', (e ->> 'ordinal')::integer, 'section', e ->> 'section',
      'header', e ->> 'header', 'body', e ->> 'body'
    ) order by (e ->> 'ordinal')::integer), '[]'::jsonb)
    from jsonb_array_elements(chunk_data) e
  ) then
    delete from private.library_chunks c where c.source_id = sid;
    insert into private.library_chunks (source_id, ordinal, section, header, body, token_count)
    select
      sid,
      (e ->> 'ordinal')::integer,
      e ->> 'section',
      e ->> 'header',
      e ->> 'body',
      (e ->> 'token_count')::integer
    from jsonb_array_elements(chunk_data) e;
  else
    update private.library_chunks c
    set token_count = (e ->> 'token_count')::integer
    from jsonb_array_elements(chunk_data) e
    where c.source_id = sid
      and c.ordinal = (e ->> 'ordinal')::integer
      and c.token_count is distinct from (e ->> 'token_count')::integer;
  end if;

  return sid;
end
$$;
revoke all on function private.library_replace_source(jsonb, jsonb)
  from public, anon, authenticated, service_role;

-- 4. Retiring a source --------------------------------------------------------------------------

-- Deletes the source with this manifest key and, through the foreign key, its chunks. Returns
-- whether a source was removed (false when none had the key, so a retire block can run twice).
-- Run by migrations as the table owner; nothing else may call it.
create function private.library_retire_source(source_key text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  removed integer;
begin
  if source_key is null or source_key !~ '^[a-z0-9][a-z0-9_.-]{0,119}$' then
    raise exception 'source_key must be a manifest key' using errcode = '22023';
  end if;
  delete from private.library_sources s where s.manifest_key = source_key;
  get diagnostics removed = row_count;
  return removed > 0;
end
$$;
revoke all on function private.library_retire_source(text)
  from public, anon, authenticated, service_role;

-- 3. The version a Coach answer saw -------------------------------------------------------------

alter table public.coach_messages
  add column library_version text,
  add constraint coach_messages_library_version_check
    check (library_version is null or library_version ~ '^[0-9a-f]{16}$');

-- 1. Search, version 3 --------------------------------------------------------------------------

-- Contract 6, version 3. The same hybrid search as v2 (the 30 best full-text matches, terms ORed,
-- and the 30 nearest embeddings, merged by reciprocal rank fusion with k = 50; at most three rows
-- per source; the athlete's regions through target_user_id), with:
--
--   query_embedding_model  the model that embedded query_embedding ('gte-small'); required with an
--                          embedding (22023 otherwise). Only chunks embedded with it are compared.
--   vector_distance        cosine distance between the chunk and the question (0 is identical, 2
--                          opposite), for every row whose chunk has an embedding from that model;
--                          null without a query embedding
--   text_rank              ts_rank (normalisation 1) of the chunk for the ORed terms, 0 when the
--                          chunk holds none of them; null when the question has no searchable term
--   evidence_level, kind   from the source
--   library_version        private.library_version(), the same on every row
--
-- Rows carry schema_version 3. No query (both inputs skipped) returns no rows.
create function public.search_library_v3(
  query_text text,
  query_embedding public.library_embedding,
  query_embedding_model text,
  match_count integer,
  filters jsonb,
  target_user_id uuid default null
)
returns table (
  schema_version integer,
  chunk_id uuid,
  source_id uuid,
  source_key text,
  title text,
  year smallint,
  url text,
  section text,
  body text,
  header text,
  evidence_level text,
  kind text,
  score double precision,
  vector_distance double precision,
  text_rank double precision,
  library_version text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  result_limit constant integer := least(greatest(coalesce(match_count, 8), 1), 10);
  candidate_limit constant integer := 30;
  per_source_limit constant integer := 3;
  rrf_k constant double precision := 50;
  or_terms text;
  text_query tsquery;
  region_filter text[];
  topic_filter text[];
  filter_key text;
  text_ids uuid[] := '{}';
  vector_ids uuid[] := '{}';
  current_version text := private.library_version();
begin
  if query_embedding is not null
    and (query_embedding_model is null or btrim(query_embedding_model) = '') then
    raise exception 'query_embedding_model is required with an embedding' using errcode = '22023';
  end if;

  if filters is not null and jsonb_typeof(filters) <> 'null' then
    if jsonb_typeof(filters) <> 'object' then
      raise exception 'filters must be an object' using errcode = '22023';
    end if;
    for filter_key in select jsonb_object_keys(filters) loop
      if filter_key not in ('region', 'topics') then
        raise exception 'unknown filter: %', filter_key using errcode = '22023';
      end if;
      if jsonb_typeof(filters -> filter_key) not in ('array', 'null')
        or exists (
          select 1 from jsonb_array_elements(
            case when jsonb_typeof(filters -> filter_key) = 'array' then filters -> filter_key else '[]'::jsonb end
          ) element
          where jsonb_typeof(element) <> 'string'
        ) then
        raise exception 'filter % must be an array of text', filter_key using errcode = '22023';
      end if;
    end loop;
    if jsonb_typeof(filters -> 'region') = 'array' then
      select array_agg(value) into region_filter from jsonb_array_elements_text(filters -> 'region');
    end if;
    if jsonb_typeof(filters -> 'topics') = 'array' then
      select array_agg(value) into topic_filter from jsonb_array_elements_text(filters -> 'topics');
    end if;
  end if;

  -- The athlete's own regions, unless the caller named some.
  if region_filter is null and target_user_id is not null then
    region_filter := private.library_regions_for_account(target_user_id);
  end if;

  if length(btrim(coalesce(query_text, ''))) > 0 then
    select string_agg(quote_literal(w.term), ' | ' order by w.term) into or_terms
    from (
      select distinct t.term
      from regexp_split_to_table(lower(left(query_text, 1000)), '[^a-z0-9]+') as t(term)
      where length(t.term) >= 2
    ) w;
    if or_terms is not null then
      text_query := to_tsquery('english', or_terms);
      -- Only stop words: nothing an index can match.
      if numnode(text_query) = 0 or querytree(text_query) = 'T' then
        text_query := null;
      end if;
    end if;
  end if;

  if text_query is not null then
    select coalesce(array_agg(t.id order by t.rank_value desc, t.id), '{}') into text_ids
    from (
      select c.id, ts_rank(c.fts, text_query, 1) as rank_value
      from private.library_chunks c
      join private.library_sources s on s.id = c.source_id
      where c.fts @@ text_query
        and (region_filter is null or s.region && region_filter)
        and (topic_filter is null or s.topics && topic_filter)
      order by rank_value desc, c.id
      limit candidate_limit
    ) t;
  end if;

  -- Always an exact scan, never the HNSW index. An index scan returns the nearest vectors of every
  -- model and applies the model, region and topic filters afterwards, so vectors of an older
  -- model (kept until a re-embedding finishes) could fill the candidate list and leave too few,
  -- or not the nearest, rows. The offset 0 keeps the filters ahead of the ordering. The library
  -- is a few hundred chunks (a few thousand at most), so the scan costs milliseconds; the index
  -- stays for search_library_v2.
  if query_embedding is not null then
    select coalesce(array_agg(v.id order by v.distance, v.id), '{}') into vector_ids
    from (
      select m.id, m.embedding operator(extensions.<=>) query_embedding as distance
      from (
        select c.id, c.embedding
        from private.library_chunks c
        join private.library_sources s on s.id = c.source_id
        where c.embedding is not null and c.embedding_model = query_embedding_model
          and (region_filter is null or s.region && region_filter)
          and (topic_filter is null or s.topics && topic_filter)
        offset 0
      ) m
      order by distance, m.id
      limit candidate_limit
    ) v;
  end if;

  return query
  with text_hits as (
    select h.id, h.list_rank from unnest(text_ids) with ordinality as h(id, list_rank)
  ), vector_hits as (
    select h.id, h.list_rank from unnest(vector_ids) with ordinality as h(id, list_rank)
  ), fused as (
    select
      coalesce(t.id, v.id) as id,
      coalesce(1 / (rrf_k + t.list_rank), 0) + coalesce(1 / (rrf_k + v.list_rank), 0) as fused_score,
      least(t.list_rank, v.list_rank) as best_rank
    from text_hits t
    full join vector_hits v on v.id = t.id
  ), placed as (
    select
      c.id as chunk_ref,
      s.id as source_ref,
      s.manifest_key as key_ref,
      s.title as title_ref,
      s.year as year_ref,
      s.url as url_ref,
      c.section as section_ref,
      c.body as body_ref,
      c.header as header_ref,
      s.evidence_level as evidence_ref,
      s.kind as kind_ref,
      f.fused_score,
      f.best_rank,
      case
        when query_embedding is not null and c.embedding is not null
          and c.embedding_model = query_embedding_model
        then (c.embedding operator(extensions.<=>) query_embedding)::double precision
      end as distance_ref,
      case
        when text_query is null then null
        when c.fts @@ text_query then ts_rank(c.fts, text_query, 1)::double precision
        else 0
      end as rank_ref,
      row_number() over (
        partition by s.id order by f.fused_score desc, f.best_rank, c.id
      ) as source_place
    from fused f
    join private.library_chunks c on c.id = f.id
    join private.library_sources s on s.id = c.source_id
  )
  select
    3,
    p.chunk_ref,
    p.source_ref,
    p.key_ref,
    p.title_ref,
    p.year_ref,
    p.url_ref,
    p.section_ref,
    p.body_ref,
    p.header_ref,
    p.evidence_ref,
    p.kind_ref,
    p.fused_score,
    p.distance_ref,
    p.rank_ref,
    current_version
  from placed p
  where p.source_place <= per_source_limit
  order by p.fused_score desc, p.best_rank, p.chunk_ref
  limit result_limit;
end
$$;

revoke all on function public.search_library_v3(text, public.library_embedding, text, integer, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.search_library_v3(text, public.library_embedding, text, integer, jsonb, uuid)
  to service_role;
