import { analyzeGroqMealImage } from "./groq_meal_vision_provider.ts";

const candidateReply = () =>
  new Response(JSON.stringify({
    choices: [{
      message: {
        content: JSON.stringify({
          candidates: [{
            name: "Dal",
            serving_label: "1 bowl",
            calories: 180,
            protein_g: 9,
            carbohydrate_g: 24,
            fat_g: 5,
            confidence: "low",
            assumptions: ["Oil is uncertain"],
            question: "Was ghee added?",
          }],
        }),
      },
    }],
    usage: { prompt_tokens: 12, completion_tokens: 20 },
  }));

const environment = (values: Record<string, string>) => ({
  get: (name: string) =>
    ({
      MEAL_VISION_ENABLED: "true",
      MEAL_VISION_MODEL_EVALUATED: "true",
      GROQ_API_KEY: "synthetic-key",
      ...values,
    })[name],
});

Deno.test("Groq Qwen meal adapter validates candidate output before persistence", async () => {
  const result = await analyzeGroqMealImage(
    new Uint8Array([1, 2, 3]),
    "image/jpeg",
    () => Promise.resolve(candidateReply()),
    environment({ MEAL_VISION_MODEL: "qwen/qwen3.8-27b" }),
  );
  if (result.candidates[0].name !== "Dal" || result.outputUnits !== 20) {
    throw new Error("Meal candidate parsing changed.");
  }
});

Deno.test("Groq meal cost uses qwen3.8 rates, not the retired route's GROQ_* secrets", async () => {
  const result = await analyzeGroqMealImage(
    new Uint8Array([1, 2, 3]),
    "image/jpeg",
    () => Promise.resolve(candidateReply()),
    environment({
      GROQ_INPUT_COST_PER_MILLION_USD: "0.6",
      GROQ_OUTPUT_COST_PER_MILLION_USD: "3",
    }),
  );
  // 12 input tokens at USD 0.80/M and 20 output tokens at USD 4.00/M.
  const expected = (12 * 0.8 + 20 * 4) / 1_000_000;
  if (Math.abs(result.estimatedCostUsd - expected) > 1e-12) {
    throw new Error(`Unexpected cost estimate: ${result.estimatedCostUsd}`);
  }
});

Deno.test("Groq meal adapter defaults to qwen3.8, the successor of the retired qwen3.6", async () => {
  let sentModel = "";
  const result = await analyzeGroqMealImage(
    new Uint8Array([1, 2, 3]),
    "image/jpeg",
    (_input, init) => {
      sentModel = JSON.parse(String(init?.body)).model;
      return Promise.resolve(candidateReply());
    },
    environment({}),
  );
  if (sentModel !== "qwen/qwen3.8-27b" || result.model !== "qwen/qwen3.8-27b") {
    throw new Error(`Unexpected meal vision model: ${sentModel}`);
  }
});

Deno.test("Groq meal adapter refuses the retired qwen3.6 model before calling Groq", async () => {
  let called = false;
  let message = "";
  try {
    await analyzeGroqMealImage(
      new Uint8Array([1, 2, 3]),
      "image/jpeg",
      () => {
        called = true;
        return Promise.resolve(candidateReply());
      },
      environment({ MEAL_VISION_MODEL: "qwen/qwen3.6-27b" }),
    );
  } catch (error) {
    message = error instanceof Error ? error.message : String(error);
  }
  if (called || message !== "meal_vision_configuration_invalid") {
    throw new Error(`Retired model was not refused: ${message}`);
  }
});
