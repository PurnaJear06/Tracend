# ADR 0009: Coach Continuity Memory

**Date:** 2026-07-17 **Status:** Accepted

## Context

Owner QA confirmed the Coach generates correct structured output but does not feel like a continuing
personal trainer. The user's GPT Project coach experience reveals the gap: GPT reads entire project
history on every call, creating a "mental timeline" and continuous narrative. Tracend instead serves
point-in-time snapshots with a static chat window.

Industry benchmarks (Mem0, Letta) confirm structured memory with retrieval outperforms full-context
brute-force at 3-5x lower token cost.

## Decision

Add five new PostgreSQL tables, each with forced RLS, to serve as structured coaching memory
consumed by `prepare_coach_chat_v5`:

1. `coach_narrative_entries` — timeline phases with deterministic headlines
2. `user_preferences` — confirmed preferences with provenance and expiry
3. `coach_session_summaries` — deterministic daily journal entries
4. tsvector FTS index on `coach_messages` for relevance-ranked retrieval
5. `reasoning_chain` field in `CoachChatAnswerV2` contract

All layers are additive to the existing pipeline. No existing table, RLS policy, or safety invariant
is relaxed.

## Consequences

- Deterministic engine gains responsibility for narrative phase detection
- `classifyQuestion()` gains preference-statement regex patterns
- `CoachChatAnswerV2` extends V1 with `reasoning_chain`
- Session summaries are produced post-chat via deterministic template (zero extra API cost); model
  summarization is deferred to evaluation gate
- tsvector remains within "no vector RAG" invariant (ARCHITECTURE.md §11)
- Token budget net increase: ~100 input + ~100 output (well within 8K cap)
- Provider prompts (Groq and Gemini) restructured to use multi-role messages (`system` + `user`) per
  AI_SAFETY_SPEC §11 — user text is now the primary content of the `user` turn and prepared context
  is delimited supporting evidence, not bundled with system instructions. The prior single-turn
  "Lead with one clear recommendation" instruction was removed because it forced plan-style answers
  even for greetings. Temperature on the Groq path is bumped from 0.15 to 0.2 for natural
  conversational tone; Gemini unchanged pending regression evaluation.
