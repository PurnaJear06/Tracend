import { assertEquals } from "jsr:@std/assert@1.0.14";
import { cleanExpiredExports } from "./export_retention.ts";

Deno.test("export retention clears successful objects and preserves failures for retry", async () => {
  const completions: Array<[string, boolean]> = [];
  const result = await cleanExpiredExports({
    claim: () => Promise.resolve([{ storage_path: "one" }, { storage_path: "two" }]),
    remove: (path) => Promise.resolve(path === "one"),
    complete: (path, succeeded) => {
      completions.push([path, succeeded]);
      return Promise.resolve();
    },
  });
  assertEquals(result, { claimed: 2, deleted: 1, failed: 1, unfinalized: 0 });
  assertEquals(completions, [["one", true], ["two", false]]);
});

Deno.test("export retention never sends an unsafe path to Storage", async () => {
  const removed: string[] = [];
  const result = await cleanExpiredExports({
    claim: () => Promise.resolve([{ storage_path: "user/../other/x" }, { storage_path: "user/y" }]),
    remove: (path) => {
      removed.push(path);
      return Promise.resolve(true);
    },
    complete: () => Promise.resolve(),
  });
  assertEquals(result, { claimed: 2, deleted: 1, failed: 1, unfinalized: 0 });
  assertEquals(removed, ["user/y"]);
});

Deno.test("an export whose result cannot be written back does not strand the rest of the batch", async () => {
  const completions: string[] = [];
  const result = await cleanExpiredExports({
    claim: () => Promise.resolve([{ storage_path: "u/one" }, { storage_path: "u/two" }]),
    remove: () => Promise.resolve(true),
    complete: (path) => {
      completions.push(path);
      return path === "u/one"
        ? Promise.reject(new Error("export_completion_failed"))
        : Promise.resolve();
    },
  });
  assertEquals(completions, ["u/one", "u/two"]);
  assertEquals(result, { claimed: 2, deleted: 2, failed: 0, unfinalized: 1 });
});
