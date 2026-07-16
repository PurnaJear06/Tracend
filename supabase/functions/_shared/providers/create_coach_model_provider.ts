import type { CoachModelProvider } from "./coach_model_provider.ts";
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

function nonnegativeNumber(
  environment: CoachProviderEnvironment,
  name: string,
): number {
  const raw = environment.get(name)?.trim();
  if (!raw) return 0;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error("coach_provider_configuration_invalid");
  }
  return value;
}

export function createCoachModelProvider(
  environment: CoachProviderEnvironment = Deno.env,
): CoachModelProvider {
  const provider = environment.get("COACH_MODEL_PROVIDER")?.trim() || "mock";
  if (provider === "mock") return new MockCoachModelProvider();
  if (provider !== "gemini" && provider !== "groq") {
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
      inputCostPerMillionUsd: nonnegativeNumber(
        environment,
        "GROQ_INPUT_COST_PER_MILLION_USD",
      ),
      outputCostPerMillionUsd: nonnegativeNumber(
        environment,
        "GROQ_OUTPUT_COST_PER_MILLION_USD",
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
    inputCostPerMillionUsd: nonnegativeNumber(environment, "GEMINI_INPUT_COST_PER_MILLION_USD"),
    outputCostPerMillionUsd: nonnegativeNumber(
      environment,
      "GEMINI_OUTPUT_COST_PER_MILLION_USD",
    ),
  });
}
