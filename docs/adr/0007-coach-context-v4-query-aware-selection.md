# ADR 0007: Coach Context v4 Query-Aware Selection

## Status

Accepted (2026-07-16)

## Context

Coach Context v3 (`prepare_coach_chat_v3`) produced a single monolithic context for every chat
request: 12 full workout sessions with per-exercise, per-set detail, 10 change proposals, workout
reconciliations, 7-day nutrition and HealthKit history, and data quality stats. This averaged 8467
input tokens, exceeding Groq's free `on_demand` tier hard cap of 8000 TPM. Every chat request
returned HTTP 413 `rate_limit_exceeded`.

## Decision

Implement Coach Context v4 with query-aware selection. A regex classifier (`classifyQuestion`)
determines the user's intent as one of six context kinds: `daily_action`, `plan_change`,
`explain_evidence`, `nutrition_focus`, `recovery`, or `general`. The SQL function
`prepare_coach_chat_v4` returns only the data relevant to that kind, with bounded LIMITs on every
query. A TS-side `compactContext` strips nulls, abbreviates keys, truncates rationales, and drops
empty arrays before sending to the AI provider.

### Context Kinds

| Kind               | Typical Question                  | Data Included                                                                                                               |
| ------------------ | --------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `daily_action`     | "What should I train today?"      | Last 2 sessions (summarized), today's nutrition schedule, latest HealthKit, latest check-in, latest measurement             |
| `plan_change`      | "I hit a plateau, review my plan" | 12-session trend aggregates, 5 proposals, 5 reconciliations, 8-week measurement delta, 7-day HealthKit trends, data quality |
| `explain_evidence` | "What data is missing?"           | Evidence freshness timestamps, data quality stats, evidence contract                                                        |
| `nutrition_focus`  | "What should I eat?"              | Today's confirmed meals, active macro targets, 7-day compliance, latest weight                                              |
| `recovery`         | "I feel sore and tired"           | Latest HealthKit (sleep/HRV/HR), latest check-in, last 3 sessions summary, training week structure                          |
| `general`          | "Hello coach"                     | 2 sessions, 2 measurements, 2 health days, plan+targets+goal, evidence codes, today's menu                                  |

### Classification Logic

The `classifyQuestion` function uses ordered regex matching: `plan_change` → `recovery` →
`explain_evidence` → `nutrition_focus` → `daily_action` → `general`. Specific domains are checked
before broader catch-all patterns.

### Compaction

The `compactContext` function in the TS provider reduces token count further by:

- Stripping `null` values recursively
- Abbreviating known keys (e.g., `prescribed_workout` → `w`, `duration_seconds` → `dur`)
- Truncating `rationale` fields to 120 characters
- Dropping empty arrays

Compaction targets 30-40% byte reduction, applied only in the Groq provider path.

## Consequences

- **Positive:** Every context kind fits under 8000 TPM with compaction headroom.
- **Positive:** Classification is fast (regex, no LLM call) and easily tunable without migrations.
- **Positive:** Backward compatible — `prepare_coach_chat_v3` wraps
  `prepare_coach_chat_v4(..., 'general')`.
- **Positive:** No new infrastructure, no vector database, no paid tier required.
- **Negative:** `classifyQuestion` is regex-based and may misclassify ambiguous questions.
- **Negative:** `plan_change` session trends omit per-exercise top loads to stay under token budget.
  Per-exercise detail remains available in the base v2 context for other kinds.

## Alternatives Considered

1. **Pay for Groq tier:** Rejected due to project budget constraints.
2. **Truncate v3 context arbitrarily:** Rejected — truncation would silently drop data without
   semantic awareness.
3. **Implement RAG:** Rejected per ARCHITECTURE.md §11 and AI_SAFETY_SPEC §15 — the evaluation gate
   has not been passed.
4. **Move classification to SQL:** Rejected — would require a migration for every classifier tuning
   iteration.

## Affected Components

- `public.prepare_coach_chat_v4()` — new SQL function with 6 context kinds
- `public.prepare_coach_chat_v3()` — now wraps v4 with `'general'` kind
- `coach-chat/index.ts` — calls `classifyQuestion()` and `prepare_coach_chat_v4`
- `coach_chat_provider.ts` — `classifyQuestion()`, `compactContext()`, applied in Groq path
- `coach_context_v4_test.sql` — pgTAP: 37 tests covering RLS, kind validation, fallback,
  idempotency, size budgets
- `coach_chat_provider_test.ts` — 15 new tests covering classification (7 domains) and compaction (8
  fixtures)
