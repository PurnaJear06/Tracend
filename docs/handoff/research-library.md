# Research Library Handoff

**As of:** 2026-10-18

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

A hybrid (full-text plus gte-small vector) research library behind Coach answers and plan explanations. Rules still decide every number.

## Chunks

E1 (Phase 1); E2, E3 (Phase 3); E4, E5 (Phase 4)

E2 (Phase 3, round 2) merged (#135); E2.1, its follow-up with 14 more sources, is merged. E3 (the library in every Coach reply) is in review. See the sections below.

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
are stored. 15 sources are CC BY, 3 CC BY-NC, 2 CC BY-NC-ND, 15 publisher copyright.

Areas: Training 14, Joint-friendly 3, Nutrition 9, Cardio and activity 4, Recovery and sleep 3,
Screening 2. Ten of B1's twelve external sources are reused (ACSM 2009, 2011, 2026; Schoenfeld 2017, 2021;
Iversen 2021; Pelland 2026; Singer 2024; Zourdos 2016; Robinson 2024). Baz-Valle 2022 and Helms
2016 are left out because Schoenfeld 2017, Pelland and Zourdos already cover them.

| Key | Area | Citation | DOI or link | Licence | Region | Topics | Why chosen |
|---|---|---|---|---|---|---|---|
| acsm_2009_progression | Training | ACSM 2009 | doi:10.1249/MSS.0b013e3181915670 | Publisher copyright | global | training, strength, hypertrophy, progression, frequency, rest, intensity | The long-standing reference for how a lifter's training should progress with experience; Tracend's standard cites it, and Coach needs to explain where beginner and advanced advice differ. |
| acsm_2026_resistance_prescription | Training | Currier et al. 2026 (ACSM) | doi:10.1249/MSS.0000000000003897 | CC BY-NC-ND | global | training, strength, hypertrophy, volume, intensity, progression, frequency | The newest and broadest synthesis of what actually changes results in resistance training; it updates the 2009 stand and is the best single reference for the question 'what matters and what does not'. |
| schoenfeld_2017_weekly_volume | Training | Schoenfeld et al. 2017 | doi:10.1080/02640414.2016.1210197 | Publisher copyright | global | training, hypertrophy, volume | The classic answer to 'how many sets per week?'; Tracend's volume ranges cite it, so Coach needs a plain explanation of the dose-response finding and its limits. |
| schoenfeld_2021_loading_continuum | Training | Schoenfeld et al. 2021 | doi:10.3390/sports9020032 | CC BY 4.0 | global | training, strength, hypertrophy, intensity | Explains why a wide span of rep ranges works, which is the evidence behind letting people train with loads they enjoy and tolerate; Tracend's rep-range rules cite it. |
| pelland_2026_volume_frequency | Training | Pelland et al. 2026 | doi:10.1007/s40279-025-02344-w | Publisher copyright | global | training, hypertrophy, strength, volume, frequency | The most recent and detailed analysis of weekly volume and frequency together, showing diminishing returns; it keeps Coach from overselling 'more sets'. |
| singer_2024_rest_intervals | Training | Singer et al. 2024 | doi:10.3389/fspor.2024.1429789 | CC BY 4.0 | global | training, hypertrophy, rest, time-efficient | Gives a practical, evidence-based answer to 'how long should I rest between sets?', which matters for time-pressed users. |
| zourdos_2016_rir_scale | Training | Zourdos et al. 2016 | doi:10.1519/JSC.0000000000001049 | Publisher copyright | global | training, intensity, rir, progression | The origin of the repetitions-in-reserve effort scale that Tracend's plans use; Coach needs to explain what 'reps in reserve' means and how reliable it is. |
| robinson_2024_proximity_to_failure | Training | Robinson et al. 2024 | doi:10.1007/s40279-024-02069-2 | Publisher copyright | global | training, hypertrophy, strength, intensity, rir | The best available analysis of how close to failure to train, the basis for Tracend's reps-in-reserve targets. |
| iversen_2021_time_efficient | Training | Iversen et al. 2021 | doi:10.1007/s40279-021-01490-1 | CC BY 4.0 | global | training, time-efficient, volume, strength, hypertrophy, frequency | Directly answers the most common barrier, lack of time, with concrete choices on exercises, sets, warm-ups and techniques that save minutes. |
| schoenfeld_2016_frequency_hypertrophy | Training | Schoenfeld et al. 2016 | doi:10.1007/s40279-016-0543-8 | Publisher copyright | global | training, hypertrophy, frequency | The reason Coach can say each muscle is best trained at least twice a week when volume is equal, a core split-design rule. |
| grgic_2018_frequency_strength | Training | Grgic et al. 2018 | doi:10.1007/s40279-018-0872-x | Publisher copyright | global | training, strength, frequency, volume | Shows that for strength the benefit of training more often comes mostly from the extra volume, helping Coach advise people with limited gym days. |
| bell_2023_deloading | Training | Bell et al. 2023 | doi:10.1186/s40798-023-00633-0 | CC BY 4.0 | global | training, deload, recovery, progression | Deloading is widely used but lightly researched; this is the only structured consensus, so it lets Coach describe deloads honestly as expert practice. |
| lopez_2021_load_network | Training | Lopez et al. 2021 | doi:10.1249/MSS.0000000000002585 | CC BY-NC-ND | global | training, hypertrophy, strength, intensity, joint-friendly | Backs the advice that lighter loads still build muscle when taken to failure, important for people who need joint-friendlier training. |
| schumann_2022_concurrent_training | Training | Schumann et al. 2022 | doi:10.1007/s40279-021-01587-7 | CC BY 4.0 | global | training, cardio, strength, hypertrophy, concurrent-training | Settles the common worry that cardio kills muscle gains, so Coach can advise people who want both. |
| schoenfeld_2020_range_of_motion | Joint-friendly | Schoenfeld and Grgic 2020 | doi:10.1177/2050312120901559 | CC BY-NC | global | training, hypertrophy, joint-friendly, exercise-selection | Answers whether partial range of motion is a fair swap when a full range bothers a joint, using the best controlled evidence available. |
| lauersen_2014_injury_prevention | Joint-friendly | Lauersen et al. 2014 | doi:10.1136/bjsports-2013-092538 | Publisher copyright | global | injury-prevention, joint-friendly, strength, training | The strongest evidence that regular strength training itself lowers injury risk, which supports telling users that building strength protects joints. |
| gabbett_2016_training_load | Joint-friendly | Gabbett 2016 | doi:10.1136/bjsports-2015-095788 | CC BY-NC | global | injury-prevention, joint-friendly, training, progression, load-management | Explains why gradual load increases protect against injury and why too little training is also a risk, the logic behind Tracend's progression caps. |
| jager_2017_protein | Nutrition | Jäger et al. 2017 (ISSN) | doi:10.1186/s12970-017-0177-8 | CC BY 4.0 | global | nutrition, protein, hypertrophy, body-composition, timing | The standard open position on daily protein for people who train; it grounds the protein targets Coach explains. |
| kerksick_2017_nutrient_timing | Nutrition | Kerksick et al. 2017 (ISSN) | doi:10.1186/s12970-017-0189-4 | CC BY 4.0 | global | nutrition, timing, protein, carbohydrate, recovery | Answers the very common 'does meal timing matter?' with a clear order of priorities; useful for keeping advice proportionate. |
| schoenfeld_2018_protein_per_meal | Nutrition | Schoenfeld and Aragon 2018 | doi:10.1186/s12970-018-0215-1 | CC BY 4.0 | global | nutrition, protein, timing, hypertrophy | Corrects the myth that the body can only use about 25 grams of protein per meal, so Coach can give sensible meal-by-meal protein advice. |
| morton_2018_protein_supplementation | Nutrition | Morton et al. 2018 | doi:10.1136/bjsports-2017-097608 | CC BY-NC | global | nutrition, protein, hypertrophy, strength, supplements | The key evidence for the point where more protein stops adding muscle (about 1.6 g/kg/day), which sets a sensible ceiling for the advice. |
| aragon_2017_diets_body_composition | Nutrition | Aragon et al. 2017 (ISSN) | doi:10.1186/s12970-017-0174-y | CC BY 4.0 | global | nutrition, energy-balance, body-composition, protein, fat-loss | The best open statement on how energy balance and diet style change body composition, backing Tracend's focus on calories, protein and adherence over diet branding. |
| helms_2014_contest_prep | Nutrition | Helms et al. 2014 | doi:10.1186/1550-2783-11-20 | CC BY 4.0 | global | nutrition, energy-balance, body-composition, protein, fat-loss, supplements | The most practical open source on the rate of weight loss and diet make-up when a lean person wants to lose fat and keep muscle. |
| kreider_2017_creatine | Nutrition | Kreider et al. 2017 (ISSN) | doi:10.1186/s12970-017-0173-z | CC BY 4.0 | global | nutrition, creatine, supplements, strength, safety | Creatine is the best-supported training supplement; this open position stand covers both benefit and safety, which Coach needs for honest answers. |
| guest_2021_caffeine | Nutrition | Guest et al. 2021 (ISSN) | doi:10.1186/s12970-020-00383-4 | CC BY 4.0 | global | nutrition, caffeine, supplements, performance, sleep | Gives dose and timing guidance for the most widely used performance aid, plus the sleep and anxiety trade-offs Coach should mention. |
| sawka_2007_fluid_replacement | Nutrition | Sawka et al. 2007 (ACSM) | doi:10.1249/mss.0b013e31802ca597 | Publisher copyright | global | nutrition, hydration, performance, safety | The main professional position on drinking before, during and after exercise, with a practical way to measure personal needs. |
| acsm_2011_exercise_quantity | Cardio and activity | Garber et al. 2011 (ACSM) | doi:10.1249/MSS.0b013e318213fefb | Publisher copyright | global | cardio, activity, strength, flexibility, training, guidelines | A complete weekly template covering cardio, strength, balance and flexibility, plus the point that something is better than nothing; Tracend's standard cites it. |
| who_2020_activity_guidelines | Cardio and activity | Bull et al. 2020 (WHO) | doi:10.1136/bjsports-2020-102955 | CC BY 4.0 | global | cardio, activity, strength, sedentary, guidelines | The international reference on how much activity adults need, and the safest public baseline for any country; free to read. |
| piercy_2018_us_guidelines | Cardio and activity | Piercy et al. 2018 (US guidelines) | doi:10.1001/jama.2018.14854 | Publisher copyright | US | cardio, activity, strength, guidelines | The national guideline Americans meet in practice; useful for US users and for the point that the least active people gain the most from small increases. |
| paluch_2022_daily_steps | Cardio and activity | Paluch et al. 2022 | doi:10.1016/S2468-2667(21)00302-9 | CC BY 4.0 | global | activity, steps, cardio, health | Gives an evidence-based answer to 'do I really need 10,000 steps?', a question the app's step data raises daily. |
| watson_2015_sleep_duration | Recovery and sleep | Watson et al. 2015 (AASM and SRS) | doi:10.5665/sleep.4716 | Publisher copyright | global | sleep, recovery, health, guidelines | The clearest professional statement on how much sleep adults need, the baseline for any recovery advice. |
| walsh_2021_sleep_athlete | Recovery and sleep | Walsh et al. 2021 | doi:10.1136/bjsports-2020-102025 | Publisher copyright | global | sleep, recovery, performance, training | Covers sleep specifically for people who train: how common sleep problems are, what hurts performance and why one-size-fits-all targets are unwise. |
| dupuy_2018_recovery_techniques | Recovery and sleep | Dupuy et al. 2018 | doi:10.3389/fphys.2018.00403 | CC BY 4.0 | global | recovery, soreness, training | Compares popular recovery methods on soreness and fatigue, so Coach can say which ones have evidence and which do not. |
| riebe_2015_screening | Screening | Riebe et al. 2015 (ACSM) | doi:10.1249/MSS.0000000000000664 | Publisher copyright | global | screening, safety, health | The professional basis for deciding who should check with a doctor before starting or stepping up exercise, central to Tracend's safety gate. |
| bredin_2013_parq_plus | Screening | Bredin et al. 2013 | https://pmc.ncbi.nlm.nih.gov/articles/PMC3596208/ | Publisher copyright | global | screening, safety, health | Describes the widely used PAR-Q+ readiness questionnaire and its risk tiers, matching how Tracend's screening decides between proceed, moderate and refer. |
| byrne_2018_matador | Energy balance | Byrne et al. 2018 (MATADOR) | doi:10.1038/ijo.2017.206 | CC BY-NC-ND | global | nutrition, energy-balance, fat-loss, diet-break, metabolic-adaptation | The best-known trial of planned breaks from dieting, so Coach can explain what a diet break is and what the evidence for it does and does not show. |
| peos_2021_icecap | Energy balance | Peos et al. 2021 (ICECAP) | doi:10.1249/mss.0000000000002636 | Publisher copyright | global | nutrition, energy-balance, fat-loss, diet-break, training, hunger | The only trial of diet breaks in resistance-trained men and women, and it did not reproduce the extra fat loss seen in earlier work, which keeps Coach honest about breaks. |
| trexler_2014_metabolic_adaptation | Energy balance | Trexler et al. 2014 | doi:10.1186/1550-2783-11-7 | CC BY 2.0 | global | nutrition, energy-balance, fat-loss, metabolic-adaptation, diet-break, weight-maintenance | Explains why fat loss slows and hunger rises on a long diet, the situation of anyone who has already lost a lot of weight and still wants to lose more. |
| mountjoy_2023_reds | Energy balance | Mountjoy et al. 2023 (IOC) | doi:10.1136/bjsports-2023-106994 | Publisher copyright | global | nutrition, energy-balance, low-energy-availability, recovery, safety, fat-loss | The leading authority on the health risk of eating too little for the training done, which Coach needs for anyone cutting hard while training. |
| varkevisser_2019_weight_loss_maintenance | Energy balance | Varkevisser et al. 2019 | doi:10.1111/obr.12772 | CC BY-NC-ND | global | nutrition, weight-maintenance, fat-loss, behaviour-change, adherence | The most careful review of what predicts keeping weight off, which tells Coach where to put attention once someone has lost a lot of weight. |
| icmr_nin_2024_dietary_guidelines | Energy balance | ICMR-NIN 2024 | https://www.nin.res.in/dietaryguidelines/pdfjs/locale/DGI_2024.pdf | Publisher copyright (reproducing it in a product needs written permission) | IN | nutrition, protein, fat-loss, energy-balance, activity, guidelines, india | India's official food-based guidance, needed for users in India, and it differs from the sports-nutrition papers on BMI and protein powders in ways Coach must explain. |
| vella_2010_alcohol_recovery | Energy balance | Vella and Cameron-Smith 2010 | doi:10.3390/nu2080781 | CC BY 3.0 | global | alcohol, recovery, nutrition, sleep, hydration, performance | A free review of what alcohol does to exercise performance and recovery, for the common question of whether drinking undoes training. |
| zhu_2024_motivational_interviewing | Behaviour change | Zhu et al. 2024 | doi:10.1136/bmj-2023-078713 | CC BY 4.0 | global | behaviour-change, coaching-communication, activity, adherence, motivation | The strongest recent test of whether a motivational-interviewing coaching style raises activity, with a frank statement of how weak and short-lived the evidence is. |
| lally_2010_habit_formation | Behaviour change | Lally et al. 2010 | doi:10.1002/ejsp.674 | Publisher copyright | global | behaviour-change, habits, adherence, consistency, coaching-communication | The standard study of how long a new daily habit takes to feel automatic, which answers 'how long until this becomes easy?' without a made-up number. |
| mujika_2001_muscular_detraining | Special cases | Mujika and Padilla 2001 | doi:10.1097/00005768-200108000-00009 | Publisher copyright | global | detraining, training, strength, recovery, time-off | Directly answers 'will I lose my gains if I cannot train for a couple of weeks?' for trained people. |
| bosquet_2013_training_cessation | Special cases | Bosquet et al. 2013 | doi:10.1111/sms.12047 | Publisher copyright | global | detraining, training, strength, time-off, older-adults | The broadest pooled analysis of how much strength is lost when resistance training stops and who loses it fastest. |
| lopes_2019_elastic_resistance | Special cases | Lopes et al. 2019 | doi:10.1177/2050312119831116 | CC BY-NC | global | home-training, equipment, strength, training, minimal-equipment | Shows that resistance bands, which fit in a bag, build strength about as well as weights, which is the main question when a person must train away from a gym. |
| fragala_2019_older_adults | Special cases | Fragala et al. 2019 (NSCA) | doi:10.1519/jsc.0000000000003230 | Publisher copyright | global | older-adults, strength, training, safety, guidelines | The most thorough professional position on resistance training for older adults, so Coach can explain why lifting matters with age. |
| mcnulty_2020_menstrual_cycle | Special cases | McNulty et al. 2020 | doi:10.1007/s40279-020-01319-3 | CC BY 4.0 | global | women, menstrual-cycle, performance, training, individualisation | The best pooled answer to whether training should change across the menstrual cycle, which Coach is often asked. |

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
  words or fewer). Deterministic, no model call. The query is embedded with `gte-small` through the
  Edge runtime (`createGteSmallEmbedder`, the model `library-embed` used; no new provider), then the
  search runs for the athlete. Up to 8 chunks, whole chunks within 9,000 characters (the eight
  longest chunks are 7,200), each `[source: <id>] <header>` and the body. A failed embedding falls
  back to words alone (logged `library_retrieval_degraded`); a failed or slow search (the host's
  4 seconds) leaves the library out and Coach answers without it. A red-flag turn retrieves nothing
  (`coach-chat/index.ts` skips every contributor, and now also a turn `screenTurn` would refer).
- **Citations.** Evidence items gain the source `library`: `code` is the source id, `label` a short
  citation. `parseCoachChatAnswer` refuses a library citation whose id was not shown this turn (new
  rule `citation_not_retrieved`; `shownLibraryKeysIn` reads the ids back from the rendered block),
  and the reply guard refuses an id printed in the text that was not shown. One repair, then the
  labelled data summary, like every other rule. The output schema takes a library item with any
  code (an `anyOf` branch) because the ids change every turn and a schema change would break the
  prompt cache; data evidence still uses the day's enum. The app shows library evidence in the
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

- **Embedding deadline (P2).** The question's embedding races a 1.5-second deadline
  (`libraryEmbedDeadlineMs`); on a timeout or a failure the search runs with `embedding: null`
  (words alone) instead of the host's 4-second limit dropping the whole block. A cold gte-small load
  (16.3 s locally in the E1 spike, about 70 ms after) therefore costs one turn its vector half, and the
  load goes on in the background for the next. Not done: warming the session when the module loads,
  because it would charge every coach-chat cold start (red-flag and non-retrieval turns too) with an
  unmeasured model load. **Cold start and memory are not measured**: no test or document records
  coach-chat's memory with gte-small loaded, and the E2 note that the local runtime cut library-embed
  at about 1.1 s of CPU shows a first load could meet the CPU limit. After the deploy, check coach-chat's
  logs for `library_retrieval_degraded` and for resource-limit errors, and roll back with
  `./scripts/rollback-function.sh coach-chat` if the limit is hit.
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

## Next agent starts here

E4 (regional modules) adds sources the same way as E2 (files plus a migration) and should store a
country on the profile so `private.library_regions_for_account` stops guessing from the locale and
time zone. E5 (plan explanations citing sources) can reuse `libraryRetrievalQuery`, the contributor
and the `library` evidence source. Run `retrieval_only` after any library or search change.
