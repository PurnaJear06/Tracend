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

Not started. The A4 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

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
