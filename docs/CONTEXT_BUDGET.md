# Coach Context Budget

## Why This Exists

The coaching pipeline assembles user context across the versioned database layers, adds fresh
coaching-date scores/evidence in v7, renders a prioritized bounded context in the Edge Function,
and sends it to the AI model. When any layer adds data without checking the
cumulative budget, the pipeline fails silently in production. This has happened repeatedly because
nothing enforces the budget end-to-end.

This document is the contract. Any PR that adds data to the coach context pipeline must pass the
budget test or explicitly increase the budget with justification.

**Gateway route and contributors (Phase 2, chunk A6):** when the `AI_COACH_CHAT_*` settings make
a gateway route, Coach chat sends a cache-friendly request (below); without them it keeps today's
DeepSeek request byte for byte (`coach_chat_parity_test.ts`). `prepare_coach_chat_v8` and
`build_coach_athlete_context` stay frozen for the program; new context arrives through Contract 7
contributors (`_shared/coach_context/`), each with its own character budget. See
[`docs/plans/coaching-platform-2026-10/README.md`](./plans/coaching-platform-2026-10/README.md).

## Gateway Prompt Layout (A6)

Stable first, so questions asked within 5 minutes of each other share a cached prefix (Claude
caches prefixes of 512 tokens or more; the cache lasts 5 minutes from its last use):

1. System: persona, data honesty and the answer contract with the day's evidence codes.
2. User message, block 1 (cache breakpoint): the athlete file without conversation memory, then
   the stable contributors.
3. Block 2: conversation memory (session history, other conversations, this thread), the
   "Omitted This Turn" line, then the volatile contributors.
4. Block 3: the question. A repair attempt adds its instruction after it, so it reuses the cache.

The athlete file and memory share the same budget as today (96,000 characters, 128,000 for a plan
change; wrappers and question reserved first) and the same whole-section dropping.
`renderCoachContextParts` splits the one rendering; `formatContextAsMarkdown` joins it for the
legacy path. Contributors render after the athlete file in the registry's fixed order, each
clipped to its `budgetChars` (at most 12,000) and labelled as reference data; a contributor that
fails, returns nothing or takes over 4 seconds is left out. Their budgets are on top of the
athlete file's and count toward the turn's budget reservation.

## Safety Blocks (A9)

Three deterministic pieces came with the Coach guardrails. None changes a budget layer; they sit
inside budgets that already exist.

| Piece | Where | Size | Notes |
| --- | --- | --- | --- |
| Safe Ranges section | Athlete file, after the profile (`renderCoachContextParts`) | about 660-900 characters (712 for a full profile; 891 with the pain line; 658 with no data) | Inside the 96,000 / 128,000 file budget, rendered as a required section (never dropped). Calorie floor, weekly loss ceiling, healthy-weight floor, longest cut, effort-cap pointer, and the pain-of-7 line on an escalate day. |
| Plan Status section | Athlete file, after the Safe Ranges, only when `plan_status` says there is no plan or no nutrition target | 470 (no plan approved) or 627 (`see_professional`) characters | Required section. Stated reason, health-check outcome and date, and "no plan-specific advice". |
| Coaching principles digest | First stable contributor (cached block, after the athlete file) | 6,581 characters (limits 4,800 to 7,200; budget 7,200) | Fixed text, no athlete data (E2). Its figures ground the numbers check. Counts toward the turn's budget reservation; Sonnet 5.5 still fits one reservation. Changing the text changes the cached prefix: bump its version. |
| `screening` contributor | Stable contributor block, first in the registry | 249 (cleared), 458 (see_professional), 483 (moderate_until_cleared) or about 800 (unknown, when the lookup failed) characters; budget 900 | Counts toward the turn's budget reservation (`coachContextMaxChars`); nothing renders for an athlete never screened. |
| Persona and contract lines | System prompt | about +1,650 characters (7,265 before A9) | Inside the 16,000-character instructions reserve. |

Sonnet 5.5 as the stronger Coach route still fits one budget reservation (USD 0.50) with these
blocks; `coach_chat_provider_route_test.ts` fails if a larger block ever pushes it over.

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
log and 7/14/28-day totals, watch workouts, 28 days of watch data with averages that each carry
the days their metric was measured, eight weeks of weights, 14 days of check-ins, 28 days of
logged nutrition, today's meals, plan structure, proposals, reconciliations, data freshness). The
Edge message puts this file first and the question last, so the file is a stable, cacheable prefix
across a day's questions. Since 2026-09-30 the Edge message also carries a "Calculated by Tracend"
section computed from the same file (about 2,600 characters for a fully logged athlete). It adds no
database query and no model call, and it keeps the prefix cacheable because it changes only when
the file does.

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
| Gateway route | 96,000 / 128,000 chars | Same as Edge DeepSeek | Same file, split at the cache breakpoint before conversation memory |
| Each contributor | its `budgetChars` (≤ 12,000) | Clip | Labelled reference data, after the athlete file |

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
- `supabase/functions/_shared/providers/coach_chat_provider_gateway.ts` — gateway prompt layout
- `supabase/functions/_shared/coach_context/registry.ts` — contributors and their budgets
- `supabase/migrations/20260927230000_coach_chat_v8_full_athlete_context.sql` — v8 90K guard and
  conversation memory, first version. The current definition of `prepare_coach_chat_v8` is in
  `20261002110000_coach_intake.sql`, the latest migration that replaces it (same 90K guard)
- `supabase/migrations/20260928040000_coach_chat_long_threads.sql` — v1 18K guard (history trim)
- `supabase/migrations/20260719090000_context_budget_guard.sql` — DB v5 40K guard
- the latest additive `prepare_coach_chat_v*` migration — fresh fields and context version
- `supabase/functions/_shared/providers/coach_chat_provider_test.ts` — contract test
- This document
