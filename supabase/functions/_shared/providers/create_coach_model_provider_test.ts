import { createCoachModelProvider } from "./create_coach_model_provider.ts";
import { MockCoachModelProvider } from "./mock_coach_model_provider.ts";
import { GroqCoachModelProvider } from "./groq_coach_model_provider.ts";

function environment(values: Record<string, string>) {
  return { get: (name: string) => values[name] };
}

Deno.test("provider factory defaults to the deterministic mock", () => {
  const provider = createCoachModelProvider(environment({}));
  if (!(provider instanceof MockCoachModelProvider)) throw new Error("Mock must remain default.");
});

Deno.test("provider factory creates the approved Groq Qwen owner-test adapter", () => {
  const provider = createCoachModelProvider(environment({
    COACH_MODEL_PROVIDER: "groq",
    COACH_AI_ENABLED: "true",
    GROQ_API_KEY: "synthetic-key",
    GROQ_MODEL: "qwen/qwen3.6-27b",
    GROQ_INPUT_COST_PER_MILLION_USD: "0.6",
    GROQ_OUTPUT_COST_PER_MILLION_USD: "3",
  }));
  if (!(provider instanceof GroqCoachModelProvider)) throw new Error("Groq Qwen was not selected.");
});

Deno.test("provider factory kill switch blocks Gemini", () => {
  let message = "";
  try {
    createCoachModelProvider(environment({ COACH_MODEL_PROVIDER: "gemini" }));
  } catch (error) {
    message = error instanceof Error ? error.message : "";
  }
  if (message !== "coach_provider_disabled") throw new Error("Kill switch did not fail closed.");
});

Deno.test("provider factory requires paid data terms for Gemini", () => {
  let message = "";
  try {
    createCoachModelProvider(environment({
      COACH_MODEL_PROVIDER: "gemini",
      COACH_AI_ENABLED: "true",
      GEMINI_API_KEY: "synthetic-key",
      GEMINI_MODEL: "gemini-3.5-flash",
    }));
  } catch (error) {
    message = error instanceof Error ? error.message : "";
  }
  if (message !== "gemini_paid_data_terms_required") {
    throw new Error("Paid-data gate did not fail closed.");
  }
});
