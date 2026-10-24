import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  deletableKeys,
  isExactDeletionConfirmation,
  listAccountStorage,
  type StorageListingClient,
} from "./index.ts";

Deno.test("account deletion requires the exact destructive phrase", () => {
  assertEquals(isExactDeletionConfirmation("DELETE"), true);
  assertEquals(isExactDeletionConfirmation("delete"), false);
  assertEquals(isExactDeletionConfirmation("DELETE "), false);
});

Deno.test("account deletion sends Storage only safe keys in the user's folder", () => {
  const user = "11111111-1111-4111-8111-111111111111";
  assertEquals(
    deletableKeys(user, [
      `${user}/meal/a.jpg`,
      `${user}/meal/../../22222222-2222-4222-8222-222222222222/meal/b.jpg`,
      "22222222-2222-4222-8222-222222222222/meal/c.jpg",
      null,
    ]),
    { keys: [`${user}/meal/a.jpg`], unsafe: 2 },
  );
});

Deno.test("a key listed twice is removed once", () => {
  const user = "11111111-1111-4111-8111-111111111111";
  assertEquals(
    deletableKeys(user, [`${user}/meal/a.jpg`, `${user}/meal/a.jpg`]),
    { keys: [`${user}/meal/a.jpg`], unsafe: 0 },
  );
});

// Serves lists like PostgREST: at most 1000 rows from the requested range.
function fakeListing(totals: { media: number; exports: number; objects: number }, failOn = "") {
  const ranges: Record<string, Array<[number, number]>> = { media: [], exports: [], objects: [] };
  const page = (kind: keyof typeof totals, make: (i: number) => Record<string, unknown>) => {
    const query = {
      order: () => query,
      range: (from: number, to: number) => {
        ranges[kind].push([from, to]);
        if (failOn === kind) return Promise.resolve({ data: null, error: { message: "detail" } });
        const end = Math.min(to + 1, from + 1000, totals[kind]);
        return Promise.resolve({
          data: Array.from({ length: Math.max(0, end - from) }, (_, i) => make(from + i)),
          error: null,
        });
      },
    };
    return query;
  };
  const client = {
    from: () => ({
      select: () => ({
        eq: () => ({
          neq: () =>
            page("media", (i) => ({ purpose: "meal_analysis", object_key: `u/m/${i}.jpg` })),
          not: () => page("exports", (i) => ({ storage_path: `u/${i}.tracendexport` })),
        }),
      }),
    }),
    rpc: () => page("objects", (i) => ({ bucket_id: "progress-photos", name: `u/p/${i}.jpg` })),
  } as unknown as StorageListingClient;
  return { client, ranges };
}

Deno.test("account deletion lists every media row, export and Storage object past 1000", async () => {
  const { client, ranges } = fakeListing({ media: 2300, exports: 1000, objects: 1500 });
  const listed = await listAccountStorage(client, "u");
  assertEquals(listed.media.length, 2300);
  assertEquals(listed.exports.length, 1000);
  assertEquals(listed.objects.length, 1500);
  assertEquals(listed.objects.at(-1)?.name, "u/p/1499.jpg");
  assertEquals(ranges.media, [[0, 999], [1000, 1999], [2000, 2999]]);
  assertEquals(ranges.exports, [[0, 999], [1000, 1999]]);
  assertEquals(ranges.objects, [[0, 999], [1000, 1999]]);
});

Deno.test("a failed listing stops the deletion with a code instead of skipping files", async () => {
  for (
    const [kind, code] of [
      ["media", "media_lookup_failed"],
      ["exports", "export_lookup_failed"],
      ["objects", "storage_listing_failed"],
    ] as const
  ) {
    const { client } = fakeListing({ media: 1, exports: 1, objects: 1 }, kind);
    await assertRejects(() => listAccountStorage(client, "u"), Error, code);
  }
});
