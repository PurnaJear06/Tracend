import type { CoachModelProvider } from "./coach_model_provider.ts";
import { DeepseekCoachModelProvider } from "./deepseek_coach_model_provider.ts";
import { deepseekFlashPeakPricePerMillionUsd, isApprovedDeepseekModel } from "./deepseek_models.ts";
import { GeminiCoachModelProvider } from "./gemini_coach_model_provider.ts";
import { GroqCoachModelProvider } from "./groq_coach_model_provider.ts";
import { MockCoachModelProvider } from "./mock_coach_model_provider.ts";

export type CoachProviderEnvironment = Readonly<{
  get(name: string): string | undefined;
}>;

function required(environment: CoachProviderEnvironment, name: string): string {
  const value = environment.get(name)?.trim();
  if (!value) throw new Error("coach_provider_configuration_invalid");
  return value;
}

// An unset price falls back to the provider's list price (the same rates
// coach-chat uses), so no call is ever counted as free.
function priceOrListPrice(
  environment: CoachProviderEnvironment,
  name: string,
  listPrice: number,
): number {
  const raw = environment.get(name)?.trim();
  if (!raw) return listPrice;
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error("coach_provider_configuration_invalid");
  }
  return value;
}

export function createCoachModelProvider(
  environment: CoachProviderEnvironment = Deno.env,
): CoachModelProvider {
  const provider = environment.get("COACH_MODEL_PROVIDER")?.trim() || "mock";
  if (provider === "mock") return new MockCoachModelProvider();
  if (provider !== "gemini" && provider !== "groq" && provider !== "deepseek") {
    throw new Error("coach_provider_configuration_invalid");
  }
  if (environment.get("COACH_AI_ENABLED") !== "true") {
    throw new Error("coach_provider_disabled");
  }
  if (provider === "groq") {
    const model = required(environment, "GROQ_MODEL");
    if (model !== "qwen/qwen3.6-27b") {
      throw new Error("coach_provider_model_not_approved");
    }
    return new GroqCoachModelProvider({
      apiKey: required(environment, "GROQ_API_KEY"),
      model,
      inputCostPerMillionUsd: priceOrListPrice(
        environment,
        "GROQ_INPUT_COST_PER_MILLION_USD",
        0.6,
      ),
      outputCostPerMillionUsd: priceOrListPrice(
        environment,
        "GROQ_OUTPUT_COST_PER_MILLION_USD",
        3,
      ),
    });
  }
  if (provider === "deepseek") {
    const model = required(environment, "DEEPSEEK_MODEL");
    if (!isApprovedDeepseekModel(model)) {
      throw new Error("coach_provider_model_not_approved");
    }
    return new DeepseekCoachModelProvider({
      apiKey: required(environment, "DEEPSEEK_API_KEY"),
      model,
      inputCostPerMillionUsd: priceOrListPrice(
        environment,
        "DEEPSEEK_INPUT_COST_PER_MILLION_USD",
        deepseekFlashPeakPricePerMillionUsd.input,
      ),
      outputCostPerMillionUsd: priceOrListPrice(
        environment,
        "DEEPSEEK_OUTPUT_COST_PER_MILLION_USD",
        deepseekFlashPeakPricePerMillionUsd.output,
      ),
    });
  }
  const model = required(environment, "GEMINI_MODEL");
  if (model !== "gemini-3.5-flash") {
    throw new Error("coach_provider_model_not_approved");
  }
  return new GeminiCoachModelProvider({
    apiKey: required(environment, "GEMINI_API_KEY"),
    model,
    paidDataTermsAccepted: environment.get("GEMINI_PAID_DATA_TERMS_ACCEPTED") === "true",
    inputCostPerMillionUsd: priceOrListPrice(environment, "GEMINI_INPUT_COST_PER_MILLION_USD", 1.5),
    outputCostPerMillionUsd: priceOrListPrice(
      environment,
      "GEMINI_OUTPUT_COST_PER_MILLION_USD",
      9,
    ),
  });
}
