# Research Library Handoff

**As of:** 2026-10-24

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

A hybrid (full-text plus gte-small vector) research library behind Coach answers and plan explanations. Rules still decide every number.

## Chunks

E1 (Phase 1); E2, E3 (Phase 3); E4, E5 (Phase 4)

E2 (Phase 3, round 2) merged (#135); E2.1, its follow-up with 14 more sources, is merged; E2.2 (57 more sources and machine-readable licences, 106 in all) is merged (#152). E3 (the library in every Coach reply) is merged (#150). E3.1, the engine's production pass (relevance floor, latency, telemetry, versioning), is in review. E4 (regional modules and the athlete's country, 114 sources) is in review (branch `claude/regional-modules`). E5 (plan explanations that cite sources, in Coach chat and in the onboarding plan) is in review (branch `claude/e5-plan-explanations`). See the sections below.

## State

**E1 (live, #109).** Migration
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

## E2: knowledge base, part 1 (in review)

Migration `20261017150842_library_content.sql` (code 42), the `library-embed` Edge Function,
35 sources in `supabase/library/`, a retrieval test set, and a coaching-principles digest.

### What shipped

- **Content as files.** `supabase/library/sources/*.ts` holds one object per source (metadata,
  licence, region, topics, why it was chosen, and a summary in our own words in titled sections);
  `supabase/library/index.ts` lists them. The type is `_shared/library/types.ts`. TypeScript modules
  (not Markdown) so tests import the content as modules. The one test that reads files,
  `library_content_test.ts` (it compares each source with the newest migration that loads it), needs
  `--allow-read=supabase/migrations`, which the CI deno step and `pre-deploy.sh` both grant
  (`--allow-read=supabase/migrations,site/src/config.ts`).
- **Chunking.** `_shared/library/chunk.ts`: split on blank lines, at most 1400 characters a chunk
  (about 350 tokens, inside gte-small's 512-token window), header
  `Source: <label>, <title>. Section: <section>.` on every chunk. 35 sources become 122 chunks.
- **Loading.** The migration defines `private.library_replace_source(source, chunks)` (upsert by
  `manifest_key`; chunks replaced only if their text changed, so reloading keeps valid embeddings),
  then 35 generated blocks (`-- library-source: <key> sha256:<digest>`) call it. Chunks load with
  null embeddings, so full-text search works at once.
- **Embedding.** The `library-embed` Edge Function fills missing embeddings with
  `new Supabase.ai.Session("gte-small")` (`mean_pool`, `normalize`, 384 numbers, checked) and sets
  `embedding_model = 'gte-small'`. A pg_cron job (`tracend-library-embed`, every minute) calls
  `private.library_embed_kick()`, which does nothing when no chunk lacks an embedding and otherwise
  posts to the function through `pg_net`. The target URL is not in the migration: it is the Vault
  secret `library_embed_url`, set by `private.library_set_embed_url(url)` (execute granted to
  `service_role` only; it accepts just `https://<20 lowercase letters>.supabase.co/functions/v1/library-embed`
  and creates or updates the secret). Until that secret exists the kick sends nothing, so a local or CI
  database never posts to production. The bearer secret is generated by the database in Vault
  (`private.library_worker_secret()` creates it on first use, so a restore heals itself); the function
  checks it with the service-role `library_worker_authorized_v1`. No Edge secret and no GitHub secret; the only deploy step is setting the URL (below). Migrations run before functions deploy, so early ticks get a 404 and later ones
  succeed. Idempotent: pending chunks are read, and embeddings are written only where none exists,
  so a second run or two runs at once are harmless. Each run writes a `library_ingest_runs` row.
- **Edge CPU limit (found while testing).** The local edge runtime killed requests at about 1.1 s
  (soft) and 2.1 s (hard) of CPU, after roughly 17 chunk embeddings. So one request embeds for at
  most 800 ms (`embedBudgetMs`), about 11 chunks, then returns; cron calls again the next minute.
  122 chunks take about 11 minutes after the deploy. If hosted CPU turns out slower than local, the
  worker simply embeds fewer per call; check `library_status_v1()` and `library_ingest_runs` after
  the deploy (below).
- **Updating content later.** Edit or add a file under `supabase/library/sources/`, then run
  `./scripts/deno.sh run --allow-read supabase/functions/_shared/library/build_migration.ts --only key1,key2`
  and paste the output into a new migration (it needs nothing else: the loader exists). The deno
  test `library_content_test.ts` fails if a content file differs from the newest migration that loads
  it. Changed chunks are re-embedded by the same cron job. To re-embed everything with another model,
  a migration sets `embedding = null, embedding_model = null` on the chunks.
- **Failed chunks.** The worker records each chunk that fails to embed
  (`library_record_embed_failures_v1`) and leaves it out of the rest of that run, so one bad chunk
  cannot block the others. `private.library_chunks.embed_attempts` counts failed attempts; at 5,
  `library_pending_chunks_v1` stops offering the chunk and `library_embed_kick` stops waking cron for
  it (it posts nothing when every waiting chunk is at 5). Sentry gets one event, and the function
  one log line, when a chunk is given up on, never one a minute. A batch where every chunk fails ends
  the run without marking the rest, since the model is probably down; but a long outage still uses up
  attempts on the first chunks each minute. To retry given-up chunks, a migration or the SQL editor
  runs `update private.library_chunks set embed_attempts = 0, embed_failed_at = null where embedding is null`.
- **Local runs** send nothing: with no `library_embed_url` secret the kick returns at once, so the
  local cron job is inert. To embed locally, call the function by hand (see "How to run it").
- `library-embed` also accepts `{"texts": [..]}` (at most 8 short texts, same secret) and returns
  their embeddings; the retrieval evaluation uses it because gte-small only runs in the Supabase
  runtime.

### Contract requests (lead only: files outside E2's ownership)

1. `supabase/config.toml`, after `[functions.meal-media-retention]`:
   ```toml
   [functions.library-embed]
   # Cron authenticates with a secret the database keeps in Vault; the function checks it. It never
   # accepts a user session.
   verify_jwt = false
   ```
   Without it the gateway rejects the cron call (a non-JWT bearer) and nothing is ever embedded.
2. `.github/workflows/deploy.yml` and `hotfix.yml`: add `library-embed` to the function matrix
   (alphabetical, after `health-sync`). `verify-live-function.sh --all` picks it up from the folder.
   Both workflows must also, after the migrations apply (and again after any restore, since Vault is
   not restored), run on the production database:
   `select private.library_set_embed_url('https://qsfzzsjenopqqqhvpyaw.supabase.co/functions/v1/library-embed');`
   It is idempotent. Without it the cron job stays inert and nothing is embedded. It needs a direct SQL
   connection (the database owner); `private` is not exposed to the Data API.
3. After the first deploy, check (dashboard SQL editor, read-only):
   `select public.library_status_v1();` should reach `embedded_chunks = chunks` (122) in about ten
   minutes, and `select * from private.library_ingest_runs order by started_at desc;` shows the runs.
   If nothing embeds, look at the function's logs for the CPU limit and lower `defaultEmbedOptions`.

### Retrieval test set and recall

`supabase/functions/_evals/library_questions.json`: 42 realistic questions (no athlete data), each
with the one to three sources a good answer needs; `library_eval.ts` embeds the questions with the
real gte-small model, runs the real `search_library_v1` (top 8) and scores recall, for hybrid,
full-text-only and vector-only searches.

Measured 2026-10-17 on the local stack (Supabase CLI 2.101.0, edge runtime 1.73.13, real gte-small,
all 122 chunks embedded by `library-embed`):

| Search | Mean recall in top 8 | All expected sources found | At least one found |
|---|---|---|---|
| Hybrid (`search_library_v1`) | **0.929** | 90% | 95% |
| Vector only | 0.940 | 93% | 95% |
| Full-text only | 0.202 | 17% | 24% |

Hybrid misses: `freq_hypertrophy` (Pelland 2026), `see_doctor` (PAR-Q+), `strength_per_week` (WHO
2020 and ACSM 2011) and `tempo` (ACSM 2026). The question set was written before measuring and not
tuned. E3's gate (recall of the expected sources in the top 8) is met at 0.8; E3 still has to check
citations against retrieved chunks and the no-unsupported-claim eval.

**Finding for E3 (E1's function, not changed here).** Full-text search is nearly useless for whole
questions: `websearch_to_tsquery` ANDs every word, so a question like "How much protein should I eat
per day to build muscle?" rarely matches any chunk, and the hybrid is effectively the vector search
(hybrid 0.929 against vector-only 0.940; the fusion adds nothing). Options: E3 passes a keyword-only
`query_text` (nouns from the question, or an OR query), or a later migration changes the function to
OR the terms. Re-run the evaluation after either.

How to run it (local stack; `functions serve` cannot see a worktree on the external SSD, so copy the
function folders into the Colima VM at the same path, as the E1 spike did):

```sh
./scripts/container.sh start && ./scripts/supabase.sh start && ./scripts/supabase.sh db reset
D="$PWD"; COPYFILE_DISABLE=1 tar -cf - supabase/functions/library-embed supabase/functions/_shared/library \
  supabase/functions/_shared/sentry.ts | ./scripts/container.sh ssh -- sh -c "sudo mkdir -p '$D' && cd '$D' && sudo tar -xf -"
./scripts/supabase.sh functions serve --no-verify-jwt &
SECRET=$(./scripts/docker.sh exec supabase_db_Tracend psql -U postgres -tA -c "select private.library_worker_secret()")
# call library-embed with the secret until embedded_chunks = chunks (about 11 calls; the local cron job is inert without a `library_embed_url` secret)
curl -X POST http://127.0.0.1:54321/functions/v1/library-embed -H "Authorization: Bearer $SECRET" -d '{}'
EVAL_SERVICE_KEY=$(./scripts/supabase.sh status -o env | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"/\1/p') EVAL_WORKER_SECRET="$SECRET" \
  ./scripts/deno.sh run --allow-env --allow-net --allow-read=supabase/functions/_evals supabase/functions/_evals/library_eval.ts
```

(Colima was stopped between tool calls while I worked, probably by another agent's cleanup; run the
steps in one command if that happens.)

### Coaching principles digest (owner request, 2026-10-17)

`supabase/library/coaching_principles.ts` is a fixed, deterministic text (6,007 characters in version 1;
7,024 in version 2, see E2.1; about 1,500 to 1,800 tokens, in our own words, no athlete data) with source ids inline in square brackets:
training (volume, frequency, loads, effort, rest, progression, deloads, cardio with lifting), cardio
and activity, nutrition, recovery and sleep, screening and safety, and how a good coach
communicates (individualise, honest about missing data and evidence strength, never diagnose, no
supplements pushed). `_shared/library/principles.ts` exports `coachingPrinciples` (`version`, `text`),
`citedSourceKeys(text)` and `coachingPrinciplesContributor`, a Contract 7 contributor with
`id: "coaching_principles"`, `slot: "stable"`, `budgetChars: 7200`, whose `render` returns the same
text for every question. A9 registered it first in `coach_context/registry.ts` (it was not
registered when E2 shipped). Any edit to the text changes the cached prefix, so bump
`coachingPrinciplesVersion`. Tests (`principles_test.ts`): every cited id exists in the source list;
the digest stays between 4,800 and 7,200 characters (1,200 to 1,800 tokens at four characters a
token; real tokenisation of the bracketed ids runs higher, so E3 should count tokens with the
provider's tokenizer before registering); all six sections are present; no markup, dates or
addresses; the contributor passes `validateCoachContextContributors`. The host wraps it as reference
data, so the communication rules are phrased as guidance for explaining, not as instructions that
override Tracend's rules.

### The first 35 sources (for the owner's review; E2.1 adds 14 below)

Every entry was checked on 2026-10-17 against its Europe PMC and PubMed record (title, authors,
year, pages, DOI or PMCID, licence); the DOI is the one in that record. Nothing is copied: every
summary is in our own words, written from the abstract (Kreider 2017, Watson 2015 and Bredin 2013
also from the open full text), so a claim is limited to what that source says. No source's full text
is stored, including the CC BY ones, because a short own-words summary is what Coach can quote and
the NC/ND licences forbid copying. Licences are what each source is published under, from Europe
PMC/Crossref; "Publisher copyright" means no open licence was found, so only a summary and a link
are stored. 15 sources are CC BY, 3 CC BY-NC, 2 CC BY-NC-ND, 15 publisher copyright (as first recorded; E2.2 corrected Paluch 2022 to CC BY-NC-ND 4.0 and Helms 2014 to CC BY 2.0).

Areas: Training 14, Joint-friendly 3, Nutrition 9, Cardio and activity 4, Recovery and sleep 3,
Screening 2. Ten of B1's twelve external sources are reused (ACSM 2009, 2011, 2026; Schoenfeld 2017, 2021;
Iversen 2021; Pelland 2026; Singer 2024; Zourdos 2016; Robinson 2024). Baz-Valle 2022 and Helms
2016 are left out because Schoenfeld 2017, Pelland and Zourdos already cover them.

| Key | Area | Citation | DOI or link | Licence | Region | Topics | Why chosen |
|---|---|---|---|---|---|---|---|
| acsm_2009_progression | Training | ACSM 2009 | doi:10.1249/MSS.0b013e3181915670 | proprietary | global | training, strength, hypertrophy, progression, frequency, rest, intensity | The long-standing reference for how a lifter's training should progress with experience; Tracend's standard cites it, and Coach needs to explain where beginner and advanced advice differ. |
| acsm_2026_resistance_prescription | Training | Currier et al. 2026 (ACSM) | doi:10.1249/MSS.0000000000003897 | CC-BY-NC-ND-4.0 | global | training, strength, hypertrophy, volume, intensity, progression, frequency | The newest and broadest synthesis of what actually changes results in resistance training; it updates the 2009 stand and is the best single reference for the question 'what matters and what does not'. |
| schoenfeld_2017_weekly_volume | Training | Schoenfeld et al. 2017 | doi:10.1080/02640414.2016.1210197 | proprietary | global | training, hypertrophy, volume | The classic answer to 'how many sets per week?'; Tracend's volume ranges cite it, so Coach needs a plain explanation of the dose-response finding and its limits. |
| schoenfeld_2021_loading_continuum | Training | Schoenfeld et al. 2021 | doi:10.3390/sports9020032 | CC-BY-4.0 | global | training, strength, hypertrophy, intensity | Explains why a wide span of rep ranges works, which is the evidence behind letting people train with loads they enjoy and tolerate; Tracend's rep-range rules cite it. |
| pelland_2026_volume_frequency | Training | Pelland et al. 2026 | doi:10.1007/s40279-025-02344-w | proprietary | global | training, hypertrophy, strength, volume, frequency | The most recent and detailed analysis of weekly volume and frequency together, showing diminishing returns; it keeps Coach from overselling 'more sets'. |
| singer_2024_rest_intervals | Training | Singer et al. 2024 | doi:10.3389/fspor.2024.1429789 | CC-BY-4.0 | global | training, hypertrophy, rest, time-efficient | Gives a practical, evidence-based answer to 'how long should I rest between sets?', which matters for time-pressed users. |
| zourdos_2016_rir_scale | Training | Zourdos et al. 2016 | doi:10.1519/JSC.0000000000001049 | proprietary | global | training, intensity, rir, progression | The origin of the repetitions-in-reserve effort scale that Tracend's plans use; Coach needs to explain what 'reps in reserve' means and how reliable it is. |
| robinson_2024_proximity_to_failure | Training | Robinson et al. 2024 | doi:10.1007/s40279-024-02069-2 | proprietary | global | training, hypertrophy, strength, intensity, rir | The best available analysis of how close to failure to train, the basis for Tracend's reps-in-reserve targets. |
| iversen_2021_time_efficient | Training | Iversen et al. 2021 | doi:10.1007/s40279-021-01490-1 | CC-BY-4.0 | global | training, time-efficient, volume, strength, hypertrophy, frequency | Directly answers the most common barrier, lack of time, with concrete choices on exercises, sets, warm-ups and techniques that save minutes. |
| schoenfeld_2016_frequency_hypertrophy | Training | Schoenfeld et al. 2016 | doi:10.1007/s40279-016-0543-8 | proprietary | global | training, hypertrophy, frequency | The reason Coach can say each muscle is best trained at least twice a week when volume is equal, a core split-design rule. |
| grgic_2018_frequency_strength | Training | Grgic et al. 2018 | doi:10.1007/s40279-018-0872-x | proprietary | global | training, strength, frequency, volume | Shows that for strength the benefit of training more often comes mostly from the extra volume, helping Coach advise people with limited gym days. |
| bell_2023_deloading | Training | Bell et al. 2023 | doi:10.1186/s40798-023-00633-0 | CC-BY-4.0 | global | training, deload, recovery, progression | Deloading is widely used but lightly researched; this is the only structured consensus, so it lets Coach describe deloads honestly as expert practice. |
| lopez_2021_load_network | Training | Lopez et al. 2021 | doi:10.1249/MSS.0000000000002585 | CC-BY-NC-ND-4.0 | global | training, hypertrophy, strength, intensity, joint-friendly | Backs the advice that lighter loads still build muscle when taken to failure, important for people who need joint-friendlier training. |
| schumann_2022_concurrent_training | Training | Schumann et al. 2022 | doi:10.1007/s40279-021-01587-7 | CC-BY-4.0 | global | training, cardio, strength, hypertrophy, concurrent-training | Settles the common worry that cardio kills muscle gains, so Coach can advise people who want both. |
| schoenfeld_2020_range_of_motion | Joint-friendly | Schoenfeld and Grgic 2020 | doi:10.1177/2050312120901559 | CC-BY-NC-4.0 | global | training, hypertrophy, joint-friendly, exercise-selection | Answers whether partial range of motion is a fair swap when a full range bothers a joint, using the best controlled evidence available. |
| lauersen_2014_injury_prevention | Joint-friendly | Lauersen et al. 2014 | doi:10.1136/bjsports-2013-092538 | proprietary | global | injury-prevention, joint-friendly, strength, training | The strongest evidence that regular strength training itself lowers injury risk, which supports telling users that building strength protects joints. |
| gabbett_2016_training_load | Joint-friendly | Gabbett 2016 | doi:10.1136/bjsports-2015-095788 | CC-BY-NC-4.0 | global | injury-prevention, joint-friendly, training, progression, load-management | Explains why gradual load increases protect against injury and why too little training is also a risk, the logic behind Tracend's progression caps. |
| jager_2017_protein | Nutrition | Jäger et al. 2017 (ISSN) | doi:10.1186/s12970-017-0177-8 | CC-BY-4.0 | global | nutrition, protein, hypertrophy, body-composition, timing | The standard open position on daily protein for people who train; it grounds the protein targets Coach explains. |
| kerksick_2017_nutrient_timing | Nutrition | Kerksick et al. 2017 (ISSN) | doi:10.1186/s12970-017-0189-4 | CC-BY-4.0 | global | nutrition, timing, protein, carbohydrate, recovery | Answers the very common 'does meal timing matter?' with a clear order of priorities; useful for keeping advice proportionate. |
| schoenfeld_2018_protein_per_meal | Nutrition | Schoenfeld and Aragon 2018 | doi:10.1186/s12970-018-0215-1 | CC-BY-4.0 | global | nutrition, protein, timing, hypertrophy | Corrects the myth that the body can only use about 25 grams of protein per meal, so Coach can give sensible meal-by-meal protein advice. |
| morton_2018_protein_supplementation | Nutrition | Morton et al. 2018 | doi:10.1136/bjsports-2017-097608 | CC-BY-NC-4.0 | global | nutrition, protein, hypertrophy, strength, supplements | The key evidence for the point where more protein stops adding muscle (about 1.6 g/kg/day), which sets a sensible ceiling for the advice. |
| aragon_2017_diets_body_composition | Nutrition | Aragon et al. 2017 (ISSN) | doi:10.1186/s12970-017-0174-y | CC-BY-4.0 | global | nutrition, energy-balance, body-composition, protein, fat-loss | The best open statement on how energy balance and diet style change body composition, backing Tracend's focus on calories, protein and adherence over diet branding. |
| helms_2014_contest_prep | Nutrition | Helms et al. 2014 | doi:10.1186/1550-2783-11-20 | CC-BY-2.0 | global | nutrition, energy-balance, body-composition, protein, fat-loss, supplements | The most practical open source on the rate of weight loss and diet make-up when a lean person wants to lose fat and keep muscle. |
| kreider_2017_creatine | Nutrition | Kreider et al. 2017 (ISSN) | doi:10.1186/s12970-017-0173-z | CC-BY-4.0 | global | nutrition, creatine, supplements, strength, safety | Creatine is the best-supported training supplement; this open position stand covers both benefit and safety, which Coach needs for honest answers. |
| guest_2021_caffeine | Nutrition | Guest et al. 2021 (ISSN) | doi:10.1186/s12970-020-00383-4 | CC-BY-4.0 | global | nutrition, caffeine, supplements, performance, sleep | Gives dose and timing guidance for the most widely used performance aid, plus the sleep and anxiety trade-offs Coach should mention. |
| sawka_2007_fluid_replacement | Nutrition | Sawka et al. 2007 (ACSM) | doi:10.1249/mss.0b013e31802ca597 | proprietary | global | nutrition, hydration, performance, safety | The main professional position on drinking before, during and after exercise, with a practical way to measure personal needs. |
| acsm_2011_exercise_quantity | Cardio and activity | Garber et al. 2011 (ACSM) | doi:10.1249/MSS.0b013e318213fefb | proprietary | global | cardio, activity, strength, flexibility, training, guidelines | A complete weekly template covering cardio, strength, balance and flexibility, plus the point that something is better than nothing; Tracend's standard cites it. |
| who_2020_activity_guidelines | Cardio and activity | Bull et al. 2020 (WHO) | doi:10.1136/bjsports-2020-102955 | CC-BY-4.0 | global | cardio, activity, strength, sedentary, guidelines | The international reference on how much activity adults need, and the safest public baseline for any country; free to read. |
| piercy_2018_us_guidelines | Cardio and activity | Piercy et al. 2018 (US guidelines) | doi:10.1001/jama.2018.14854 | proprietary | US | cardio, activity, strength, guidelines | The national guideline Americans meet in practice; useful for US users and for the point that the least active people gain the most from small increases. |
| paluch_2022_daily_steps | Cardio and activity | Paluch et al. 2022 | doi:10.1016/S2468-2667(21)00302-9 | CC-BY-NC-ND-4.0 | global | activity, steps, cardio, health | Gives an evidence-based answer to 'do I really need 10,000 steps?', a question the app's step data raises daily. |
| watson_2015_sleep_duration | Recovery and sleep | Watson et al. 2015 (AASM and SRS) | doi:10.5665/sleep.4716 | proprietary | global | sleep, recovery, health, guidelines | The clearest professional statement on how much sleep adults need, the baseline for any recovery advice. |
| walsh_2021_sleep_athlete | Recovery and sleep | Walsh et al. 2021 | doi:10.1136/bjsports-2020-102025 | proprietary | global | sleep, recovery, performance, training | Covers sleep specifically for people who train: how common sleep problems are, what hurts performance and why one-size-fits-all targets are unwise. |
| dupuy_2018_recovery_techniques | Recovery and sleep | Dupuy et al. 2018 | doi:10.3389/fphys.2018.00403 | CC-BY-4.0 | global | recovery, soreness, training | Compares popular recovery methods on soreness and fatigue, so Coach can say which ones have evidence and which do not. |
| riebe_2015_screening | Screening | Riebe et al. 2015 (ACSM) | doi:10.1249/MSS.0000000000000664 | proprietary | global | screening, safety, health | The professional basis for deciding who should check with a doctor before starting or stepping up exercise, central to Tracend's safety gate. |
| bredin_2013_parq_plus | Screening | Bredin et al. 2013 | https://pmc.ncbi.nlm.nih.gov/articles/PMC3596208/ | proprietary | global | screening, safety, health | Describes the widely used PAR-Q+ readiness questionnaire and its risk tiers, matching how Tracend's screening decides between proceed, moderate and refer. |
| byrne_2018_matador | Energy balance | Byrne et al. 2018 (MATADOR) | doi:10.1038/ijo.2017.206 | CC-BY-NC-ND-4.0 | global | nutrition, energy-balance, fat-loss, diet-break, metabolic-adaptation | The best-known trial of planned breaks from dieting, so Coach can explain what a diet break is and what the evidence for it does and does not show. |
| peos_2021_icecap | Energy balance | Peos et al. 2021 (ICECAP) | doi:10.1249/mss.0000000000002636 | proprietary | global | nutrition, energy-balance, fat-loss, diet-break, training, hunger | The only trial of diet breaks in resistance-trained men and women, and it did not reproduce the extra fat loss seen in earlier work, which keeps Coach honest about breaks. |
| trexler_2014_metabolic_adaptation | Energy balance | Trexler et al. 2014 | doi:10.1186/1550-2783-11-7 | CC-BY-2.0 | global | nutrition, energy-balance, fat-loss, metabolic-adaptation, diet-break, weight-maintenance | Explains why fat loss slows and hunger rises on a long diet, the situation of anyone who has already lost a lot of weight and still wants to lose more. |
| mountjoy_2023_reds | Energy balance | Mountjoy et al. 2023 (IOC) | doi:10.1136/bjsports-2023-106994 | proprietary | global | nutrition, energy-balance, low-energy-availability, recovery, safety, fat-loss | The leading authority on the health risk of eating too little for the training done, which Coach needs for anyone cutting hard while training. |
| varkevisser_2019_weight_loss_maintenance | Energy balance | Varkevisser et al. 2019 | doi:10.1111/obr.12772 | CC-BY-NC-ND-4.0 | global | nutrition, weight-maintenance, fat-loss, behaviour-change, adherence | The most careful review of what predicts keeping weight off, which tells Coach where to put attention once someone has lost a lot of weight. |
| icmr_nin_2024_dietary_guidelines | Energy balance | ICMR-NIN 2024 | https://www.nin.res.in/dietaryguidelines/pdfjs/locale/DGI_2024.pdf | proprietary | IN | nutrition, protein, fat-loss, energy-balance, activity, guidelines, india | India's official food-based guidance, needed for users in India, and it differs from the sports-nutrition papers on BMI and protein powders in ways Coach must explain. |
| vella_2010_alcohol_recovery | Energy balance | Vella and Cameron-Smith 2010 | doi:10.3390/nu2080781 | CC-BY-3.0 | global | alcohol, recovery, nutrition, sleep, hydration, performance | A free review of what alcohol does to exercise performance and recovery, for the common question of whether drinking undoes training. |
| zhu_2024_motivational_interviewing | Behaviour change | Zhu et al. 2024 | doi:10.1136/bmj-2023-078713 | CC-BY-4.0 | global | behaviour-change, coaching-communication, activity, adherence, motivation | The strongest recent test of whether a motivational-interviewing coaching style raises activity, with a frank statement of how weak and short-lived the evidence is. |
| lally_2010_habit_formation | Behaviour change | Lally et al. 2010 | doi:10.1002/ejsp.674 | proprietary | global | behaviour-change, habits, adherence, consistency, coaching-communication | The standard study of how long a new daily habit takes to feel automatic, which answers 'how long until this becomes easy?' without a made-up number. |
| mujika_2001_muscular_detraining | Special cases | Mujika and Padilla 2001 | doi:10.1097/00005768-200108000-00009 | proprietary | global | detraining, training, strength, recovery, time-off | Directly answers 'will I lose my gains if I cannot train for a couple of weeks?' for trained people. |
| bosquet_2013_training_cessation | Special cases | Bosquet et al. 2013 | doi:10.1111/sms.12047 | proprietary | global | detraining, training, strength, time-off, older-adults | The broadest pooled analysis of how much strength is lost when resistance training stops and who loses it fastest. |
| lopes_2019_elastic_resistance | Special cases | Lopes et al. 2019 | doi:10.1177/2050312119831116 | CC-BY-NC-4.0 | global | home-training, equipment, strength, training, minimal-equipment | Shows that resistance bands, which fit in a bag, build strength about as well as weights, which is the main question when a person must train away from a gym. |
| fragala_2019_older_adults | Special cases | Fragala et al. 2019 (NSCA) | doi:10.1519/jsc.0000000000003230 | proprietary | global | older-adults, strength, training, safety, guidelines | The most thorough professional position on resistance training for older adults, so Coach can explain why lifting matters with age. |
| mcnulty_2020_menstrual_cycle | Special cases | McNulty et al. 2020 | doi:10.1007/s40279-020-01319-3 | CC-BY-4.0 | global | women, menstrual-cycle, performance, training, individualisation | The best pooled answer to whether training should change across the menstrual cycle, which Coach is often asked. |

Owner review points: Helms 2014 is a contest-prep paper (an extreme case; the summary says so and
repeats its eating-disorder warning); Piercy 2018 is tagged `US` (the others are `global`); the
PAR-Q+ article has no DOI (linked in PubMed Central); Kreider 2017, Guest 2021 and Sawka 2007 are
supplement and hydration guidance for healthy adults, flagged as such. Not included: certification-
body articles (NASM, ACE, NSCA; none needed to cover the areas), a regional India source (the
ICMR-NIN dietary guidelines URL I tried returned 404, so it could not be verified; E4 is the right
place), and a recovery consensus statement (Kellmann 2018, dropped as too general).

### Gates

`./scripts/deno.sh fmt --check`, `lint`, `test` for `supabase/functions` pass (738 tests);
`./scripts/pre-deploy.sh --deno-only` passes. pgTAP `library_ingestion_test.sql` (52 assertions:
loaded counts and constraints, the loader's idempotence, the worker functions' grants with
`has_function_privilege`, the cron job, the Vault secret, pending and store behaviour) passes, as
does the whole suite (71 files, 1,989 tests) on the local stack with the migration applied.
`research_library_test.sql` now starts by deleting the loaded sources inside its transaction,
because its ranking fixtures assume an empty library.

## E2.1: knowledge base, gap sources (in review)

Branch `claude/e2-library-gaps`, migration `20261018030042_library_gap_sources.sql` (code 42, additive:
it only calls `private.library_replace_source`; the `library-embed` worker fills the 14 sources'
embeddings after the deploy, as it did for the first 35). Written for a real case: an athlete who
lost 15 kg (17 percent) over 19 weeks, is at BMI 23, still wants to lose fat, says he "feels a
little weird" and will train at home for 10 to 15 days.

### What shipped

- **14 sources** in `supabase/library/sources/energy_balance.ts`, `behaviour_change.ts` and
  `special_cases.ts` (49 sources in all; 14 source blocks in the migration, generated by the same
  `build_migration.ts` with `--only`). The table above lists them with licence, region, topics and
  why each was chosen. One is regional: `icmr_nin_2024_dietary_guidelines` carries `region: ["IN"]`
  (the pgTAP region check now allows `IN`), so a caller passes `["global", "IN"]` to see it.
- **Verification.** Every DOI was checked on 2026-10-18 against Crossref (title, authors, year,
  volume and pages, licence) and Europe PMC (the abstract). Each summary is in our own words and
  limited to text fetched: the abstract for all but Trexler 2014, Vella 2010 and Varkevisser 2019
  (also read in their open full text) and ICMR-NIN 2024 (read in the PDF: guidelines 8, 9 and 10).
  Lally 2010 is not in PubMed or Europe PMC, so its abstract comes from Crossref.
- **Digest, version 2** (`coaching_principles.ts`): 7,024 characters, inside the 7,200 budget
  (1,800 tokens at four characters a token). Added: long diets and diet breaks, metabolic
  adaptation, low energy availability, keeping weight off, alcohol, time off, home training, the
  menstrual cycle, older adults and habits. Every figure added is in a cited source (4 weeks,
  18 to 254 days). There is deliberately no India line: the digest is in every athlete's prompt,
  and the ICMR-NIN source is region-tagged `IN`, so it is reached only through retrieval with a
  region filter (regional digests are E4). To make room, wording of the version-1 text was tightened
  without removing a figure; `pelland_2026_volume_frequency` and `piercy_2018_us_guidelines` are no
  longer cited in the digest (both stay in the library).
- **Retrieval questions:** 19 added to `library_questions.json` (61 in all); the size bounds in
  `library_eval_test.ts` and `library_content_test.ts` were widened, and the area test now checks the
  new topics.

### Recall

Not measured. The local Colima VM would not boot (nine minutes with no serial log, the known VZ
boot hang), so `library_eval.ts` could not run against real gte-small embeddings, and a number
from full-text search alone would say nothing (E2 measured 0.20 for it). The 19 new questions are
in place; run the E2 "How to run it" steps on a working stack, or once production has embedded
all 14 sources, and compare against E2's 0.929 hybrid mean recall (42 questions).

### Gates

`./scripts/deno.sh fmt --check supabase/functions`, `lint` and `test --allow-env --allow-net
--allow-read=supabase/migrations,site/src/config.ts supabase/functions` pass (941 tests);
`./scripts/check-migration-order.sh origin/main` passes. The pgTAP file
`library_ingestion_test.sql` was edited for the new `IN` region and has not run locally (no
stack); CI runs it.

### Sources dropped or limited

- Grgic 2022 (detraining, older adults) was dropped: it covers 12 to 52 weeks in older adults, not
  a short break. Mujika and Padilla 2001 and Bosquet 2013 answer the short-break question.
- Gardner 2012 (habits) was dropped: its abstract is empty, and Lally 2010 carries the habit
  evidence.
- No bodyweight-training review was found with a usable abstract; the home-training source
  (Lopes 2019) covers resistance bands against conventional weights only, and its summary and the
  digest say bodyweight was not tested.
- Mountjoy 2023 (IOC REDs) and Fragala 2019 (NSCA position statement) are summarised from the
  abstract only (the full text is paywalled or behind a bot check), so neither gives signs,
  thresholds or programme variables. Fragala is a peer-reviewed journal position statement; no
  NSCA, NASM or ACE course material or textbook was used.

### Owner review points

- ICMR-NIN 2024 copyright: reproduction "in any electronic format for creating a product" needs
  NIN's written permission. Only an own-words summary with the citation is stored (same treatment as
  the other publisher-copyright sources); confirm that is acceptable, or ask NIN.
- The ICMR-NIN guidelines advise against protein powders and give 0.83 g per kg a day as the
  allowance, while ISSN (Jäger 2017) gives 1.4 to 2.0 g per kg for people who train. Coach sees ICMR-NIN
  only through retrieval for Indian users, where the region filter applies; the numbers stay with the
  plan's rules.
- MATADOR (Byrne 2018) found more fat loss with diet breaks in men with obesity; ICECAP (Peos 2021)
  found none in trained adults but less hunger. Both are summarised, and the digest calls a break a
  choice, not a promise.

## E2.2: library expansion and machine-readable licences (in review)

Branch `claude/library-expansion`, migration `20261018170042_library_expansion.sql` (code 42,
additive: it only calls `private.library_replace_source`). Written from the 2026-10-18 RAG audit
(P1-1 corpus gaps, the P3 licence item, the licensing section and its source plan).

### What shipped

- **Licence fields.** `LibrarySource.licence` is now a `LibraryLicence` identifier (`CC-BY-2.0`,
  `CC-BY-3.0`, `CC-BY-4.0`, `CC-BY-NC-4.0`, `CC-BY-NC-ND-4.0`, `CC-BY-NC-SA-3.0-IGO`, `OGL-UK-3.0`,
  `public-domain-us-gov`, `proprietary`) with `verbatimAllowed`, `lastReviewed` (ISO date) and an
  optional `supersededBy`. The free text is gone from all 49 earlier sources. `chosenBecause` now
  ends with what the summary was written from ("Summarised from the full text.", "... the abstract
  only.", "... the full document ...", "... the official summary ..."). `acsm_2009_progression` is
  `supersededBy: "acsm_2026_resistance_prescription"` (the field is stored in the content files
  only; retrieval does not read it yet).
- **Licence re-check of the 49.** Against Crossref, Europe PMC and the full-text licence tag:
  Helms 2014 is CC BY 2.0 (was recorded as 4.0) and Paluch 2022 is CC BY-NC-ND 4.0 (was recorded
  as CC BY 4.0; Crossref and the PMC article page both say NC-ND). The table above now shows
  the identifiers.
- **Tests** (`library_content_test.ts`): the cap is 30 to 150 sources; every licence is a known
  identifier; `verbatimAllowed` is possible only for `CC-BY-2.0/3.0/4.0`, `OGL-UK-3.0` or
  `public-domain-us-gov` (never NC, ND, SA or proprietary); `lastReviewed` is a real date; a
  superseded source names a newer, non-superseded source; `chosenBecause` says what was read;
  the area test covers the new topics and the `US`, `GB` and `IN` regions. pgTAP
  `library_ingestion_test.sql` (plan 98) now expects `licence = 'CC-BY-4.0'` for the known source,
  allows region `GB`, and checks every loaded licence is an identifier.
- **57 new sources** in eight new files (`programming.ts`, `exercise_selection.ts`,
  `body_composition.ts`, `supplements.ts`, `cardio_recovery.ts`, `populations.ts`,
  `guidelines.ts`, `india.ts`), 106 in all, 351 chunks. The migration carries all 106 blocks: the
  49 earlier ones differ only in the licence value (their chunks are byte-identical, so the loader
  keeps their chunks and embeddings); the 57 new ones load without embeddings and
  `library-embed` fills them after the deploy.
- **Size.** The whole library renders to 199,715 characters, about 50,000 to 57,000 tokens, under
  the 60,000-token line in `_evals/library_full_test.ts`. Headroom is now about 3,000 tokens: the
  next expansion either trims or retires sources, or that line is revisited (retrieval does not
  depend on it).

### Licence policy (commercial app)

- Every source: an own-words summary with a citation and link. No close paraphrase, no tables or
  figures, no full texts stored or placed in prompts.
- Short verbatim text only when `verbatimAllowed` is true (CC BY without NC/ND/SA, OGL v3, US
  federal public domain), with attribution. Two entries quote a phrase this way: HHS 2018 ("start
  low and go slow") and the UK CMOs ("some is good, more is better"); the rest quote nothing.
- NC, ND, WHO IGO, ICMR-NIN and paywalled sources: summary only. ICMR-NIN and the Indian food
  composition tables forbid reproduction in an electronic product without NIN's written
  permission, so only individual facts with the citation are stored (five rounded protein values
  from IFCT 2017; single figures from the 2020 requirements), never a table.
- When records disagree, the more restrictive licence wins; unclear means `proprietary`.

### Verification

Every source was checked on 2026-10-18 against its Crossref record (title, authors, year, journal,
licence URLs) and Europe PMC (identifiers, licence, abstract), and the open full text was read
where it is lawful to read (Europe PMC, PMC, the publisher or the issuing body). Numbers come only
from what was read. 37 were summarised from the full text or full document, 19 from the abstract
only, and one (ICMR-NIN 2020) from NIN's official brief note because the full book is sold in
print. Abstract-only entries say so in their "Practical reading and limits" section.

### The 57 new sources

| Key | Area | Citation | DOI or link | Licence | Verbatim | Region | Read from |
|---|---|---|---|---|---|---|---|
| williams_2017_periodised_strength | Programming | Williams et al. 2017 | doi:10.1007/s40279-017-0734-y | proprietary | no | global | abstract only |
| moesgaard_2022_periodisation_volume_equated | Programming | Moesgaard et al. 2022 | doi:10.1007/s40279-021-01636-1 | proprietary | no | global | abstract only |
| grgic_2017_linear_undulating_hypertrophy | Programming | Grgic et al. 2017 | doi:10.7717/peerj.3695 | CC-BY-4.0 | yes | global | full text |
| helms_2018_rpe_vs_percentage | Programming | Helms et al. 2018 | doi:10.3389/fphys.2018.00247 | CC-BY-4.0 | yes | global | full text |
| hickmott_2022_autoregulation | Programming | Hickmott et al. 2022 | doi:10.1186/s40798-021-00404-9 | CC-BY-4.0 | yes | global | full text |
| halperin_2022_rir_prediction_accuracy | Programming | Halperin et al. 2022 | doi:10.1007/s40279-021-01559-x | proprietary | no | global | abstract only |
| refalo_2023_failure_hypertrophy | Programming | Refalo et al. 2023 | doi:10.1007/s40279-022-01784-y | CC-BY-4.0 | yes | global | full text |
| coleman_2024_deload_trial | Programming | Coleman et al. 2024 | doi:10.7717/peerj.16777 | CC-BY-4.0 | yes | global | full text |
| travis_2020_powerlifting_taper | Programming | Travis et al. 2020 | doi:10.3390/sports8090125 | CC-BY-4.0 | yes | global | full text |
| bosquet_2007_tapering | Programming | Bosquet et al. 2007 | doi:10.1249/mss.0b013e31806010e0 | proprietary | no | global | abstract only |
| haugen_2023_free_weights_machines | Exercise selection and injury risk | Haugen et al. 2023 | doi:10.1186/s13102-023-00713-4 | CC-BY-4.0 | yes | global | full text |
| wolf_2023_partial_full_rom | Exercise selection and injury risk | Wolf et al. 2023 | doi:10.47206/ijsc.v3i1.182 | CC-BY-4.0 | yes | global | full text |
| kassiano_2022_exercise_variation | Exercise selection and injury risk | Kassiano et al. 2022 | doi:10.1519/JSC.0000000000004258 | proprietary | no | global | abstract only |
| keogh_2017_weight_training_injuries | Exercise selection and injury risk | Keogh and Winwood 2017 | doi:10.1007/s40279-016-0575-0 | proprietary | no | global | abstract only |
| lauersen_2018_strength_dose_injury | Exercise selection and injury risk | Lauersen et al. 2018 | doi:10.1136/bjsports-2018-099078 | proprietary | no | global | abstract only |
| impellizzeri_2020_acwr_pitfalls | Exercise selection and injury risk | Impellizzeri et al. 2020 | doi:10.1123/ijspp.2019-0864 | proprietary | no | global | abstract only |
| trommelen_2023_protein_dose | Body composition | Trommelen et al. 2023 | doi:10.1016/j.xcrm.2023.101324 | CC-BY-4.0 | yes | global | full text |
| iraki_2019_offseason_bodybuilding | Body composition | Iraki et al. 2019 | doi:10.3390/sports7070154 | CC-BY-4.0 | yes | global | full text |
| slater_2019_energy_surplus | Body composition | Slater et al. 2019 | doi:10.3389/fnut.2019.00131 | CC-BY-4.0 | yes | global | full text |
| helms_2023_energy_surplus | Body composition | Helms et al. 2023 | doi:10.1186/s40798-023-00651-y | CC-BY-4.0 | yes | global | full text |
| murphy_2022_energy_deficiency_lean_mass | Body composition | Murphy and Koehler 2022 | doi:10.1111/sms.14075 | CC-BY-NC-ND-4.0 | no | global | abstract only |
| garthe_2011_weight_loss_rate | Body composition | Garthe et al. 2011 | doi:10.1123/ijsnem.21.2.97 | proprietary | no | global | abstract only |
| barakat_2020_recomposition | Body composition | Barakat et al. 2020 | doi:10.1519/SSC.0000000000000584 | CC-BY-NC-ND-4.0 | no | global | full text |
| pinckaers_2021_plant_protein | Body composition | Pinckaers et al. 2021 | doi:10.1007/s40279-021-01540-8 | CC-BY-4.0 | yes | global | full text |
| hevia_larrain_2021_vegan_protein | Body composition | Hevia-Larraín et al. 2021 | doi:10.1007/s40279-021-01434-9 | proprietary | no | global | abstract only |
| maughan_2018_ioc_supplements | Supplements | Maughan et al. 2018 (IOC) | doi:10.1136/bjsports-2018-099027 | CC-BY-NC-4.0 | no | global | full text |
| antonio_2021_creatine_questions | Supplements | Antonio et al. 2021 | doi:10.1186/s12970-021-00412-w | CC-BY-4.0 | yes | global | full text |
| kaviani_2020_creatine_vegetarians | Supplements | Kaviani et al. 2020 | doi:10.3390/ijerph17093041 | CC-BY-4.0 | yes | global | full text |
| trexler_2015_beta_alanine | Supplements | Trexler et al. 2015 (ISSN) | doi:10.1186/s12970-015-0090-y | CC-BY-4.0 | yes | global | full text |
| senefeld_2020_nitrate | Supplements | Senefeld et al. 2020 | doi:10.1249/mss.0000000000002363 | CC-BY-NC-ND-4.0 | no | global | full text |
| wolfe_2017_bcaa | Supplements | Wolfe 2017 | doi:10.1186/s12970-017-0184-9 | CC-BY-4.0 | yes | global | full text |
| nih_ods_2024_exercise_supplements | Supplements | NIH ODS 2024 | https://ods.od.nih.gov/factsheets/ExerciseAndAthleticPerformance-HealthProfessional/ | public-domain-us-gov | yes | global | full text |
| wewege_2017_hiit_body_composition | Cardio, recovery and sleep | Wewege et al. 2017 | doi:10.1111/obr.12532 | proprietary | no | global | abstract only |
| milanovic_2015_hiit_vo2max | Cardio, recovery and sleep | Milanović et al. 2015 | doi:10.1007/s40279-015-0365-0 | proprietary | no | global | abstract only |
| mandsager_2018_cardiorespiratory_fitness_mortality | Cardio, recovery and sleep | Mandsager et al. 2018 | doi:10.1001/jamanetworkopen.2018.3605 | CC-BY-4.0 | yes | global | full text |
| roberts_2015_cold_water_strength_adaptation | Cardio, recovery and sleep | Roberts et al. 2015 | doi:10.1113/JP270570 | proprietary | no | global | full text |
| malta_2021_cold_water_training_adaptations | Cardio, recovery and sleep | Malta et al. 2021 | doi:10.1007/s40279-020-01362-0 | proprietary | no | global | abstract only |
| craven_2022_sleep_loss_performance | Cardio, recovery and sleep | Craven et al. 2022 | doi:10.1007/s40279-022-01706-y | CC-BY-4.0 | yes | global | full text |
| lamon_2021_sleep_deprivation_muscle_protein | Cardio, recovery and sleep | Lamon et al. 2021 | doi:10.14814/phy2.14660 | CC-BY-4.0 | yes | global | full text |
| borde_2015_older_adults_dose_response | Older lifters, women, home and travel | Borde et al. 2015 | doi:10.1007/s40279-015-0385-9 | CC-BY-4.0 | yes | global | full text |
| izquierdo_2021_icfsr_older_adults | Older lifters, women, home and travel | Izquierdo et al. 2021 (ICFSR) | doi:10.1007/s12603-021-1665-8 | CC-BY-4.0 | yes | global | full text |
| bauer_2013_prot_age_protein | Older lifters, women, home and travel | Bauer et al. 2013 (PROT-AGE) | doi:10.1016/j.jamda.2013.05.021 | CC-BY-NC-ND-4.0 | no | global | abstract only |
| roberts_2020_sex_differences_resistance_training | Older lifters, women, home and travel | Roberts et al. 2020 | doi:10.1519/JSC.0000000000003521 | proprietary | no | global | abstract only |
| colenso_semple_2023_menstrual_cycle_resistance | Older lifters, women, home and travel | Colenso-Semple et al. 2023 | doi:10.3389/fspor.2023.1054542 | CC-BY-4.0 | yes | global | full text |
| elliott_sale_2020_oral_contraceptives_performance | Older lifters, women, home and travel | Elliott-Sale et al. 2020 | doi:10.1007/s40279-020-01317-5 | CC-BY-4.0 | yes | global | full text |
| kikuchi_2017_push_up_bench_press | Older lifters, women, home and travel | Kikuchi and Nakazato 2017 | doi:10.1016/j.jesf.2017.06.003 | CC-BY-NC-ND-4.0 | no | global | full text |
| wiedenmann_2025_older_adults_training_modalities | Older lifters, women, home and travel | Wiedenmann et al. 2025 | doi:10.1159/000546346 | proprietary | no | global | abstract only |
| spiering_2021_minimal_dose_maintenance | Older lifters, women, home and travel | Spiering et al. 2021 | doi:10.1519/JSC.0000000000003964 | proprietary | no | global | abstract only |
| janse_van_rensburg_2021_travel_jet_lag | Older lifters, women, home and travel | Janse van Rensburg et al. 2021 | doi:10.1007/s40279-021-01502-0 | proprietary | no | global | full text |
| hhs_2018_physical_activity_guidelines | National guidelines | HHS 2018 (Physical Activity Guidelines for Americans) | https://odphp.health.gov/sites/default/files/2019-09/Physical_Activity_Guidelines_2nd_edition.pdf | public-domain-us-gov | yes | US | full document |
| usda_hhs_2026_dietary_guidelines | National guidelines | USDA and HHS 2026 (Dietary Guidelines for Americans) | https://cdn.realfood.gov/DGA.pdf | public-domain-us-gov | yes | US | full document |
| uk_cmo_2026_activity_guidelines | National guidelines | UK CMOs 2026 | https://www.gov.uk/government/publications/physical-activity-guidelines-uk-chief-medical-officers-report/uk-chief-medical-officers-physical-activity-guidelines | OGL-UK-3.0 | yes | GB | full document |
| icmr_nin_2020_nutrient_requirements | India | ICMR-NIN 2020 (RDA and EAR) | https://www.nin.res.in/rdabook/brief_note.pdf | proprietary | no | IN | official summary |
| longvah_2017_ifct | India | Longvah et al. 2017 (IFCT) | https://nin.res.in/ebooks/IFCT2017.pdf | proprietary | no | IN | full document |
| who_2004_asian_bmi | India | WHO expert consultation 2004 | doi:10.1016/S0140-6736(03)15268-3 | proprietary | no | IN | abstract only |
| misra_2025_obesity_asian_indians | India | Misra et al. 2025 | doi:10.1016/j.dsx.2024.102989 | proprietary | no | IN | full text |
| anjana_2014_indiab_activity | India | Anjana et al. 2014 (ICMR-INDIAB) | doi:10.1186/1479-5868-11-26 | CC-BY-2.0 | yes | IN | full text |

### Coverage of the audit's gaps

| Gap (audit P1-1) | Sources now covering it |
|---|---|
| Periodisation | williams_2017_periodised_strength, moesgaard_2022_periodisation_volume_equated, grgic_2017_linear_undulating_hypertrophy |
| RPE/RIR and autoregulation | helms_2018_rpe_vs_percentage, hickmott_2022_autoregulation, halperin_2022_rir_prediction_accuracy, refalo_2023_failure_hypertrophy (plus zourdos_2016, robinson_2024) |
| Deloads | coleman_2024_deload_trial (plus bell_2023_deloading) |
| Peaking and tapering | travis_2020_powerlifting_taper, bosquet_2007_tapering |
| Free weights vs machines, ROM, substitution | haugen_2023_free_weights_machines, wolf_2023_partial_full_rom, kassiano_2022_exercise_variation, wiedenmann_2025_older_adults_training_modalities |
| Injury risk (non-rehab) and the ACWR critique | keogh_2017_weight_training_injuries, lauersen_2018_strength_dose_injury, impellizzeri_2020_acwr_pitfalls (against gabbett_2016_training_load) |
| HIIT vs steady cardio, fitness | wewege_2017_hiit_body_composition, milanovic_2015_hiit_vo2max, mandsager_2018_cardiorespiratory_fitness_mortality |
| Surplus, bulking, recomposition | slater_2019_energy_surplus, helms_2023_energy_surplus, iraki_2019_offseason_bodybuilding, barakat_2020_recomposition, murphy_2022_energy_deficiency_lean_mass, garthe_2011_weight_loss_rate |
| Protein dose per meal | trommelen_2023_protein_dose |
| Cold-water immersion | roberts_2015_cold_water_strength_adaptation, malta_2021_cold_water_training_adaptations |
| Supplements beyond protein, creatine and caffeine | maughan_2018_ioc_supplements, antonio_2021_creatine_questions, trexler_2015_beta_alanine, senefeld_2020_nitrate, wolfe_2017_bcaa, nih_ods_2024_exercise_supplements |
| Plant protein, creatine for vegetarians | pinckaers_2021_plant_protein, hevia_larrain_2021_vegan_protein, kaviani_2020_creatine_vegetarians |
| Sleep loss | craven_2022_sleep_loss_performance, lamon_2021_sleep_deprivation_muscle_protein |
| Older lifters | borde_2015_older_adults_dose_response, izquierdo_2021_icfsr_older_adults, bauer_2013_prot_age_protein, wiedenmann_2025_older_adults_training_modalities |
| Women | roberts_2020_sex_differences_resistance_training, colenso_semple_2023_menstrual_cycle_resistance, elliott_sale_2020_oral_contraceptives_performance (no pregnancy content) |
| Home, bodyweight, travel, minimal dose | kikuchi_2017_push_up_bench_press, wiedenmann_2025_older_adults_training_modalities, spiering_2021_minimal_dose_maintenance, janse_van_rensburg_2021_travel_jet_lag |
| Verbatim-OK guidelines | hhs_2018_physical_activity_guidelines (US), usda_hhs_2026_dietary_guidelines (US, the 2025-2030 edition released January 2026), uk_cmo_2026_activity_guidelines (GB; first issued 2011, revised 2019, evidence updated July 2026 without changing the guidance) |
| India | icmr_nin_2020_nutrient_requirements, longvah_2017_ifct, who_2004_asian_bmi, misra_2025_obesity_asian_indians, anjana_2014_indiab_activity |

### Sources dropped or replaced

- Viana 2019 (BJSM, interval training and fat loss) was retracted on 2020-12-15; it is not in the
  library, and the Wewege 2017 entry says why.
- Misra 2009 (Asian Indian obesity consensus, JAPI) has no DOI and an abstract with no cut-offs;
  replaced by its 2025 revision (Misra et al., full text), which restates the 2009 figures.
- Verified but left out to keep the size budget: Larsen 2021 (PeerJ, overlaps Hickmott 2022),
  Impellizzeri 2021 (Sports Med, same case as the 2020 paper, mentioned there), Pallarés 2021
  (ROM, covered by Wolf 2023), Momma 2022 (BJSM, strength activity and mortality, observational),
  Grgic 2019 (caffeine umbrella; Guest 2021 covers caffeine), Jones 2018 (nitrate; Senefeld 2020
  chosen for its open full text).
- Not used: Peeling 2018 (short abstract, covered by the IOC statement), Pritchard 2015 (Travis
  2020 covers tapering for strength), Janse van Rensburg 2020 (an editorial with no abstract).
- Two DOIs suggested in the brief were wrong (Bosquet 2007 and Helms 2023); the correct ones
  are in the table.

### Where new sources strain the digest (owner review; `coaching_principles.ts` not edited)

None contradicts a digest line outright; these refine it. The digest stays at version 2 and does
not cite the new sources yet.

- **Protein per meal.** The digest's "0.25 to 0.4 g per kg" per meal rests partly on a 20 to 25 g
  ceiling; Trommelen 2023 found 100 g kept building muscle protein for longer with little extra
  burned, and Iraki 2019 suggests 0.40 to 0.55 g per kg per meal. The entries keep spreading as a
  sensible guide.
- **Daily protein.** Barakat 2020 cites 2.6 to 3.5 g per kg of fat-free mass for recomposition;
  the US 2025-2030 guidelines give 1.2 to 1.6 g per kg for the public; ICMR-NIN 2020 gives an
  allowance of 0.83 g per kg. The entries explain the different purposes.
- **ACWR.** Impellizzeri 2020 says no evidence supports using the acute:chronic ratio to manage
  injury risk, which challenges how the Gabbett 2016 entry describes it; the digest's line on
  gradual progression still holds. Consider a half-line in the digest or the Gabbett entry.
- **Cold water.** The digest says cold eases soreness; Roberts 2015 and Malta 2021 add that
  routine use after lifting can blunt strength and muscle gains.
- **Bodyweight.** The digest says "bodyweight alone was not tested" (true of Lopes 2019);
  Kikuchi 2017 and Wiedenmann 2025 now test it.
- **Range of motion.** Wolf 2023 found little difference between partial and full range and no
  clear upper versus lower body split, a refinement of the digest's legs-versus-arms wording.
- **Time off.** Travis 2020 (two weeks or more off lowered maximums slightly) and Coleman 2024 (a
  week off gave somewhat smaller strength gains) soften "a short break rarely undoes progress".
- **Rest for older adults.** Borde 2015 found 60 seconds best for strength in older adults, from
  only two studies.
- **Periodisation.** Williams 2017 and Moesgaard 2022 find a small strength advantage, against
  ACSM 2026's "no consistent effect"; both entries say so.

### Owner review points

- Agents read Misra 2025 from an institutional copy (CMC Vellore) and the NIH ODS fact sheet from
  the Internet Archive snapshot of 2026-10-12 (the live site is behind a bot check).
- Barakat 2020's CC BY-NC-ND rests on Crossref, OpenAlex and Semantic Scholar; the publisher page
  shows no licence wording. It is summary-only either way.
- Region `GB` is new (UK CMOs). The account-region function already derives `GB` from an `en-GB`
  locale, so no SQL change was needed.
- Not done here (other owners): retrieval does not yet read `supersededBy`, `verbatimAllowed` or
  `lastReviewed` (they are not in the database). Recall on the new sources is measured since E3.1
  (below).

### Fact-check corrections (after review)

An independent fact-check compared the summaries with the original papers; Codex added one item.
All corrections are in the content files and the migration was regenerated (the 106 blocks and
their hashes match the sources). No source was added.

- **Wrong or unsupported claims.** Helms 2023 (the two surplus groups gained the same weight; the
  logged surpluses did differ, and not everyone kept to theirs); Roberts 2015 (now read from the
  full text: lower-body training, water about 10 °C waist-deep, experienced men; later work by Fyfe
  2019 and Grgic 2022 shows a smaller cost, limited to immersing the trained limbs); Malta 2021
  (Grgic 2022 cited as a caveat); Anjana 2014 (the 46 and 14 minute figures are averages among
  those with active work or active travel, and the survey is "large, representative" rather than
  "the largest"); Misra 2025 (body fat overrides BMI only below 23, no exception for muscular
  people; weight-loss rate wording; collective author added); Haugen 2023 (participants "mostly
  men", the counts did not add up).
- **BMI boundary (Misra 2025).** The entry said a normal BMI is up to just under 23 but staged
  obesity from "above 23", which looked like it left exactly 23.0 unclassified. The fact-check
  against the paper settled it: the paper uses "more than 23" for the obesity stages and grades
  23 to 24.9 as overweight Grade I, so the entry keeps "above 23" and now says a normal BMI is
  18.5 to 22.99 with that grading note. Stage 1 also requires no obesity-related disease.
- **Closer than allowed to a proprietary abstract.** Reworded: Impellizzeri 2020, Wiedenmann 2025,
  WHO 2004 and Roberts 2020; Impellizzeri 2021 named as the follow-up.
- **Smaller fixes.** UK CMO history (2011, 2019, evidence updated July 2026); US dietary guidelines
  (full-fat dairy with no added sugars; the PDF's Shutterstock images are not covered by the
  public-domain text); ICMR-NIN (protein figure is the same for sedentary, moderate and heavy
  work; the 5 percent basal-rate cut adds to 2010's); IFCT (as-analysed wording, six-region mean
  for most foods); Colenso-Semple 2023 (three of five reviews, ovulation assumptions);
  Elliott-Sale 2020; Kikuchi 2017 (load roughly matched, men called untrained, evidence level);
  Williams 2017; the IOC statement (Maughan); Refalo 2023 (subgroup figures, authors' extra
  cases); Barakat 2020 (sleep evidence is from non-lifting overweight adults); the HHS link now
  uses odphp.health.gov.

### Gates

`./scripts/deno.sh fmt --check supabase/functions`, `lint` and `test --allow-env --allow-net
--allow-read=supabase/migrations,site/src/config.ts supabase/functions` pass (1,298 tests);
`./scripts/check-migration-order.sh origin/main` passes. pgTAP runs only in CI.

## E3: the library shapes every Coach reply (in review)

Branch `claude/e3-library-in-coach`, migration `20261018140043_library_search_v2.sql` (code 43).

### What shipped

- **`search_library_v2`** (Contract 6 v2; `search_library_v1` is dropped, nothing deployed called it).
  Full-text search ORs the terms of the question (v1's `websearch_to_tsquery` ANDed them: the
  "Finding for E3" above), reciprocal rank fusion with k = 50, rows carry `source_key` (the manifest
  key Coach cites) and `schema_version` 2, at most three rows per source, `match_count` up to 10.
  `target_user_id` limits the sources to the athlete's regions: `global` plus the country in the
  account locale and `IN` for an Indian time zone, because the app stores no country yet
  (`private.library_regions_for_account`; change that one function when a country is stored). An
  `IN` source reaches only Indian athletes. Field list and rules: DATA_MODEL.md section 12.
- **The `library` contributor** (`_shared/library/retrieval.ts`, `live.ts`, `query.ts`), registered
  last, volatile, gateway route only. Query: the question, plus the topic of the athlete's last real
  question when it is a follow-up (`isFollowUp`: no topic word, or a few and a lead or demonstrative
  such as "And ...", "What about ...", "that"; a bare "it" counts only in a question of two topic
  words or fewer). Deterministic, no model call. The query is embedded with `gte-small` by
  `library-embed` (its new `{"query": ...}` mode, called over HTTP by `query_embedder.ts`; no new
  provider), then the
  search runs for the athlete. Up to 8 chunks, whole chunks within 9,000 characters (the eight
  longest chunks are 7,200), each `[source: <id>] <header>` and the body. A failed embedding falls
  back to words alone (logged `library_retrieval_degraded`); a failed or slow search (the host's
  4 seconds) leaves the library out and Coach answers without it. A red-flag turn retrieves nothing
  (`coach-chat/index.ts` skips every contributor, and now also a turn `screenTurn` would refer).
- **Citations.** Evidence items gain the source `library`: `code` is the source id, `label` a short
  citation. `parseCoachChatAnswer` refuses a library citation whose id was not shown this turn (new
  rule `citation_not_retrieved`; `shownLibraryKeysIn` reads the ids back from the rendered block),
  and the reply guard refuses an id printed in the text that was not shown. One repair, then the
  labelled data summary, like every other rule. The output schema takes any evidence code as a
  plain string because the ids change every turn (the permitted data codes and the shown library
  ids are checked after the answer; the schema had an `anyOf` and the day's enum until the
  2026-10-18 incident, see `ai-gateway.md`). The app shows library evidence in the
  existing evidence disclosure as "Research library" (`coach_labels.dart`).
- **Rules in the prompt.** "Using the research library" (system prompt, gateway only): precedence
  (Tracend's calculations, confirmed facts, the athlete's words, then the library), cite by id, never
  print ids, never fill a gap from memory, a figure is that source's guidance, never the athlete's
  target. The retrieved block is a contributor block, so its figures are grounded for the numbers
  check; a figure nothing holds is still refused.
- **Heart-rate profile registered** (C3's `heart_rate_profile`, 900 characters, volatile). It reads
  `get_heart_rate_inputs_v1` with the service role.
- **Contract 7 v1.1:** the contributor input gains the optional `previousQuestions` (the athlete's
  earlier questions, newest first). Listed for the lead's approval in the program doc.
- **Removed:** `search_library_v1` (migration), its pgTAP assertions (rewritten for v2), the
  `library_eval.ts` url-to-key lookup, and the unregistered state of the digest and heart-rate
  contributors. The `coachChatEvidenceSources` list gained `library`; the legacy provider schema uses
  the new `coachChatDataEvidenceSources` (the old three).

### Review fixes (Opus review of #150, no P1s)

- **Embedding deadline (P2) and the model out of coach-chat (blocking change).** The question's
  embedding races a 1.5-second deadline (`libraryEmbedDeadlineMs`); on a timeout or a failure the
  search runs with `embedding: null` (words alone) instead of the host's 4-second limit dropping
  the whole block. The model itself no longer loads in coach-chat: a first load (16.3 s locally in the
  E1 spike, about 70 ms after) and the CPU kills the E2 note records (about 1.1 s soft, 2.1 s hard
  locally) would have taken the whole Coach turn down. `library-embed` gained a `{"query": "..."}`
  mode (one text of 1 to 1,000 characters in, `{schema_version, embedding}` out; the `texts` batch
  mode and the cron worker run are unchanged) behind the same worker-secret check. Coach chat reads
  the secret once through the service-role function `library_worker_secret_v1()` (added to this PR's
  migration; it returns the Vault secret the cron job already uses; no new secret, no new public
  surface) and calls `${SUPABASE_URL}/functions/v1/library-embed` with it; the body is the question,
  which neither side logs. The embedder constants and type moved to `embedding.ts` so coach-chat's
  import graph holds no model code: `deno info --json supabase/functions/coach-chat/index.ts` lists
  101 modules and not `embedder.ts`, and `Supabase.ai` appears nowhere under coach-chat or the
  shared modules it imports. A first query after library-embed's isolate starts still waits for the
  model there, so that turn gets word search; the load continues for the next.
  **Deploy order:** `library-embed` and coach-chat deploy in the same run, one after the other. Until
  the new `library-embed` is live, coach-chat's query call gets a non-200 and uses word search: safe.
  The migration runs before both. Not measured: library-embed's memory and CPU with query traffic;
  after the deploy, check its logs for resource-limit errors and coach-chat's for
  `library_retrieval_degraded`.
- **Library figures (P2).** The library is no longer in the main numbers ground. A figure only the library
  holds is accepted when the reply cites the source whose shown chunks contain it, and in a sentence that
  states the athlete's own target or prescription the numbers must come from the athlete's data and
  calculations alone, never the library or the principles digest (AI_SAFETY_SPEC §11.2). The
  contributor host now returns each contributor's text (`texts`) and the shown sources (`shown`:
  id, label, chunk text) beside the blocks; `CoachChatAnswerCheck` takes the cited ids.
- **Labels (P3).** The server overwrites a `library` citation's label with the retrieved source's title
  and year (`parseCoachChatAnswer`).
- **Red-flag follow-ups (P3).** An earlier question `screenMessage` flags is skipped when a follow-up
  picks its topic.
- **"Why" and "how come" (P3)** are no longer follow-up leads ("Why?" alone still has no topic of its own).
- **Shown ids (P3).** They come from the contributor's rows (`RenderedBlock.shown`), not from parsing the
  prompt text; `shownLibraryKeys` and `shownLibraryKeysIn` are removed.

### The gate (measured in CI, not locally)

Colima is off limits for builders, so the recall gate runs in `coach-eval.yml`'s
`library-retrieval` job (local stack, real `gte-small`, real `search_library_v2`). Run it alone
without spend: Actions, Coach Eval, Run workflow, `retrieval_only`. Measured 2026-10-18 on the
branch (run 39080097067), 49 sources, 169 chunks, all embedded, 82 scored questions (61 single-topic,
15 multi-source, 6 follow-up; 10 no-answer are listed, not scored):

| Search | Mean recall in top 8 | All found | At least one | MRR |
|---|---|---|---|---|
| Hybrid (`search_library_v2`) | **0.917** | 84% | 98% | 0.878 |
| Vector only | 0.884 | 79% | 96% | 0.869 |
| Full-text only (terms ORed) | 0.860 | 74% | 96% | 0.773 |

By kind (hybrid): single 0.934, multi-source 0.811, follow-up 1.000. Regional sources shown to
athletes outside their region: 0 of 92 searches. The gate (mean recall at least 0.8, multi-source
at least 0.7, MRR at least 0.5, no regional leak) passes. For comparison, E2 measured the v1 hybrid at
0.929 on its 42 questions, where the fusion added nothing over the vectors (0.940 vector-only); the
question set has since grown with harder ones, and now the fusion is the best of the three. 13
questions still miss at least one expected source (listed in the job's output).

"Every citation points at a retrieved chunk" holds by construction: a reply that cites anything else
is refused and repaired, then replaced by the data summary (gateway, contract and reply-guard tests
in the Deno job). How often a model needs that repair is measured by the answer bank's `library`
category (6 cases on fixed chunks: guideline figure quoted as guidance, shrinking returns, a
consensus figure, two sources that differ, retrieval that found nothing, a follow-up), which needs a
gateway route and so runs locally with the `AI_COACH_CHAT_*` settings and an Anthropic key, not in
CI (no Anthropic key is stored there). Unsupported claims are the numbers check's job (a figure that
no excerpt, record or message holds is refused) and the bank's graders.

### Head-to-head: retrieval against the whole library in the cached prefix

The whole library (`_evals/library_full.ts`) is 85,246 characters: about 21,300 tokens at four
characters a token, 24,400 at 3.5. That is under the 60,000-token line, so the option was built, as
an evaluation arm only (Coach chat ships one path). Prices are the gateway's (`ai/models.ts`), the
extra input a turn adds beyond today's prompt:

| | Retrieval | Whole library in the prefix |
|---|---|---|
| Tokens a turn adds | about 1,300 to 1,500 (eight chunks, 616 characters each on average, plus the introduction), never cached | 21,300 to 24,400, cached |
| Haiku 5.5, cache hit | USD 0.00013 to 0.00015 | USD 0.00021 to 0.00024 |
| Haiku 5.5, cache miss | the same | USD 0.0027 to 0.0030 (cache write) |
| Sonnet 5.5, cache hit | USD 0.0026 to 0.0030 | USD 0.0021 to 0.0024 |
| Sonnet 5.5, cache miss | the same | USD 0.053 to 0.061 (cache write) |
| Sonnet 5.5, half the turns miss | USD 0.0026 to 0.0030 | USD 0.028 to 0.032 |

The cache lives five minutes, and a chat with a coach is a question now and another tomorrow, so most
turns that follow a pause are misses; with retrieval the library costs the same either way. Latency:
retrieval adds one embedding (about 70 ms once the model is loaded, from the E1 spike) and one
database call before the model is called, a few hundred milliseconds inside the 4-second limit; the
whole library adds 21,000 to 24,000 tokens to every uncached prefill (the athlete file changes
daily, so the prefix changes with it unless the library is placed before it). Quality: the script
`library_head_to_head.ts` answers the same questions end to end through the gateway in both arms and
reports citations of the expected sources, citation precision, repairs, cost, latency and cache
tokens (`library_head_to_head_metrics.ts` is tested). It needs a gateway route and an Anthropic key
and the retrieval database, so **it has not been run**: no quality numbers exist yet. Other
differences that do not depend on it: the whole library cannot honour the athlete's region (an `IN`
source would reach everyone unless there is one prefix per region), its prompt grows with every
source added (the design revisits at about 100,000 tokens), and with retrieval the citation guard
works from a short list of ids.

**Recommendation: keep retrieval.** The cost is about twenty times lower on a miss and about equal on a hit,
the region filter works, the guard's list of ids is short and it scales; the whole library has no
measured quality advantage to pay for. Re-run the script when the library nears 60,000 tokens or the
model changes.

### Owner and lead notes

- **Contract requests (lead):** Contract 6 v2 and Contract 7 v1.1 (above and in the program doc);
  `coach-eval.yml` gained the `retrieval_only` input and its description (builder-owned in the brief).
- **No topic filter.** The brief called for filtering by topic and population. Population is the
  region filter. A topic filter is supported by the function but Coach does not use it: the tags are
  free text and a hard filter drops the second source of a question that spans topics (15 of the 82
  questions need two or three). Recall is measured without it. Revisit with real traffic.
- **No country in the app yet.** Region comes from the account locale (`en-IN`) and time zone
  (`Asia/Kolkata`). An Indian athlete with a US locale and a US time zone is treated as outside India.
  A country on the profile is the real fix (E4).
- **Today's DeepSeek path does not retrieve** (it has no field to cite in); production uses the Claude
  route.
- **The first deploy needs no extra step:** the migration creates the function, the existing
  `library-embed` embeds new chunks, and coach-chat embeds each question itself. After the deploy,
  `select * from public.search_library_v2('protein per day', null, 3, null)` as `service_role` shows
  rows, and `coach_context_contributors` in the function log shows `library` rendered.

## E3.1: the engine's production pass (in review)

Branch `claude/rag-engine`, migration `20261018200044_library_search_v3.sql` (code 44, additive).
The engine fixes from the 2026-10-18 RAG audit (P1-2, P2-1, P2-2, P2-3, P2-5, P2-6 and the P3 items).
New sources, the licence field, new questions and the claim-support judge are other branches.

### What shipped

- **`search_library_v3`** (Contract 6 v3) beside v2, which stays for the Coach chat build deployed
  now (drop it in a cleanup migration once this is live). Rows add `vector_distance` (cosine distance
  to the question), `text_rank` (`ts_rank`, 0 when no term matched), `evidence_level`, `kind` and
  `library_version`, with `schema_version` 3. Vector search compares only chunks whose
  `embedding_model` equals the new `query_embedding_model` argument (required with an embedding).
  Every TypeScript caller (`live.ts`, `library_eval.ts`, `library_head_to_head.ts`) uses v3 and
  parses rows with one function, `libraryRowsOf`.
- **Relevance floor** (`relevantRows` in `_shared/library/retrieval.ts`, calibrated below). Two
  limits on the cosine distance: the turn shows excerpts only when its nearest chunk is within 0.15;
  then every chunk within 0.19 is shown. One per-row limit could not separate the two sets: the
  second or third source of a multi-topic question sits farther from it than the first, so a row
  limit tight enough to drop the no-answer questions' chunks cost multi-source recall, while the
  gate on the nearest chunk costs far less. A full-text rank is no part of this floor: on the
  106-source library a strong word match (`ts_rank` at least 0.006, as first calibrated on 49
  sources) let through as many out-of-library questions as it rescued answerable ones, so the first
  version's text rule was removed.
- **Word-search fallback floor** (`keywordRelevantRows`, `libraryKeywordFloor`). With no embedding
  there is no distance, and a word match is a weak sign: the strongest chunk of an answerable
  question and of an out-of-library one overlap in `ts_rank`. The fallback therefore shows rows
  only when the best chunk has a rank of at least 0.0055 **and** holds at least 35% of the
  question's distinct topic words (`termCoverage`: `topicTerms` of the query, matched on the first
  five letters of each word, so "sleeping" meets "sleep"); then every chunk ranked at least 0.002.
  No new SQL: the coverage is measured in TypeScript on the returned header and body.
- **Exact vector scan** (review fix). v3 never uses the HNSW index: an index scan returns the nearest
  vectors of every model and filters by `embedding_model`, region and topic afterwards, so vectors of
  an older model kept during a re-embedding could fill the candidate list and leave too few, or not
  the nearest, rows. Production calls always carried a region, which already took the exact path;
  the no-filter branch is gone, so all calls do. Chosen over a partial HNSW index per model (a new
  index and a changed query for every model, and it still needs the region and topic filters) and
  over pgvector's iterative scan (needs 0.8 and still approximates). At 351 chunks of 384
  dimensions the scan is about 135,000 multiply-adds, well under a millisecond; it is the right
  call into the low thousands of chunks, and the index would be worth revisiting beyond that.
  `library_search_v3_test.sql` forces index scans on and puts 40 nearer old-model chunks in the
  library: the current model's nearest rows still come back.
- **Loader and digest agree** (review fix). The digest includes each chunk's `token_count`, but the
  loader compared only ordinal, section, header and body, so a re-load that changed only a token
  count wrote nothing. Migration 44 redefines `private.library_replace_source` (same signature and
  grants): a text change re-writes the chunks as before; a token-count-only change updates them in
  place and keeps their embeddings. pgTAP covers it (the row, the digest, the version, the kept
  embedding).
- **Prefetch order** (review fix). Coach chat starts the question's embedding after the replay check
  and the budget reservation, just before `prepare_coach_chat_v9` is awaited, so a replay or a
  request at the usage limit never calls `library-embed` and the embedding still overlaps the context
  preparation (the saving over starting it in the contributor is the context step, not the two
  cheap reads before it). `handler_test.ts` checks the order and that a replay and a 429 start none.
- **Nothing passes: an explicit line.** The block then says no excerpt matched, that Coach must cite
  no library source and should say the evidence is not in Tracend's library rather than answering
  from memory (`libraryNoMatchText`). When the search ran on words alone it says the library could
  only be searched by keyword, and Coach must not claim the library lacks the topic
  (`libraryWordsOnlyText`). The answer bank's `library-found-nothing` case now gets the same block
  production gives.
- **Marker line** (P2-2, P2-3): `[source: <id>] <Kind>, <year>. Evidence: <evidence level>.` before
  the header. A "Practical reading" section, or any section whose title names Tracend's reading (for example "How it fits with other entries (Tracend's reading)"), is marked "Tracend's reading of this source (our
  interpretation and its limits), not a finding the source reports."; a chunk elsewhere that points
  to another entry ("see the ... entry", "in this library") is marked as holding Tracend's remark. 49
  of the 169 chunks are Practical reading sections and 1 more carries a cross-reference. Done in
  rendering, so nothing is re-embedded. The system prompt tells Coach to present a marked excerpt as
  our reading.
- **Latency** (P2-1). Coach chat starts the question's embedding after the replay check and the budget
  reservation (`prefetchLibraryEmbedding` in `live.ts`), so it runs while `prepare_coach_chat_v10` runs; the contributor reuses it when its query is that text (every
  question that is not a follow-up; a follow-up's query needs the prepared context, so it is
  embedded then). The 1.5-second deadline counts from the start of the embedding, and the word
  search fallback is unchanged (Contract 7 v1.2: `queryEmbedding` on the contributor input).
  `library-embed` keeps its service client for the isolate and remembers the last accepted worker
  secret by its SHA-256 for 5 minutes (`embed_service.ts`); a refused bearer always goes to the
  database and never evicts the accepted one. Safe because the secret changes only when Vault loses
  it (a restore), and the worst case is that a replaced secret works for 5 more minutes in a warm
  isolate.
- **Telemetry** (P2-1). One `library_retrieval` log line per turn, with the request's correlation
  id: `embed_ms`, `degraded` (`none`, `embedding_unavailable`, `embedding_timeout`), `prefetched`,
  `follow_up`, `candidates`, `shown` (source keys), `top_distance` and `library_version`. No question
  text, chunk text or health value. It replaces `library_retrieval_degraded` (Contract 7 v1.2: a
  contributor may return `trace`, which the host passes on as `traces[id]`).
- **Versioning** (P2-5). `private.library_sources.content_sha256`, kept current by triggers on both
  library tables (whatever writes the rows: the loader, a retire, the SQL editor) and back-filled by
  the migration; `private.library_version()` digests every source's key and digest into 16 hex
  characters; coach-chat stores it on the answer as `coach_messages.library_version` with the turn
  trace (`recordTurnTrace`). The version does not count embedding state, so it is the same before
  and after the worker embeds a chunk.
- **Retiring a source** (P2-5). Deploys load content only through migrations (`supabase db push`
  runs the generated `library_replace_source` blocks; no deploy step calls it), so retiring follows
  the same path: `build_migration.ts --retire <key>` prints a block that calls
  `private.library_retire_source(key)` (deletes the source and its chunks; false when no source has
  the key). `library_content_test.ts` fails while a migration still loads a source that `index.ts`
  no longer lists and no later retire block removes it, and when a retire follows a source's newest
  load.
- **P3 fixes.** A question with no ASCII word (Hindi in Devanagari, emoji) is never a follow-up, so
  it is not searched with an earlier question's words. On a 401 from `library-embed`, the query
  embedder reads the worker secret again and retries once. The search filters by `embedding_model`.
  `library-embed`'s catch-all logs every failure (`library_embed_failed` with its code) and sends at
  most one Sentry event per 30 minutes per isolate. The digest is shown to Coach without its source
  ids (`withoutSourceIds`; the authored file keeps them, and the test still checks every id exists):
  only retrieved excerpts are citable, so an id copied from the digest was a refused citation. That
  was simpler than making the digest's 46 ids citable, which would have meant shown text and labels
  for sources that were not retrieved. Digest version 3, 5,661 characters as shown.
- **Deploy check** (P3). `deploy.yml` gains a read-only **Library Check** job after the functions
  deploy (tag-release waits for it): through `supabase db query --linked` with the existing
  `SUPABASE_ACCESS_TOKEN`, it waits up to 20 minutes for `library_status_v1()` to reach
  embedded = chunks, then checks that a sample word search (`search_library_v3('protein per day',
  null, null, 3, null)`) returns rows.
- **The retrieval gate runs on library pull requests** (P2-6). `coach-eval.yml`'s
  `library-retrieval` job also runs on a pull request (opened, pushed, reopened) that changes
  `supabase/library/**`, `supabase/functions/_shared/library/**`, `library-embed/**`, the library
  evaluation and question files (`_evals/library_*`), the few shared modules the evaluation imports,
  `supabase/config.toml`, this workflow, or a migration that mentions the library (a small
  `library-changes` job decides). It is not a required check. The model jobs keep
  the label and manual runs; their concurrency group moved to the job.

### Relevance floor: calibration

Re-measured 2026-10-18 on the merged library, after the first calibration (49 sources, 92
questions) turned out too small: **106 sources, 351 chunks, all embedded, real `gte-small`**, in CI
(Coach Eval, `retrieval_only`; the pull request's own runs 39108987328, 39109648904 and 39110180961,
and a manual hold-out run 39110194476). `library_eval.ts` prints the distances, the sweeps and the
tables.

**Questions.** `library_questions.json` (the calibration set, which chooses every threshold) holds
219 questions: the 92 older ones (written against the first 49 sources) and 127 written blind for the
rest, from each source's title and topic and a lifter's point of view, never from its chunk text.
189 are answerable (147 single-source, 28 multi-source, 14 follow-ups; 28 are colloquial: gym slang,
typos, Indian English such as "how much protein for gaining in veg diet") and 30 are no-answer
questions near the library but outside it (medication, injury rehabilitation, specific diseases,
sport technique, pregnancy and postpartum, minors, eating disorders, medical reports). Every one of
the 106 sources is the expected answer of at least one calibration question.
`library_questions_holdout.json` holds 55 more (34 single, 8 multi-source, 5 follow-ups, 8
no-answer; 5 colloquial), written separately and phrased differently: 20% of the 274. It is run
once, with `EVAL_QUESTION_SET=holdout` (workflow input `question_set: holdout`), which prints the
tables and gates but none of the tuning output. It chose nothing.

**Calibration set** (hybrid search with the chosen floor is what Coach chat shows):

| | recall@8 | MRR | no-answer shown nothing | colloquial recall |
|---|---|---|---|---|
| Hybrid, no floor (v2 behaviour) | 0.890 | 0.801 to 0.802 | 0 of 30 | 0.810 |
| Hybrid, the first calibration's floor (0.16 / 0.19 / text 0.006) | 0.879 | 0.802 | 16 of 30 (53%) | 0.756 |
| **Hybrid, floor 0.15 / 0.19** | **0.855** | **0.774** | **27 of 30 (90%)** | 0.667 |
| Word search alone, no floor (old fallback) | 0.795 | 0.683 | 1 of 30 (3%) | 0.625 |
| Word search alone, the first calibration's floor (rank 0.006 per row) | 0.521 | 0.519 | 20 of 30 (67%) | 0.125 |
| **Word search alone, new floor (rank 0.0055, 35% of topic words)** | **0.611** | **0.549** | **22 of 30 (73%)** | 0.304 |

By kind with the chosen hybrid floor: single 0.859 (0.904 without), multi-source 0.780 (unchanged),
follow-up 0.964 (unchanged). Eight answerable questions are shown nothing. The three no-answer
questions still shown excerpts are metformin (nearest chunk 0.1475), ACL rehabilitation (0.1468) and
steroid cycles (0.1468): they sit as close to training and recovery chunks as covered questions do,
so no distance separates them; the prompt's precedence and medical-boundary rules still apply.
**The floor costs colloquial questions most** (0.810 to 0.667): typos and slang sit farther from the
chunks. 0.155 / 0.19 would give 0.756 for them and 0.869 overall, at 77% to 80% of the no-answer
questions (one question moved between runs); it is a one-line change if the owner prefers recall.

Distances: the nearest chunk of an expected source is at 0.074 to 0.187 (p50 0.106, p90 0.140); the
nearest chunk among the rows returned for a no-answer question is at 0.147 to 0.245 (p50 0.177,
p10 0.1475). The two groups overlap: three no-answer questions sit at 0.147 to 0.150, while
answerable questions reach 0.187. The nearest distance among the eight returned rows moves a little
between runs, because chunk ids (which break ties in the fused ranking) are new at every database
reset; recall and MRR moved by 0.001 to 0.01.

Hybrid sweep (calibration set, run 39110180961): nearest-chunk limit by row limit. The no-answer
share and the number of answerable questions shown nothing depend only on the nearest-chunk limit.
No text rule is part of it (see above).

| nearest-chunk limit | no-answer shown nothing | answerable shown nothing | row 0.150 | row 0.160 | row 0.170 | row 0.180 | row 0.190 | row 0.200 | row 0.210 |
|---|---|---|---|---|---|---|---|---|---|
| 0.130 | 100% | 31 | 0.743 | 0.757 | 0.765 | 0.771 | 0.771 | 0.771 | 0.771 |
| 0.135 | 100% | 25 | 0.755 | 0.770 | 0.778 | 0.785 | 0.785 | 0.785 | 0.785 |
| 0.140 | 100% | 18 | 0.772 | 0.790 | 0.803 | 0.810 | 0.810 | 0.810 | 0.810 |
| 0.145 | 100% | 12 | 0.795 | 0.817 | 0.832 | 0.840 | 0.840 | 0.842 | 0.842 |
| **0.150** | 90% | 8 | 0.802 | 0.832 | 0.848 | 0.855 | **0.855** | 0.858 | 0.858 |
| 0.155 | 77% | 5 | | 0.835 | 0.859 | 0.869 | 0.869 | 0.871 | 0.871 |
| 0.160 | 63% | 3 | | 0.843 | 0.869 | 0.879 | 0.879 | 0.882 | 0.882 |
| 0.165 | 63% | 3 | | | 0.869 | 0.879 | 0.879 | 0.882 | 0.882 |
| 0.170 | 63% | 3 | | | | 0.879 | 0.879 | 0.882 | 0.882 |
| 0.175 | 60% | 3 | | | | 0.879 | 0.879 | 0.882 | 0.882 |
| 0.180 | 43% | 3 | | | | 0.879 | 0.879 | 0.882 | 0.882 |

Why 0.15 / 0.19: the highest recall that left at least 90% of the no-answer questions with nothing
in both calibration runs (0.155 gave 77% in two of three runs, 80% in one). Row limits 0.18 to 0.21
give the same recall within 0.003; 0.19 keeps a margin for the second source of multi-topic
questions. The strong-text-rank rule removed from the floor, measured at 0.16 / 0.19: with it at
0.006 the no-answer share fell from 67% to 53% for no recall gain (0.879 either way); at 0.004 it
fell to 30%.

Word-search sweep (calibration set): recall / no-answer shown nothing, by the best chunk's `ts_rank`
(rows) and the share of the question's topic words it must hold (columns), row rank 0.002.

| best chunk's rank | coverage 0 | 0.20 | 0.25 | 0.30 | **0.35** | 0.40 | 0.45 | 0.50 |
|---|---|---|---|---|---|---|---|---|
| 0.0030 | 0.779 / 10% | 0.754 / 20% | 0.739 / 33% | 0.712 / 43% | 0.669 / 60% | 0.654 / 60% | 0.590 / 70% | 0.590 / 70% |
| 0.0035 | 0.776 / 13% | 0.751 / 20% | 0.736 / 33% | 0.709 / 43% | 0.667 / 60% | 0.652 / 60% | 0.590 / 70% | 0.590 / 70% |
| 0.0040 | 0.771 / 23% | 0.751 / 30% | 0.736 / 37% | 0.709 / 43% | 0.667 / 60% | 0.652 / 60% | 0.590 / 70% | 0.590 / 70% |
| 0.0045 | 0.729 / 37% | 0.713 / 40% | 0.701 / 43% | 0.686 / 50% | 0.654 / 63% | 0.650 / 63% | 0.590 / 73% | 0.590 / 73% |
| 0.0050 | 0.694 / 57% | 0.683 / 57% | 0.671 / 57% | 0.656 / 60% | 0.635 / 70% | 0.632 / 70% | 0.576 / 77% | 0.576 / 77% |
| **0.0055** | 0.645 / 63% | 0.639 / 63% | 0.634 / 63% | 0.622 / 67% | **0.611 / 73%** | 0.611 / 73% | 0.571 / 80% | 0.571 / 80% |
| 0.0060 | 0.597 / 67% | 0.592 / 67% | 0.586 / 67% | 0.581 / 70% | 0.571 / 77% | 0.571 / 77% | 0.547 / 80% | 0.547 / 80% |
| 0.0065 | 0.544 / 77% | 0.539 / 77% | 0.534 / 77% | 0.528 / 77% | 0.523 / 80% | 0.523 / 80% | 0.504 / 83% | 0.504 / 83% |
| 0.0070 | 0.484 / 80% | 0.479 / 80% | 0.474 / 80% | 0.468 / 80% | 0.463 / 80% | 0.463 / 80% | 0.455 / 83% | 0.455 / 83% |
| 0.0075 | 0.429 / 93% | 0.423 / 93% | 0.418 / 93% | 0.413 / 93% | 0.407 / 93% | 0.407 / 93% | 0.399 / 93% | 0.399 / 93% |
| 0.0080 | 0.331 / 93% | 0.331 / 93% | 0.331 / 93% | 0.325 / 93% | 0.320 / 93% | 0.320 / 93% | 0.320 / 93% | 0.320 / 93% |

The row rank (at 0.0055 and 0.35) changes little: 0 gives 0.611, 0.002 0.611, 0.003 0.608, 0.004
0.601, 0.005 0.571, all at 73%. **The word-search fallback cannot be brought back to its unfloored
recall (0.795) while most out-of-library questions show nothing.** The ts_rank of an answerable
question's best chunk (p10 0.004) overlaps the no-answer questions' (p50 0.005, p90 0.007), and
topic-word coverage separates them only partly. Coverage buys about 0.09 recall at a similar
no-answer share (0.635 at 70% against 0.544 at 77% by rank alone), and the two-part form (best
chunk, then rows) adds about 0.08 over the first calibration's per-row rank at the same 67%
(0.597), but the fallback stays far below the main path.
That is accepted because the fallback runs only when the embedding is unavailable, and its
block then says Coach must not claim the library lacks the topic. Rank 0.005 with the same coverage
gives 0.635 at exactly 70%; 0.0055 was chosen for margin over the gate.

**Hold-out set** (run 39110194476, 55 questions, chosen floors, run once, no retuning):

| | recall@8 | MRR | no-answer shown nothing |
|---|---|---|---|
| Hybrid, no floor | 0.897 | 0.822 | 0 of 8 |
| **Hybrid, floor 0.15 / 0.19** | **0.897** | **0.822** | **7 of 8 (88%)** |
| Word search alone, no floor | 0.805 | 0.673 | 0 of 8 |
| **Word search alone, new floor** | **0.613** | **0.542** | **5 of 8 (63%)** |

By kind with the hybrid floor: single 0.941, multi-source 0.646 (8 questions; 0.646 without a floor
too), follow-up 1.000, colloquial 1.000 (5 questions). The one no-answer question shown excerpts
asks at what age children should start strength sessions (nearest 0.149). **Two gates are not met on
the hold-out set**, and the run failed on them: multi-source recall 0.646 against 0.7, and
word-search no-answer precision 0.625 against 0.7 (5 of 8; the calibration set gave 73%, 22 of 30).
The floor did not cause the first (it equals the unfloored hybrid); the second is the fallback's
limit described above, on only 8 questions. Neither gate was moved. Eight multi-source questions
and eight no-answer questions are small samples, and the set was not tuned on; the calibration set
passes every gate (recall 0.855, multi-source 0.780, MRR 0.774, no-answer 0.900, word-search recall
0.611, word-search no-answer 0.733).

`library_eval.ts` gates, all measured with the floors: recall 0.8, multi-source recall 0.7, MRR 0.5,
no-answer precision 0.7 (`EVAL_MIN_NO_ANSWER_PRECISION`), and for the word-search fallback recall 0.55
(`EVAL_MIN_KEYWORD_RECALL`) and no-answer precision 0.7 (`EVAL_MIN_KEYWORD_NO_ANSWER_PRECISION`).
The workflow step now runs with `pipefail`, so a gate failure fails the job (it used to be hidden by
`tee`). Thirty no-answer questions are still few: one question is 3.3 points. Re-run the sweep when
the library or the question set grows, on the calibration set only, and keep the hold-out set for
confirming the result once.

### Not done, and why

- **Follow-ups anchored on the Coach's previous reply** (P3, "if cheap and measurable"). Not
  measurable here: no retrieval question carries a previous Coach reply, and the question file
  belongs to another branch. A reply is model text that often spans several topics, so adding it to
  the query could pull the search off the athlete's question; measure it with follow-up questions
  that carry a reply before building it.
- **The answer bank's fixed rows carry no scores, kind or evidence level**
  (`_evals/coach_bank/harness.ts`, another branch's file). They are shown as given (unscored rows
  pass the floor) and their marker line shows only the year; the bank's chunks therefore do not get
  the Tracend's-reading mark from the section. `LibraryRow` takes `section`, `kind` and
  `evidenceLevel` when the harness passes them.
- **The digest's sources stay uncitable** rather than made citable (above).

### Gates

`./scripts/deno.sh fmt --check supabase/functions`, `lint` and `test --allow-env --allow-net
--allow-read=supabase/migrations,site/src/config.ts supabase/functions` pass. pgTAP
`library_search_v3_test.sql` (38 assertions: grants, the v3 keys and schema version, cosine
distances, the model filter, text ranks, the embedding-model requirement, evidence level and kind,
regions, the content digest and when it changes, the version, loading and retiring, and the
library version on a Coach answer) runs in CI. The legacy DeepSeek request digests
(`coach_chat_parity_test.ts`) were recorded again because the digest's persona line changed (the
only prompt edits are the persona's digest line and two library-rule bullets; the structured-output
schema is untouched, and `coach_chat_schema_test.ts` still passes: 0 optional keys, 0 unions, under
3,100 bytes). The branch was rebased onto `main` after #151, #152 and #155; migration 44 still sorts
after every migration there (`check-migration-order.sh origin/main`).

### After the deploy

- Run Coach Eval with `retrieval_only` on `main`.
- In the function logs, `library_retrieval` lines should show `prefetched: true` on most turns and a
  low `embed_ms`; `degraded` other than `none` points at `library-embed` (cold load or errors).
- `select library_version, count(*) from public.coach_messages where library_version is not null
  group by 1;` in the SQL editor shows which library content answers were given from.
- Once no deployed code calls `search_library_v2`, drop it in a cleanup migration.

## E4: regional modules (in review)

Branch `claude/regional-modules`, migration `20261023120044_regional_modules.sql` (code 44, additive).
Decision D5: a global audience, with nutrition and body-measure modules for India, the United
States, the United Kingdom and Australia chosen by the athlete's region.

### What shipped

- **The athlete's country.** `user_accounts.country_code`, optional (null, or two capital letters).
  The app reads and writes it only through `get_my_country_v1()` and `set_my_country_v1(p_country_code)`
  (security definer, authenticated only, both `{schema_version: "1.1", country_code, effective_regions}`
  built by `private.my_country_answer`; `effective_regions` is the sorted list the library search uses
  for the athlete now, so "Not set" on an Indian time zone reads `["IN", "global"]`; a blank code clears
  the choice; the set accepts only the codes the app offers, AU, IN, GB, US and ZZ, and raises `22023`
  for anything else; a signed-out caller gets `42501`; an actual change writes an `account.country.changed`
  audit event with the old and new code, a repeat writes none); clients cannot write the column. `private.library_regions_for_account` (the one function both searches call) is redefined
  with the same signature and grants: a stored country gives `['global', <country>]`; with none it
  behaves exactly as before (locale country, and `IN` for an Indian time zone). `ZZ` is the athlete's
  answer "another country" (ISO's user-assigned code): it sees global sources only and is not
  guessed back into India from the time zone. Export is automatic (`select *`) and deletion cascades.
- **The app.** Account has a **Region** section with one optional row, **Country** (Australia, India,
  United Kingdom, United States, Another country, Not set). It says what it does and reads the server's `effective_regions`
  ("Not set · Coach uses guidance that applies everywhere" only when nothing but global is in effect;
  "Not set · Coach goes by your time zone or language (India)" when the account's time zone or language
  still selects a country; "India · Coach can cite India's national guidelines") and that no plan number
  changes. Files: `lib/features/account/region_repository.dart`,
  `lib/features/account/widgets/region_settings.dart`; `AccountScreen` takes a `region` repository
  (fixture by default). With nothing chosen the app and the search behave as before. Needs a reinstall
  of the app to show the row; the migration must deploy first (the row shows "Could not be read" until
  the RPCs exist).
- **Eight sources** in `supabase/library/sources/regional.ts` (114 in all). Each of the four regions
  now has a nutrition source and a body-measure source (BMI and waist, including the points that differ
  for people of Asian origin); a content test enforces it.

| Key | Region | Citation | Link | Licence | Verbatim | Read from |
|---|---|---|---|---|---|---|
| nhs_2026_overweight_obesity_adults | GB | NHS, Overweight and obesity in adults (page reviewed 29 April 2026) | nhs.uk/conditions/obesity | proprietary (NHS terms of use not readable here; the OGL claim was not confirmed) | no | full page |
| phe_2018_quick_guide_healthy_eating | GB | Public Health England 2018, A Quick Guide to the Government's Healthy Eating Recommendations | assets.publishing.service.gov.uk (PDF) | OGL-UK-3.0 (stated in the PDF) | yes | full document |
| phe_2016_government_dietary_recommendations | GB | Public Health England 2016, Government Dietary Recommendations | assets.publishing.service.gov.uk (PDF) | OGL-UK-3.0 (stated in the PDF) | yes | full document |
| nhlbi_2000_practical_guide_obesity | US | NHLBI and NAASO 2000, The Practical Guide (NIH 00-4084) | nhlbi.nih.gov/files/docs/guidelines/prctgd_c.pdf | proprietary (federal publication with a non-government co-sponsor and no rights notice in the text) | no | full document |
| nhmrc_2013_australian_dietary_guidelines | AU | NHMRC 2013, Australian Dietary Guidelines | eatforhealth.gov.au/guidelines/australian-dietary-guidelines-1-5 | proprietary (the WHO-hosted copy read here allows personal and internal non-commercial use only) | no | full document (WHO-hosted copy) |
| nhmrc_nz_2006_nrv_protein | AU | NHMRC, Australian Department of Health and NZ Ministry of Health 2006, Nutrient Reference Values: Protein (page updated 9 April 2014) | eatforhealth.gov.au/nutrient-reference-values/nutrients/protein | proprietary (no notice readable) | no | archived copy of 3 November 2022 |
| au_health_2021_adult_activity_guidelines | AU | Australian Department of Health, Disability and Ageing, activity guidelines for adults 18 to 64 (updated 10 May 2021) | health.gov.au/topics/physical-activity-and-exercise/... | proprietary (no notice readable) | no | archived copy of March 2026 |
| who_2011_waist_circumference_report | global | WHO 2011, Waist circumference and waist-hip ratio (consultation Dec 2008) | who.int/publications/i/item/9789241501491 | proprietary (copyright notice requires permission) | no | WHO library copy via the Internet Archive |

Every summary is in Tracend's own words, with its own order and structure rather than the source's
sentences (the first draft followed the NIH guide and the PHE documents too closely and was rewritten
after review). The two UK documents allow short quotation (OGL); nothing is quoted from any source.
Figures come only from what was read: the NHS page (BMI 23 to 27.4
overweight and 27.5 or more obese for South Asian, Chinese, other Asian, Middle Eastern, Black African
and African-Caribbean adults; waist under half of height when BMI is under 35), the NHLBI guide (waist
lines of 40 and 35 inches), the ADG (serves, BMI bands, waist 80/88 cm and 94/102 cm, the notes on
Asian and Polynesian origin), the NRV page (0.68 and 0.60 g/kg EAR, 0.84 and 0.75 g/kg RDI) and the
UK tables (55.5 and 45 g protein a day, 30 g fibre).

### Figures checked against the copy read

Each number in the Australian and WHO entries was found again, by text search, in the copy that was read
(2026-10-23):

| Entry | Copy read | Figures confirmed |
|---|---|---|
| NHMRC and NZ MoH 2006, NRV protein | web.archive.org/web/20221103015557/https://www.nrv.gov.au/nutrients/protein | adults 19-70: average requirement 0.68 (men) and 0.60 (women) g/kg, recommended intake 0.84 and 0.75 g/kg, 64 and 46 g a day; over 70: 0.86 and 0.75, then 1.07 and 0.94 g/kg, the 25 percent rise and its limited evidence; no upper level in grams, 25 percent of energy; about 33 percent of intake from meat, poultry and fish, about 25 percent from cereals; page updated 9 April 2014 |
| NHMRC 2013, Australian Dietary Guidelines | extranet.who.int/ncdccs/Data/AUS_B18_n55_australian_dietary_guidelines.pdf (WHO-hosted copy) | BMI bands 18.5, 25, 30; waist 80/88 cm (women) and 94/102 cm (men); the Asian-origin and Polynesian-origin notes; the over-70 note; check weight and waist every 2 to 3 months; serves table (3 and 2.5 at 19-50, 2.5 and 2 from 51); serve sizes 65 g, 80 g, 100 g, 2 eggs, 1 cup (150 g), 170 g |
| Australian Dept of Health, adults 18-64 | web.archive.org/web/20260310033757/https://www.health.gov.au/topics/physical-activity-and-exercise/physical-activity-and-exercise-guidelines-for-all-australians/for-adults-18-to-64-years | 2.5 to 5 hours moderate, 1.25 to 2.5 hours vigorous, strength on at least 2 days, the named activities, page updated 10 May 2021 |
| WHO 2011, waist circumference | web.archive.org/web/20150209033722/http://whqlibdoc.who.int:80/publications/2011/9789241501491_eng.pdf | Annex A cut-offs 94/80 and 102/88 cm and their Dutch-sample origin, IDF 94/80 and 90/80 cm, US cholesterol programme 102/88 cm, the STEPS and US measuring sites, more visceral fat in Asian populations, no universal cut-offs; the publication date (16 May 2011) is from the who.int item page |

### Considered and left out

- **NICE NG246 (UK obesity guideline, 2025).** The NICE site and its mirror returned 403 from here,
  and the BMJ summary has no abstract in Europe PMC, so none of its numbers could be read. The NHS page
  states the same lower BMI points for the same groups, so it covers the need. Add NICE when someone
  can read it.
- **CDC adult BMI categories page** (403 from here); the NIH guide covers the US bands.
- **NHMRC 2013 obesity guidelines** are rescinded (2019); the ADG chapter, which carries the BMI and waist
  lines, is used instead.
- **AIHW "Overweight and obesity" pages**: only an archived 2020 copy could be read and it repeats the
  ADG's waist table, so it adds nothing.
- **Australian Dietary Guidelines licence.** A search result suggested a later reissue under CC BY 4.0, but
  that was not read; the stricter notice on the copy that was read applies.
- Canada, Singapore, Japan, Brazil and others: D5 names four regions; a new region is a source file and
  a country entry in `regionalModuleCountries`.

### Tests

- `library_content_test.ts`: AU is a known region; each of IN, US, GB and AU has a nutrition and a
  body-measure source; the migration carries every source's current content (it failed when a summary was
  edited after the migration was generated, as designed).
- `library_questions.json`: 17 questions asked from GB, US, AU (and two with no region), each
  expecting its source; the existing content, region and no-athlete-data tests check them. The
  regional-isolation gate in `library_eval.ts` fails if a regional source reaches an athlete outside its
  region.
- pgTAP `regional_modules_test.sql` (42 assertions: the regions in effect with and without a country, a
  code the app does not offer is refused) and `library_ingestion_test.sql` (AU allowed); Flutter
  `contract/region_contract_test.dart` (fixtures `my_country_v1_1.json`, `my_country_unset_v1_1.json`) and
  `region_settings_test.dart` (a time-zone country is named, not hidden).
- `library_full_test.ts`: before E4 the 106 sources render to 201,482 characters (57,566 tokens at 3.5
  characters a token); with E4, 114 sources and 220,432 characters (62,981 tokens). The 60,000 line guards
  only the shelved whole-library evaluation and is now 70,000 (owner decision below).

### Measured in CI (PR #164)

The library retrieval gate ran on the 236 calibration questions with 114 sources: mean recall in the
top 8 with the floor 0.867 (206 scored questions; 0.855 before E4), multi-source 0.787, MRR 0.792,
follow-ups 0.964, 27 of 30 no-answer questions shown nothing (90%), and no regional source reached an
athlete outside its region (0 leaks). All 17 regional questions found their expected source. The
pgTAP file `regional_modules_test.sql` (37 assertions) passes; on a scratch branch
(`feature/e4-pgtap-before`, deleted) with the migration minus the regions function it failed exactly
the four assertions about a stored country (30, 31, 32 and 35).

### Decisions for the owner

1. **Which regions ship first.** The four D5 names, all built. Canada, the EU and others wait for a
   request; each is a source file and a line in `regionalModuleCountries`.
2. **UK's NICE guideline is not in the library** (could not be read). The NHS page stands in.
3. **Country is optional and the app does not ask in onboarding.** The row sits in Account. Asking in
   onboarding needs `onboarding_flow.dart` (see "Follow-up after #162").
4. **A country changes citations, not numbers.** No calorie, protein or safe-range rule reads it. A
   regional BMI floor or a lower "high BMI" point for Asian-origin athletes in the plan's rules
   (ALGORITHMS.md uses BMI 18.5 and 25 for everyone) would be a rule change and is not made here.
5. **The 60,000-token line for the whole library is now 70,000.** Retrieval does not depend on it; the line guards only the shelved whole-library evaluation.
6. **Summary-only licences.** Six of the eight are `proprietary` on purpose: where a notice could not be
   read or was restrictive, the stricter reading applies, as in E2.2.
7. **ADG and NRV are under NHMRC review** (the dietary guidelines were reported to be under revision
   and a public consultation on the nutrient reference values was reported for early 2026; neither was
   read here). Re-read both when NHMRC publishes.

### Follow-up after #162

PR #162 owns `onboarding_flow.dart`, the rules plan, `catalog.ts`, `answers.ts`, `prescription.ts`,
`volume.ts`, `templates/*` and the redefinitions of `private.next_session_targets` and
`get_coach_plan_state_v1`. After it merges:

- Add an optional **Country** step to onboarding that calls `SupabaseRegionRepository.save` (the same
  RPC; skipping leaves null). A draft needs no new key: the answer is stored by the RPC, not by the
  onboarding answers.
- If the rules plan should ever vary by region (for example protein basis or BMI points), read
  `user_accounts.country_code` in `onboarding-plan`'s handler beside `timezone` (the handler already reads
  `user_accounts`). Not needed for E4.
- E5 (plan explanations citing sources) can pass the athlete's id to `search_library_v3` and the region
  follows from the stored country.

### After the deploy

- `select country_code, count(*) from public.user_accounts group by 1;` (SQL editor, read-only) is all
  null until athletes choose.
- `select public.library_status_v1();` should reach `embedded_chunks = chunks` (the eight sources add
  29 chunks, 380 in all) in about ten minutes, as in E2.
- Install the app from the merged commit to get the Region row; the migration deploys first.

## E5: plan explanations that cite sources (in review)

Branch `claude/e5-plan-explanations`. No migration and no change to any RPC or table: the proposal's
`evidence` column already takes any list of items, and the search is `search_library_v3` as E3.1 left
it. Deterministic plan numbers stay authoritative; the library only supplies the reasons.

### What shipped

- **Coach chat, "why is my plan like this?"** `isPlanExplanationQuestion`
  (`_shared/library/plan_explanation.ts`, deterministic: the question names the plan or a part of it,
  and asks for a reason) marks the turn. "Why is my plan like this?" has no topic of its own for the
  search (and "this" even reads as a follow-up), so the contributor makes a second search beside the
  question as asked: `libraryRetrievalQuery` returns the question as `text` and, in `planText`, the
  question with what a plan is made of added (`planTopicText`: training days, weekly sets per muscle,
  rep ranges, rest, effort and reps in reserve, progression, and the goal's nutrition topic). The two
  result lists are merged (`interleave`: a chunk once, the first search's first). The first CI run
  showed why one enriched query is not enough: it found 0.54 of the expected sources against 0.29 for
  the bare question, but missed questions about one part of the plan ("why do I rest so long?") that
  the added topics diluted; the as-asked search keeps those. The plan facts (`planFactsFrom`,
  `_shared/library/plan_facts.ts`: counts and enumerated values only, never an exercise name, a load,
  a weight or a date) come from the plan state and the goal inputs, read once for the turn and shared
  with the plan and goal-phase sections (`sharedRead`; the goal phase contributor now reads its inputs
  under the key `goal_phase_inputs`). Both searches run for this athlete (their id, so the region
  follows from the stored country, E4). Facts that fail or take over 0.8 s leave the general topics of
  a plan in the second query; the turn is never held up. The first search reuses the embedding started
  with the request (a question that reads as a follow-up, like "Why is my plan like this?", is embedded
  when its context is known, as for any follow-up); the second embeds its own text in parallel.
- **What Coach is told.** The library block of a plan turn adds a fixed note (no figure, grounds
  nothing): explain from the plan's own numbers and Tracend's rules first, use the excerpts for the
  reasoning behind them, cite the source of each, say plainly when a part of the plan has no excerpt
  behind it, an excerpt never changes a number. With nothing close enough the block says the
  explanation rests on the plan's rules and is less certain, cite no library source, no answer from
  memory (`libraryPlanNoMatchText`; the words-only variant does not claim the library lacks the topic).
  A plan turn's block is built when either of its two searches works; when both fail it renders
  `libraryPlanUnavailableText` (say you could not check the research); on any other turn a failing
  search still leaves the library out. Citing, the
  `citation_not_retrieved` guard and figure grounding are E3's, unchanged.
- **Onboarding plan.** `onboarding-plan` searches the library before it builds the gateway prompt
  (`retrievePlanLibrary`, `_shared/library/plan_library.ts`): two searches in parallel, one for how
  the training is built and one for what the nutrition targets rest on, from the enumerated answers
  (goal, experience, training days, session length, focus muscles; the athlete's free text never
  enters a query), each embedded by `library-embed` within 1.5 s and searched for the athlete's id with
  the same relevance floor as Coach. The rows alternate between the two searches, a chunk once, whole
  chunks only, within 6,000 characters (about 1,700 tokens); the whole retrieval has a 4 s deadline and
  never throws. The rules about the excerpts go in the cached system prompt (one of three variants by
  what was found), the excerpts in the user message, so the cost ceiling counts them. The model may
  list source ids in a new `sources` field (the gateway's JSON schema gains it, required, a list of
  strings; the settings path's prompt and shape are unchanged and `sources` is optional when parsed).
  `validateOnboardingPlan` refuses an id the prompt did not show (`source_not_retrieved`, repaired by
  name once like any rule), and so does the gateway when the plan's text prints an unshown id or names
  a study or an institution's document that was not shown (`unshownKeysIn`, `unshownStudies`). A cited
  source becomes an evidence item `{code: <id>, label: "<retrieved title> (<year>)", source: "library"}`
  on the proposal, labelled from the retrieval, never from the model's words.
- **Missing hits lower confidence and say so.** A plan from the model that cites nothing adds a line
  to "Not known yet" ("No research source is cited for this plan; its numbers come from Tracend's safe
  ranges and your answers", or "The research library could not be searched for this plan, so it cites
  no source; ..."). When the search found nothing close enough, or failed, confidence also drops to
  low (it was never above medium: first estimates). Excerpts shown but not cited leave confidence as
  it was and only add the line. The rules plan and the settings path are built without the library
  and are unchanged: the plan must stand when the library does not.
- **The app.** The plan screen reads the proposal's `evidence` and, when the plan cites sources,
  shows an `EvidenceAccordion` "Research behind this plan" under "Why this plan" listing the labels
  (`OnboardingProposal.librarySources`). It cites nothing and shows nothing otherwise. Needs a reinstall
  to show it; nothing breaks on older builds (they ignore `evidence`).

### What `onboarding-propose-plan` is

The task for E5 named `onboarding-propose-plan`, which is the Phase-2 mock kept for installed older
builds (a fixed plan with fixed wording, no model). The onboarding plan the app now builds, the one
whose explanation (`rationale`, `assessment`, ...) a model writes, is `onboarding-plan`; E5 is there.
The mock keeps its fixed text and cites nothing.

### Tests

- Deno: `plan_explanation_test.ts` (the intent in both directions, the topics, the query, the
  onboarding queries), `plan_facts_test.ts`, `plan_library_test.ts` (both searches for this
  athlete's id, floor, one search failing, both failing, the deadline, embedding failure and lateness,
  the budget, the merge, the rules), `retrieval_test.ts` (the contributor on plan turns: the
  the two searches, facts failing or late, the notes, one or both searches failing, budget, prefetch reuse),
  `plan_contract_library_test.ts` (parsing, `source_not_retrieved`, evidence and labels,
  confidence and the note, the rules plan unchanged), `onboarding-plan/gateway_test.ts` (the prompt,
  the citation in the stored proposal, repair of an invented id or study, no excerpt, library
  unavailable, no wiring, no route, provider failure), `goal_phase_test.ts` (shared read).
- Retrieval gate (CI, `library_eval.ts`): a separate set, `library_questions_plan.json`, is scored with
  the floor as it stands: 12 plan questions with their plan facts, once as the bare question and once
  as Coach searches them (two searches merged), failing under `EVAL_MIN_PLAN_RECALL` (default 0.5); and
  5 athletes' answers through the onboarding plan's two searches against the sources a good plan
  prompt needs, failing under `EVAL_MIN_ONBOARDING_RECALL` (default 0.4). The calibration and
  hold-out sets are untouched.
- Flutter: `phase_2_flow_test.dart` ("Research behind the plan": listed, absent, parsing).

### Decisions and limits

1. **Region.** Nothing new: the search takes the athlete's id and `search_library_v3` applies
   `private.library_regions_for_account` (stored country, E4). A pgTAP test is not added: no SQL changed.
2. **The retrieval is for the gateway route only**, like E3. The settings (DeepSeek rollback) path
   builds the plan as before, byte for byte (the golden requests still match).
3. **The goal's nutrition topic is always added** to a plan question's search (when the athlete has
   a goal), so a general "why is my plan like this?" also finds the protein and energy sources; a
   question about one part of the plan carries its own topic as well.
4. **No citation in the plan text.** The model puts ids in `sources` and never in prose; the app lists
   the labels under "Why this plan", not inline.

## Next agent starts here

E5 (above) reused `libraryRetrievalQuery`, the contributor, `relevantRows` and the `library`
evidence source; the athlete's region follows their stored country. The next step there is to read the
CI plan-question recall and the `onboarding_library` log lines after the first athletes build plans,
and to tune `planTopicText` (one fixed string) if a topic is missed. A source removed from `index.ts` needs a retire block in the same migration
(`build_migration.ts --retire`). The retrieval gate runs by itself on library pull requests; re-run the
floor sweep in its output when the question set or the library grows. Decide whether retrieval should
skip or down-rank `supersededBy` sources (the field lives in the content files only). Add NICE NG246 for
the UK when it can be read; re-read the NHMRC pages after its reviews.
