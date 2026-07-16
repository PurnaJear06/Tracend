import { analyzeGroqMealImage } from "./groq_meal_vision_provider.ts";

Deno.test("Groq Qwen meal adapter validates candidate output before persistence", async () => {
  const result = await analyzeGroqMealImage(
    new Uint8Array([1, 2, 3]),
    "image/jpeg",
    () =>
      Promise.resolve(
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
        })),
      ),
    {
      get: (name) =>
        ({
          MEAL_VISION_ENABLED: "true",
          MEAL_VISION_MODEL_EVALUATED: "true",
          GROQ_API_KEY: "synthetic-key",
          MEAL_VISION_MODEL: "qwen/qwen3.6-27b",
        })[name],
    },
  );
  if (result.candidates[0].name !== "Dal" || result.outputUnits !== 20) {
    throw new Error("Meal candidate parsing changed.");
  }
});
