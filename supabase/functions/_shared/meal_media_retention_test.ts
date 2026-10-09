import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { cleanExpiredMealMedia, sweepOrphanObjects } from "./meal_media_retention.ts";

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

  assertEquals(result, { claimed: 2, deleted: 1, failed: 1, unsafe: 0 });
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

Deno.test("retention never sends an unsafe key to Storage", async () => {
  const removed: string[] = [];
  const completions: Array<[string, boolean]> = [];
  const result = await cleanExpiredMealMedia({
    claim: () =>
      Promise.resolve([
        { media_object_id: "media-1", object_key: "user/meal/../../other/meal/a.jpg" },
        { media_object_id: "media-2", object_key: "user/meal/b.jpg" },
      ]),
    remove: (key) => {
      removed.push(key);
      return Promise.resolve(true);
    },
    complete: (id, succeeded) => {
      completions.push([id, succeeded]);
      return Promise.resolve();
    },
  });

  assertEquals(result, { claimed: 2, deleted: 1, failed: 1, unsafe: 1 });
  assertEquals(removed, ["user/meal/b.jpg"]);
  assertEquals(completions, [["media-1", false], ["media-2", true]]);
});

Deno.test("the orphan sweep removes safe names and counts the rest", async () => {
  const removed: string[] = [];
  const result = await sweepOrphanObjects({
    list: () =>
      Promise.resolve([
        { bucket_id: "meal-images", name: "user/meal/a.jpg" },
        { bucket_id: "progress-photos", name: "user/progress/../../other/b.jpg" },
        { bucket_id: "avatars", name: "user/c.jpg" },
        { bucket_id: "account-exports", name: "user/d.tracendexport" },
      ]),
    remove: (bucket, name) => {
      removed.push(`${bucket}:${name}`);
      return Promise.resolve(name.endsWith("a.jpg"));
    },
  });
  assertEquals(result, { listed: 4, removed: 1, failed: 1, unsafe: 2 });
  assertEquals(removed, ["meal-images:user/meal/a.jpg", "account-exports:user/d.tracendexport"]);
});
