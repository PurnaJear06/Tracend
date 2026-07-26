# Tracend Progress Context

**Active change:** CI/CD automation deployed — three pipelines (ci, deploy, hotfix) + pre-push hook.
Agent deployment rule active. Feature Engine Phase 4 — Flutter UI complete. Phase 3 deployed to
production and merged. 155 Flutter tests pass, 0 analysis issues.

**Purpose:** tiny live dashboard and pointer index, not a history dump.

## Required Agent Flow

1. Read `AGENTS.md` → this dashboard → relevant authority docs → scoped handoff.
2. Inspect actual files before editing. After work, update handoff + this dashboard.

## Context Layers

| Layer     | Path                       | Purpose                  | Read by Default |
| --------- | -------------------------- | ------------------------ | --------------- |
| Rules     | `AGENTS.md`                | Mandatory agent behavior | Yes             |
| Authority | `docs/*.md` specs          | Product/architecture/etc | Relevant only   |
| Dashboard | `docs/PROGRESS_CONTEXT.md` | Current phase, pointers  | Yes             |
| Handoff   | `docs/handoff/*.md`        | Per-workstream state     | Relevant only   |
| Worklog   | `docs/worklog/*.md`        | Detailed history         | When needed     |
| ADR       | `docs/adr/*.md`            | Durable decisions        | When relevant   |

## Current Phase

Phases 1–8 are hosted; Coach Continuity Memory (v6 schema + v16 prompt) is hosted and live.
Stability infrastructure deployed 2026-07-19, context budget guard + health-check deployed
2026-07-20. Pre-deploy gate, contract tests, Sentry, backups, auth hardening all live.

## Active Workstreams

| Workstream              | Status                              | Read Next                  | Detail History                                |
| ----------------------- | ----------------------------------- | -------------------------- | --------------------------------------------- |
| Feature Engine Phase 1    | **Deployed — verified**              | `docs/handoff/backend.md`  | `docs/adr/0010-deterministic-feature-engine.md` |
| Feature Engine Phase 2    | **Complete — merged & verified**      | `docs/handoff/backend.md`  | `docs/ALGORITHMS.md`, `.opencode/plans/phase-2-feature-engine-algorithms.md` |
| Feature Engine Phase 3    | **Deployed — merged**                | `docs/handoff/backend.md`  | `.opencode/plans/phase-3-coach-integration.md`                                |
| Feature Engine Phase 4    | **Complete — widgets built + Today integrated** | `docs/handoff/frontend.md` | `.opencode/plans/phase-4-flutter-computed-metrics.md`
| Backend foundation        | **Complete — verified**              | `docs/handoff/backend.md`  | worklogs                                      |
| Frontend/UI               | **Complete — iPhone release build**  | `docs/handoff/frontend.md` | worklogs                                      |
| Coach Continuity Memory   | **Deployed**                         | `docs/handoff/backend.md`  | `docs/worklog/2026-07-17-coach-continuity.md` |
| Stitch/design             | **23 refs imported**                 | `docs/handoff/design.md`   | `design/stitch/README.md`                     |
| Stability infra           | **Complete — deployed**              | `AGENTS.md` (commands)     | N/A                                           |
| CI/CD automation          | **Complete — deployed**              | `docs/CI_CD_DEPLOYMENT.md` | `AGENTS.md` (deployment)                      |

## Global Current State

- Supabase project `qsfzzsjenopqqqhvpyaw` (Singapore); 57 migrations, 15 are fix migrations.
- Navigation: five tabs — Today · Train · Coach · Nutrition · Progress.
- DeepSeek V4 Flash is the active Coach/chat provider (`COACH_MODEL_PROVIDER=deepseek`).
- Sign in with Apple deferred; owner email/password mode active (ADR 0002).

## Global Open Decisions

- Apple Developer Program enrollment and TestFlight environment names.
- Licensed food catalog source.
- Owner smoke: rest-day Train, exact Nutrition foods, Today Health evidence refresh.
- Production migration deploy for `20260719090000_context_budget_guard.sql`. ✅ Deployed 2026-07-20.

## Coach Continuity (2026-07-17)

ADR-0009 five-layer structured memory: `coach_narrative_entries`, `user_preferences`,
`coach_session_summaries`, FTS on `coach_messages`, `prepare_coach_chat_v5`,
`search_coach_messages`, etc. `CoachChatAnswerV2` with optional `reasoning_chain`. `coach-chat` v16
with preference detection, FTS retrieval, session summary. Tests: pgTAP 36 assertions, Deno 58/58.
Post-deploy fixes: 4 migrations (v4→v5 recursion, schema_version constraint, jsonb_agg ordering,
ambiguous coaching_date). Prompt restructure separates system/rules from user/message.

## Global Known Issues

- Do not commit `.codex/config.toml`.
- CoreSimulator not used; physical iPhone for builds.
- Supabase CLI timeout on `db reset` is known, not a schema failure.
- Colima must be running for local pgTAP execution and Deno→DB contract tests.
- Contract test fixtures must be updated when RPC or Edge Function response shapes change — the act
  of updating them triggers a manual review of the shape change.

## HealthKit Quick-Complete (2026-07-18)

TrainScreen hub reloads after workout completion via `push<bool>` / `pop(true)`. When Apple Health
detects a workout on a day with a scheduled Tracend workout but no completed session, Train shows a
prompt card. "Yes, mark complete" calls `healthkit_auto_complete_workout` RPC. Per-date refactor:
lightweight `get_healthkit_completion_candidate(date)` RPC called per weekday. Completion state
v1.3: weekday strip shows green checkmark for completed days. `loadSession`/`start` accept optional
`localDate`. Auto-completed sessions show plan exercises read-only with info banner.

**Migrations:** `20260718100000`, `20260718110000`, `20260718150000`. All deployed. **Tests:**
Flutter 85/85 pass. Docs: PRD, UX_FLOWS, ARCHITECTURE, DATA_MODEL, SECURITY_PRIVACY, AI_SAFETY_SPEC,
TESTING_STRATEGY, frontend handoff updated.

## Stability Infrastructure (2026-07-19)

**Pre-deploy gate:** `scripts/pre-deploy.sh` runs deno fmt/lint/test, flutter analyze/test/build,
pgTAP, and migration dry-run. Supports `--deno-only`, `--flutter-only`, `--db-only`.

**Contract tests:** Flutter `test/contract/` (13 snapshot-based), Deno→DB
`_tests/db_contract_test.ts` (live, skipped when Supabase offline).

**Crash reporting:** Sentry on Flutter (`sentry_flutter`, `--dart-define SENTRY_DSN`) and Edge
Functions (`_shared/sentry.ts` wired into coach-chat, meal-analyze). `beforeSend` scrubber redacts
19 sensitive keys. Empty DSN = disabled.

**Backup:** `scripts/backup-db.sh` via session pooler → `.tooling/backups/YYYY-MM-DD/` + SHA-256
manifest.

**Rollback:** `scripts/rollback-function.sh <name>` redeploys prior git version with `--use-api`.

**Auth hardening:** Password min 8 + upper/lower/digit, re-auth for password change, email
confirmations on. Session timeouts deferred (Pro plan).

**Forward-compatible migrations:** Two-step rule — add then deploy then remove. Never single-step
rename/drop/type-change.

**Test counts:** pgTAP 362 assertions (270 + 72 Phase 2 + 20 Phase 3), Deno 94, Flutter 155 (104 + 51 Phase 4). All pass.

## Phase 4 Pipeline Fix (2026-07-26)

- `get_my_daily_brief` now reads computed metrics from `daily_computed_metrics` (was: `feature_snapshots`)
- `healthkit_auto_complete_workout` sets `session_effort = 5` so auto-completed sessions contribute to strain/ACWR
- Migration: `20260726160000_fix_computed_pipeline.sql` (ready to deploy)
- No Flutter or Edge Function changes needed — response shape unchanged

## Phase 4 — Flutter Computed Metrics UI (2026-07-26)

**6 widgets built, all screen-integrated, 155 tests pass, zero analysis issues.**

### Widgets delivered
| Widget | Location | Screen |
|--------|----------|--------|
| `RecoveryRing` (240° arc gauge) | `lib/features/today/recovery_ring.dart` | Today |
| `SleepArchitectureCard` (quality + sub-scores) | `lib/features/today/sleep_architecture_card.dart` | Today |
| `_ReadinessStrip` redesign (scored tiles) | `lib/features/today/today_screen.dart` | Today |
| `TrainingLoadGauge` (4-zone ACWR bar) | `lib/features/train/training_load_gauge.dart` | Train |
| `WeightTrendIndicator` (7d/28d trend) | `lib/features/progress/weight_trend_indicator.dart` | Progress |
| `MetricSparkline` (inline sparkline) | `lib/shared/widgets/metric_sparkline.dart` | Shared |

### Data plumbing
- `ComputedMetrics` model with `fromJson()` — parses `computed.scores.*`, `computed.baselines.*`, `computed.data_confidence`
- `DailyBrief` model updated with `computed` field
- Contract test updated for `computed` parsing
- Train/Progress screens now accept `DailyBriefRepository` and load brief in parallel

### Build
- iOS release builds clean (25.4MB), installed on owner's iPhone 12 with live Supabase backend
- **Build command:** `./scripts/flutter.sh build ios --release --dart-define SUPABASE_URL=https://... --dart-define SUPABASE_PUBLISHABLE_KEY=...`

## Design Tools (2026-07-26)

- **Impeccable** (`npx impeccable install`): 23-command design skill + 60-rule CLI detector installed at
  `.opencode/skills/impeccable/`. Run `/impeccable init` to generate DESIGN.md context, then use
  `/impeccable critique`, `/impeccable audit`, `/impeccable bolder` for Flutter UI quality.
- **Taste-Skill** (`npx skills add`): 3 anti-slop skills installed at `.agents/skills/`:
  `stitch-design-taste` (Stitch rules → code bridge), `redesign-existing-projects` (audit + fix
  workflow), `design-taste-frontend` (default v2 with VARIANCE/MOTION/DENSITY dials).
