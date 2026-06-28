# Tracend Testing Strategy

**Status:** Authoritative MVP quality strategy  
**Scope:** Flutter iOS app, Supabase Auth/PostgreSQL/Storage/Edge Functions/Queues/Cron, HealthKit, and controlled AI

This strategy verifies [PRD.md](./PRD.md), [ARCHITECTURE.md](./ARCHITECTURE.md), [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md), [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md), and [UX_FLOWS.md](./UX_FLOWS.md).

## 1. Quality Gates

A change is complete only when:

- deterministic logic has proportional unit tests;
- external and persistence boundaries have integration tests;
- affected journeys have widget, Data API/RPC/Edge Function, or end-to-end coverage;
- AI schema, policy, grounding, and safety fixtures pass;
- privacy and user-isolation checks pass for sensitive flows;
- UI passes accessibility, theme, state, and reduced-motion review; and
- lint, static analysis, migration checks, and supported builds succeed.

Safety-critical fixtures and cross-user isolation require a 100% pass rate. A flaky test is not accepted as a permanent retry.

## 2. Test Layers

### Unit

- trends, adherence, baselines, workload, nutrition totals, freshness, and confidence;
- policy eligibility and persistent-change thresholds;
- canonical units and timezone conversion;
- schema and semantic validation;
- state reducers, formatters, and token mapping; and
- redaction and retention-date logic.

### Integration

- PostgreSQL constraints, RLS policies, grants, transactions, idempotency, and version activation;
- Supabase Auth native Sign in with Apple using fixtures and nonce/error cases;
- HealthKit normalization for authorized, partial, stale, duplicate, unavailable, and empty responses;
- upload authorization, purpose binding, signed-read expiry, and deletion;
- provider adapters using sanitized contracts, never production health data; and
- Supabase Queue/Cron retry, deduplication, cancellation, authorization recheck, and terminal failure.

### Supabase boundaries

For each exposed table, Storage policy, RPC, and Edge Function, test anonymous access, same-user access, cross-user access, validation, canonical units, idempotency where relevant, expected audit event, and safe errors. Test Flutter with a publishable key; secret/service-role tests run only in trusted server fixtures.

### Flutter widget and flow

- onboarding autosave and both branches;
- Today states and Trajectory Lens semantics;
- offline workout logging and synchronization;
- meal candidate editing and confirmation;
- proposal approval/rejection;
- HealthKit permission/status variants;
- progress-photo capture guidance and private access; and
- export/deletion and recent-authentication gates.

### End-to-end critical suite

1. Sign in → beginner onboarding → approve initial plan.
2. Check in → receive decision → inspect evidence.
3. Start workout offline → log sets → reconnect → complete.
4. Upload meal → correct candidates → confirm totals.
5. Reject proposal with no plan mutation.
6. Accept proposal and activate exactly one new version.
7. Export and verify user ownership and contents.
8. Delete account and verify propagation across storage layers.

## 3. AI Evaluation

Use versioned synthetic or explicitly consented, minimized fixtures. Each includes feature snapshot, policy result, permitted actions, expected decision class, forbidden behavior, and rubric.

Required groups cover:

- stable plan where maintain is correct;
- true plateau versus inadequate adherence;
- isolated poor session versus repeated regression;
- poor sleep and same-day adjustment;
- pain and red-flag escalation;
- missing, stale, contradictory, and adversarial text;
- mixed meals, hidden ingredients, and uncertain portions;
- inconsistent progress photos and prohibited body-composition certainty;
- prompt injection in notes/imports;
- schema failure, timeout, outage, and fallback; and
- every supported goal and onboarding branch.

Score schema validity, policy compliance, grounding, decision class, hallucination, repeatability, clarity, meal accuracy, latency, and estimated cost. Model, prompt, schema, retrieval, or orchestration changes require regression comparison to the baseline.

## 4. Security and Privacy Tests

- Attempt cross-user reads and mutations for every user resource.
- Verify signed URLs are short-lived, purpose-bound, and invalid after deletion.
- Scan logs for tokens, prompts, notes, health values, meal descriptions, photos, and signed URLs.
- Verify consent withdrawal stops new provider processing.
- Verify retention jobs delete media and metadata by purpose.
- Verify export is complete, user-scoped, machine-readable, and recently authenticated.
- Verify deletion is idempotent and propagates to Supabase Auth, PostgreSQL, Storage, Queues, exports, derived artifacts, and provider-held data where applicable.
- Verify notifications contain no sensitive lock-screen content.

## 5. UX and Accessibility

- Test light and dark themes independently.
- Test compact/large iPhones, landscape, safe areas, keyboard, and iPad-compatible width.
- Test largest Dynamic Type, Bold Text, Increase Contrast, Differentiate Without Color, and Reduced Motion.
- Verify targets are at least 44×44pt and icon-only actions have labels.
- Manually review VoiceOver order, traits, hints, charts, and lens summaries.
- Test loading, slow, success, empty, partial, offline, error, retry, and cancellation.
- Ensure animations are interruptible and cause no layout shifts.

## 6. Performance Baseline

Measure on the oldest supported iPhone:

- tap feedback within 100ms;
- interactive motion targeting 60fps without sustained misses;
- no avoidable main-thread image processing;
- no unbounded history/list rendering;
- Today usable from cached approved state without waiting for AI; and
- media processing never blocking non-media navigation.

Set numeric binary-size, launch, Data API/Edge Function, and AI-latency budgets after the first measured vertical slice.

## 7. Test Data

- Factories create synthetic user-scoped data with explicit timezone and units.
- Fixtures use stable clocks and deterministic seeds.
- Production photos, prompts, HealthKit exports, tokens, and notes never enter source control.
- Media fixtures include valid, oversized, corrupt, mismatched, and malicious files.
- Shared fixture IDs are prohibited where they could hide tenancy bugs.

## 8. CI and TestFlight Gates

CI eventually runs formatting, strict Dart/TypeScript analysis, unit and integration tests, Supabase migration/RLS/grant validation, Edge Function schema tests, Flutter tests, AI evaluation smoke tests, secret scanning, and builds.

Before TestFlight expansion:

- full AI/safety evaluation passes;
- critical end-to-end tests pass on the hosted private-beta project using synthetic test accounts, or on staging if a separate staging project is later created;
- privacy export/deletion and Free/Pro backup-restore drills pass as applicable;
- manual VoiceOver/device matrix is complete;
- crash, latency, cost, and proposal-rate telemetry is reviewed; and
- known limitations and rollback owner are recorded.

Exact commands belong in `DEVELOPMENT_GUIDE.md` only after scaffolding exists.
