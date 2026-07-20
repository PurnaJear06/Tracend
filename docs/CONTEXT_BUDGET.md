# Coach Context Budget

## Why This Exists

The coaching pipeline assembles user context across five database layers (v1→v5), compacts it in the
Edge Function, and sends it to the AI model. When any layer adds data without checking the
cumulative budget, the pipeline fails silently in production. This has happened repeatedly because
nothing enforces the budget end-to-end.

This document is the contract. Any PR that adds data to the coach context pipeline must pass the
budget test or explicitly increase the budget with justification.

## Budget Layering

```
DB v1 (prepare_coach_chat)              16K guard ← ONLY check before this doc
DB v2 (recent_other_conversations)      no guard
DB v4 (context-kind enrichment)         no guard
DB v5 (memory: narrative + prefs + journal)  40K guard ← NEW (20260719090000)
Edge (compactContext)                   30-40% compression
Edge (fitContextToLimit)                32K ceiling, 3-tier progressive trimming
Model (qwen/qwen3.6-27b)               131K tokens (~500K chars) ← huge headroom
```

## Budget Values

| Layer          | Limit        | Type             | Enforcement                                                              |
| -------------- | ------------ | ---------------- | ------------------------------------------------------------------------ |
| DB v1          | 16,000 chars | Hard guard       | PostgreSQL exception (unchanged)                                         |
| DB v5          | 40,000 chars | Trimming guard   | Trims `recent_messages`, `recent_other_conversations`, `session_journal` |
| Edge compacted | 32,000 chars | Progressive trim | Tier 1 (200 chars), Tier 2 (150 chars), Tier 3 (hard chop)               |
| Edge fallback  | Unlimited    | Never throws     | Returns minimal stub if all tiers fail                                   |

## Rules for Adding Coach Context Data

1. **Run the contract test before merging**:
   `deno test --allow-env supabase/functions/_shared/providers/coach_chat_provider_test.ts --filter "CONTEXT BUDGET CONTRACT"`
2. If the test fails, either reduce data volume elsewhere or increase budgets with a documented
   justification
3. New SQL context layers must include a size guard (like v5's 40K guard)
4. New Edge Function context additions must be registered in `messageArrays` or `longTextKeys` in
   `fitContextToLimit`'s Tier 1

## How Enterprise Systems Prevent This

What we're fixing here is industry-standard for production AI pipelines:

| Practice                             | Tracend Status                                              |
| ------------------------------------ | ----------------------------------------------------------- |
| **Contract tests with size budgets** | `CONTEXT BUDGET CONTRACT` test in CI                        |
| **Layered size guards**              | v1 (16K) + v5 (40K) + Edge (32K)                            |
| **Graceful degradation**             | `fitContextToLimit` returns fallback, never throws          |
| **Observability**                    | `console.log` context sizes in Edge Function                |
| **Configurable budgets**             | 32K/40K values are in source, changeable with justification |

## What To Do When The Contract Test Fails

1. Check which context kind exceeds the budget
2. Ask: does the new data actually improve coaching decisions? If not, drop it
3. If yes: can you trim existing data (shorter limits, fewer items) to make room?
4. If no: increase the budget at the appropriate layer and document the change here
5. Re-run the contract test

## Files To Update When Changing The Budget

- `supabase/functions/_shared/providers/coach_chat_provider.ts` — `fitContextToLimit` maxLength
- `supabase/migrations/20260719090000_context_budget_guard.sql` — DB v5 40K guard
- `supabase/functions/_shared/providers/coach_chat_provider_test.ts` — contract test
- This document
