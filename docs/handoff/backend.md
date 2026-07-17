# Backend Handoff

## Active Personal Coaching Work

Hosted forward migrations `20260716120000` through `20260716122000` deploy Coach Context v4:
query-aware context selection with 6 kinds (`daily_action`, `plan_change`, `explain_evidence`,
`nutrition_focus`, `recovery`, `general`). `prepare_coach_chat_v3` now wraps
`prepare_coach_chat_v4(..., 'general')` for backward compatibility. `coach-chat` classifies user
questions with regex-based `classifyQuestion()` and compacts the JSON context with
`compactContext()` before sending to Groq. Every context kind targets well under 8000 TPM. ADR 0007
documents the decision; Deno provider tests pass 15/15 (7 classification + 8 compaction); pgTAP
covers RLS, kind fallback, idempotency, and size budgets across 37 test assertions.

Forward migration `20260711220000_evidence_ui_truth_repair.sql` is hosted with local/remote parity.
It returns one ranked unresolved reconciliation candidate per session, closes competitors on
confirmation, and turns same-day manual measurements into audited amendments. PostgreSQL/RLS checks
pass 313/313.

**Scope:** Supabase, database, RLS, Edge Functions, CI, local tooling, and server-side integration
boundaries.

This file is current-state handoff, not durable architecture. Keep detailed history in
`docs/worklog/` and durable decisions in `docs/adr/`.

## Current State

- **Coach Context v5 deployed:** migration `20260716130000_coach_context_v5.sql` replaces
  `prepare_coach_chat_v4` in-place with enriched v5 context. New fields: `nutrition_adherence`
  (days_with_confirmed_meals_7d, schedule_slot_compliance), extended `nutrition_compliance_7day`
  (avg_daily_carbohydrate_g, avg_daily_fat_g, days_with_meals), `data_quality.last_photo_set`,
  `photo_sets_completed`, `has_physique_analysis`, and `evidence_freshness.last_photo_set`.
  `physique_analyses` table created with forced RLS (empty pending vision AI evaluation gate).
  `classifyQuestion` extended: +4 keywords for physique/visual progress → `explain_evidence`, +4 for
  adherence/compliance → `nutrition_focus`. `compactContext` has 12 new abbreviations for v5 fields.
  Per-pose photo rows replace the monolithic capture flow in Flutter. Schema version: 3.0. ADR 0008
  records the decision. Deno 56/56, Flutter 68/68.
- **Coach Continuity Memory (v6 + v16 prompt):** three migrations through
  `20260717110000` add `coach_narrative_entries`, `user_preferences`, and
  `coach_session_summaries` (all forced RLS), tsvector FTS on `coach_messages`,
  `prepare_coach_chat_v5` (wraps v4 with narrative, preferences, journal),
  `persist_coach_narrative_entry`, `persist_coach_preference`,
  `persist_coach_session_summary`, `search_coach_messages`. `coach-chat` v16 adds
  preference detection, FTS retrieval of relevant past messages, deterministic
  session summary creation, and `preference_prompt` in response. Provider contract
  extended to `CoachChatAnswerV2` with optional `reasoning_chain`. All
  service-only grants. ADR 0009. **Hosted: migrations through
  `20260717110004_fix_coaching_date_ambiguous.sql` are live.** Four post-deploy
  fix migrations exist — see `docs/worklog/2026-07-17-coach-continuity.md` for
  the bug-and-fix sequence (v4→v5 recursion, schema_version constraint,
  `jsonb_agg(... ORDER BY ...)` unsupported on hosted PG ⇒ subquery rewrite,
  `coaching_date` PL/pgSQL variable ambiguity ⇒ table-qualified columns).
  Prompt restructure in `coach_chat_provider.ts`: Groq and Gemini request bodies
  now use multi-role `system` + `user` messages (system owns identity, schema,
  evidence rules; user carries the user's raw message first, prepared context
  second). The prior "Lead with one clear recommendation" instruction is removed
  because it produced the same plan-style answer for every input including
  greetings. Diagnostic stubs added during debugging were removed; safe
  `persist_failed_coach_chat_run` try/catch is retained. Pending: run pgTAP
  locally (need Colima start), regression-eval the new prompt at scale, and
  decide whether to bump Gemini temperature to match Groq.
- **Coach Context v4 deployed:** migrations `20260716120000_coach_context_v4.sql`,
  `20260716121000_coach_context_v4_enrichment.sql`, and
  `20260716122000_coach_context_v4_enrichment.sql` are hosted. `coach-chat` is redeployed with
  `classifyQuestion()` and `compactContext()`. Each context kind produces bounded, kind-specific
  data; the TS provider compacts keys, strips nulls, and truncates rationales before the Groq call.
  `prepare_coach_chat_v3` wraps v4 for backward compat. ADR 0007 records the decision. Deno 51/51.
  Owner should send one chat message to confirm a real Groq 200 response.
- **Current active change:** ADR 0006 server-only Groq Qwen owner-test routing is hosted for
  Coach/chat and JPEG/PNG meal-photo candidates. Migration
  `20260711100000_owner_groq_qwen_test_routing.sql` adds provider metadata and a USD 2/10 request
  guard while preserving schema/confirmation checks. Do not add a key to Flutter.
- **Qwen repair deployed:** the first owner Coach request failed before billable usage. All Qwen
  prompts now put instructions in the user message, as required by current Groq Qwen guidance.
  `coach-decide`, `coach-chat`, and `meal-analyze` were redeployed; owner must make one fresh Coach
  request to confirm a persisted Groq run.
- **Verified root cause:** direct server diagnostic proved the stored key/model returns HTTP 200.
  The Coach adapter failed only because Qwen reasoning mode produced unpermitted evidence under the
  strict validator. Non-thinking JSON mode passed the same schema/policy validation and is now
  deployed for Coach and chat. The diagnostic function and temporary secret were deleted.
- **Chat failure behavior is fail-closed:** migration `20260711113000_coach_chat_fail_closed.sql`
  and `coach-chat` v12 are hosted. Qwen receives one schema-repair retry; a second failure is
  persisted as a sanitized failed `coach_chat` run and returns 503. Do not reintroduce
  `deterministic-chat-fallback-v1` for a live conversation.
- **Coach context/voice repair deployed:** migration `20260711150000_coach_longitudinal_context.sql`
  adds active goal/profile, seven-day confirmed nutrition and normalized HealthKit history, recent
  measurements/review, workouts, check-in, approved plan, and thread context. Provider guidance now
  gives practical same-day recovery coaching for ordinary illness reports while retaining
  diagnosis/treatment and durable-change boundaries. The migration is hosted with local/remote
  parity and `coach-chat` v13 is ACTIVE.
- **Context coverage repair deployed:** migration `20260711170000_coach_context_coverage.sql` adds a
  service-only v2 chat preparation wrapper and owner-only context-status RPC. It treats recent
  HealthKit history as available chat context instead of requiring an exact same-day row, while
  retaining true gaps such as zero completed workouts. Hosted migration parity passes and
  `coach-chat` v14 is ACTIVE.

- Phase 1 backend foundation is complete and verified.
- Supabase CLI, Deno, Docker CLI, Colima, and Lima are intended to run from repository-local
  `.tooling/` on the external SSD.
- Supabase local project exists under `supabase/`.
- Repository-local CLI is authenticated and linked to hosted project `qsfzzsjenopqqqhvpyaw`
  (`Tracend`) in Southeast Asia (Singapore).
- Phase 1 plus two forward-only Phase 2 migrations exist. Phase 2 adds automatic Auth linkage,
  profile/consent/draft/goal state, immutable snapshots, proposals, plan/target versions, audit,
  service-only mock persistence, and transactional proposal response.
- `onboarding-propose-plan` validates the caller session, loads only that user's draft, computes a
  deterministic mock proposal, and calls the service-only persistence RPC. It contains no live
  provider or client secret.
- ADR 0002 authorizes Supabase email/password only for owner development while preserving
  `auth.users.id`, RLS, and the later Sign in with Apple route.
- `DEVELOPMENT_GUIDE.md` is the command source for verified local workflows.

## Current Verification State

- Deno formatting, linting, type checking, and mock-provider tests: **passed**.
- Phase 2 pgTAP: **passed — 39/39**, covering forced RLS, anonymous denial, cross-user denial,
  append-only consent, both onboarding paths, invalid output, acceptance/replay behavior, audit, and
  one active plan/target per user.
- All migrations were applied from scratch to a recreated local PostgreSQL container before the
  39/39 run.
- Supabase local start and database reset: **passed** (local analytics disabled).
- pgTAP RLS test suite: **passed — 8/8 tests, Files=1, Result: PASS** (2026-06-28). Tests cover: RLS
  enabled, RLS forced, own-row select isolation, own-row update, update persists, row_version
  increments on update, cross-user update blocked, cross-identity insert blocked.
- Hosted project access and link status: **verified** with `./scripts/supabase.sh projects list`
  (2026-06-28).
- Hosted migration deployment: **passed** — `20260628190000_phase_1_foundation.sql` applied
  successfully (2026-06-28).
- Hosted pgTAP behavior verification: **passed — 8/8** in the Supabase SQL Editor against the linked
  project (2026-06-29). The transaction rolled back all three synthetic Auth users and account rows
  after testing.

Phase 1 is complete. Phase 2 is locally verified and deployed to the linked hosted project: both
migration versions match remote, and `onboarding-propose-plan` version 1 reports ACTIVE.

The forward-only Phase 3 migration is deployed and local/remote migration versions match. It adds
planned workouts/exercises, workout sessions, performances, sets, append-only amendments, and
revisioned daily check-ins. Narrow authenticated RPCs start, revision-sync, complete, and save
check-ins; direct client writes remain denied. Phase 3 pgTAP passes 22/22 and the full database
suite is 61/61.

Phase 4 migration `20260701140000` is deployed to the linked hosted project and local/remote
migration versions match. It adds `health_sync_runs`, `daily_health_summaries`, forced RLS/read-only
owner policies, bounded canonical-unit constraints, and the service-role-only transactional
`persist_health_sync` RPC. Authenticated Edge Function `health-sync` derives identity from the
caller JWT, validates schema/ranges, requires per-type hashed provenance, stores supported
sleep-stage totals and explicit HRV metric/unit, and never accepts a client ownership field. Phase 4
pgTAP passes 20/20; the full database suite passes 81/81 after applying every migration to a freshly
recreated local schema. Deno checks pass 9/9. `health-sync` version 1 is ACTIVE. An unauthenticated
hosted POST returns the sanitized `authentication_required` response with HTTP 401, confirming the
deployed JWT boundary without retaining synthetic data. Owner-device verification created three
authenticated sync runs. The latest partial run accepted seven summaries with zero rejects; no
health values or user identifiers were copied into verification notes.

Phase 5 is locally complete with the existing mock provider. Forward migration `20260702090000` adds
forced-RLS policy evaluations, model runs, and decisions; service-only snapshot/persistence RPCs;
idempotency and a ten-run daily limit; sanitized failure recording; and owner-only monthly usage.
Authenticated `coach-decide` derives identity from JWT, runs deterministic policy, validates
evidence/actions, and cannot persist a proposal. Deno passes 16/16 and the full pgTAP suite passes
101/101. Successful decisions and failed provider runs emit sanitized, replay-safe audit events.
Migration `20260702090000` is deployed and matches remote; `coach-decide` version 1 is ACTIVE. An
unauthenticated hosted POST returns HTTP 401 with `authentication_required`.

The initial Phase 6 local migration is verified against the SSD-local database. It adds forced-RLS
meal/food/candidate/media tables, a private meal bucket with owner policies, manual and
sample-confirmation RPCs, confirmed-only totals, idempotency, and sanitized audit events. Full pgTAP
passes 122/122; Phase 6 contributes 21 checks. Migration `20260702110000` is hosted and matches
local. Hosted verification confirms five forced-RLS tables, one private bucket, three scoped Storage
policies, and four authenticated RPC grants.

The next forward-only Phase 6 migration, `20260702130000`, is hosted and verified. It adds atomic
corrected-candidate confirmation, idempotent owner-scoped meal deletion, media retention
exemption/status/index fields, and service-only claim/finalize RPCs. `meal-media-retention` version
3 is ACTIVE and removes private Storage bytes before safely finalizing or retrying metadata. Its
dedicated secret exists in Function secrets and encrypted Vault; daily Cron is active at 02:15 UTC
and references Vault rather than embedding the secret. A hosted invocation returned HTTP 200/schema
1.0 with zero due objects; unauthenticated access returned 401. Full pgTAP passes 141/141 and Deno
18/18.

Phase 7 local migration `20260702170000` adds forced-RLS measurements, progress photo sets/poses,
reviews, separate progress storage/AI consent values, a private purpose-bound `progress-photos`
bucket, authenticated measurement writes, and deterministic owner summaries. Forward repair
`20260702173000` requires two distinct measurement dates before a trend is available. Full local
pgTAP passes 163/163.

The reviewed Phase 7 migration is now hosted and local/remote histories match through
`20260702173000`. The signed hosted app is installed. Authenticated measurement persistence and
readback QA passed; no image worker or provider was deployed.

Migration `20260702200000` is hosted and adds consent-gated set creation, owner/path-verified pose
registration, completion, and idempotent metadata deletion after Storage removal. Full pgTAP passes
171/171. No Gemini secret, worker, Queue consumer, or provider request exists.

Migration `20260702223000` is hosted and local/remote histories match. It adds a private durable
`weekly_reviews` queue, owner-readable forced-RLS job state, one job per user/week, daily local-
week scheduling, five-minute consumption, immutable deterministic snapshots and reviews, eligibility
cancellation, delayed retry, three-attempt terminal failure, owner acknowledgement, and sanitized
audit. Queue payloads contain only schema version and opaque job ID. Full pgTAP passes 200/200. No
Edge Function, provider call, or secret is added. Hosted migration parity passed; the optional
schema dump was blocked by the known container DNS limitation. The owner hosted smoke now passes: an
authenticated owner request queued the 2026-06-22 review, the worker completed one message with zero
failures, and the persisted review is ready for owner acknowledgement. The device-side queue error
was confirmed as an expired mobile access token, not a database or Queue failure; the stored refresh
token remained valid.

## Next Safe Actions

1. Start Colima (`./scripts/container.sh start`), start Supabase (`./scripts/supabase.sh start`),
   run pgTAP (`./scripts/test-db.sh`) for the new 36-assertion Coach Continuity test file.
2. Deploy Coach Continuity migrations to hosted: `./scripts/supabase.sh db push --linked --dry-run`,
   then `./scripts/supabase.sh db push --linked`. Redeploy `coach-chat`:
   `./scripts/supabase.sh functions deploy coach-chat --project-ref qsfzzsjenopqqqhvpyaw --use-api`.
3. Finish the weekly Free database/Storage backup through a reviewed pooler or dashboard path;
   direct-host CLI dump currently fails container DNS.
4. Keep Gemini disabled until billing/paid-service data terms, provider controls, and full task
   evaluations pass. The hosted routes accept only `gemini-3.5-flash`; Flash-Lite is not a
   production fallback.
5. Keep manual/sample nutrition available and leave live meal/progress AI and licensed catalog
   selection deferred.

## Do Not Do

- Do not put service-role keys or AI provider keys in Flutter.
- Do not bypass RLS from the client.
- Do not add a separate API server, vector database, Redis, or agent framework.
- Do not run destructive production operations.

Phase 7 weekly review owner acknowledgement passed. Phase 8 notification preferences are locally
verified: forced RLS, validated RPC, cross-user denial, and append-only consent/withdrawal evidence
pass in the 210-test pgTAP suite. Migration `20260703090000` is hosted and migration histories
match.

Phase 8 privacy migrations `20260703150000` and `20260703170000` are hosted and match local history.
They add forced-RLS export/deletion state, private export Storage, opaque queues,
recent-authentication gates, three-download/seven-day limits, retry-safe cleanup, and 180-day
content-free deletion receipts. `privacy-export` and `privacy-delete-account` are ACTIVE; the
redeployed daily `meal-media-retention` worker also clears expired exports. Full pgTAP passes
236/236 and Deno passes 22/22. A hosted synthetic account passed encrypted export, secure download,
local decryption/manifest validation, private Storage cleanup, Auth/database deletion, and
completion-receipt verification.

Gemini readiness migration `20260703190000` is hosted with local/remote parity, and `coach-decide`
version 7 is ACTIVE. Provider selection defaults to mock and fails closed unless enablement,
paid-data attestation, model, key, and rates are configured server-side. Provider metadata RPCs are
service-only. Full pgTAP passes 247/247 and Deno passes 28/28; unauthenticated access remains
HTTP 401. No live Gemini request was made.

Owner continuation migrations `20260704100000`, `20260704101500`, and `20260704103000` are hosted. A
pre-change encrypted owner-state backup is under ignored SSD tooling. The service-only import
created one active imported plan, six workouts, 33 exercises, a new active target version, three
confirmed progress checkpoints, and one sanitized audit event; the setup measurement is superseded
rather than deleted. pgTAP passes 264/264. Private values remain only in PostgreSQL and ignored
`.tooling/private-imports/`, not this handoff.

Production rebuild migrations `20260704145000`, `20260704150000`, and `20260704151000` are hosted
and local/remote histories match. The rebuild adds coach chat, nutrition scheduling, meal-photo
draft/candidate flow, AI budget accounting, daily brief/training hub RPCs, and a strict Gemini model
boundary: production Gemini routes accept only `gemini-3.5-flash`. Flash-Lite usage fails closed in
both Edge Function configuration and service-only database usage recording. `coach-decide`,
`coach-chat`, and `meal-analyze` are deployed and unauthenticated requests return HTTP 401. Billing
remains disabled, so live Gemini traffic remains off; no provider request was made. Current
verification: Deno 32/32, pgTAP 287/287, hosted migration parity, and hosted app install/ launch on
the paired iPhone.

Repair migration `20260705100000_owner_schedule_and_daily_brief_repair` is hosted and local/remote
histories match. It replaces placeholder active nutrition schedule foods with the owner-confirmed
quantities, changes `get_my_daily_brief` to use the latest stored HealthKit summary from the
previous 31 days, and keeps rest days unassigned instead of falling back to the first planned
workout. Verification: Deno 32/32, pgTAP 290/290, Flutter analysis, 65/65 tests, and a strictly
verified signed iPhone release build.
