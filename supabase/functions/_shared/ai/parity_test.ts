// Rollback parity (Contract 1 v2): an OpenAI-compatible or Gemini route sends the request fields
// today's providers send. Each test records the existing provider's request with a fake fetch
// and compares every field except the prompt text with the gateway's request.

import { assertEquals } from "jsr:@std/assert@1";
import { DeepseekCoachModelProvider } from "../providers/deepseek_coach_model_provider.ts";
import {
  decisionSchema,
  GeminiCoachModelProvider,
} from "../providers/gemini_coach_model_provider.ts";
import { analyzeMealImage } from "../providers/gemini_meal_vision_provider.ts";
import { analyzeGroqMealImage } from "../providers/groq_meal_vision_provider.ts";
import {
  callOnboardingModel,
  resolveOnboardingModel,
} from "../providers/onboarding_plan_provider.ts";
import { captureLogs, fakeFetch, routeFor, syntheticKey } from "./fakes.ts";
import { call } from "./gateway.ts";
import type { AiRequest, AiRoute } from "./types.ts";

const decisionRequest = {
  decisionKind: "daily" as const,
  featureSnapshotId: "a",
  policyEvaluationId: "b",
  policyOutcome: "request_data" as const,
  permittedEvidence: [],
  featureContext: {},
  missingData: ["check_in"],
};

/** The JSON body an existing provider sends; its call fails afterwards on purpose. */
async function legacyBody(run: (fetcher: typeof fetch) => Promise<unknown>) {
  let body: Record<string, unknown> | null = null;
  const fetcher = ((_: string | URL | Request, init?: RequestInit) => {
    body = JSON.parse(String(init?.body));
    return Promise.resolve(new Response("{}", { status: 500 }));
  }) as typeof fetch;
  await captureLogs(async () => {
    try {
      await run(fetcher);
    } catch {
      // The 500 ends the legacy call; only its request matters here.
    }
  });
  if (!body) throw new Error("the legacy provider sent nothing");
  return body as Record<string, unknown>;
}

/** The JSON body the gateway sends for the same route. */
async function gatewayBody(
  route: AiRoute,
  extra: Partial<AiRequest> = {},
): Promise<Record<string, unknown>> {
  const fake = fakeFetch(() => new Response("{}", { status: 500 }));
  await captureLogs(() =>
    call({
      route,
      system: [{ type: "text", text: "Rules." }],
      messages: [{ role: "user", content: [{ type: "text", text: "Context." }] }],
      output: { kind: "json", schema: decisionSchema },
      consentVendor: route.vendor,
      ...extra,
    }, { fetch: fake.fetch })
  );
  return fake.sent[0].body;
}

const withoutPrompt = (body: Record<string, unknown>) => {
  const { messages: _m, contents: _c, systemInstruction: _s, ...rest } = body;
  return rest;
};

const image = { type: "image" as const, mediaType: "image/jpeg" as const, base64: "AQID" };

Deno.test("DeepSeek daily decision: same fields, schema restated for JSON mode", async () => {
  const legacy = await legacyBody((fetcher) =>
    new DeepseekCoachModelProvider({ apiKey: syntheticKey, model: "deepseek-flash", fetcher })
      .generateDecision(decisionRequest)
  );
  const gateway = await gatewayBody(routeFor("daily_decision", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    MAX_OUTPUT_TOKENS: "1800",
    OPENAI_COMPATIBLE_API_KEY_DAILY_DECISION: syntheticKey,
  }));
  assertEquals(withoutPrompt(gateway), withoutPrompt(legacy));
  const schemaText = JSON.stringify(decisionSchema);
  const legacyPrompt = (legacy.messages as { content: string }[]).map((m) => m.content).join("");
  const gatewaySystem = (gateway.messages as { role: string; content: string }[])[0];
  assertEquals(legacyPrompt.includes(schemaText), true);
  assertEquals(gatewaySystem.role, "system");
  assertEquals(gatewaySystem.content.includes(schemaText), true);
  assertEquals(gatewaySystem.content.includes("JSON"), true);
});

Deno.test("DeepSeek onboarding plan with thinking: same fields, no temperature", async () => {
  const resolution = resolveOnboardingModel({
    get: (name) =>
      ({
        ONBOARDING_PLAN_PROVIDER: "deepseek",
        ONBOARDING_PLAN_MODEL: "deepseek-flash",
        ONBOARDING_PLAN_MODEL_EVALUATED: "true",
        DEEPSEEK_API_KEY: syntheticKey,
      } as Record<string, string>)[name],
  });
  if (resolution.kind !== "model") throw new Error("no onboarding model");
  const legacy = await legacyBody((fetcher) =>
    callOnboardingModel(
      resolution.config,
      [{ role: "user", content: "Plan." }],
      1000,
      { thinking: true },
      fetcher,
    )
  );
  const gateway = await gatewayBody(routeFor("onboarding_plan", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    THINKING: "adaptive",
    MAX_OUTPUT_TOKENS: "24000",
    OPENAI_COMPATIBLE_API_KEY_ONBOARDING_PLAN: syntheticKey,
  }));
  assertEquals(withoutPrompt(gateway), withoutPrompt(legacy));
});

Deno.test("Groq meal photo: same fields", async () => {
  const legacy = await legacyBody((fetcher) =>
    analyzeGroqMealImage(new Uint8Array([1, 2, 3]), "image/jpeg", fetcher, {
      get: (name) =>
        ({
          MEAL_VISION_ENABLED: "true",
          MEAL_VISION_MODEL_EVALUATED: "true",
          GROQ_API_KEY: syntheticKey,
        } as Record<string, string>)[name],
    })
  );
  const gateway = await gatewayBody(
    routeFor("meal_vision", {
      PROVIDER: "openai_compatible",
      MODEL: "qwen/qwen3.8-27b",
      BASE_URL: "https://api.groq.com/openai/v1",
      MAX_OUTPUT_TOKENS: "1000",
      OPENAI_COMPATIBLE_API_KEY_MEAL_VISION: syntheticKey,
    }),
    {
      messages: [{ role: "user", content: [{ type: "text", text: "Meal?" }, image] }],
    },
  );
  assertEquals(withoutPrompt(gateway), withoutPrompt(legacy));
});

const geminiSettings = {
  PROVIDER: "gemini",
  MODEL: "gemini-3.5-flash",
  MAX_OUTPUT_TOKENS: "1800",
  GEMINI_API_KEY: syntheticKey,
  GEMINI_PAID_DATA_TERMS_ACCEPTED: "true",
};

Deno.test("Gemini meal photo: same generationConfig (thinking low, temperature 0.1)", async () => {
  const legacy = await legacyBody((fetcher) =>
    analyzeMealImage(new Uint8Array([1, 2, 3]), "image/jpeg", fetcher, {
      get: (name) =>
        ({
          MEAL_VISION_ENABLED: "true",
          MEAL_VISION_MODEL_EVALUATED: "true",
          GEMINI_PAID_DATA_TERMS_ACCEPTED: "true",
          GEMINI_API_KEY: syntheticKey,
          MEAL_VISION_INPUT_COST_PER_MILLION_USD: "1.5",
          MEAL_VISION_OUTPUT_COST_PER_MILLION_USD: "9",
        } as Record<string, string>)[name],
    })
  );
  const legacySchema = (legacy.generationConfig as Record<string, Record<string, unknown>>)
    .responseJsonSchema;
  const gateway = await gatewayBody(routeFor("meal_vision", geminiSettings), {
    messages: [{ role: "user", content: [{ type: "text", text: "Meal?" }, image] }],
    output: { kind: "json", schema: legacySchema },
  });
  assertEquals(withoutPrompt(gateway), withoutPrompt(legacy));
});

Deno.test("Gemini daily decision: same generationConfig (thinking medium, temperature 0.1)", async () => {
  const legacy = await legacyBody((fetcher) =>
    new GeminiCoachModelProvider({
      apiKey: syntheticKey,
      model: "gemini-3.5-flash",
      paidDataTermsAccepted: true,
      fetcher,
    }).generateDecision(decisionRequest)
  );
  const gateway = await gatewayBody(
    routeFor("daily_decision", { ...geminiSettings, THINKING: "adaptive" }),
  );
  assertEquals(withoutPrompt(gateway), withoutPrompt(legacy));
});
