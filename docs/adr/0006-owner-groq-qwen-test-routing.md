# ADR 0006: Server-side Groq Qwen owner-test routing

**Status:** Accepted for the owner-only test period

Groq `qwen/qwen3.6-27b` is enabled only behind Supabase Edge Functions for the
owner's time-bounded dogfood test. It powers Coach text and meal-photo candidate
extraction, remains subject to deterministic policy and schema checks, and cannot
confirm meals or activate persistent changes. The mobile client never receives
the key. Controls cap the test at 10 AI requests/day and USD 2 estimated monthly
cost. Progress-photo AI remains separately gated.

This is not a production-quality or privacy certification. Re-evaluate after ten
owner-test days using safety fixtures, meal corrections, latency, cost, and feedback.
