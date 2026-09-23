# Tracend Stability & Hardening — 7-Phase Plan

**Created**: 2026-07-19 **Goal**: Close all security, testing, operational, and code-quality gaps
from the 4-dimension audit. **Hard constraint**: Nothing breaks. Every phase gates on
`./scripts/pre-deploy.sh` passing.

---

## Phase 1: Security Guards

**Risk**: Zero. Config-only changes.

| #   | Action                                                                                                                         | Break risk                                    |
| --- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------- |
| 1.1 | Add `verify_jwt = true` to `supabase/config.toml` for `coach-chat`, `meal-analyze`, `privacy-delete-account`, `privacy-export` | None — they already validate JWT manually     |
| 1.2 | Re-enable `assert_owner_ai_budget` call in `coach-chat/index.ts` (~line 93) and `meal-analyze/index.ts` (~line 38)             | None — RPC exists, tested, capped at $2/month |
| 1.3 | Add `.github/dependabot.yml` for Flutter pub + GitHub Actions                                                                  | None — CI-only                                |
| 1.4 | Add `.pre-commit-config.yaml` with `gitleaks` hook for secret scanning                                                         | None — dev tooling only                       |
| 1.5 | Add `flutter pub outdated --no-transitive` + `deno outdated` step to CI workflow                                               | None — CI-only                                |

**Gate**: `./scripts/pre-deploy.sh` passes. iPhone login still works.

---

## Phase 2: Test Gap Closure — Backend

**Risk**: Zero. Additive — new test files only, zero production code touched.

| #   | Action                                                                                                                                                                                                |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2.1 | pgTAP: `healthkit_auto_complete_workout` (auth, cross-user, idempotency, missing-HealthKit guard, inactive-plan guard, audit event)                                                                   |
| 2.2 | pgTAP: `get_healthkit_completion_candidate` (5 states: candidate present, no HK data, already completed, no matching weekday, cross-user)                                                             |
| 2.3 | pgTAP: `persist_health_workouts`, `correct_completed_workout`, `get_my_workout_repair_candidates`, `get_my_workout_reconciliation_candidates`, `respond_workout_reconciliation`                       |
| 2.4 | pgTAP: `create_meal_photo_draft`, `persist_meal_photo_candidates`, `confirm_analyzed_meal`, `save_scheduled_manual_meal`                                                                              |
| 2.5 | Deno handler test: `coach-chat/index.ts` — `detectPreferenceStatement()` (6 regex patterns), `buildSessionSummary()`, idempotent replay, FTS integration, session summary persistence, error fallback |
| 2.6 | Deno handler test: `deterministicBoundary()` — chest pain, heart attack, diagnose, prescribe, medication, suicidal → all must return `emergencyRedirect` or `clinicalDisclosure`                      |
| 2.7 | Deno handler test: `coach-decide`, `health-sync`, `meal-analyze`, `onboarding-propose-plan`                                                                                                           |
| 2.8 | Update `db_contract_test.ts` to cover new RPC response shapes                                                                                                                                         |

**Gate**: `./scripts/pre-deploy.sh --db-only` passes with all new pgTAP assertions.

---

## Phase 3: Operational Safeguards

**Risk**: Very low. Tools and additive code only.

| #   | Action                                                                                                  | Break risk                        |
| --- | ------------------------------------------------------------------------------------------------------- | --------------------------------- |
| 3.1 | Enable Supabase Session Pooler on hosted project (free tier, port 6543)                                 | None — additive                   |
| 3.2 | Write `scripts/backup-db.sh`: `pg_dump` via pooler → `.tooling/backups/YYYY-MM-DD/` + SHA-256 manifest  | None — read-only                  |
| 3.3 | Write `scripts/rollback-function.sh <name>`: query deploy history, redeploy prior version               | None — tool only                  |
| 3.4 | Add `supabase/functions/health-check/index.ts` — returns DB connectivity + version, no auth             | None — new function               |
| 3.5 | Add `_shared/logger.ts` — correlation ID propagation + JSON-structured logging with `LOG_LEVEL` env var | Low — additive import             |
| 3.6 | Wire new logger into `coach-chat` and `meal-analyze` handlers                                           | Low — existing `console.*` remain |

**Gate**: `./scripts/backup-db.sh` produces valid SQL dump. Health check returns 200. Edge Functions
still deploy.

---

## Phase 4: Code Cleanup

**Risk**: Medium. Structural refactors. Mitigation: one file at a time, test after each.

| #   | Action                                                                                                           | Break risk                                             |
| --- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| 4.1 | Extract `_shared/auth.ts` — `requireAuth(request)` + `reply(status, body)` — deduplicate across 7 Edge Functions | Medium — extract one function at a time, deploy-verify |
| 4.2 | Delete `supabase/functions/privacy-export-retention/` (empty orphan directory)                                   | None                                                   |
| 4.3 | Comment `20260716122000` migration: "supersedes 20260716121000 for same prepare_coach_chat_v4"                   | None — comment only                                    |
| 4.4 | Extract `TracendLoadingIndicator` widget (5 identical `CircularProgressIndicator(strokeWidth: 2)`)               | Low                                                    |
| 4.5 | Add `debugPrint('Non-critical error: $e')` in 38 `catch (_)` blocks                                              | None — no-op in release                                |
| 4.6 | Fix `coach_screen.dart:70` — replace `setState((){})` timer hack with `Stream.periodic` + `StreamBuilder`        | Medium — write widget test first                       |
| 4.7 | Move `FixtureXxxRepository` classes from `lib/features/*/` to `test/helpers/`                                    | Medium — 8 files, all imports updated                  |

**Gate**: `./scripts/pre-deploy.sh --flutter-only` 85 tests pass. `--deno-only` 58+ tests pass.
iPhone build.

---

## Phase 5: Observability (Sentry)

**Risk**: Very low. Sentry is a no-op when DSN is empty.

**DSN**:
`https://6d3f662b0d2eda3941ad9b529c2d3446@o4511762519490560.ingest.us.sentry.io/4511762526830592`
**Org**: `purnajear` / **Project**: `flutter`

| #   | Action                                                                                                                                                                            | Break risk            |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| 5.1 | Add `sentry_flutter: ^9.0.0` to `pubspec.yaml`                                                                                                                                    | None                  |
| 5.2 | `SentryFlutter.init` in `main.dart` — DSN via `--dart-define SENTRY_DSN` (empty = disabled). `beforeSend` scrubber strips HealthKit values, meal content, photo URLs, prompt text | None                  |
| 5.3 | `runZonedGuarded` + `FlutterError.onError` → Sentry bridge                                                                                                                        | None                  |
| 5.4 | HTTP-based `Sentry.captureException` in Edge Function error paths (coach-chat, meal-analyze)                                                                                      | None — fails silently |
| 5.5 | Throw test error → verify Sentry ingestion → remove test code                                                                                                                     | None                  |

**Gate**: App launches fine with `SENTRY_DSN=""`. With DSN set, test error appears in dashboard.
iPhone build.

---

## Phase 6: Auth Hardening

**Risk**: Low. Hosted Supabase Auth Dashboard settings. Existing user unaffected.

| #   | Action                                                                       | Break risk                             |
| --- | ---------------------------------------------------------------------------- | -------------------------------------- |
| 6.1 | Set password min length 8, require upper+lower+digit in hosted Auth settings | None — existing user not affected      |
| 6.2 | Enable `secure_password_change = true` (re-auth required to change password) | None                                   |
| 6.3 | Enable `enable_confirmations = true` (email verification on new signups)     | None — existing user already confirmed |
| 6.4 | Set `inactivity_timeout` = 7 days, session `timebox` = 30 days               | Low — generous windows                 |
| 6.5 | Test login flow on iPhone after all changes                                  | —                                      |

**Deferred**: MFA (MVP constraint — no multi-user), CAPTCHA (no bot threat yet), SMTP (needs
provider)

**Gate**: iPhone login works. Password change prompts re-auth. Session persists.

---

## Phase 7: Documentation

**Risk**: None. Docs only.

| #   | Action                                                                                             |
| --- | -------------------------------------------------------------------------------------------------- |
| 7.1 | `IMPLEMENTATION_ROADMAP.md` — mark Phases 1–8 complete, remove future-tense delivery language      |
| 7.2 | `TESTING_STRATEGY.md` — add Sentry crash reporting, backup procedure, health check, auth hardening |
| 7.3 | `PROGRESS_CONTEXT.md` — new test counts, Sentry integration, backup procedure                      |
| 7.4 | `AGENTS.md` §11 — backup procedure, rollback script, Sentry instructions                           |

---

## Execution Constraints

- **After each phase**: `./scripts/pre-deploy.sh` must pass
- **Single-function deploys**: When refactoring Edge Functions (Phase 4), deploy one at a time
- **iPhone verify after**: Phases 1, 4, 5, 6 (any phase touching Flutter or auth)
- **Backup before start**: Run backup manually before Phase 1 begins
- **No partial deploys**: Never push a migration or deploy a function mid-phase

---

## Summary of Changes

| Phase | Files created                                        | Files modified                                                   | Test count impact                |
| ----- | ---------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------- |
| 1     | 2 (dependabot.yml, pre-commit-config)                | 3 (config.toml, 2 Edge Functions, CI)                            | +1 CI step                       |
| 2     | ~8 test files                                        | 1 (db_contract_test.ts)                                          | +~90 pgTAP, +~30 Deno            |
| 3     | 4 (backup.sh, rollback.sh, health-check/, logger.ts) | 2 (coach-chat, meal-analyze)                                     | +0                               |
| 4     | 1 (_shared/auth.ts)                                  | 14+ (7 Edge Functions, 8 fixture moves, coach_screen, 5 widgets) | +1 coach_screen widget test      |
| 5     | 0                                                    | 3 (pubspec.yaml, main.dart, 2 Edge Functions)                    | +0 (Sentry is no-op without DSN) |
| 6     | 0                                                    | 0 (Dashboard only)                                               | +0                               |
| 7     | 0                                                    | 4 docs                                                           | +0                               |

**Total new tests**: ~90 pgTAP assertions + ~30 Deno handler tests + ~5 Flutter widget tests
