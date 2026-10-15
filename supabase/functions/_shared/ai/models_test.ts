import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { costUsd, models, modelSpec, vendorLabels } from "./models.ts";

const tokens = (input: number, output: number, cacheRead = 0, cacheWrite = 0) => ({
  inputTokens: input,
  outputTokens: output,
  cacheReadTokens: cacheRead,
  cacheWriteTokens: cacheWrite,
});

const price = (model: string) => {
  const spec = models[model];
  if (!spec) throw new Error(`no ${model}`);
  return spec.price;
};

Deno.test("Claude list prices per million tokens match the pricing page (2026-10-15)", () => {
  // 100,000 tokens (Haiku 5.5's standard card), scaled to a million.
  const tokensPerCall = 100_000;
  const perMillion = (model: string, counts: ReturnType<typeof tokens>) =>
    costUsd(price(model), counts) * 10;
  for (
    const [model, input, output, cacheRead, cacheWrite] of [
      ["claude-haiku-5-5", 0.1, 0.5, 0.01, 0.125],
      ["claude-sonnet-5-5", 2, 10, 0.1, 2.5],
      ["claude-opus-5-5", 4, 20, 0.2, 5],
    ] as const
  ) {
    assertAlmostEquals(perMillion(model, tokens(tokensPerCall, 0)), input, 1e-9);
    assertAlmostEquals(perMillion(model, tokens(0, tokensPerCall)), output, 1e-9);
    assertAlmostEquals(perMillion(model, tokens(0, 0, tokensPerCall)), cacheRead, 1e-9);
    assertAlmostEquals(perMillion(model, tokens(0, 0, 0, tokensPerCall)), cacheWrite, 1e-9);
  }
});

Deno.test("cost adds input, output, cache reads and cache writes at their own rates", () => {
  // Haiku 5.5: 1,000 × 0.10 + 500 × 0.50 + 2,000 × 0.01 + 4,000 × 0.125 = 870 µUSD.
  assertAlmostEquals(
    costUsd(price("claude-haiku-5-5"), tokens(1000, 500, 2000, 4000)),
    0.00087,
    1e-12,
  );
  // Sonnet 5.5: 3,000 × 2 + 800 × 10 + 12,000 × 0.10 + 0 = 15,200 µUSD.
  assertAlmostEquals(
    costUsd(price("claude-sonnet-5-5"), tokens(3000, 800, 12_000)),
    0.0152,
    1e-12,
  );
});

Deno.test("Haiku 5.5 prompts over 100K tokens, cached tokens included, use the long rate card", () => {
  const haiku = price("claude-haiku-5-5");
  // 50,000 input + 60,000 cache read = 110,000 prompt tokens: every token at the higher rates.
  assertAlmostEquals(costUsd(haiku, tokens(50_000, 1000, 60_000)), 0.0305, 1e-12);
  // Exactly 100,000 stays on the standard card.
  assertAlmostEquals(costUsd(haiku, tokens(40_000, 0, 30_000, 30_000)), 0.00805, 1e-12);
  // Cache writes count toward the threshold too.
  assertAlmostEquals(costUsd(haiku, tokens(1, 0, 0, 100_000)), 0.0625005, 1e-12);
});

Deno.test("every model has finite, positive prices and only known efforts", () => {
  for (const [name, spec] of Object.entries(models)) {
    for (const rate of [spec.price.input, spec.price.output, spec.price.cacheWrite]) {
      if (!(Number.isFinite(rate) && rate > 0)) throw new Error(`${name} has a bad price`);
    }
    if (!(Number.isFinite(spec.price.cacheRead) && spec.price.cacheRead > 0)) {
      throw new Error(`${name} has a bad cache-read price`);
    }
    for (const effort of spec.efforts) {
      if (!["low", "medium", "high"].includes(effort)) throw new Error(`${name} effort`);
    }
  }
});

Deno.test("thinking 'off' maps to each Claude model's lowest mode; Opus 5.5 has none", () => {
  const off = (model: string) => {
    const spec = modelSpec("anthropic", model);
    return spec?.provider === "anthropic" ? spec.thinkingOff : undefined;
  };
  assertEquals(off("claude-haiku-5-5"), "disabled");
  assertEquals(off("claude-sonnet-5-5"), "between_tools");
  assertEquals(off("claude-opus-5-5"), null);
});

Deno.test("modelSpec matches provider and model, and nothing inherited", () => {
  assertEquals(modelSpec("anthropic", "claude-haiku-5-5")?.vendor, "anthropic");
  assertEquals(modelSpec("openai_compatible", "claude-haiku-5-5"), null);
  assertEquals(modelSpec("anthropic", "deepseek-flash"), null);
  assertEquals(modelSpec("anthropic", "claude-haiku-4-5"), null);
  assertEquals(modelSpec("anthropic", "toString"), null);
  assertEquals(modelSpec("openai_compatible", "deepseek-flash")?.vendor, "deepseek");
  assertEquals(modelSpec("openai_compatible", "qwen/qwen3.8-27b")?.vendor, "groq");
  assertEquals(modelSpec("gemini", "gemini-3.5-flash")?.vendor, "gemini");
});

Deno.test("notice labels name companies only, never a model (D11)", () => {
  assertEquals(vendorLabels, {
    anthropic: "Anthropic",
    deepseek: "DeepSeek",
    groq: "Groq",
    gemini: "Google",
    router: "Evaluation router",
  });
  const modelWords = /claude|haiku|sonnet|opus|qwen|flash|gemini|llama|gpt/i;
  for (const label of Object.values(vendorLabels)) {
    assertEquals(modelWords.test(label), false, label);
  }
});

Deno.test("image limits: Claude keeps to 5 MB of base64, Groq and Gemini to today's 4 MiB", () => {
  assertEquals(models["claude-sonnet-5-5"].maxImageBytes, 3_750_000);
  assertEquals(models["qwen/qwen3.8-27b"].maxImageBytes, 4_194_304);
  assertEquals(models["gemini-3.5-flash"].maxImageBytes, 4_194_304);
  assertEquals(models["deepseek-flash"].maxImageBytes, 0);
});
