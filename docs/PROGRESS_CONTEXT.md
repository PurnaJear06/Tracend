# Tracend Current State

**As of:** 2026-09-23

**Lifecycle:** owner-only private beta; not approved for public production

**Current priority:** release foundation complete before any UI redesign

## Shipped baseline

- iOS-only Flutter app backed by Supabase Auth, PostgreSQL/RLS, Storage, and nine Edge Functions.
- Deterministic recovery, sleep, training-load, nutrition, and plan state remains authoritative;
  model output can explain or propose but cannot silently activate durable changes.
- Coach chat reliability hotfix is merged and deployed. Device acceptance remains a separate check
  from CI, deployment, and installation.
- HealthKit sleep aggregation handles mixed staged and unspecified intervals without double-counting.
- Fresh-database pgTAP parity, Flutter/Deno tests, iOS compilation, migration collision checks, and
  secret scanning run in CI.

## Release controls

- `main` accepts reviewed pull requests with all required checks passing.
- Deployment waits for successful CI on the exact merged `main` commit.
- Failed, missing, empty, checksum-invalid, or non-restorable database backups stop deployment.
- Production dumps are restore-drilled in an isolated local Supabase database before migration.
- Semantic versions come from `pubspec.yaml`; build numbers are monotonic in CI and derived from Git
  history for local device builds.

See [CI_CD_DEPLOYMENT.md](./CI_CD_DEPLOYMENT.md) for the executable release contract.

## Open release blockers

These are not silently considered complete:

1. Complete a structured owner-device regression pass on the latest installed build, including the
   exact recovery Coach prompt and Sentry verification.
2. Approve a coherent visual direction and then redesign from the current product truth; do not
   copy a competitor's protected assets or flows.
3. Complete the Apple AI-consent/App Review review, privacy/legal review, pricing decision, developer
   account/entity decision, and brand/IP clearance before expanding beyond owner dogfooding.
4. Refresh dependencies in small reviewed batches; old Dependabot PRs were based on obsolete code
   and checks and are not release candidates.

## What happens next

No implementation plan is active after this release-foundation stage. The next work item is a
read-only product and UI audit that produces one owner-approved redesign brief. Only then should a
new scoped plan and branch be created.

## Sources of truth

- Product and system behavior: `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`
- Safety, security, and privacy: `docs/AI_SAFETY_SPEC.md`, `docs/SECURITY_PRIVACY.md`
- UX and visual rules: `docs/UX_FLOWS.md`, `docs/DESIGN_SYSTEM.md`
- Algorithms and tests: `docs/ALGORITHMS.md`, `docs/TESTING_STRATEGY.md`
- Release process: `docs/CI_CD_DEPLOYMENT.md`
- Historical progress, plans, and handoffs: `docs/archive/`

Historical artifacts explain prior decisions but are not instructions for current work.
