import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { fetchAllPages } from "./paging.ts";

function source(total: number) {
  const calls: Array<[number, number]> = [];
  const fetchPage = (from: number, to: number) => {
    calls.push([from, to]);
    const data = Array.from(
      { length: Math.max(0, Math.min(to + 1, total) - from) },
      (_, i) => from + i,
    );
    return Promise.resolve({ data, error: null });
  };
  return { calls, fetchPage };
}

Deno.test("paging reads every page until one comes back short", async () => {
  const { calls, fetchPage } = source(2500);
  const rows = await fetchAllPages(fetchPage, "x", 1000);
  assertEquals(rows.length, 2500);
  assertEquals(rows[2499], 2499);
  assertEquals(calls, [[0, 999], [1000, 1999], [2000, 2999]]);
});

Deno.test("paging asks once more when the last page is exactly full", async () => {
  const { calls, fetchPage } = source(2000);
  assertEquals((await fetchAllPages(fetchPage, "x", 1000)).length, 2000);
  assertEquals(calls.length, 3);
});

Deno.test("paging an empty list asks once", async () => {
  const { calls, fetchPage } = source(0);
  assertEquals(await fetchAllPages(fetchPage, "x", 1000), []);
  assertEquals(calls, [[0, 999]]);
});

Deno.test("a failed page throws the caller's code and nothing from the database", async () => {
  await assertRejects(
    () =>
      fetchAllPages(
        () => Promise.resolve({ data: null, error: { message: "secret detail" } }),
        "media_lookup_failed",
      ),
    Error,
    "media_lookup_failed",
  );
});
