import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { FakeQuery, type Row } from "./fake_postgrest.ts";
import { fetchAllByKey } from "./paging.ts";

const key = (n: number) => String(n).padStart(6, "0");
const table = (count: number): Row[] => Array.from({ length: count }, (_, i) => ({ id: key(i) }));

// Reads `rows` by keyset pages; `between` runs before each request after the first.
function read(
  rows: Row[],
  options: { size?: number; maxRows?: number; between?: (request: number) => void } = {},
) {
  const requests: Array<string | null> = [];
  let count = 0;
  return {
    requests,
    done: fetchAllByKey<Row>(
      (after, size) => {
        requests.push(after);
        const query = new FakeQuery(() => rows, options.maxRows ?? 1000, () => {
          if (count++ > 0) options.between?.(count);
        });
        return (after === null ? query : query.gt("id", after)).order("id").limit(size);
      },
      (row) => row.id,
      "x",
      options.size ?? 1000,
    ),
  };
}

Deno.test("paging reads every row, then stops on the first empty page", async () => {
  const run = read(table(2500));
  const rows = await run.done;
  assertEquals(rows.length, 2500);
  assertEquals(rows.map((row) => row.id), table(2500).map((row) => row.id));
  assertEquals(run.requests, [null, key(999), key(1999), key(2499)]);
});

Deno.test("paging an empty list asks once", async () => {
  const run = read([]);
  assertEquals(await run.done, []);
  assertEquals(run.requests, [null]);
});

Deno.test("a server that caps a response below the page size does not end the list early", async () => {
  const run = read(table(1200), { size: 1000, maxRows: 400 });
  assertEquals((await run.done).length, 1200);
});

// Rows go and arrive behind and ahead of the page being read.
function churn(rows: Row[], request: number) {
  const drop = (id: string) => rows.splice(rows.findIndex((row) => row.id === id), 1);
  if (request === 2) {
    for (let i = 0; i < 50; i++) drop(key(i * 10));
    rows.push({ id: "000000a" });
  } else if (request === 3) {
    for (let i = 0; i < 20; i++) drop(key(2000 + i));
    rows.push({ id: key(2500) + "z" });
  }
}

Deno.test("rows inserted and deleted between pages never repeat or skip a row that stays", async () => {
  const rows = table(3000);
  const stays = new Set(rows.map((row) => row.id as string));
  const run = read(rows, { between: (request) => churn(rows, request) });
  const ids = (await run.done).map((row) => row.id as string);
  assertEquals(new Set(ids).size, ids.length, "no row repeats");
  for (const id of rows.map((row) => row.id as string)) {
    if (stays.has(id)) assertEquals(ids.includes(id), true, `${id} is read`);
  }
});

Deno.test("control: offset pages lose a row under the same churn", async () => {
  const rows = table(3000);
  const stays = new Set(rows.map((row) => row.id as string));
  const seen: string[] = [];
  for (let from = 0, request = 0;; from += 1000) {
    if (request++ > 0) churn(rows, request);
    const page = [...rows].sort((a, b) => (a.id as string) < (b.id as string) ? -1 : 1)
      .slice(from, from + 1000);
    seen.push(...page.map((row) => row.id as string));
    if (page.length < 1000) break;
  }
  const lost = rows.map((row) => row.id as string).filter((id) =>
    stays.has(id) && !seen.includes(id)
  );
  assertEquals(lost.length > 0, true);
});

Deno.test("a failed page throws the caller's code and nothing from the database", async () => {
  await assertRejects(
    () =>
      fetchAllByKey<Row>(
        () => new FakeQuery(() => [], 1000, () => {}, true),
        (row) => row.id,
        "media_lookup_failed",
      ),
    Error,
    "media_lookup_failed",
  );
});

Deno.test("a key that does not move forward stops the read instead of looping", async () => {
  await assertRejects(
    () =>
      fetchAllByKey<Row>(
        () => Promise.resolve({ data: [{ id: "a" }], error: null }),
        (row) => row.id,
        "paging_stuck",
      ),
    Error,
    "paging_stuck",
  );
});
