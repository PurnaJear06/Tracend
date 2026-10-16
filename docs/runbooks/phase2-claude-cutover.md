# Phase 2 cutover: DeepSeek and Groq to Claude

Moves Tracend's AI features to Anthropic's Claude models with settings only. Written by chunk A7.
Program: [`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md)
(D1, D11). Design: [`AI_SAFETY_SPEC.md`](../AI_SAFETY_SPEC.md) §10.5-§10.7.

**Who runs it.** Every step marked **(OWNER)** changes production (a merge, a notice, a secret) and is
the owner's. An agent may prepare and verify, never publish or set. Replace nothing in the commands:
the project is `qsfzzsjenopqqqhvpyaw`, and the wrapper is `./scripts/supabase.sh` (never the bare
`supabase`). Run from a checkout of the merged `main` commit.

**Safety properties to keep in mind.**
- Merging and deploying changes nothing for athletes: with no `AI_<FEATURE>_*` settings every
  feature runs today's DeepSeek or Groq path unchanged.
- A route sends nothing to an athlete's vendor unless that athlete accepted a notice naming it.
- The active plan, manual logging and the deterministic fallbacks work throughout; no step needs
  downtime.
- Every secret change creates a new version of every Edge Function. After each one, run
  `./scripts/verify-live-function.sh --all` and wait for it to pass before the next change.
- Never type a key into a command. Load it from `.env` into a shell variable (step 5.0).

## What moves

| Feature | `AI_<FEATURE>_*` prefix | Model id | `MAX_OUTPUT_TOKENS` | `TIMEOUT_MS` | At this cutover |
| --- | --- | --- | ---: | ---: | --- |
| Coach chat | `AI_COACH_CHAT_` | `claude-haiku-5-5` | 4096 | 30000 | yes |
| Daily decision | `AI_DAILY_DECISION_` | `claude-sonnet-5-5` | 1800 | 25000 | yes |
| Meal photo | `AI_MEAL_VISION_` | `claude-haiku-5-5` | 1500 | 30000 | yes |
| Physique check | `AI_PHYSIQUE_VISION_` | `claude-sonnet-5-5` | 800 | 60000 | yes, after the owner's real-photo check |
| Onboarding plan | `AI_ONBOARDING_PLAN_` | `claude-sonnet-5-5` | 8000 | 90000 | **no, later, after B2** |
| Onboarding questions | `AI_ONBOARDING_QUESTIONS_` | `claude-sonnet-5-5` | 1500 | 30000 | **no, later, after B2** |

Every route also sets `<prefix>PROVIDER=anthropic` and `<prefix>EVALUATED=true`. `THINKING` and
`EFFORT` stay unset (thinking off, the model's default effort). A route needs `ANTHROPIC_API_KEY`.

Budget (owner decision 2026-10-16): USD 3 per athlete a month, 30 requests a day, USD 50 across all
accounts. Migration code 17 sets them when it deploys.

## 1. Merge A3-A7 (OWNER)

Merge in the program's order: P2, B1, A3, A5, A6, D1, A4, C2, A7 (each PR's required checks green;
agents do not merge). Merging to `main` deploys automatically (`deploy.yml`: migrate, then functions
one at a time, then verify all live).

Verify:
- The deploy run is green, then from the merged commit:
  `./scripts/verify-live-function.sh --all` prints that every function matches.
- Migration code 17 applied. In the SQL editor:
  `select per_person_monthly_usd, global_monthly_usd from private.ai_budget_limits;`
  expects `3.00` and `50.00`.
- **Confirm the USD 50 global stop.** The owner said "that is fine" but it was to be confirmed at
  cutover. To change it: `update private.ai_budget_limits set global_monthly_usd = <n>, updated_at
  = now();`
- Production still runs DeepSeek and Groq: Supabase dashboard > Edge Functions > Logs shows no
  `ai_call` lines yet (the gateway logs only when a route is used).

## 2. Install the new app build (OWNER)

The D11 wording ships in the app (AI answers read "AI answer · checked by Tracend"; no screen names a
model or company outside a consent notice). From the merged `main` commit:
`./scripts/install-device.sh` (it checks the bundle with `scripts/verify-app-bundle.sh`). Older
builds keep working: they show the server notice's company name on two cards, and nothing else
changes. Do this before step 4 so athletes re-accept in the new build.

## 3. Publish the notices (OWNER)

Drafts: [`docs/notices/ai-coaching-v6.md`](../notices/ai-coaching-v6.md),
[`meal-photo-ai-v2.md`](../notices/meal-photo-ai-v2.md),
[`progress-photo-ai-v2.md`](../notices/progress-photo-ai-v2.md). Each holds the full SQL call
(`private.publish_ai_notice`, `private.publish_meal_photo_ai_notice`,
`private.publish_photo_ai_notice`, all five arguments: version, provider `anthropic`, label
`Anthropic`, purposes or model, body).

1. **Edit the text if you want to, then re-read Anthropic's published retention policy**
   (privacy.claude.com, "How long do you store my organization's data?"). The drafts say: deleted
   within 30 days, not used for training, kept longer only where the law requires or to enforce its
   usage rules. If the policy changed, change the text first. Keep the app's built-in fallback in
   step: `AiNotice.builtIn` must equal the v6 body (`test/ai_coaching_consent_test.dart` checks it
   against the draft), so a text change to v6 needs the same change in
   `lib/features/consent/ai_coaching_consent.dart` and a new app build.
2. **Mind the gap.** The moment `ai-coaching-v6` is current, an athlete who accepts it is still
   served by the old DeepSeek path until step 5 sets the Coach and daily decision routes, because
   the old path checks that the current notice is granted but not whom it names. Keep the gap to
   minutes: do steps 3, 4 and 5.1-5.2 in one sitting. If any athlete other than you is active, close
   the gap instead: first `./scripts/supabase.sh secrets set COACH_AI_ENABLED=false --project-ref
   qsfzzsjenopqqqhvpyaw` (Coach and daily decision then show their no-AI fallbacks), verify live,
   and set it back to `true` in the same command as step 5.1's settings. Meal photos need no pause:
   the old path refuses (503 `meal_photo_notice_outdated`) while the current meal photo notice names
   another company.
3. Run each draft's SQL in the Supabase SQL editor (production). Then run its "Check after
   publishing" query. The label check refuses a wrong label (22023); nothing is half-published.

Verify: `select public.get_ai_consent_v2('<your user id>', 'coach_chat');` shows `provider`
`anthropic` and `notice_version` `ai-coaching-v6`, with `granted` false until you accept (same for
`'daily_decision'`, `'meal_vision'`, `'physique_vision'`).

## 4. Athletes re-accept the notices in the app (OWNER, then each athlete)

A new notice version asks every athlete again; a grant of an older version no longer counts.
1. Open the new build. The AI coaching question appears: read the Anthropic notice, choose **Allow
   AI coaching**. Then accept the meal photo notice (Log a meal) and the progress photo notice
   (Progress > physique check) when each is offered.
2. Other athletes accept the same way the next time they open the app. Until they do, the new
   routes send them nothing and they see "AI coaching is off" with a **Review AI coaching** button
   (the deterministic plan and logging keep working).

Verify, in the SQL editor:
```sql
select distinct on (user_id) user_id, consent_type, action, notice_version, created_at
from public.consent_records
where consent_type in ('ai_coaching', 'meal_photo_ai', 'progress_photo_ai')
order by user_id, consent_type, created_at desc;
```
The owner's rows show `granted` with `ai-coaching-v6`, `meal-photo-ai-v2` and `progress-photo-ai-v2`.
Do not set a route (step 5) for a feature whose notice you have not accepted yourself: you could not
test it.

## 5. Set the routes, one feature at a time (OWNER)

Order: Coach chat, daily decision, meal photo, physique check. After **each** feature: run the verify
list, use the feature, and check the log. Stop and roll back (section 7) at the first problem.

**5.0 Load the key (once).** Never print it. `.env` holds `ANTHROPIC_API_KEY`:
```sh
set -a; . ./.env; set +a
./scripts/supabase.sh secrets set ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
Also set a monthly spend limit on the Anthropic console workspace as a backstop to the in-app stops.

**5.1 Coach chat.**
```sh
./scripts/supabase.sh secrets set \
  AI_COACH_CHAT_PROVIDER=anthropic AI_COACH_CHAT_MODEL=claude-haiku-5-5 \
  AI_COACH_CHAT_MAX_OUTPUT_TOKENS=4096 AI_COACH_CHAT_TIMEOUT_MS=30000 \
  AI_COACH_CHAT_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
Use: ask the Coach one question, then the same question again. Check the log (below): the second
`ai_call` for `coach_chat` has `cache_read_tokens` above zero. The reply is labelled "AI answer ·
checked by Tracend".

**5.2 Daily decision.**
```sh
./scripts/supabase.sh secrets set \
  AI_DAILY_DECISION_PROVIDER=anthropic AI_DAILY_DECISION_MODEL=claude-sonnet-5-5 \
  AI_DAILY_DECISION_MAX_OUTPUT_TOKENS=1800 AI_DAILY_DECISION_TIMEOUT_MS=25000 \
  AI_DAILY_DECISION_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
Use: generate today's decision. It must pass the existing validator (a forbidden or ungrounded
answer falls back to the deterministic decision and records a failed run).

**5.3 Meal photo.** `MEAL_VISION_ENABLED` stays `true`. This is also the **real-photo check** the
spec requires before `EVALUATED` (AI_SAFETY_SPEC §8): the synthetic drawings used in the evals test
the contract and refusals, not recognition of real food. Nothing is logged until the athlete
confirms the foods, so the check costs no wrong data.
```sh
./scripts/supabase.sh secrets set \
  AI_MEAL_VISION_PROVIDER=anthropic AI_MEAL_VISION_MODEL=claude-haiku-5-5 \
  AI_MEAL_VISION_MAX_OUTPUT_TOKENS=1500 AI_MEAL_VISION_TIMEOUT_MS=30000 \
  AI_MEAL_VISION_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
Use: photograph about ten of your own typical meals, including a mixed home dish. Foods named,
portions sensible, no invented items, and "no food" for a non-meal photo. If it is poor, unset the
five settings (section 7) and report it.

**5.4 Physique check (only after the owner's real-photo check).** The route refuses with 403
`physique_vision_not_evaluated` until `EVALUATED=true`, and only the ids in
`PHYSIQUE_VISION_ALLOWED_USERS` (you) can run it, so setting it exposes nothing else. The check is
your own set of photos: the result must be sensible muscles to develop, no body-fat figure, no score,
and no judgement of appearance.
```sh
./scripts/supabase.sh secrets set \
  AI_PHYSIQUE_VISION_PROVIDER=anthropic AI_PHYSIQUE_VISION_MODEL=claude-sonnet-5-5 \
  AI_PHYSIQUE_VISION_MAX_OUTPUT_TOKENS=800 AI_PHYSIQUE_VISION_TIMEOUT_MS=60000 \
  AI_PHYSIQUE_VISION_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
Do not add another account to the allowlist; that needs the separate evaluation in
AI_SAFETY_SPEC §9.

**Verify after each feature.**
- `./scripts/verify-live-function.sh --all` passes.
- The `ai_call` log (Supabase dashboard > Logs > Logs Explorer):
  ```sql
  select timestamp, event_message from function_logs
  where event_message like '%ai_call%' order by timestamp desc limit 50
  ```
  Each line shows `feature`, `vendor` `anthropic`, the model, `outcome` `ok`, token counts,
  `cost_usd` and `latency_ms`. A line with another outcome (`consent_provider_mismatch`,
  `rate_limited`, `invalid_output`, `refused`, `timeout`) names the problem. No prompt, image or
  reply text is ever in a line.
- The stored provenance (what the feature wrote):
  ```sql
  select purpose, provider, model, count(*), sum(estimated_cost_usd)
  from public.model_runs where created_at > now() - interval '1 day' group by 1, 2, 3;
  select purpose, provider, model, count(*), sum(estimated_cost_usd)
  from public.ai_usage_events where created_at > now() - interval '1 day' group by 1, 2, 3;
  ```
  Rows for the moved feature show `anthropic` and the model id.
- The budget is counting: the Account AI usage row shows the month's spend against USD 3.

## 6. Verify the whole cutover (OWNER)

- `./scripts/verify-live-function.sh --all` from the deployed commit.
- Each moved feature has a recent `ai_call` line with `vendor` `anthropic` and `outcome` `ok`, and
  its newest `model_runs` or `ai_usage_events` rows say `anthropic` (step 5's queries).
- Use the app as an athlete would: Coach question, today's decision, a meal photo, a physique check.
  No screen names a model or company except the consent notices.
- Onboarding is still on DeepSeek (below). Until it moves, DeepSeek still receives onboarding
  answers and Apple Health summaries, so **the external TestFlight group does not open yet**
  (beta exit criterion, plan decisions log 2026-10-15).

## Later: onboarding, after B2 (OWNER)

Not part of this cutover. A4's eval passes the 90% bar on only about half of the runs; the failures
are weekly-volume rules that chunk B2 fixes. After B2 merges, re-run the onboarding eval
(`supabase/functions/_evals/onboarding_plan_eval.ts`, `EVAL_PROVIDER=anthropic`, at most USD 2) until
it passes the bar on repeated runs, then set both routes (the coaching notice v6 already covers the
`onboarding_plan` purpose; no new notice):
```sh
./scripts/supabase.sh secrets set \
  AI_ONBOARDING_PLAN_PROVIDER=anthropic AI_ONBOARDING_PLAN_MODEL=claude-sonnet-5-5 \
  AI_ONBOARDING_PLAN_MAX_OUTPUT_TOKENS=8000 AI_ONBOARDING_PLAN_TIMEOUT_MS=90000 \
  AI_ONBOARDING_PLAN_EVALUATED=true \
  AI_ONBOARDING_QUESTIONS_PROVIDER=anthropic AI_ONBOARDING_QUESTIONS_MODEL=claude-sonnet-5-5 \
  AI_ONBOARDING_QUESTIONS_MAX_OUTPUT_TOKENS=1500 AI_ONBOARDING_QUESTIONS_TIMEOUT_MS=30000 \
  AI_ONBOARDING_QUESTIONS_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
Verify as in step 5 (`feature` `onboarding_plan` and `onboarding_questions`), with a new test
account's onboarding. Onboarding's own 2-week rollback window starts then.

## 7. Rollback by settings (OWNER), for 2 weeks after each feature moves (D1)

DeepSeek and Groq keys and the old `COACH_*`, `ONBOARDING_PLAN_*`, `MEAL_VISION_*` and
`PHYSIQUE_VISION_*` settings stay in place for the whole window. Do not remove them early.

To roll one feature back, unset its provider (a route without a provider is no route):
```sh
./scripts/supabase.sh secrets unset AI_COACH_CHAT_PROVIDER --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
(`AI_DAILY_DECISION_PROVIDER`, `AI_MEAL_VISION_PROVIDER`, `AI_PHYSIQUE_VISION_PROVIDER`, and for
onboarding both `AI_ONBOARDING_*_PROVIDER`.) Unset the other `AI_<FEATURE>_*` settings of that
feature too when tidying up. If you paused with `COACH_AI_ENABLED=false` in step 3, set it back to
`true`.

**Then fix consent.** The old path reads only that the current notice is granted, not whom it
names, so after a rollback the notice text must name the company that really receives the data:
republish the old text under a new version, which asks everyone again.
- Coaching: `private.publish_ai_notice('ai-coaching-v7', 'deepseek', 'DeepSeek', array['coach_chat',
  'daily_coaching','onboarding_plan'], <the ai-coaching-v5 body>)`. The v5 text is in
  `supabase/migrations/20261009160100_meal_photo_ai_notice.sql`.
- Meal photo: `private.publish_meal_photo_ai_notice('meal-photo-ai-v3', 'groq', 'Groq',
  'qwen/qwen3.8-27b', <the v1 body>)` (text in the same migration); without it the old path
  answers `meal_photo_notice_outdated`.
- Physique: `private.publish_photo_ai_notice('progress-photo-ai-v3', 'groq', 'Groq',
  'qwen/qwen3.8-27b', <the v1 body>)` (text in `20261002150000_physique_check.sql`).

Rolling back is cheap but visible to athletes (they are asked to accept again), so roll back for a
real problem, not for one slow answer. Anthropic being briefly down needs no rollback: the Coach
shows its labelled data summary and the daily decision its deterministic fallback.

## 8. After the window (OWNER)

Two weeks after a feature moved with no rollback:
1. Remove its old settings and keys (`./scripts/supabase.sh secrets unset ...`), then
   `./scripts/verify-live-function.sh --all`. Groq's keys go two weeks after meal photos and the
   physique check moved. DeepSeek's key goes two weeks after **onboarding** moved (not before: it is
   the last feature on DeepSeek).
2. **Drop the processors from the privacy policy.** Remove Groq from the website's AI processor list
   after the Groq features' window, and DeepSeek after the onboarding window. Update
   `docs/SECURITY_PRIVACY.md` §6 (processor table) and `docs/AI_SAFETY_SPEC.md` §10.2 in the same
   change, and the website privacy page (chunk W1 owns the site files).
3. A cleanup change may then delete the DeepSeek, Groq and Gemini adapters and the old `COACH_*`
   gates. That is a code change for a later chunk, not a setting.
4. Open the external TestFlight group only when no feature still sends health data to DeepSeek.

## Reference: what each step relies on

| Step | Relies on |
| --- | --- |
| Routes only when `EVALUATED=true` | `_shared/ai/routes.ts`; Coach chat, daily decision and onboarding treat an unevaluated route as no route; physique answers `physique_vision_not_evaluated` |
| Vendor-checked consent | `get_ai_consent_v2`, `AiRequest.consentVendor`, migration `20261015120011_provider_neutral_ai.sql` |
| Budget | `reserve_ai_budget_v2`, `private.ai_budget_limits`, migration `20261016004017_ai_budget_phase2.sql` |
| Handoffs with each feature's own settings and tests | `docs/handoff/ai-gateway.md` |
