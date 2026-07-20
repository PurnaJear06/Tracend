# Tracend Implementation Roadmap

## Personal Coaching System Sequence

Deliver Workout Truth Repair, HealthKit reconciliation, Coach Context v2, Qwen weekly reasoning,
approval-gated plan evolution, and owner-device dogfooding in that order. RAG remains deferred
pending measured structured-retrieval failure.

**Status:** Execution order for the private-beta MVP\
**Constraint:** This roadmap does not expand [PRD.md](./PRD.md)\
**Backend:** Supabase Auth, PostgreSQL, Storage, Edge Functions, Queues, and Cron **Coordination:**
Current cross-chat dashboard lives in [PROGRESS_CONTEXT.md](./PROGRESS_CONTEXT.md); scoped handoffs
live in [`docs/handoff/`](./handoff/)

Build complete vertical slices instead of every screen, table, or AI component separately.

## 1. Decisions Before Scaffolding

- minimum iOS version and device matrix;
- Flutter/Dart and Supabase CLI version pinning;
- app identifier, Apple team, and TestFlight environments;
- Supabase project region nearest initial users — resolved: Southeast Asia (Singapore),
  `ap-southeast-1`;
- Free-first backup/export schedule and Pro upgrade triggers from [COST_MODEL.md](./COST_MODEL.md);
- initial AI model candidates and provider budget controls;
- licensed food catalog, region coverage, attribution, updates, and manual fallback;
- photo retention defaults within [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md); and
- custom-font license, size, Dynamic Type, and offline viability.

Use short architecture decision records only for expensive-to-reverse choices.

## 2. Phase 1 — Supabase Foundation and UI Shell

Deliver:

- Flutter iOS scaffold with `supabase_flutter` and environment-specific project configuration;
- Supabase CLI local project using a Docker-compatible runtime;
- migration structure, generated database types, seed fixtures, and RLS test harness;
- Auth/Data API/RPC/Edge Function client boundaries;
- local mocks for Apple, HealthKit, Storage, Queue, and AI provider behavior;
- semantic themes, typography, icons, navigation shell, and component gallery;
- CI for formatting, analysis, tests, migration lint, RLS tests, Edge Functions, and Flutter build;
  and
- `AGENTS.md` containing verified commands and architecture rules.

Exit gate: a clean checkout starts the local Supabase stack and Flutter app; no secret/service-role
key appears in the client; design/accessibility smoke tests pass.

## 3. Phase 2 — Supabase Auth, Onboarding, and Approval

`Configured Supabase Auth → eligibility/consent → onboarding → deterministic snapshot → mocked proposal → explicit approval → transactional activation`

Owner development uses the ADR 0002 email/password mode until Apple Developer Program capabilities
are available. Sign in with Apple remains the external private-beta route and must use the same
downstream identity and session contracts.

Start with a mocked provider response using the final schema. Implement `auth.users` linkage,
`user_accounts`, Account/profile states, RLS, consent, versioning, transactional RPC, audit, and
cross-user tests before live AI.

Exit gate: two isolated users complete both onboarding paths; anonymous/cross-user access fails;
invalid output cannot activate a plan; exactly one approved version is active.

**Implementation status (2026-07-01):** implemented and locally verified with owner email/password
auth, both onboarding paths, autosave, deterministic mock proposal generation, explicit response
RPC, version activation, audit, and 39 pgTAP checks. Both Phase 2 migrations and
`onboarding-propose-plan` version 1 are deployed to the linked hosted project. Physical-iPhone
runtime verification remains before this phase is marked complete.

## 4. Phase 3 — Workout and Check-In

Deliver approved-plan reads under RLS, offline set logging, local autosave, idempotent sync,
completion/amendment RPC, check-in, deterministic features, and Today states using fixture
decisions.

Exit gate: a session survives interruption/offline use without lost, duplicated, or cross-user sets.

**Implementation status (2026-07-01):** the first complete local slice is implemented: approved-plan
workout expansion/read, local set autosave, idempotent start/sync, transactional completion,
immutable completed sessions, revisioned check-ins, RLS, and 22 Phase 3 pgTAP checks. Flutter
analysis and 24 tests pass. The migration is deployed and matches the linked hosted project.
Physical-iPhone interruption/reconnection verification remains before this phase is complete.

## 5. Phase 4 — HealthKit Summaries

Add contextual permissions, `HealthDataSource`, normalized summaries, authenticated `health-sync`
Edge Function, idempotency, provenance, freshness, partial/unknown states, and manual fallback.

Exit gate: malformed/duplicate/cross-user sync fails safely and Today works without HealthKit.

**Implementation status (2026-07-02): complete.** Implemented, locally verified, deployed to the
linked hosted project, and exercised on the owner's physical iPhone. Flutter includes the read-only
HealthKit adapter, deterministic daily normalization, Today/Account connection states, and manual
fallback. The forward-only migration, service-only persistence RPC, authenticated Edge Function,
RLS, validation, idempotency, and cross-user tests pass locally. Migration `20260701140000` matches
local and remote, and `health-sync` version 1 is ACTIVE. The signed hosted-config build requested
permission in context and completed authenticated partial sync: seven daily summaries accepted, none
rejected. Today and Account reflect the same shared health status. Real-device revocation remains a
non-blocking regression check.

**Readback correction (2026-07-04): complete locally.** Today now reads the stored daily summaries
into dated evidence cards and real sleep/step trends, while partial status names categories found
and absent without claiming denial. The Train placeholder performance curve and fictional
week/schedule values are removed; the active plan is selected explicitly and today prefers its
matching weekday. Device refresh/readback QA remains.

## 6. Phase 5 — Controlled Coaching

Implement Edge Function workflow: snapshot → deterministic policy → bounded context → one provider
call → validation → decision persistence. Add evaluation, per-user cost/rate controls, and the
sanitized user-scoped AI usage summary before live decisions.

Exit gate: provider failure leaves plans usable; safety fixtures pass 100%; each decision cites its
snapshot; AI/provider keys stay in Edge Function secrets.

**Implementation status (2026-07-02): local complete; deployment/device QA pending.** The
mock-provider-first controlled workflow now creates immutable daily snapshots and deterministic
policy, invokes one typed provider, validates the whole response, records success/failure, and
persists an owner-readable decision. Forced RLS, idempotency, daily rate limits, escalation,
sanitized usage, Today/Coach reads, and provider-failure fallback are implemented. Deno passes 16/16
and its local pgTAP/Flutter gates pass. Migration `20260702090000` and `coach-decide` version 1 are
hosted; owner iPhone QA passed.

## 7. Phase 6 — Nutrition and Meals

Implement targets, licensed catalog, manual meals, private Supabase Storage meal bucket, Storage
RLS, vision queue, candidate editor, transactional confirmation, retention Cron, and deletion.

Exit gate: unconfirmed AI never affects totals; failure permits manual logging; another user cannot
list/read meal objects.

**Start checkpoint (2026-07-02): local implementation authorized.** Begin with manual meal logging,
confirmed deterministic totals, fixture candidate editing, and the private Storage/RLS foundation.
Keep unconfirmed candidates out of totals. Licensed catalog selection, live image AI, hosted
deployment, and physical-iPhone QA remain deferred until their explicit decisions are available.

**Initial local slice verified (2026-07-02).** Manual logging, confirmed-only totals,
sample-candidate selection/confirmation, private Storage/RLS foundation, and safe failure states
pass 38/38 Flutter tests and 122/122 full pgTAP checks. The unsigned iOS device build passes at 18.5
MB. Migration `20260702110000` is hosted; manual entry, sample confirmation, deterministic totals,
and restoration passed owner-iPhone QA. Catalog, live vision, retention automation, deletion, and
editable candidate values remain later Phase 6 work.

**Corrections/deletion/retention local slice verified (2026-07-02).** Candidate names, servings, and
nutrition values are editable before atomic confirmation; owned meals have explicit audited
deletion; and a service-only retention worker claims due non-exempt media, removes private Storage
bytes, then finalizes or retries metadata safely. Flutter passes 40/40, Deno 18/18, pgTAP 141/141,
and the unsigned iOS device build passes at 18.5 MB. Migration `20260702130000` is hosted;
`meal-media-retention` version 3 is ACTIVE, its dedicated secret is held in Edge Function secrets
and Vault, and daily Cron is active at 02:15 UTC. The hosted worker returned HTTP 200 and
unauthenticated access returned 401. A signed 19.2 MB build is installed/launched on the owner's
iPhone; correction and deletion device QA remain pending. Live photo AI and licensed food-catalog
selection remain deferred decisions.

**Draft-resume correction (2026-07-02).** Owner-device review found candidate editing discoverable
only during new sample analysis while an existing draft timeline card was inert. Draft cards now
expose **Review & edit draft** and restore the candidate editor. Flutter passes 41/41 and analysis
is clean. The replacement signed 19.2 MB build is installed and launched on iPhone; owner
verification of the resumed draft remains pending.

**Keyboard correction (2026-07-02).** Owner-device QA found no dismissal route after candidate entry
on the iOS numeric keyboard. Candidate and manual forms now support explicit **Hide keyboard**,
tap-outside dismissal, and drag dismissal. Flutter passes 42/42 and analysis is clean. The
replacement signed 19.2 MB build is installed and launched on iPhone. Owner QA passed draft resume,
candidate editing, keyboard dismissal, confirmation, deletion, totals, and session restoration.
Phase 6 is complete for the approved manual/sample scope; live photo AI and licensed catalog remain
explicitly deferred.

## 8. Phase 7 — Progress and Weekly Review

Implement measurements, private progress bucket, separate consent/RLS, standardized capture,
analysis queue, confidence-qualified comparison, deterministic trends, and Cron-triggered weekly
review.

Exit gate: photo access is scoped and short-lived; AI output is never presented as measurement or
diagnosis.

**Local foundation verified (2026-07-02).** Migration `20260702170000` adds forced-RLS measurements,
progress photo sets/poses, progress reviews, separate storage/AI consent types, a private progress
bucket, an authenticated write RPC, and deterministic weight/waist deltas. Flutter adds honest
empty/baseline/trend states, manual entry, accessible trend summaries, standardized capture
guidance, and an editorial weekly-review preview. Flutter passes 46/46, Deno 18/18, pgTAP 163/163,
analysis, and the unsigned iOS build. Real photo transfer/access/deletion, queues/Cron, and live
progress-photo AI remain deferred beyond this foundation.

**Hosted foundation deployed (2026-07-02).** The reviewed dry-run listed only `20260702170000`;
deployment succeeded and local/remote histories match. A signed hosted-config 19.3 MB build was
installed on the owner's iPhone. CLI launch succeeded after the device was unlocked; foundation
interaction QA passed. Photo transfer, signed reads, queues/Cron, and live photo AI remain
unavailable.

Forward repair `20260702173000` is hosted and requires two distinct measurement dates before a trend
is available. Repeated same-day entries cannot create a false trend, and no stored measurement rows
are changed.

**Owner-device foundation QA passed (2026-07-02).** The hosted signed build successfully saves and
restores measurements and exposes the intended baseline, weekly-review, and private-photo guidance
states on the owner's iPhone.

**Private media slice hosted (2026-07-02).** Migration `20260702200000` adds consent-gated set
creation, upload-verified pose registration, completion, and idempotent deletion. Flutter adds
guided camera capture, partial-set recovery, 60-second private viewing, and destructive deletion.
Flutter passes 46/46, pgTAP 171/171, analysis, and a signed 19.7 MB build. The build is installed
and launched on the owner's iPhone; capture, view, deletion, and pose-prompt QA passed. Gemini is
planned but not called.

**Weekly review slice locally verified (2026-07-02).** Forward migration `20260702223000` adds
durable `pgmq` jobs, daily deduplicating scheduling, five-minute consumption, deterministic
immutable weekly snapshots/reviews, eligibility recheck, bounded retry/terminal failure, owner
acknowledgement, and sanitized audit. Flutter replaces the preview with queued/ready/error/evidence
states. Flutter passes 49/49, full pgTAP passes 200/200, analysis is clean, and the unsigned 18.9 MB
iOS build passes. The reviewed migration is hosted and local/remote histories match. A signed 19 MB
app is installed on the owner's iPhone; launch and interaction QA remain pending while the device is
locked.

**Weekly review device repair (2026-07-03).** The first owner request was rejected before PostgreSQL
because the persisted access token had expired; the refresh token remained valid. Flutter now
refreshes expired sessions during account restoration and immediately before review generation, with
a bounded reauthentication message if recovery fails. Flutter passes 50/50, analysis is clean, and
the signed 19 MB hosted build is installed/launched on the iPhone; the refreshed session was
verified persisted without exposing token contents.

## 9. Phase 8 — Free-Tier Dogfooding and Beta Hardening

Complete export, deletion, retention, notification privacy, telemetry, cost caps, manual
database/Storage backup procedure, incident rehearsal, and device/accessibility testing.

Run owner dogfooding on local/Free Supabase first. Invite a few friends/family on Free only if usage
stays within quota, backups are operating, and possible inactivity pausing/downtime is acceptable.
Upgrade to Pro when reliability or automated daily backups become important; do not upgrade merely
because code exists.

**Notification privacy slice locally verified (2026-07-03).** Flutter and a narrow iOS method
channel expose daily check-in and weekly-review reminders, request permission only on save, schedule
locally, and use generic lock-screen copy. Migration `20260703090000` stores only owner-scoped
toggles/coarse authorization plus append-only consent evidence. Flutter passes 51/51, analysis is
clean, pgTAP passes 210/210, and no notification SDK was added. Hosted migration and signed device
QA require explicit deployment approval. The reviewed migration is now hosted with local/remote
parity. A signed 19 MB build is installed and launched on the owner's iPhone; reminder interaction
QA found that the UI could reset when iOS returned no pending requests after reopen. The client now
reconciles the durable server preference into authorized iOS scheduling. Flutter passes 53/53; the
hosted-config replacement is signed with the active Gmail development identity and
installed/launched on iPhone for reopen QA. A second owner failure showed pending requests cannot
serve as local preference storage. Native booleans now persist independently, repair delivery
requests after reopen, and surface scheduling errors; the physical-device build and Flutter 53/53
pass. The hosted-config replacement is signed, installed, and launched for final reopen QA.

**Phase 8 privacy and operations complete (2026-07-03).** Owner QA confirms notification choices
survive force-close/reopen. Forward migrations `20260703150000` and `20260703170000` add forced-RLS
export/deletion state, opaque queues, recent-auth gates, private export Storage, bounded downloads,
retryable retention, and minimal deletion receipts. `privacy-export` creates a media-inclusive
readable ZIP encrypted with a non-persisted password-derived AES-256-GCM key;
`privacy-delete-account` removes Storage before Auth deletion. Both migrations/functions are hosted,
the existing daily worker handles export cleanup, pgTAP passes 236/236, Deno passes 22/22, and
hosted synthetic export/decrypt/delete QA passes. `BETA_OPERATIONS.md` records Free backup,
recovery, and incident procedures. Destructive device QA remains synthetic-only by design.

**Post-Phase-8 provider readiness (2026-07-03).** The server-only Gemini structured-output adapter
is wired behind environment selection, an off-by- default kill switch, and an explicit paid-service
data-terms gate. Migration `20260703190000` stores validated provider/model/token/cost metadata
through service-only RPCs; it and `coach-decide` version 7 are hosted. With no provider selection
secret, mock remains active. Deno passes 28/28, pgTAP 247/247, Flutter 55/55, analysis, and the
unsigned iPhone build. Live text still needs paid service, provider-control review, full evaluation
parity, and activation.

**Owner continuation import (2026-07-04).** After an encrypted owner-state backup, three forward
migrations added a service-only validated import, imported-plan seed bypass, and timezone-safe
local-date handling. The hosted transaction replaced setup fixtures with newly versioned
owner-confirmed goal, plan, targets, workouts, and progress checkpoints; prior versions remain and
the known fixture measurement is explicitly superseded. The iOS client now performs one bounded
31-day Apple Health backfill, then returns to seven-day overlap sync. pgTAP passes 264/264 and
Flutter passes 56/56. DeepSeek was rejected for restricted data after official privacy review.

## 10. Stability Hardening (2026-07-19)

A 7-phase cross-layer audit applied security, testing, operational, and code-quality hardening while
keeping the full pre-deploy gate green:

| Phase | Scope | Outcome |
|-------|-------|---------|
| 1 | Security guards | JWT enforcement, AI budget re-enabled, Dependabot, Gitleaks pre-commit, CI dep freshness |
| 2 | Backend tests | 4 pgTAP files (74 assertions), 3 Deno test files (35 tests), 4 contract test additions |
| 3 | Operational safeguards | Session pooler, `backup-db.sh`, `rollback-function.sh`, `health-check` Edge Function, structured `_shared/logger.ts` |
| 4 | Code cleanup | `_shared/auth.ts` deduplicating 7 Edge Functions, `TracendLoadingIndicator` widget, 38 catch-block diagnostics, coach screen timer refactor |
| 5 | Observability (Sentry) | Flutter `sentry_flutter` + `beforeSend` scrubber (19 sensitive fields redacted), Edge Function `_shared/sentry.ts`, DSN wired into coach-chat and meal-analyze |
| 6 | Auth hardening | Password min 8 + upper/lower/digit, re-auth for password change, email confirmations, session timeouts deferred (Pro plan) |
| 7 | Documentation sync | Updated testing strategy, progress context, AGENTS.md for backup/rollback/Sentry |

All gates pass: Deno 92 tests, Flutter 85 tests, iOS build 25.1 MB, Edge Functions deployed with
Sentry wiring.

## 11. Deferred Until Measured Need

## 9.1 Production Rebuild

The production rebuild replaces the generic Phase 8 shell with real read models and interaction
contracts: deterministic daily brief, complete training hub, persistent Coach threads, versioned
meal schedules, private meal-photo analysis, dark-default theme selection, and bounded AI budgets.
Forward-only migrations deploy before `coach-chat` and `meal-analyze`; live Gemini remains off until
paid terms and evaluation gates pass. Physical-iPhone installation and QA are the release gate.

Do not add NestJS, Railway, a separate API server, pgvector, autonomous agents, LangGraph, Redis,
microservices, medical reports, Android, subscriptions, social features, or public-store
infrastructure. [ARCHITECTURE.md](./ARCHITECTURE.md) controls adoption.

## 12. Next Action

1. Redownload the owner `.tracendexport` to the external SSD and validate its decryption using
   `BETA_OPERATIONS.md`; never test deletion on the owner.
2. Complete the weekly Free database and private-Storage backup. The pinned CLI direct-host dump is
   blocked by container DNS, so use a reviewed pooler/dashboard path rather than accepting a partial
   backup.
3. Before live Gemini text coaching, enable a paid-service project, document provider data controls,
   run the full text evaluation suite, add provider usage/cost persistence and a kill switch, then
   request deployment.
4. Keep meal/progress vision, licensed catalog, Sign in with Apple, and external beta distribution
   deferred until their existing gates are met.
