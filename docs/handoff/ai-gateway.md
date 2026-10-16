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

Not started. The A7 builder replaces this paragraph with its state, files, tests and
anything the next agent must know.

## Next agent starts here

Phase 2: A3, A5 and A6 start first, A4 next, A7 after A3–A6 merge. Briefs and file owners are in
the program doc.
