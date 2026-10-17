# Phase 2 cutover: DeepSeek and Groq to Claude

Moves Tracend's AI features to Anthropic's Claude models with settings only. Written by chunk A7.
Program: [`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md)
(D1, D11). Design: [`AI_SAFETY_SPEC.md`](../AI_SAFETY_SPEC.md) §10.5-§10.7.

**Who runs it.** Every step marked **(OWNER)** changes production (a merge, a notice, a secret) and is
the owner's. An agent may prepare and verify, never publish or set. Replace nothing in the commands:
the project is `qsfzzsjenopqqqhvpyaw`, and the wrapper is `./scripts/supabase.sh` (never the bare
`supabase`). Run from a checkout of the merged `main` commit.

**The rule this runbook follows.** Data goes only to the vendor named by the notice the athlete
accepted. The gateway routes, and (after the A4-A6 fixes) the old DeepSeek and Groq paths too,
refuse to send, and fail closed, when the current notice names a different vendor. Two consequences
set the order of every feature's cutover: **route first, then notice, then the athlete accepts.**
- **Set the route first (`EVALUATED=true`).** While the current notice still names DeepSeek or Groq,
  the new route cannot send either (its vendor is not the one named), so athletes get the
  feature's fail-closed answer: Coach chat "consent required", the daily decision and the starting
  plan the deterministic rules, meal photos unavailable. Nothing reaches Anthropic and nothing
  reaches the old vendor through that route.
- **Then publish the Anthropic notice, and athletes accept it.** From the moment it is current the
  route serves every athlete who has accepted it, and nobody else.
- **The degraded window.** From setting the route until an athlete accepts, that athlete's feature
  is degraded as above. The other order (notice first, route second) is equally degraded: the old
  path fails closed from the moment the Anthropic notice is current, until the route is set. Either
  way nothing is sent to a vendor the athlete did not accept; route first just means the owner is
  never left with a published notice and no route. Keep the window to minutes per feature: route,
  publish, accept, in one sitting.

Other properties:
- Merging and deploying changes nothing for athletes: with no `AI_<FEATURE>_*` settings and no new
  notice, every feature runs today's DeepSeek or Groq path unchanged.
- The active plan, manual logging and the deterministic fallbacks work throughout; no step needs
  downtime.
- Every secret change creates a new version of every Edge Function. After each one, run
  `./scripts/verify-live-function.sh --all` and wait for it to pass before the next change.
- Never type a key into a command. Load it from `.env` into a shell variable (step 3.0).

## What moves

| Feature | `AI_<FEATURE>_*` prefix | Model id | `MAX_OUTPUT_TOKENS` | `TIMEOUT_MS` | At this cutover |
| --- | --- | --- | ---: | ---: | --- |
| Coach chat | `AI_COACH_CHAT_` | `claude-haiku-5-5` | 4096 | 30000 | yes |
| Coach chat, stronger route (A9, optional) | `AI_COACH_CHAT_STRONG_` | `claude-sonnet-5-5` | 4096 | 30000 | optional, after 3.1 (step 3.1b) |
| Daily decision | `AI_DAILY_DECISION_` | `claude-sonnet-5-5` | 1800 | 25000 | yes |
| Meal photo | `AI_MEAL_VISION_` | `claude-haiku-5-5` | 1500 | 30000 | yes, after your own-photo check passes (3.3) |
| Physique check | `AI_PHYSIQUE_VISION_` | `claude-sonnet-5-5` | 800 | 60000 | yes, after your own-photo check passes (3.4), limited to you |
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
- The USD 50 global stop is the owner's to confirm **before merging #124**: migration code 17
  sets it at deploy. If you want another number, tell the lead before the merge so the migration
  is changed; after it has deployed, change it with
  `update private.ai_budget_limits set global_monthly_usd = <n>, updated_at = now();`.
- Production still runs DeepSeek and Groq: Supabase dashboard > Edge Functions > Logs shows no
  `ai_call` lines yet (the gateway logs only when a route is used).

## 2. Install the new app build (OWNER)

The D11 wording ships in the app (AI answers read "AI answer · checked by Tracend"; no screen names a
model or company outside a consent notice). From the merged `main` commit:
`./scripts/install-device.sh` (it checks the bundle with `scripts/verify-app-bundle.sh`). Older
builds keep working: they show the server notice's company name on two cards, and nothing else
changes. Do this before step 4 so athletes accept the notices in the new build.

## 3. Set a feature's route (OWNER)

Work one feature group at a time, in this order: **Coach chat and daily decision**, then **meal
photo**, then **physique check**. For each group: set its route here (3.1-3.4), then publish its
notice and accept it (step 4), then use the feature and run the verify list at the end of this
step. Stop and roll back (section 6) at the first problem.

Until the notice is published and accepted (step 4), the route sends nothing and the feature is
degraded for that athlete: Coach chat answers "consent required" (the app shows its AI-off card),
the daily decision and the starting plan use the deterministic rules, meal photos answer 503
`meal_photo_notice_outdated`, the physique check is unavailable. Plans, logging and Apple Health
sync are unaffected. Do the route, the publish and your own accept in one sitting. For the two
photo features, your own-photo check on your Mac (3.3, 3.4) comes before their route.

**3.0 Load the key (once).** Never print it. `.env` holds `ANTHROPIC_API_KEY`:
```sh
set -a; . ./.env; set +a
./scripts/supabase.sh secrets set ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
Also set a monthly spend limit on the Anthropic console workspace as a backstop to the in-app stops.

**3.1 Coach chat.**
```sh
./scripts/supabase.sh secrets set \
  AI_COACH_CHAT_PROVIDER=anthropic AI_COACH_CHAT_MODEL=claude-haiku-5-5 \
  AI_COACH_CHAT_MAX_OUTPUT_TOKENS=4096 AI_COACH_CHAT_TIMEOUT_MS=30000 \
  AI_COACH_CHAT_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
After you accept the coaching notice (step 4), use it: ask the Coach one question, then the same question again. Check the log (below): the second
`ai_call` for `coach_chat` has `cache_read_tokens` above zero. The reply is labelled "AI answer ·
checked by Tracend".

**3.1b Coach chat, stronger route (OWNER, optional; needs the A9 server change deployed).**
Questions that ask for analysis (progress, a trend or pace, a change to the plan or a target, a nutrition amount) are
answered by this second route instead of the default one (a plain rules classifier decides;
`coach_chat_provider_route.ts`). Everything else, and every question while this is unset, uses the
3.1 route. It needs no new key and no new notice: it is Anthropic like the default route, and it is
used only for an athlete whose accepted notice names Anthropic. Set it after 3.1 works:
```sh
./scripts/supabase.sh secrets set \
  AI_COACH_CHAT_STRONG_PROVIDER=anthropic AI_COACH_CHAT_STRONG_MODEL=claude-sonnet-5-5 \
  AI_COACH_CHAT_STRONG_MAX_OUTPUT_TOKENS=4096 AI_COACH_CHAT_STRONG_TIMEOUT_MS=30000 \
  AI_COACH_CHAT_STRONG_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
Cost: A6's eval measured about USD 0.011 per Sonnet answer against 0.00045 for Haiku, so an
analytic question costs about 25 times a chat one. The per-athlete stop (USD 3 a month) counts the
real price of the route that answered; at 30 analytic questions a day it would be reached in about
nine days, which is why only the analytic questions use it. Check: ask "Why has my weight
stalled?" in the app. The log (below) shows an `ai_call` with `feature` `coach_chat_strong` and the
Sonnet model, and `model_runs` shows `anthropic` with `claude-sonnet-5-5`. A greeting still shows
`coach_chat`. **Roll back (instant, settings only):** `./scripts/supabase.sh secrets unset
AI_COACH_CHAT_STRONG_PROVIDER --project-ref qsfzzsjenopqqqhvpyaw`, then
`./scripts/verify-live-function.sh --all`: every question goes back to the default route.

**3.2 Daily decision.**
```sh
./scripts/supabase.sh secrets set \
  AI_DAILY_DECISION_PROVIDER=anthropic AI_DAILY_DECISION_MODEL=claude-sonnet-5-5 \
  AI_DAILY_DECISION_MAX_OUTPUT_TOKENS=1800 AI_DAILY_DECISION_TIMEOUT_MS=25000 \
  AI_DAILY_DECISION_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
After you accept the coaching notice (step 4): generate today's decision. It must pass the existing validator (a forbidden or ungrounded
answer falls back to the deterministic decision and records a failed run).

**3.3 Meal photo.** `MEAL_VISION_ENABLED` stays `true`. Meal vision has no allowlist: once its
route is evaluated, every athlete who accepts the notice can use it. So your own-photo check
(AI_SAFETY_SPEC §8) comes **first**; the synthetic drawings used in the evals test the contract and
refusals, not recognition of real food. The check runs on your Mac and touches nothing in
production: no route, no database, no Storage.
1. Put about ten of your own typical meals in a local folder (not in the repo), including a mixed
   home dish and one photo that is not a meal.
2. Run it (the key is read from `.env` and never printed; the photos go only to Anthropic; it
   stops before a call that could pass its cap, 1 USD unless you pass `--cap-usd`):
   ```sh
   set -a; . ./.env; set +a
   ./scripts/deno.sh run --allow-env --allow-net=api.anthropic.com --allow-read="$PHOTOS" \
     supabase/functions/_evals/owner_photo_check.ts meal "$PHOTOS"
   ```
   It sends each photo through the same request meal-analyze sends (same instructions, schema,
   model and settings, imported from `meal-analyze/vision.ts`) and prints the foods it would offer.
3. Judge the output: the foods named are the foods on the plate, portions are sensible, nothing is
   invented, the mixed dish asks about its recipe, and the non-meal photo returns "no food found".
4. **Only if it passes,** set the production route (`EVALUATED=true` last). If it does not, set
   nothing and report what was wrong.
```sh
./scripts/supabase.sh secrets set \
  AI_MEAL_VISION_PROVIDER=anthropic AI_MEAL_VISION_MODEL=claude-haiku-5-5 \
  AI_MEAL_VISION_MAX_OUTPUT_TOKENS=1500 AI_MEAL_VISION_TIMEOUT_MS=30000 \
  AI_MEAL_VISION_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
After you accept the meal photo notice (step 4): photograph a meal or two in the app and confirm the
candidates look like the check's. Nothing is logged until you confirm the foods. If it is poor,
unset the five settings (section 6) and report it.

**3.4 Physique check (your own-photo check first, then a route limited to you, then widen later).**
The route refuses with 403 `physique_vision_not_evaluated` until `AI_PHYSIQUE_VISION_EVALUATED=true`,
and AI_SAFETY_SPEC §9 requires your own-photo check before that. It comes **first** and runs on your
Mac only; nothing in production is touched.
1. Put a few of your own photo sets in a local folder (not in the repo): one sub-folder per set,
   each holding `front.jpg`, `side.jpg` and `back.jpg`.
2. Run it (the key is read from `.env` and never printed; the photos go only to Anthropic; it
   stops before a call that could pass its cap, 1 USD unless you pass `--cap-usd`):
   ```sh
   set -a; . ./.env; set +a
   ./scripts/deno.sh run --allow-env --allow-net=api.anthropic.com --allow-read="$PHOTOS" \
     supabase/functions/_evals/owner_photo_check.ts physique "$PHOTOS"
   ```
   Each set goes through the check's own handler (JPEG cleaning, the same request, model and
   settings, the result contract and the one correction), and the parsed result or the refusal is
   printed.
3. Judge the output: sensible muscles to develop for your own build, no body-fat figure, no score,
   no judgement of appearance, nothing medical, and no refusal on a clear set. The drawings in the
   evals only test the contract.
4. **Only if it passes,** confirm the route stays limited to you, then set it. The first
   production day keeps `PHYSIQUE_VISION_ALLOWED_USERS` at your id alone; widening it is a later
   step that needs the separate evaluation in AI_SAFETY_SPEC §9, and this runbook never adds an
   account. Check first: `./scripts/supabase.sh secrets list --project-ref qsfzzsjenopqqqhvpyaw`
   shows `PHYSIQUE_VISION_ALLOWED_USERS` (its value is hidden; if you cannot say it is only you,
   set it to your id first).
```sh
./scripts/supabase.sh secrets set \
  AI_PHYSIQUE_VISION_PROVIDER=anthropic AI_PHYSIQUE_VISION_MODEL=claude-sonnet-5-5 \
  AI_PHYSIQUE_VISION_MAX_OUTPUT_TOKENS=800 AI_PHYSIQUE_VISION_TIMEOUT_MS=60000 \
  AI_PHYSIQUE_VISION_EVALUATED=true --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
After you accept the progress photo notice (step 4), run one check in the app on your own set and
confirm it matches the check's. If anything is wrong, unset the five settings (section 6).

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

## 4. Publish the feature's notice, then accept it (OWNER)

Publish each notice right after its route is set (step 3), in the same order: **Coach chat and
daily decision together** (one coaching notice covers both), then **meal photo**, then **physique
check**. The route already exists, so the feature works for you the moment you accept.

Drafts: [`docs/notices/ai-coaching-v6.md`](../notices/ai-coaching-v6.md),
[`meal-photo-ai-v2.md`](../notices/meal-photo-ai-v2.md),
[`progress-photo-ai-v2.md`](../notices/progress-photo-ai-v2.md). Each holds the full SQL call
(`private.publish_ai_notice`, `private.publish_meal_photo_ai_notice`,
`private.publish_photo_ai_notice`, all five arguments: version, provider `anthropic`, label
`Anthropic`, purposes or model, body).

**Before the first publish:** edit the text if you want to, then re-read Anthropic's published
retention policy (privacy.claude.com, "How long do you store my organization's data?"). The drafts
say: deleted within 30 days, not used for training, kept longer only where the law requires or to
enforce its usage rules. If the policy changed, change the text first.

The app has no notice text of its own: it shows and records only the notice the server returns
(`get_current_ai_notice`), so a text change needs no new app build. If that call fails, the
signed-in app still opens with AI coaching off and no answer assumed; only the AI coaching
question, the Coach and Account sheet and the onboarding AI step say the notice could not be
loaded and offer **Try again**, with no answer buttons until it loads (onboarding goes on with the
rules plan). Nothing is recorded without a fetched notice. If you cannot accept in the app, check
the publish with the draft's "Check after publishing" query and retry.

**4a. Publish.** Run the draft's SQL in the Supabase SQL editor (production), then its "Check after
publishing" query. The label check refuses a wrong label (22023); nothing is half-published. (The
old four-argument publishers refuse too, so a notice can never be published without its vendor.)
- Coaching `ai-coaching-v6` covers `coach_chat`, `daily_coaching` **and `onboarding_plan`**. The
  notice is written to be honest about onboarding: it says AI starting plans are not switched on
  yet and nothing from onboarding goes to an AI until they are. So **from the moment v6 is current,
  new athletes get the rules plan, with no AI starting plan and no follow-up questions, until you set
  the onboarding routes after B2** (section "Later"); the old DeepSeek onboarding path stops
  because the current notice no longer names DeepSeek. DeepSeek therefore receives nothing. If you
  would rather keep AI onboarding on DeepSeek meanwhile, do not publish v6 until B2 has merged and
  onboarding can move with the rest (the Coach and daily decision routes stay degraded until then).
- Meal photo `meal-photo-ai-v2`: before it is accepted, meal photos answer 503 `meal_photo_notice_outdated`.
- Physique `progress-photo-ai-v2`: before it is accepted the physique check is unavailable.

**4b. Check the notice.**
`select public.get_ai_consent_v2('<your user id>', 'coach_chat');` shows `provider` `anthropic` and
`notice_version` `ai-coaching-v6`, with `granted` false until you accept (the same for
`'daily_decision'`, `'meal_vision'`, `'physique_vision'` with their notices).

**4c. Athletes re-accept in the app.** A new notice version asks every athlete again; a grant of an
older version no longer counts.
1. Open the new build. The AI coaching question appears: read the Anthropic notice, choose **Allow
   AI coaching**. Accept the meal photo notice (Log a meal) and the progress photo notice (Progress
   > physique check) when you reach their step.
2. Other athletes accept the same way the next time they open the app. Until they do, nothing is
   sent for them and they see "AI coaching is off" with a **Review AI coaching** button (the
   deterministic plan and logging keep working). The route serves each athlete the
   moment they accept.

Verify, in the SQL editor:
```sql
select distinct on (user_id, consent_type) user_id, consent_type, action, notice_version, created_at
from public.consent_records
where consent_type in ('ai_coaching', 'meal_photo_ai', 'progress_photo_ai')
order by user_id, consent_type, created_at desc;
```
Your rows show `granted` with the new version. Then use the feature (step 3's checks) before moving
to the next group.

## 5. Verify the whole cutover (OWNER)

- `./scripts/verify-live-function.sh --all` from the deployed commit.
- Each moved feature has a recent `ai_call` line with `vendor` `anthropic` and `outcome` `ok`, and
  its newest `model_runs` or `ai_usage_events` rows say `anthropic` (step 3's queries).
- Use the app as an athlete would: Coach question, today's decision, a meal photo, a physique check.
  No screen names a model or company except the consent notices.
- Onboarding has no AI route yet. Because `ai-coaching-v6` covers `onboarding_plan`, new athletes get
  the rules plan with no AI and no follow-up questions until onboarding moves (below). DeepSeek
  receives nothing. The external TestFlight group should wait for onboarding's AI route (a product
  decision, beta exit criterion in the plan decisions log 2026-10-15 is already met for health
  data).

## Later: onboarding, after B2 (OWNER)

Not part of this cutover; until then onboarding uses its rules plan (see 4a). A4's eval passes the 90%
bar on only about half of the runs; the failures are weekly-volume rules that chunk B2 fixes. After B2 merges, re-run the onboarding eval
(`supabase/functions/_evals/onboarding_plan_eval.ts`, `EVAL_PROVIDER=anthropic`, at most USD 2) until
it passes the bar on repeated runs, then set both routes. The coaching notice v6 already names
Anthropic for the `onboarding_plan` purpose, so no new notice is needed and the routes serve every
athlete who accepted v6:
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
Verify as in step 3 (`feature` `onboarding_plan` and `onboarding_questions`), with a new test
account's onboarding. Onboarding's own 2-week rollback window starts then.

## 6. Rollback (OWNER), for 2 weeks after each feature moves (D1)

Rolling back has **two separate steps**. 6.1 is instant and safe. 6.2 is only needed if you
want the old vendor to serve athletes again.

DeepSeek and Groq keys and the old `COACH_*`, `ONBOARDING_PLAN_*`, `MEAL_VISION_*` and
`PHYSIQUE_VISION_*` settings stay in place for the whole window. Do not remove them early.

### 6.1 Stop calling Anthropic (settings only, immediate)

Unset the feature's provider (a route without a provider is no route):
```sh
./scripts/supabase.sh secrets unset AI_COACH_CHAT_PROVIDER --project-ref qsfzzsjenopqqqhvpyaw
./scripts/verify-live-function.sh --all
```
(`AI_DAILY_DECISION_PROVIDER`, `AI_MEAL_VISION_PROVIDER`, `AI_PHYSIQUE_VISION_PROVIDER`, and for
onboarding both `AI_ONBOARDING_*_PROVIDER`; unset the feature's other `AI_<FEATURE>_*` settings when
tidying.) Calls to Anthropic stop at once.

**This does not send traffic back to DeepSeek or Groq.** While the current notice names Anthropic,
the old paths refuse because the athlete's accepted notice does not name their vendor. The features
degrade safely instead:
- Coach chat answers "consent required" (403 `ai_consent_required`; the app shows its AI-off card).
- The daily decision and the starting plan use the deterministic rules.
- Meal photos are unavailable (503 `meal_photo_notice_outdated`); the physique check is unavailable.
- The plan, manual logging and Apple Health sync are unaffected.

That is the right state for an Anthropic outage or a bad answer you want to stop. A brief Anthropic
outage needs no rollback at all: the Coach shows its labelled data summary and the daily decision
its deterministic fallback.

### 6.2 Restore DeepSeek or Groq (only if you want AI back on the old vendor)

Do 6.1 first. Then republish the old text under a **new version** naming the old vendor, so the
current notice matches the vendor that will receive the data. Every athlete is asked again and must
re-accept before the old path serves them.
- Coaching: `private.publish_ai_notice('ai-coaching-v7', 'deepseek', 'DeepSeek',
  array['coach_chat','daily_coaching','onboarding_plan'], <the ai-coaching-v5 body>)`. The v5 text is
  in `supabase/migrations/20261009160100_meal_photo_ai_notice.sql`.
- Meal photo: `private.publish_meal_photo_ai_notice('meal-photo-ai-v3', 'groq', 'Groq',
  'qwen/qwen3.8-27b', <the v1 body>)` (text in the same migration).
- Physique: `private.publish_photo_ai_notice('progress-photo-ai-v3', 'groq', 'Groq',
  'qwen/qwen3.8-27b', <the v1 body>)` (text in `20261002150000_physique_check.sql`).

Re-accept the notice yourself and check the feature works before telling anyone. Restoring is visible to athletes (they
are asked to accept again), so restore for a real reason, not one slow answer. Moving forward to
Anthropic again later needs a new Anthropic notice version and the same accept step.

## 7. After the window (OWNER)

Two weeks after a feature moved with no rollback:
1. Remove its old settings and keys (`./scripts/supabase.sh secrets unset ...`), then
   `./scripts/verify-live-function.sh --all`. Groq's keys go two weeks after meal photos and the
   physique check moved. DeepSeek's key goes two weeks after the Coach and daily decision moved,
   unless onboarding is still waiting on DeepSeek by choice (see 4a); onboarding on its rules plan
   needs no key.
2. **Drop the processors from the privacy policy.** Remove Groq, and DeepSeek, from the website's AI
   processor list once nothing still sends them data and the window has passed. Update
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
