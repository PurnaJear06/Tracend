import type { AiEffort, AiProvider, AiThinking } from "./types.ts";

// The one price and capability table for the AI gateway. A model that is not
// here has no known price, so route() refuses it: an unknown price would let
// the budget count a call as free.
//
// Prices are list prices in USD per million tokens.
// Claude: https://platform.claude.com/docs/en/about-claude/pricing, read
// 2026-10-15. Cache writes use the 5-minute rate: the gateway only marks
// `cache_control: {type: "ephemeral"}`, whose default lifetime is 5 minutes.

export type TokenPrice = Readonly<{
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
}>;

export type ModelPrice =
  & TokenPrice
  & Readonly<{
    /**
     * A higher rate card for long prompts. The prompt counts every input token,
     * cache reads and writes included, and each request is priced on its own.
     */
    longPrompt?: TokenPrice & Readonly<{ aboveTokens: number }>;
  }>;

/**
 * What the request sends for thinking "off" on a Claude model:
 * - disabled: `thinking: {type: "disabled"}` (Haiku 5.5, accepted at effort high or below);
 * - between_tools: `thinking: {type: "between_tools"}`, the lowest mode on Sonnet 5.5, where
 *   "disabled" returns 400 (accepted at effort high or below, with no other thinking field);
 * - always_on: no `thinking` field; Opus 5.5 rejects every way of turning thinking off, so "off"
 *   runs adaptive thinking at the route's effort.
 * Every effort the gateway accepts (low, medium, high) is within those limits.
 */
export type AnthropicThinkingOff = "disabled" | "between_tools" | "always_on";

type ModelBase = Readonly<{
  /** Shown in notices and logs. */
  label: string;
  price: ModelPrice;
  images: boolean;
  /** Efforts this model accepts; an empty list means the route must not set one. */
  efforts: readonly AiEffort[];
}>;

export type AnthropicModel =
  & ModelBase
  & Readonly<{
    provider: "anthropic";
    thinkingOff: AnthropicThinkingOff;
  }>;

export type OpenAiCompatibleModel =
  & ModelBase
  & Readonly<{
    provider: "openai_compatible";
    /** Hosts allowed in AI_<FEATURE>_BASE_URL: the athlete agreed to this provider, not a router. */
    hosts: readonly string[];
    /** The request field that limits output tokens. */
    maxTokensField: "max_tokens" | "max_completion_tokens";
    /** Request fields per thinking setting; null when the model has no such mode. */
    thinking: Readonly<Record<AiThinking, Record<string, unknown> | null>>;
  }>;

export type GeminiModel =
  & ModelBase
  & Readonly<{
    provider: "gemini";
    /** generationConfig.thinkingConfig.thinkingLevel for thinking "off". */
    thinkingOffLevel: AiEffort;
  }>;

export type ModelSpec = AnthropicModel | OpenAiCompatibleModel | GeminiModel;

const claudeLabel = "Claude (Anthropic)";
const allEfforts: readonly AiEffort[] = ["low", "medium", "high"];

// DeepSeek-V4.1-Flash peak list prices from 2026-09-10 (docs/COST_MODEL.md): 0.30 cache-miss
// input, 0.006 cache-hit input, 1.20 output. Peak prices, so the budget never undercounts.
// DeepSeek charges no cache write; a write is an ordinary cache miss.
const deepseekFlashPeak: ModelPrice = {
  input: 0.3,
  output: 1.2,
  cacheRead: 0.006,
  cacheWrite: 0.3,
};

const deepseekFlash: OpenAiCompatibleModel = {
  provider: "openai_compatible",
  label: "DeepSeek",
  price: deepseekFlashPeak,
  images: false,
  // reasoning_effort "high" is the only value the live DeepSeek calls have used.
  efforts: ["high"],
  hosts: ["api.deepseek.com"],
  maxTokensField: "max_tokens",
  thinking: {
    // V4 thinks by default; live decision requests without this failed after about 17 s.
    off: { thinking: { type: "disabled" } },
    adaptive: { thinking: { type: "enabled" }, reasoning_effort: "high" },
  },
};

export const models: Readonly<Record<string, ModelSpec>> = {
  "claude-haiku-5-5": {
    provider: "anthropic",
    label: claudeLabel,
    price: {
      input: 0.1,
      output: 0.5,
      cacheRead: 0.01,
      cacheWrite: 0.125,
      longPrompt: {
        aboveTokens: 100_000,
        input: 0.5,
        output: 2.5,
        cacheRead: 0.05,
        cacheWrite: 0.625,
      },
    },
    images: true,
    efforts: allEfforts,
    thinkingOff: "disabled",
  },
  "claude-sonnet-5-5": {
    provider: "anthropic",
    label: claudeLabel,
    price: { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 },
    images: true,
    efforts: allEfforts,
    thinkingOff: "between_tools",
  },
  "claude-opus-5-5": {
    provider: "anthropic",
    label: claudeLabel,
    price: { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
    images: true,
    efforts: allEfforts,
    thinkingOff: "always_on",
  },
  // Both DeepSeek names serve V4.1 Flash (providers/deepseek_models.ts).
  "deepseek-flash": deepseekFlash,
  "deepseek-v4-flash": deepseekFlash,
  "qwen/qwen3.8-27b": {
    provider: "openai_compatible",
    label: "Qwen (Groq)",
    // Groq's paid price (providers/groq_meal_vision_provider.ts). No cache discount is
    // verified, so cached tokens are counted at the full input price.
    price: { input: 0.8, output: 4, cacheRead: 0.8, cacheWrite: 0.8 },
    images: true,
    efforts: [],
    hosts: ["api.groq.com"],
    maxTokensField: "max_completion_tokens",
    // Groq refused this model's request with reasoning options on the free tier
    // (2026-09-30), so the working request sends none and has no thinking mode.
    thinking: { off: {}, adaptive: null },
  },
  "gemini-3.5-flash": {
    provider: "gemini",
    label: "Gemini (Google)",
    // Paid standard rate of 2026-07-04 (docs/COST_MODEL.md). No cache discount is verified,
    // so cached tokens are counted at the full input price.
    price: { input: 1.5, output: 9, cacheRead: 1.5, cacheWrite: 1.5 },
    images: true,
    efforts: allEfforts,
    // The lowest level the Gemini routes have used (meal photos).
    thinkingOffLevel: "low",
  },
};

export function modelSpec(provider: AiProvider, model: string): ModelSpec | null {
  const spec = Object.hasOwn(models, model) ? models[model] : undefined;
  return spec?.provider === provider ? spec : null;
}

export type TokenCounts = Readonly<{
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}>;

/** List-price cost of one call, rounded to a billionth of a dollar. */
export function costUsd(price: ModelPrice, tokens: TokenCounts): number {
  const prompt = tokens.inputTokens + tokens.cacheReadTokens + tokens.cacheWriteTokens;
  const rates = price.longPrompt && prompt > price.longPrompt.aboveTokens
    ? price.longPrompt
    : price;
  const micro = tokens.inputTokens * rates.input + tokens.outputTokens * rates.output +
    tokens.cacheReadTokens * rates.cacheRead + tokens.cacheWriteTokens * rates.cacheWrite;
  return Math.round(micro * 1_000) / 1_000_000_000;
}
