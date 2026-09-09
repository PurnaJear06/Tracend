# Tracend post-review fix + optimization plan — 2026-09-04

> **Execution status (2026-09-07):** implementation on branch
> `feature/review-optimizations`. Passes 0–2 complete (one commit per pass).
> Before this ladder began, PR #18 (`feature/precision-pro-ui-redesigns`) had
> already landed three of its items ahead of it: 0a (gitignore `session-*.md`),
> 0e (CLAUDE.md exact-case commit), and 1a (respiratory rate collected
> end-to-end — health read type, Edge contract, migration
> `20260906120000_resp_rate_sync.sql`). They are marked DONE inline below.
> Pass 2 (math honesty) landed migration `20260907120000`: ln-domain HRV z,
> ACWR ≥14-strain-day gate over zero-filled calendar windows, monotony ≥4-day
> gate, sleep sub-score null-drop + renormalize + `sleep_breakdown_missing`,
> 7-night cold-start floor, per-metric plausibility bands; scoring 2.2, brief
> 1.3, engine baseline-v2. Pass 2.5 (Today-screen honesty: decision
> freshness, raw values next to z, resp verification) added 2026-09-07 after
> owner dogfooding; runs before Pass 3. Pass 3 done 2026-09-07; Pass 4 done
> 2026-09-08 (Edge-only, no DB/client change; owner device-QA'd Passes 1–3 the
> same day). Pass 5 done 2026-09-08 — **the full ladder is complete** (test-only
> pass: reference + parity; no migration, no deploy). Merge points are owner-called (merge to `main`
> auto-deploys).

## Context

The full project review ([docs/reviews/2026-09-04-full-project-review.md](../reviews/2026-09-04-full-project-review.md))
found the noop port faithful where it counts, but left: three real bugs (resp-rate dead code,
check-in dead letter, future-dated rows), a dormant secret-scanning control, doc/governance debt
(PRD provider drift, missing ADR, Claude.md case), and a rigor backlog (ln-domain HRV, ACWR gates,
sleep imputation, spread/staleness, AI null contract, reference implementation).

Owner direction:
- Make **one comprehensive plan** covering all review items and save it in the project for future
  reference — this document.
- Production-level items (widgets, pricing, consent gate, IP check) are **parked** for a later
  owner-led planning session.
- `Claude.md` is intentional: CLAUDE.md serves Claude Code, AGENTS.md serves other harnesses →
  resolve by committing with exact casing, not deleting. (DONE — landed in PR #18.)

## Gate (all implementation passes)

1. Owner explicitly green-lights a pass (or the whole ladder).
2. Other agent's bug branch is pushed and merged to `main`. (DONE — PR #18, 2026-09-06.)
3. `git status` — if redesign work is still uncommitted, commit it on `main` first.
4. Branch `feature/review-optimizations` from `main`. One commit per pass.
5. Merging to `main` auto-deploys (deploy.yml: verify → dry-run → backup → migrate → deploy).
   Suggested merge points: after Pass 1 (trust bugs) and after Pass 5 — owner calls timing. Agents
   never run `db push` / `functions deploy` manually.

---

## Pass 0 — security wiring + governance docs

- **0a.** `.gitignore`: add `session-*.md` under "Logs, private media, and local artifacts"
  (protects `session-ses_fcef.md` from any `git add -A`). **DONE — landed in PR #18.**
- **0b. Secret scanning live** (currently dormant — `.githooks/pre-push` has no scan step and no CI
  step exists):
  - `.githooks/pre-push`: add step 5 "Secret scan" — runs `gitleaks git --verbose` (full history;
    repo is small). If gitleaks is not on PATH: loud WARN + skip (CI backstop enforces).
  - `brew install gitleaks` locally (once) so the hook is actually live. Latest release: v8.30.1.
  - `.github/workflows/ci.yml`: new gitleaks backstop job using the **pinned release binary**
    (curl v8.30.1 tarball + sha256 verification, run scan) — keeps CI on vanilla commands, no new
    third-party action.
  - `.pre-commit-config.yaml`: bump `rev: v8.26.0 → v8.30.1` (stays informational; hooksPath is
    the active layer).
- **0c. PRD §5.8 provider fix** (`docs/PRD.md` §5.8): rewrite bullets — DeepSeek V4 Flash live
  coach since 2026-07-26 (ADR 0011); `gemini-3.5-flash` marked prior/superseded (gated alternative
  per ADR 0005); Groq Qwen owner-test route superseded (ADR 0006). Keep budget facts; verify
  against COST_MODEL.md.
- **0d. ADR 0011** (`docs/adr/0011-deepseek-activation.md`): records the 2026-07-04 restricted-data
  rejection (roadmap:272) → reconsideration → 2026-07-26 activation; the all-or-nothing secret
  gate (AI_SAFETY_SPEC §10); thinking-mode disabled for daily decisions (230338f). Format follows
  ADR 0006.
- **0e. Claude.md → CLAUDE.md**: `mv Claude.md CLAUDE.md` (exact case), commit both CLAUDE.md and
  AGENTS.md as intentional mirrors. **DONE — landed in PR #18.**
- **0f.** `docs/PROGRESS_CONTEXT.md`: pointer lines to the review + this plan.

**Verify:** `git check-ignore session-ses_fcef.md` → ignored (pre-landed); run `.githooks/pre-push`
manually (gitleaks step present, gates still pass); PRD grep shows no live-gemini claim; CLAUDE.md
tracked with exact case (pre-landed).

## Pass 1 — user-facing trust bugs (review P0 #1–3)

- **1a. Resp-rate live** (dead code: DB column + z-score + confidence rule all existed, but no
  ingestion anywhere). **DONE — landed in PR #18** (`993142a`: health read type, Edge contract,
  migration `20260906120000_resp_rate_sync.sql` widening persist/constraint whitelists).
- **1b. Check-in replay queue** (`lib/features/today/check_in_sheet.dart:39` — writes
  `daily_check_in_pending`, nothing ever reads it):
  - Store `local_date` + `timezone` in the pending envelope (the RPC needs them and the check-in
    belongs to the day it was answered, not the day connectivity returns).
  - Replay on Today-brief load: read the stored envelope, retry `save_daily_check_in` (stored
    `idempotency_key` makes retry safe), on success clear key + refresh brief, on failure keep
    silently for next launch. Makes the "will need a connection to sync" promise true.
  - Test: pending envelope replays once connectivity returns.
- **1c. Future-date guard**: new migration `20260906140000_future_date_guard.sql` —
  `compute_daily_metrics` skips the side-effect upsert + `compute_user_baselines` fold when
  `target_date > current_date` (brief still returns read-only values). Plus one-time data fix:
  delete already-written future-dated `daily_computed_metrics` rows. pgTAP: future-dated brief →
  no row inserted, no baseline folded.

**Verify:** full local gate — `./scripts/flutter.sh analyze` + `test`, `./scripts/deno.sh fmt
--check` + `lint` + `test`, pgTAP via pre-deploy (Colima; `--skip-colima` fallback documented).

## Pass 2 — math honesty (new additive migration + pgTAP + ALGORITHMS.md)

- **2a. ln-domain HRV z**: z-score `ln(hrv_ms)` instead of raw ms — raw over-weights the
  long upper tail (Plews/Altini; noop `readiness_hrv_ln`, bounds ln(8)..ln(250)). HRV baseline
  folds in ln-domain (one-time UPDATE converts existing hrv baseline_value → ln); RHR/sleep stay
  raw. ALGORITHMS.md formula section update + version bump (compute 2.1 → 2.2).
- **2b. ACWR/monotony server-side gates** (current guards only `avg28 != 0` / `stddev7 > 0`):
  adopt noop minChronic=14 — ACWR null until ≥14 strain days in the 28d window; monotony null
  unless ≥4 days + stddev > 0 (fixes the production monotony-5.57-on-zero-variance symptom).
  Align ALGORITHMS.md §4 (currently claims <7 days null — was never true in SQL).
- **2c. Sleep sub-score honesty**: efficiency must not coalesce missing awake-minutes
  to 0 (=assumes 100%); restorative must not coalesce missing stages to 0. Missing sub-input →
  null → drop + renormalize remaining weights (reuse the composite's weight-renorm pattern).
- **2d. Cold-start sleep floor** (baseline folds to first value → first-ever night scores 100):
  below 7 nights, personal need falls back to the population floor (noop minNeedNights).
- **2e. Per-metric sanity gates at fold**: plausibility bands before baseline fold — HRV 5–250 ms
  (ln bounds), RHR 30–120 bpm, resp 8–25 bpm (live after 1a), sleep 0–16 h, weight 30–300 kg.
  Out-of-band → observation rejected (reported missing), never clamped into the baseline.

**Verify:** pgTAP per item (1 strain day → ACWR null not 1.0; zero-variance week → monotony null;
stages missing → renormalized composite, no fabricated 0/50; first night < 100; out-of-band value
rejected); flutter/deno gates; fixtures if any response semantics changed.

## Pass 3 — baseline dynamics — DONE 2026-09-07 (migration `20260907160000`)

- **3a. Spread as EWMA** (noop: 21-day half-life, separate from 14-day center) + per-metric
  floorSpread, replacing static full-history MAD. — DONE as designed: stored spread is the
  21-day EWMA over |deviation| with `baseline_floor_spread()` floors (hrv ln 0.05, rhr 2,
  sleep 15, weight 0.5, resp 0.5); Winsor bounds keep the static MAD scale; no new columns
  needed (spread column reused — same kind, better derivation; next fold re-derives, so no
  backfill DDL).
- **3b. Staleness tracking**: `nightsSinceNewestValidNight`, staleDays = 14, vital carry ≤ 7 days.
  Brief gains additive fields (`baseline_stale`, `baseline_age_days`) → schema_version bump +
  fixtures. Server-first; minimal client display follows. — DONE simplified to the honest core:
  `last_observation_date` now stamps the true newest observation date (the bug — it stamped the
  compute's target_date); brief 1.4→1.5 carries per-metric `last_obs_date` + `age_days`
  (null when never observed). The staleDays-14 flag / 7-day carry cap were NOT added — the
  visible-fields design makes staleness explicit without a hardcoded gate; a display/AI-context
  threshold can layer on the age fields later. z-usability gate hardened to
  `spread > 0 AND n_observations >= 3` (the floors make cold spreads non-zero; caught a
  would-be regression via recovery_honesty 14–15 pre-ship).

**Verify:** pgTAP (stale baseline flagged; carry bounded), flutter/deno gates, fixtures bumped.

## Pass 2.5 — Today-screen honesty fixes (owner dogfooding, 2026-09-07)

Owner reviewed the Today screen after Pass 2 deployed and found one real bug plus
two comprehension gaps. Passes 3–5 stay queued behind this.

- **2.5a. Decision freshness (real bug).** The daily coach decision generates
  once ([today_screen.dart sync pipeline, lines ~205-212] generates only when
  no decision exists for today) and is never regenerated when the inputs it
  cited as missing arrive. Sequence that produced the contradiction: decision
  generated pre-check-in → policy outcome `request_data` (permitted actions
  GATHER_DATA / MAINTAIN_TARGETS) → owner checks in → bar shows "Morning
  status recorded" (reads the live table) but the T-COACH/N-COACH card still
  says "gather data / missing recovery check-in" until tomorrow. Fix: after a
  successful check-in (and after a health sync that delivers new data), if
  today's decision's `missing_data` contains `recovery_check_in`, generate a
  new decision (new idempotency key → new audited row; guardrails unchanged).
  Also refresh `_latestDecision` after check-in delivery, not just the brief.
- **2.5b. Raw values next to z-scores.** Owner read "HRV −1.2" as a broken
  ms value; it is the z-score (deviation from personal baseline in spread
  units) and was correct (38 ms vs ~50-60 ms ln-domain baseline), but
  uninterpretable without the raw number. Fix: driver rows show
  `38 ms · −1.2` style (raw value + z); RHR/resp/strain/sleep rows likewise.
  Requires today's raw values in the brief payload: add an additive
  `today_raw` object to `computed` (hrv_ms, resting_hr_bpm, sleep_minutes,
  resp_rate_bpm, strain) → brief schema 1.3 → 1.4 + fixtures.
- **2.5c. Resp-rate verification (may be working, must be proven).** Owner's
  build asked for respiratory permission (prompt proves the build carries the
  resp collection code from PR #18) and Apple Health holds past-night resp,
  but the Today card shows resp "No data". Every code link checks out
  (plugin 13.3.1 native mapping, read loop, aggregation, Edge contract, RPC
  insert, baseline fold). Today's row is legitimately empty (watch not worn
  last night → no overnight resp), so the question is whether past nights'
  resp reached `daily_health_summaries`. Owner runs the dashboard SQL-editor
  check; if rows are present with `respiratory_rate_bpm` values, the feature
  works and only today is honestly empty (baseline builds over ~7 nights →
  resp z joins the composite; confidence can reach `high`); if absent, a
  real ingestion bug exists and gets its own fix before merge.
- **2.5d. HealthDay model gap (found during trace).** `loadHistory` does not
  select `respiratory_rate_bpm` and `HealthDay` has no resp field, so any
  future UI showing resp history would silently show nothing. Additive
  select + field.

**Verify:** flutter analyze/test (widget test: decision regenerates after
check-in lands; driver rows show raw + z; brief v1.4 fixture shape), deno
fmt/lint/test, pgTAP if RPC shape changes (brief 1.3 → 1.4 bump + fixture),
contract fixtures updated.

## Pass 4 — AI-context honesty (Edge Functions, no DB) — DONE 2026-09-08

- **4a. Stop stripping nulls** (`supabase/functions/_shared/providers/coach_chat_provider.ts:186`
  `if (value === null) return undefined`): keep nulls — schema-stable fields so the model can't
  read a missing field as zero (noop contract: "a dash means NOT MEASURED — say so"). Empty
  array/object pruning stays. Check CONTEXT_BUDGET.md fit (nulls are ~4 tokens each).
- **4b. Prompt contract** (`coach-chat/index.ts`, `coach-decide/index.ts` system prompts):
  "null/— = NOT MEASURED that day — say so, never treat as zero"; date discipline: "never assert
  'today/recent' without comparing the context date to the actual current date."
- **4c. Tests**: `coach_chat_provider_test.ts` null-preservation cases; `test/contract/`
  coach_chat + coach_context fixtures; deno gates.

**As-built (2026-09-08):** beyond the planned compactValue fix, the LIVE path
(`formatContextAsMarkdown`, DeepSeek/Gemini) also hid nulls — its `if (v != null)` guards omitted
unmeasured fields entirely; nulls now render as the "—" sentinel in health/check-in/brief-health
sections, each health row carries its own date, the context renders a `coaching_date` anchor + a
one-line Null Contract header, and measured `0` stays a real `0`. The prompt contract landed as a
shared `nullContract` const spliced into all 3 chat system prompts plus the same contract in all
3 decide interpreter prompts (deepseek/gemini/groq model providers, not index.ts — that's where
the prompts live). `test/contract/` fixtures NOT bumped: no response shape changed (Edge-internal
only), so coach_chat/coach_context fixtures stay pinned — covered instead by 7 new/updated deno
tests. Budget verified neutral (98→105 deno tests, both CONTEXT BUDGET CONTRACT tests green).

## Pass 5 — reference implementation + oracle tests — DONE 2026-09-08 (test-only)

- Independent Dart implementation of the pure math under `test/reference/`
  (`recovery_reference.dart`) written from ALGORITHMS.md, not from SQL: weights 0.55/0.20/0.15/0.05,
  weight renorm, logistic k=1.6, ln-HRV, EWMA schedule (3d ≤8 obs → 14d), spread, ±3σ clamp / ±5σ
  reject, sanity bands, sleep subs, ACWR/monotony gates. — DONE as designed. The reference
  reproduces BOTH SQL fold passes (stored center via unfloored MAD bounds with the live
  `MAD=0 → last value` shortcut; stored spread via floored bounds + 21-day EWMA, λ pinned to the
  SQL's rounded 0.0330) — two Winsor regimes in one fold, now documented in ALGORITHMS.md §2.
- Shared oracle fixtures (`test/reference/fixtures/*.json`), including the owner's real production
  day (the old-69 → honest-62 case already in pgTAP). — DONE: 12 fixtures; the owner day pins
  recovery 62 / prev_strain_z −0.294.
- pgTAP parity test runs the same fixtures through SQL; outputs must match the reference within ε.
  Constants pinned once per side. This is the drift alarm for Passes 2–3. — DONE:
  `reference_parity_test.sql` 28/28 (`scripts/test-db.sh` now ships the fixtures into the pgTAP
  container at /fixtures; the parity test reads them via psql backticks).
- **Spec reconciliation found and fixed 6 doc-vs-SQL drift points** (the pass's purpose):
  two-Winsor-regimes documentation; the EWMA schedule table read "1–7 / 8+" one step early
  (SQL: observations 2–8 fast, 9th stable); §1 usability wording missing the ≥3-observation
  gate; §4 formula line missing the 10800s strain cap; §5 promised a ≥3-observation
  weight-trend gate the SQL never enforced (REGR floor is 2 — **follow-up: a future migration
  may raise the gate; the reference tracks SQL behavior until then**); §3 consistency input is
  sleep duration, not stage history.
- Verify bar met: flutter test 400 (385 + 15 reference), analyze 0, Deno 105/105, parity 28/28,
  full pgTAP 692 with only the 5 pre-existing failing files (A/B-verified on main, parked).
- **Hardened 2026-09-09 after external review (P2: compare exact outputs):** every fixture
  carries an embedded `expected` oracle block, regenerated by
  `tool/generate_expected.dart` (pure-Dart runner) and asserted field-by-field on BOTH sides —
  recovery, all five z-scores, sleep quality, the four sub-scores (exposure rule: breakdown
  object exists ⟺ all four computable), breakdown-missing, debt, strain, ACWR, monotony,
  confidence, missing components. Dart 413/413 (13 oracle + 15 anchor + 385); pgTAP
  `assert_expected()` runs 20 rows per fixture plus the 12 hand anchors (259 planned rows).
  Closes the invariant-only gap (a sign-flipped RHR z passed the old non-zero checks). Local
  pgTAP re-run skipped per owner (no VM); parity logic exercised via the Dart oracle layer.

---

## Parked — production-level (owner-led planning session, later; NOT in this plan)

Today widgets/watch complications; MacroFactor-style check-in review language; ranges-not-points
targets; "predicted feel" ACWR framing; Apple 5.1.2(i) AI-consent gate (must land before TestFlight
grows beyond owner); pricing ladder; legal-entity dev account (5.1.1(ix)); IP/patent check before
commercial launch.

## Standing rules honored throughout

Repo wrappers only; forward-only additive migrations; RPC `schema_version` additive-only; keys
never in Flutter; no manual deploys (CI merges deploy); update ALGORITHMS.md + PROGRESS_CONTEXT
when behavior changes; no code changes beyond this plan without OK.

## Per-pass verification bar (nothing is "done" until green)

`./scripts/flutter.sh analyze` + `test` · `./scripts/deno.sh fmt --check` + `lint` + `test` ·
pgTAP via `./scripts/pre-deploy.sh` (Colima; `--skip-colima --skip-reset` fallback documented) ·
contract fixtures updated where shapes changed · docs updated · `./scripts/pre-deploy.sh` full
gate before each merge handoff.

## Defaults chosen (owner can veto any at review)

1. Add resp-rate rather than drop it (unblocks `high` confidence + evidence code). (Landed.)
2. ACWR minChronic = 14 (noop parity) over the doc's aspirational 7.
3. ln-domain for HRV only (the right-skew argument is HRV-specific).
4. Claude.md committed as exact-case CLAUDE.md (owner-confirmed intent); AGENTS.md untouched.
   (Landed.)
5. gitleaks via pinned binary in CI + `brew install` locally (no new third-party action).
6. Future-dated prod rows cleaned up in the same migration that adds the guard.
