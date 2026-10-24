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
clipped to its `budgetChars` (at most 12,000, by whole lines from the end, with a closing note that the rest was cut) and labelled as reference data; a contributor that
fails, returns nothing or takes over 4 seconds is left out. Their budgets are on top of the
athlete file's and count toward the turn's budget reservation.

## Safety Blocks (A9)

Three deterministic pieces came with the Coach guardrails. None changes a budget layer; they sit
inside budgets that already exist.

| Piece | Where | Size | Notes |
| --- | --- | --- | --- |
| Safe Ranges section | Athlete file, after the profile (`renderCoachContextParts`) | about 660-900 characters (712 for a full profile; 891 with the pain line; 658 with no data) | Inside the 96,000 / 128,000 file budget, rendered as a required section (never dropped). Calorie floor, weekly loss ceiling, healthy-weight floor, longest cut, effort-cap pointer, and the pain-of-7 line on an escalate day. |
| Plan Status section | Athlete file, after the Safe Ranges, only when `plan_status` says there is no plan or no nutrition target | 470 (no plan approved) or 627 (`see_professional`) characters | Required section. Stated reason, health-check outcome and date, and "no plan-specific advice". |
| Coaching principles digest | First stable contributor (cached block, after the athlete file) | 5,661 characters as shown, version 3 (limits 4,800 to 7,200; budget 7,200) | Fixed text, no athlete data (E2), shown without its inline source ids (E3.1: only retrieved excerpts are citable; the authored file keeps them). Its figures ground the numbers check. Counts toward the turn's budget reservation; Sonnet 5.5 still fits one reservation. Changing the text changes the cached prefix: bump its version. |
| `screening` contributor | Stable contributor block, first in the registry | 249 (cleared), 458 (see_professional), 483 (moderate_until_cleared) or about 800 (unknown, when the lookup failed) characters; budget 900 | Counts toward the turn's budget reservation (`coachContextMaxChars`); nothing renders for an athlete never screened. |
| Persona and contract lines | System prompt | about +1,650 characters (7,265 before A9) | Inside the 25,500-character instructions reserve. |

Sonnet 5.5 as the stronger Coach route still fits one budget reservation (USD 0.50) with these
blocks; `coach_chat_provider_route_test.ts` fails if a larger block ever pushes it over.

## Plan, Nutrition, Index and Lookups (A10)

Coach no longer gets everything about the athlete on every turn. A lean baseline is always on; the
rest of the athlete's records come from lookups the model asks for (AI_SAFETY_SPEC section 11.1).

| Piece | Where | Size | Notes |
| --- | --- | --- | --- |
| `training_plan` contributor | Volatile contributor, after the goal phase | up to 12,000 characters (budget 12,000, the host's ceiling). About 3,500 for a four-session plan, about 4,000 for six sessions of four exercises, about 9,900 for seven sessions of nine exercises with long names (tested) | Fixed parts first: the rules for naming exercises (home options), the plan's sets a week by muscle, the equipment, and the next 7 days from the athlete's date with each session's muscles (about 1,000 characters; the muscles two sessions share on consecutive days are stated by the watch-outs block, not here). Then the lists that grow with the plan: today's or the next session with each exercise's sets, reps, rest, load, next target and last logged set, and the other sessions compactly. Heart-rate load signals (C4) add at most one fixed sentence of about 110 characters to each step-up exercise (nine at most, about 1,000 characters) and one rest sentence of about 100 characters per session; the largest plan above still fits with all of them (tested as headroom, 9 x the longest sentence plus the rest line). The signals are read in parallel with the plan with their own 1-second deadline. The host cuts a block by whole lines from the end and ends it with a note, so a cut can only shorten those lists, never remove a rule or the week. Replaces the unregistered `progression` contributor and the athlete file's "Training Week Structure". |
| `nutrition_state` contributor | Volatile | up to 3,200 characters | The week's complete days (k of n), complete-day averages, partial days, today's schedule and meals, meal sources. Replaces the athlete file's per-logged-day nutrition lines, "Logged Nutrition", "7-Day Nutrition Compliance", "Nutrition Adherence", today's meals and the schedule line. |
| `watch_outs` contributor | Volatile, before the Coverage Brief; on the rollback (DeepSeek) path too, so the back-to-back muscles fact is not lost there | up to 1,200 characters (budget 1,200): an introduction of about 250 characters, then at most 8 lines in what the budget leaves (900 at most), packed by priority so the host never cuts a block. Typically 0 to 450 | Facts computed across kinds of record (muscles shared on consecutive days, a session due on a poor-recovery day, a pain flag planned again, behind plan, repeated skips, drift from the athlete's own usual, a stale weigh-in or sync, an old plan). No text when nothing is found; its counts still reach the route. Replaces the overlap sentence that sat in the training plan block. The facts and the schedule reads are limited to 2.5 s each, so a slow read costs only its own lines. |
| `coverage_brief` contributor | Volatile, gateway route only | 2,200 to 2,555 characters (budget 2,800); the largest it can be, with every count at six digits, is tested | Replaces the data index (about 1,100 characters, budget 1,900). One line per kind of record (14): what the context shows, what a lookup adds, how much exists and how fresh, and the kinds to check with it. Static text of about 1,500 characters plus the counts and dates; still shown, marked "counts unavailable", when the index read fails. Left out on today's DeepSeek path, which has no lookups. |
| Looked-up rows | After the question, one labelled block per round | up to 5,000 characters per lookup for up to 4 lookups a round, then 24,000 characters shared evenly (8 lookups: 3,000 each), 2 rounds (at most 48,000 characters in one turn). Whole rows only, newest first; the heading says "showing the newest N of M rows" when some were cut | Not part of the cached prefix. Each lookup call is a separate model call with its own reservation. The first round is meant to be wide (the sweep-first rule); a turn that needs nothing makes no call. |
| Lookup instructions | System prompt, gateway route only | about 4,300 characters (the catalogue text grew with the new filters and the sweep-first rules replaced the lines that told Coach to look up less) | The whole instructions measure 25,220 characters with the lookups, proposals and fact suggestions on and a full list of evidence codes (21,839 before); the reservation allows 25,500 (`instructionsMaxChars`, tested), up from 16,000, which had already been passed. |

Removed from the athlete file because a contributor or a lookup replaces them: "Today's Check-In"
(mislabelled when old; the dated check-in table stays), "Latest Weekly Review" (the SQL value is
a JSON object the renderer dropped; the `weekly_reviews` lookup serves it), the nutrition schedule
line, "Today's Meals", "Logged Nutrition", "7-Day Nutrition Compliance", "Nutrition Adherence",
"Training Week Structure" and the per-logged-day line in "Calculated by Tracend".

The worst-case reservation counts the contributors' budgets (`coachContextMaxChars`) plus the
athlete file and the instructions; a lookup round reserves from its actual prompt. Sonnet 5.5 still
fits one reservation (`coach_chat_provider_route_test.ts`). Since the route is chosen after the
contributors render (the structural signals come from them), the first attempt's place covers the
dearer of the two routes.

## Library Retrieval and the Heart-Rate Profile (E3)

| Piece | Where | Size | Notes |
| --- | --- | --- | --- |
| `heart_rate_profile` contributor | Volatile, after the proposals | up to 900 characters (budget 900) | Resting rate, maximum, zones and recovery after sets, from Apple Watch summaries (C3). Nothing renders without a profile. It was built in C3 and registered here. |
| `library` contributor | Volatile, gateway route only, last in the registry (just before the question) | up to 9,000 characters (budget 9,000; about 2,300 tokens); eight chunks average about 5,200 characters with the introduction (the eight longest chunks in the library total 7,500) | The chunks `search_library_v3` returned for this question that pass the relevance floor, whole chunks only, each starting `[source: <id>]` and the kind, year and evidence level (about 60 more characters a chunk, about 160 more for a chunk marked as Tracend's reading). With no chunk past the floor, one line of about 250 characters saying none matched. Left out when the search fails or takes over 4 seconds, and on a red-flag turn. Not part of the cached prefix: it changes with every question. |
| Library rules | System prompt, gateway route only | about 2,000 characters | "Using the research library": precedence, how to cite, no ids in the text, no gap filled from memory. Inside the 25,500-character instructions reserve. |
| Library evidence in the schema | Output schema | none: evidence is one object (`code` a plain string, `source` one of four) | `source: "library"` with any `code`; the ids shown change every turn, so they are checked after the answer (`citation_not_retrieved`), not listed in the schema. The whole output schema is one fixed 2,818-byte shape with no optional key and no union, so Claude compiles it once and caches it; it no longer lists the day's evidence codes (they are in the prompt). |
| Empty-value rules | System prompt, gateway route only | about 520 characters | "The shape of your JSON": every key is always present, `[]` and `""` for nothing, no null. Inside the 25,500-character instructions reserve. |

The two contributors add 9,900 characters to the worst case. Recomputed 2026-10-18 from the registry
(`coachContextMaxChars`; budgets: principles 7,200, screening 900, confirmed facts 4,200, goal phase
2,200, training plan 12,000, nutrition 3,200, proposals 1,800, heart rate 900, notes 3,600, data
index 1,900, library 9,000): the contributors' total is 49,924 characters (44,624 before the
week-ahead fix raised the training plan from 7,000 and the data index from 1,600). On 2026-10-20
the data index (1,900) gave way to the watch-outs (1,200) and the Coverage Brief (2,800), and the
instructions reserve rose from 16,000 to 25,500 characters: the total is 52,800 characters, so a
Sonnet 5.5 reservation is about USD 0.38 (0.36 before), a Haiku 5.5 one about USD 0.096, still under the USD 0.50 cap (`coach_chat_provider_route_test.ts`). Opus 5.5 was already over the cap and takes
today's path. The athlete file carries the hours next to each sleep duration it shows (`341 min (5 h 41 min; 5.7 h)`, about 22 characters a reading, 28 days in the table) and the proposals block one line of figures for each pending proposal (at most three, inside its 1,800 characters); the instructions gained one line about a pending proposal's figures.

Regional modules (E4) add no prompt text and no contributor: they are library sources, reached by
the same retrieval and inside the same 9,000-character `library` budget, and the athlete's country
only changes which sources the search may show. The cached prefix, the digest (still 5,661
characters as shown; there is no regional digest) and the answer schema are unchanged.

Plan explanations (E5) add no contributor and no prompt reserve to Coach chat. On a turn that asks why
the plan is the way it is, the `library` block gains a fixed note of about 560 characters (counted
inside the same 9,000, so one chunk fewer fits at worst) and it makes a second search, in parallel
with the first, for the question plus about 400 characters of plan topics (one more embedding and one
more `search_library_v3` call; the merged chunks still share the same 9,000 characters). The plan facts
are a read the plan section already makes (shared for the turn) and the goal inputs the goal phase
section already reads. The onboarding plan prompt (gateway route) gains, when the library is
searched: about 1,100 characters in the cached system prompt (one of three variants of the rules
about excerpts; the same for every athlete with the same outcome) and up to 6,000 characters of
excerpts, about 1,700 tokens, in the user message (the heading and the whole chunks that fit,
chosen from two searches of six chunks each). The cost ceiling is computed from the real prompt, so
the reservation grows with the excerpts (`gateway_test.ts` checks it); the plan schema gains one
required list of strings, `sources`. The settings path's prompt is unchanged.

The coaching principles digest (E2) stays in the cached prefix as before. The whole library was
measured against retrieval in E3 (then 85,000 characters, about 21,000 to 24,000 tokens) and is not
in the prefix: see the head-to-head in `docs/handoff/research-library.md`. It has since grown to
201,482 characters (57,566 tokens at 3.5 characters a token) on `main` before E4 and 220,432
characters (62,981 tokens) with E4's regional sources. The 70,000-token line in
`library_full_test.ts` guards only that shelved whole-library evaluation; no production prompt
reads it.

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
