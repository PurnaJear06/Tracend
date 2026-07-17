# 2026-07-02 — Phase 5 controlled coaching

Phase 5 was implemented locally with the validation boundary preceding persistence and UI wiring.

## Implemented

- Extended the versioned coach-decision contract with deterministic policy outcomes and strict
  whole-response validation.
- Rejects unknown fields, invalid typed sections, unpermitted evidence, policy-widening actions, and
  persistent proposals in the initial slice.
- Preserved the existing mock `CoachModelProvider`; no live provider, key, or provider-specific
  domain dependency was added.
- Added forward migration `20260702090000` with forced-RLS policy evaluations, model runs,
  decisions, service-only deterministic snapshot/persistence RPCs, idempotency, daily rate limiting,
  and sanitized usage/failure metadata.
- Added authenticated `coach-decide`; caller identity comes only from JWT.
- Added Today latest-decision state, Coach generate/refresh/evidence surfaces, provider-failure
  fallback, and Account owner-only usage summary.

## Verification

- Deno format, lint, type-check, and tests pass: 16/16.
- Full pgTAP passes 101/101; Phase 5 covers forced RLS, grants, deterministic request-data policy,
  immutable snapshots, idempotency, owner isolation, failure recording, sanitized usage, and
  replay-safe audit events.
- Flutter format/analyze and 35/35 tests pass, including grounded decision and provider-failure UI
  behavior.
- Unsigned physical-device iOS release build passes at 18.3 MB; no simulator.
- Linked dry run lists only migration `20260702090000`. Local CLI database lint remains unavailable
  because of the documented host-port timeout; pgTAP ran directly against the healthy SSD-local
  container.

## Hosted deployment and device build

- Explicit Phase 5 deployment approval was received on 2026-07-02.
- A scoped dry run was repeated with the pending Phase 6 migration excluded; it listed only
  `20260702090000`.
- Migration `20260702090000` deployed successfully and matches remote.
- `coach-decide` version 1 deployed successfully and reports ACTIVE.
- An unauthenticated hosted POST returns sanitized HTTP 401 `authentication_required`.
- Phase 6 migration `20260702110000` was not deployed.
- A hosted-config signed arm64 release build completed at 19.1 MB without a simulator and was
  installed on the owner's iPhone 12.
- The rebuilt developer profile was trusted and CLI launch succeeded. Owner QA confirmed Coach
  generation, Today decision state, and normal app behavior. Account AI-service rows are
  status/planned controls and do not open details; this is not a Phase 5 backend failure.

The mock provider remains intentional until live-provider privacy, budget, and evaluation gates are
approved. No live provider credential was added.
