# Owner Continuation Import — 2026-07-04

## Outcome

- Reviewed an owner-supplied historical coaching report as restricted input; raw content was not
  committed or copied into repository documentation.
- Created an encrypted owner-scoped pre-change backup on the external SSD.
- Added a validated service-only import that creates new goal, training-plan, nutrition-target,
  workout, exercise, and progress versions while retaining prior records and writing sanitized audit
  metadata.
- Repaired placeholder workout seeding for imported plans through a forward migration. Added
  explicit measurement supersession so setup fixtures do not affect progress calculations.
- Hosted import completed atomically: one active imported plan, six workouts, 33 exercises, three
  confirmed progress checkpoints, and one audit event.
- Added a one-time 31-day Apple Health backfill followed by normal seven-day overlap sync. Only
  normalized daily summaries leave the device.
- Reviewed current official DeepSeek policy and rejected hosted DeepSeek for restricted health data.
  No key was accepted and no provider request occurred.
- Hosted the production rebuild migrations and Edge Functions, then tightened Gemini routing so
  production usage accepts only `gemini-3.5-flash`; Flash-Lite fails closed in `meal-analyze`
  configuration and service-only usage RPCs.

## Verification

- pgTAP: 287/287 passed after a clean local reset.
- Flutter: analysis clean; 65/65 tests passed.
- Deno: 32/32 passed.
- Hosted migrations match local history.
- Hosted functions `coach-decide`, `coach-chat`, and `meal-analyze` reject unauthenticated requests
  with HTTP 401. Billing remains disabled, so no live Gemini request was made.
- Hosted-config iPhone release built, passed strict signing, installed, and launched on the paired
  iPhone.
