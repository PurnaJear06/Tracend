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

Not started. The A4 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

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

Not started. The A6 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

### A7: wording, budgets, cutover

Not started. The A7 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

## Next agent starts here

Phase 2: A3, A5 and A6 start first, A4 next, A7 after A3–A6 merge. Briefs and file owners are in
the program doc.
