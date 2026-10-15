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

No chunk of this stream has merged yet.

### A2: gateway module (review, branch `claude/a2-ai-gateway`)

`supabase/functions/_shared/ai/` implements Contract 1. No feature calls it yet; nothing outside
the folder changed.

- `types.ts`: the Contract 1 types.
- `routes.ts`: `route(feature, env)` reads `AI_<FEATURE>_*` and the provider key. Required:
  `PROVIDER`, `MODEL`, `MAX_OUTPUT_TOKENS` (1–128,000), `TIMEOUT_MS` (1,000–600,000) and the key;
  `BASE_URL` too for `openai_compatible`. `THINKING` defaults to `off`, `EVALUATED` to `false`,
  `EFFORT` to the model's default. Any missing or invalid value returns `null`. The key stays off
  the route object (a `WeakMap`), so only a route from `route()` can send. Gemini also needs
  `GEMINI_PAID_DATA_TERMS_ACCEPTED=true` (AI_SAFETY_SPEC §10).
- `models.ts`: the price and capability table. Claude Haiku/Sonnet/Opus 5.5 at the 2026-10-15
  list prices (cache writes at the 5-minute rate; Haiku's over-100K card counts cache tokens
  toward the threshold), plus the rollback models `deepseek-flash`, `deepseek-v4-flash`,
  `qwen/qwen3.8-27b` and `gemini-3.5-flash`. A model not in the table has no price, so it has no
  route. An `openai_compatible` model is tied to its provider's host.
- Thinking "off" per model: Haiku 5.5 `{type: "disabled"}`, Sonnet 5.5 `{type: "between_tools"}`,
  Opus 5.5 no field (thinking cannot be turned off). DeepSeek off/on as the live Coach sends it;
  Qwen on Groq has no thinking mode (adaptive is refused); Gemini off = `thinkingLevel: "low"`.
- `gateway.ts`: `call()` refuses before sending on a consent mismatch, a route without a key, an
  assistant-last conversation (Claude 5 rejects prefill), images where the model or role cannot
  take them, or a JSON schema the checker cannot enforce (`json_schema.ts`). One request, timeout
  and caller `AbortSignal` both end it as `timeout`. 429 → `rate_limited` (with `retry-after`),
  529/503 → `overloaded`, other HTTP errors → `provider_error` (error bodies are never read).
  Every answer that arrived returns its priced usage, also on `refused`, `invalid_output` and an
  empty answer.
- `adapters/anthropic.ts`: Messages API, no `temperature`/`top_p`/`top_k`/`tools`/`tool_choice`;
  JSON via `output_config.format` (`json_schema`) with the limits Claude rejects (`maxLength`,
  `minimum`, `maxItems`, ...) stripped and objects closed; the gateway still checks the full
  schema on the answer. `cache: true` becomes `cache_control: {type: "ephemeral"}` (at most 4).
- `adapters/openai_compatible.ts` (DeepSeek, Groq): JSON mode, images as data URLs, cache hits
  from `prompt_cache_hit_tokens` or `prompt_tokens_details.cached_tokens`.
- `adapters/gemini.ts`: `responseJsonSchema`, thought parts skipped, thought tokens billed as output.
- `log.ts`: one `ai_call` line (feature, provider, model, outcome, four token counts, cost,
  latency, HTTP status, stop); never prompt, image, reply or error text.
- Tests: 52 offline tests with a fake fetch (`fakes.ts`); no network.

Open: the consent check compares provider kinds only (contract request in the program README).

## Next agent starts here

Take the first `todo` chunk of this stream from the program board whose dependencies are merged.
