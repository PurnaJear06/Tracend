# ADR 0006: Server-side Groq Qwen owner-test routing

**Status:** Accepted, extended through owner beta

Groq `qwen/qwen3.6-27b` is enabled only behind Supabase Edge Functions for the owner's dogfood test
through beta. It powers Coach text and meal-photo candidate extraction, remains subject to
deterministic policy and schema checks, and cannot confirm meals or activate persistent changes. The
mobile client never receives the key. Controls cap the test at 30 AI requests/day and USD 5
estimated monthly cost. Progress-photo AI remains separately gated.

**2026-07-22 update:** The original ten-day expiry is removed. Groq Qwen is confirmed working and is
the default production provider through owner beta. Gemini is available as a gated alternative
(requires paid billing for privacy compliance). DeepSeek V4 Flash is available as a low-cost
alternative ($0.00084/chat, $0.75/month at 30/day) via `COACH_MODEL_PROVIDER=deepseek`.
