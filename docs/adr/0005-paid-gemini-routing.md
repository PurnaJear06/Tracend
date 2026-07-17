# ADR 0005: Paid Gemini Routing and Budget Gates

**Status:** Accepted, activation gated\
**Date:** 2026-07-04

## Decision

Use stable `gemini-3.5-flash` as the quality baseline for Coach reasoning and separately evaluated
image interpretation. Use medium thinking for Coach, low for meal extraction, and high only for
named difficult review classes. Reject Lite models in production configuration; task thinking and
budgets control cost.

Live traffic requires paid-service data terms, provider-control review, task-specific evaluation,
explicit server secrets, a USD 3 monthly warning, USD 5 hard stop, and 30 Coach requests per
owner/day. The deterministic mock is the automatic rollback provider.

## Consequences

The model choice optimizes quality per rupee without allowing cost to weaken safety. Deployment of
an adapter does not activate Gemini. Meal and progress vision remain separately consented and
separately gated.
