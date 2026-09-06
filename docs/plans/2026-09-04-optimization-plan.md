# Tracend post-review fix + optimization plan — 2026-09-04

> **Execution status (2026-09-06):** implementation started on branch
> `feature/review-optimizations`. Before this plan began, PR #18
> (`feature/precision-pro-ui-redesigns`) had already landed three of its items
> ahead of this ladder: 0a (gitignore `session-*.md`), 0e (CLAUDE.md exact-case
> commit), and 1a (respiratory rate collected end-to-end — health read type,
> Edge contract, migration `20260906120000_resp_rate_sync.sql`). They are
> marked DONE inline below. Everything else executes in pass order on this
> branch, one commit per pass; merge points are owner-called (merge to `main`
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

## Pass 3 — baseline dynamics

- **3a. Spread as EWMA** (noop: 21-day half-life, separate from 14-day center) + per-metric
  floorSpread, replacing static full-history MAD. Additive columns on baselines + backfill
  migration.
- **3b. Staleness tracking**: `nightsSinceNewestValidNight`, staleDays = 14, vital carry ≤ 7 days.
  Brief gains additive fields (`baseline_stale`, `baseline_age_days`) → schema_version bump +
  fixtures. Server-first; minimal client display follows. Prevents "Aug-26 value presented as
  today" class everywhere (feeds Pass 4 prompt contract).

**Verify:** pgTAP (stale baseline flagged; carry bounded), flutter/deno gates, fixtures bumped.

## Pass 4 — AI-context honesty (Edge Functions, no DB)

- **4a. Stop stripping nulls** (`supabase/functions/_shared/providers/coach_chat_provider.ts:186`
  `if (value === null) return undefined`): keep nulls — schema-stable fields so the model can't
  read a missing field as zero (noop contract: "a dash means NOT MEASURED — say so"). Empty
  array/object pruning stays. Check CONTEXT_BUDGET.md fit (nulls are ~4 tokens each).
- **4b. Prompt contract** (`coach-chat/index.ts`, `coach-decide/index.ts` system prompts):
  "null/— = NOT MEASURED that day — say so, never treat as zero"; date discipline: "never assert
  'today/recent' without comparing the context date to the actual current date."
- **4c. Tests**: `coach_chat_provider_test.ts` null-preservation cases; `test/contract/`
  coach_chat + coach_context fixtures; deno gates.

## Pass 5 — reference implementation + oracle tests (backend.md's highest-leverage item)

- Independent Dart implementation of the pure math under `test/reference/`
  (`recovery_reference.dart`) written from ALGORITHMS.md, not from SQL: weights 0.55/0.20/0.15/0.05,
  weight renorm, logistic k=1.6, ln-HRV, EWMA schedule (3d ≤8 obs → 14d), spread, ±3σ clamp / ±5σ
  reject, sanity bands, sleep subs, ACWR/monotony gates.
- Shared oracle fixtures (`test/reference/fixtures/*.json`), including the owner's real production
  day (the old-69 → honest-62 case already in pgTAP).
- pgTAP parity test runs the same fixtures through SQL; outputs must match the reference within ε.
  Constants pinned once per side. This is the drift alarm for Passes 2–3.

**Verify:** flutter test (reference self-tests), pgTAP parity, full pre-deploy gate.

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
