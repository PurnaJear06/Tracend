# 2026-07-16 Coach Context v4

## Problem
Coach Context v3 (`prepare_coach_chat_v3`) produced 8,467 input tokens for every
chat request, exceeding Groq's free-tier hard cap of 8,000 TPM. Every chat request
returned HTTP 413 `rate_limit_exceeded`. Root cause: v3 bundled 12 full workout
sessions with per-exercise/per-set detail, 10 proposals, reconciliations,
7-day nutrition/HealthKit — regardless of the user's question.

## Solution
Coach Context v4 implements query-aware context selection:

1. **Question classifier** (`classifyQuestion()`): regex-based, 6 kinds:
   `daily_action`, `plan_change`, `explain_evidence`, `nutrition_focus`,
   `recovery`, `general`. Domain-specific patterns are checked before broader
   ones (plan_change → recovery → explain_evidence → nutrition_focus →
   daily_action → general).

2. **Bounded SQL** (`prepare_coach_chat_v4`): each context kind queries only
   the data relevant to that question type. Every query uses LIMIT. No unbounded
   queries. `prepare_coach_chat_v3` wraps v4 with `'general'` kind for
   backward compatibility.

3. **JSON compaction** (`compactContext()`): strips nulls recursively,
   abbreviates known keys (e.g., `prescribed_workout` → `w`), truncates
   rationales to 120 chars, drops empty arrays. Applied only in the Groq
   provider path before `JSON.stringify`.

## Files Changed

| File | Change |
|---|---|
| `supabase/migrations/20260716120000_coach_context_v4.sql` | Drop v3, create v4 skeleton, recreate v3 wrapper, RLS grants |
| `supabase/migrations/20260716121000_coach_context_v4_enrichment.sql` | Add plan_change placeholder |
| `supabase/migrations/20260716122000_coach_context_v4_enrichment.sql` | Full v4 with all 6 context kinds |
| `supabase/functions/coach-chat/index.ts` | Import `classifyQuestion`, call `prepare_coach_chat_v4` with `context_kind` |
| `supabase/functions/_shared/providers/coach_chat_provider.ts` | Add `classifyQuestion()`, `compactContext()`, `keyAbbreviations`, `compactValue()`; apply compacted context in Groq path |
| `supabase/functions/_shared/providers/coach_chat_provider_test.ts` | 15 new tests: 7 classification domains + 8 compaction fixtures |
| `supabase/tests/database/coach_context_v4_test.sql` | 37 pgTAP assertions: RLS, kind validation, fallback, idempotency, size budgets |
| `docs/adr/0007-coach-context-v4-query-aware-selection.md` | ADR |
| `docs/handoff/backend.md` | Current state update |
| `docs/PROGRESS_CONTEXT.md` | Pointer update |
| `docs/worklog/2026-07-16-coach-context-v4.md` | This file |

## Verification

- **Deno check:** 51/51 passed (fmt, lint, test) — zero regressions
- **Hosted migrations:** 3 forward migrations applied successfully
- **Edge Function:** `coach-chat` redeployed with v4 changes
- **Pending:** Owner should send one chat message from the app to confirm
  Groq returns HTTP 200 (not 413)

## Context Kind Budget

All kinds produce bounded context well below v3's 8,467 tokens. Plan shows each
kind's v2-derived base plus kind-specific enrichment, with additional compaction
in the TS provider layer.

## Design Notes

- `classifyQuestion` ordering matters: specific domains (recovery,
  explain_evidence, nutrition_focus) are checked before daily_action. Without
  this ordering, common words like "what", "do", "should" in the daily_action
  pattern would capture queries meant for other domains.
- `plan_change` session trends omit per-exercise top loads to stay under token
  budget. Per-exercise detail is available in the base v2 context included with
  every kind.
- `compactContext` key abbreviations were chosen for readability/debugging:
  short enough to save tokens, long enough to be recognizable in logs.
