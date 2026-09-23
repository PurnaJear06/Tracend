# Coach Chat — Bug Fixes & Coaching Persona

**Created**: 2026-07-21 **Goal**: Fix production crashes + make coach chat feel like a real coach
(GPT-level conversational quality) **Hard constraint**: Nothing breaks. Forward-compatible
migrations only. Zero Flutter contract changes.

---

## Background

Two issues block coach-chat:

1. **Phantom column bug**: `pw.target_day_of_week` and `pw.target_week_of_block` don't exist on
   `planned_workouts` (real column: `preferred_weekday`). This crashes ALL recovery-related
   questions with `422 chat_unavailable`. The bug appears in 5 applied migrations inside
   `prepare_coach_chat_v4` and `prepare_coach_chat_v5` function bodies.

2. **Mechanical coaching tone**: The system prompt is purely rule-oriented ("Be concrete and brief.
   Do not lead with generic recommendations"). No coaching persona, no rapport-building, no
   relationship memory. Users get transactional responses instead of the conversational,
   personalized coaching they expect from modern AI.

---

## Phase 1 — Bug Fixes (CRITICAL)

**Risk**: Zero. `CREATE OR REPLACE FUNCTION` only — same signatures, same return types, no column
renames or drops.

### 1.1: Fix phantom columns — new migration

| Phantom column                                            | Real / Fallback                       | Action                                                         |
| --------------------------------------------------------- | ------------------------------------- | -------------------------------------------------------------- |
| `pw.target_day_of_week`                                   | `pw.preferred_weekday` (smallint 1-7) | Replace                                                        |
| `pw.target_week_of_block`                                 | No column exists                      | Use `1` placeholder                                            |
| `ORDER BY pw.target_day_of_week, pw.target_week_of_block` | —                                     | Replace with `ORDER BY pw.preferred_weekday, pw.workout_order` |

**File**: `supabase/migrations/20260721000000_fix_coach_context_column_references.sql`

**Strategy**: `CREATE OR REPLACE FUNCTION` for both `prepare_coach_chat_v4` and
`prepare_coach_chat_v5`. Fixes all 5 affected migration bodies in one new forward-only migration.

**Break risk**: None. Same function signatures, same return types (jsonb). The fix changes only how
`training_week_structure` is populated — it currently returns `NULL` (broken), will return actual
workout schedule data (fixed).

### 1.2: Sanitize error messages to users

**File**: `supabase/functions/coach-chat/index.ts` lines 244-250

Replace raw diagnostic text leaking to users with friendly message:

- Raw SQL errors → `"Coach is unavailable right now. Your approved plan is unchanged."`
- Rate-limit → keep existing retry_after_seconds behavior
- Keep raw detail in Sentry (`captureException`) and structured logs

**Break risk**: None. Only changes the `detail` field in the error response body. Flutter already
handles this field — it just displays cleaner text.

### 1.3: Verify

```sh
./scripts/deno.sh fmt supabase/functions/coach-chat/index.ts
./scripts/deno.sh lint supabase/functions/coach-chat/
./scripts/deno.sh test supabase/functions/coach-chat/
./scripts/supabase.sh db reset
./scripts/test-db.sh
```

**Gate**: All tests pass. `./scripts/pre-deploy.sh --deno-only` passes.

---

## Phase 2 — GPT-Like Coaching Persona (HIGH)

**Risk**: Low. Single file change in `coach_chat_provider.ts`. Same JSON output schema — zero
Flutter or RPC changes. Can be rolled back instantly with
`./scripts/rollback-function.sh coach-chat`.

### 2.1: Rewrite system prompt

**File**: `supabase/functions/_shared/providers/coach_chat_provider.ts` (both Gemini and Groq paths,
lines 492-499 and 567-569)

**Replace current prompt**:

```
You are Tracend, an evidence-driven personal fitness coach. Answer the user's message first —
greet back, acknowledge feelings, address their topic — using prepared context only when relevant.
Be concrete and brief. Do not lead with generic recommendations unless asked.

Hard rules: Never invent data, symptoms, meals, or history. No diagnosis, treatment, medication,
pregnancy, or eating-disorder guidance. For ordinary illness (fever/cold/cough): recommend rest
and hydration, not completing workouts. Temporary same-day adjustments ok; persistent changes
require explicit user approval. Honor user's active_preferences (avoid declined foods/approaches).
```

**With persona-rich prompt** covering:

| Section              | Content                                                                                                                                                                                       |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Identity             | Experienced personal fitness coach who knows the athlete's journey. Evidence + empathy.                                                                                                       |
| Coaching Methodology | 7 principles: start with the person, build mental timeline, reason transparently, celebrate wins, acknowledge setbacks without judgment, personalize to preferences, offer natural follow-ups |
| Communication Style  | Warm and direct, concrete examples, short sentences, use "you/your", transparent about missing data                                                                                           |
| Hard Boundaries      | Preserved verbatim from current prompt (diagnosis, medication, pregnancy, illness rules unchanged)                                                                                            |
| Response Format      | Return ONLY JSON matching provided schema. Use reasoning_chain to show thinking.                                                                                                              |

**Preserved unchanged**:

- All safety rules (diagnosis, treatment, medication, pregnancy, eating disorders, illness guidance)
- "Temporary same-day adjustments ok; persistent changes require explicit user approval"
- "Honor user's active_preferences"
- "Never invent data, symptoms, meals, or history"
- JSON response schema (`answerSchema` constant)

### 2.2: Verify

```sh
./scripts/deno.sh fmt supabase/functions/_shared/providers/coach_chat_provider.ts
./scripts/deno.sh lint supabase/functions/_shared/
./scripts/deno.sh test supabase/functions/coach-chat/
```

**Gate**: All Deno tests pass. Prompt length stays within 40K context budget (new prompt ~800 chars
vs current ~500 chars — well within limits).

---

## Phase 3 — Context Quality (MEDIUM, deferred)

Hold until Phase 1+2 are smoke-tested on iPhone and coaching tone confirmed. Then iterate:

### 3.1: Natural-language context formatting

Replace abbreviated JSON injection with Markdown-structured summary. Add
`format_context_as_markdown(context jsonb) returns text` helper in RPC, called before model call.

**Risk**: Medium. Needs A/B evaluation. Context budget contract test must still pass.

### 3.2: Richer session summaries

Replace formulaic one-liner with topic-capturing summaries (what was discussed, decisions,
preferences stated).

**Risk**: Medium. Changes to `buildSessionSummary` affect what the model sees in `session_journal`.

---

## Layer Impact Summary

| Layer                 | Phase 1               | Phase 2                  | Phase 3                 |
| --------------------- | --------------------- | ------------------------ | ----------------------- |
| Database (migrations) | New migration         | No changes               | RPC helper (Phase 3.1)  |
| Edge Functions        | `coach-chat/index.ts` | `coach_chat_provider.ts` | Both + new helper       |
| Flutter app           | No changes            | No changes               | No changes              |
| Contract tests        | No changes            | No changes               | May need fixture update |
| RLS / Security        | Unchanged             | Unchanged                | Unchanged               |

**Zero Flutter changes across all phases.** The app continues to parse the same `CoachChatAnswerV2`
JSON schema.

---

## Deployment Order

1. Database migration (`./scripts/supabase.sh db push --linked --dry-run` first, then push)
2. Edge Function redeploy (`coach-chat`)
3. iPhone app already installed — no rebuild needed (same contract)

**Rollback**: `./scripts/rollback-function.sh coach-chat` reverts Phase 2 instantly. Migration stays
(it's additive and correct).

---

---

## Phase 1 Status — COMPLETE (deployed 2026-07-21)

- [x] 1.1: Fix phantom columns — migration `20260721000000` applied to production
- [x] 1.2: Error sanitization — reverted by owner request (raw errors preferred for testing)
- [x] 1.3: All gates passed, deployed

## Phase 2 Status — COMPLETE (deployed 2026-07-21)

- [x] 2.1: Persona-rich system prompt deployed to both Gemini and Groq paths
- [x] 2.2: All Deno tests pass

## Phase 3 Status — COMPLETE (deployed 2026-07-21)

- [x] 3.1: `formatContextAsMarkdown()` in `coach_chat_provider.ts` — Gemini gets Markdown+XML
      instead of JSON
- [x] 3.2: `buildSessionSummary` enriched with question+answer text for narrative summaries
- [x] Context budget contract test for markdown formatter (stays within 28K ceiling)

---

## Phase 4 — Provider Fixes, DeepSeek V4 Flash, Preference RLS, Tappable Follow-ups

**Created**: 2026-07-22 **Goal**: Fix Gemini free-tier errors, add cheap DeepSeek provider, fix
broken preference saving, make follow-ups tappable **Hard constraint**: Zero Flutter contract
changes. Same `CoachChatAnswerV2` JSON. $0 cost.

### 4.1 — Switch production back to Groq (CRITICAL)

**Problem**: `COACH_MODEL_PROVIDER=gemini` in production. Gemini free tier returns 503 overloads and
malformed JSON (`Unterminated string in JSON at position 2920`). Coach is completely broken.

**Fix**: Set `COACH_MODEL_PROVIDER=groq` in production secrets. Groq Qwen (`qwen/qwen3.6-27b`) is
already fully integrated, already smoke-tested, confirmed working perfectly by owner. Zero code
changes.

**File**: No file — secrets change only. **Break risk**: None. Instant rollback via
`secrets set COACH_MODEL_PROVIDER=gemini`.

### 4.2 — DeepSeek V4 Flash provider (NEW)

**Why**: $0.14/M input, $0.28/M output = **$0.00084 per chat**. $2 credit from DeepSeek console =
~2,381 requests = ~2.5 months at 30/day. OpenAI-compatible API. Better quality than Qwen 3.6 27B.
Thinking mode available for planning questions.

| What             | File                                                                         |
| ---------------- | ---------------------------------------------------------------------------- |
| New provider     | `supabase/functions/_shared/providers/deepseek_coach_model_provider.ts`      |
| Provider tests   | `supabase/functions/_shared/providers/deepseek_coach_model_provider_test.ts` |
| Factory update   | `create_coach_model_provider.ts` — add `"deepseek"` case                     |
| Chat integration | `coach_chat_provider.ts` — add deepseek branch                               |
| Type update      | `coach_model_provider.ts` — add `"deepseek"` to union                        |
| Secrets          | `DEEPSEEK_API_KEY`, `DEEPSEEK_MODEL=deepseek-v4-flash`, cost env vars        |

**API**: OpenAI-compatible at `https://api.deepseek.com/v1/chat/completions`. Copy Groq code path
structure, swap URL + auth header (`Bearer $DEEPSEEK_API_KEY`). Use Markdown context formatting
(same as Gemini path). Non-thinking for normal chat, thinking for planning questions.

**Break risk**: Low. New provider is additive. Falls back to mock if unconfigured. Groq still works
alongside it.

### 4.3 — Fix broken preference RLS (CRITICAL BUG)

**Problem**: `persist_coach_preference` RPC grants `EXECUTE` only to `service_role` (migration
`20260717110000` line 104-107). Flutter's `confirmPreference()` calls it as `authenticated` user →
silent PostgreSQL permission error. Users tap "Save preference" and nothing happens. Preference
saving has never worked.

**Fix**: New forward-only migration adding `GRANT EXECUTE TO authenticated`.

```sql
grant execute on function public.persist_coach_preference(uuid,text,text,text,text)
  to authenticated;
```

**Break risk**: None. Additive grant only. RLS on `user_preferences` table still protects cross-user
access. Function already validates `provenance` and `category` server-side via `security definer`.

**File**: `supabase/migrations/20260722000000_fix_preference_rls.sql`

### 4.4 — Make follow-ups tappable in Flutter

**Problem**: Suggested follow-up questions (`suggested_follow_ups`) render as static
`Text('• $prompt')` in coach bubble. Users must manually type each suggestion instead of tapping it.

**Fix**: Replace static `Text` with `ActionChip` wrapping `onSendFollowUp` callback. Same pattern
already used for empty-state seed prompts (line 409-417).

**File**: `lib/features/coach/coach_screen.dart` — `_MessageBubble` widget (lines 530-619).

**Break risk**: Low. Same `_send` method already supports optional string. Existing `ActionChip`
pattern already in file. No contract changes.

### 4.5 — Update ADR and cost docs

- Remove 10-day Groq expiry from ADR-0006
- New ADR for DeepSeek provider decision
- Update `COST_MODEL.md` with DeepSeek V4 Flash pricing

---

## Layer Impact Summary (Phase 4)

| Layer          | 4.1          | 4.2                           | 4.3           | 4.4                 | 4.5                  |
| -------------- | ------------ | ----------------------------- | ------------- | ------------------- | -------------------- |
| Database       | —            | —                             | New migration | —                   | —                    |
| Edge Functions | Secrets only | New provider + factory + chat | —             | —                   | —                    |
| Flutter        | —            | —                             | —             | `coach_screen.dart` | —                    |
| Docs           | —            | —                             | —             | —                   | COST_MODEL.md + ADRs |

---

## Deployment Order

1. 4.1: Switch secrets (instant, no deploy)
2. 4.3: Migration dry-run → push
3. 4.2: Deno tests → Edge Function deploy
4. 4.4: Flutter analyze + test → build
5. 4.5: Docs only — no deploy needed

---

## Completion Checklist

- [ ] 4.1: `COACH_MODEL_PROVIDER=groq` set in production
- [ ] 4.2: DeepSeek provider file + tests written, factory integrated, deno pass
- [ ] 4.3: Migration created, dry-run succeeds, pushed to production
- [ ] 4.4: Follow-ups tappable, flutter analyze + test pass
- [ ] 4.5: ADRs and COST_MODEL.md updated
- [ ] `./scripts/pre-deploy.sh --deno-only` passes
- [ ] `./scripts/pre-deploy.sh --flutter-only` passes
- [ ] No placeholder, TODO, or dead code
- [x] Coach smoke-tested on iPhone after each deploy

## Phase 4 Status — COMPLETE (deployed 2026-07-22)

- [x] 4.1: `COACH_MODEL_PROVIDER=groq` set in production (then Groq TPM 8000 bottleneck discovered)
- [x] 4.2: DeepSeek provider integrated — `deepseek_coach_model_provider.ts` + factory + chat
- [x] 4.3: Preference RLS fixed — `GRANT EXECUTE TO authenticated` pushed to production
- [x] 4.4: Follow-ups tappable — `ActionChip` in coach bubble
- [x] 4.5: ADR-0006 extended, `COST_MODEL.md` updated with DeepSeek pricing

---

## Phase 5 — DeepSeek Primary + Error Resilience + Context Intelligence

**Created**: 2026-07-22 **Goal**: Make coach-chat bulletproof — zero rate limits, correct error
handling, focused context for better coaching, multi-provider fallback **Hard constraint**: Same
`CoachChatAnswerV2` contract. Zero Flutter breaking changes. $2 credit covers 3-13 months.

### Why this plan exists

Groq free tier grants Qwen 3.6 27B only **8000 TPM** (tokens per minute). One coach-chat request
with 32K chars compact context ≈ 8K input tokens alone, plus 2K system prompt + 2K output = 12K per
request. Even one request overflows. DeepSeek V4 Flash has **no TPM limit** (only 2500 concurrency —
we use 0.02% of that), automatic context caching (50× cheaper on repeat prefixes), and a 1M context
window. It costs $0.00016/chat with cache hits — $2 credit covers 3-13 months at 30 req/day.

### 5.0 — Set DeepSeek as production (IMMEDIATE, 3 env vars)

```sh
COACH_MODEL_PROVIDER=deepseek
DEEPSEEK_API_KEY=<owner's key>
DEEPSEEK_MODEL=deepseek-v4-flash
```

Zero code changes. Already integrated and tested (94 Deno tests). Smoke-test on iPhone.

### 5.1 — Fix error propagation (7 error sites)

**Problem**: Groq and DeepSeek error sites use `throw new Error(...)` — no `status`/`body`
properties attached. The outer catch block checks `"status" in inner` which is false for plain Error
objects → `retryAfter` always `null` even when the API says "try again in 58s." Only Gemini uses
`Object.assign(new Error(...), { status, body })`.

| # | Provider | Site                        | Fix                                               |
| - | -------- | --------------------------- | ------------------------------------------------- |
| 1 | Groq     | Reasoning API non-OK (L795) | `Object.assign(new Error(...), { status, body })` |
| 2 | Groq     | Main chat non-OK (L886)     | `Object.assign(new Error(...), { status, body })` |
| 3 | DeepSeek | Chat non-OK (L1006)         | `Object.assign(new Error(...), { status, body })` |

Only HTTP failures need it. Validation errors (invalid JSON, missing content) have no status code —
fine as plain Error.

**Flutter side** (`coach_screen.dart` L208-212): The `_send` catch block currently starts cooldown
for any `CoachUnavailableException` with `retryAfterSeconds > 0`. But 429 errors from the 5.1 fix
will finally carry `retryAfterSeconds` — so the cooldown will work automatically. No Flutter change
needed.

### 5.2 — Context selection by question type

**Problem**: Current code dumps ALL 28K chars of context for every question. The coach receives
irrelevant data (meal plans for a sleep question), which pollutes answers and wastes tokens.

**Solution**: `selectRelevantContext(fullContext, contextKind)` filters context sections by
relevance. This is a QUALITY win — focused context = better model attention = better coaching
answers. Not a budget hack.

| contextKind        | Included sections                                                                                                         | DeepSeek budget |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `recovery`         | Health metrics (100%), recent workouts (50%), check-in, preferences, session journal, data quality, conversation (10 msg) | 64K chars       |
| `nutrition_focus`  | Meal plan, recent meals, nutrition targets, preferences, conversation (10 msg)                                            | 64K chars       |
| `daily_action`     | Today's workout, schedule, check-in, preferences, conversation (10 msg)                                                   | 48K chars       |
| `explain_evidence` | Measurements, trends, workout history, nutrition history, conversation (10 msg)                                           | 64K chars       |
| `plan_change`      | Everything — full context                                                                                                 | 128K chars      |
| `general`          | Plan headlines, check-in, health summary, nutrition summary, preferences, conversation (20 msg)                           | 48K chars       |

**DeepSeek-specific**: No `compactContext` — use readable field names. No `fitContextToLimit` — 128K
is 12% of 1M window. More conversation history (30 recent vs 20). More journal entries (10 vs 5).
Full-length FTS results (200 chars vs 150).

**Groq fallback path**: Keep compactContext + 4K char budget (fits 8K TPM).

### 5.3 — DeepSeek thinking mode: plan_change only

**Research finding**: DeepSeek thinking mode is ON by default. It adds 2K+ reasoning tokens billed
as output, disables temperature (no persona tuning), and has a known JSON empty-content bug. For 90%
of coaching questions, V4 Flash is strong enough without thinking.

**Rule**: Disable thinking for everything except `plan_change`:

```typescript
const useThinking = contextKind === "plan_change";
{
  temperature: useThinking ? undefined : 0.2,
  reasoning_effort: useThinking ? "high" : undefined,
  thinking: { type: useThinking ? "enabled" : "disabled" },
}
```

Thinking mode for plan_change (~1-2/week): model reasons through evidence before proposing plan
changes. Non-thinking for all else: faster, cheaper, temperature-driven persona warmth.

### 5.4 — Multi-provider fallback

Simple sequential fallback: try DeepSeek → if fails, try Groq (slashed 4K context) → if both fail,
mock with friendly message. No health tracking needed for single-user app.

### 5.5 — Verify + deploy

```sh
deno fmt + lint + test (94+ passed)
flutter analyze + test (85+ passed)
deploy coach-chat Edge Function
smoke test on iPhone
```

---

## Cost projection (DeepSeek V4 Flash)

| Scenario                                 | Cost/chat | 30/day month         |
| ---------------------------------------- | --------- | -------------------- |
| Non-thinking, full cache miss            | $0.00084  | $0.76                |
| Non-thinking, cache hit (system+context) | $0.00016  | $0.15                |
| Thinking (plan_change only, ~4/month)    | $0.0014   | $0.006               |
| **Realistic total**                      | —         | **$0.15–0.20/month** |
| **$2 credit lifespan**                   | —         | **10-13 months**     |

Cache hits are automatic: DeepSeek's disk caching persists system prompt + context structure for
hours/days. Every request after the first gets 50× cheaper input pricing.

---

## Layer Impact Summary (Phase 5)

| Layer          | 5.0     | 5.1                 | 5.2                                            | 5.3             | 5.4           | 5.5    |
| -------------- | ------- | ------------------- | ---------------------------------------------- | --------------- | ------------- | ------ |
| Database       | —       | —                   | —                                              | —               | —             | —      |
| Edge Functions | Secrets | 3 Object.assign     | selectRelevantContext + DeepSeek expanded path | Thinking toggle | Provider loop | Deploy |
| Flutter        | —       | cooldown auto-works | —                                              | —               | —             | Build  |

---

## Deployment Order

1. 5.0: Set 3 secrets (instant)
2. 5.1 + 5.2 + 5.3 + 5.4: Code changes → deno check → deploy
3. 5.5: Flutter build + iPhone install

---

## Completion Checklist

- [ ] 5.0: DeepSeek API key set, `COACH_MODEL_PROVIDER=deepseek` in production
- [ ] 5.1: 3 error sites fixed with Object.assign
- [ ] 5.2: `selectRelevantContext()` built, context budgets per kind, DeepSeek expanded path
- [ ] 5.3: Thinking mode toggled — disabled default, enabled for plan_change
- [ ] 5.4: Multi-provider sequential fallback loop
- [ ] 5.5: `deno task check` passes, edge function deployed, smoke test on iPhone
- [ ] No placeholder, TODO, or dead code
- [ ] Flutter analyze + test pass
