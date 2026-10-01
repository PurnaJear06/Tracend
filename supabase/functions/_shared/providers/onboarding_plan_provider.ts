import { deepseekFlashPeakPricePerMillionUsd } from "./deepseek_models.ts";

// The model behind onboarding plans, chosen by server settings so the owner
// can switch provider or model without a code change:
//
//   ONBOARDING_PLAN_PROVIDER   mock (rules plan only; the default) | deepseek | groq | gemini
//   ONBOARDING_PLAN_MODEL      the provider's model id
//   ONBOARDING_PLAN_MODEL_EVALUATED=true   set only after the onboarding eval passes
//   ONBOARDING_PLAN_INPUT_COST_PER_MILLION_USD / _OUTPUT_  (required unless the
//                              provider has a known default price)
//
// Every provider is called through its OpenAI-compatible chat-completions
// endpoint in JSON mode. A provider change also needs a new AI notice
// (private.publish_ai_notice), because athletes agreed to a named provider.

export const onboardingPlanProviders = {
  deepseek: {
    url: "https://api.deepseek.com/v1/chat/completions",
    keyEnv: "DEEPSEEK_API_KEY",
    requiredFlags: [] as string[],
    defaultPrice: deepseekFlashPeakPricePerMillionUsd as
      | Readonly<{ input: number; output: number }>
      | null,
    // Live DeepSeek requests without this failed after about 17 s
    // (deepseek_coach_model_provider.ts).
    extraBody: { thinking: { type: "disabled" } } as Record<string, unknown>,
  },
  groq: {
    url: "https://api.groq.com/openai/v1/chat/completions",
    keyEnv: "GROQ_API_KEY",
    requiredFlags: [] as string[],
    defaultPrice: null,
    extraBody: {} as Record<string, unknown>,
  },
  gemini: {
    url: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    keyEnv: "GEMINI_API_KEY",
    requiredFlags: ["GEMINI_PAID_DATA_TERMS_ACCEPTED"],
    defaultPrice: null,
    extraBody: {} as Record<string, unknown>,
  },
} as const;
export type OnboardingPlanProviderName = keyof typeof onboardingPlanProviders;

export type OnboardingModelConfig = Readonly<{
  provider: OnboardingPlanProviderName;
  model: string;
  url: string;
  apiKey: string;
  extraBody: Record<string, unknown>;
  price: Readonly<{ input: number; output: number }>;
}>;

export type OnboardingModelResolution =
  | { kind: "model"; config: OnboardingModelConfig }
  | { kind: "rules"; reason: string };

type Env = { get(name: string): string | undefined };

const price = (env: Env, name: string): number | null => {
  const raw = env.get(name);
  if (raw === undefined || raw === "") return null;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : null;
};

export function resolveOnboardingModel(env: Env = Deno.env): OnboardingModelResolution {
  const name = env.get("ONBOARDING_PLAN_PROVIDER") ?? "mock";
  if (name === "mock") return { kind: "rules", reason: "provider_mock" };
  if (!(name in onboardingPlanProviders)) {
    return { kind: "rules", reason: "provider_configuration_invalid" };
  }
  const provider = name as OnboardingPlanProviderName;
  const entry = onboardingPlanProviders[provider];
  const model = env.get("ONBOARDING_PLAN_MODEL") ?? "";
  if (!model) return { kind: "rules", reason: "provider_configuration_invalid" };
  if (env.get("ONBOARDING_PLAN_MODEL_EVALUATED") !== "true") {
    return { kind: "rules", reason: "model_not_evaluated" };
  }
  if (entry.requiredFlags.some((flag) => env.get(flag) !== "true")) {
    return { kind: "rules", reason: "provider_terms_not_accepted" };
  }
  const apiKey = env.get(entry.keyEnv) ?? "";
  if (!apiKey) return { kind: "rules", reason: "provider_key_missing" };
  const input = price(env, "ONBOARDING_PLAN_INPUT_COST_PER_MILLION_USD") ??
    entry.defaultPrice?.input ?? null;
  const output = price(env, "ONBOARDING_PLAN_OUTPUT_COST_PER_MILLION_USD") ??
    entry.defaultPrice?.output ?? null;
  // Without a price the monthly budget cannot count the call.
  if (input === null || output === null) return { kind: "rules", reason: "model_price_unknown" };
  return {
    kind: "model",
    config: {
      provider,
      model,
      url: entry.url,
      apiKey,
      extraBody: entry.extraBody,
      price: { input, output },
    },
  };
}

export type ModelCallFailure =
  | "provider_timeout"
  | "provider_rate_limited"
  | "provider_http_error"
  | "provider_response_empty"
  | "provider_response_truncated";

export class OnboardingModelCallError extends Error {
  readonly code: ModelCallFailure;
  readonly latencyMs: number;

  constructor(code: ModelCallFailure, latencyMs: number, options?: ErrorOptions) {
    super(code, options);
    this.name = "OnboardingModelCallError";
    this.code = code;
    this.latencyMs = latencyMs;
  }
}

export type ModelCallResult = Readonly<{
  content: string;
  inputUnits: number;
  outputUnits: number;
  latencyMs: number;
}>;

export async function callOnboardingModel(
  config: OnboardingModelConfig,
  messages: readonly Readonly<{ role: "system" | "user"; content: string }>[],
  timeoutMs: number,
  temperature: number,
  fetcher: typeof fetch = fetch,
): Promise<ModelCallResult> {
  const started = performance.now();
  const elapsed = () => Math.round(performance.now() - started);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.max(1, timeoutMs));
  try {
    const response = await fetcher(config.url, {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.apiKey}` },
      body: JSON.stringify({
        model: config.model,
        temperature,
        max_tokens: 6000,
        response_format: { type: "json_object" },
        ...config.extraBody,
        messages,
      }),
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new OnboardingModelCallError(
        response.status === 429 ? "provider_rate_limited" : "provider_http_error",
        elapsed(),
      );
    }
    const payload = await response.json() as Record<string, unknown>;
    const choice = Array.isArray(payload.choices)
      ? payload.choices[0] as Record<string, unknown> | undefined
      : undefined;
    const message = choice?.message as Record<string, unknown> | undefined;
    const usage = payload.usage as Record<string, unknown> | undefined;
    if (choice?.finish_reason === "length") {
      throw new OnboardingModelCallError("provider_response_truncated", elapsed());
    }
    const content = typeof message?.content === "string" ? message.content : "";
    // DeepSeek documents that JSON mode "may occasionally return empty content".
    if (!content.trim()) throw new OnboardingModelCallError("provider_response_empty", elapsed());
    return {
      content,
      inputUnits: Number.isInteger(usage?.prompt_tokens) ? Number(usage?.prompt_tokens) : 0,
      outputUnits: Number.isInteger(usage?.completion_tokens)
        ? Number(usage?.completion_tokens)
        : 0,
      latencyMs: elapsed(),
    };
  } catch (error) {
    if (error instanceof OnboardingModelCallError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new OnboardingModelCallError("provider_timeout", elapsed(), { cause: error });
    }
    throw new OnboardingModelCallError("provider_http_error", elapsed(), { cause: error });
  } finally {
    clearTimeout(timer);
  }
}

export function estimateCostUsd(
  config: OnboardingModelConfig,
  inputUnits: number,
  outputUnits: number,
): number {
  const cost = (inputUnits * config.price.input + outputUnits * config.price.output) / 1_000_000;
  return Math.round(cost * 1_000_000) / 1_000_000;
}
