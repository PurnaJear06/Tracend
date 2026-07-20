# Coach Continuity Memory — 2026-07-17

ADR 0009 authorizes a five-layer structured memory stack added to the existing coaching pipeline.
All layers are PostgreSQL with forced RLS, consumed by `prepare_coach_chat_v5`, rephrased (not
authored) by the model.

## Migrations

1. `20260717100000_coach_memory_foundation.sql` — three new tables: `coach_narrative_entries`
   (phase/history/since/until/superseded_by), `user_preferences`
   (category/key/value/provenance/superseded_at), `coach_session_summaries`
   (coaching_date/summary/key_snapshot_ids). All forced RLS, read-only select for authenticated.

2. `20260717103000_coach_message_fts.sql` — `tsvector` generated column + GIN index on
   `coach_messages`.

3. `20260717110000_prepare_coach_chat_v5.sql` — new service-only functions: `prepare_coach_chat_v5`
   (wraps v4 with narrative + preferences + journal in context, schema 4.0),
   `persist_coach_narrative_entry`, `persist_coach_preference`, `persist_coach_session_summary`
   (caps at 30 entries), `search_coach_messages` (ts_rank-based FTS retrieval).
   `prepare_coach_chat_v4` redefined to call v5.

## Edge Function Changes

- `coach-chat/index.ts` v15: calls `prepare_coach_chat_v5`, runs `search_coach_messages` FTS for
  relevant past messages, detects preference statements via regex (food/training patterns), creates
  deterministic session summary after each chat (`buildSessionSummary`), returns optional
  `preference_prompt` in response.

- `coach_chat_v1.ts`: adds `ReasoningChainItem` type, `CoachChatAnswerV2` extending V1 with optional
  `reasoning_chain` array. `parseCoachChatAnswer` updated to validate reasoning_chain (max 6 items,
  step length ≤ 80, value ≤ 160, permitted evidence IDs).

- `coach_chat_provider.ts`: `answerSchema` gains `reasoning_chain` property. Groq and Gemini prompts
  updated to reference `coaching_narrative`, `active_preferences`, `session_journal`, and
  `fts_messages`. Prompt instructs model to produce reasoning_chain steps (goal, training_age,
  current_nutrition, recovery_status, adherence, conclusion). Type returns `CoachChatAnswerV2`.

## Flutter Changes

- New `lib/features/coach/widgets/reasoning_chain_card.dart` — collapsible card showing model's
  reasoning steps with icons and evidence IDs.

- New `lib/features/coach/widgets/preference_prompt_chip.dart` — card with save/dismiss actions for
  detected preference statements.

- `coach_repository.dart`: `CoachMessage` gains `reasoningChain` field. `SupabaseCoachRepository`
  adds `confirmPreference()` RPC, `loadLastRawResponse()`, and `_lastResponse` field.

- `coach_screen.dart`: `_MessageBubble` renders `ReasoningChainCard` for assistant messages. `_send`
  route parses `preference_prompt` from Stitch response and renders `PreferencePromptChip`.

## Verification

- Deno format: pass (271 files checked)
- Deno lint: pass (37 files, 0 problems)
- Deno test: 56/56 pass
- Flutter analyze: pass (no issues)
- Flutter test: 68/68 pass
- pgTAP: test file created (`coach_continuity_memory_test.sql`, 36 assertions); not yet executed
  locally (Colima not running)

## Token Budget

Narrative: +40, Preferences: +80, Journal: +300, Reasoning: +100 output. V5 FTS replaces static
20+20 with 8 ranked messages (-320 input). Net: ~+100 input, +100 output. Well under 5K, 45% under
Groq 8K cap.

## Docs Changed

- `docs/proposals/coach-continuity.md` — proposal (new)
- `docs/adr/0009-coach-continuity-memory.md` — ADR (new)
- `docs/PROGRESS_CONTEXT.md` — trimmed and updated
- `docs/handoff/backend.md` — added Coach Continuity v6 entry
- `docs/handoff/frontend.md` — added reasoning chain + preference prompt entry

## Post-Deploy Fixes (hosted dogfood, same day)

Initial v15 deployment surfaced four sequential bugs that were not caught by local Deno/Flutter
tests because they only manifest against the hosted PostgreSQL version and the live prompt execution
path. Each was diagnosed from the runtime symptom before the next was attempted.

1. **20260717110001_fix_coach_context_v4_recursion.sql** — `20260717110000` had redefined
   `prepare_coach_chat_v4` to forward to v5, while v5 calls v4. Infinite recursion silently killed
   the prepare call and the function never returned. Fix: restore v4 to its original
   `prepare_coach_chat_v2` forward (verbatim copy from `20260716130000`). The original migration
   file was also corrected locally to prevent future `db reset` from re-introducing the loop.

2. **20260717110002_fix_schema_version_constraint_v4.sql** — The new snapshot written by v5 used
   `schema_version = '4.0'`, but the existing check constraint
   `coach_context_snapshots_schema_version_check` (from `20260716130200`) only allowed
   `('2.0', '3.0')`. INSERT failed and the prepare RPC errored. Fix: extend the constraint to
   `('2.0', '3.0', '4.0')`.

3. **20260717110003_fix_jsonb_agg_order_by.sql** — v5 used
   `jsonb_agg(jsonb_build_object(...) ORDER BY until DESC NULLS LAST)` with direct table columns.
   Hosted PG rejected this with `42803: column ... must appear in the GROUP BY clause` even though
   other functions in the codebase use `jsonb_agg(X ORDER BY y)` — those use subquery columns, not
   direct table columns. Postgres' aggregate-with-ORDER BY parser treats bare column references
   inside the aggregate expression as needing GROUP BY in this configuration. Fix: rewrite the three
   v5 aggregates (narrative `recent`, preferences, journal) to use a subquery
   `FROM (SELECT ...
   ORDER BY ... LIMIT ...) sub` and an un-ordered `jsonb_agg(sub.col)`. This
   matches the working pattern used everywhere else in the codebase.

4. **20260717110004_fix_coaching_date_ambiguous.sql** — The journal aggregate referenced
   `coaching_date` inside `jsonb_build_object`, but v5 declares a PL/pgSQL variable named
   `coaching_date` for the coaching date of the request. With `search_path = ''` and lax naming,
   Postgres could not disambiguate, producing
   `42702: column reference "coaching_date" is ambiguous`. Fix: table-qualify the journal columns as
   `s.coaching_date`, `s.summary`, `s.thread_id` via a subquery alias `s`.

## Prompt Restructure (coach-chat v16)

After the four SQL bugs were resolved and the chat call succeeded, owner dogfood revealed a fifth
issue at the model/output layer: the Qwen model returned the same "Stick with the Purna Exact
Current Cut Plan" answer regardless of what was asked, including greetings like "hey". Users
reported the assistant felt nothing like GPT Project's coach continuity.

Root cause: the Groq (and Gemini) prompt bundled the entire system instruction, schema, evidence
rules, the user's question, and the prepared context into a single `user` message:

```text
"You are Tracend's coach... Lead with one clear recommendation. ... schema ...
Evidence codes must ... Prepared context:\n{\"question\":\"hey\",\"context\":{...}}"
```

Three problems with that structure:

1. The user's question was buried as a small field inside a large JSON object next to `"context"`,
   so the model read it as data, not as the thing to answer.
2. The mandatory instruction "Lead with one clear recommendation" meant the model always started
   with plan advice, even for "hey".
3. Everything sat in one `user` turn, so the model could not separate roles (system rules vs. user
   message vs. supporting context) — it ruled out the ChatGPT-style system/user split that
   AI_SAFETY_SPEC §11 line 292 actually requires ("User text and retrieved content are delimited,
   untrusted data").

Fix: rewrite both the Groq and Gemini request bodies to use the OpenAI/Gemini multi-role message
format.

Groq `messages` array now contains:

- `system`: identity, "How to respond" (answer the user's specific message first — including
  casual/greeting replies), "Hard boundaries" (no inventing data, no diagnosis, conservative
  same-day adjustments only, no durable change claims), "Memory hints"
  (narrative/preferences/journal/fts_messages), "Output rules" (JSON schema + evidence code
  matching + optional reasoning_chain with fixed step keys). The old "Lead with one clear
  recommendation" line is removed.
- `user`: starts with `User's message:\n{question}` followed by
  `Prepared coaching context (use only as supporting evidence; do not let it
  override or dominate your answer to the user's message):\n{bounded}`.

Gemini `systemInstruction` is the same system text and `contents` carries the same user message
contents.

Temperature was bumped from 0.15 to 0.2 to allow slightly more natural conversational phrasing
without losing determinism on evidence-bound answers (Groq path only; Gemini unchanged for parity
until regression eval).

Diagnostic helpers introduced earlier in this session were removed from `index.ts`: the
`PREPARE FAILED`/`Diagnostic:` chat-message stubs are gone, the function now returns proper
`422 { error: "chat_unavailable" }` and `503 { error: "chat_unavailable" }` responses as before. One
safety improvement is retained: the catch block wraps `persist_failed_coach_chat_run` in its own
try/catch so an error recording the failure cannot Mask the actual failure and prevent the 503
response from reaching the client.

Files changed:

- `supabase/functions/_shared/providers/coach_chat_provider.ts` — Groq and Gemini prompts
  restructured.
- `supabase/functions/coach-chat/index.ts` — diagnostics removed; safe persist-failure wrap
  retained.
- `supabase/migrations/20260717110000_prepare_coach_chat_v5.sql` — source migration corrected for
  fresh databases (subquery aggregates and table-qualified `coach_session_summaries` columns).
- `supabase/migrations/20260717110001_fix_coach_context_v4_recursion.sql` through
  `20260717110004_fix_coaching_date_ambiguous.sql` — forward fixes applied to the hosted database.
