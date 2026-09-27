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
DB v1 (prepare_coach_chat)              16K guard ← ONLY check before this doc
DB v2 (recent_other_conversations)      no guard
DB v4 (context-kind enrichment)        no guard
DB v5 (memory: narrative + prefs + journal)  40K guard (20260719090000)
DB v7 (fresh scores + shared evidence)  replaces stale fields; no history expansion
Edge (DeepSeek markdown)                48K-128K kind budget, wrappers reserved first
Edge (legacy JSON providers)            compact/trim path retained for disabled providers
Model (deepseek-v4-flash)               4,096-token output ceiling
```

Null values are preserved end-to-end since Pass 4 (2026-09-08): `null` is the NOT MEASURED
signal, not bloat. A null serializes to ~4 chars (`"k":null`), so null preservation adds
negligible budget pressure. The `CONTEXT BUDGET CONTRACT` tests protect required sections and the
legacy provider paths.

## Budget Values

| Layer          | Limit        | Type             | Enforcement                                                              |
| -------------- | ------------ | ---------------- | ------------------------------------------------------------------------ |
| DB v1          | 16,000 chars | Hard guard       | PostgreSQL exception (unchanged)                                         |
| DB v5          | 40,000 chars | Trimming guard   | Trims `recent_messages`, `recent_other_conversations`, `session_journal` |
| Edge DeepSeek recovery/nutrition/evidence | 64,000 chars | Whole-section budget | Reserves the question and wrappers; required truth sections render first |
| Edge DeepSeek daily/general | 48,000 chars | Whole-section budget | Drops complete low-priority sections when they do not fit                |
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
| **Layered size guards**              | v1 (16K) + v5 (40K) + kind-specific Edge budgets            |
| **Graceful degradation**             | Whole optional sections are omitted; required truth is intact |
| **Observability**                    | Sanitized per-attempt outcome and latency telemetry            |
| **Configurable budgets**             | Kind budgets are in source and require contract-test review   |

## What To Do When The Contract Test Fails

1. Check which context kind exceeds the budget
2. Ask: does the new data actually improve coaching decisions? If not, drop it
3. If yes: can you trim existing data (shorter limits, fewer items) to make room?
4. If no: increase the budget at the appropriate layer and document the change here
5. Re-run the contract test

## Files To Update When Changing The Budget

- `supabase/functions/_shared/providers/coach_chat_provider.ts` — kind budgets and whole-section renderer
- `supabase/migrations/20260719090000_context_budget_guard.sql` — DB v5 40K guard
- the latest additive `prepare_coach_chat_v*` migration — fresh fields and context version
- `supabase/functions/_shared/providers/coach_chat_provider_test.ts` — contract test
- This document
