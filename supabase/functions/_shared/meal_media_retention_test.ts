import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  cleanExpiredMealMedia,
  reportRetentionOutcome,
  runRetentionStages,
  sweepOrphanObjects,
} from "./meal_media_retention.ts";

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

  assertEquals(result, { claimed: 2, deleted: 1, failed: 1, unsafe: 0, unfinalized: 0 });
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

  assertEquals(result, { claimed: 2, deleted: 1, failed: 1, unsafe: 1, unfinalized: 0 });
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

Deno.test("a row whose result cannot be written back does not strand the rest of the batch", async () => {
  const completions: string[] = [];
  const removed: string[] = [];
  const result = await cleanExpiredMealMedia({
    claim: () =>
      Promise.resolve([
        { media_object_id: "media-1", object_key: "user/meal/one.jpg" },
        { media_object_id: "media-2", object_key: "user/meal/two.jpg" },
        { media_object_id: "media-3", object_key: "user/meal/three.jpg" },
      ]),
    remove: (key) => {
      removed.push(key);
      return Promise.resolve(true);
    },
    complete: (id) => {
      completions.push(id);
      if (id === "media-1") return Promise.reject(new Error("completion_failed"));
      return Promise.resolve();
    },
  });
  assertEquals(removed.length, 3);
  assertEquals(completions, ["media-1", "media-2", "media-3"]);
  assertEquals(result, { claimed: 3, deleted: 3, failed: 0, unsafe: 0, unfinalized: 1 });
});

Deno.test("a Storage error on one object still lets the others go", async () => {
  const completions: Array<[string, boolean]> = [];
  const result = await cleanExpiredMealMedia({
    claim: () =>
      Promise.resolve([
        { media_object_id: "media-1", object_key: "user/meal/one.jpg" },
        { media_object_id: "media-2", object_key: "user/meal/two.jpg" },
      ]),
    remove: (key) =>
      key.endsWith("one.jpg") ? Promise.reject(new Error("socket reset")) : Promise.resolve(true),
    complete: (id, ok) => {
      completions.push([id, ok]);
      return Promise.resolve();
    },
  });
  assertEquals(completions, [["media-1", false], ["media-2", true]]);
  assertEquals(result.deleted, 1);
  assertEquals(result.failed, 1);
});

Deno.test("a failing stage is reported by code and the later stages still run", async () => {
  const reports: Array<[string, string]> = [];
  const ran: string[] = [];
  const { results, failedStages } = await runRetentionStages([
    ["meal_media", () => {
      ran.push("meal_media");
      return Promise.reject(new Error("claim_failed"));
    }],
    ["export_retention", () => {
      ran.push("export_retention");
      return Promise.resolve({ claimed: 0 });
    }],
    ["orphan_sweep", () => {
      ran.push("orphan_sweep");
      return Promise.reject(new Error("user/meal/secret path with spaces.jpg"));
    }],
  ], (message, code) => reports.push([message, code]));
  assertEquals(ran, ["meal_media", "export_retention", "orphan_sweep"]);
  assertEquals(failedStages, ["meal_media", "orphan_sweep"]);
  assertEquals(results, { export_retention: { claimed: 0 } });
  assertEquals(reports, [
    ["retention_stage_failed_meal_media_claim_failed", "retention_stage_failed"],
    ["retention_stage_failed_orphan_sweep_unknown", "retention_stage_failed"],
  ]);
});

Deno.test("the retention report carries counts and codes, never keys", () => {
  const reports: Array<[string, string]> = [];
  reportRetentionOutcome({
    meals: { claimed: 9, deleted: 4, failed: 5, unsafe: 2, unfinalized: 1 },
    orphans: { listed: 3, removed: 0, failed: 2, unsafe: 1 },
    exportFailures: 1,
  }, (message, code) => reports.push([message, code]));
  assertEquals(reports, [
    ["meal_media_unsafe_keys_2", "unsafe_storage_key"],
    ["meal_media_removal_failed_3", "storage_removal_failed"],
    ["meal_media_unfinalized_1", "retention_completion_failed"],
    ["export_removal_failed_1", "storage_removal_failed"],
    ["orphan_unsafe_keys_1", "unsafe_storage_key"],
    ["orphan_removal_failed_2", "storage_removal_failed"],
  ]);
  const quiet: string[] = [];
  reportRetentionOutcome({
    meals: { claimed: 1, deleted: 1, failed: 0, unsafe: 0, unfinalized: 0 },
    orphans: null,
    exportFailures: 0,
  }, (message) => quiet.push(message));
  assertEquals(quiet, []);
});
