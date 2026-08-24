# Design Handoff

**Scope:** Stitch, design exports, screen metadata, visual decisions, and handoff into Flutter
implementation.

This file is current-state handoff, not design authority. Visual system rules belong in
`docs/DESIGN_SYSTEM.md`; screen flows belong in `docs/UX_FLOWS.md`; portable Stitch prompt/context
belongs in `DESIGN.md`.

## Current State

- **Active change: Phase 5 v2 "Precision Pro" production UI** — chunked execution on
  `feature/feature-engine-phase-5-v2`, master plan `.opencode/plans/phase-5-v2-precision-pro.md`.
  Chunks 0–2 complete and reviewed (foundation, Today, Train + Nutrition); Chunk 3
  (Progress + Coach) complete and reviewed 2026-08-24 (PASS w/ findings, all fixed);
  Chunk 4 (AI Usage + Shell + Account) is the next scope.
  Owner rulings: Stitch dark direction approved; `DESIGN_SYSTEM.md` amended in the same change
  as code (§3.1 dark hexes, §3.2 Spline Sans + IBM Plex Mono, §3.3 shape lock 12/24/28,
  §3.4 premium-gradient cards + chrome-only glass, §10 anti-patterns); all 5 tabs in scope;
  every implemented feature surfaced and working; AI Usage from real RPC fields only.
- Canonical five-tab navigation: **Today · Train · Coach · Nutrition · Progress**. This is
  authoritative and confirmed across `DESIGN_SYSTEM.md`, `UX_FLOWS.md`, and `PROGRESS_CONTEXT.md`.
- Stitch project **2662655096321681608** ("Tracend Design System") is the source.
- **All six canonical screen references are imported** into `design/stitch/screens/`:
  - `screens/today/` — "Tracend Today - Premium Precision Pro" (780×4012)
  - `screens/train/` — "Training Hub - Production Ready" (780×3912)
  - `screens/workout-detail/` — "Daily Workout Detail - Premium Technical" (780×2784)
  - `screens/coach/` — "Coach Room - Focused Architectural Baseline" (886×2336)
  - `screens/nutrition/` — "Nutrition - Final 5-Tab Navigation" (780×2952)
  - `screens/progress/` — "Progress - Tracend Operating System V2" (780×3594)
- **Sixteen authentication and onboarding references are imported** under
  `design/stitch/onboarding/`, indexed by `design/stitch/onboarding/screens.json`. They cover
  welcome loading/error/ restore states, eligibility, both onboarding paths, HealthKit states,
  review, plan generation, and initial proposal.
- **Account/Profile is imported** under `design/stitch/account/` as "Account & Profile - Kinetic
  Precision" (780×2328), indexed by `design/stitch/account/screens.json`.
- Each screen folder contains `*.html` (Stitch generated code), `*.png` (screenshot), and
  `metadata.json` (id, title, tab, dimensions, import date).
- `design/stitch/screens.json` is the top-level index of all imported screens.
- Root `DESIGN.md` remains the portable Stitch prompt/handoff brief and must not override
  authoritative product, UX, or design-system docs.

## Open Items

- The Account/Profile **My AI usage** row needs its detail reference. Two Stitch generation requests
  did not create a screen; the reviewed retry prompt is stored at
  `design/stitch/account/AI_USAGE_PROMPT.md`.
- Provider API-key entry is intentionally absent from mobile designs. Provider credentials remain
  environment-specific Supabase secrets as required by `ARCHITECTURE.md` and `SECURITY_PRIVACY.md`.
- The imported Progress reference includes trajectory, evidence, and weekly review, but omits the
  Body Measurements and privacy-safe Progress Photos entry sections required by `PRD.md` and
  `UX_FLOWS.md`. Add them in Stitch or implement them from the authoritative docs before declaring
  the Progress tab feature-complete.
- Workout-detail exercise list shows placeholder rows; fix before Flutter implementation of the
  Train tab detail view.

## Next Safe Actions

1. Generate and import the My AI Usage detail using `design/stitch/account/AI_USAGE_PROMPT.md`.
2. Review all imported onboarding references against `UX_FLOWS.md`; generated screens may be
   visually useful while still missing required states or copy.
3. Complete the Progress reference with Body Measurements and the private Progress Photos entry
   without exposing photo thumbnails on the overview.
4. Fix the workout-detail exercise list to show real planned exercises.
5. Flutter implementation is underway via Phase 5 v2 (Chunks 0–3 done and reviewed;
   Chunk 4 — AI Usage + Shell + Account — is the next scope). Design work should
   support the master plan
   (`.opencode/plans/phase-5-v2-precision-pro.md`), not restart a shell scaffold.
6. Do not commit local MCP config or API keys.
7. Update this file and `PROGRESS_CONTEXT.md` after material design changes.

## Do Not Do

- Do not paste large generated design dumps into `PROGRESS_CONTEXT.md`.
- Do not let Stitch output override PRD, UX, safety, privacy, or design-system authority.
- Do not commit real API keys from MCP or local design tooling.
