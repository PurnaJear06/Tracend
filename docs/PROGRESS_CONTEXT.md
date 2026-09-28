# Tracend Current State

**As of:** 2026-09-28

**Lifecycle:** owner-only private beta; not approved for public production

**Current priority:** make Coach chat answer every question from the full athlete file and never
dead-end (FLUTTER-8). The plan is owner-approved: PR #35 → A1 (server) → A2 (app) → B
(calculators). Finish owner-device acceptance before any UI redesign.

## Shipped baseline

- iOS-only Flutter app backed by Supabase Auth, PostgreSQL/RLS, Storage, and nine Edge Functions.
- Deterministic recovery, sleep, training-load, nutrition, and plan state remains authoritative;
  model output can explain or propose but cannot silently activate durable changes.
- The first Coach chat reliability hotfix is deployed. Two FLUTTER-8 changes are in review, in order:
  - PR #35: typed validation rules, targeted fail-closed repair, fresh coaching-date scores, shared
    daily/chat evidence, whole-section budgeting, the full shared persona, and a scoring-failure
    guard.
  - A1 (stacked on #35): the root-cause fix.
    - Every question gets the same full athlete file (`prepare_coach_chat_v8`); keywords no longer
      remove data.
    - The formatter renders all history, and the question comes last for caching.
    - Accuracy rules stay strict while formatting limits become generous ceilings.
    - Labeled estimates and clarifying questions are allowed.
    - The question is saved before the model runs.
    - DeepSeek failures are recorded with rule names.
    - A labeled data-summary reply replaces the 503 for app request schema 1.1.
    - A live 60-prompt evaluation runs on demand.
    - Review fixes (2026-09-28):
      - Long threads keep their newest messages instead of failing with `chat context too large`.
        That was a 422 before the model ran, pre-existing since July.
      - Data summaries never re-enter the coach's memory.
      - Every blocked turn reaches Sentry, and its 422 names a finite reason.
      - DeepSeek retired V4 Flash on 2026-09-10. The code accepts V4.1 Flash as `deepseek-flash`
        as well as the temporary legacy alias, and cost estimates use V4.1 Flash peak prices.
      - The live evaluation defaults to 12 calls and can run through an OpenAI-compatible router
        as a smoke test.
- HealthKit sleep aggregation handles mixed staged and unspecified intervals without double-counting.
- Fresh-database pgTAP parity, Flutter/Deno tests, iOS compilation, migration collision checks, and
  secret scanning run in CI. Locally:
  - PR #35 passes 124 Deno tests, 422 Flutter tests, 34 pgTAP files / 951 assertions, analysis, an
    unsigned iOS release build, and the linked production migration dry-run.
  - A1 passes 149 Deno tests and, in CI on a fresh database, 35 pgTAP files / 987 assertions,
    including the 36-assertion v8 file.

  The seven required PR checks gate every push; owner merge remains pending.

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

1. Merge PR #35, then A1, after their required CI checks pass (no reinstall).
   - After the deploy, switch the `DEEPSEEK_MODEL` Edge secret to `deepseek-flash`.
   - The DeepSeek regression run is still owed. It is waiting for a DeepSeek key; a NaraRouter
     smoke test can run first.
   - Verify A1 in production with the handoff queries after real iPhone use.
   - Then A2 (app, reinstall) and B (calculators), followed by owner-device acceptance and Sentry
     verification.
2. Approve a coherent visual direction and then redesign from the current product truth; do not
   copy a competitor's protected assets or flows.
3. Complete the Apple AI-consent/App Review review, privacy/legal review, pricing decision, developer
   account/entity decision, and brand/IP clearance before expanding beyond owner dogfooding.
4. Refresh dependencies in small reviewed batches; old Dependabot PRs were based on obsolete code
   and checks and are not release candidates.

## What happens next

The active implementation is the FLUTTER-8 Coach work described in
[`docs/handoff/backend.md`](./handoff/backend.md): PR #35, A1, A2 and B. After merge, automatic
deployment, and owner-device acceptance, return to the read-only product/UI audit and one
owner-approved redesign brief.

## Sources of truth

- Product and system behavior: `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`
- Safety, security, and privacy: `docs/AI_SAFETY_SPEC.md`, `docs/SECURITY_PRIVACY.md`
- UX and visual rules: `docs/UX_FLOWS.md`, `docs/DESIGN_SYSTEM.md`
- Algorithms and tests: `docs/ALGORITHMS.md`, `docs/TESTING_STRATEGY.md`
- Release process: `docs/CI_CD_DEPLOYMENT.md`
- Historical progress, plans, and handoffs: `docs/archive/`

Historical artifacts explain prior decisions but are not instructions for current work.
