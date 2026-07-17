# Gemini Provider Readiness — 2026-07-03

## Outcome

- Reviewed current official Gemini structured-output, billing, data-use, and retention guidance
  against Tracend's restricted-data rules.
- Confirmed the unpaid project is not eligible for personal health/coaching context. No live Gemini
  request or mobile behavior change was made.
- Added a server-only structured-output adapter requiring an explicit paid-data gate. It keeps the
  API key in a request header, applies a timeout, and exposes only sanitized failures.
- Added synthetic tests for the privacy gate, schema request, key handling, semantic validation
  boundary, and error redaction.
- Added an off-by-default provider factory, bounded deterministic feature context, kill switch,
  usage/cost metadata, and service-only persistence RPCs.
- Hosted migration `20260703190000` and `coach-decide` version 7. No provider- selection secret
  exists, so the deployed function still uses mock.

## Verification

- `./scripts/deno.sh task check` — 28/28 passed.
- Full pgTAP — 247/247 passed.
- Flutter format/analyze/test — 55/55 passed; unsigned iPhone release build is 19.0 MB. No simulator
  was used.
- Local/remote migration histories match; unauthenticated `coach-decide` returns HTTP 401.
- The documented hosted database dump failed before output because the local container could not
  resolve the direct Supabase database hostname. No partial file was accepted as a backup.

## Remaining Gates

Paid-service data terms, provider-control documentation, full text evaluation parity, explicit
activation, and owner-device QA remain before live coaching.
