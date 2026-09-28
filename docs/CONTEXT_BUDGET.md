# Coach Context Budget

## Why This Exists

The coaching pipeline assembles user context across the versioned database layers, adds fresh
coaching-date scores/evidence in v7, renders a prioritized bounded context in the Edge Function,
and sends it to the AI model. When any layer adds data without checking the
cumulative budget, the pipeline fails silently in production. This has happened repeatedly because
nothing enforces the budget end-to-end.

This document is the contract. Any PR that adds data to the coach context pipeline must pass the
budget test or explicitly increase the budget with justification.

## Budget Layering

```
DB v1 (prepare_coach_chat)              18K guard: keeps the newest 20/10/4/0 messages first
DB v2 (recent_other_conversations)      no guard
DB v4 (context-kind enrichment)        no guard; v8 calls it with the neutral kind only
DB v5 (memory: narrative + prefs + journal)  40K guard (20260719090000)
DB v7 (fresh scores + shared evidence)  replaces stale fields; no history expansion
DB v8 (full athlete file for every question)  rebuilds conversation memory; 90K guard, drops whole sections, lists them
Edge (DeepSeek markdown)                96K (plan change 128K), wrappers and question reserved first
Edge (legacy JSON providers)            compact/trim path retained for disabled providers
Model (deepseek-flash, V4.1 Flash)       4,096-token output ceiling; 1M-token context window
```

Since v8 (2026-09-27) the question's keyword classification never adds or removes data. Every
question receives the same file: the v7 base plus `build_coach_athlete_context` (28-day training
log and 7/14/28-day totals, watch workouts, 28 days of watch data with averages, eight weeks of
weights, 14 days of check-ins, 28 days of logged nutrition, today's meals, plan structure,
proposals, reconciliations, data freshness). The Edge message puts this file first and the
question last, so the file is a stable, cacheable prefix across a day's questions.

Conversation memory (2026-09-28): v8 rebuilds it from `coach_messages` as the ten newest messages
of this thread and ten of other threads. Each message is capped at 2,000 characters, keeping its
ending, and a labeled data summary is never included. A question and answer saved in one
transaction are ordered question first. Before this:
- v5's 40K guard kept the oldest ten of the last twenty messages, so a long thread lost its
  newest turns, including the coach's clarifying question.
- The v1 guard raised `chat context too large` once the last twenty messages pushed the base
  context past 18,000 characters. Every new question in that thread failed with a 422 before the
  model ran. The guard now keeps fewer, newest messages first, and raises only when the context
  is oversized without any conversation.

Null values are preserved end-to-end since Pass 4 (2026-09-08): `null` is the NOT MEASURED
signal, not bloat. A null serializes to ~4 chars (`"k":null`), so null preservation adds
negligible budget pressure. The `CONTEXT BUDGET CONTRACT` tests protect required sections and the
legacy provider paths.

## Budget Values

| Layer          | Limit        | Type             | Enforcement                                                              |
| -------------- | ------------ | ---------------- | ------------------------------------------------------------------------ |
| DB v1          | 18,000 chars | Trimming guard   | Keeps the newest 20, 10, 4 or 0 thread messages; raises only if still oversized without them |
| DB v5          | 40,000 chars | Trimming guard   | Trims `recent_messages`, `recent_other_conversations`, `session_journal` |
| DB v8          | 90,000 chars | Whole-section guard | Drops other conversations, journal, proposals, reconciliations, watch workouts, nutrition log, watch log, training log (in that order); records `omitted_sections` |
| Edge DeepSeek (every question) | 96,000 chars | Whole-section budget | Reserves the question and wrappers; required truth renders first; history last; dropped sections listed |
| Edge DeepSeek plan change | 128,000 chars | Whole-section budget | Larger bounded context; no string slicing                                |
| Legacy compacted path | 32,000 chars | Progressive trim | Retained for disabled prior providers                                    |

## Rules for Adding Coach Context Data

1. **Run the contract test before merging**:
   `./scripts/deno.sh test --allow-env --allow-net supabase/functions/_shared/providers/coach_chat_provider_test.ts --filter "CONTEXT BUDGET CONTRACT"`
2. If the test fails, either reduce data volume elsewhere or increase budgets with a documented
   justification
3. New SQL context layers must include a size guard (like v5's 40K guard)
4. New Edge Function context additions must declare their priority. Context Date, Null Contract,
   Evidence Contract, and Computed Scores remain mandatory and byte-complete; history remains the
   first content dropped.

## How Enterprise Systems Prevent This

What we're fixing here is industry-standard for production AI pipelines:

| Practice                             | Tracend Status                                              |
| ------------------------------------ | ----------------------------------------------------------- |
| **Contract tests with size budgets** | `CONTEXT BUDGET CONTRACT` test in CI                        |
| **Layered size guards**              | v1 (18K) + v5 (40K) + v8 (90K) + Edge budgets               |
| **Graceful degradation**             | Whole optional sections are omitted; required truth is intact |
| **Observability**                    | Sanitized per-attempt outcome and latency telemetry            |
| **Configurable budgets**             | Budgets are in source and require contract-test review        |

## What To Do When The Contract Test Fails

1. Check which section pushes the file over the budget
2. Ask: does the new data actually improve coaching decisions? If not, drop it
3. If yes: can you trim existing data (shorter limits, fewer items) to make room?
4. If no: increase the budget at the appropriate layer and document the change here
5. Re-run the contract test

## Files To Update When Changing The Budget

- `supabase/functions/_shared/providers/coach_chat_provider.ts` — budgets and whole-section renderer
- `supabase/migrations/20260927230000_coach_chat_v8_full_athlete_context.sql` — v8 90K guard and
  conversation memory
- `supabase/migrations/20260928040000_coach_chat_long_threads.sql` — v1 18K guard (history trim)
- `supabase/migrations/20260719090000_context_budget_guard.sql` — DB v5 40K guard
- the latest additive `prepare_coach_chat_v*` migration — fresh fields and context version
- `supabase/functions/_shared/providers/coach_chat_provider_test.ts` — contract test
- This document
