import { deepseekFlashPeakPricePerMillionUsd } from "./deepseek_models.ts";
import { costUsd, modelSpec } from "../ai/models.ts";
import { type Env as RouteEnv, route } from "../ai/routes.ts";
import type { AiRoute } from "../ai/types.ts";

// The model behind onboarding plans, chosen by server settings so the owner
// can switch provider or model without a code change:
//
//   ONBOARDING_PLAN_PROVIDER   mock (rules plan only; the default) | deepseek | groq | gemini
//   ONBOARDING_PLAN_MODEL      the provider's model id
//   ONBOARDING_PLAN_MODEL_EVALUATED=true   set only after the onboarding eval passes
//   ONBOARDING_PLAN_INPUT_COST_PER_MILLION_USD / _OUTPUT_  (required unless the
//                              provider has a known default price)
//   ONBOARDING_PLAN_THINKING   on (the default) | off: the first attempt reasons
//                              before answering, for providers that support it
//
// Changing any of these creates a new version of every Edge Function: wait for
// the change to finish, then run ./scripts/verify-live-function.sh --all from
// the deployed commit.
//
// Every provider is called through its OpenAI-compatible chat-completions
// endpoint in JSON mode. A provider change also needs a new AI notice
// (private.publish_ai_notice), because athletes agreed to a named provider.
//
// The AI gateway (Contract 1) is the other path: AI_ONBOARDING_PLAN_* and
// AI_ONBOARDING_QUESTIONS_* settings, read by route(). A feature with a complete,
// evaluated route (and a worst-case cost the budget accepts) goes through the
// gateway; without one it takes the settings above unchanged. See
// onboardingGatewayRoute and gatewayCeilingUsd below.

export const onboardingPlanProviders = {
  deepseek: {
    url: "https://api.deepseek.com/v1/chat/completions",
    keyEnv: "DEEPSEEK_API_KEY",
    requiredFlags: [] as string[],
    defaultPrice: deepseekFlashPeakPricePerMillionUsd as
      | Readonly<{ input: number; output: number }>
      | null,
    // Thinking off. DeepSeek V4 thinks by default; live daily-decision requests
    // without this flag failed after about 17 s (deepseek_coach_model_provider.ts).
    extraBody: { thinking: { type: "disabled" } } as Record<string, unknown>,
    // Thinking on: the request Coach chat sends for plan changes.
    thinkingBody: { thinking: { type: "enabled" }, reasoning_effort: "high" } as
      | Record<string, unknown>
      | null,
  },
  groq: {
    url: "https://api.groq.com/openai/v1/chat/completions",
    keyEnv: "GROQ_API_KEY",
    requiredFlags: [] as string[],
    defaultPrice: null,
    extraBody: {} as Record<string, unknown>,
    thinkingBody: null,
  },
  gemini: {
    url: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    keyEnv: "GEMINI_API_KEY",
    requiredFlags: ["GEMINI_PAID_DATA_TERMS_ACCEPTED"],
    defaultPrice: null,
    extraBody: {} as Record<string, unknown>,
    thinkingBody: null,
  },
} as const;
export type OnboardingPlanProviderName = keyof typeof onboardingPlanProviders;

export type OnboardingModelConfig = Readonly<{
  provider: OnboardingPlanProviderName;
  model: string;
  url: string;
  apiKey: string;
  /** Request fields for an answer without thinking. */
  extraBody: Record<string, unknown>;
  /** Request fields for a thinking answer; null when the provider has none. */
  thinkingBody: Record<string, unknown> | null;
  /** The first attempt thinks: the setting is on and the provider supports it. */
  thinking: boolean;
  price: Readonly<{ input: number; output: number }>;
  /**
   * Output token limit for every call; when absent, production uses
   * onboardingPlanMaxOutputTokens, or the thinking limit for a thinking call.
   */
  maxOutputTokens?: number;
}>;

/** Room for a compact six-day plan with thinking off. */
export const onboardingPlanMaxOutputTokens = 6000;

/** Reasoning counts toward the output limit, so a thinking call needs more. */
export const onboardingPlanThinkingMaxOutputTokens = 24_000;

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
  const thinkingSetting = env.get("ONBOARDING_PLAN_THINKING") ?? "on";
  if (thinkingSetting !== "on" && thinkingSetting !== "off") {
    return { kind: "rules", reason: "provider_configuration_invalid" };
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
      thinkingBody: entry.thinkingBody,
      thinking: thinkingSetting === "on" && entry.thinkingBody !== null,
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

export type ModelUsage = Readonly<{
  inputUnits: number;
  /** Every billed output token, reasoning included. */
  outputUnits: number;
  /** The reasoning part of outputUnits, when the provider reports it. */
  reasoningUnits: number;
}>;

const noUsage: ModelUsage = Object.freeze({ inputUnits: 0, outputUnits: 0, reasoningUnits: 0 });

export class OnboardingModelCallError extends Error {
  readonly code: ModelCallFailure;
  readonly latencyMs: number;
  /**
   * Tokens the provider reported for a failed answer. An empty or cut-off
   * answer is still billed, so it counts toward the AI budget.
   */
  readonly usage: ModelUsage;
  /** The provider's HTTP status for an HTTP or rate-limit failure. */
  readonly httpStatus: number | null;

  constructor(
    code: ModelCallFailure,
    latencyMs: number,
    usage: ModelUsage = noUsage,
    options?: ErrorOptions & { httpStatus?: number },
  ) {
    super(code, options);
    this.name = "OnboardingModelCallError";
    this.code = code;
    this.latencyMs = latencyMs;
    this.usage = usage;
    this.httpStatus = options?.httpStatus ?? null;
  }
}

const tokens = (value: unknown): number =>
  typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : 0;

export type ModelCallResult = Readonly<{
  content: string;
  inputUnits: number;
  outputUnits: number;
  reasoningUnits: number;
  finishReason: string | null;
  latencyMs: number;
}>;

/**
 * A thinking call leaves temperature out (thinking models ignore it); any
 * other call sets it.
 */
export type ModelCallMode =
  | Readonly<{ thinking: true }>
  | Readonly<{ thinking: false; temperature: number }>;

export async function callOnboardingModel(
  config: OnboardingModelConfig,
  messages: readonly Readonly<{ role: "system" | "user"; content: string }>[],
  timeoutMs: number,
  mode: ModelCallMode,
  fetcher: typeof fetch = fetch,
): Promise<ModelCallResult> {
  if (mode.thinking && config.thinkingBody === null) {
    throw new Error("onboarding model has no thinking mode");
  }
  const started = performance.now();
  const elapsed = () => Math.round(performance.now() - started);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.max(1, timeoutMs));
  try {
    const response = await fetcher(config.url, {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.apiKey}` },
      body: JSON.stringify(
        mode.thinking
          ? {
            model: config.model,
            max_tokens: config.maxOutputTokens ?? onboardingPlanThinkingMaxOutputTokens,
            response_format: { type: "json_object" },
            ...config.thinkingBody,
            messages,
          }
          : {
            model: config.model,
            temperature: mode.temperature,
            max_tokens: config.maxOutputTokens ?? onboardingPlanMaxOutputTokens,
            response_format: { type: "json_object" },
            ...config.extraBody,
            messages,
          },
      ),
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new OnboardingModelCallError(
        response.status === 429 ? "provider_rate_limited" : "provider_http_error",
        elapsed(),
        noUsage,
        { httpStatus: response.status },
      );
    }
    const payload = await response.json() as Record<string, unknown>;
    const choice = Array.isArray(payload.choices)
      ? payload.choices[0] as Record<string, unknown> | undefined
      : undefined;
    const message = choice?.message as Record<string, unknown> | undefined;
    const reported = payload.usage as Record<string, unknown> | undefined;
    const details = reported?.completion_tokens_details as Record<string, unknown> | undefined;
    const usage: ModelUsage = {
      inputUnits: tokens(reported?.prompt_tokens),
      outputUnits: tokens(reported?.completion_tokens),
      reasoningUnits: tokens(details?.reasoning_tokens),
    };
    const finishReason = typeof choice?.finish_reason === "string" ? choice.finish_reason : null;
    if (choice?.finish_reason === "length") {
      throw new OnboardingModelCallError("provider_response_truncated", elapsed(), usage);
    }
    const content = typeof message?.content === "string" ? message.content : "";
    // DeepSeek documents that JSON mode "may occasionally return empty content".
    if (!content.trim()) {
      throw new OnboardingModelCallError("provider_response_empty", elapsed(), usage);
    }
    return { content, ...usage, finishReason, latencyMs: elapsed() };
  } catch (error) {
    if (error instanceof OnboardingModelCallError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new OnboardingModelCallError("provider_timeout", elapsed(), noUsage, { cause: error });
    }
    throw new OnboardingModelCallError("provider_http_error", elapsed(), noUsage, {
      cause: error,
    });
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

// --- The AI gateway path ----------------------------------------------------------------------

export type OnboardingGatewayFeature = "onboarding_plan" | "onboarding_questions";

/**
 * The gateway route for an onboarding feature, or null when the feature takes the settings path
 * above. Null for a feature without a complete route and for one whose
 * AI_<FEATURE>_EVALUATED is not true: a route that has not passed its eval behaves exactly like
 * having no route. The eval router is ignored too (logged): no notice names it, so an athlete's
 * answers never reach it.
 */
export function onboardingGatewayRoute(
  feature: OnboardingGatewayFeature,
  env?: RouteEnv,
): AiRoute | null {
  const found = route(feature, env);
  if (!found || !found.evaluated) return null;
  if (found.vendor === "router") {
    console.error(`${feature}_route_ignored: the evaluation router never receives athlete data`);
    return null;
  }
  return found;
}

/** The most `reserve_ai_budget_v2` accepts for one reservation (it refuses anything above). */
export const maxReservableCeilingUsd = 0.5;

const utf8 = new TextEncoder();

/** A token is at least one byte, so the UTF-8 length bounds a text's tokens from above. */
export const tokenBound = (...texts: readonly string[]): number =>
  texts.reduce((sum, text) => sum + utf8.encode(text).length, 0);

/** Message framing and the schema Claude compiles from ours: counted on top of the text. */
const requestOverheadTokens = 1_000;

/**
 * The most a route's requests can cost: for each attempt, the whole prompt (one token per byte,
 * plus framing) at the higher of the input and cache-write prices, and every output token the
 * route allows. Never clamped: the result can pass maxReservableCeilingUsd, and then the route
 * is unusable for the request (nothing sent, nothing reserved). Null when the model has no
 * price.
 */
export function gatewayCeilingUsd(
  gatewayRoute: AiRoute,
  attemptPromptBytes: readonly number[],
): number | null {
  const spec = modelSpec(gatewayRoute.provider, gatewayRoute.model);
  if (!spec) return null;
  let total = 0;
  for (const bytes of attemptPromptBytes) {
    const promptTokens = bytes + requestOverheadTokens;
    const rest = { outputTokens: gatewayRoute.maxOutputTokens, cacheReadTokens: 0 };
    total += Math.max(
      costUsd(spec.price, { ...rest, inputTokens: promptTokens, cacheWriteTokens: 0 }),
      costUsd(spec.price, { ...rest, inputTokens: 0, cacheWriteTokens: promptTokens }),
    );
  }
  return Math.max(0.001, Math.ceil(total * 1_000_000) / 1_000_000);
}
