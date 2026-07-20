# Coach Continuity Proposal

**Proposed:** 2026-07-17 **Status:** Accepted (ADR-0009) **Author:** Owner + Codex

## Problem

The Tracend Coach responds accurately but does not feel like a continuing personal trainer. Each
reply is mechanically correct while the user's GPT Project experience shows what is missing: a
timeline, memory of what failed, visible reasoning, and journal continuity.

## Solution

Five-layer structured memory stack, all PostgreSQL with forced RLS, consumed by the existing
`prepare_coach_chat_v4` pipeline. The model rephrases prepared context; it never authors memory.

1. **Coaching Narrative** — timeline of phases ("aggressive cut", "recovery")
2. **Preference Memory** — confirmed user likes/dislikes with provenance
3. **Session Journal** — daily deterministic summaries
4. **Reasoning Chain** — visible step-by-step in UI
5. **Retrieval Router** — tsvector FTS replaces static 20+20 messages

Token budget: +100 input, +100 output. Net neutral on 8K cap.

## Delivered Files

- `supabase/migrations/20260717100000_coach_memory_foundation.sql`
- `supabase/migrations/20260717103000_coach_message_fts.sql`
- `supabase/migrations/20260717110000_prepare_coach_chat_v5.sql`
- `supabase/functions/_shared/contracts/coach_chat_v2.ts`
- `supabase/functions/_shared/providers/coach_chat_provider.ts` (updated)
- `supabase/functions/coach-chat/index.ts` (updated)
- `lib/features/coach/widgets/reasoning_chain_card.dart`
- `lib/features/coach/widgets/preference_prompt_chip.dart`
- `lib/features/coach/coach_screen.dart` (updated)
- `lib/features/coach/coach_repository.dart` (updated)
- `docs/adr/0009-coach-continuity-memory.md`
