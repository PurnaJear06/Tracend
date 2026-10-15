-- Research library (coaching platform program, chunk E1) --------------------------------

-- Open papers, guidelines, position stands and in-house summaries in our own words, split
-- into chunks for Coach answers and plan explanations (decision D3). No user data lives
-- here. Rules still decide every number; the library only grounds wording.
--
-- Embeddings are Supabase's built-in gte-small (384 dimensions, mean-pooled, normalised),
-- computed inside Edge Functions (decision D4). Search is hybrid: Postgres full-text plus
-- cosine distance, merged by reciprocal rank fusion.
--
-- The tables sit in `private`, which the Data API does not expose. No API role reads or
-- writes them; Edge Functions reach the library through service-role functions only.

create extension if not exists vector with schema extensions;

create table private.library_sources (
  id uuid primary key default gen_random_uuid(),
  -- Stable key from the ingestion manifest; re-ingesting a source replaces it by this key.
  manifest_key text not null unique check (manifest_key ~ '^[a-z0-9][a-z0-9_.-]{0,119}$'),
  title text not null check (length(btrim(title)) between 1 and 500),
  authors text[] not null default '{}',
  year smallint check (year between 1900 and 2100),
  doi text check (length(doi) between 3 and 200),
  url text check (url ~ '^https://' and length(url) <= 2000),
  -- Every source records the licence it is stored under; paid course material is never stored.
  licence text not null check (length(btrim(licence)) between 1 and 200),
  -- Regions the source applies to (for example 'global', 'IN', 'US', 'UK', 'AU') and its topics.
  region text[] not null default '{}',
  topics text[] not null default '{}',
  evidence_level text check (length(btrim(evidence_level)) between 1 and 100),
  kind text not null check (kind in ('paper', 'guideline', 'position_stand', 'summary')),
  created_at timestamptz not null default now()
);

create table private.library_chunks (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references private.library_sources(id) on delete cascade,
  ordinal integer not null check (ordinal >= 0),
  section text check (length(section) <= 300),
  -- Context header written at ingestion (source and section in a line), embedded and
  -- searched with the body so a chunk stands on its own.
  header text not null default '' check (length(header) <= 1000),
  body text not null check (length(btrim(body)) between 1 and 8000),
  token_count integer not null check (token_count between 1 and 2000),
  -- Null until embedded; a chunk without an embedding is still found by full-text search.
  embedding extensions.vector(384),
  fts tsvector generated always as (
    to_tsvector('english', coalesce(header, '') || ' ' || body)
  ) stored,
  created_at timestamptz not null default now(),
  unique (source_id, ordinal)
);
-- The unique (source_id, ordinal) index also serves lookups and cascades by source_id.
create index library_chunks_embedding_hnsw on private.library_chunks
  using hnsw (embedding extensions.vector_cosine_ops);
create index library_chunks_fts on private.library_chunks using gin (fts);

create table private.library_ingest_runs (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running' check (status in ('running', 'succeeded', 'failed')),
  source_count integer not null default 0 check (source_count >= 0),
  chunk_count integer not null default 0 check (chunk_count >= 0),
  error text check (length(error) <= 2000),
  check ((status = 'running') = (finished_at is null)),
  check (finished_at is null or finished_at >= started_at)
);

alter table private.library_sources enable row level security;
alter table private.library_sources force row level security;
alter table private.library_chunks enable row level security;
alter table private.library_chunks force row level security;
alter table private.library_ingest_runs enable row level security;
alter table private.library_ingest_runs force row level security;

revoke all on private.library_sources from public, anon, authenticated, service_role;
revoke all on private.library_chunks from public, anon, authenticated, service_role;
revoke all on private.library_ingest_runs from public, anon, authenticated, service_role;

-- Search ---------------------------------------------------------------------------------

-- Contract 6. Hybrid search: the 30 best full-text matches (websearch syntax, ranked by
-- ts_rank_cd) and the 30 nearest embeddings (cosine distance), merged by reciprocal rank
-- fusion with k = 60. A chunk found by both lists outranks one found by either alone.
--
--   query_text       free text; null or blank skips full-text search
--   query_embedding  gte-small vector of 384 dimensions; null skips vector search
--   match_count      clamped to 1..8; null means 8
--   filters          null or an object with optional `region` and `topics` text arrays.
--                    A source matches when its array overlaps the filter. An absent, null
--                    or empty array does not filter. Other keys are refused.
--
-- Returns at most match_count rows, best first, each with schema_version 1. No query
-- (both inputs skipped) returns no rows.
create function public.search_library_v1(
  query_text text,
  query_embedding extensions.vector(384),
  match_count integer,
  filters jsonb
)
returns table (
  schema_version integer,
  chunk_id uuid,
  source_id uuid,
  title text,
  year smallint,
  url text,
  section text,
  body text,
  header text,
  score double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  result_limit constant integer := least(greatest(coalesce(match_count, 8), 1), 8);
  candidate_limit constant integer := 30;
  rrf_k constant double precision := 60;
  text_query tsquery;
  region_filter text[];
  topic_filter text[];
  filter_key text;
begin
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

  if query_embedding is not null and extensions.vector_dims(query_embedding) <> 384 then
    raise exception 'query_embedding must have 384 dimensions' using errcode = '22023';
  end if;

  if length(btrim(coalesce(query_text, ''))) > 0 then
    text_query := websearch_to_tsquery('english', query_text);
    -- Only stop words: nothing to match.
    if numnode(text_query) = 0 then
      text_query := null;
    end if;
  end if;

  return query
  with text_candidates as (
    select c.id, ts_rank_cd(c.fts, text_query) as text_rank
    from private.library_chunks c
    join private.library_sources s on s.id = c.source_id
    where text_query is not null
      and c.fts @@ text_query
      and (region_filter is null or s.region && region_filter)
      and (topic_filter is null or s.topics && topic_filter)
    order by text_rank desc, c.id
    limit candidate_limit
  ), text_hits as (
    select t.id, row_number() over (order by t.text_rank desc, t.id) as list_rank
    from text_candidates t
  ), vector_candidates as (
    select c.id, c.embedding operator(extensions.<=>) query_embedding as distance
    from private.library_chunks c
    join private.library_sources s on s.id = c.source_id
    where query_embedding is not null
      and c.embedding is not null
      and (region_filter is null or s.region && region_filter)
      and (topic_filter is null or s.topics && topic_filter)
    order by distance
    limit candidate_limit
  ), vector_hits as (
    select v.id, row_number() over (order by v.distance, v.id) as list_rank
    from vector_candidates v
  ), fused as (
    select
      coalesce(t.id, v.id) as id,
      coalesce(1 / (rrf_k + t.list_rank), 0) + coalesce(1 / (rrf_k + v.list_rank), 0) as fused_score,
      least(t.list_rank, v.list_rank) as best_rank
    from text_hits t
    full join vector_hits v on v.id = t.id
  )
  select
    1,
    c.id,
    s.id,
    s.title,
    s.year,
    s.url,
    c.section,
    c.body,
    c.header,
    f.fused_score
  from fused f
  join private.library_chunks c on c.id = f.id
  join private.library_sources s on s.id = c.source_id
  order by f.fused_score desc, f.best_rank, c.id
  limit result_limit;
end
$$;

revoke all on function public.search_library_v1(text, extensions.vector, integer, jsonb)
  from public, anon, authenticated;
grant execute on function public.search_library_v1(text, extensions.vector, integer, jsonb)
  to service_role;
