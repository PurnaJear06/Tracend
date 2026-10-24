// Contract 1 (version 2) of the coaching platform program
// (docs/plans/coaching-platform-2026-10/README.md). The shapes are fixed by the
// contract; change them only through a new contract version.

export const aiFeatures = [
  "coach_chat",
  // A second Coach chat route for progress, body-weight, nutrition-number and plan questions
  // (A9). Unset, those questions take the "coach_chat" route.
  "coach_chat_strong",
  "daily_decision",
  "onboarding_plan",
  "onboarding_questions",
  "meal_vision",
  "physique_vision",
  "library_context",
] as const;
export type AiFeature = typeof aiFeatures[number];

/** The wire protocol. */
export const aiProviders = ["anthropic", "openai_compatible", "gemini"] as const;
export type AiProvider = typeof aiProviders[number];

/**
 * Who receives the data: stored in SQL whitelists, notices and consent; a notice names a vendor.
 * "router" is for synthetic evals through an OpenAI-compatible router; no notice names it.
 */
export const aiVendors = ["anthropic", "deepseek", "groq", "gemini", "router"] as const;
export type AiVendor = typeof aiVendors[number];

export type AiThinking = "off" | "adaptive";
export type AiEffort = "low" | "medium" | "high";

export type AiRoute = Readonly<{
  feature: AiFeature;
  provider: AiProvider;
  /** From the model table; DeepSeek and Groq hosts are pinned per vendor. */
  vendor: AiVendor;
  /** Shown in notices: the company only, never a model (D11), e.g. "Anthropic". */
  providerLabel: string;
  model: string;
  /** openai_compatible only: the vendor's host, or any https host for "router". */
  baseUrl?: string;
  /** Mapped per model in models.ts; Sonnet 5.5 "off" is between_tools. */
  thinking: AiThinking;
  effort?: AiEffort;
  maxOutputTokens: number;
  timeoutMs: number;
  /** false = the feature's eval has not passed yet; features may refuse. */
  evaluated: boolean;
}>;

export type AiContent =
  /** cache = the end of a cacheable prefix. */
  | { type: "text"; text: string; cache?: boolean }
  | { type: "image"; mediaType: "image/jpeg"; base64: string };

export type AiMessage = { role: "user" | "assistant"; content: AiContent[] };

export type AiOutput = { kind: "text" } | { kind: "json"; schema: Record<string, unknown> };

export type AiRequest = Readonly<{
  route: AiRoute;
  /** Stable first, so prefixes cache. */
  system: AiContent[];
  messages: AiMessage[];
  output: AiOutput;
  /** The vendor named by the athlete's accepted notice. */
  consentVendor: AiVendor | null;
  signal?: AbortSignal;
}>;

export type AiUsage = Readonly<{
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  /** From the model price table in models.ts; list prices, never guessed. */
  costUsd: number;
}>;

export type AiFailure =
  /** No request sent. */
  | "consent_provider_mismatch"
  /** Provider safety refusal (Anthropic stop_reason "refusal"). */
  | "refused"
  | "rate_limited"
  | "overloaded"
  | "timeout"
  | "network"
  /** The JSON did not parse or match the schema. */
  | "invalid_output"
  | "provider_error";

export type AiResult =
  | {
    ok: true;
    text: string;
    json?: unknown;
    usage: AiUsage;
    model: string;
    stop: "end" | "max_tokens";
  }
  | {
    ok: false;
    reason: AiFailure;
    usage: AiUsage | null;
    retryAfterSeconds?: number;
    /**
     * The provider's HTTP status on a "provider_error" that was an error response other than
     * 429, 503 and 529: the number only, never a body. Absent for every other failure.
     */
    httpStatus?: number;
  };

export type AiCallDeps = { fetch?: typeof fetch; now?: () => number };
