# Tracend Current State

**As of:** 2026-09-28

**Lifecycle:** owner-only private beta; not approved for public production

**Current priority:** make Coach chat answer every question from the full athlete file and never
dead-end (FLUTTER-8). The plan is owner-approved: PR #35 → A1 (server) → A2 (app) → B
(calculators). PR #35 and A1's server code are live; an owner spot check passed on 2026-09-28.
A2 is next. Finish the full owner-device acceptance checklist before any UI redesign.

## Shipped baseline

- iOS-only Flutter app backed by Supabase Auth, PostgreSQL/RLS, Storage, and nine Edge Functions.
- Deterministic recovery, sleep, training-load, nutrition, and plan state remains authoritative;
  model output can explain or propose but cannot silently activate durable changes.
- Coach chat reliability (FLUTTER-8) is live. PR #35 and A1 (#36) merged on 2026-09-28, and A1 has
  been live since a 10:50 UTC redeploy (see Release controls):
  - PR #35: typed validation rules, targeted fail-closed repair, fresh coaching-date scores, shared
    daily/chat evidence, whole-section budgeting, the full shared persona, and a scoring-failure
    guard.
  - A1 (#36): the root-cause fix.
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
      - The live evaluation runs 17 calls by default, always including every safety prompt, and
        can run through an OpenAI-compatible router as a smoke test.
    - Second review fixes (2026-09-28):
      - A data summary for a message that may be about a health risk is a safety referral
        without numbers, and every summary ends with that referral.
      - A scoring failure no longer blocks the day's first chat (`prepare_daily_coaching` guard).
      - A retried request returns its first attempt's outcome instead of the thread list.
      - Watch averages carry a day count per metric.
      - The installed app still gets the 503 on a model failure until A2, by design.
- HealthKit sleep aggregation handles mixed staged and unspecified intervals without double-counting.
- Fresh-database pgTAP parity, Flutter/Deno tests, iOS compilation, migration collision checks, and
  secret scanning run in CI. Locally:
  - PR #35 passes 124 Deno tests, 422 Flutter tests, 34 pgTAP files / 951 assertions, analysis, an
    unsigned iOS release build, and the linked production migration dry-run.
  - A1 passes 157 Deno tests and, in CI on a fresh database, every pgTAP file, including the
    45-assertion v8 file and the 7-assertion scoring-guard file.

  The seven required PR checks gate every push.

## Release controls

- `main` accepts reviewed pull requests with all required checks passing.
- Every agent follows the delivery workflow in `AGENTS.md`: a worktree and pull request per change,
  no hook or branch-protection bypass, and no agent merges. The owner merges.
- Deployment waits for successful CI on the exact merged `main` commit.
- Failed, missing, empty, checksum-invalid, or non-restorable database backups stop deployment.
- Production dumps are restore-drilled in an isolated local Supabase database before migration.
- Edge Functions deploy one at a time, and each is confirmed live by comparing the deployed source
  with the commit; the release tag waits for that check. On 2026-09-28, parallel deploys had
  reported success while Supabase kept the previous version of four functions.
- Semantic versions come from `pubspec.yaml`; build numbers are monotonic in CI and derived from Git
  history for local device builds.

See [CI_CD_DEPLOYMENT.md](./CI_CD_DEPLOYMENT.md) for the executable release contract.

## Open release blockers

These are not silently considered complete:

1. Coach chat: A1's server code is live. End-to-end acceptance remains open:
   - After the #40 deploy passes, switch the `DEEPSEEK_MODEL` Edge secret from the legacy alias
     `deepseek-v4-flash` to `deepseek-flash`, then run `./scripts/verify-live-function.sh --all`
     from the deployed commit. `UPDATED_AT` does not prove that the source stayed live.
   - The DeepSeek regression run is still owed. It is waiting for a DeepSeek key; the NaraRouter
     smoke run on 2026-09-28 was too slow to measure pass rates.
   - Measure A1 in production with the handoff queries after real iPhone use.
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
[`docs/handoff/backend.md`](./handoff/backend.md). PR #35 and A1 are live. A2 (app) is next, in its
own PR, then B. After owner-device acceptance, return to the read-only product/UI audit and one
owner-approved redesign brief.

## Sources of truth

- Product and system behavior: `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`
- Safety, security, and privacy: `docs/AI_SAFETY_SPEC.md`, `docs/SECURITY_PRIVACY.md`
- UX and visual rules: `docs/UX_FLOWS.md`, `docs/DESIGN_SYSTEM.md`
- Algorithms and tests: `docs/ALGORITHMS.md`, `docs/TESTING_STRATEGY.md`
- Release process: `docs/CI_CD_DEPLOYMENT.md`
- Historical progress, plans, and handoffs: `docs/archive/`

Historical artifacts explain prior decisions but are not instructions for current work.
