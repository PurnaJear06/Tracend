# Tracend Current State

**As of:** 2026-10-09

**Lifecycle:** owner-only private beta; not approved for public production

**Security hardening (2026-10-09):** a source review of `d26cf2c` raised leads that the owner
asked to fix in five PRs, merged in order; details stay in the owner's private report. PR 1
(media key grammar and ownership, a key guard on every service-role Storage call, the Coach
preference caller check, restore-drill log output) is in review. Workstream state:
[`docs/handoff/security-hardening.md`](./handoff/security-hardening.md).

**Current priority (2026-10-03):** the app-wide graphite + lime redesign. The owner chose palette
A and the round 3 signature picks (focus logging, muscle map on, big new-best moment, day boxes,
white and lime icon) and asked for parallel delivery against a five-hour window. Delivery is now
two integrated pull requests instead of ten: the foundation (backend data, workout logging and
Train data layers, tokens, Archivo, shared widgets, tab bar, icon, launch and intro), then the six
screens, built in parallel. Device checks drop to two: after the foundation, and after the screens
with a real workout. Workstream state: [`docs/handoff/redesign.md`](./handoff/redesign.md). The
foundation (#78) merged and deployed on 2026-10-03 (`12f5bbb`, migration applied); the six screens
are integrated in one PR. The installed app sends the fixed session effort of 8 until the screens
PR ships the new logging. Older plans' exercises are linked to the catalog by exact name (#80, SQL
only) so the Train muscle map can light them; #81 added reviewed muscles for the names the
catalog lacks (build 329 installed). Today's food card is now the fuel rail: protein to go and
the day's meals on a line, since Nutrition already holds the full ledger. Meal slot status
(`due`, `upcoming`, `skipped`) now follows the athlete's time zone instead of UTC (SQL only, no
reinstall).
Today was rebuilt on 2026-10-04 around the owner's chosen prototype: a recovery tick ring split by
driver, a morning check-in gate in place of the tab bar, Sleep/Load/Fuel tiles, a session strip that
fills as sets are logged, and the week as recovery ticks (brief 1.7, migration first, then install).
Recovery then gained two modes (owner report, 2026-10-04: "around 10, and it changes"): a night with
the watch scores that night against nights; without one, a morning estimate scores the morning's
HRV against mornings plus the check-in and settles at noon. Resting HR is yesterday's final value
(brief 1.8, scoring 2.3, migration first, then install).

**Previous priority:** UI polish, so the app reads as a finished consumer product rather than a
beta full of logs. The owner approved the plan on 2026-10-01 and chose to start it before the full
owner-device acceptance checklist. Order: Progress (P1) → Nutrition (P2) → Today, Train, Coach,
Account (P3–P6). Workstream state: [`docs/handoff/ui-polish.md`](./handoff/ui-polish.md).

Progress (#56) and Nutrition (#57) merged on 2026-10-01, and build 235 (main 46c892b) is installed.
The owner liked Progress but found Nutrition ordinary, and chose option A's row style for Today's
meals only (#58). P3–P6 wait for the owner's device check on the new build.

The FLUTTER-8 Coach work is shipped: PR #35, A1, A2, and B are live (B at main 21c3b55, build 225).
The direct DeepSeek evaluation is still unmeasured, and the owner's device check on build 225 is
open; see [`docs/handoff/backend.md`](./handoff/backend.md).

New-user onboarding: a 2026-10-01 audit found the onboarding plan is still the Phase-2 mock, and
it ignores goal, equipment and session length. The approved plan is not the delivered plan, and
reopening on the proposal step spins forever. The owner chose an AI-proposed plan, validated by
deterministic code, with a swappable provider. PR 1 fixes Today's workout date, Start session, and
the Coach's proposal line. PR 2 (server, in review) adds per-purpose AI notices, an exercise
catalog, `onboarding-policy-v1` and the new `onboarding-plan` function (any provider, set by secrets,
with a rules fallback). Review fixes on PR 2: movements to avoid enforced on every path, daily
coaching checks its own notice, nutrition capped to the database bounds with infeasible answers
refused up front, billed failures counted, and expired proposals recoverable. PR 3 (app) adds the
new onboarding steps (including movements to avoid), a resumable plan build, the full proposal
screen, expired-plan recovery and the server-rendered AI notice. All three merged and deployed
2026-10-02 (`c0931ef`), with the eval fixes (#63, #64, `dd76316`); the app is installed and the
`ONBOARDING_PLAN_*` secrets are set, so consenting athletes get a DeepSeek plan. The final
onboarding batch is four stacked PRs: A turns on thinking for the first attempt (setting
`ONBOARDING_PLAN_THINKING`, default on) and stores call telemetry in the audit event; B publishes notice
`ai-coaching-v4` for every purpose (fixing new athletes' grants never counting for the plan),
stores the device time zone, feeds a 28-day Apple Health summary into the plan, and keeps
movements to avoid on the profile for the Coach; C adds the optional Apple Health onboarding step
(weight and activity shown from it, a 31-date first sync, health state per athlete, the device
time zone stored); D fixes onboarding's remaining flaws (draft
restore that could overwrite answers, duplicate consent records, review with Edit, steppers,
2x-text layout, reject confirmation, a "You're set" screen, the profile's onboarding answers). Evals run
through NaraRouter only (owner's decision). All four merged and deployed 2026-10-02 (c35946c) and
the app is installed. On the owner's fresh account the AI plan worked (thinking, 38 s) but felt
generic, so a **coach-quality batch** of three PRs follows: (1) coach intake — training years,
barbell top sets turned into starting loads, up to two focus muscles with weekly set minimums,
0–3 follow-up questions from the coach, and Apple Health usual months against the last 28 days
(`onboarding-policy-v2`, merged in #70 and deployed `a716afb`, build 273 installed); (2) an
owner-only physique check on progress photos: Groq suggests muscles to develop from one photo set
under its own notice, and the athlete confirms up to two as their focus (merged in #72, deployed
`9995cc3`, on for the owner only; see
[`docs/handoff/physique-check.md`](./handoff/physique-check.md)); (3) calibration and a stale-safe
re-plan from two weeks of logged sets. See
[`docs/handoff/onboarding.md`](./handoff/onboarding.md).

Account deletion recovery (owner report 2026-10-02, build 273): after **Delete account** spun
and the app was force-closed, it opened on "Connection needed" for a deleted account. The gate
never asked Auth whether a stored, unexpired session's account still existed, and the deletion
request had no timeout. The fix (in review) validates the session with Auth on launch, signs out
on any refusal, bounds the deletion wait with server confirmation and **Check again**, stores the
pending check-in per athlete, and lets a stopped deletion be claimed again (additive migration).
Needs a reinstall. See [`docs/handoff/account-session.md`](./handoff/account-session.md).

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
  - A2 (#41, merged 2026-09-29): the app side.
    - The app sends request 1.1, so a model failure shows a labeled data summary or safety note,
      with Retry and the beta diagnostic.
    - Coach reopens the last conversation and creates a thread on its first send.
    - It lists only conversations that contain a message (`get_my_coach_threads`).
    - The first install (build 185) had no font files, so every icon showed as a "?" box. Its
      build folder was shared with other checkouts. A rebuild from the same commit, with every font
      present, replaced it the same day (see
      [Device installs](./CI_CD_DEPLOYMENT.md#device-installs)).
- HealthKit sleep aggregation handles mixed staged and unspecified intervals without double-counting.
- Owner batch, 2026-09-29/30 (PRs #42–#49, all deployed):
  - each checkout builds in its own folder, and installs refuse an app bundle without its fonts;
  - AI coaching consent in onboarding and Account, with Coach and Today gated in the app;
  - Coach replies render bold, italic and lists;
  - meal-photo failures show under the buttons and reach Sentry;
  - meal photos run on Groq `qwen/qwen3.8-27b` on the free tier, which allows 1,000 output tokens a
    minute (about one photo a minute);
  - the owner AI budget is USD 1 warning, USD 2 stop, 30 requests a day;
  - `sentry_flutter` 9.30.1 with matching iOS pods.
- Fresh-database pgTAP parity, Flutter/Deno tests, iOS compilation, migration collision checks, and
  secret scanning run in CI. Locally:
  - PR #35 passes 124 Deno tests, 422 Flutter tests, 34 pgTAP files / 951 assertions, analysis, an
    unsigned iOS release build, and the linked production migration dry-run.
  - A1 passes 157 Deno tests and, in CI on a fresh database, every pgTAP file, including the
    45-assertion v8 file and the 7-assertion scoring-guard file.
  - A2 passes 443 Flutter tests and 159 Deno tests. Its 7-assertion thread-list pgTAP file runs
    in CI.

  The seven required PR checks gate every push.

## Release controls

- `main` accepts reviewed pull requests with all required checks passing.
- Every agent follows the delivery workflow in `AGENTS.md`: a worktree and pull request per change,
  no hook or branch-protection bypass, and no agent merges. The owner merges.
- Deployment waits for successful CI on the exact merged `main` commit.
- Failed, missing, empty, checksum-invalid, or non-restorable database backups stop deployment.
- Production dumps are restore-drilled in an isolated local Supabase database before migration.
- The encrypted backup is stored in a separate private repository by `scripts/store-backup.sh`
  (newest 30 kept), never as a workflow artifact: artifacts of a public repository are downloadable
  by any signed-in GitHub user.
- Edge Functions deploy one at a time, and each is confirmed live by comparing the deployed source
  with the commit; the release tag waits for that check. On 2026-09-28, parallel deploys had
  reported success while Supabase kept the previous version of four functions. Supabase's
  intermittent deploy 500 is retried automatically (`scripts/deploy-function.sh`).
- Semantic versions come from `pubspec.yaml`; build numbers are monotonic in CI and derived from Git
  history for local device builds.
- Each checkout builds in its own folder. The device installer refuses an app bundle without its
  fonts and asset manifests, and CI checks the same on its iOS build.

See [CI_CD_DEPLOYMENT.md](./CI_CD_DEPLOYMENT.md) for the executable release contract.

## Open release blockers

These are not silently considered complete:

1. Coach chat: A1's server code is live. End-to-end acceptance remains open:
   - Done on 2026-09-28: `DEEPSEEK_MODEL` is `deepseek-flash`, and afterwards all nine live
     functions matched the released commit (`./scripts/verify-live-function.sh --all`).
   - The DeepSeek regression run is still owed; it needs a DeepSeek key. A NaraRouter run on
     2026-09-29 answered 27 of 30 (90% against the 97% gate):
     - every safety prompt was handled safely, with no dead ends and no unpermitted evidence;
     - the 3 misses were invalid JSON from the router on the largest synthetic athlete.
   - Measure A1 in production with the handoff queries after real iPhone use.
   - A2 is merged, deployed, and reinstalled with the app's `SENTRY_DSN`. The owner's A2 device
     check in the handoff is next.
   - B (calculators, `_shared/coach_calculations.ts`) is in review. Its merge gate is the direct
     DeepSeek eval, before and after. Then owner-device acceptance and Sentry verification.
2. Meal photos need their own AI consent before anyone other than the owner uses them: the AI
   coaching notice covers DeepSeek and says photos are not sent, but meal photos go to Groq. See the
   backend handoff, "Meal photos".
3. Approve a coherent visual direction and then redesign from the current product truth; do not
   copy a competitor's protected assets or flows.
4. Complete the Apple AI-consent/App Review review, privacy/legal review, pricing decision, developer
   account/entity decision, and brand/IP clearance before expanding beyond owner dogfooding.
5. Refresh dependencies in small reviewed batches; old Dependabot PRs were based on obsolete code
   and checks and are not release candidates.
   - Batch 1 (2026-09-30): `supabase_flutter` 2.17.2, `shared_preferences` 2.5.5, `uuid` 4.6.0,
     and in-range transitive updates. The passkeys and `ua_client_hints` pods left with the old
     `gotrue`. A network failure during a function call now arrives as `FunctionsFetchException`,
     so Health maps it to "Connection lost" (`healthSyncFailureMessage`).
   - `health` 13.3.2 (2026-09-30, after batch 1): it rewrote its iOS plugin in Swift. The iOS
     release build fails with "Definition of 'HealthPlugin' must be imported from module
     'health.Swift'" only in a checkout that built 13.3.1 before: `flutter clean` leaves the old
     `HealthPlugin.h` in that checkout's `build/ios/Release-iphoneos/health` (`build` links to the
     checkout's own build folder under `.tooling`). Delete that folder once. CI builds from scratch. Its new iOS 15 minimum is below the app's 17.
   - GitHub Actions: `actions/checkout` v4 → v5 and the last `supabase/setup-cli@v1` → v2, for the
     Node.js 20 deprecation warning GitHub showed on every job.
   - Majors not taken: `cupertino_icons` 2.0.0 and the pinned `device_info_plus` override.

## What happens next

UI polish, one PR per screen, in the order in [`docs/handoff/ui-polish.md`](./handoff/ui-polish.md).
Each PR changes only Flutter code and docs, so it needs a device install from merged `main` and no
backend deploy. AI coaching needs the athlete's consent, asked in onboarding and once for existing
accounts; for server enforcement status, see the backend handoff, "AI coaching consent".

## Sources of truth

- Product and system behavior: `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`
- Safety, security, and privacy: `docs/AI_SAFETY_SPEC.md`, `docs/SECURITY_PRIVACY.md`
- UX and visual rules: `docs/UX_FLOWS.md`, `docs/DESIGN_SYSTEM.md`
- Algorithms and tests: `docs/ALGORITHMS.md`, `docs/TESTING_STRATEGY.md`
- Release process: `docs/CI_CD_DEPLOYMENT.md`
- Historical progress, plans, and handoffs: `docs/archive/`

Historical artifacts explain prior decisions but are not instructions for current work.
