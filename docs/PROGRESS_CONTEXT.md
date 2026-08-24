# Tracend Progress Context

**Active change:** Phase 5 v2 "Precision Pro" production UI — chunked execution on
`feature/feature-engine-phase-5-v2`, plan: `.opencode/plans/phase-5-v2-precision-pro.md`
(progress tracker at top of plan). Chunk 0 complete (`c55d281`: authority docs, Stitch dark
tokens, Spline Sans + IBM Plex Mono, TracendGlass/PremiumGradientCard/MicroMotion). Chunk 1
complete (`1bcc0d8`: Today screen rebuild — TrajectoryLens bezier, hero, readiness strip,
readout cards, coach perspective, check-in bar; 8 widgets extracted). Chunk 2 complete
(`d1db7b1`: Train + Nutrition — IntensityBar, DatePillStrip, TargetsGrid,
NutritionInsightCard; Train/Nutrition screens rebuilt, sub-widgets extracted) — reviewed
PASS w/ findings, all follow-ups fixed 2026-08-24 (coach repo injected at shell, meal
widgets extracted, 4 screen-level tests, v1.4 fixture `workout_id`, legend/null-summary
nits). Chunk 3 complete 2026-08-24 (Progress + Coach — deterministic 7d/28d weight
regression overlays on `EvidenceTrendChart`, `EvidenceAccordion` + `ExpandableText` shared
widgets, tappable measurement history with read-only detail sheet, `MetricSparkline` wired
into `WeightTrendIndicator`, Coach/Progress screens rebuilt from extracted widgets) — gate
passed, review pending. Session duration cap (180 min) deployed 2026-08-22
(`20260822120000_session_duration_cap.sql`). Feature Engine Phase 4 remains the last
shipped UI milestone. 261 Flutter tests pass, 0 analysis issues.

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
| Phase 5 v2 "Precision Pro" UI | **In progress — Chunk 3 complete, review pending** | `docs/handoff/design.md`   | `.opencode/plans/phase-5-v2-precision-pro.md`   |
| Backend foundation        | **Complete — verified**              | `docs/handoff/backend.md`  | worklogs                                      |
| Frontend/UI               | **Complete — iPhone release build**  | `docs/handoff/frontend.md` | worklogs                                      |
| Coach Continuity Memory   | **Deployed**                         | `docs/handoff/backend.md`  | `docs/worklog/2026-07-17-coach-continuity.md` |
| Stitch/design             | **23 refs imported**                 | `docs/handoff/design.md`   | `design/stitch/README.md`                     |
| Stability infra           | **Complete — deployed**              | `AGENTS.md` (commands)     | N/A                                           |
| CI/CD automation          | **Complete — deployed**              | `docs/CI_CD_DEPLOYMENT.md` | `AGENTS.md` (deployment)                      |

## Global Current State

- Supabase project `qsfzzsjenopqqqhvpyaw` (Singapore); 61 migrations (all deployed; session
  duration cap deployed 2026-08-22).
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
- **Phase 4 — July 22 strain 403 outlier:** ~~Open~~ **Fixed 2026-08-22.** The July 22 session
  (`duration_seconds = 30238`, strain ≈403) is now excluded from strain/ACWR windows by
  `compute_daily_metrics` (`duration_seconds <= 10800` filter). New completions are clamped
  client-side (`active_workout_screen.dart`) and server-side (`complete_workout` RPC) to 10800s.
  Raw historical value left untouched (no data rewrite). Migration:
  `20260822120000_session_duration_cap.sql` (additive, deployed 2026-08-22).

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

**Test counts:** pgTAP 362 assertions (270 + 72 Phase 2 + 20 Phase 3), Deno 94 (77 pass, 4 pre-existing failures from unconfigured serve() + no local DB), Flutter 155 (104 + 51 Phase 4). All Flutter pass.

## Phase 4 — Flutter Computed Metrics UI + Backend Pipeline (2026-07-26)

**Status: Complete. 6 widgets built, 3 screen integrations, 2 pipeline migrations deployed, 155 tests pass, app installed on Purna's iPhone 12.**

### Widgets delivered

| Widget | File | Screen | What it shows |
|--------|------|--------|---------------|
| `RecoveryRing` | `lib/features/today/recovery_ring.dart` | Today | 240° arc gauge (0-100 recovery score) with HRV/RHR/sleep/respiratory/strain Z-score driver breakdown |
| `SleepArchitectureCard` | `lib/features/today/sleep_architecture_card.dart` | Today | Sleep quality (0-100) + duration/efficiency/restorative/consistency sub-scores + HRV/RHR baselines |
| `_ReadinessStrip` redesign | `lib/features/today/today_screen.dart` | Today | Three scored tiles: Recovery, Load (ACWR), Nutrition (macro adherence %) — each with color-coded detail + tap-to-explain |
| `TrainingLoadGauge` | `lib/features/train/training_load_gauge.dart` | Train | 4-zone ACWR bar (undertraining/optimal/elevated/high-risk) + monotony indicator + daily strain pill |
| `WeightTrendIndicator` | `lib/features/progress/weight_trend_indicator.dart` | Progress | 7d / 28d trend rates (kg/day) + R² confidence + optional MetricSparkline |
| `MetricSparkline` | `lib/shared/widgets/metric_sparkline.dart` | Shared | Inline smooth-curved sparkline for any numeric series (used by WeightTrendIndicator) |

### Data model + plumbing

- `ComputedMetrics` (`lib/features/today/computed_metrics.dart`): `fromJson()` parses `computed.scores.*` (recovery, sleep_quality, acwr, daily_strain, training_monotony, weight_trend_7d_kg_per_day, weight_trend_28d_kg_per_day, macro_adherence_pct, recovery_breakdown, sleep_breakdown, sleep_debt_minutes), `computed.baselines.*` (5 metrics: hrv_sdnn_ms, resting_hr_bpm, sleep_minutes, weight_kg, resp_rate_bpm each with ewma/spread/n_obs/confidence), `computed.data_confidence` (high/medium/low/cold_start)
- `DailyBrief` model updated with nullable `computed` field; existing consumers unaffected
- `app_shell.dart` passes `DailyBriefRepository` to Train and Progress screens
- Contract test `test/contract/daily_brief_contract_test.dart` updated with `computed` model parsing assertion
- All widgets auto-hide when `computed == null`; ReadinessStrip tiles show `--` with contextual fallback text

### Screen integration

| Screen | Integration | Date binding |
|--------|-------------|--------------|
| Today | RecoveryRing + SleepArchitectureCard rendered below header; ReadinessStrip redesigned with scored tiles | Always today (via `DateTime.now()`) |
| Train | TrainingLoadGauge rendered inline below weekday strip; gauge reloads per selected weekday via `_selectWeekday` → `_brief.load(_dateForWeekday(day))` | Per selected weekday date |
| Progress | WeightTrendIndicator rendered in body section | Always today |

### Backend pipeline — two migrations (both deployed to production)

**v1: `20260726160000_fix_computed_pipeline.sql`** (backfill + structural fixes)
- Backfill: `UPDATE workout_sessions SET session_effort = 5 WHERE session_effort IS NULL AND state = 'completed'` — all 13 existing sessions got effort values
- Recompute: one-time loop recomputed `daily_computed_metrics` for all dates in last 28 days with workout_sessions
- `healthkit_auto_complete_workout`: added `session_effort = 5` for all future auto-completed sessions (was NULL, making them invisible to ACWR/strain calculations)
- `recompute_stale_metrics`: now processes `current_date` AND `current_date - 1` (was: only yesterday)
- `get_my_daily_brief`: switched source from `feature_snapshots` (point-in-time coaching snapshot) to `daily_computed_metrics` (cron-refreshed)

**v2: `20260726170000_fix_computed_on_the_fly.sql`** (compute-on-the-fly — Noop pattern)
- Architecture fix: `get_my_daily_brief` now **always calls `compute_daily_metrics` fresh** (VOLATILE plpgsql) instead of reading any cache. This eliminates the fundamental gap where cache rows may not exist for the requested date. Pattern inspired by Noop's pure-computation-from-raw-data approach.
- `compute_daily_metrics` still upserts to `daily_computed_metrics` as a side effect for other consumers (`prepare_coach_chat_v6`, `recompute_stale_metrics`)
- Coach accuracy unaffected: `prepare_daily_coaching` already calls `compute_daily_metrics` directly
- `get_my_training_hub`: switched `latest_computed` CTE from `feature_snapshots` to `daily_computed_metrics` (was the only RPC still reading the stale coaching snapshot)
- Graceful failure: if `compute_daily_metrics` throws, `v_metrics := null` → `computed` field null → all widgets auto-hide

### ACWR / Strain / Monotony — what the numbers mean

- **Strain** = `sum(effort × duration_seconds / 600)` for completed sessions on a given day. 1 hour moderate (effort=5) ≈ strain 30. Higher = harder day.
- **ACWR** (Acute:Chronic Workload Ratio) = average daily strain over last 7 days (acute) divided by average over last 28 days (chronic). 0.8–1.3 = optimal training zone. 1.3–1.5 = slightly elevated. >1.5 = sharp increase, injury risk signal.
- **Monotony** = mean daily strain / stddev of daily strain over 7 days. <1.5 = varied training (good). >2.0 = repetitive, same intensity every day (injury risk).
- **Recovery** (0-100) = weighted Z-score composite from HRV, resting HR, sleep minutes, respiratory rate, and prior strain. Higher = more recovered.
- **Sleep Quality** (0-100) = weighted model: 50% duration + 20% efficiency + 20% restorative (deep+REM %) + 10% consistency.

### Build & install

- iOS release build: 25.4MB, arm64, signed with development team CGLRSQ8G95
- Build command: `./scripts/flutter.sh build ios --release --dart-define SUPABASE_URL=https://qsfzzsjenopqqqhvpyaw.supabase.co --dart-define SUPABASE_PUBLISHABLE_KEY=sb_publishable_...`
- Installed on Purna's iPhone 12 via `xcrun devicectl device install app`

### Tests

- Flutter: 155/155 (104 original + 51 Phase 4)
- New test files: `computed_metrics_test.dart` (12), `recovery_ring_test.dart` (10), `sleep_architecture_card_test.dart` (11), `training_load_gauge_test.dart` (10), `weight_trend_and_sparkline_test.dart` (7)
- Contract test: `daily_brief_contract_test.dart` updated with `computed` model parsing
- Flutter analyze: 0 issues

## Design Tools (2026-07-26)

- **Impeccable** (`npx impeccable install`): 23-command design skill + 60-rule CLI detector installed at
  `.opencode/skills/impeccable/`. Run `/impeccable init` to generate DESIGN.md context, then use
  `/impeccable critique`, `/impeccable audit`, `/impeccable bolder` for Flutter UI quality.
- **Taste-Skill** (`npx skills add`): 3 anti-slop skills installed at `.agents/skills/`:
  `stitch-design-taste` (Stitch rules → code bridge), `redesign-existing-projects` (audit + fix
  workflow), `design-taste-frontend` (default v2 with VARIANCE/MOTION/DENSITY dials).
