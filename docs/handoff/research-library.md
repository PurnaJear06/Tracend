# Research Library Handoff

**As of:** 2026-10-15

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

A hybrid (full-text plus gte-small vector) research library behind Coach answers and plan explanations. Rules still decide every number.

## Chunks

E1 (Phase 1); E2, E3 (Phase 3); E4, E5 (Phase 4)

## State

**E1 (in review, branch `claude/e1-library-tables`).** Migration
`20261015150041_research_library.sql`:

- `create extension if not exists vector with schema extensions`.
- `private.library_sources`, `private.library_chunks` (`embedding extensions.vector(384)`, nullable
  until embedded; generated stored `fts`; HNSW cosine and GIN indexes; unique
  `(source_id, ordinal)`), `private.library_ingest_runs`. Forced RLS, no policies, all privileges
  revoked from `public`, `anon`, `authenticated` and `service_role` (same as the waitlist tables):
  E2 writes through its own service-role functions.
- `public.search_library_v1(query_text, query_embedding, match_count, filters)` per Contract 6,
  service role only. Field list and rules: `docs/DATA_MODEL.md` section 12. Each row carries
  `schema_version` 1 next to the contract keys (a row set, not a jsonb wrapper, so supabase-js
  `rpc()` returns an array of chunks).
- pgTAP: `supabase/tests/database/research_library_test.sql` (access, grants, indexes, ranking on a
  seeded fixture with hand-made 384-dimension vectors, filters, clamps, both single-search paths).
- Docs: decision D3 replaces the "no vector databases" rule in `CLAUDE.md`, `ARCHITECTURE.md`
  (section 11) and `IMPLEMENTATION_ROADMAP.md`; tables in `DATA_MODEL.md`; classification, export
  and deletion notes in `SECURITY_PRIVACY.md`.
- Restore drill: no change needed. `vector` lives in `extensions`, which the drill keeps; the
  isolated database gets it from the migrations and the dump's `CREATE EXTENSION IF NOT EXISTS`
  line is a no-op, so the `private` schema it recreates restores `extensions.vector` columns and
  the HNSW index as is. pg_dump leaves the generated `fts` column out of COPY.
- Spike: the local stack did not start (Colima VZ boot hang, 2026-10-15), so `create extension
  vector` was proven by CI pgTAP on the pinned CLI (2.101.0) and the `gte-small` Edge Function
  call was not run locally. E2 must confirm `new Supabase.ai.Session("gte-small")` returns 384
  numbers with `mean_pool: true, normalize: true` before ingesting.

Conventions for E2 to keep: tag sources that apply everywhere with `global` in `region` (filters
match by overlap, so a regional caller passes for example `["global", "IN"]`); always set
`licence`; write a context header (source and section) per chunk, because it is embedded and
searched with the body.

## Next agent starts here

E2 (ingestion and the first 30 sources) once E1 merges: add service-role write functions for the
library (upsert a source by `manifest_key` and replace its chunks, record an ingest run), then the
ingestion Edge Function or script using `gte-small` inside an Edge Function.
