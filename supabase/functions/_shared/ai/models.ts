import type { AiEffort, AiProvider, AiThinking, AiVendor } from "./types.ts";

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

/** Vendors that receive athlete data. "router" receives synthetic eval data only. */
export type AthleteVendor = Exclude<AiVendor, "router">;

/**
 * Company names shown in notices (D11: never a model name). No notice names the router, so
 * its label only appears in eval logs.
 */
export const vendorLabels: Readonly<Record<AiVendor, string>> = {
  anthropic: "Anthropic",
  deepseek: "DeepSeek",
  groq: "Groq",
  gemini: "Google",
  router: "Evaluation router",
};

/** The only hosts an athlete-data OpenAI-compatible vendor is reached on. */
export const vendorHosts: Readonly<Partial<Record<AthleteVendor, readonly string[]>>> = {
  deepseek: ["api.deepseek.com"],
  groq: ["api.groq.com"],
};

/**
 * What the request sends for thinking "off" on a Claude model, or null when the model cannot
 * turn thinking off (route() then refuses THINKING=off):
 * - disabled: `thinking: {type: "disabled"}` (Haiku 5.5, accepted at effort high or below);
 * - between_tools: `thinking: {type: "between_tools"}`, the lowest mode on Sonnet 5.5, where
 *   "disabled" returns 400 (accepted at effort high or below, with no other thinking field);
 * - null: Opus 5.5 rejects every way of turning thinking off.
 * Every effort the gateway accepts (low, medium, high) is within those limits.
 */
export type AnthropicThinkingOff = "disabled" | "between_tools" | null;

type ModelBase = Readonly<{
  vendor: AthleteVendor;
  price: ModelPrice;
  /** Largest decoded JPEG the model takes, in bytes; 0 = no image input. */
  maxImageBytes: number;
  /** Efforts this model accepts; an empty list means the route must not set one. */
  efforts: readonly AiEffort[];
  /** True when the effort only reaches the request with thinking "adaptive". */
  effortNeedsThinking: boolean;
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
    /** The request field that limits output tokens. */
    maxTokensField: "max_tokens" | "max_completion_tokens";
    /**
     * Request fields per thinking setting, sampling defaults included; null when the model has
     * no such mode.
     */
    thinking: Readonly<Record<AiThinking, Record<string, unknown> | null>>;
    /** Where an adaptive request carries its effort, and the effort sent when none is set. */
    reasoningEffort: Readonly<{ field: string; default: AiEffort }> | null;
  }>;

export type GeminiModel =
  & ModelBase
  & Readonly<{
    provider: "gemini";
    /** generationConfig.thinkingConfig.thinkingLevel for thinking "off". */
    thinkingOffLevel: AiEffort;
    /** Sampling defaults merged into generationConfig. */
    generationDefaults: Record<string, unknown>;
  }>;

export type ModelSpec = AnthropicModel | OpenAiCompatibleModel | GeminiModel;

const allEfforts: readonly AiEffort[] = ["low", "medium", "high"];

// The Claude API takes up to 10 MB of base64 per image; Amazon Bedrock and Google Cloud take
// 5 MB (https://platform.claude.com/docs/en/build-with-claude/vision). The gateway keeps to the
// smaller limit: 5,000,000 base64 characters are 3,750,000 decoded bytes.
const claudeMaxImageBytes = 3_750_000;

// Today's meal-photo limit for Groq and Gemini (4 MiB of image bytes).
const fourMiB = 4_194_304;

// DeepSeek-V4.1-Flash peak list prices from 2026-09-10 (docs/COST_MODEL.md): 0.30 cache-miss
// input, 0.006 cache-hit input, 1.20 output. Peak prices, so the budget never undercounts.
// DeepSeek charges no cache write; a write is an ordinary cache miss.
const deepseekFlash: OpenAiCompatibleModel = {
  provider: "openai_compatible",
  vendor: "deepseek",
  price: { input: 0.3, output: 1.2, cacheRead: 0.006, cacheWrite: 0.3 },
  maxImageBytes: 0,
  // reasoning_effort "high" is the only value the live DeepSeek calls have used.
  efforts: ["high"],
  effortNeedsThinking: true,
  maxTokensField: "max_tokens",
  thinking: {
    // The decision request (deepseek_coach_model_provider.ts). V4 thinks by default; live
    // decision requests without the flag failed after about 17 s.
    off: { thinking: { type: "disabled" }, temperature: 0.1 },
    // The thinking request of onboarding plans and Coach chat: no temperature.
    adaptive: { thinking: { type: "enabled" } },
  },
  reasoningEffort: { field: "reasoning_effort", default: "high" },
};

export const models: Readonly<Record<string, ModelSpec>> = {
  "claude-haiku-5-5": {
    provider: "anthropic",
    vendor: "anthropic",
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
    maxImageBytes: claudeMaxImageBytes,
    efforts: allEfforts,
    effortNeedsThinking: false,
    thinkingOff: "disabled",
  },
  "claude-sonnet-5-5": {
    provider: "anthropic",
    vendor: "anthropic",
    price: { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 },
    maxImageBytes: claudeMaxImageBytes,
    efforts: allEfforts,
    effortNeedsThinking: false,
    thinkingOff: "between_tools",
  },
  "claude-opus-5-5": {
    provider: "anthropic",
    vendor: "anthropic",
    price: { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
    maxImageBytes: claudeMaxImageBytes,
    efforts: allEfforts,
    effortNeedsThinking: false,
    thinkingOff: null,
  },
  // Both DeepSeek names serve V4.1 Flash (providers/deepseek_models.ts).
  "deepseek-flash": deepseekFlash,
  "deepseek-v4-flash": deepseekFlash,
  "qwen/qwen3.8-27b": {
    provider: "openai_compatible",
    vendor: "groq",
    // Groq's paid price (providers/groq_meal_vision_provider.ts). No cache discount is
    // verified, so cached tokens are counted at the full input price.
    price: { input: 0.8, output: 4, cacheRead: 0.8, cacheWrite: 0.8 },
    maxImageBytes: fourMiB,
    efforts: [],
    effortNeedsThinking: true,
    maxTokensField: "max_completion_tokens",
    // The meal-photo and physique requests: temperature 0.1 and no reasoning options. Groq
    // refused this model's request with reasoning options on the free tier (2026-09-30), so the
    // model has no thinking mode here.
    thinking: { off: { temperature: 0.1 }, adaptive: null },
    reasoningEffort: null,
  },
  "gemini-3.5-flash": {
    provider: "gemini",
    vendor: "gemini",
    // Paid standard rate of 2026-07-04 (docs/COST_MODEL.md). No cache discount is verified,
    // so cached tokens are counted at the full input price.
    price: { input: 1.5, output: 9, cacheRead: 1.5, cacheWrite: 1.5 },
    maxImageBytes: fourMiB,
    efforts: allEfforts,
    effortNeedsThinking: true,
    // The lowest level the Gemini routes have used (meal photos).
    thinkingOffLevel: "low",
    // Every Gemini provider sends temperature 0.1.
    generationDefaults: { temperature: 0.1 },
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
