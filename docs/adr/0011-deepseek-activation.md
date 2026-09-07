# ADR 0011: DeepSeek V4 Flash activation as the live Coach provider

**Status:** Accepted (2026-07-26 active; recorded 2026-09-06 during the post-review documentation
pass)

## Context

Coach text and chat need a live structured-output model behind Supabase Edge Functions that
passes the deterministic policy and schema checks at owner-beta cost. Two earlier candidates
were evaluated:

- Gemini `gemini-3.5-flash` (ADR 0005): gated on paid-service privacy terms; never activated.
- Groq Qwen `qwen/qwen3.6-27b` (ADR 0006): the owner dogfooding route through beta; confirmed
  working, superseded.

DeepSeek was first considered and **rejected on 2026-07-04** after the official privacy review
classified it as a restricted-data provider (roadmap §9). That rejection is part of this record:
the reversal below was a re-evaluation, not an oversight.

## Decision

DeepSeek V4 Flash (`deepseek-v4-flash`) is the active production Coach/chat provider via
`COACH_MODEL_PROVIDER=deepseek`, activated 2026-07-26.

Activation followed the all-or-nothing gate in [AI_SAFETY_SPEC.md](../AI_SAFETY_SPEC.md) §10:
all server-side secrets (`COACH_MODEL_PROVIDER`, `COACH_AI_ENABLED`, provider API keys) must be
configured together, and coach-decide still defaults to the deterministic mock unless the full
secret configuration is present. No provider key ever enters Flutter; the mobile client has no
provider knowledge.

Thinking mode is disabled for daily decisions (commit `230338f`, 2026-08-26): daily coaching
decisions run with thinking off for latency and cost determinism.

## Consequences

- Cost: ~USD 0.00084 per coach-chat request (5K input + 500 output at the 2026-07-22 standard
  rate of USD 0.14/1M input, USD 0.28/1M output) — roughly USD 0.75/month at 30 requests/day;
  a USD 2 console top-up covers ~2.5 months. Details in [COST_MODEL.md](../COST_MODEL.md).
- The monthly owner warning (USD 3) and hard stop (USD 5) plus the 30 requests/owner/day cap
  remain enforced server-side, unchanged from the prior providers.
- Gemini and Groq adapters remain in the codebase, disabled by default, and require their own
  data-terms/evaluation gates before any future use.
- Provider changes require new regression results per AI_SAFETY_SPEC §10.
