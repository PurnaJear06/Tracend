# Tracend CI/CD & Deployment Plan

**Status:** Implementation planned — not yet built
**Provider:** DeepSeek V4 Flash (`COACH_MODEL_PROVIDER=deepseek`) active for Coach/chat
**Last updated:** 2026-07-26

---

## 1. Problem Statement

Deployment is currently 100% manual CLI — `pre-deploy.sh` → `db push` → `functions deploy` — run
by the developer or AI agent. This creates risks:

- 11 out of 56 migrations are "fix" migrations (evidence of deploy-then-patch pattern)
- No automated backup before migration push
- No deploy mutex — two concurrent `db push` commands could corrupt production
- No migration timestamp collision detection before merge
- No git hooks to catch errors before push
- CI runs redundant overlapping jobs (ci.yml + pre-deploy.yml on same triggers)
- iOS build artifact is discarded in CI
- No deployment audit trail (no tags, no changelog)

## 2. Target State

### Three GitHub Actions pipelines

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Actions                           │
│                                                             │
│  ci.yml          deploy.yml          hotfix.yml             │
│  ───────         ──────────          ─────────              │
│  On: every push  On: merge to main   On: manual trigger     │
│  ┌───────────┐   ┌───────────────┐   ┌───────────────┐     │
│  │ deno      │   │ verify        │   │ dry-run       │     │
│  │ flutter   │   │ dry-run       │   │ skip-backup   │     │
│  │ ios-build │   │ backup        │   │ migrate       │     │
│  │ migration │   │ migrate       │   │ deploy-func   │     │
│  │  -check   │   │ deploy-func   │   │ smoke-test    │     │
│  └───────────┘   │ smoke-test    │   │ tag-release   │     │
│                  │ tag-release   │   └───────────────┘     │
│                  └───────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

### Zero manual deployment steps
Developer merges PR → deployment runs in GitHub automatically → green pipeline = deployed.

### Visual pipeline in GitHub Actions UI
Each job is a box, each step expandable with logs, green/red status, timing per step. Same visual
as enterprise CI dashboards.

## 3. Files in Scope

| File | Action | Purpose |
|------|--------|---------|
| `.github/workflows/ci.yml` | Overwrite | Consolidated fast checks with caching + migration collision check |
| `.github/workflows/deploy.yml` | Create | Auto-deploy on merge to main with concurrency lock |
| `.github/workflows/hotfix.yml` | Create | Emergency manual deploy (skips backup) |
| `.github/workflows/pre-deploy.yml` | Delete | Replaced by ci.yml + deploy.yml |
| `.githooks/pre-push` | Create | Local guard: deno fmt/lint, flutter analyze, migration check |
| `AGENTS.md` §12 | Edit | Deployment Rule — agents must not manually deploy |

## 4. Pipeline Design

### 4.1 CI Pipeline (`ci.yml`)

**Trigger:** Every push and PR to `main` or `feature/**`

**Concurrency:** Cancel old runs on same branch when new push arrives (`cancel-in-progress: true`)

**Jobs (all parallel):**

| Job | Runner | Timeout | Steps |
|-----|--------|---------|-------|
| deno | ubuntu-latest | 10 min | checkout → setup-deno 2.9.0 → `deno fmt --check` → `deno lint` → `deno test` |
| flutter | ubuntu-latest | 15 min | checkout → flutter-action 3.41.7 (cached) → `flutter pub get` → `flutter analyze` → `flutter test` |
| ios-build | macos-latest | 30 min | checkout → flutter-action 3.41.7 (cached) → `flutter pub get` → `flutter build ios --release --no-codesign` → upload artifact |
| migration-check | ubuntu-latest | 1 min | checkout → verify no duplicate migration timestamps |

**Migration uniqueness check logic:**
```bash
DUPES=$(ls supabase/migrations/*.sql | sed 's|.*/||' | grep -oP '^\d+' | sort | uniq -d)
[ -z "$DUPES" ] || { echo "Migration collision: $DUPES"; exit 1; }
```

### 4.2 Deploy Pipeline (`deploy.yml`)

**Trigger:** Push to `main` (i.e., merge) or manual `workflow_dispatch`

**Concurrency:** Queue, do NOT cancel (`cancel-in-progress: false`) — only one deploy at a time

**Jobs (sequential):**

| # | Job | Purpose | Failure Behavior |
|---|-----|---------|-----------------|
| 1 | verify | Re-run all tests (flutter + deno + migration check) | Stop — nothing deployed |
| 2 | dry-run | `supabase db push --linked --dry-run` | Stop — nothing deployed |
| 3 | backup | `supabase db dump --linked` → upload as artifact | Stop — nothing deployed |
| 4 | deploy-migrations | `supabase db push --linked` | Partial deploy — functions not updated |
| 5 | deploy-functions | Deploy all 9 Edge Functions (parallel matrix) | Partial deploy — some functions new, some old |
| 6 | smoke-test | `curl` health-check endpoint (3 retries) | Partial deploy — need rollback |
| 7 | tag-release | Create `vYYYY.MM.DD-HHMM` git tag | Deploy complete — cosmetic only |

### 4.3 Hotfix Pipeline (`hotfix.yml`)

**Trigger:** Manual `workflow_dispatch` only

**Key differences from deploy.yml:**
- Skips `verify` job (developer already tested)
- Skips `backup` job by default (speed over safety in emergency)
- Same `concurrency: production-deploy` group — joins same queue

### 4.4 Pre-Push Git Hook (`.githooks/pre-push`)

Runs before every `git push`:
1. `deno fmt --check supabase/functions`
2. `deno lint supabase/functions`
3. `flutter analyze`
4. Migration timestamp uniqueness check

Blocks push if any check fails. Saves ~5 min of CI time by catching issues locally.

## 5. Deployment Concurrency Lock

```
Developer A merges PR #1 ──→ deploy.yml starts (holds production-deploy lock)
                               │
                               ├─ verify ✓
                               ├─ dry-run ✓
                               ├─ backup ✓
                               ⏳ deploy-migrations (in progress...)
                               │
Developer B merges PR #2 ──→ deploy.yml QUEUES (lock held)
                               │
                               │  ... waiting ...
                               │
                               ├─ deploy-migrations ✓
                               ├─ deploy-functions ✓
                               ├─ smoke-test ✓
                               ├─ tag-release ✓
                               │  LOCK RELEASED
                               │
                               ▼
                               deploy.yml for PR #2 STARTS
```

## 6. Migration Collision Prevention

### Problem
Two developers on different branches create:
- `20260726120000_add_feature_a.sql`
- `20260726120000_add_feature_b.sql`

Same timestamp → `db push` fails with `schema_migrations_pkey` unique constraint violation.

### Solution (three layers)

**Layer 1: Pre-push hook** — catches collisions before code leaves the developer's machine.

**Layer 2: CI check** — migration-check job runs on every push/PR, blocks merge if collision found.

**Layer 3: Deploy concurrency lock** — only one deploy runs at a time, preventing race conditions
even without timestamp collisions.

### Multi-developer workflow (documented for future team members)

When rebasing a feature branch on latest `main` after another developer's migration was deployed:
```bash
git fetch origin
git rebase origin/main
# Re-timestamp own migration to current time
OLD=$(ls supabase/migrations/*.sql | grep -v "origin" | tail -1)
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
NAME=$(basename "$OLD" | sed 's/^\d\+_//')
git mv "$OLD" "supabase/migrations/${TIMESTAMP}_${NAME}"
git commit --amend
```

## 7. Rollback Strategy

### Edge Function Rollback
```
GitHub Actions → "Rollback Function" workflow (or manual CLI)
→ ./scripts/rollback-function.sh <function_name>
→ Checks out previous git version → deploys with --use-api
```

### Database Migration Rollback
Applied migrations are NEVER edited, deleted, or reverted in place. Instead:
1. Write a NEW forward migration that undoes the bad migration
2. Push → PR → CI passes → merge → deploy pipeline runs
3. Audit trail preserved — both the bad migration and the fix are in git history

## 8. GitHub Secrets Required

| Secret | Purpose | Source |
|--------|---------|--------|
| `SUPABASE_ACCESS_TOKEN` | Authenticate Supabase CLI for deploy, dry-run, backup | Supabase Dashboard → Account → Access Tokens |
| `COACH_MODEL_PROVIDER` | Deploy metadata (optional, informational) | Set to `deepseek` |

Backup uses `supabase db dump --linked` which works with just the access token — no separate
database URL or password needed.

## 9. Migration Safety Rules

Enforced by CI, documented for developers:

1. **Never create a migration directly on `main`.** Always on a feature branch.
2. **Rebase on latest `main` before merging.** Resolves timestamp ordering.
3. **Re-timestamp your migration after rebase.** Ensures chronological order.
4. **Never revert an applied migration.** Write a new forward migration to undo.
5. **Every migration must be additive.** No renames, no drops on live columns.
6. **Every migration must be idempotent.** Use `IF NOT EXISTS` / `DROP IF EXISTS`.
7. **Every migration must be backward-compatible.** Deployed app must still work.
8. **Data migrations go in separate files AFTER the schema migration.**

## 10. Agent Deployment Rule (AGENTS.md §12)

After implementation, agents are prohibited from running deployment commands directly. Normal
deployment is automated via GitHub Actions on merge to `main`. Manual CLI deployment is only
permitted when GitHub Actions is down or the user explicitly requests it.

## 11. Implementation Checklist

### Phase 1 — CI/CD Files
- [ ] `.github/workflows/ci.yml` — consolidated, cached, migration check added
- [ ] `.github/workflows/deploy.yml` — auto-deploy pipeline with concurrency lock
- [ ] `.github/workflows/hotfix.yml` — emergency manual deploy
- [ ] `.github/workflows/pre-deploy.yml` — deleted (replaced)
- [ ] `.githooks/pre-push` — local guard

### Phase 2 — GitHub Configuration
- [ ] `SUPABASE_ACCESS_TOKEN` secret added to GitHub Settings
- [ ] Branch protection: require CI to pass before merge to `main`
- [ ] Enable git hooks: `git config core.hooksPath .githooks`

### Phase 3 — Validation
- [ ] Test PR → verify `ci.yml` runs all jobs and passes
- [ ] Merge test PR → verify `deploy.yml` runs dry-run successfully
- [ ] First real deployment → verify full pipeline end-to-end

### Phase 4 — Documentation
- [ ] Update `AGENTS.md` with §12 Deployment Rule
- [ ] Update `PROGRESS_CONTEXT.md` with CI/CD workstream status
- [ ] Document migration workflow for future team members
- [ ] Verify fastlane/TestFlight integration path for future

## 12. Visual Reference

### What the CI pipeline looks like:
```
CI #1567 — PurnaJear06 pushed to feature/feature-engine-phase-3
┌──────────────────────────────────────────────────────────┐
│ ✅ Deno (fmt + lint + test)               1m 12s         │
│ ✅ Flutter (analyze + test)               2m 04s         │
│ ✅ iOS Build (macOS)                      8m 31s         │
│ ✅ Migration collision check              0m 03s         │
└──────────────────────────────────────────────────────────┘
```

### What the Deploy pipeline looks like:
```
Deploy #42 — main ← Merged PR #11
┌──────────────────────────────────────────────────────────┐
│ │ Step                     │ Status │ Time    │          │
│ ├───────────────────────────┼────────┼─────────┤          │
│ │ verify                    │   ✅   │ 2m 14s  │          │
│ │ dry-run                   │   ✅   │ 1m 08s  │          │
│ │ backup                    │   ✅   │ 3m 42s  │          │
│ │ deploy-migrations         │   ✅   │ 0m 45s  │          │
│ │ deploy-functions (9 jobs) │   ✅   │ 2m 31s  │  ← click │
│ │ smoke-test                │   ✅   │ 0m 02s  │          │
│ │ tag-release               │   ✅   │ 0m 03s  │          │
│ └───────────────────────────┴────────┴─────────┘          │
└──────────────────────────────────────────────────────────┘

Click "deploy-functions" → expands:
  ✅ coach-chat (12s)
  ✅ coach-decide (8s)
  ✅ health-check (6s)
  ✅ health-sync (11s)
  ✅ meal-analyze (15s)
  ✅ meal-media-retention (8s)
  ✅ onboarding-propose-plan (9s)
  ✅ privacy-delete-account (7s)
  ✅ privacy-export (6s)
```

## 13. Related Documents

- `AGENTS.md` — Agent behavior rules (will gain §12 Deployment Rule)
- `BETA_OPERATIONS.md` — Backup, recovery, incident procedures
- `ARCHITECTURE.md` — System architecture and deployment environments
- `COST_MODEL.md` — Cost assumptions (DeepSeek V4 Flash active)
- `IMPLEMENTATION_ROADMAP.md` — Phase sequencing
- `PROGRESS_CONTEXT.md` — Live dashboard (will track CI/CD workstream)
