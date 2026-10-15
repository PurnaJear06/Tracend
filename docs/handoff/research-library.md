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
  `rpc()` returns an array of chunks). `query_embedding` is the domain `public.library_embedding`
  over `extensions.vector(384)`: `supabase db dump` drops GRANT/REVOKE lines that mention the
  `extensions` schema, so a plain vector parameter came back from a restore executable by `anon`
  and `authenticated` (seen in the local drill). Callers still pass a JSON number array.
  Unfiltered vector search uses HNSW; filtered vector search ranks exactly over the matching
  sources (an HNSW scan stops at `ef_search` 40 and a narrow filter could empty it).
- Review fixes (lead, 2026-10-15): Contract 6 v1.1 accepted (the domain); `region` has no
  default and needs at least one entry, each `global` or an ISO alpha-2 code
  (`private.library_regions_valid`); `library_chunks.embedding_model` is set exactly when
  `embedding` is; the search uses the first 1000 characters of `query_text` and treats a
  negation-only query (`-creatine`) like an empty one.
- pgTAP: `supabase/tests/database/research_library_test.sql`, 66 assertions (access, grants,
  indexes, ranking on a seeded fixture with hand-made 384-dimension vectors, filters, clamps, both
  single-search paths, wrong dimensions, query limits, region and model constraints, cascade, and
  the repo-wide dump-safe signature rule in `docs/DATA_MODEL.md` section 12).
- Docs: decision D3 replaces the "no vector databases" rule in `CLAUDE.md`, `AGENTS.md`,
  `ARCHITECTURE.md` (section 11) and `IMPLEMENTATION_ROADMAP.md`, with matching lines in
  `AI_SAFETY_SPEC.md` section 15 and `PRD.md`; tables in `DATA_MODEL.md`; classification, export
  and deletion notes in `SECURITY_PRIVACY.md`.
- Restore drill: no change needed, run locally on 2026-10-15 with the deploy job's exact
  statements on 5,000 embedded chunks. The dump creates `vector` (`CREATE EXTENSION IF NOT EXISTS
  ... WITH SCHEMA "extensions"`) before any table; the isolated database already has it from the
  migrations; the recreated `private` tables, HNSW index, forced RLS and service-role-only grant
  all came back, and pg_dump leaves the generated `fts` column out of COPY. A function-level
  `SET hnsw.*` setting was tried and dropped: the schema restore failed on it ("permission denied
  to set parameter"), because the vector library is not loaded in the restoring session.
- Spike (local stack, 2026-10-15): Supabase CLI 2.101.0, Postgres 17.6, pgvector 0.8.0, edge
  runtime 1.73.13. `new Supabase.ai.Session("gte-small")` with `mean_pool: true, normalize: true`
  returned 384 numbers with norm 1.0; first call 16.3 s (model download and load), then about
  70 ms per call. A real embedding passed through local PostgREST (`rpc`) as a JSON array
  returned rows; the anon key got `42501`. Local `functions serve` cannot see a worktree on the
  external SSD (empty bind mount in the Colima VM), so the spike file was written into the VM
  path; nothing was committed.
- Local Postgres quirk found while testing (not caused by this chunk): a session that connects as
  `postgres` or `supabase_admin`, runs `SET ROLE anon` (or `authenticated`, `service_role`) and
  then calls a function it may not execute crashes the backend (signal 11; reproduced with
  `waitlist_confirm`). Connecting as `authenticator` (the PostgREST path) gets a clean `42501`.
  pgTAP tests must therefore check function grants with `has_function_privilege`, never by
  calling the function under `SET ROLE`.

Conventions for E2 to keep (region convention accepted by the lead): tag sources that apply
everywhere with `global` in `region` (filters match by overlap, so a regional caller passes for
example `["global", "IN"]`); always set `licence`; set `embedding_model` (`gte-small`) with every
embedding; write a context header (source and section) per chunk, because it is embedded and
searched with the body.

Scale note: the filtered vector path ranks every chunk of the matching sources exactly (about
2 ms at 5,000 chunks). Past roughly 50,000 chunks, switch it to an HNSW scan with a runtime
`set_config('hnsw.iterative_scan', 'relaxed_order', true)` inside the function (never a
function-level `SET`, which breaks the restore drill), or denormalise `region` and `topics` onto
the chunks.

## Next agent starts here

E2 (ingestion and the first 30 sources) once E1 merges: add service-role write functions for the
library (upsert a source by `manifest_key` and replace its chunks, record an ingest run), then the
ingestion Edge Function or script using `gte-small` inside an Edge Function.
