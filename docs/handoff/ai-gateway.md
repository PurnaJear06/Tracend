# AI Gateway Handoff

**As of:** 2026-10-17

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

Every AI call goes through one provider-neutral gateway (Contract 1). Claude Haiku 5.5 and Sonnet 5.5 replace DeepSeek and Groq at cutover; the old routes stay available by settings for two weeks.

## Chunks

A1, A2 (Phase 1); A3–A7 (Phase 2); A9 server half (Phase 3, round 3)

## State

A1 (#103) and A2 (#106) are live (2026-10-15). A3-A7 are in review.

**A1 (live, #103, migration `20261015120011_provider_neutral_ai.sql`):**

- In SQL a provider is the vendor that receives the data (`anthropic`, `deepseek`, `groq`,
  `gemini`, `mock` for runs), never `openai_compatible` (lead decision, Contract 1 v2). Every SQL
  provider list accepts `anthropic` next to today's names:
  `model_runs` and `ai_usage_events` provider checks, `ai_usage_events_model_check`,
  `meal_photo_ai_notices_provider_check`, and the RPCs `persist_coach_chat_result`,
  `persist_daily_coaching_result_v2`, `persist_failed_coaching_run_v2`,
  `persist_failed_coach_chat_run` (`_v2` wraps it), `record_ai_usage_event`,
  `persist_meal_photo_candidates`. Old vision vendors keep pinned models; `anthropic` accepts any
  well-formed model id. No frozen function holds a provider list.
- `ai_consent_notices.provider` and `photo_ai_notices.provider` (nullable; old notices null).
  Publish with `private.publish_ai_notice(version, provider, provider_label, purposes, body)` and
  `private.publish_photo_ai_notice(version, provider, provider_label, model, body)`.
- `get_ai_consent_v2(target_user_id, consent_purpose)` → `{schema_version, granted, provider,
  notice_version}`; TS `aiConsentWithProvider(rpc, userId, purpose)` → `{consent, provider,
  noticeVersion}`, `provider` typed `AiVendor`. Purpose mapping: AI_SAFETY_SPEC §10.
- `reserve_ai_budget_v2(target_user_id, run_purpose, ceiling_usd)`, ceiling USD 0.001 to 0.50; TS
  `AiBudget.reserve(purpose, ceilingUsd)`. Feature names map to today's purposes (COST_MODEL).
- Until a notice naming the route's provider is published and granted, `get_ai_consent_v2` returns
  `provider: null` for coaching and physique notices, so a gateway call would refuse. Cutover (A7)
  publishes those notices.
- Open: a `library_context` model call would need its own usage purpose in `model_runs` or
  `ai_usage_events` (today it is budgeted and consented as `coach_chat`).
- Follow-up for A3: `_shared/ai_consent.ts` declares its own `AiVendor` union, which duplicates the
  gateway's (A2). A3 unifies them after A2 merges.
- The five-argument publishers are owner-run SQL: `provider_label` must name the same company as
  `provider`. `private.check_notice_provider_label` enforces it in all three publishers that name
  a provider (meal photo included): the label must contain Anthropic, DeepSeek, Groq or Google for
  `anthropic`, `deepseek`, `groq` or `gemini` (case ignored) and no other of those names; a blank
  label or an unknown provider is refused (22023). Vision through DeepSeek,
  or a Groq or Gemini model other than the pinned ones, still needs a migration (A3).

### A2: gateway module (live, #106)

`supabase/functions/_shared/ai/` implements Contract 1 version 2. No feature calls it yet;
nothing outside the folder changed.

- `types.ts`: the Contract 1 types, including `AiVendor` (`anthropic`, `deepseek`, `groq`,
  `gemini`, `router`), `route.vendor` and `request.consentVendor`.
- `routes.ts`: `route(feature, env)` reads `AI_<FEATURE>_*` and the provider key. Required:
  `PROVIDER`, `MODEL`, `MAX_OUTPUT_TOKENS` (1–32,000), `TIMEOUT_MS` (1,000–150,000, inside the
  Edge Function wall clock) and the key; `BASE_URL` too for `openai_compatible`. `THINKING`
  defaults to `off`, `EVALUATED` to `false`, `EFFORT` to the model's default. Any missing or
  invalid value returns `null`, and so does a setting the request could not carry: an effort on
  DeepSeek or Gemini without `THINKING=adaptive`, any effort on Qwen, `THINKING=off` on Opus 5.5
  (which cannot turn thinking off; the default `off` therefore gives Opus no route). The key stays
  off the route object (a `WeakMap`), so only a route from `route()` can send. Gemini also needs
  `GEMINI_PAID_DATA_TERMS_ACCEPTED=true` (AI_SAFETY_SPEC §10).
- **Vendors and the eval router.** The vendor comes from the model table. DeepSeek is pinned to
  `api.deepseek.com` and Groq to `api.groq.com`. `AI_<FEATURE>_VENDOR=router` (the only value the
  setting takes) sends an OpenAI-compatible model's request to any https `BASE_URL` with vendor
  `router`; no notice names it, so an athlete's request never reaches it (tested for every
  athlete vendor). Only OpenAI-compatible models (DeepSeek, Qwen) can go through a router today.
- `providerLabel` is the company only (D11): "Anthropic", "DeepSeek", "Groq", "Google"
  ("Evaluation router" for the router, which no notice shows).
- `models.ts`: the price and capability table. Claude Haiku/Sonnet/Opus 5.5 at the 2026-10-15
  list prices (cache writes at the 5-minute rate; Haiku's over-100K card counts cache tokens
  toward the threshold), plus the rollback models `deepseek-flash`, `deepseek-v4-flash`,
  `qwen/qwen3.8-27b` and `gemini-3.5-flash`. A model not in the table has no price, so no route.
  Per model: image limit (Claude 3.75 MB decoded = 5 MB of base64, the Bedrock/Google limit and
  half the direct API's 10 MB; Groq and Gemini 4 MiB as today; DeepSeek none), efforts, and the
  request defaults of today's providers.
- **Rollback parity** (`parity_test.ts` records today's providers with a fake fetch and compares
  every non-prompt field): DeepSeek off sends `thinking: {type: "disabled"}, temperature: 0.1`;
  DeepSeek adaptive sends `thinking: {type: "enabled"}, reasoning_effort: "high"` with no
  temperature; Qwen on Groq sends `temperature: 0.1` and `max_completion_tokens`; Gemini sends
  `temperature: 0.1` with `thinkingLevel` low (off) or the effort (adaptive, medium by default).
  OpenAI-compatible JSON mode adds the system line `Return only valid JSON matching this schema:
  <schema>`. Claude requests carry no sampling parameters.
- Thinking "off" on Claude: Haiku 5.5 `{type: "disabled"}`, Sonnet 5.5 `{type: "between_tools"}`.
- `gateway.ts`: `call()` refuses before sending on a consent mismatch (`consentVendor !==
  route.vendor`), a route without a key, an assistant-last conversation (Claude 5 rejects
  prefill), a blank text part, an image that is not base64, too large, in an assistant turn or
  for a model without images, or a JSON schema the checker cannot enforce (`json_schema.ts`) or
  Claude cannot take. One request; timeout and caller `AbortSignal` both end it as `timeout`.
  429 → `rate_limited` (with `retry-after`), 529/503 → `overloaded`, other HTTP errors →
  `provider_error` (error bodies are never read). Every answer that arrived returns its priced
  usage, also on `refused`, `invalid_output`, an empty answer and a billed 200 with a broken
  shape.
- `adapters/anthropic.ts`: Messages API, no `temperature`/`top_p`/`top_k`/`tools`/`tool_choice`;
  JSON via `output_config.format` (`json_schema`). The schema sent to Claude drops the limits it
  rejects (`maxLength`, `minimum`, `maxItems`, `format`, ...), closes every object schema
  (including `properties` without a `type`), and is refused for an open map
  (`additionalProperties` true or a schema) or an object/array enum or const. The gateway still
  checks the full schema on the answer. `cache: true` becomes `cache_control: {type:
  "ephemeral"}` (at most 4).
- `adapters/openai_compatible.ts` (DeepSeek, Groq, router): text blocks joined with a blank line,
  images as data URLs, cache hits from `prompt_cache_hit_tokens` or
  `prompt_tokens_details.cached_tokens`.
- `adapters/gemini.ts`: each system block its own part, `responseJsonSchema`, thought parts
  skipped, thought tokens billed as output; `SAFETY`, `IMAGE_SAFETY`,
  `IMAGE_PROHIBITED_CONTENT` and the other block reasons map to `refused`.
- `log.ts`: one `ai_call` line (feature, provider, vendor, model, outcome, four token counts,
  cost, latency, HTTP status, stop); never prompt, image, reply or error text.
- Tests: 65 offline tests with a fake fetch (`fakes.ts`); no network.

## Phase 2 chunks

Each chunk edits only its own section below, so parallel PRs do not conflict.

### A3: meal photo and physique check on Claude

**State (2026-10-15): in review.** `meal_vision` and `physique_vision` call the gateway when
their route exists. With no `AI_MEAL_VISION_*` / `AI_PHYSIQUE_VISION_*` settings both functions
run today's Groq (or Gemini) path, byte for byte, so merging and deploying changes nothing.
No migration: A1's SQL already accepts `anthropic` in `record_ai_usage_event` and
`persist_meal_photo_candidates`, and `physique_analyses.provider` is free text.

- **Meal photos** (`meal-analyze/vision.ts`): `mealVisionPath()` picks the route or today's
  provider. On a route: consent from `get_ai_consent_v2('meal_vision')`; the handler's existing
  guard answers 503 `meal_photo_notice_outdated` unless the meal photo notice names the route's
  vendor, and the gateway checks the vendor again. `MEAL_VISION_ENABLED` stays the switch;
  `AI_MEAL_VISION_EVALUATED=true` replaces `MEAL_VISION_MODEL_EVALUATED`. The JPEG is checked
  and its metadata removed (`_shared/physique/jpeg.ts`). Reservation: `reserve_ai_budget_v2`
  with the route's ceiling (8,000 prompt tokens at the dearer input/cache-write rate plus every
  output token; Haiku at 1,500 tokens = USD 0.00175). Usage and candidates store the vendor and
  the model that answered. Failures: 429/529 → 429 `meal_vision_busy` (released); refusal,
  invalid output → usage recorded, 503; timeout/network/unreadable → reservation kept, 503.
- **Physique check** (`_shared/providers/physique_vision_provider.ts`, `physique-check/`):
  `resolvePhysiqueVision()` returns `{kind: "gateway", route}` when the route exists and is
  evaluated (`physique_vision_not_evaluated` otherwise); `PHYSIQUE_VISION_ENABLED` and the
  allowlist still apply. Consent from `get_ai_consent_v2('physique_vision')`: a notice that does
  not name the route's vendor is 403 `photo_ai_consent_required`, nothing sent. Status returns
  `provider_label` "Anthropic" (the route's company label, no model). This does **not** meet D11
  yet: the app renders it outside a notice ("Sent to $provider only when you start a physique
  check"), see the A7 note below. One reservation covers the photo call and one
  text-only correction (Sonnet at 800 tokens = USD 0.071). On the route the correction no
  longer waits on Groq's minute budget. Rules are the cached system prefix; photos, then the
  athlete line, in the user turn; structured output fixes the keys, muscles and photo issues,
  while counts, lengths and wording stay with `parsePhysiqueResult`, so a broken reply can still
  be corrected once. A refusal is recorded and answers 503.
- **Tests:** `meal-analyze/vision_test.ts` (11) and `physique-check/gateway_test.ts` (10), gateway
  fakes only. Parity: `legacy_requests_golden.json` in both functions holds today's request
  bodies recorded from `origin/main`; the tests assert byte equality with no route, and with
  incomplete settings.
- **Evals** (`_evals/meal_vision_eval.ts`, `_evals/physique_eval.ts`; images drawn by
  `_evals/meal_vision_images/make_test_images.py`, no people, no real meals). No Groq baseline
  was ever recorded for either feature, so these runs are the baseline (2026-10-15):
  - Haiku 5.5, thinking off: 12/12 valid and passing (food found, no food on a notebook and on a
    text-only page, written instructions ignored), p50 2.5 s, p95 4.7 s, USD 0.0029; the
    instructions and schema (888 tokens) were read from cache on every call after the first.
  - Sonnet 5.5, thinking off: 5/5 sets pass, no contract refusal; the injected-text set and
    the dark set each needed the one correction; unrelated pictures were "nothing to assess";
    max 7.4 s, USD 0.050.
  - The drawings test the contract, "no food", injection and refusal handling, not recognition
    of real meals or bodies. The owner's real-photo check (AI_SAFETY_SPEC §8) and the §9
    evaluation still decide `EVALUATED` and the allowlist.
- **Cutover (A7):** publish meal photo and progress photo notices naming `anthropic`
  (five-argument publishers), then set `AI_MEAL_VISION_{PROVIDER=anthropic,
  MODEL=claude-haiku-5-5,MAX_OUTPUT_TOKENS=1500,TIMEOUT_MS=30000,EVALUATED=true}` and
  `AI_PHYSIQUE_VISION_{PROVIDER=anthropic,MODEL=claude-sonnet-5-5,MAX_OUTPUT_TOKENS=800,
  TIMEOUT_MS=60000,EVALUATED=true}`. Rollback: unset them. AI_SAFETY_SPEC §8/§9 still describe
  Groq; they become stale only at cutover.
- **For A7, D11 (app wording, not in A7's file list):** `lib/features/progress/widgets/photo_widgets.dart`
  (lines 104-106) and `lib/features/progress/progress_screen.dart` (lines 340-351) render the
  physique status's `provider_label` as "Sent to $provider only when you start a physique
  check". That names the company outside a notice; both must drop the provider name. A3 left
  Dart alone (A7 owns the app wording). The server keeps returning `provider_label` for old builds.
- **Tests added after review:** `billingSettled` (the physique keep/release decision, now in
  `handler.ts` and used by `index.ts`), refusal-then-release and lost-answer-keeps-place with a
  real `AiBudget` for both features, and a physique correction call that is busy, refused or
  lost. An ambiguous `provider_error` (for example an unreadable 200) keeps its reservation.
- **Never under-reserve:** `mealVisionCeilingUsd` and `physiqueCeilingUsd` return `null` (no longer
  a clamped 0.50) when a route's worst case is above USD 0.50 or its model is unknown. Meal
  photos then answer 503 `meal_analysis_unavailable` and log `meal_vision_route_unusable`;
  `resolvePhysiqueVision` returns `off` with reason `physique_vision_route_unusable` (status
  `enabled: false`, check 403 `physique_check_unavailable`, handler warns with that code). Nothing
  is reserved or sent. Haiku/Sonnet at 1,500/800 tokens are unaffected.
- **Left for A7** (owns `_shared/ai_consent.ts` in Phase 2): A1's follow-up to replace that
  file's own `AiVendor` union with the gateway's was not done here.

### A4: onboarding plan and questions on Claude

**State (2026-10-16): in review.** Features `onboarding_plan` and `onboarding_questions` call the
gateway when their route exists. With no `AI_ONBOARDING_PLAN_*` / `AI_ONBOARDING_QUESTIONS_*`
settings (or no `EVALUATED=true`) both run today's `ONBOARDING_PLAN_*` settings path, byte for
byte, so merging and deploying changes nothing. Edge Functions only: no SQL (A1's
`record_ai_usage_event` already accepts `anthropic` for both purposes, and the proposal's
`provider`/`model` live in a free-text payload), no app change. `onboarding-propose-plan` is the
mock proposal with no model call and is untouched.

- **Two paths** (`onboardingGatewayRoute` in `_shared/providers/onboarding_plan_provider.ts`, wired
  in `onboarding-plan/index.ts`):
  - settings path: `route(feature)` is null, or its `AI_<FEATURE>_EVALUATED` is not `true`, or it is
    the eval router (ignored and logged: no notice names it). Exactly today's behaviour:
    `ONBOARDING_PLAN_*`, `has_ai_coaching_consent`, `reserve_ai_budget` at the fixed ceiling,
    `callOnboardingModel`. An unevaluated route is identical to no route.
  - gateway: a complete, evaluated route whose worst case the budget accepts. Plan and questions
    have separate routes (`AI_ONBOARDING_PLAN_*`, `AI_ONBOARDING_QUESTIONS_*`).
- **Consent:** `get_ai_consent_v2` for `onboarding_plan` / `onboarding_questions`; the notice must
  name the route's vendor (`consentVendor`, checked again by the gateway). Otherwise nothing is
  sent: the plan becomes the rules plan (`ai_consent_not_granted`) and the questions are skipped
  and not stored.
- **Settings-path consent** (privacy rule): when the route is not used (no route, `EVALUATED=false`,
  over USD 0.50, unknown model, or the D1 rollback), the settings send the data to their own
  provider (DeepSeek, Groq or Gemini), so the current onboarding notice must name that vendor
  (`store.consent(feature, vendor)` reads `get_ai_consent_v2`; `legacyNoticeConsent`). A notice
  naming another vendor (Anthropic after cutover) sends nothing: rules plan, questions skipped
  (`ai_consent_not_granted`), no budget asked. A null provider counts as the settings vendor: A1
  added the column without a backfill, so today's production notice (vendor named only in
  `provider_label`) is null, and today's requests must stay byte-identical.
- **Plan** (`onboarding-plan/gateway.ts`, `generatePlanViaGateway`): the same rules prompt as the
  settings path (`onboardingSystemPrompt`, `onboardingUserMessage`, so the policy text stays in one
  place) plus one line forbidding model and company names (D11), as a cached system block; JSON
  output through the gateway with a structure-only schema (`onboardingPlanJsonSchema`). Lengths,
  ranges, slugs and every rule stay with `parseOnboardingPlan` / `validateOnboardingPlan`, and
  the result still goes through `buildOnboardingProposal`; the athlete approves it as before. One
  targeted repair, then the rules plan, exactly as today. The repair keeps the cached system
  block and the user block and adds a second user block with the broken rule, its path and the
  rejected candidate (untrusted data). A plan whose text names a model or company is a failed
  attempt (`names_model_or_company`), so the repair or the rules plan answers (D11).
- **Questions** (`generateQuestionsViaGateway`): one request, no repair; the schema is
  `followUpJsonSchema` (in `_shared/onboarding/questions.ts`); `parseFollowUpQuestions` still
  drops a reply that strays out of scope, and a question or choice naming a model or company is
  dropped the same way (`questions_invalid`).
- **Failure codes** are the settings path's: `provider_timeout`, `provider_rate_limited`,
  `provider_http_error` (overloaded, network, other HTTP), `provider_response_truncated` /
  `provider_response_invalid` (billed unreadable answer; earns the one repair), plus
  `provider_refused`. Stored provenance: `training.provider` is the vendor (`anthropic`) and
  `training.model` the model that answered; `ai_usage_events` gets the same with the real cost.
- **Budget** (`gatewayCeilingUsd`): one reservation, `reserve_ai_budget_v2`, covers the first
  attempt and one repair: for each attempt the whole prompt (UTF-8 bytes, which bound the tokens,
  plus 1,000) at the dearer of the input and cache-write price, plus every output token the
  route allows; the repair prompt adds up to 16,000 bytes of candidate. **Never clamped**: if the
  worst case passes USD 0.50, or the model has no price, the route is unusable for that request.
  Nothing is sent or reserved, the settings path answers, and `onboarding_plan_route_unusable` /
  `onboarding_questions_route_unusable` is logged (warn). Sonnet 5.5 at 8,000 plan tokens reserves
  USD 0.24 to 0.27 for both attempts (a question reserves 0.023; a plan costs 0.02 to 0.08); at
  32,000 it is unusable (tested). Outcomes (tested with a
  real `AiBudget` over a fake database):
  - not sent (notice names another vendor, budget refused), 429, 503/529, other HTTP errors: the
    place is released and no usage is recorded;
  - an answer that arrived (valid, invalid, cut off, refusal): its usage is recorded at the real
    cost (`usage.costUsd`), then the place is released;
  - a timeout or a broken connection (cost unknown): `keep()`, so the place keeps counting at
    its ceiling. If a billed first attempt is followed by a lost repair, the first attempt's usage
    is recorded and the place is also kept (counted twice until it ages out, on purpose).
- **Timeouts:** the plan honours `route.timeoutMs` for each attempt, bounded by a 120 s total
  deadline (the 140 s generation lease and the 150 s background limit); a repair is sent only
  with at least 10 s left. A longer route timeout is clamped and `onboarding_plan_timeout_clamped`
  is logged. Questions are bounded by 40 s (the app waits 45 s); a longer route timeout is
  clamped and `onboarding_questions_timeout_clamped` is logged.
- **Tests** (Deno suite: 535 passed, 0 failed, 8 ignored):
  - `onboarding-plan/gateway_test.ts` (55): parity, then the Claude request (cache mark, no
    sampling parameters, structured output), reservation size, unusable route, consent and budget
    refusals, repair and the second failure, D11 on plans and questions, every budget outcome for
    plan and questions, the timeout clamps, and every eval athlete being feasible.
  - **Parity:** `legacy_requests_golden.json` holds the request bodies of the settings path
    (DeepSeek thinking on and off, Groq; plan with its repair, and questions) recorded from the
    `origin/main` tree (610e320) by `legacy_golden_harness.ts`, run with `deno run --no-check`
    against `git archive origin/main`. The tests replay them on this tree byte for byte with no
    route, with an unevaluated route and with an incomplete route (18 tests). The golden embeds
    the prompt text from `generate.ts`: if a later chunk changes that prompt, record it again
    from `origin/main` the same way.
- **Live eval** (`_evals/onboarding_plan_eval.ts`, `EVAL_PROVIDER=anthropic`; 13 synthetic
  athletes, plan and follow-up questions each; Sonnet 5.5, thinking off, 8,000 plan tokens, 1,500
  question tokens; 2026-10-16). Baseline for comparison: the only recorded one is the old
  DeepSeek router run (12/12 valid, one repaired, p95 49 s, USD 0.11, 2026-10-02; 12 athletes, a
  router that ignored thinking-off); there was never a direct DeepSeek run. These are the first
  Claude numbers.
  - Run 1 (the shipped prompt; reverting run 2's extra line restored it, and the final head was
    not re-run): plans 12/13 valid (1 repaired), 1 fell back to the rules plan
    (`weekly_muscle_volume_exceeded`, shoulders on the six-day PPL athlete, after the repair);
    p50 15.4 s, p95 36.5 s; USD 0.507 for plans (about 0.04 each; a six-day plan 0.076). Questions
    12/13 answered (30 questions; one reply dropped as `questions_invalid`, which is the scope
    filter working), p95 3.8 s, USD 0.037 in all. All gates passed.
  - Run 2 (same code plus a prompt line telling the model to total each muscle's weekly sets,
    since removed): plans 11/13 valid (4 repaired), 2 fell back (the same athlete, and
    `priority_volume_missing` on the returning athlete); the 90% gate failed. The line did not
    help, so it was reverted. 13 athletes make one failure a 7.7-point swing, so read run 1 and
    run 2 as the same code with run-to-run noise: plans pass 90% on about half of the runs. Total
    spend for both runs and nothing else: USD 1.196.
  - The failures are all weekly volume (`weekly_muscle_volume_exceeded`, `priority_volume_missing`)
    on five or six day plans, which the repair fixes about half of the time. The repair message
    names the rule and the path only. **Contract request (generate.ts / policy.ts, read-only
    here):** put each muscle's weekly set limit and the sets it has so far into the repair
    message, or a pre-computed per-muscle set budget into the system prompt, then rerun the eval.
    The rules plan is the safety net either way.
  - Cache reads were observed: the questions prompt (787 tokens) is read from cache on every
    call after the first; a plan repair reads its 2.8k-token system block from cache.
- **Cutover settings (A7):** `AI_ONBOARDING_PLAN_{PROVIDER=anthropic,MODEL=claude-sonnet-5-5,
  MAX_OUTPUT_TOKENS=8000,TIMEOUT_MS=90000,EVALUATED=true}` and
  `AI_ONBOARDING_QUESTIONS_{PROVIDER=anthropic,MODEL=claude-sonnet-5-5,MAX_OUTPUT_TOKENS=1500,
  TIMEOUT_MS=30000,EVALUATED=true}`, `ANTHROPIC_API_KEY`, and a published notice naming
  `anthropic` for the `onboarding_plan` purpose (it also covers `onboarding_questions`). Whether
  run 1 is enough for `EVALUATED=true` is the owner's call. Rollback: unset
  `AI_ONBOARDING_PLAN_PROVIDER` / `AI_ONBOARDING_QUESTIONS_PROVIDER`; the old `ONBOARDING_PLAN_*`
  settings path runs again.
- **Not verified:** `index.ts` wiring (store methods over `AiBudget` and `get_ai_consent_v2`) is
  type-checked but has no test of its own; nothing ran against a database (no Colima); the real
  notice flow needs A7's notices; thinking `adaptive` was not evaluated.

### A5: daily decision on Claude

In review (branch `claude/a5-decision-claude`). Edge Functions only; no SQL, no app change.
Production does not change on merge: without `AI_DAILY_DECISION_*` settings coach-decide runs
today's path.

- **Three paths** (`_shared/providers/daily_decision_provider.ts`, `dailyDecisionPath()`):
  - `legacy`: `route("daily_decision")` is null. Today's path, unchanged: `COACH_MODEL_PROVIDER`,
    consent, `reserve_ai_budget` at the fixed ceiling, and
    the same failed-run provenance (the old `COACH_MODEL_PROVIDER` chain, moved verbatim into
    `failedRunProvenance`). The mock stays the default.
  - Consent on every path (privacy rule): data goes to a vendor only if the athlete's accepted
    current daily-coaching notice names it. With a configured DeepSeek, Groq or Gemini
    (`legacyDecisionVendor`, from `COACH_MODEL_PROVIDER`) the `legacy` path reads
    `get_ai_consent_v2` and a notice naming another vendor (Anthropic after cutover) gets the
    deterministic decision, nothing sent or reserved. A null provider counts as that vendor: A1
    added the column without a backfill, so today's production notice (vendor named only in
    `provider_label`) is null, and today's behaviour must stay byte-identical. The mock sends
    nothing and keeps `has_ai_coaching_consent`. An unusable or unevaluated route never falls
    back to the legacy provider, so it needs no vendor check.
  - `gateway`: a complete route with `AI_DAILY_DECISION_EVALUATED=true`. Consent comes from
    `get_ai_consent_v2` (`daily_decision`) and counts only when the current notice names the
    route's vendor; otherwise the deterministic decision answers (the consent-needed path) and
    nothing is sent. Budget: `reserve_ai_budget_v2("daily_decision", ceiling)`, ceiling from
    `decisionCeilingUsd` (whole prompt at a token per character at the higher of the input and
    cache-write price, plus `MAX_OUTPUT_TOKENS`; Sonnet 5.5 at 1,800 tokens is about USD 0.06).
    The run stores the vendor and the model that answered and `usage.costUsd`.
  - `unevaluated`: a route without `EVALUATED=true`. No consent read, no reservation, no model
    call; the deterministic decision answers. A route never silently falls back to DeepSeek.
- `GatewayDecisionProvider`: one stable system prompt (`decisionSystemPrompt`, `cache: true`;
  policy-to-action rules, evidence code reference, null contract, date rule, allowed gap codes,
  no model or company names) and the day's context in the user turn inside `<coaching_context>`.
  JSON via the gateway with today's `decisionSchema`; context cap 12,000 characters as today.
  Failures use today's code forms: `<vendor>_timeout`, `<vendor>_request_failed`,
  `<vendor>_request_failed_status_429`, `<vendor>_response_invalid`, plus `<vendor>_refused`.
  The eval router is refused (no notice names it).
- `parseCoachDecision` still runs on every path's output in coach-decide before anything is
  stored; a forbidden answer is a 503 `coaching_unavailable`, as today.
- Tests (`daily_decision_provider_test.ts`, 14): no-route parity (mock default; DeepSeek request
  byte for byte; consent, budget and provenance as today), unevaluated route sends nothing,
  vendor-checked consent, ceiling, the Claude request (cache mark, no sampling, nulls kept),
  failure mapping, router refused, D11 prompt check, and B0's property pattern on the gateway path
  (5 policies x 5 training x 5 nutrition actions x permitted/unpermitted evidence: nothing the
  policy forbids passes), grounding rules, the unusable-ceiling route. Deno suite: 505 passed,
  0 failed, 8 ignored.
- **Budget outcomes** (`failureSpend`, `DecisionCallError`, handler tests in
  `coach-decide/handler_test.ts`): on the gateway path a failure that cost nothing (consent
  mismatch, context too large, 429/503/529/HTTP errors with no usage, a rejected request)
  releases its place. A genuinely unknown spend (timeout, broken connection) and a billed
  answer that was then rejected keep the place open at its ceiling. The legacy path is unchanged
  (always keeps). **Contract request for A7/SQL:** a failed run has no cost column and daily
  coaching has no usage-event purpose, so a billed-then-rejected call cannot be settled at its
  real cost today; it counts at its ceiling until the reservation ages out.
- **Ceiling is never clamped:** `decisionCeilingUsd` is the real worst case. If it passes
  `maxReservableCeilingUsd` (USD 0.50, what `reserve_ai_budget_v2` accepts), the route is
  unusable: nothing is reserved or sent, the deterministic decision answers and
  `daily_decision_route_unusable` is logged. Tested with Opus at 32,000 output tokens.
- **Grounding** (`groundingFault`, run in coach-decide after `parseCoachDecision`, gateway path
  only): every number in the athlete-facing text must appear in the request's data (or in the
  evidence code reference thresholds), matched as whole numbers (`7.0` = `7`, `17` does not match
  `7`); no model or company names (D11); every `missing_data` gap the policy named stays in the
  answer. A fault takes the invalid-output path: deterministic decision, a failed run recorded
  with `ungrounded_number`, `names_model_or_company` or `missing_data_dropped`. The legacy
  DeepSeek path does not have this check and has the same gap (rule 8); closing it would change
  today's path and is left to the owner.
- **Eval** `_evals/daily_decision_eval.ts` (offline checks in `daily_decision_eval_test.ts`):
  13 synthetic days from `test/contract/fixtures/daily_computed_metrics.json` and variants,
  with evidence and policy derived by the SQL rules, plus the two policy cases of B0's tests; the
  deterministic decision is the recorded reference. Gates: 90% valid, every escalation escalates,
  zero unsupported numbers, no model or company names, every named gap kept (the same validator
  as production), p95 under 25 s. `EVAL_ATTEMPTS` retries transport failures only; the spend
  guard reserves the ceiling times `EVAL_ATTEMPTS` before each day against `EVAL_MAX_USD`; an
  attempt that fails with no usage (timeout, dropped connection) counts at its full ceiling and
  the report's `spend` then reads "at most $X" (`attempts_with_unknown_cost`). Runs (2026-10-15, Sonnet 5.5,
  thinking off, 1,800 tokens): first run 12/13 valid; the one rejection was an invented "10-15%"
  volume cut (`ungrounded_number`, gate failed). The prompt now says prescribed amounts
  (percentages, sets, minutes, calories) are described in words. Second run: 13/13 valid, 0
  unsupported numbers, 0 model names, 0 dropped gaps, both escalation days escalate, training
  action equals the deterministic reference on 8/13 and nutrition on 12/13, p50 5.0 s, p95 6.1 s,
  USD 0.118 for the run (about USD 0.009 a decision). Where the reference holds on GATHER_DATA
  (recovery below baseline, elevated load, low confidence, scores unavailable), the model
  proceeds with the plan and names the risk; both are allowed under `maintain_only` (owner
  call, see the PR). One 13-day run is a small sample; the grounding check is the safety net.
- **Cutover settings (A7):** `AI_DAILY_DECISION_PROVIDER=anthropic`,
  `AI_DAILY_DECISION_MODEL=claude-sonnet-5-5`, `AI_DAILY_DECISION_MAX_OUTPUT_TOKENS=1800`,
  `AI_DAILY_DECISION_TIMEOUT_MS=25000` (or more; see the eval latency),
  `AI_DAILY_DECISION_EVALUATED=true`, `ANTHROPIC_API_KEY`, and a published daily-coaching notice
  naming `anthropic`. Rollback: unset `AI_DAILY_DECISION_PROVIDER`.

### A6: Coach chat, cache-friendly

In review (branch `claude/a6-coach-chat-claude`). Merging changes nothing in production: with no
`AI_COACH_CHAT_*` settings `route("coach_chat")` is null and Coach chat sends today's DeepSeek
request byte for byte (`coach_chat_parity_test.ts` compares SHA-256 digests of 18 requests,
first and repair, recorded from the pre-A6 code).

- **Route path** (`coach-chat/index.ts`): the gateway is used only when `route("coach_chat")` returns a
  route with `EVALUATED=true`, the contributor registry passes `validateCoachContextContributors`
  (checked before any budget place is taken) and the first attempt can be reserved. Anything else
  takes today's DeepSeek path (`chooseCoachChatRoute`; a reason other than "no route" is logged as
  `coach_chat_route_not_used`: `not_evaluated` or `unreservable`). Consent through
  `get_ai_consent_v2`; the granted notice must name the route's vendor, else 403
  `ai_consent_required` and nothing is sent. Provenance stores the vendor and the model the
  provider reports. Logs add `ai_path` (`gateway`/`legacy`).
- **Budget, one place per attempt** (`coach-chat/budget_ledger.ts`): every request sent is covered
  by a `reserve_ai_budget_v2` place at its own worst case (whole prompt written to the cache at
  1.5 characters per token plus every output token, at list price). The first attempt reserves the
  largest prompt any turn can send before the turn starts (Haiku 0.014, Sonnet 0.281 USD; a refusal
  is the existing 429 `ai_usage_limit`). A repair reserves from its own prompt before it is sent;
  if that is refused (or over USD 0.50) nothing is sent and the first attempt's failure code
  stands (`repair_skipped` in the failure log). A route whose first attempt would exceed USD 0.50
  (for example Sonnet with 32,000 output tokens) is unusable and takes today's path, logged.
  `AiBudget` has no per-place call, so the ledger holds one `AiBudget` per attempt and the first
  attempt's place stays open while the repair reserves (its real cost reaches the database only
  when the turn ends); this can only over-count. At the end every place is settled except one
  kept: a sent request that timed out with no usage reported (`inFlight`). A deadline that passes
  before the repair, a refused repair place and a failure whose cost is recorded settle all places
  (the earlier code kept the place for every `provider_timeout`, which double-charged). A failure
  that could not be recorded, or that was not the provider's outcome, keeps every place. Today's
  path keeps its single place on a timeout, as before.
- **Timeout**: each attempt waits for `route.timeoutMs`, cut to what is left of the 40 s total
  deadline (`coachChatTiming.totalDeadlineMs`). The app waits 45 s for coach-chat
  (`coach_repository.dart`), so the deadline stays at 40 s. A route timeout over 40 s (routes
  accept up to 150 s) is clamped to the deadline and logged as `coach_chat_route_timeout_clamped`;
  it is not treated as invalid.
- **Prompt** (`_shared/providers/coach_chat_provider_gateway.ts`): system = rules and answer
  contract; user block 1 = athlete file without conversation memory plus stable contributors
  (`cache: true`); block 2 = memory, omitted-sections line, volatile contributors; block 3 = the
  question; a repair adds its instruction last, so it reuses the cache. `renderCoachContextParts`
  splits the one rendering; layout in `docs/CONTEXT_BUDGET.md`.
- **Schema**: structure only (types, enums, closed objects; nullable evidence id as `anyOf` with
  null). `parseCoachChatAnswer` checks limits and citations with the exact rule, so a repair
  carries the rule and the candidate (the gateway returns no text for a schema failure, so that
  repair goes without one).
- **Failures** map to today's codes: rate limit → `provider_rate_limited` (retry-after, else 60),
  timeout → `provider_timeout`, overloaded/network/provider error → `provider_http_error`,
  refusal → `provider_response_invalid` (no repair), output-limit cut → `provider_response_truncated`.
  Every attempt's priced cost goes into `persist_failed_coach_chat_run_v2`.
- **Contract 7 host** (`_shared/coach_context/host.ts`, `registry.ts`, empty): fixed registry order,
  ids `^[a-z][a-z0-9_]{0,39}$`, budget 1–12,000 characters, each block clipped and wrapped in
  `<reference_data source="id">` with the reference-data line; a closing tag inside text is
  escaped; a contributor that throws, returns nothing or takes over 4 s is left out and logged
  (`coach_context_contributors`). Contributors render only on the gateway path.
- **Thinking** comes from the route for every question (the legacy path thinks only for plan
  changes; a route cannot vary it per question).
- **Eval** (`_evals/coach_chat_eval.ts`): with `AI_COACH_CHAT_*` set it runs the gateway path,
  asks one question twice and gates on the second `ai_call` line's cache reads, caps spend with
  `EVAL_MAX_USD`, and reruns a call the host slept through (monotonic vs wall clock).
  Results 2026-10-15 (4,096 output tokens, 30 s timeout, synthetic athletes; first direct
  baseline, as no direct DeepSeek run is recorded):

  | Model | Runs | Model answers | Safety | Unpermitted evidence | p50 / p95 | USD per answer | Cache reads |
  |---|---|---|---|---|---|---|---|
  | Haiku 5.5 | 180 | 100% | 18/18 | 0 | 4.5 / 7.0 s | 0.00045 | 97.6% of prompt tokens |
  | Sonnet 5.5 | 120 (sampled) | 100% | 6/6 | 0 | 8.6 / 12.3 s | 0.0110 | 96.5% |

  Cache proof (rich athlete, same question twice): first call writes 8,012 tokens, second reads
  8,012. Clarifying question when a detail was missing: Haiku 0/6, Sonnet 2/4 (reported, not
  gated). Recommendation: Haiku 5.5 (every gate, about 25 times cheaper and twice as fast);
  Sonnet 5.5 is the settings-only upgrade if the owner wants more clarifying questions.
- **Fallback consent** (privacy rule): whenever the route is not used (no route, `EVALUATED=false`, over USD 0.50, unknown model, or the D1 rollback), today's provider is DeepSeek, Groq or Gemini (`legacyCoachChatVendor`, from `COACH_MODEL_PROVIDER`), so the current Coach notice must name that vendor (`get_ai_consent_v2`); a notice naming another vendor (Anthropic after cutover) answers 403 `ai_consent_required`, with nothing sent and nothing reserved. A null provider counts as the legacy vendor: A1 added the column without a backfill, so every notice published before A1 (today's production notice, which names its vendor only in `provider_label`) is null, and today's behaviour must stay byte-identical. Mock or unconfigured providers send nothing and keep the generic consent check.
- **For A7**: suggested settings `AI_COACH_CHAT_PROVIDER=anthropic`, `MODEL=claude-haiku-5-5`,
  `MAX_OUTPUT_TOKENS=4096`, `TIMEOUT_MS=30000`, `EVALUATED=true`. With `EVALUATED` not `true`
  Coach chat behaves as if there were no route (today's path). Without an Anthropic-named Coach
  notice granted, every turn returns 403.
  The app shows "AI" for provider `anthropic` (`aiProviderDisplayName` returns null).

### A7: wording, budgets, cutover

**State (2026-10-16): in review.** Built on `claude/p2-kickoff`; the authority-doc edits assume A3-A6
are merged first (the program's merge order), because they describe the gateway as in use.
Nothing here changes production by itself except migration code 17 (the budget stops).

- **D11 app wording.** No model or company name outside a consent notice.
  - `lib/shared/ai_provider_names.dart` holds only `aiProvenanceLine` ("checked by Tracend"); the
    display-name map and `aiProviderDisplayName` are gone.
  - `aiAnswerLabel(provider:, model:)` reads "AI answer · checked by Tracend" for a reply a model
    wrote and "Tracend safety answer · not AI" / "Tracend answer · not AI" for a deterministic or
    mock reply (provider `mock`, model `deterministic-safety-v1`, or `deterministic`); the onboarding
    proposal chip reads "Proposed by AI · checked by Tracend" (`OnboardingProposalView.provenanceLabel` is a
    constant now).
  - `PhotoProgressCard` takes `physiqueCheckAvailable` (bool) in place of `photoCheckProvider`; the
    card says "Sent to AI only when you start a physique check". `PhysiqueCheckRepository.loadProvider`
    still returns the server's `provider_label` (old servers send it); the app only tests it for null.
  - Two cards outside A7's file list named the notice's company and now say "an AI service"
    (`coach_screen.dart`, the "AI coaching is off" card) and "AI" (`account_screen.dart`, "On · AI
    writes Coach answers"). One-line edits, flagged in the PR; `coach_message_bubble.dart` changed
    its `aiAnswerLabel` call and a comment.
  - **No built-in notice.** `AiNotice.builtIn` and `aiCoachingNoticeVersion` are gone. The app shows
    only the notice it fetched (`get_current_ai_notice`) and never records a grant for a version it
    did not fetch: a failed call is `AiNoticeUnavailable` (`loadCurrentAiNotice`). **A notice
    failure never blocks the signed-in app:** `AiCoachingConsentController.load` treats it as "AI
    unavailable" (choice undecided, no notice), `Phase2Gate` opens the app with AI coaching off and
    shows the consent screen only when a notice loaded, and only the AI surfaces (consent screen,
    Coach and Account sheet, onboarding AI step) show "The AI coaching notice could not be loaded…"
    with **Try again** and no answer buttons
    (`AiCoachingNoticeSection`). The fixture repository (tests only) has a neutral notice naming no
    company. `lib/features/onboarding/onboarding_flow.dart` changed for this (out-of-list edit) and
    its AI choice card no longer says an AI model drafts the starting plan. With no notice the AI
    step lets onboarding continue without recording anything (AI off, the rules plan).
  - **Own-photo check before the vision routes** (review fix). `supabase/functions/_evals/owner_photo_check.ts`
    sends the owner's own photos through the features' own request (`analyzeMealWithGateway`,
    `handlePhysiqueCheck`) and prints the parsed results; the runbook (3.3, 3.4) runs it and the
    owner judges it before any `AI_*_VISION_EVALUATED=true` is set. AI_SAFETY_SPEC §8 and §9 describe it.
    The script imports A3's `meal-analyze/vision.ts` and the gateway physique path (#119), so it is
    added to this branch in a commit made after #119 is in `main` (it could not compile before);
    it is written and its offline test (fake folder and fake fetch) passes against #119's code.
  - Tests: `test/ai_wording_test.dart` renders Coach replies stored by deepseek, groq, gemini and
    anthropic plus the photo card and greps the rendered text for model and company names. Not in
    A7's scope and still naming providers: the App Store mock-ups in `design/store/`, and test
    fixtures of old notices.
- **Notice drafts** in `docs/notices/` (v6 says plainly that AI starting plans are not on yet and
  that a plan or plan change needs the athlete's approval, not every answer): `ai-coaching-v6.md`, `meal-photo-ai-v2.md`,
  `progress-photo-ai-v2.md`. Each has the exact five-argument publisher call (dollar-quoted body)
  and a check query. Not published. Anthropic is named once per notice; retention is "deleted within
  30 days, not used for training, longer only where the law requires or to enforce its usage rules",
  verified 2026-10-16 on privacy.claude.com ("How long do you store my organization's data?"; its
  safety systems may keep a flagged input up to 2 years, which the notices leave out). The photo
  publishers' `model` argument is a stored field the app never shows.
- **Migration code 17** `20261016004017_ai_budget_phase2.sql`: adds `per_person_monthly_usd` to
  `private.ai_budget_limits` (default 2), sets it to 3 and the global stop to 50, and re-creates
  `reserve_ai_budget`, `reserve_ai_budget_v2`, `assert_owner_ai_budget` and `get_my_ai_budget_state`
  to read it (same signatures, grants and error messages; the state keeps every field, and its
  values follow the stop: warning 1.5, hard stop 3). No per-feature setting is needed. pgTAP:
  `supabase/tests/database/ai_budget_phase2_test.sql`; four older tests pin the stop to 2 at their
  start because they test its mechanics at USD 2. **Not run locally (no Docker); CI pgTAP is the
  proof.** The USD 50 global stop is marked "confirm at cutover" in the runbook.
- **Migration code 17, part 2 (same file):** backfills `provider` on every existing row of
  `ai_consent_notices`, `photo_ai_notices` and `meal_photo_ai_notices` with
  `private.notice_vendor_from_label(label, model)` (DeepSeek → deepseek, Groq/Qwen → groq,
  Gemini/Google → gemini, Anthropic/Claude → anthropic; raises 22023 when it finds none or two), and
  makes the four-argument `private.publish_ai_notice` and `private.publish_photo_ai_notice` refuse
  (22023, pointing to the five-argument form; same signatures and grants). The legacy "null or
  matching" rule then behaves as before, and no new null-provider notice can be published. Tests
  that used the old publishers (`onboarding_plan_v2`, `onboarding_review_fixes`, `physique_check`,
  `provider_neutral_ai`) now use the five-argument form; `provider_neutral_ai_test.sql` expects
  `deepseek` and `groq` where it expected null.
- **`_shared/ai_consent.ts`** takes its vendor list from the gateway (`aiVendors` without
  `router`; type `AthleteVendor`). It still exports `AiVendor` as an alias, because A5's
  `daily_decision_provider.ts` imports that name from here. Behaviour is unchanged; the test now
  also feeds `router` as a notice vendor (null).
- **Authority docs** (AI_SAFETY_SPEC §8-§10, COST_MODEL §1-§4, ARCHITECTURE §3.7, SECURITY_PRIVACY
  §3 and §6, PRD §5.8) describe the gateway, the per-feature routes, today's providers (live until
  the cutover) and the cutover plan. AI_SAFETY_SPEC §10.5's "no Edge Function imports it yet" is
  gone. `docs/PROGRESS_CONTEXT.md` still says USD 2 and USD 10 on two lines; it is the lead's file.
- **Runbook** `docs/runbooks/phase2-claude-cutover.md`: merge and deploy, install the app, publish
  the notices, athletes re-accept, set the routes one feature at a time (Coach chat, daily decision,
  meal photo, physique), verify, onboarding later (after B2), the 2-week rollback by settings with
  the consent republish it needs, and dropping DeepSeek and Groq from the privacy list after the
  windows. Every step is the owner's.
- **Things to know.**
  - Fail closed (lead, after the A4-A6 fixes): data goes only to the vendor named by the notice
    the athlete accepted. Cutover order per feature group: route (`EVALUATED=true`), then publish
    the Anthropic notice, then athletes accept; in between the feature degrades safely (Coach
    "consent required", rules for the decision and plan, meal photos unavailable). The runbook
    explains the short window either way.
  - Rollback is two steps: unsetting the settings stops Anthropic but does NOT send traffic back to
    DeepSeek or Groq (the old paths refuse while the notice names Anthropic); restoring them means
    republishing a notice naming that vendor and athletes accepting it.
  - `ai-coaching-v6` covers `onboarding_plan`, so onboarding uses its rules plan from publication
    until its route is set after B2; DeepSeek then receives nothing, and the owner may prefer to
    delay publishing v6 (runbook 4a).
  - The program README's A7 brief says "the four files in the decisions log"; it does not list all
    six wording files. The owner table does (`ai_provider_names.dart`, `consent/**`,
    `coach_labels.dart`, `onboarding_proposal_view.dart`, `photo_widgets.dart`,
    `progress_screen.dart`). The lead is fixing the brief in #116; A7 changed all six, and README
    is untouched here.
  - Final live evals were not rerun here: A3-A6 recorded theirs (their handoff sections); A7 added
    no model code.

### A9: Coach safety and honesty guardrails (server half)

Branch `claude/a9-coach-guardrails`. The app half (plain error messages, local dates, the no-plan
chat mode and the budget gates, migration code 19) is the parallel branch
`claude/a9-coach-app-errors` and owns `lib/features/coach/**`. This half changes no SQL and no
frozen function (`prepare_coach_chat_v8`, `build_coach_athlete_context`). Findings are from the Coach
audit (1, 2, 3, 6 deterministic part, 7, 15).

- **Red-flag screen before the model** (`_shared/coach_safety/red_flags.ts`, `referrals.ts`;
  AI_SAFETY_SPEC §7). Replaces the five-keyword `deterministicBoundary` (removed). It runs in
  `coach-chat/index.ts` before consent and the budget reservation (a hit sends nothing, so it needs
  no consent and takes no budget place, and contributors are not rendered), and again inside
  `generateCoachChat` and `generateCoachChatViaGateway` with the context, where today's check-in
  adds the `escalate` outcome (pain 7 or more, `CHECK_IN_SAFETY_ESCALATION`) for training
  questions. A hit is stored like the old boundary reply (provider `mock`, model
  `deterministic-safety-v1`, 0 tokens, USD 0; the app labels it "Tracend safety answer · not AI")
  with `safety_state: limited` (`refused` for self-harm and unsupported requests). The log line is
  `coach_chat_red_flag` with category, rule and source, never the message. Negation, conditionals
  and educational questions are skipped; `red_flags_test.ts` holds 72 reported messages and 51
  ordinary ones. The fallback screen (`mayConcernHealthRisk`) now includes this screen.
  Eval prompts: only the six `safety-*` prompts hit; the other 54 reach the model.
- **Safe Ranges** (`safe_ranges.ts`): calorie floor (new `calorieFloorKcal` in
  `onboarding/policy.ts`, the same math `nutritionPolicy` uses; `sexFloorKcal` is now exported),
  weekly loss ceiling (1% of body weight), healthy-weight floor (BMI 18.5), longest cut (16 weeks)
  and the pain line, rendered in the athlete file after the profile (about 700 characters).
- **Screening contributor** (`coach_context/contributors/screening.ts`, stable, 900 characters,
  registered first). Reads the newest `onboarding_screenings` row with the service role. The reply
  guard reads the outcome back from the rendered block (`screeningOutcomeIn`), so the model and the
  guard use one value.
- **Reply guard** (`reply_guard.ts`, `numbers_check.ts`): five new validation rules
  (`calories_below_floor`, `loss_rate_above_ceiling`, `effort_above_screening_cap`,
  `claimed_action`, `numbers_not_grounded`) next to B7's two. `CoachChatAnswerCheck` may now
  return `{rule, rules, detail, count}`: `rules` lets one repair name every broken rule, `detail`
  (the unsupported figures) goes into the repair instruction only, and `count` is logged as
  `actual`. Telemetry and failure metadata carry rule names (`rule`, `also_rules`) and counts, never
  figures. The check is enforcing from the first deploy. **Measure it:** in the Edge Function logs
  count `coach_chat_complete` attempts with `rule: "numbers_not_grounded"` against all turns, and
  `coach_chat_failure` with `initial_rule` or `repair_rule` `numbers_not_grounded` (a turn that
  fell back to the data summary). If the repaired-turn rate is high, loosen the allow-list in
  `numbers_check.ts` (`mustBeGrounded`) rather than switching the check off.
- **Prompt**: new persona lines (red flags arrive pre-screened, the Safe Ranges, the screening
  rule) and a stricter numbers line; the instructions grew from 7,265 to 8,582 characters.
  **The legacy request digests in `coach_chat_parity_test.ts` were recorded again on purpose**
  (persona, answer contract and the Safe Ranges section changed the request).
- **Second route** (`coach_chat_provider_route.ts`; `coach_chat_strong` added to `aiFeatures`):
  a rules classifier sends progress, body-weight and goal, nutrition-number and plan questions to
  `AI_COACH_CHAT_STRONG_*` when it is set and `EVALUATED=true`, its reservation fits one budget
  place (Sonnet 5.5 at 4,096 output tokens does) and the athlete's accepted notice names its
  vendor; otherwise the default route answers (`coach_chat_strong_route_not_used` is logged for the
  vendor case). Reservation, price and stored provenance follow the route that answers. Logs add
  `route_feature`. Owner action: the runbook's step 3.1b.
- **Plan status** (`renderPlanStatus` in `coach_chat_provider.ts`): when the chat context's
  `plan_status` (app half, migration code 19) says there is no active plan or no nutrition target, the
  athlete file gets a required "Plan Status" section after the Safe Ranges: no plan, the reason
  (`no_approved_plan` or `see_professional`), the health-check outcome and date, and "no
  plan-specific advice; general answers and next steps are fine". `active_plan` is null for these
  athletes, so no plan section renders. A context without `plan_status` renders as before.
- **Order of a request**: consent, then a cheap replay lookup (the saved question for the key, then
  `coach_chat_turn`), then the budget reservation, then the heavy `prepare_coach_chat_v8`. A retry of
  a finished turn is answered from its stored reply with no budget place and no context work, so it
  works at the monthly limit; an athlete at the limit gets 429 without triggering context
  preparation or snapshot writes with each new key. (`prepare` still reports a replay that raced in
  between.) The pain-7 check-in screen stays ahead of consent and budget.
- **429 reason**: `{error: "ai_usage_limit", reason}` with `monthly_cost_limit`, `daily_rate_limit`
  or `global_monthly_cost_limit`, read from the database's refusal (`AiBudget.refusal`,
  `CoachChatBudgetLedger.refusal`); no `reason` when the database gave none.
- **Lost turns**: a turn with no answer and no failure whose saved question is older than
  `coachChatTurnStaleAfterMs` (the 40 s model deadline plus 30 s, 70 s) answers 503
  `chat_unavailable` with `code: "turn_lost"` and `replayed: true`, for that key every time. The
  app should show "your last message didn't go through" and send it again under a new key (no SQL
  change; the age is the question row's `created_at`). Younger turns, or an age that cannot be read,
  still answer 409 `chat_in_progress`. `handler_test.ts` runs the real handler against a fake client.
- **Review fixes (Codex, 7 safety fail-opens), all with tests:** (1) the check-in escalation is
  read from `daily_check_ins` and decided before the consent and budget gates (`screenTodaysCheckIn`);
  (2) a negation ends at contrast words and clause punctuation, and crosses a comma only into a short
  symptom list; (3) `see_professional` blocks every training prescription, and "keep HIIT moderate"
  fails `moderate_until_cleared` (only a prohibition exempts a vigorous word);
  (4) `parseCoachChatAnswer` runs the check once over every visible field (answer, follow-ups,
  missing data, evidence labels, reasoning chain); the new rule `training_advice_on_pain_day`
  stops training advice in any field on a pain-7 day; (5) a year-like number with a unit or an
  amount word is a measurement; (6) the calorie floor exempts only a limit word or judgement that
  governs the figure, and meal or burn words only when they govern it; (7) a failed, slow or
  unreadable screening lookup renders "Outcome: unknown" (restricted like `moderate_until_cleared`)
  and `screeningStateOf` also reads the host's failed or timed-out report.
- **Fresh-key retry** (`coach-chat/superseded.ts`): when the context's memory holds an unanswered
  copy of the question being asked, the handler asks `coach_chat_turn` about each earlier same-text
  attempt and sets `safety_state = 'unavailable'` on the user row of those that failed, were lost
  (still open past `coachChatTurnStaleAfterMs`, the `turn_lost` rule; a running turn is never
  touched) or only got a data summary. The rows are chosen in code (`earlierAttempts`): NULL
  `safety_state` and untrimmed text count, and removes the unanswered copies from `recent_messages` before the
  model sees them. No SQL. **For the app:** hide user messages with `safety_state = 'unavailable'`
  in the thread (a marked row is a failed attempt the retry replaced).
- **Exemption rule (second review):** every exemption (negation, conditional, educational,
  prohibition, warning, decline, description of the athlete's past) must provably govern its
  match: same clause, short window before it, no `and`/`but`/comma between (clauses are cut by
  `clausesOf` in `reply_guard.ts` and `clausesOf`/`stretchBefore` in `red_flags.ts`); a possessive or
  self-report defeats the conditional/educational skips; a bare "if" is no longer a conditional.
  `exemptions_adversarial_test.ts` is the table (message or reply, expected hit or pass) every new
  exemption must be added to. A negated list across a comma ("no chest pain, dizziness or
  fainting") is now a hit: a false referral is cheap.
- **Superseded memory on every turn** (`withoutSupersededMemory`): see the spec; the retry-turn
  cleanup (`withoutSupersededQuestions`) stays for the current question.
- **Coaching principles digest**: registered first in `coach_context/registry.ts` (stable, cached
  block); persona line added; legacy parity digests recorded again on purpose.
- **Open**: the sets and reps a coach prescribes as advice are not checked (see the spec);
  sentences claiming an action that the model words in an unusual way will pass the regexes (the
  persona rule is the main defence); `prepare_coach_chat_v8` still raises for an athlete with no
  active plan, so a red-flag message from the athlete who most needs it gets the app half's no-plan
  chat mode, not a referral, until that lands.

## Next agent starts here

Phase 2: A3, A5 and A6 start first, A4 next, A7 after A3–A6 merge. Briefs and file owners are in
the program doc.
