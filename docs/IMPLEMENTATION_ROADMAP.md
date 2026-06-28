# Tracend Implementation Roadmap

**Status:** Execution order for the private-beta MVP  
**Constraint:** This roadmap does not expand [PRD.md](./PRD.md)  
**Backend:** Supabase Auth, PostgreSQL, Storage, Edge Functions, Queues, and Cron

Build complete vertical slices instead of every screen, table, or AI component separately.

## 1. Decisions Before Scaffolding

- minimum iOS version and device matrix;
- Flutter/Dart and Supabase CLI version pinning;
- app identifier, Apple team, and TestFlight environments;
- Supabase project region nearest initial users;
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
- CI for formatting, analysis, tests, migration lint, RLS tests, Edge Functions, and Flutter build; and
- `DEVELOPMENT_GUIDE.md` containing only verified commands.

Exit gate: a clean checkout starts the local Supabase stack and Flutter app; no secret/service-role key appears in the client; design/accessibility smoke tests pass.

## 3. Phase 2 — Supabase Auth, Onboarding, and Approval

`Native Sign in with Apple → Supabase Auth → eligibility/consent → onboarding → deterministic snapshot → mocked proposal → explicit approval → transactional activation`

Start with a mocked provider response using the final schema. Implement `auth.users` linkage, `user_accounts`, RLS, consent, versioning, transactional RPC, audit, and cross-user tests before live AI.

Exit gate: two isolated users complete both onboarding paths; anonymous/cross-user access fails; invalid output cannot activate a plan; exactly one approved version is active.

## 4. Phase 3 — Workout and Check-In

Deliver approved-plan reads under RLS, offline set logging, local autosave, idempotent sync, completion/amendment RPC, check-in, deterministic features, and Today states using fixture decisions.

Exit gate: a session survives interruption/offline use without lost, duplicated, or cross-user sets.

## 5. Phase 4 — HealthKit Summaries

Add contextual permissions, `HealthDataSource`, normalized summaries, authenticated `health-sync` Edge Function, idempotency, provenance, freshness, partial/unknown states, and manual fallback.

Exit gate: malformed/duplicate/cross-user sync fails safely and Today works without HealthKit.

## 6. Phase 5 — Controlled Coaching

Implement Edge Function workflow: snapshot → deterministic policy → bounded context → one provider call → validation → decision persistence. Add evaluation and per-user cost/rate controls before live decisions.

Exit gate: provider failure leaves plans usable; safety fixtures pass 100%; each decision cites its snapshot; AI/provider keys stay in Edge Function secrets.

## 7. Phase 6 — Nutrition and Meals

Implement targets, licensed catalog, manual meals, private Supabase Storage meal bucket, Storage RLS, vision queue, candidate editor, transactional confirmation, retention Cron, and deletion.

Exit gate: unconfirmed AI never affects totals; failure permits manual logging; another user cannot list/read meal objects.

## 8. Phase 7 — Progress and Weekly Review

Implement measurements, private progress bucket, separate consent/RLS, standardized capture, analysis queue, confidence-qualified comparison, deterministic trends, and Cron-triggered weekly review.

Exit gate: photo access is scoped and short-lived; AI output is never presented as measurement or diagnosis.

## 9. Phase 8 — Free-Tier Dogfooding and Beta Hardening

Complete export, deletion, retention, notification privacy, telemetry, cost caps, manual database/Storage backup procedure, incident rehearsal, and device/accessibility testing.

Run owner dogfooding on local/Free Supabase first. Invite a few friends/family on Free only if usage stays within quota, backups are operating, and possible inactivity pausing/downtime is acceptable. Upgrade to Pro when reliability or automated daily backups become important; do not upgrade merely because code exists.

## 10. Deferred Until Measured Need

Do not add NestJS, Railway, a separate API server, pgvector, autonomous agents, LangGraph, Redis, microservices, medical reports, Android, subscriptions, social features, or public-store infrastructure. [ARCHITECTURE.md](./ARCHITECTURE.md) controls adoption.

## 11. Next Action

Authorize Phase 1 only. Supabase Free/local is the default. Provider/catalog details may remain behind interfaces and mocks until their phases.
