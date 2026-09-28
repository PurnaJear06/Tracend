# Backend Handoff — FLUTTER-8 Coach Reliability

**Status:** live. Both PRs merged on 2026-09-28, in order:
1. PR #35 `codex/coach-chat-validation-reliability`
2. A1 (#36) `claude/coach-full-context-a1`

A1 has been live since 10:50 UTC. Its first deploy reported success while Supabase kept #35's code
for two coach functions (see [Deploy incident](#deploy-incident-2026-09-28)). The owner's device
check then passed, and FLUTTER-8 is resolved.

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
- DeepSeek model and prices:
  - DeepSeek retired V4 Flash on 2026-09-10. It serves V4.1 Flash as `deepseek-flash` and routes
    the legacy `deepseek-v4-flash`, which production's `DEEPSEEK_MODEL` secret uses, to it "for
    now", with no end date.
  - Four checks required the exact old name, so removing the alias would have stopped every coach
    chat. `_shared/providers/deepseek_models.ts` now accepts both names and nothing else.
  - The cost defaults move from the retired 0.14/0.28 to V4.1 Flash peak prices (0.30/1.20 USD
    per 1M). Production sets no DeepSeek cost secret, so this takes effect on deploy.
- Live evaluation:
  - A run makes 17 calls unless `max_calls` or `EVAL_MAX_CALLS` asks for another number: every
    safety prompt, then one prompt from each other category.
  - It can go through an OpenAI-compatible router: repository variable `EVAL_BASE_URL`, secret
    `EVAL_API_KEY`, optional variable `EVAL_MODEL`. NaraRouter (`https://router.bynara.id/v1`)
    lists `deepseek-v4-flash` at a fraction of DeepSeek's price and does not name its upstream.
    Treat its results as a smoke test, not as DeepSeek's production behaviour or latency.

Second review fixes (2026-09-28, PR review of #35 and A1):
- The data summary is safe for any question. It does not answer the question, so a purging, injury
  or fainting message that timed out would have received training and calorie numbers.
  - A broad deterministic screen (`mayConcernHealthRisk`, grouped by the safety spec's red flags and
    unsupported populations) now swaps the numbers for a safety referral: `safety_state: "limited"`,
    no data, and a pointer to a doctor, physiotherapist or dietitian, or emergency services.
  - A false alarm only replaces the numbers with the referral. Every other summary ends with the
    same referral in one line, because no word list catches every phrasing.
  - The narrow pre-model boundary is unchanged, so the model still answers ordinary soreness
    questions.
- A scoring failure no longer blocks the first chat of the day.
  - The base preparation creates the day's snapshot through `prepare_daily_coaching`, which
    computed scores without v7's guard.
  - `20260928120000_daily_coaching_scoring_guard.sql` adds the guard. The snapshot is stored with
    `scores_unavailable`, and evidence keeps only non-score codes, for chat and coach-decide alike.
  - `daily_coaching_scoring_guard_test.sql` covers a day with no snapshot. PR #35's test created
    one first, so it missed this path.
- A retried request (same idempotency key) reports what its first attempt produced.
  - A saved question is no longer proof of a reply, because the question is saved when the turn
    starts.
  - `coach_chat_turn` finds the stored answer or data summary, the failure code, or neither.
  - The Edge Function returns the answer as `message` (the list `messages` stays), the original 503
    code, or 409 `request_in_progress`. It never runs the model twice for one key.
- Watch averages carry a day count per metric (`days_with_sleep`, `days_with_resting_heart_rate`,
  `days_with_hrv`, `days_with_steps`). A week of steps with one measured night is now one night of
  sleep evidence in the prompt and the summary, not "7 days synced".
- The cheap evaluation always runs all six safety prompts. The three the pre-model boundary does not
  catch (fainting, purging, injury) had been sampled away. A data summary served for a safety
  prompt now passes only if it is the referral.
- Unchanged by design: the installed app (request 1.0) still gets the 503 when the model fails,
  so the beta keeps showing the raw failure code. A2 switches to request 1.1 and renders the labeled
  reply.

Verification:
- Deno fmt/lint clean. Deno tests: 157 passed, 7 database-dependent ignored.
- pgTAP on a fresh database in CI, because the local Colima VM would not boot on 2026-09-28: every
  migration applies; `coach_chat_v8_test.sql` has 45 assertions and
  `daily_coaching_scoring_guard_test.sql` 7.
- Before and after, for the long-thread fix:
  - On the pre-fix commit, test 30 fails with `died: 22023: chat context too large` (scratch
    branch, CI run 36358845827).
  - With the fix, every file passes (run 36358873313).

Owner steps:
1. Done: PR #35 and A1 merged. There was no reinstall: the installed app sends request 1.0 and keeps
   its behaviour, but already benefits from the full file, the relaxed formatting limits, and
   failure recording.
2. Switch the Edge secret `DEEPSEEK_MODEL` from `deepseek-v4-flash` to `deepseek-flash`. A1's code
   accepts both and is confirmed live, so this is safe now. A secret change creates a new version of
   every function, so afterwards confirm in `supabase functions list` that no function's
   `UPDATED_AT` moved back.
3. Live evaluation:
   - The NaraRouter smoke run on 2026-09-28 (run 36384822050) found no dead ends and no unpermitted
     evidence. The router was too slow to measure pass rates: 9 of 12 calls timed out.
   - The DeepSeek regression run is still owed. With a DeepSeek key, add `DEEPSEEK_API_KEY`, delete
     `EVAL_BASE_URL`, and run the `Coach Eval` workflow.

The queries below measure A1 in production after real use on the iPhone.

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

## Deploy incident (2026-09-28)

- The A1 deploy (run 36392439194) reported success for all nine functions at 07:43 UTC. Supabase
  still kept the previous version of `coach-chat`, `coach-decide`, `health-check` and
  `privacy-export`.
  - Their `UPDATED_AT` stayed at the 07:22 deploy of #35.
  - The live `coach-chat` source, downloaded later, was byte-identical to #35.
- #35's code accepts only `deepseek-v4-flash`. Switching `DEEPSEEK_MODEL` to `deepseek-flash` at
  07:44 therefore turned the live provider off:
  - Every chat failed with `provider_http_error` (FLUTTER-9: provider `mock`, model
    `provider_not_configured`).
  - `coach-decide` returned 503 `coach_provider_model_not_approved`.
- Recovery: the owner restored `deepseek-v4-flash`, which both versions accept, and ran `hotfix.yml`
  (run 36411972320). `coach-chat` and `coach-decide` have run A1's code since 10:50 UTC.
  - That run dropped `health-sync`, which already ran the same code.
  - Its tag step failed because `hotfix.yml` could not push tags.
- A secret change creates a new version of every function: all nine versions rose by one, while
  `UPDATED_AT` stayed the same.
  - It is not proven whether the 07:44 secret change or the parallel deploys rolled the four
    functions back.
  - The hotfix run shows that parallel deploys alone can drop a function.
- Prevention in the A1 close-out PR (details in `docs/CI_CD_DEPLOYMENT.md`):
  - Functions deploy one at a time.
  - `scripts/verify-live-function.sh` confirms each one is live and redeploys it once if not.
  - A final job checks all of them before tagging.
  - `hotfix.yml` can push its tag.

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

After the 10:50 UTC redeploy on 2026-09-28, the owner's iPhone got answers to their questions and
Sentry recorded no errors. FLUTTER-8 and FLUTTER-9 are resolved; either reopens as regressed on a
new event.

The owner has not yet worked through the full checklist item by item, so keep checking it during
normal use:
- the nine prompts in the PR checklist;
- quoted numbers match Today exactly;
- missing metrics are called not measured;
- no plan activates without approval;
- any terminal failure shows finite rule names in Edge Sentry.

## Next — A2 (app, needs a reinstall), then B (calculators)

- A2:
  - Send request schema 1.1 and render the data-summary bubble with Retry and the beta diagnostic
    line. A summary with `safety_state: "limited"` is the safety referral, so show no data styling.
  - Reopen the last-opened thread (`shared_preferences`).
  - Create a thread only on its first send.
  - Refresh the thread list after each reply, and hide threads with no messages.
  - Keep the raw error snackbar for real errors.
  - Add the app `SENTRY_DSN`.
  - Retry after a failure must send a new `idempotency_key`. Reusing a key returns the first
    attempt's outcome: its answer as `message`, its 503 code, or 409 `request_in_progress`.
  - Treat `answer_source` null as a model answer: `persist_coach_chat_result` does not set it; only
    data summaries carry a value.
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
