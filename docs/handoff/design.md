# Design Handoff

**Scope:** Stitch, design exports, screen metadata, visual decisions, and
handoff into Flutter implementation.

This file is current-state handoff, not design authority. Visual system rules
belong in `docs/DESIGN_SYSTEM.md`; screen flows belong in `docs/UX_FLOWS.md`;
portable Stitch prompt/context belongs in `DESIGN.md`.

## Current State

- Canonical five-tab navigation: **Today · Train · Coach · Nutrition · Progress**.
  This is authoritative and confirmed across `DESIGN_SYSTEM.md`, `UX_FLOWS.md`,
  and `PROGRESS_CONTEXT.md`.
- Stitch project **2662655096321681608** ("Tracend Design System") is the source.
- **All six canonical screen references are imported** into `design/stitch/screens/`:
  - `screens/today/` — "Tracend Today - Premium Precision Pro" (780×4012)
  - `screens/train/` — "Training Hub - Production Ready" (780×3912)
  - `screens/workout-detail/` — "Daily Workout Detail - Premium Technical" (780×2784)
  - `screens/coach/` — "Coach Room - Focused Architectural Baseline" (886×2336)
  - `screens/nutrition/` — "Nutrition - Final 5-Tab Navigation" (780×2952)
  - `screens/progress/` — "Progress - Tracend Operating System V2" (780×3594)
- **Sixteen authentication and onboarding references are imported** under
  `design/stitch/onboarding/`, indexed by
  `design/stitch/onboarding/screens.json`. They cover welcome loading/error/
  restore states, eligibility, both onboarding paths, HealthKit states, review,
  plan generation, and initial proposal.
- **Account/Profile is imported** under `design/stitch/account/` as
  "Account & Profile - Kinetic Precision" (780×2328), indexed by
  `design/stitch/account/screens.json`.
- Each screen folder contains `*.html` (Stitch generated code), `*.png`
  (screenshot), and `metadata.json` (id, title, tab, dimensions, import date).
- `design/stitch/screens.json` is the top-level index of all imported screens.
- Root `DESIGN.md` remains the portable Stitch prompt/handoff brief and must
  not override authoritative product, UX, or design-system docs.

## Open Items

- The Account/Profile **My AI usage** row needs its detail reference. Two Stitch
  generation requests did not create a screen; the reviewed retry prompt is
  stored at `design/stitch/account/AI_USAGE_PROMPT.md`.
- Provider API-key entry is intentionally absent from mobile designs. Provider
  credentials remain environment-specific Supabase secrets as required by
  `ARCHITECTURE.md` and `SECURITY_PRIVACY.md`.
- The imported Progress reference includes trajectory, evidence, and weekly
  review, but omits the Body Measurements and privacy-safe Progress Photos
  entry sections required by `PRD.md` and `UX_FLOWS.md`. Add them in Stitch or
  implement them from the authoritative docs before declaring the Progress tab
  feature-complete.
- Workout-detail exercise list shows placeholder rows; fix before Flutter
  implementation of the Train tab detail view.

## Next Safe Actions

1. Generate and import the My AI Usage detail using
   `design/stitch/account/AI_USAGE_PROMPT.md`.
2. Review all imported onboarding references against `UX_FLOWS.md`; generated
   screens may be visually useful while still missing required states or copy.
3. Complete the Progress reference with Body Measurements and the private
   Progress Photos entry without exposing photo thumbnails on the overview.
4. Fix the workout-detail exercise list to show real planned exercises.
5. Begin Flutter UI shell scaffold using imported screen HTML and tokens from
   `docs/DESIGN_SYSTEM.md` (see `docs/handoff/frontend.md`).
6. Do not commit local MCP config or API keys.
7. Update this file and `PROGRESS_CONTEXT.md` after material design changes.

## Do Not Do

- Do not paste large generated design dumps into `PROGRESS_CONTEXT.md`.
- Do not let Stitch output override PRD, UX, safety, privacy, or design-system
  authority.
- Do not commit real API keys from MCP or local design tooling.
