# Backend Handoff — FLUTTER-8 Coach Reliability

**Status:** two PRs awaiting the owner's merge, in order:
1. PR #35 `codex/coach-chat-validation-reliability`
2. A1 `claude/coach-full-context-a1`, stacked on it

**Scope:** Edge Functions, additive SQL, the live evaluation, and docs. No app code change, so no
reinstall. A2 (app) follows.

## A1 — full athlete file for every question, never a dead end

Design and research: `/Users/purnajear/.claude/plans/precious-meandering-acorn.md` (owner-approved
2026-09-27).

Root cause:
- A keyword router chose one topic, and both SQL (v4 per-kind enrichment) and Edge
  (`selectRelevantContext`) removed data the question needed. "till" matched "ill" in production.
  PR #35 would route the same question to nutrition and drop the training and weight history.
- The markdown formatter also ignored most base history: HealthKit, measurements, nutrition
  history, the weekly review and the profile.
- Formatting limits rejected whole accurate answers.
- DeepSeek failures could not be recorded.

What A1 changes:
- `prepare_coach_chat_v8` (`20260927230000_coach_chat_v8_full_athlete_context.sql`) gives every
  question the same full file: the v7 base plus `build_coach_athlete_context` (28-day training log
  with sets and volume, 7/14/28-day totals, watch workouts, 28 days of watch data with averages,
  eight weeks of weights with amendments resolved, 14 days of check-ins, 28 days of logged
  nutrition, today's meals, plan structure, proposals, reconciliations, data freshness). It has a
  90K whole-section guard that lists what it drops. v7 stays for rollback.
- The formatter renders all of it. Required truth comes first, conversation history last, and the
  question at the very end (DeepSeek prefix cache). Dropped sections are named. Long coach messages
  keep their ending, so a clarifying question survives.
- Budgets: one 96K budget for every question (plan change 128K). The classification only chooses
  thinking for explicit plan changes.
- Accuracy rules stay strict. Formatting limits become generous ceilings (reasoning 10 × 200/400,
  follow-ups 6 × 300, missing data 12 × 300, evidence 20 / label 400), while the prompt still asks
  for short items.
- The contract allows labeled estimates that show their inputs (owner decision), and one
  clarifying question with quick replies.
- `record_coach_chat_question` stores the question before the model runs and bumps
  `last_message_at`.
- `persist_failed_coach_chat_run` accepts DeepSeek and stores up to four finite rule names. The
  Edge Function now checks its result.
- Request schema 1.1 receives response 1.2: `answer_source` on every message, and on failure a
  labeled deterministic data summary (`_shared/coach_chat_fallback.ts`) stored via
  `persist_coach_chat_data_summary` instead of a 503. Request 1.0 (the installed app) is unchanged.
- Sentry events carry an `answer_source` tag.
- Live evaluation: `supabase/functions/_evals/` (about 60 prompts × 3 synthetic athletes, gates in
  AI_SAFETY_SPEC §13) and the manual `Coach Eval` workflow.

Review fixes (2026-09-28, independent review of A1):
- Conversation memory is rebuilt in v8. It holds the ten newest messages of the thread and of other
  threads, each capped at 2,000 characters keeping its ending, and never a labeled data summary.
  The plan required the exclusion; A1 had stored the `answer_source` flag without reading it.
- Pre-existing since July, fixed here:
  - v5's 40K guard kept the oldest ten of the last twenty messages, so long threads lost their
    newest turns, including the coach's clarifying question.
  - The base `prepare_coach_chat` raised `chat context too large` once the last twenty messages
    pushed its context past 18,000 characters. Every new question in that thread then failed with a
    422 before the model ran, and nothing reached Sentry.
  - `20260928040000_coach_chat_long_threads.sql` makes that guard keep fewer, newest messages first
    (20, 10, 4, none). It raises only when the context is oversized without any conversation.
- Every blocked turn is now visible. A context-preparation failure reaches Sentry, and its 422
  carries a finite `reason`: `daily_rate_limit`, `monthly_cost_limit`, `approved_plan_required`,
  `chat_context_too_large`, `thread_not_found`, and so on, or `sqlstate_<code>`. A question that
  could not be recorded and a data summary that could not be stored are captured too.

Verification:
- Deno fmt/lint clean. Deno tests: 145 passed, 7 database-dependent ignored.
- pgTAP on a fresh database in CI, because the local Colima VM would not boot on 2026-09-28: every
  migration applies; 35 files, 987 assertions; `coach_chat_v8_test.sql` has 36.
- Before and after:
  - On the pre-fix commit, test 30 fails with `died: 22023: chat context too large` (scratch
    branch, CI run 36358845827).
  - With the fix, every file passes (run 36358873313).

Owner steps:
1. Merge PR #35, then A1. There is no reinstall: the installed app sends request 1.0 and keeps
   today's behaviour, but already benefits from the full file, the relaxed formatting limits, and
   failure recording.
2. Live evaluation: on hold since 2026-09-28, because the owner cannot sign in to DeepSeek to create
   a key. Once a key exists, add the `DEEPSEEK_API_KEY` repository secret, then add the
   `coach-eval` label to the PR (or use Run workflow on `main`) and review the summary. Until then,
   A1 is verified in production with the queries below after real use on the iPhone.

See what the coach did in the last 7 days. These are read-only queries for the Supabase SQL editor:

```sql
select created_at::date as day,
  count(*) filter (where status = 'succeeded') as answered,
  count(*) filter (where status = 'failed') as failed,
  string_agg(distinct sanitized_error_code, ', ') filter (where status = 'failed') as failures
from public.model_runs
where purpose = 'coach_chat' and created_at > now() - interval '7 days'
group by 1 order by 1 desc;

select created_at, metadata->>'error_code' as code, metadata->'rules' as rules
from public.audit_events
where action_code = 'coach.chat.model_run.failed' and created_at > now() - interval '7 days'
order by created_at desc;

-- Labeled data summaries served (request 1.1 builds only, so zero until A2)
select created_at::date as day, count(*) as data_summaries
from public.coach_messages
where answer_source = 'data_summary' and created_at > now() - interval '7 days'
group by 1 order by 1 desc;

-- Threads whose last 20 messages were near or past the old 18,000-character base guard (sizes only)
with per_thread as (
  select t.id,
    (select coalesce(sum(length(jsonb_build_object('role', r.role, 'content', r.content)::text)), 0)
       from (select m.role, m.content from public.coach_messages m
             where m.thread_id = t.id order by m.created_at desc limit 20) r) as last20_chars
  from public.coach_threads t where t.status = 'active'
)
select count(*) as active_threads,
  count(*) filter (where last20_chars > 12000) as over_12k,
  count(*) filter (where last20_chars > 18000) as over_18k,
  max(last20_chars) as largest
from per_thread;
```

## PR #35 — base hardening

- Coach answer validation exposes finite internal rules and JSON paths while public failures retain
  the stable sanitized error code.
- The model-facing schema and validator share one set of limits and the request's exact evidence
  whitelist. One targeted non-thinking repair remains fail-closed.
- `prepare_coach_chat_v7` computes the coaching date fresh, renders those same scores, and derives
  chat evidence through the same helper as `prepare_daily_coaching`.
- NULL recovery emits no recovery code. Daily and chat health availability both mean a HealthKit row
  on the coaching date; stale two-day health no longer becomes current evidence.
- Required truth sections render before history and are never cut. The question is sent once.
- Classifier patterns use word boundaries and include HRV, heart rate, readiness, tired, exhausted,
  slept, and sleepless without false matches such as `will`, `interest`, or `great`.

Review follow-ups on the same branch:

- The live DeepSeek prompt had been reduced to a four-line persona. All providers now share one
  `coachChatPersona` constant (coaching approach, communication style, hard boundaries) placed
  before the null and output contracts. Its "celebrate wins" example now cites only numbers the
  context shows, consistent with the no-new-statistics rule.
- `prepare_coach_chat_v7` guards the score computation and evidence derivation like
  `get_my_daily_brief`: a scoring failure yields `computed_metrics.unavailable` and only non-score
  evidence codes instead of failing the whole chat. The migration was unapplied, so it was amended
  in place.
- `scripts/flutter.sh` clears git's hook variables (`GIT_DIR` and related). Inside the pre-push hook
  Flutter had read the Tracend repository as its own SDK checkout, reported an unknown version, and
  failed dependency resolution.

## Verification

- Deno format/lint: clean; Deno tests: 124 passed and 7 database-dependent tests ignored without a
  local database (131 with the database contract environment).
- Fresh local database reset: all migrations applied, including
  `20260927120000_coach_chat_reliability_v7.sql`.
- pgTAP: 34 files, 951 assertions; `coach_chat_v7_test.sql` has 23, including the simulated
  scoring failure.
- Flutter: 422 tests passed; analysis clean; unsigned iOS release build passed.
- Linked production migration dry-run passed and lists only the new v7 migration.
- PR CI: the seven required checks gate every push to this branch; the PR shows the latest run.

## Post-deploy acceptance

Keep FLUTTER-8 open until the nine prompts in the PR checklist pass on the owner's iPhone, quoted
numbers match Today exactly, missing metrics are called not measured, no plan activates without
approval, and any terminal failure shows finite rule names in Edge Sentry.

## Next — A2 (app, needs a reinstall), then B (calculators)

- A2:
  - Send request schema 1.1 and render the data-summary bubble with Retry and the beta diagnostic
    line.
  - Reopen the last-opened thread (`shared_preferences`).
  - Create a thread only on its first send.
  - Refresh the thread list after each reply, and hide threads with no messages.
  - Keep the raw error snackbar for real errors.
  - Add the app `SENTRY_DSN`.
  - Retry must send a new `idempotency_key`. The question is recorded under the request's key
    before the model runs, and the base function treats a known key as a replay, so reusing it
    returns the thread without a new answer.
  - Treat `answer_source` null as a model answer: `persist_coach_chat_result` does not set it; only
    data summaries carry a value.
  - A replayed request still answers with response schema 1.1 and the raw thread rows.
- B: read-only deterministic calculators the model can call (`project_weight_goal`,
  `training_summary`, `metric_stats`, `compare_periods`), so common estimates become exact.

## Recorded follow-ups — out of scope

- Add short per-request row evidence aliases (`E1…En`) mapped server-side; never expose UUIDs to the
  model.
- Replace the legacy `CHECK_IN_RECOVERY_MIXED` name for the 40–49 recovery band only through a
  coordinated whitelist/prompt migration.
- Add log-only numeric-grounding telemetry that counts answer numbers absent from context without
  logging content.
- The base context's `measurement_history` and `brief_measurements` still include amended weight
  readings. v8 renders `weight_series_8w`, which resolves amendments, and uses the base history only
  when no reading falls within eight weeks.
- Set `TRACEND_ENV=production` as an Edge secret, so Sentry's `environment` tag stops reading
  `unknown`.
- A Sentry alert on every Coach chat failure event (current alerts fire only on a new issue) is
  created once the owner approves it.
