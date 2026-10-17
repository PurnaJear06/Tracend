# Research Library Handoff

**As of:** 2026-10-17

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

A hybrid (full-text plus gte-small vector) research library behind Coach answers and plan explanations. Rules still decide every number.

## Chunks

E1 (Phase 1); E2, E3 (Phase 3); E4, E5 (Phase 4)

E2 (Phase 3, round 2) is built and in review; see its section below.

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

Migration `20261017110842_library_content.sql` (code 42), the `library-embed` Edge Function,
35 sources in `supabase/library/`, a retrieval test set, and a coaching-principles digest.

### What shipped

- **Content as files.** `supabase/library/sources/*.ts` holds one object per source (metadata,
  licence, region, topics, why it was chosen, and a summary in our own words in titled sections);
  `supabase/library/index.ts` lists them. The type is `_shared/library/types.ts`. TypeScript modules
  (not Markdown) so tests can import the content without the extra read permission the CI deno step
  does not grant.
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
  checks it with the service-role `library_worker_authorized_v1`. No Edge secret, nothing in GitHub. Migrations run before functions deploy, so early ticks get a 404 and later ones
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
# call library-embed with the secret until embedded_chunks = chunks (about 11 calls; local cron posts to production)
curl -X POST http://127.0.0.1:54321/functions/v1/library-embed -H "Authorization: Bearer $SECRET" -d '{}'
EVAL_SERVICE_KEY=$(./scripts/supabase.sh status -o env | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"/\1/p') EVAL_WORKER_SECRET="$SECRET" \
  ./scripts/deno.sh run --allow-env --allow-net --allow-read=supabase/functions/_evals supabase/functions/_evals/library_eval.ts
```

(Colima was stopped between tool calls while I worked, probably by another agent's cleanup; run the
steps in one command if that happens.)

### Coaching principles digest (owner request, 2026-10-17)

`supabase/library/coaching_principles.ts` is a fixed, deterministic text of about 6,000 characters
(about 1,500 tokens, in our own words, no athlete data) with source ids inline in square brackets:
training (volume, frequency, loads, effort, rest, progression, deloads, cardio with lifting), cardio
and activity, nutrition, recovery and sleep, screening and safety, and how a good coach
communicates (individualise, honest about missing data and evidence strength, never diagnose, no
supplements pushed). `_shared/library/principles.ts` exports `coachingPrinciples` (`version`, `text`),
`citedSourceKeys(text)` and `coachingPrinciplesContributor`, a Contract 7 contributor with
`id: "coaching_principles"`, `slot: "stable"`, `budgetChars: 7200`, whose `render` returns the same
text for every question. It is **not registered**: E3 or the lead adds it to
`coach_context/registry.ts`. Any edit to the text changes the cached prefix, so bump
`coachingPrinciplesVersion`. Tests (`principles_test.ts`): every cited id exists in the source list;
the digest stays between 4,800 and 7,200 characters (1,200 to 1,800 tokens at four characters a
token; real tokenisation of the bracketed ids runs higher, so E3 should count tokens with the
provider's tokenizer before registering); all six sections are present; no markup, dates or
addresses; the contributor passes `validateCoachContextContributors`. The host wraps it as reference
data, so the communication rules are phrased as guidance for explaining, not as instructions that
override Tracend's rules.

### The 35 sources (for the owner's review)

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

## Next agent starts here

E3 (library inside Coach chat) once E2 merges and its contract requests are in: see "Finding for
E3" above (full-text search with whole questions) and the coaching-principles contributor, which is
built but not registered. E4 adds regional sources the same way as E2 (files plus a migration).
