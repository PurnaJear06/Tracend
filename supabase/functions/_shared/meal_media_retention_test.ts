import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { cleanExpiredMealMedia } from "./meal_media_retention.ts";

Deno.test("retention removes claimed objects and finalizes each result", async () => {
  const completions: Array<[string, boolean]> = [];
  const result = await cleanExpiredMealMedia({
    claim: () =>
      Promise.resolve([
        { media_object_id: "media-1", object_key: "user/meal/one.jpg" },
        { media_object_id: "media-2", object_key: "user/meal/two.jpg" },
      ]),
    remove: (key) => Promise.resolve(key.endsWith("one.jpg")),
    complete: (id, succeeded) => {
      completions.push([id, succeeded]);
      return Promise.resolve();
    },
  });

  assertEquals(result, { claimed: 2, deleted: 1, failed: 1 });
  assertEquals(completions, [["media-1", true], ["media-2", false]]);
});

Deno.test("retention rejects unbounded batches", async () => {
  await assertRejects(
    () =>
      cleanExpiredMealMedia({
        claim: () => Promise.resolve([]),
        remove: () => Promise.resolve(true),
        complete: () => Promise.resolve(),
      }, 101),
    Error,
    "invalid_batch_size",
  );
});
