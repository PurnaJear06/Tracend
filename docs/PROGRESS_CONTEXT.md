# Tracend Current State

**As of:** 2026-09-27

**Lifecycle:** owner-only private beta; not approved for public production

**Current priority:** review and merge the FLUTTER-8 Coach reliability/accuracy hotfix, then complete
owner-device acceptance before any UI redesign

## Shipped baseline

- iOS-only Flutter app backed by Supabase Auth, PostgreSQL/RLS, Storage, and nine Edge Functions.
- Deterministic recovery, sleep, training-load, nutrition, and plan state remains authoritative;
  model output can explain or propose but cannot silently activate durable changes.
- The first Coach chat reliability hotfix is deployed. A second FLUTTER-8 hardening change is in
  review: typed validation rules, targeted fail-closed repair, fresh coaching-date scores, shared
  daily/chat evidence derivation, whole-section context budgeting, word-boundary routing, the full
  shared coach persona on every provider, and a scoring-failure guard that keeps chat available.
- HealthKit sleep aggregation handles mixed staged and unspecified intervals without double-counting.
- Fresh-database pgTAP parity, Flutter/Deno tests, iOS compilation, migration collision checks, and
  secret scanning run in CI. The FLUTTER-8 branch passes 124 Deno tests locally (131 with the
  database contract environment), 422 Flutter tests, 34 pgTAP files / 951 assertions, analysis, an
  unsigned iOS release build, and the linked production migration dry-run. The seven required PR
  checks gate every push; owner review and merge remain pending.

## Release controls

- `main` accepts reviewed pull requests with all required checks passing.
- Every agent follows the delivery workflow in `AGENTS.md`: a worktree and pull request per change,
  no hook or branch-protection bypass, and no agent merges. The owner merges.
- Deployment waits for successful CI on the exact merged `main` commit.
- Failed, missing, empty, checksum-invalid, or non-restorable database backups stop deployment.
- Production dumps are restore-drilled in an isolated local Supabase database before migration.
- Semantic versions come from `pubspec.yaml`; build numbers are monotonic in CI and derived from Git
  history for local device builds.

See [CI_CD_DEPLOYMENT.md](./CI_CD_DEPLOYMENT.md) for the executable release contract.

## Open release blockers

These are not silently considered complete:

1. Review and merge the FLUTTER-8 hotfix after all required CI checks pass, then complete the nine
   owner-device Coach prompts and Sentry verification. No reinstall is expected for this Edge/SQL
   change.
2. Approve a coherent visual direction and then redesign from the current product truth; do not
   copy a competitor's protected assets or flows.
3. Complete the Apple AI-consent/App Review review, privacy/legal review, pricing decision, developer
   account/entity decision, and brand/IP clearance before expanding beyond owner dogfooding.
4. Refresh dependencies in small reviewed batches; old Dependabot PRs were based on obsolete code
   and checks and are not release candidates.

## What happens next

The active implementation is the isolated FLUTTER-8 Coach hotfix described in
[`docs/handoff/backend.md`](./handoff/backend.md). After merge, automatic deployment, and owner-device
acceptance, return to the read-only product/UI audit and one owner-approved redesign brief.

## Sources of truth

- Product and system behavior: `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`
- Safety, security, and privacy: `docs/AI_SAFETY_SPEC.md`, `docs/SECURITY_PRIVACY.md`
- UX and visual rules: `docs/UX_FLOWS.md`, `docs/DESIGN_SYSTEM.md`
- Algorithms and tests: `docs/ALGORITHMS.md`, `docs/TESTING_STRATEGY.md`
- Release process: `docs/CI_CD_DEPLOYMENT.md`
- Historical progress, plans, and handoffs: `docs/archive/`

Historical artifacts explain prior decisions but are not instructions for current work.
