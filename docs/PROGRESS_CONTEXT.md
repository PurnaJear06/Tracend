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
nits). Chunk 3 complete 2026-08-24 (`672f28f`: Progress + Coach — deterministic 7d/28d
weight regression overlays on `EvidenceTrendChart`, `EvidenceAccordion` + `ExpandableText`
shared widgets, tappable measurement history with read-only detail sheet, `MetricSparkline`
wired into `WeightTrendIndicator`, Coach/Progress screens rebuilt from extracted widgets) —
reviewed PASS w/ findings, all follow-ups fixed 2026-08-24 (overlay anchoring disclosed in
binding contracts, DESIGN_SYSTEM evidence-visualization amended for labeled R²-gated
overlays, accordion subtitle semantics, TextPainter disposal, reachability/loading tests
strengthened). Chunk 4 complete 2026-08-24 (AI Usage + Shell + Account — `My AI usage`
screen rebuilt on real `get_my_ai_usage`/`get_my_ai_budget_state` fields with
RPC-bound thresholds, operational-estimate labeling, loading/empty/unavailable states and
real refresh; read-only consent ledger wired from the Privacy row over `consent_records`;
Account restyled and extracted to `features/account/widgets/` (388 lines); tab capsule now
uses `TracendGlass` (glass budget stays 2 visible sites); dead `ComingSoonButton` /
`MiniTrendChart` deleted) — reviewed PASS w/ findings, all follow-ups fixed 2026-08-24
(usage future moved to initState with honest row error state, order-independent consent
latest-per-purpose, consent source rendered, fractional-safe threshold formatting, thread
delete error path). Chunk 5 (Motion + A11y + copy audit) implemented 2026-08-24:
`MicroMotionCountUp` on the recovery score, staggered entrances across all nine Today brief
sections, driver-bar semantics labels, extended contrast asserts, padded chip tap targets,
tab-label scale clamp, and a Dynamic Type regression test (1.3×/2.0× at 320pt, all five
tabs, no overflow) that fixed two real overflows. Copy audit found no filler, cliché, or
fabricated numbers. Reviewed PASS w/ findings, all follow-ups fixed 2026-08-24 (brief
FutureBuilder retains the previous brief across reloads so entrances don't replay and the
count-up fires; two latent setState-returns-Future bugs fixed in today_screen.dart; light
secondary-on-canvas contrast assert added; computed-brief Dynamic Type coverage added;
driver-bar raw-vs-clamped z-score documented). Chunk 6 (Today redesign, owner-approved
2026-08-25 after device QA): centered `RecoveryRing` + three-tile `ReadinessStrip` +
today-only `TrajectoryLens` + top-level "See evidence" accordion replaced by a full-width
`RecoveryReadoutCard` (tabular score, band chip, five z-score driver rows) and a real
`TrajectoryTrend` 7-day chart from `daily_health_summaries` (HRV → sleep → resting HR
priority, ≥4 recorded days, window anchored to the latest stored day, gaps never
interpolated, "Building baseline" cold start); ACWR folded into `SessionPlanCard` as a
display-only load row; stagger slots re-indexed 0–7; evidence stays reachable in the
Apple Health section. DESIGN_SYSTEM/UX_FLOWS/PRD amended in the same change. Session
duration cap (180 min) deployed 2026-08-22 (`20260822120000_session_duration_cap.sql`).
Feature Engine Phase 4 remains the last shipped UI milestone. Chunk 7 (Recovery honesty,
2026-08-25) in progress: production showed recovery 58 on days with no usable data, so
`20260825120000_recovery_honesty.sql` (additive create-or-replace) makes
`compute_daily_metrics` honest — components join the composite only with a value today
AND a usable baseline (spread > 0), unusable ones land in
`recovery_breakdown.missing_components`, recovery is NULL when nothing is usable, the
+0.2 optimism offset is gone (baseline → 50), and `data_confidence` counts the four
HealthKit components; `get_my_daily_brief` schema_version 1.2. On the client:
`RecoveryReadoutCard` renders No data rows (never a fake +0.0), the Apple Health section
left Today (controls profile-only), and the hero sync chip syncs health + brief +
decision together. ALGORITHMS §1 and UX_FLOWS amended same-change. Reviewed PASS WITH
FINDINGS (`docs/reviews/2026-08-26-phase-5-v2-chunk-7-recovery-honesty.md`), all
follow-ups fixed pre-commit. 2026-08-26: device-QA visual pass (hero headline now the
32pt `displaySmall` token instead of 42pt, "View analytics" demoted to a TextButton
affordance that stacks at accessibility sizes, all Today caps labels unified on the new
`TracendTheme.labelCaps` 11/16 · 0.08em helper — the wide-tracked sub-11pt labels read
as stretched) plus a noop StrandAnalytics backend rigor cross-check that fixed two more
fabrication leaks in the undeployed migration: `duration_score` now scores tonight's
sleep against the personal baseline (old `480/baseline` form ignored tonight entirely),
and `prev_strain` needs a 28-day spread > 0 to join the composite. pgTAP
recovery_honesty now 33/33 incl. a synthetic reproduction of the owner's exact
production day (old formula → 69, honest → 62). 318 Flutter tests pass, 0 analysis
issues. Remaining noop-inspired follow-ups (ACWR <7-day gate, sleep sub-component
imputation, rolling baseline spread, staleness, reference implementation) are tracked
in `docs/handoff/backend.md`. 2026-08-26 post-deploy: production backup analysis showed
zero successful `daily_coaching` runs ever — `persist_daily_coaching_result_v2` rejected
every live decision because its per-outcome evidence whitelist (2-4 codes) was narrower
than the 17 codes `prepare_daily_coaching` permits and the DeepSeek prompt teaches.
`20260826120000_sync_persist_evidence_whitelist.sql` widens the persist whitelist to the
full 17-code set (fabricated codes still rejected), and `coach-decide` now records a
failed run with `error_code='decision_rejected'` when persistence rejects, so rejections
are diagnosable in AI usage. pgTAP `persist_evidence_whitelist_test.sql` 11 assertions.
2026-09-06 (branch `feature/precision-pro-ui-redesigns`, commits `e939cb6`/`993142a`/`fdbc023`):
Today recovery fixes from the production sleep/resp diagnosis — sleep sessions attribute
to the morning they end (watch 30-min segments group ≤60 min gaps; window widened to
today−7/−8 so the fetch captures the full night; recent days self-heal on next sync),
respiratory rate collected end-to-end (read type + Edge contract + migration
`20260906120000` widening the persist/constraint whitelists; `data_confidence='high'`
finally attainable once all four signals have usable baselines), and
`SleepArchitectureCard` restyled to the sibling card grammar (`widgets/` move, band chip,
mono score + count-up, reflowing sub-score rows, no duplicated baseline footer, full
Semantics). 352 Flutter tests pass, 0 analyze issues, Deno contract tests +3.
2026-09-06 (branch `feature/review-optimizations`, review-ladder Passes 0+1): secret scanning
live at all three layers (gitleaks 8.30.1: pre-push step 5, CI pinned-binary job with sha256
verify, pre-commit rev bump; `.gitleaks.toml` allowlists the public supabase-demo anon JWT,
Podfile.lock checksums, and the contract-test fixture UUID); PRD §5.8 now states the DeepSeek
reality with ADR 0011 recording the activation; the check-in replay queue makes the offline
promise true (`CheckInQueue`: envelope persisted pre-RPC, replayed on Today launch with the
answer day's date, idempotent server-side, cleared on delivery, silent retry otherwise;
legacy envelopes without dates discarded); future-date guard migration `20260906140000`
stops `compute_daily_metrics` from folding baselines or persisting rows for
`target_date > current_date + 1` (Train weekday strip future pages get a read-only brief —
recovery null, z-keys 0, all components missing, `data_confidence` low) and deletes the
future-dated prod rows once. pgTAP `future_date_guard_test.sql` 10 assertions. 362 Flutter
tests pass, 0 analyze. Known: 6 pre-existing pgTAP failures on `main` (A/B-verified
independent of this branch — phase_4 resp-range order-of-rejection from PR #18, plan-count
off-by-one, coach_context_v5:269 syntax error, healthkit auto-complete/candidate fixtures,
workout_persistence pgTAP is() cast) — CI/deploy never run pgTAP (Colima-gated), so they
slipped; fix list tracked in the plan's follow-ups.
2026-09-07 (Pass 2 — math honesty, migration `20260907120000`): HRV folds and z-scores in
ln(ms) — scale-invariant (an x3-scaled history yields the identical z; one-time UPDATE
converts stored baselines via first-order delta, history `raw_value` keeps ms); ACWR moves
to zero-filled 28-day calendar windows and is null until ≥14 strain days (was: single
session → 1.0); monotony over the zero-filled acute week, null unless ≥4 strain days and
stddev > 0 (fixes the production monotony-5.57-on-identical-loads symptom); sleep
sub-scores stop coalescing missing awake/stages to 0 — each missing sub scores null and
drops out, the composite renormalizes, `sleep_breakdown` is emitted only when all four
subs exist (shipped Dart parser requires every key), and a new additive
`scores.sleep_breakdown_missing` names what dropped; duration_score uses the personal sleep
EWMA only at ≥7 nights (480-min population floor below — the cold-start EWMA scored the
first night 100 against itself); plausibility bands at fold and today-value (HRV 5–250ms,
RHR 30–120, sleep 1–960 — a 0-minute night is absence — weight 30–300kg, resp 8–25bpm):
out-of-band values are rejected, never clamped. Versions: scoring 2.2, brief RPC 1.3,
engine `baseline-v2`. pgTAP `math_honesty_test.sql` 26/26 (every pin hand-computed then
live-verified: z=1.241 on the 55-vs-~50ms day, ACWR 1.95/monotony 2.27 zero-filled pins,
duration floor 85.6 vs personal 92.7); phase_2 tests 32–34/40–41 updated to the honest
expectations; fixtures: new `daily_brief_v1_3.json` (live-captured shape: ln-ewma 3.94,
`sleep_breakdown_missing`, gated-null acwr/monotony) + 8 Dart contract tests;
`daily_computed_metrics.json` bumped to 2.2. 369 Flutter tests, 0 analyze, Deno 105/105.
Pre-existing pgTAP failures unchanged (auto_complete re-A/B-verified 13-run/4-fail without
the migration — the earlier "Tests: 2" record was a stale-DB artifact).
2026-09-07 (Pass 2.5 — Today-screen honesty, migration `20260907140000`, owner dogfooding
of Pass 2): driver rows now pair the raw measured value with its z (`38 ms · +0.5`) via the
additive `computed.today_raw` passthrough object (HRV/RHR/sleep/resp + computed strain;
all-null when unmeasured — never zero; brief RPC 1.3→1.4, scoring stays 2.2); the daily
decision regenerates when the check-in lands after the decision cited `recovery_check_in`
as missing (was: generated pre-check-in, stuck on gather-data all day even with
"Morning status recorded" showing — the coach card and check-in bar contradicted each
other); `loadHistory` selects `respiratory_rate_bpm` for the health history screen. Resp
pipe re-verified sound end-to-end in code (plugin read→contract→`persist_health_sync`
v2→v1→column→baseline fold; Apple Watch records resp only during sleep, so an empty
today with the watch off is honest — past-night backfill confirmation is an owner SQL
check against production). pgTAP `today_honesty_test.sql` 9/9 (brief-driven as
authenticated + jwt claim — the brief is security definer and computes internally;
guard-payload tests run compute as postgres, the `future_date_guard_test` pattern);
fixtures: new `daily_brief_v1_4.json` + 4 Dart contract tests; 378 Flutter tests, 0
analyze, Deno 105/105. Full pgTAP 665 tests: only the 5 pre-existing failing files.
2026-09-07 (Pass 3 — baseline dynamics, migration `20260907160000`): stored
`user_baselines.spread` becomes a 21-day-half-life EWMA over per-observation |deviation|
(was: static full-history 1.4826·MAD — a metric whose noise shrank kept being scored on its
whole noisy past, and vice versa; Winsor bounds keep the static MAD scale); per-metric spread
floors via new `baseline_floor_spread()` (hrv ln 0.05, rhr 2, sleep 15, weight 0.5, resp 0.5 —
an all-identical history floors at its floor instead of raw 0, keeping z finite);
`last_observation_date` now stamps the TRUE newest observation date (was: the compute's
target_date — 08-26 data read as fresh on a 09-07 sync; the Aug-26-presented-as-today class);
brief (1.4→1.5, additive) carries per-metric `last_obs_date` + `age_days`, null when never
observed (anti-masquerade: never-observed ≠ observed-today); z-usability gate hardened to
`spread > 0 AND n_observations >= 3` because the floor makes cold-start spreads non-zero —
present-value-with-cold-baseline still reports missing (a Pass-3-introduced regression caught
by `recovery_honesty_test` 14–15 before it shipped). pgTAP `baseline_dynamics_test.sql`
14/14 (floor pins, true-date stamps, cold-start age 9 reported as 9, never-observed null,
x3-scale-invariance survives the spread EWMA); `BaselineMetric` gains `lastObsDate`/`ageDays`
(parse-only, no UI yet — server-first per plan); fixtures: `daily_brief_v1_5.json` + 4
contract tests; 385 Flutter tests, 0 analyze, Deno 105/105; full pgTAP 679 with only the 5
pre-existing failing files.
2026-09-08 (Pass 4 — AI-context honesty, Edge Functions only, no DB/client change): the model
context stopped hiding NOT-MEASURED data. `compactValue`/`compactContext` now PRESERVE nulls
(was: stripped — the model could read a missing metric as absent history or zero; empty
arrays/objects stay pruned, absent ≠ not measured); `formatContextAsMarkdown` (live DeepSeek +
Gemini path) renders null fields as the "—" sentinel instead of omitting them (`if (v != null)`
guards removed from health/check-in/brief-health sections — a watch-off day now reads "- sleep:
—" rather than silently absent), renders each health row's own date plus the context
`coaching_date` anchor, and a one-line Null Contract header explains "—" up front; measured 0
stays a real 0 (distinct fact from null). Every coach-chat system prompt (3 providers) carries
the Data-honesty block (null/— = NOT MEASURED that day — say so, never zero, never a negative
result; distinguish measured-zero; never say "today/recent" without checking the value's date
against the context date), and all three decide interpreter prompts carry the same contract
(null = NOT MEASURED, never zero, never infer; `feature_context.local_date` is the decision
date — older values are past readings). Budget-neutral: nulls are ~4 chars; 32K/28K ceilings
and both CONTEXT BUDGET CONTRACT tests unchanged and green. Deno 105/105 (+7 Pass 4 tests:
null preservation through compaction, sentinel rendering, measured-zero vs null, date
rendering, decide-context null serialization, prompt-contract assertions); AI_SAFETY_SPEC §11
null contract; CONTEXT_BUDGET note. Owner device QA 2026-09-08 confirmed Passes 1–3 fixes
visible on iPhone (raw values next to z, No-data rows honest on a watch-off night, coach card
refresh after check-in).
2026-09-08 (Pass 5 — reference implementation + oracle tests, test-only, no production
behavior change): `test/reference/recovery_reference.dart` — an independent Dart
re-derivation of the recovery/sleep/strain math written from ALGORITHMS.md, not from the SQL
(both SQL fold passes reproduced: the stored center from `compute_winsorized_ewma` with
unfloored MAD bounds and the live `MAD=0 → last value` shortcut, and the stored spread from
the floored-bounds 21-day EWMA loop — two Winsor regimes in one fold, now documented).
12 shared oracle fixtures `test/reference/fixtures/*.json` (zero data, HRV-only, cold start,
full data, long sleep + resp, short night, sleep subs partial, 6-night floor, ln-scale x3
invariance, out-of-band today, out-of-band history, ACWR/monotony windows) including the
owner's real 2026-08-25 strain-only production day (62, prev_strain_z −0.294). Dart self-tests
15/15 (fixtures through the reference); `reference_parity_test.sql` 28/28 runs the SAME
fixtures through the production SQL — pins: 62, −0.294, ACWR 1.95, monotony 2.27, duration
floor 85.6, x3-identical z. Any scoring drift between SQL and the documented math now breaks a
test instead of shipping — the drift alarm for Passes 2–3. ALGORITHMS.md reconciled with the
live SQL (6 drift points: two-Winsor-regimes documentation, EWMA schedule off-by-one
"1–7/8+" → observations 2–8 fast / 9+ stable, §1 usability wording missing the ≥3-obs gate,
§4 missing the 10800s strain cap in the formula line, §5's "minimum 3 observations" weight
gate the SQL never enforced (REGR floor is 2), §3 consistency input is sleep duration not
stage history); spread-EWMA λ pinned to the SQL's rounded 0.0330 literal. Harness:
`scripts/test-db.sh` now ships the fixtures directory into the pgTAP container (/fixtures)
so the parity test reads them via psql backticks. 400 Flutter tests (385 + 15), 0 analyze,
Deno 105/105, full pgTAP 692 with only the 5 pre-existing failing files. Weight ≥3-gate
follow-up recorded in the plan (SQL behavior = ≥2; doc promised 3 — never enforced).

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
| Phase 5 v2 "Precision Pro" UI | **In progress — Chunk 7 (recovery honesty) pending review** | `docs/handoff/design.md`   | `.opencode/plans/phase-5-v2-precision-pro.md`   |
| Backend foundation        | **Complete — verified**              | `docs/handoff/backend.md`  | worklogs                                      |
| Frontend/UI               | **Complete — iPhone release build**  | `docs/handoff/frontend.md` | worklogs                                      |
| Coach Continuity Memory   | **Deployed**                         | `docs/handoff/backend.md`  | `docs/worklog/2026-07-17-coach-continuity.md` |
| Stitch/design             | **23 refs imported**                 | `docs/handoff/design.md`   | `design/stitch/README.md`                     |
| Stability infra           | **Complete — deployed**              | `AGENTS.md` (commands)     | N/A                                           |
| CI/CD automation          | **Complete — deployed**              | `docs/CI_CD_DEPLOYMENT.md` | `AGENTS.md` (deployment)                      |
| Post-review optimizations | **Complete — Passes 0–5 all done (Pass 5 reference + oracle parity 2026-09-08, test-only)** | [docs/plans/2026-09-04-optimization-plan.md](plans/2026-09-04-optimization-plan.md) | [docs/reviews/2026-09-04-full-project-review.md](reviews/2026-09-04-full-project-review.md) |

## Global Current State

- Supabase project `qsfzzsjenopqqqhvpyaw` (Singapore); 69 migrations (65 deployed through
  `20260907120000`; `20260907140000` Pass 2.5 + `20260907160000` Pass 3 deploy via CI on next
  merge to main).
- Navigation: five tabs — Today · Train · Coach · Nutrition · Progress.
- DeepSeek V4 Flash is the active Coach/chat provider (`COACH_MODEL_PROVIDER=deepseek`) —
  the activation record is ADR 0011; the full optimization ladder spawned by the 2026-09-04
  project review lives in `docs/plans/2026-09-04-optimization-plan.md`.
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
| `SleepArchitectureCard` | `lib/features/today/widgets/sleep_architecture_card.dart` | Today | Sleep quality (0-100) + duration/efficiency/restorative/consistency sub-scores + debt/surplus pill (restyled to sibling card grammar 2026-09-06; baselines live in RecoveryReadoutCard) |
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
