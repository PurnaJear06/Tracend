# ADR 0001: Phase 1 Foundation

**Status:** Accepted\
**Date:** 2026-06-28

## Context

Tracend needs a reproducible iOS-first Flutter and Supabase foundation without placing large project
dependencies or runtime state on the Mac's internal storage. The product is a private beta for
modern iPhones and does not need to support older iOS releases at the cost of additional
compatibility work.

## Decision

- Pin Flutter 3.41.7 and Dart 3.11.5 for the initial scaffold.
- Set the minimum deployment target to iOS 17.0.
- Target iPhone only for the private beta. Compile the unsigned physical-device release target in
  local checks and CI; use a connected iPhone for runtime QA after signing is configured instead of
  consuming Mac resources with a simulator.
- Use `com.tracend.app` as the working application identifier while the brand remains subject to
  name clearance.
- Pin Supabase CLI 2.101.0 and install it under `.tooling/` in the repository.
- Pin Deno 2.9.0, Docker CLI 29.6.1, Colima 0.10.3, and Lima 2.1.1 under `.tooling/` for
  project-local Edge Function and container execution.
- Pin `health` 13.3.1 for the iOS HealthKit bridge, `crypto` 3.0.7 for on-device SHA-256 source
  references, and `uuid` 4.5.3 for retry-safe sync identifiers. These packages add no analytics or
  remote data processor; HealthKit access remains behind the internal `HealthDataSource` boundary.
- Pin the Flutter-maintained `image_picker` 1.2.3 for user-initiated iOS camera and library
  selection. It adds no analytics or remote processor; selected bytes flow only to Tracend's private
  Supabase Storage after explicit consent.
- Keep package caches, container state, generated artifacts, and local service state under the
  external-SSD repository path.
- Use programmatic `UIScene` setup and `UILaunchScreen` instead of Interface Builder storyboards.
  Bundle the existing iPhone icon PNGs directly for the private device build so compilation does not
  depend on CoreSimulator's asset rendering service.
- Use local Supabase plus one future hosted Free project for owner dogfooding.
- Keep Apple, Storage, Queue, and AI integrations behind deterministic mocks until their roadmap
  phases. HealthKit becomes native only in Phase 4.
- Use `CoachModelProvider` as the only model-provider boundary. Phase 1 ships no live provider call.

The Apple team identifier and hosted Supabase region remain deployment configuration because they do
not affect the local backend foundation. They must be selected before device signing or
hosted-project creation.

## Consequences

- A clean checkout can install the exact Supabase CLI without a global package.
- Local container tooling must also use repository-local state.
- Device builds remain possible when CoreSimulator is unavailable; public App Store asset packaging
  remains deferred with the public release itself.
- Changing the working bundle identifier after Apple capabilities are created will require new Apple
  configuration, so name clearance should happen before TestFlight setup.
