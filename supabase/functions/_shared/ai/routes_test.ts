import { assertEquals } from "jsr:@std/assert@1";
import { envOf, settings, syntheticKey } from "./fakes.ts";
import { route, routeApiKey } from "./routes.ts";
import type { AiFeature } from "./types.ts";

const routeWith = (feature: AiFeature, values: Record<string, string> = {}) =>
  route(feature, envOf(settings(feature, values)));

Deno.test("route parses every setting for a Claude route", () => {
  const result = routeWith("coach_chat", {
    MODEL: "claude-haiku-5-5",
    THINKING: "adaptive",
    EFFORT: "low",
    MAX_OUTPUT_TOKENS: "3000",
    TIMEOUT_MS: "45000",
    EVALUATED: "true",
  });
  assertEquals(result, {
    feature: "coach_chat",
    provider: "anthropic",
    providerLabel: "Claude (Anthropic)",
    model: "claude-haiku-5-5",
    thinking: "adaptive",
    effort: "low",
    maxOutputTokens: 3000,
    timeoutMs: 45000,
    evaluated: true,
  });
});

Deno.test("route defaults: thinking off, no effort, not evaluated", () => {
  const result = routeWith("daily_decision");
  assertEquals(result?.thinking, "off");
  assertEquals(result !== null && "effort" in result, false);
  assertEquals(result?.evaluated, false);
  assertEquals(result !== null && "baseUrl" in result, false);
});

Deno.test("each feature reads only its own settings", () => {
  const env = envOf(settings("meal_vision", { MODEL: "claude-haiku-5-5" }));
  assertEquals(route("meal_vision", env)?.model, "claude-haiku-5-5");
  assertEquals(route("coach_chat", env), null);
});

Deno.test("route returns null when a required setting or the key is missing", () => {
  for (const missing of ["PROVIDER", "MODEL", "MAX_OUTPUT_TOKENS", "TIMEOUT_MS"]) {
    assertEquals(routeWith("coach_chat", { [missing]: "" }), null, missing);
  }
  assertEquals(routeWith("coach_chat", { ANTHROPIC_API_KEY: "" }), null);
  assertEquals(routeWith("coach_chat", { ANTHROPIC_API_KEY: "  " }), null);
});

Deno.test("route rejects unknown or malformed settings", () => {
  const invalid: Record<string, string>[] = [
    { PROVIDER: "openai" },
    { PROVIDER: "deepseek" },
    { MODEL: "claude-haiku-4-5" },
    { MODEL: "deepseek-flash" },
    { THINKING: "on" },
    { THINKING: "enabled" },
    { EFFORT: "max" },
    { EFFORT: "xhigh" },
    { EVALUATED: "yes" },
    { MAX_OUTPUT_TOKENS: "0" },
    { MAX_OUTPUT_TOKENS: "128001" },
    { MAX_OUTPUT_TOKENS: "1.5" },
    { MAX_OUTPUT_TOKENS: "-5" },
    { TIMEOUT_MS: "999" },
    { TIMEOUT_MS: "600001" },
    { TIMEOUT_MS: "20s" },
    { BASE_URL: "https://api.anthropic.com" },
  ];
  for (const values of invalid) {
    assertEquals(routeWith("coach_chat", values), null, JSON.stringify(values));
  }
  assertEquals(route("unknown_feature" as AiFeature, envOf(settings("coach_chat"))), null);
});

Deno.test("an OpenAI-compatible route needs its feature key and a base URL on the model's host", () => {
  const deepseek = {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1/",
    OPENAI_COMPATIBLE_API_KEY_DAILY_DECISION: syntheticKey,
  };
  const result = routeWith("daily_decision", deepseek);
  assertEquals(result?.provider, "openai_compatible");
  assertEquals(result?.providerLabel, "DeepSeek");
  assertEquals(result?.baseUrl, "https://api.deepseek.com/v1");
  assertEquals(result ? routeApiKey(result) : null, syntheticKey);

  assertEquals(routeWith("daily_decision", { ...deepseek, BASE_URL: "" }), null);
  // Another feature's key does not count.
  assertEquals(
    routeWith("daily_decision", {
      ...deepseek,
      OPENAI_COMPATIBLE_API_KEY_DAILY_DECISION: "",
      OPENAI_COMPATIBLE_API_KEY_COACH_CHAT: syntheticKey,
    }),
    null,
  );
  for (
    const baseUrl of [
      "http://api.deepseek.com/v1",
      "https://router.example.com/v1",
      "https://api.groq.com/openai/v1",
      "https://user:pass@api.deepseek.com/v1",
      "https://api.deepseek.com:8443/v1",
      "https://api.deepseek.com/v1?x=1",
      "not a url",
    ]
  ) {
    assertEquals(routeWith("daily_decision", { ...deepseek, BASE_URL: baseUrl }), null, baseUrl);
  }
});

Deno.test("route refuses thinking or effort the model cannot take", () => {
  const deepseek = {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_COACH_CHAT: syntheticKey,
  };
  assertEquals(
    routeWith("coach_chat", { ...deepseek, THINKING: "adaptive" })?.thinking,
    "adaptive",
  );
  assertEquals(routeWith("coach_chat", { ...deepseek, EFFORT: "high" })?.effort, "high");
  assertEquals(routeWith("coach_chat", { ...deepseek, EFFORT: "low" }), null);

  const groq = {
    PROVIDER: "openai_compatible",
    MODEL: "qwen/qwen3.8-27b",
    BASE_URL: "https://api.groq.com/openai/v1",
    OPENAI_COMPATIBLE_API_KEY_MEAL_VISION: syntheticKey,
  };
  assertEquals(routeWith("meal_vision", groq)?.providerLabel, "Qwen (Groq)");
  assertEquals(routeWith("meal_vision", { ...groq, THINKING: "adaptive" }), null);
  assertEquals(routeWith("meal_vision", { ...groq, EFFORT: "low" }), null);
});

Deno.test("a Gemini route needs the paid data-terms flag and its key", () => {
  const gemini = {
    PROVIDER: "gemini",
    MODEL: "gemini-3.5-flash",
    GEMINI_API_KEY: syntheticKey,
    GEMINI_PAID_DATA_TERMS_ACCEPTED: "true",
  };
  assertEquals(routeWith("coach_chat", gemini)?.providerLabel, "Gemini (Google)");
  assertEquals(
    routeWith("coach_chat", { ...gemini, GEMINI_PAID_DATA_TERMS_ACCEPTED: "false" }),
    null,
  );
  assertEquals(routeWith("coach_chat", { ...gemini, GEMINI_API_KEY: "" }), null);
});

Deno.test("the key never appears on the route", () => {
  const result = routeWith("coach_chat");
  if (!result) throw new Error("no route");
  assertEquals(JSON.stringify(result).includes(syntheticKey), false);
  assertEquals(Object.isFrozen(result), true);
  assertEquals(routeApiKey({ ...result }), null);
});
