# 2026-07-01 — Phase 2 Local Vertical Slice

## Outcome

Implemented the local Phase 2 Auth, Onboarding, and Approval vertical slice.
ADR 0002 permits owner-only Supabase email/password auth until Apple Developer
Program capabilities are available; Sign in with Apple remains required before
an external private beta.

## Delivered

- real Supabase session gate and runtime-only email/password form;
- beginner and experienced onboarding with eligibility, consent, autosave,
  review, deterministic mocked proposal, and explicit response states;
- forward-only user/profile/consent/draft/goal/snapshot/proposal/plan/target/audit
  migrations with forced RLS;
- service-only mock persistence and authenticated transactional activation;
- replay, invalid-payload, anonymous, and cross-user protections; and
- sign out back to the authenticated app gate.

HealthKit, native Sign in with Apple, live AI calls, and hosted deployment were
not added.

## Verification

- Deno format/lint/tests: pass, 2 tests.
- pgTAP: pass, 39/39 across two isolated users and both onboarding paths.
- Flutter format/analyze: pass, no issues.
- Flutter tests: pass, 21 tests.
- Unsigned iPhone arm64 release build: pass, 17.3 MB.
- No simulator was started.

The pinned Supabase CLI timed out on its host-port handshake after recreating
the refreshed PostgreSQL container. The container was healthy; all three
migrations were reapplied from scratch inside it and the full pgTAP suite then
passed. Hosted changes were still pending at that checkpoint and were deployed
later as recorded below.

## Hosted Deployment

After explicit approval, the linked dry run listed only
`20260701090000_phase_2_onboarding_approval.sql` and
`20260701100000_phase_2_mock_proposal_boundary.sql`. Both applied successfully.
Remote migration history matches all three local versions.

Docker bundling could not resolve the function entrypoint through the external
SSD bind mount, so the verified `--use-api` server-side bundler was used.
`onboarding-propose-plan` deployed successfully and reports ACTIVE at version 1.
No synthetic hosted users or private data were created during deployment.
