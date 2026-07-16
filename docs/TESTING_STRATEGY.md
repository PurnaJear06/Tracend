# Tracend Testing Strategy

## Personal Coaching Evaluation Set

Fixtures cover server-session resume, unknown versus skipped logging, HealthKit
duration conflicts, illness, alternative exercises, incomplete evidence,
plateau analysis, and unsupported evidence IDs. Safety and durable-change
fixtures require a 100% pass rate.
Evidence UI tests cover 320–430pt phones, light/dark mode, 200% text, reduced
motion, compact Signal Rail layout, plain Health status, date-aware chart
semantics, same-day measurement amendment, and reconciliation candidate ranking.

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
- initial 31-day HealthKit backfill followed by seven-day overlap sync;
- upload authorization, purpose binding, signed-read expiry, and deletion;
- provider adapters using sanitized contracts, never production health data;
- provider selection defaults to mock, the live-provider kill switch and paid-
  data gate fail closed, API keys stay out of URLs/logs, and failures expose
  only sanitized codes;
- controlled-coaching request/response validation, deterministic policy,
  provider failure, idempotency, rate limit, evidence grounding, and escalation;
- live Coach chat never converts an unconfigured, provider-failed, or
  schema-invalid response into a successful deterministic fallback; a bounded
  schema-repair retry either returns validated model output or a sanitized
  failed run;
- user-scoped AI usage aggregation, including anonymous and cross-user denial,
  estimate labeling, and exclusion of secrets, prompts, request IDs, and raw
  errors;
- nutrition forced RLS, private meal Storage policies, manual idempotency,
  unconfirmed-candidate exclusion, transactional confirmation, deterministic
  totals, sanitized audit events, and cross-user denial;
- Supabase Queue/Cron retry, deduplication, cancellation, authorization recheck, and terminal failure.
- Weekly review tests additionally require opaque minimal payloads, immutable
  snapshot linkage, forced-RLS owner reads, deterministic evidence totals,
  zero generated proposals, acknowledgement ownership, and approved-plan
  availability while a job is delayed.

### Supabase boundaries

For each exposed table, Storage policy, RPC, and Edge Function, test anonymous access, same-user access, cross-user access, validation, canonical units, idempotency where relevant, expected audit event, and safe errors. Test Flutter with a publishable key; secret/service-role tests run only in trusted server fixtures.

### Flutter widget and flow

- onboarding autosave and both branches;
- Account profile, connection, AI service, usage, export, deletion, and sign-out states;
- Today states and Trajectory Lens semantics;
- offline workout logging and synchronization;
- meal candidate editing and confirmation;
- previous-day nutrition retrieval so confirmed meals remain visible after a
  coaching-day boundary;
- proposal approval/rejection;
- HealthKit permission/status variants;
- Today HealthKit readback, real-value trend rendering, and explicit missing-
  category copy without inferring permission denial;
- training surfaces must not render fixture performance charts in hosted mode;
- progress-photo capture guidance and private access;
- progress measurement ranges, deterministic deltas, empty/trend states,
  cross-user denial, separate photo consent, and private progress-bucket
  policies;
- consent-gated photo-set creation, upload-before-registration, path/type/size/
  checksum validation, short-lived reads, idempotent deletion, and partial
  capture recovery; and
- export/deletion and recent-authentication gates.
- production Today brief, complete weekly Train selection, prescription detail,
  Coach thread/composer/evidence behavior, next-meal schedule states, theme
  persistence, and Progress period/evidence gates;
- Coach context coverage distinguishes recent available HealthKit data from a
  genuinely absent source and labels evidence/data gaps separately from model
  follow-up suggestions;
- 320, 375, 390, and 430pt widths, landscape, text scales 1.0/1.3/2.0,
  light/dark, Reduce Motion, keyboard dismissal, and bottom-bar clearance.

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

`gemini-3.5-flash` is the only production route for Coach and separately gated
meal/progress vision. Meal evaluation covers mixed dishes, oil/sauces, hidden
ingredients, portion uncertainty, prompt injection, candidate edit rate,
latency, and cost. Safety-critical and schema fixtures require 100%; routing
remains disabled when the gate fails.

## 4. Security and Privacy Tests

- Attempt cross-user reads and mutations for every user resource.
- Verify signed URLs are short-lived, purpose-bound, and invalid after deletion.
- Scan logs for tokens, prompts, notes, health values, meal descriptions, photos, and signed URLs.
- Verify Flutter contains no provider-key input, storage, logging, or transport path.
- Verify consent withdrawal stops new provider processing.
- Verify confirmed administrative context import creates new active versions,
  preserves old versions, supersedes known fixtures, writes a sanitized audit
  event, and remains unavailable to mobile/anonymous roles.
- Verify retention jobs delete media and metadata by purpose.
- Verify meal-media retention claims only due, non-exempt objects, finalizes
  successful Storage deletion, and returns failures to a bounded retry state.
- Verify corrected candidates remain excluded before confirmation, confirmation
  snapshots corrections atomically, and meal deletion is owner-scoped,
  idempotent, audited, and reflected in deterministic totals.
- Verify export is complete, user-scoped, machine-readable, and recently authenticated.
- Verify JSON/CSV, units, provenance, timestamps, purpose-organized media,
  encryption, 60-second authorization, three-use limit, seven-day cleanup,
  retryable Storage deletion, and absence of persisted password/key material.
- Verify deletion is idempotent and propagates to Supabase Auth, PostgreSQL, Storage, Queues, exports, derived artifacts, and provider-held data where applicable.
- Run hosted destructive deletion only against a synthetic account and verify
  its minimal completion receipt contains no content attributes.
- Verify notifications contain no sensitive lock-screen content.
- Verify notification preference writes reject enabled reminders without iOS
  authorization, remain owner-scoped under forced RLS, and append grant or
  withdrawal evidence without storing message content.
- Verify notification choices survive app termination, missing pending requests
  are repaired only while authorized, and native scheduling errors are surfaced.

## 5. UX and Accessibility

- Test light and dark themes independently.
- Test compact/large iPhones, landscape, safe areas, keyboard, and iPad-compatible width.
- Test largest Dynamic Type, Bold Text, Increase Contrast, Differentiate Without Color, and Reduced Motion.
- Verify targets are at least 44×44pt and icon-only actions have labels.
- Verify long and numeric forms provide explicit, tap-outside, and drag keyboard
  dismissal without losing entered values.
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
- Mobile auth regressions cover an expired access token, successful SDK refresh,
  and a sanitized reauthentication message when refresh cannot recover.
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
