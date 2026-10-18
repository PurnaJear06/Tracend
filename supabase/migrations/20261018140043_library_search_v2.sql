-- Research library search, version 2 (coaching platform program, chunk E3) ----------------

-- Coach chat retrieves from the library on every turn, so the search gets the fixes the Coach
-- design called for (docs/plans/coaching-platform-2026-10/README.md, "Retrieval, just enough"):
--
--   1. Full-text search ORs the terms of the question. v1 used websearch_to_tsquery, which ANDs
--      every word: a whole question like "How much protein should I eat to build muscle?" rarely
--      matched a chunk, so the hybrid was effectively the vector search alone (E2 measured full-text
--      recall 0.20 against 0.94 for vectors). Terms are lower-cased words of letters and digits;
--      the English configuration drops stop words and stems the rest, as the stored column does.
--   2. Reciprocal rank fusion with k = 50 (v1 used 60).
--   3. The athlete's region. Pass target_user_id and the search shows global sources plus the
--      sources for the athlete's country: the country in the account locale ('en-IN' is IN) and
--      IN for the Asia/Kolkata time zone, because the app stores no country yet. An explicit
--      `region` filter overrides it. A source tagged IN reaches only athletes in India.
--   4. No source supplies more than three of the rows, so a multi-topic question is not filled by
--      one paper's chunks.
--   5. Rows carry source_key, the stable manifest key. Coach cites sources by that key; the
--      random source_id differs in every database.
--   6. match_count is clamped to 1..10 (v1: 1..8); null still means 8.
--
--   7. Coach chat embeds the question by calling library-embed, which is the only place gte-small
--      loads. The call is gated like the cron job's, with the library worker secret, so the service
--      role may read that one secret (library_worker_secret_v1). The service role can already read
--      every row and call every function; the secret opens nothing but the embedding function.
--
-- Nothing else in the repository calls search_library_v1 (the retrieval evaluation moves to v2
-- with this change, and the deployed Edge Functions never called it), so it is dropped here.
-- Additive for every caller that exists.

-- The regions an athlete's account maps to: always 'global', plus the country in the locale
-- ('en-IN', 'en_GB') and 'IN' for an Indian time zone. A missing account is just 'global'.
create function private.library_regions_for_account(target_user_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select array(
        select distinct r.region
        from unnest(array[
          'global',
          upper(substring(a.locale from '[-_]([A-Za-z]{2})$')),
          case when a.timezone in ('Asia/Kolkata', 'Asia/Calcutta') then 'IN' end
        ]) as r(region)
        where r.region is not null
      )
      from public.user_accounts a
      where a.id = target_user_id
    ),
    array['global']
  )
$$;
revoke all on function private.library_regions_for_account(uuid)
  from public, anon, authenticated, service_role;

-- Contract 6, version 2. Hybrid search: the 30 best full-text matches (terms ORed, ranked by
-- ts_rank) and the 30 nearest embeddings (cosine distance), merged by reciprocal rank fusion
-- with k = 50. A chunk found by both lists outranks one found by either alone.
--
--   query_text       free text, first 1000 characters used; null, blank or stop words only skips
--                    full-text search
--   query_embedding  gte-small vector of 384 dimensions (other sizes raise 22000); null skips
--                    vector search
--   match_count      clamped to 1..10; null means 8
--   filters          null or an object with optional `region` and `topics` text arrays. A source
--                    matches when its array overlaps the filter. An absent, null or empty array
--                    does not filter. Other keys are refused.
--   target_user_id   when set and filters has no region, the sources are limited to the athlete's
--                    regions (private.library_regions_for_account)
--
-- Returns at most match_count rows, best first, at most three per source, each with
-- schema_version 2. No query (both inputs skipped) returns no rows.
--
-- Without filters the nearest embeddings come from the HNSW index. With a filter they are ranked
-- exactly over the matching sources' chunks: an HNSW scan stops after ef_search (40) candidates,
-- and a narrow filter could leave almost none of them. The library is small (open sources only),
-- so the exact ranking stays cheap.
create function public.search_library_v2(
  query_text text,
  query_embedding public.library_embedding,
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
  score double precision
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
    select coalesce(array_agg(t.id order by t.text_rank desc, t.id), '{}') into text_ids
    from (
      select c.id, ts_rank(c.fts, text_query, 1) as text_rank
      from private.library_chunks c
      join private.library_sources s on s.id = c.source_id
      where c.fts @@ text_query
        and (region_filter is null or s.region && region_filter)
        and (topic_filter is null or s.topics && topic_filter)
      order by text_rank desc, c.id
      limit candidate_limit
    ) t;
  end if;

  if query_embedding is not null and region_filter is null and topic_filter is null then
    select coalesce(array_agg(v.id order by v.distance, v.id), '{}') into vector_ids
    from (
      select c.id, c.embedding operator(extensions.<=>) query_embedding as distance
      from private.library_chunks c
      where c.embedding is not null
      order by distance
      limit candidate_limit
    ) v;
  elsif query_embedding is not null then
    select coalesce(array_agg(v.id order by v.distance, v.id), '{}') into vector_ids
    from (
      select m.id, m.embedding operator(extensions.<=>) query_embedding as distance
      from (
        select c.id, c.embedding
        from private.library_chunks c
        join private.library_sources s on s.id = c.source_id
        where c.embedding is not null
          and (region_filter is null or s.region && region_filter)
          and (topic_filter is null or s.topics && topic_filter)
        offset 0 -- keeps the filter ahead of the ordering: exact, not an index scan
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
      f.fused_score,
      f.best_rank,
      row_number() over (
        partition by s.id order by f.fused_score desc, f.best_rank, c.id
      ) as source_place
    from fused f
    join private.library_chunks c on c.id = f.id
    join private.library_sources s on s.id = c.source_id
  )
  select
    2,
    p.chunk_ref,
    p.source_ref,
    p.key_ref,
    p.title_ref,
    p.year_ref,
    p.url_ref,
    p.section_ref,
    p.body_ref,
    p.header_ref,
    p.fused_score
  from placed p
  where p.source_place <= per_source_limit
  order by p.fused_score desc, p.best_rank, p.chunk_ref
  limit result_limit;
end
$$;

revoke all on function public.search_library_v2(text, public.library_embedding, integer, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.search_library_v2(text, public.library_embedding, integer, jsonb, uuid)
  to service_role;

drop function public.search_library_v1(text, public.library_embedding, integer, jsonb);

-- The library worker secret, for the Edge Functions that call library-embed (Coach chat). It is
-- created in Vault on first use, as for the cron job, and never leaves the service role.
create function public.library_worker_secret_v1()
returns text
language sql
security definer
set search_path = ''
as $$
  select private.library_worker_secret()
$$;
revoke all on function public.library_worker_secret_v1() from public, anon, authenticated;
grant execute on function public.library_worker_secret_v1() to service_role;
