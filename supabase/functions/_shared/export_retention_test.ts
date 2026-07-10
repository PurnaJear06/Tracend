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
  assertEquals(result, { claimed: 2, deleted: 1, failed: 1 });
  assertEquals(completions, [["one", true], ["two", false]]);
});
