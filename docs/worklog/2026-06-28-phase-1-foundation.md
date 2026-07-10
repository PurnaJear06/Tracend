# Worklog: 2026-06-28 Phase 1 Foundation

This is a dated worklog for detailed progress. Agents should not read all
worklogs by default; read this only when the history behind Phase 1 setup is
needed.

## Summary

- Phase 1 was authorized.
- Repository-local tooling direction was selected to keep large dependencies,
  caches, container runtime state, and generated artifacts on the external SSD.
- `.codex/`, `.tooling/`, and dependency caches are ignored from git.
- `docs/adr/0001-phase-1-foundation.md` records Phase 1 foundation decisions
  (Flutter 3.41.7/Dart 3.11.5, iOS 17.0 minimum, `com.tracend.app` bundle ID,
  Supabase CLI 2.101.0, Deno 2.9.0, Docker CLI 29.6.1, Colima 0.10.3).
- Supabase local foundation scaffolded: `supabase/config.toml`, initial
  `user_accounts` migration with enums, RLS (enabled + forced), narrow column
  grants, `private` schema, and `set_updated_at_and_version` trigger.
- Edge Function shared contracts written:
  `supabase/functions/_shared/contracts/coach_decision_v1.ts` (typed schema v1.0)
  and `supabase/functions/_shared/providers/coach_model_provider.ts` (interface).
- Mock provider + Deno tests in
  `supabase/functions/_shared/providers/mock_coach_model_provider_test.ts`.
- Seven wrapper scripts in `scripts/`: `supabase.sh`, `deno.sh`, `docker.sh`,
  `container.sh`, `bootstrap-tools.sh`, `bootstrap-container-runtime.sh`,
  `test-db.sh`.
- `DEVELOPMENT_GUIDE.md` written with only verified commands.
- `docs/handoff/backend.md`, `docs/handoff/frontend.md`,
  `docs/handoff/design.md`, and `docs/PROGRESS_CONTEXT.md` established.

## Verification Results (2026-06-28)

- Local Supabase analytics disabled (analytics/vector sidecar caused
  health-check failure under the project-local runtime; not needed for Phase 1).
- `./scripts/supabase.sh start` — **passed**.
- `./scripts/supabase.sh db reset` — **passed**.
- `./scripts/deno.sh task check` (format, lint, typecheck, mock tests) — **passed**.
- `./scripts/test-db.sh` pgTAP RLS suite — **passed: 8/8 tests, Result: PASS**.
  Tests: RLS enabled, RLS forced, own-row select isolation, own-row update,
  update persists, `row_version` increments, cross-user update blocked,
  cross-identity insert blocked (error 42501).

## Stitch Design Import (2026-06-28)

- Five canonical screens downloaded from Stitch project 2662655096321681608
  and saved into `design/stitch/screens/`:
  - `today/` — Tracend Today - Premium Precision Pro
  - `train/` — Training Hub - Production Ready
  - `workout-detail/` — Daily Workout Detail - Premium Technical
  - `coach/` — Coach Room - Focused Architectural Baseline
  - `nutrition/` — Nutrition - Final 5-Tab Navigation
- `design/stitch/screens.json` is the canonical index.
- **Progress screen not yet generated** in Stitch; create before Flutter
  Progress tab implementation.

## Phase 1 Status

Backend foundation: **complete and verified**.
Design import: **5/5 screens imported** (Progress pending).
Flutter shell: **not yet started** — next workstream action.

## Hosted Supabase Linkage (2026-06-28)

- Authenticated the repository-local Supabase CLI; its user state remains under
  `.tooling/home` on the external SSD.
- Linked the repository to hosted project `qsfzzsjenopqqqhvpyaw` (`Tracend`) in
  Southeast Asia (Singapore), region code `ap-southeast-1`.
- Verified the linked project through `./scripts/supabase.sh projects list`.
- Previewed the hosted migration plan; it contained only
  `20260628190000_phase_1_foundation.sql`.
- Deployed that migration successfully with `supabase db push --linked`.
- Hosted pgTAP did not produce a valid result: the first linked run reported
  `Files=0, Tests=0, Result: NOTESTS`, and corrected-path retries stalled.
  Local pgTAP remains the valid 8/8 verification; hosted behavior verification
  remains explicitly open.

## Follow-Up

- Generate Progress screen in Stitch and import into `design/stitch/screens/progress/`.
- Scaffold Flutter iOS shell (see `docs/handoff/frontend.md` for exact steps).
- Keep `DEVELOPMENT_GUIDE.md` limited to verified commands only.
