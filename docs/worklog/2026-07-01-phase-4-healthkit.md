# 2026-07-01 — Phase 4 HealthKit daily summaries

Implemented the first complete Phase 4 vertical slice without simulator use.

## Mobile

- Added pinned `health` 13.3.1 behind `HealthDataSource`.
- Requested only the seven PRD-approved read types after an explicit user tap.
- Added deterministic daily normalization, supported sleep-stage totals, duplicate/malformed
  removal, canonical units, explicit HRV SDNN milliseconds, SHA-256 source references, freshness,
  and partial/manual/unavailable states.
- Added Today and Account connection surfaces with manual fallback. Removed fixture
  sleep/recovery/readiness claims from Today pending real evidence.
- Added HealthKit purpose strings and entitlement configuration.

## Backend

- Added forward migration `20260701140000_phase_4_healthkit_summaries.sql`.
- Added forced-RLS summary/sync tables and a service-role-only transactional RPC.
- Added authenticated `health-sync` with strict schema, range, window, provenance, completeness,
  duplicate-type, and identity validation. The function uploads summaries only, never raw samples.

## Verification

- Flutter format, analysis, and 33 tests pass.
- Deno format/lint/type-check and nine tests pass.
- Every migration applies to a freshly recreated local schema and pgTAP passes 81/81.
- iOS config-only and full unsigned release builds pass; `Runner.app` is 18.3 MB and no simulator
  was used.
- Linked migration dry run lists only the Phase 4 migration.
- All Flutter/CocoaPods/build artifacts remain under `.tooling/`.

## Hosted deployment and device build — 2026-07-02

- Explicit approval was received before hosted mutation.
- Migration `20260701140000` deployed successfully; local and remote migration versions match.
- `health-sync` version 1 deployed successfully and reports ACTIVE.
- An unauthenticated hosted POST returns HTTP 401 with the sanitized `authentication_required`
  response.
- A hosted-config signed release build completed at 19.1 MB without a simulator. Flutter, CocoaPods,
  dependencies, and build output remained under repository `.tooling/` on the external SSD.
- The signed app and embedded provisioning profile both contain the HealthKit entitlement, and the
  build is installed on the owner's iPhone 12.
- At this checkpoint, CLI launch was blocked until iOS trusted the regenerated developer profile.
  The later verification below resolved that blocker and completed permission, partial-data,
  refresh, and sync checks.

## Physical-iPhone verification — 2026-07-02

- The developer profile was trusted and Tracend opened successfully.
- The owner enabled all requested Apple Health read permissions and refreshed from the Account
  surface; Today reflected the same shared repository state.
- Hosted verification found three authenticated sync runs. The latest was a valid partial run with
  seven summaries accepted and zero rejected.
- Apple Health returned five supported categories for the tested window; sleep and weight had no
  returned records. This remains `partial`, not permission denial or sync failure.
- No health measurements or user identifiers were copied into documentation. Real-device revocation
  remains a non-blocking regression check.
