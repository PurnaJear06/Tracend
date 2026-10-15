// Contract 1 of the coaching platform program
// (docs/plans/coaching-platform-2026-10/README.md). The shapes are fixed by the
// contract; change them only through a new contract version.

export const aiFeatures = [
  "coach_chat",
  "daily_decision",
  "onboarding_plan",
  "onboarding_questions",
  "meal_vision",
  "physique_vision",
  "library_context",
] as const;
export type AiFeature = typeof aiFeatures[number];

export const aiProviders = ["anthropic", "openai_compatible", "gemini"] as const;
export type AiProvider = typeof aiProviders[number];

export type AiThinking = "off" | "adaptive";
export type AiEffort = "low" | "medium" | "high";

export type AiRoute = Readonly<{
  feature: AiFeature;
  provider: AiProvider;
  /** Shown in notices, e.g. "Claude (Anthropic)". */
  providerLabel: string;
  model: string;
  /** openai_compatible only (DeepSeek, Groq). */
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
  /** The provider named by the athlete's accepted notice. */
  consentProvider: AiProvider | null;
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
  | { ok: false; reason: AiFailure; usage: AiUsage | null; retryAfterSeconds?: number };

export type AiCallDeps = { fetch?: typeof fetch; now?: () => number };
