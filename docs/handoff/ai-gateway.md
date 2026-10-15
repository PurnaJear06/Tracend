# AI Gateway Handoff

**As of:** 2026-10-15

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

Every AI call goes through one provider-neutral gateway (Contract 1). Claude Haiku 5.5 and Sonnet 5.5 replace DeepSeek and Groq at cutover; the old routes stay available by settings for two weeks.

## Chunks

A1, A2 (Phase 1); A3–A7 (Phase 2)

## State

A1 (#103) and A2 (#106) are live (2026-10-15).

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

Not started. The A3 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

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

Not started. The A5 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

### A6: Coach chat, cache-friendly

Not started. The A6 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

### A7: wording, budgets, cutover

Not started. The A7 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

## Next agent starts here

Phase 2: A3, A5 and A6 start first, A4 next, A7 after A3–A6 merge. Briefs and file owners are in
the program doc.
