# Backend Handoff

**Scope:** Supabase, database, RLS, Edge Functions, CI, local tooling, and
server-side integration boundaries.

This file is current-state handoff, not durable architecture. Keep detailed
history in `docs/worklog/` and durable decisions in `docs/adr/`.

## Current State

- Phase 1 backend foundation is complete and verified.
- Supabase CLI, Deno, Docker CLI, Colima, and Lima are intended to run from
  repository-local `.tooling/` on the external SSD.
- Supabase local project exists under `supabase/`.
- Repository-local CLI is authenticated and linked to hosted project
  `qsfzzsjenopqqqhvpyaw` (`Tracend`) in Southeast Asia (Singapore).
- Phase 1 plus two forward-only Phase 2 migrations exist. Phase 2 adds automatic
  Auth linkage, profile/consent/draft/goal state, immutable snapshots, proposals,
  plan/target versions, audit, service-only mock persistence, and transactional
  proposal response.
- `onboarding-propose-plan` validates the caller session, loads only that user's
  draft, computes a deterministic mock proposal, and calls the service-only
  persistence RPC. It contains no live provider or client secret.
- ADR 0002 authorizes Supabase email/password only for owner development while
  preserving `auth.users.id`, RLS, and the later Sign in with Apple route.
- `DEVELOPMENT_GUIDE.md` is the command source for verified local workflows.

## Current Verification State

- Deno formatting, linting, type checking, and mock-provider tests: **passed**.
- Phase 2 pgTAP: **passed — 39/39**, covering forced RLS, anonymous denial,
  cross-user denial, append-only consent, both onboarding paths, invalid output,
  acceptance/replay behavior, audit, and one active plan/target per user.
- All migrations were applied from scratch to a recreated local PostgreSQL
  container before the 39/39 run.
- Supabase local start and database reset: **passed** (local analytics disabled).
- pgTAP RLS test suite: **passed — 8/8 tests, Files=1, Result: PASS** (2026-06-28).
  Tests cover: RLS enabled, RLS forced, own-row select isolation, own-row update,
  update persists, row_version increments on update, cross-user update blocked,
  cross-identity insert blocked.
- Hosted project access and link status: **verified** with
  `./scripts/supabase.sh projects list` (2026-06-28).
- Hosted migration deployment: **passed** —
  `20260628190000_phase_1_foundation.sql` applied successfully (2026-06-28).
- Hosted pgTAP behavior verification: **passed — 8/8** in the Supabase SQL
  Editor against the linked project (2026-06-29). The transaction rolled back
  all three synthetic Auth users and account rows after testing.

Phase 1 is complete. Phase 2 is locally verified and deployed to the linked
hosted project: both migration versions match remote, and
`onboarding-propose-plan` version 1 reports ACTIVE.

The forward-only Phase 3 migration is deployed and local/remote migration
versions match. It
adds planned workouts/exercises, workout sessions, performances, sets,
append-only amendments, and revisioned daily check-ins. Narrow authenticated
RPCs start, revision-sync, complete, and save check-ins; direct client writes
remain denied. Phase 3 pgTAP passes 22/22 and the full database suite is 61/61.

Phase 4 migration `20260701140000` is deployed to the linked hosted project and
local/remote migration versions match. It adds
`health_sync_runs`, `daily_health_summaries`, forced RLS/read-only owner
policies, bounded canonical-unit constraints, and the service-role-only
transactional `persist_health_sync` RPC. Authenticated Edge Function
`health-sync` derives identity from the caller JWT, validates schema/ranges,
requires per-type hashed provenance, stores supported sleep-stage totals and
explicit HRV metric/unit, and never accepts a client ownership field. Phase 4
pgTAP passes 20/20; the full database suite passes 81/81 after applying every
migration to a freshly recreated local schema. Deno checks pass 9/9.
`health-sync` version 1 is ACTIVE. An unauthenticated hosted POST returns the
sanitized `authentication_required` response with HTTP 401, confirming the
deployed JWT boundary without retaining synthetic data.
Owner-device verification created three authenticated sync runs. The latest
partial run accepted seven summaries with zero rejects; no health values or
user identifiers were copied into verification notes.

Phase 5 is locally complete with the existing mock provider. Forward migration
`20260702090000` adds forced-RLS policy evaluations, model runs, and decisions;
service-only snapshot/persistence RPCs; idempotency and a ten-run daily limit;
sanitized failure recording; and owner-only monthly usage. Authenticated
`coach-decide` derives identity from JWT, runs deterministic policy, validates
evidence/actions, and cannot persist a proposal. Deno passes 16/16 and the full
pgTAP suite passes 101/101. Successful decisions and failed provider runs emit
sanitized, replay-safe audit events. Migration `20260702090000` is deployed and
matches remote; `coach-decide` version 1 is ACTIVE. An unauthenticated hosted
POST returns HTTP 401 with `authentication_required`.

The initial Phase 6 local migration is verified against the SSD-local database.
It adds forced-RLS meal/food/candidate/media tables, a private meal bucket with
owner policies, manual and sample-confirmation RPCs, confirmed-only totals,
idempotency, and sanitized audit events. Full pgTAP passes 122/122; Phase 6
contributes 21 checks. Migration `20260702110000` is hosted and matches local.
Hosted verification confirms five forced-RLS tables, one private bucket, three
scoped Storage policies, and four authenticated RPC grants.

The next forward-only Phase 6 migration, `20260702130000`, is hosted and
verified. It adds atomic corrected-candidate confirmation, idempotent
owner-scoped meal deletion, media retention exemption/status/index fields, and
service-only claim/finalize RPCs. `meal-media-retention` version 3 is ACTIVE and
removes private Storage bytes before safely finalizing or retrying metadata. Its
dedicated secret exists in Function secrets and encrypted Vault; daily Cron is
active at 02:15 UTC and references Vault rather than embedding the secret. A
hosted invocation returned HTTP 200/schema 1.0 with zero due objects;
unauthenticated access returned 401. Full pgTAP passes 141/141 and Deno 18/18.

Phase 7 local migration `20260702170000` adds forced-RLS measurements, progress
photo sets/poses, reviews, separate progress storage/AI consent values, a
private purpose-bound `progress-photos` bucket, authenticated measurement
writes, and deterministic owner summaries. Forward repair `20260702173000`
requires two distinct measurement dates before a trend is available. Full local
pgTAP passes 163/163.

The reviewed Phase 7 migration is now hosted and local/remote histories match
through `20260702173000`. The signed hosted app is installed. Authenticated
measurement persistence and readback QA passed; no image worker or provider was
deployed.

Migration `20260702200000` is hosted and adds consent-gated set creation,
owner/path-verified pose registration, completion, and idempotent metadata
deletion after Storage removal. Full pgTAP passes 171/171. No Gemini secret,
worker, Queue consumer, or provider request exists.

Migration `20260702223000` is hosted and local/remote histories match. It adds
a private durable `weekly_reviews`
queue, owner-readable forced-RLS job state, one job per user/week, daily local-
week scheduling, five-minute consumption, immutable deterministic snapshots
and reviews, eligibility cancellation, delayed retry, three-attempt terminal
failure, owner acknowledgement, and sanitized audit. Queue payloads contain
only schema version and opaque job ID. Full pgTAP passes 200/200. No Edge
Function, provider call, or secret is added. Hosted migration parity passed;
the optional schema dump was blocked by the known container DNS limitation.
The owner hosted smoke now passes: an authenticated owner request queued the
2026-06-22 review, the worker completed one message with zero failures, and the
persisted review is ready for owner acknowledgement.
The device-side queue error was confirmed as an expired mobile access token,
not a database or Queue failure; the stored refresh token remained valid.

## Next Safe Actions

1. Finish the weekly Free database/Storage backup through a reviewed pooler or
   dashboard path; direct-host CLI dump currently fails container DNS.
2. Keep Gemini disabled until billing/paid-service data terms, provider
   controls, and full task evaluations pass. The hosted routes accept only
   `gemini-3.5-flash`; Flash-Lite is not a production fallback.
3. Keep manual/sample nutrition available and leave live meal/progress AI and
   licensed catalog selection deferred.

## Do Not Do

- Do not put service-role keys or AI provider keys in Flutter.
- Do not bypass RLS from the client.
- Do not add a separate API server, vector database, Redis, or agent framework.
- Do not run destructive production operations.

Phase 7 weekly review owner acknowledgement passed. Phase 8 notification
preferences are locally verified: forced RLS, validated RPC, cross-user denial,
and append-only consent/withdrawal evidence pass in the 210-test pgTAP suite.
Migration `20260703090000` is hosted and migration histories match.

Phase 8 privacy migrations `20260703150000` and `20260703170000` are hosted and
match local history. They add forced-RLS export/deletion state, private export
Storage, opaque queues, recent-authentication gates, three-download/seven-day
limits, retry-safe cleanup, and 180-day content-free deletion receipts.
`privacy-export` and `privacy-delete-account` are ACTIVE; the redeployed daily
`meal-media-retention` worker also clears expired exports. Full pgTAP passes
236/236 and Deno passes 22/22. A hosted synthetic account passed encrypted
export, secure download, local decryption/manifest validation, private Storage
cleanup, Auth/database deletion, and completion-receipt verification.

Gemini readiness migration `20260703190000` is hosted with local/remote parity,
and `coach-decide` version 7 is ACTIVE. Provider selection defaults to mock and
fails closed unless enablement, paid-data attestation, model, key, and rates are
configured server-side. Provider metadata RPCs are service-only. Full pgTAP
passes 247/247 and Deno passes 28/28; unauthenticated access remains HTTP 401.
No live Gemini request was made.

Owner continuation migrations `20260704100000`, `20260704101500`, and
`20260704103000` are hosted. A pre-change encrypted owner-state backup is under
ignored SSD tooling. The service-only import created one active imported plan,
six workouts, 33 exercises, a new active target version, three confirmed
progress checkpoints, and one sanitized audit event; the setup measurement is
superseded rather than deleted. pgTAP passes 264/264. Private values remain only
in PostgreSQL and ignored `.tooling/private-imports/`, not this handoff.

Production rebuild migrations `20260704145000`, `20260704150000`, and
`20260704151000` are hosted and local/remote histories match. The rebuild adds
coach chat, nutrition scheduling, meal-photo draft/candidate flow, AI budget
accounting, daily brief/training hub RPCs, and a strict Gemini model boundary:
production Gemini routes accept only `gemini-3.5-flash`. Flash-Lite usage fails
closed in both Edge Function configuration and service-only database usage
recording. `coach-decide`, `coach-chat`, and `meal-analyze` are deployed and
unauthenticated requests return HTTP 401. Billing remains disabled, so live
Gemini traffic remains off; no provider request was made. Current verification:
Deno 32/32, pgTAP 287/287, hosted migration parity, and hosted app install/
launch on the paired iPhone.

Repair migration `20260705100000_owner_schedule_and_daily_brief_repair` is
hosted and local/remote histories match. It replaces placeholder active nutrition
schedule foods with the owner-confirmed quantities, changes `get_my_daily_brief`
to use the latest stored HealthKit summary from the previous 31 days, and keeps
rest days unassigned instead of falling back to the first planned workout.
Verification: Deno 32/32, pgTAP 290/290, Flutter analysis, 65/65 tests, and a
strictly verified signed iPhone release build.
