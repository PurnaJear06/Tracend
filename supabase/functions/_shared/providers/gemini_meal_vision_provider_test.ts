import { assertRejects } from "jsr:@std/assert@1.0.13";
import { analyzeMealImage } from "./gemini_meal_vision_provider.ts";

Deno.test("meal vision fails closed until every live gate is enabled", async () => {
  await assertRejects(
    () =>
      analyzeMealImage(
        new Uint8Array([1]),
        "image/jpeg",
        fetch,
        { get: () => undefined },
      ),
    Error,
    "meal_vision_disabled",
  );
});

Deno.test("meal vision rejects Flash-Lite configuration", async () => {
  await assertRejects(
    () =>
      analyzeMealImage(
        new Uint8Array([1]),
        "image/jpeg",
        fetch,
        {
          get: (name) =>
            ({
              GEMINI_API_KEY: "test-key",
              GEMINI_PAID_DATA_TERMS_ACCEPTED: "true",
              MEAL_VISION_ENABLED: "true",
              MEAL_VISION_MODEL: "gemini-3.1-flash-lite",
              MEAL_VISION_MODEL_EVALUATED: "true",
            })[name],
        },
      ),
    Error,
    "meal_vision_configuration_invalid",
  );
});
