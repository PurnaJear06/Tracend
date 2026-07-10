# ADR 0002: Owner Development Authentication

**Status:** Accepted  
**Date:** 2026-07-01

## Context

Phase 2 requires a real Supabase Auth identity before onboarding, RLS, and
approval behavior can be implemented and tested. The owner is currently using
a free Apple development account, which does not expose the Sign in with Apple
capability required by the intended external private-beta flow.

Anonymous authentication or a client-side bypass would weaken account
durability, obscure the real tenancy boundary, and make two-user RLS testing
less representative.

## Decision

- Add a Supabase email/password authentication mode for owner-only development.
- Keep Supabase Auth as the session authority and `auth.users.id` as the
  canonical identity in every mode.
- Select auth mode through non-secret environment configuration; do not
  hard-code owner credentials or commit passwords.
- Do not add an unauthenticated shortcut, synthetic fixed user, or anonymous
  production session.
- Keep native Sign in with Apple as the required route before inviting external
  private-beta users.
- Keep downstream onboarding, RLS, consent, proposal, and approval contracts
  independent of the selected sign-in mechanism.

## Consequences

- Phase 2 owner dogfooding can proceed without paid Apple membership.
- Email/password UI is a development surface, not a new public product promise.
- Two separate test users can exercise cross-user isolation with normal
  Supabase sessions.
- Enabling an external private beta still requires Apple Developer Program
  membership, Apple capability configuration, and native token/nonce testing.
