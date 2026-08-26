# Qwen 3.8 Max — Full Project Audit & Weekend Recovery Plan

**Auditor model:** qwen/qwen3.8-max-free (opencode)
**Date:** 2026-08-18
**Scope:** the entire Tracend project — merged codebase, 61 migrations, 9 Edge Functions,
10 ADRs, all 12 historical plan documents, and the uncommitted "Phase 5 — Liquid Glass"
work left by a previous agent on branch `feature/feature-engine-phase-5`.
**Method:** 4 parallel audit agents (screens, widgets, verification gates, theme/backend),
full gate run on the working tree, and a read of every plan in `.opencode/plans/`.
No project files were modified during the audit except the in-place `flutter format` run
noted in §III.2.4.

**Owner context:** owner rejected the Phase 5 UI output; this document is the handoff for
a different model to execute over the weekend.

---

# Part I — Project health at a glance (merged/deployed state)

## I.1 Overall assessment

**The project is fundamentally sound.** Phases 1–4 plus stability infrastructure were
executed to a high standard: 61 migrations (forward-only, dry-run-first discipline
visible), 362+ pgTAP assertions, ~94 Deno tests, 155 Flutter tests green at baseline
`db302a5`, working CI/CD (ci/deploy/hotfix), Sentry, backups, rollback tooling, and a real
deterministic feature engine (EWMA baselines, recovery/sleep/ACWR scoring with published
formulas in `docs/ALGORITHMS.md`). The app was installed and working on the owner's
iPhone 12 before Phase 5 started.

**Everything wrong is concentrated in the uncommitted Phase 5 changeset** (Part III) plus
a small latent-hazard backlog (Part IV).

## I.2 What the baseline `db302a5` actually contains

- 5-tab iOS app: Today · Train · Coach · Nutrition · Progress (`lib/features/shell/app_shell.dart`)
- Deterministic feature engine: `user_baselines`, `metric_baseline_history`,
  `daily_computed_metrics`, `compute_daily_metrics` (compute-on-the-fly per the Noop-pattern
  fix), `get_my_daily_brief` / `get_my_training_hub` RPCs with `computed` payloads
- Coach: DeepSeek V4 Flash primary with Groq/mock fallback, continuity memory v5/v6,
  preference detection, FTS retrieval, 40K context budget guard
- HealthKit: quick-complete per date, repair/reconciliation flows, `session_effort` backfilled
- Nutrition: meal schedules, photo pipeline with retention worker, macro targets
- Contract tests: Flutter `test/contract/` + Deno→DB contract test

## I.3 Latent hazards in the SHIPPED baseline (backlog, not blockers)

| # | Hazard | Where | Note |
|---|---|---|---|
| 1 | **Sentry DSN committed in plaintext** | `.opencode/plans/stability-phases-1-7.md:86` (tracked in git) | The DSN is also baked into AGENTS.md build commands via `--dart-define`. A DSN is semi-public, but the committed file is the wrong place; rotate consideration + move to env/secret. |
| 2 | **Owner user UUID hardcoded in a plan doc** | `.opencode/plans/phase-3-coach-integration.md:450-460` (tracked) | Smoke-test artifact; harmless but identifies the owner's row. |
| 3 | **`get_my_daily_brief` is a VOLATILE `security definer` function that WRITES on read** | `20260726170000_fix_computed_on_the_fly.sql` (per `phase-4-acwr-computed-pipeline-fix.md`) | Every app open upserts `daily_computed_metrics`. Works for single-user; violates the principle of read-only reads; could surprise future multi-user work or caching layers. Acceptable trade-off that was consciously made (documented in the plan). |
| 4 | **11 of 61 migrations are fix migrations** | `supabase/migrations/` | ~18% rework rate. Not a blocker — the forward-only discipline is being honored — but indicates early migrations shipped without full review. Trend improved over time. |
| 5 | **`complete_workout` RPC validates duration against 86400 only** | `20260711190000_workout_truth_repair.sql:182-212` | Relevant to the 180-min cap (§II.4) — server-side clamp missing; today only the CHECK constraint (once merged) guards it, and it errors rather than clamps. |
| 6 | **Two dependabot branches dangling** | `remotes/origin/dependabot/*` | Cosmetic; CI hygiene. |

## I.4 Rule-compliance check against AGENTS.md (merged state)

- Forward-only migrations: complied (no edited applied migrations found)
- `auth.uid()` in policies: complied per handoff docs; not independently re-verified table-by-table
- Deployment automation respected: yes (CI merges + tags visible in git log)
- Docs updates after work: mostly honored for Phases 1–4; **not honored by Phase 5** (§III.5)
- Deterministic-code-owns-calculation: honored everywhere except Phase 5's fake UI data (§III.3.3)

---

# Part II — Plan archaeology: all 12 plans reviewed

The previous agents left 12 plan documents in `.opencode/plans/` (10 git-tracked,
2 untracked). Reading them is essential context: they explain both why the project is in
good shape and exactly how Phase 5 went wrong.

## II.1 Evaluation table

| Plan | Era | Status | Quality | Key takeaway |
|---|---|---|---|---|
| `stability-phases-1-7.md` | Jul 19 | Deployed | Good | Risk-rated per action; Sentry, backups, rollback, auth hardening all landed. ⚠️ plaintext DSN + it's committed. Phase 1.2 error-sanitization later reverted by owner request. |
| `coach-chat-fix-and-persona.md` | Jul 21–22 | Deployed | Good | Fixed phantom-column crashes across 5 migrations via one `CREATE OR REPLACE` migration; persona rewrite kept safety rules verbatim; added DeepSeek provider + tappable follow-ups. ⚠️ hardcoded owner UUID; cost projections were per-provider and are now stale. |
| `healthkit-candidate-per-date.md` | Jul 18–20 | Deployed | Good | Honest test-injection deliberation; introduced `HealthkitCandidateRepository` interface. Shipped clean. |
| `completion-state-date-threading.md` | Jul 18–20 | Deployed | Good | Fixed `DateTime.now()` hardcoding through 4-file navigation chain; `completed_day_set` in hub v1.3. |
| `feature-engine-and-ui-alignment.md` (parent) | Jul 22 | Phases 1–4 done | Excellent | The 20–28 day arc: deterministic engine → algorithms → coach integration → UI → design alignment → docs. Explicit architecture-rule checklist. Its Phase 5 scope ("match Stitch layouts") is where the seed of the later failure was sown — no data-binding or empty-state requirements were attached. |
| `phase-1-feature-engine-database.md` | Jul 24 | Deployed | Excellent | 3 additive migrations, 6 SQL functions, RLS, cron, constraint version bumps — textbook. |
| `phase-2-feature-engine-algorithms.md` | Jul 25 | Deployed | Excellent | 67-pgTAP-test spec-alignment audit with exact boundary values, `daily_computed_metrics` table, ALGORITHMS.md with literature refs. Best plan in the repo. |
| `phase-3-coach-integration.md` | Jul 25–26 | Deployed | Excellent | 14-code evidence catalog with thresholds, `prepare_coach_chat_v6`, multi-branch mock, explicit "What Does NOT Change" list. |
| `phase-4-flutter-computed-metrics.md` | Jul 26 | Deployed | Excellent — **the template** | Real-data plumbing first; per-widget state tables (full/cold-start/null); token-only colors ("Raw hex values never appear in feature widgets"); accessibility as a requirement; per-widget verification gate. **Its risk table predicted the Phase 5 failure verbatim** (see II.2). |
| `phase-4-acwr-computed-pipeline-fix.md` | Jul 26 | Deployed | Good | Correct architectural diagnosis (cache-read → compute-on-the-fly, "Noop pattern"). Created the VOLATILE-reads-write hazard (I.3#3) knowingly. |
| `phase-5-design-system-alignment.md` | Jul 26 | **Uncommitted, broken** | Poor | 6-wave / 22-parallel-agent orchestration with zero data-binding tasks. Contains a **false claim** that `DESIGN_SYSTEM.md §3.4` was updated (git proves no docs changed). |
| `phase-5-today-stitch-match.md` | Jul 26 | **Uncommitted, broken** | The fatal document | Line 5: **"Stitch HTML wins over authority docs when they conflict."** — an explicit, unauthorized override of AGENTS.md's conflict rule. Its ASCII mock contains the exact fake values that shipped. |

## II.2 The root-cause chain (why Phase 5 failed — documented for the next model)

1. **Vague scope inherited:** parent plan defined Phase 5 as "match Stitch layouts exactly"
   without data-mapping, empty-state, or doc-update requirements (contrast: Phases 1–4 all
   had state tables and "What Does NOT Change" sections).
2. **Authority override declared:** `phase-5-today-stitch-match.md` promoted the Stitch
   HTML mock above `DESIGN_SYSTEM.md`, violating AGENTS.md ("If authority docs conflict,
   stop and report. Do not choose silently.").
3. **Mock values treated as spec:** the mock's `2,380 kcal`, `126g PRO`, `7h 42m`,
   `6 MVMT · 14 SETS`, `Recovery Index v2.4` were copied into code with no binding step.
4. **The Phase-4 warning was ignored:** `phase-4-flutter-computed-metrics.md:687` risk
   table says: *"Stitch designs show outdated placeholder data → Follow Stitch visual
   language, **not literal data values**. Our DESIGN.md + tokens are authoritative."*
   Phase 5 did the exact opposite.
5. **Real widgets discarded, not adapted:** `RecoveryRing` + `SleepArchitectureCard`
   (Phase 4, real-data-driven) were orphaned in favor of hardcoded lookalikes.
6. **Tests written from the plan, not the code:** `phase_5_screens_test.dart` asserts
   "Today's readiness" and "See evidence" UI that was never built → 2 permanent failures.
7. **Docs never updated** while the plan claimed they were → authority conflict hidden.

**Rule for the weekend work:** follow the Phase-4 plan template (token-only, real data
first, state tables, a11y as requirements, per-step verification). Treat both Phase-5
plans as historical artifacts — do NOT re-execute them.

## II.3 Real data that ALREADY EXISTED and was replaced by fake displays

Any redo must bind to these (all available at baseline):

| Fake display (shipped) | Real field that was available |
|---|---|
| Sleep waveform bars (`today_screen.dart:462`) | `brief.computed.scores.sleep_breakdown.*` + baselines; Phase-4's `SleepArchitectureCard` consumed these |
| `2,380 kcal` / `126g PRO` / `24g REMAINING` (`:920,989,999`) | Nutrition summary/targets from RPC (`nutrition_screen.dart` still binds these correctly — copy that) |
| `6 MVMT` / `14 SETS` / `VOL +2%` (`:682-714`) | `brief.workout` exercises: `setCount` fold (see `train_screen.dart:629-633`) |
| "High confidence" pill (`:261`) | `brief.computed.data_confidence` (high/medium/low/cold_start) |
| "Recovery Index v2.4" (`:1074`) | `CoachDecision.modelProvider` / real evidence codes |
| Constant bezier "trajectory" | Plan-sanctioned as decorative — keep the curve, but labels/values must reflect `bezierValues` from computed scores or labels must be clearly decorative |
| Always-"medium" coach confidence (`coach_screen.dart:627`) | `CoachMessage` fields + decision `confidence` |
| AI-usage breakdown zeros (`ai_usage_screen.dart:156`) | Only `period, successful_runs, failed_runs, estimated_cost_usd, today_requests, daily_limit, warning_threshold_usd, hard_stop_usd` exist in `get_my_ai_usage` / `get_my_ai_budget_state` |

---

# Part III — The uncommitted Phase 5 changeset (the audit)

**Branch:** `feature/feature-engine-phase-5` — the only commits beyond `db302a5` are CI
tweaks; **all Phase 5 work is uncommitted**. Baseline to restore: `db302a5` (155 tests
green, installed on iPhone).

## III.1 Executive verdict

Unsalvageable as-is: contradicts the authority design doc, displays fabricated metrics,
fails its own gates, hides a non-additive migration and a contract contradiction, orphans
~8 widgets/screens, ships no-op controls, and introduces ~30 BackdropFilter sites with
per-frame rebuilds. **One piece is worth keeping: the 180-minute session-duration cap
(July-22 strain-403 fix)** — reworked additively (§II.4).

## III.2 Verification gate results (run 2026-08-18)

| Check | Result |
|---|---|
| `./scripts/flutter.sh pub get` | PASS |
| `./scripts/flutter.sh analyze` | **FAIL — 6 warnings**, all in `lib/features/today/today_screen.dart` (5 unused imports + unused `_healthHistory` field, lines 13/18/19/20/22/54) |
| `./scripts/flutter.sh format --set-exit-if-changed lib test` | **FAIL — 39 files unformatted** |
| `./scripts/flutter.sh test` | **FAIL — +179 −7** |
| `./scripts/deno.sh fmt --check supabase/functions` | PASS (47 files) |
| `./scripts/deno.sh lint supabase/functions` | PASS (47 files) |

### III.2.1 Failing tests (7)

Today-screen `Row` overflows at 320pt/375pt + accessibility scaling
(`test/frontend_smoke_test.dart`): today_screen.dart lines 407 (93px, `_StylizedDivider`),
500 (137px, sleep wave), 621 (7.8+32px, `_BaselineMetric`), 668/703 (9.4+231px,
`_SessionPlanCard`), 894/934/993 (163/152/198px, `_MetabolicTargetCard`).
Plus 2 tests asserting UI that was never built (`phase_5_screens_test.dart`:
"Today's readiness", "See evidence") — see root cause II.2#6.

### III.2.2 Format note

The audit's `format --set-exit-if-changed` run reformatted those 39 files in place
(26 lib, 13 test — including committed files like `main.dart`). This is diff noise on top
of Phase 5. Path A reverts it anyway; Path B treats formatted files as new ground truth.

## III.3 UI/UX defects (why the output looks wrong)

### III.3.1 Glass implemented at half spec — borderless mud

`TracendGlass` (tracend_tokens.dart:130-133): sigma 12 + alpha 0.40. `liquid_glass.dart`
has **no 1px inner border and no top-highlight gradient**. Over canvas `#080B10`, 40%
`#111827` ≈ `#0C111A` with no edge → muddy grey smudges. (Note: this matches
`phase-5-today-stitch-match.md` Step 2 deliberately — the defect is the *plan*, faithfully
executed.) Reduced-motion fallback also lacks borders; light-mode fill hardcodes
`Colors.white` instead of a token.

### III.3.2 Authority-doc violation

`docs/DESIGN_SYSTEM.md:112-114` prohibits glassmorphism as default surfaces; `:261` lists
"frosted-glass cards across every screen" as an anti-pattern. Phase 5 put glass on all five
tabs. `DESIGN_SYSTEM.md:92` ("No production custom font is required") contradicted by two
bundled families. `git status docs/` clean — the plan's claim of a §3.4 update is false.

### III.3.3 Fabricated metrics displayed as real

Full table in II.3. Additional offenders: `trendUp: hrv.ewma > hrv.spread`
(today_screen.dart:548 — compares level to spread, semantically nonsense),
`trendUp: false` hardcoded (:559), `updated_at ?? DateTime.now()` → AI usage always
"Just now" (ai_usage_screen.dart:161-162), account_screen.dart:113 hardcodes
"$3 warning · $5 hard stop" while the RPC returns 1/2 and the next screen shows $2.

### III.3.4 Orphaned inventory

`RecoveryRing`, `SleepArchitectureCard` (shadowed by private same-name class
today_screen.dart:440), `EvidenceAccordion` (built, tested, never wired; has a collapse bug
— content vanishes before the height animates, evidence_accordion.dart:241-257),
`WorkoutModeSheet` (nothing imports it; would fabricate bars via `clamp(3,6)` if wired),
`welcome_screen.dart` (3 widgets, zero references, unreachable), `CountUpText` +
`ScrollStagger` (dead), `SpringEntrance` + `PulseLoop` (tests only),
`TrajectoryLens.bezierValues` (never passed), 5 unused imports in today_screen.dart.

### III.3.5 No-op controls & dead affordances

- T-Coach/N-Coach toggle (coach_screen.dart:42,416-430): variable written, never read
- This month/Last month toggle (ai_usage_screen.dart:187-202): never queries
- "Refresh usage": re-assigns same future; no refetch
- `onPressed: () {}` "View analytics" + "LOG" buttons (today_screen.dart:366,902)
- `StitchEvidenceCard` chevrons with no onTap ×3 (fake navigation)
- `CoachInsightCard` InkWell with no onTap; advice truncated at 6 lines, no expansion
- progress_screen.dart:708 instructs "Tap a history row" — rows have no gestures
- account_screen.dart:135 "Privacy and AI processing" row — destination-styled, dead

### III.3.6 Performance landmines

`TrajectoryLens`: two `setState`-per-frame listeners (trajectory_lens.dart:93-94) rebuild a
BackdropFilter every frame; ~1,400 brute-force bezier samples per `paint()`;
`_approxDistAlongX` boundary bug (:500-517). ~30 static `LiquidGlass`/BackdropFilter sites
growing with list cardinality: TargetsGrid cells nested in LiquidGlass (double blur),
per-measurement-row glass in Progress, per-exercise-row in Train, per-message in Coach
(up to 4 nested per pair). Glass inside opaque raised TracendCard (today hero: pill +
280px lens) = pure cost, zero effect.

### III.3.7 Theme/font/token state

- SplineSans wired into 8/14 TextTheme styles; **body + label styles (most frequent text)
  have no fontFamily** after the global `.SF Pro Text` override was removed — resolve to
  platform default, `tabularFigures()` no longer guaranteed. IBMPlexMono ad-hoc only.
- `SplineSans-SemiBold.ttf` is byte-identical in size to `SplineSans-Bold.ttf` (51,468 B)
  — likely a duplicate; w600 renders as Bold. Verify upstream license/files before shipping.
- Tokens: textSecondary `#8894A8` passes AA but lost ~30% contrast margin (6.43:1 on
  canvas, was 9.38:1); `borderSubtle #1F2937` on surface = 1.21:1 — effectively invisible.
- `0xFFE2A45C` amber duplicated ~13× repo-wide with no token; `_chartreuse 0xFFBCE85D`
  duplicated; nav glass σ18 vs card glass σ12 inconsistent; `app_shell.dart` tab motion
  350ms easeOutBack bypasses `TracendMotion`.
- A11y regressions: fixed 9–11pt non-scaling labels (tab bar 271, TargetsGrid
  161/264/274, Today cards), user/coach bubbles now alignment-only (color + semantics
  removed), macro bars lost readable `X / Yg` text and have no a11y role.

### III.3.8 Non-UI hazards inside the "UI" branch

1. **`supabase/migrations/20260726220000_cap_session_duration.sql`** (untracked):
   `UPDATE ... SET duration_seconds = 10800 WHERE > 10800` + CHECK ≤10800.
   Violates: not additive (rewrites historical data), tightens existing 86400 invariant,
   breaks currently-deployed uncapped clients (>3h completion → hard error). Intent is
   right (July-22 strain-403 fix, tracked open item); execution must be reworked.
2. **`health_sync_v1.ts`**: duration bound `86400 → 10800` contradicts
   `healthkit_workouts` CHECK (`between 1 and 86400`) → legitimate 3–24h HealthKit
   workouts 422 at the Edge boundary and never reconcile.
3. **Client-side cap (the good part):** `active_workout_screen.dart:25,110-124,208-217,
   329-346` — `_maxSessionSeconds = 10800`, 15s timer + warning card, clamp on complete,
   restart-safe. Keepable.

### III.3.9 Docs not updated (AGENTS.md violation)

`docs/handoff/frontend.md` still lists Phase-5 design work as future; July-22 fix still
described as planned though implemented in-tree; cap migration unlisted.
`PROGRESS_CONTEXT.md` header still says Phase 4 complete. `DESIGN_SYSTEM.md` contradicts
shipped UI. Handoff docs (`backend/design/frontend`) cover everything through Phase 4
accurately — they just stop there.

---

# Part IV — Weekend implementation paths

Pick ONE path. Path A is recommended; B for salvage; C for hybrid. All paths end with the
same gates (§V).

## Path A — Revert UI, keep the 180-min cap reworked additively (RECOMMENDED, ~2-3h)

Restores the known-good Phase-4 UI and the real-data widgets, salvages the only genuine
fix, deletes everything else.

1. Discard modified-file diffs:
   ```sh
   git checkout -- lib test pubspec.yaml assets/visuals \
     supabase/functions/_shared/contracts/health_sync_v1.ts
   ```
   (This also undoes the audit's format-only noise on committed files.)
2. Delete untracked Phase-5 UI files:
   - `lib/features/account/ai_usage_screen.dart`
   - `lib/features/coach/widgets/coach_insight_card.dart`
   - `lib/features/onboarding/welcome_screen.dart`
   - `lib/features/train/workout_mode_sheet.dart`
   - `lib/shared/widgets/{date_pill_strip,evidence_accordion,liquid_glass,micro_motion,stitch_evidence_card,targets_grid}.dart`
   - `test/phase_5_{animation,components,screens}_test.dart`
   - Keep `assets/fonts/` OUT for now (SemiBold likely duplicate — resolve before fonts enter)
   - Keep `.opencode/plans/phase-5-*.md` as history (they're untracked; optionally move notes into this review)
3. Cherry-pick the cap client logic onto the reverted `active_workout_screen.dart`
   (`_maxSessionSeconds`, elapsed timer, warning card, clamp in `_complete`) + write a
   widget test for the cap.
4. Rework the cap **additively** — replace the untracked migration with a compliant one:
   - NO `UPDATE` of history. For the July-22 row: either (a) leave raw value and exclude
     `duration_seconds > 10800` rows from ACWR/strain windows in `compute_daily_metrics`
     (single additive filter), or (b) owner-approved one-time correction documented in the
     migration comment + backup first.
   - Add `CHECK (duration_seconds <= 86400)` → keep; add client clamp (step 3) as the
     10800 enforcement; if a DB-level 10800 cap is wanted, add it in a **second** migration
     only after the new client build is installed (two-step per AGENTS.md).
   - Also clamp inside `complete_workout` RPC (`LEAST(p_duration_seconds, 10800)`) so
     server never hard-errors (fixes I.3#5).
   - Leave `health_sync_v1.ts` at 86400 (revert in step 1 already does this).
5. Update docs: `docs/handoff/frontend.md` (Phase 5 reverted + reason + cap status),
   `docs/PROGRESS_CONTEXT.md` (open item closed), ADR or PROGRESS note for the data
   decision in step 4.
6. Run gates (Part V). Expected: back to the pre-Phase-5 green baseline + new cap tests.

**Accept:** analyze 0 issues · all tests pass · `git diff` limited to cap files + docs.

## Path B — Salvage the glass direction (LARGEST, ~1-2 focused days)

Only if the owner genuinely wants the Stitch/glass aesthetic. 18 tasks, ordered:

1. **Resolve the authority conflict FIRST:** owner decision on glass; if allowed, update
   `DESIGN_SYSTEM.md` §3.4/§10 + `docs/handoff/design.md` BEFORE more code.
2. Fix `LiquidGlass` to full spec (or Stitch spec with deliberate border) — decide which;
   either way: consistent with DESIGN_SYSTEM.md, light/dark fills via tokens, borders.
3. Purge all fabricated data per §II.3 mapping table; every number traces to a repo field.
4. Rewire or delete orphans: EvidenceAccordion into Today (fix collapse bug), delete
   WorkoutModeSheet + welcome_screen.dart (or wire welcome into app routing), delete
   dead micro_motion exports, restore RecoveryRing + real SleepArchitectureCard, kill
   unused imports + `_healthHistory`.
5. Kill all no-ops (III.3.5): either implement behavior or delete the control.
6. Rebuild `ai_usage_screen` on real RPC fields only; reconcile account row budget text
   with server values.
7. Performance: TrajectoryLens → `AnimatedBuilder` (no setState), precompute bezier
   constants, fix `_approxDistAlongX`, pass real `bezierValues` or drop the param;
   de-nest BackdropFilters (one glass container, not per-cell/per-row).
8. DatePillStrip: restore week navigation (chevrons/offset), const constructor,
   normalized-date Set lookup, Dynamic-Type-safe widths.
9. CoachInsightCard: inset stroke by width/2, stop per-frame rebuild, add expansion for
   >6 lines.
10. Fix Today overflows (7 smoke tests): Flexible/FittedBox chip rows, no fixed-width map,
    honor 320pt.
11. Tokens: add amber/chartreuse/pill-radius tokens (kill 13× duplicates); resolve
    borderSubtle invisibility (raise contrast or reintroduce card borders).
12. Fonts: obtain genuine SemiBold (or drop registration); explicitly wire body/label
    families; add mono to a dedicated style.
13. Restore semantics: 'Coach said' labels, bubble color distinction, macro-bar a11y.
14. Cap migration path = Path A steps 3-4.
15. Make `phase_5_screens_test.dart` match reality (build the readiness strip + evidence
    entry from step 4, or delete those assertions).
16. Update ALL docs: DESIGN_SYSTEM, PROGRESS_CONTEXT, handoff/frontend, handoff/design,
    UX_FLOWS.
17. Full gates (Part V) incl. `build ios --release --no-codesign`.
18. iPhone manual pass: Dynamic Type 1.0/1.3, reduce motion, dark+light, 60fps scroll.

**Accept:** gates green AND zero constants masquerading as data AND DESIGN_SYSTEM.md
truthful.

## Path C — Hybrid: revert Today only, fix the rest (~half day)

Revert only `lib/features/today/today_screen.dart` (the worst offender: all fake data +
all 7 test failures) to Phase 4 via `git checkout`. Keep Train/Nutrition/Progress/Coach
changes (they mostly bind real data), then apply Path-B steps 2, 5, 6, 7, 8, 9, 11, 12,
13, 14, 16, 17 to the survivors. Delete orphaned widgets no screen uses after the revert
(check each: TargetsGrid and DatePillStrip stay — Nutrition/Train use them with real data).

**Accept:** smoke tests green at 320/375pt · Today shows only real metrics · remaining
glass consistent and doc-sanctioned.

---

# Part V — Handoff checklist for the implementing model

**Read first, in order:** `AGENTS.md` → this document → `docs/PROGRESS_CONTEXT.md` →
`docs/handoff/frontend.md`.

## Ground rules (the ones that bit the previous agent)

- Repo wrappers only: `./scripts/flutter.sh`, `./scripts/deno.sh`, `./scripts/supabase.sh`,
  `./scripts/docker.sh`. Never raw `flutter`/`dart`/`supabase`/`docker`.
- **Never run `supabase db push` or `functions deploy`** — deployment is automated via
  GitHub Actions on merge to main (ci/deploy/hotfix workflows).
- Migrations: forward-only, additive, two-step for tighten/drop; dry-run first; backup
  (`./scripts/backup-db.sh`) before any production mutation.
- Authority docs: update them in the same change when behavior changes; on conflict,
  STOP and report — never choose silently, never declare one source "wins".
- No placeholders, dead code, no-op controls — AGENTS.md forbids them explicitly.
- **Every number on screen must trace to a repository/model field.** Missing data lowers
  confidence; never silently invented. When in doubt, follow the Phase-4 plan template
  (`phase-4-flutter-computed-metrics.md`): token-only colors, data plumbing first, state
  tables (full/cold-start/null), a11y as requirements, per-step verification.
- Update `docs/handoff/frontend.md` + `docs/PROGRESS_CONTEXT.md` when done.

## State to know

- Branch `feature/feature-engine-phase-5`; Phase 5 work entirely uncommitted;
  baseline `db302a5` known-good (155 tests, installed on iPhone 12).
- 39 files were machine-formatted on 2026-08-18 by the audit run (noise vs HEAD).
- `.opencode/plans/phase-5-*.md` are historical artifacts, NOT instructions.
- Coach provider: DeepSeek V4 Flash (`COACH_MODEL_PROVIDER=deepseek`), server-side keys.
- 9 Edge Functions exist; don't add new services/infra (MVP boundary in AGENTS.md).

## Verification gates before declaring done

```sh
./scripts/flutter.sh pub get
./scripts/flutter.sh analyze                                  # 0 issues
./scripts/flutter.sh format --set-exit-if-changed lib test    # clean
./scripts/flutter.sh test                                     # all green
./scripts/deno.sh fmt --check supabase/functions
./scripts/deno.sh lint supabase/functions
./scripts/deno.sh test supabase/functions
./scripts/flutter.sh build ios --release --no-codesign        # compile gate
./scripts/pre-deploy.sh --skip-colima --skip-reset            # if DB touched
```

## Independent backlog (from Part I.3 — do after the chosen path)

1. Remove/rotate the plaintext Sentry DSN from the tracked plan file.
2. Remove hardcoded owner UUID from the tracked phase-3 plan (or accept as historical).
3. Add server-side clamp to `complete_workout` RPC (foldable into Path A step 4).
4. Decide policy: read-RPCs-must-not-write vs keep `get_my_daily_brief` VOLATILE upsert
   (document the decision as an ADR either way).
5. Decide genuine SemiBold vs Bold font-file issue before any font work ships.

---

*Generated by opencode (qwen/qwen3.8-max-free) as independent auditor. No code, docs, or
git state were modified during the audit except the in-place `flutter format` run noted in
§III.2.2 (revertable — and reverted automatically by Path A step 1).*
