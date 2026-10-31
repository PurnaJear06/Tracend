import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { FakeQuery, type Row } from "../_shared/fake_postgrest.ts";
import {
  deletableKeys,
  isExactDeletionConfirmation,
  listAccountStorage,
  reportUnsafeKeys,
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

const pad = (n: number) => String(n).padStart(6, "0");

// A fake database for the three lists. `onRequest` runs before each answer.
function fakeListing(
  data: { media: Row[]; exports: Row[]; objects: Row[] },
  options: { maxRows?: number; failOn?: "media" | "exports" | "objects"; onRequest?: () => void } =
    {},
) {
  const make = (kind: "media" | "exports" | "objects") =>
    new FakeQuery(
      () => data[kind],
      options.maxRows ?? 1000,
      () => options.onRequest?.(),
      options.failOn === kind,
    );
  const wrap = (query: FakeQuery) => {
    const wrapped = {
      gt: (column: string, value: string) => (query.gt(column, value), wrapped),
      order: (column: string) => (query.order(column), wrapped),
      limit: (count: number) => query.limit(count),
    };
    return wrapped;
  };
  const client = {
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          neq: () => wrap(make("media")),
          not: () => wrap(make(table === "data_exports" ? "exports" : "media")),
        }),
      }),
    }),
    rpc: () => ({
      eq: (column: string, value: string) => wrap(make("objects").eq(column, value)),
    }),
  } as unknown as StorageListingClient;
  return client;
}

const media = (n: number): Row[] =>
  Array.from(
    { length: n },
    (_, i) => ({ id: pad(i), purpose: "meal_analysis", object_key: `u/m/${i}.jpg` }),
  );
const exportRows = (n: number): Row[] =>
  Array.from({ length: n }, (_, i) => ({ id: pad(i), storage_path: `u/${i}.tracendexport` }));
const objects = (n: number, bucket = "progress-photos"): Row[] =>
  Array.from({ length: n }, (_, i) => ({ bucket_id: bucket, name: `u/p/${pad(i)}.jpg` }));

Deno.test("account deletion lists every media row, export and Storage object past 1000", async () => {
  const listed = await listAccountStorage(
    fakeListing({
      media: media(2300),
      exports: exportRows(1000),
      objects: [...objects(1500), ...objects(1200, "meal-images"), ...objects(3, "other-bucket")],
    }),
    "u",
  );
  assertEquals(listed.media.length, 2300);
  assertEquals(listed.exports.length, 1000);
  assertEquals(listed.objects.length, 2700);
  assertEquals(listed.objects.filter((o) => o.bucket_id === "progress-photos").length, 1500);
  assertEquals(listed.objects.filter((o) => o.bucket_id === "meal-images").length, 1200);
});

Deno.test("a server that caps responses below the page size still lists everything", async () => {
  const listed = await listAccountStorage(
    fakeListing({ media: media(900), exports: exportRows(10), objects: objects(700) }, {
      maxRows: 250,
    }),
    "u",
  );
  assertEquals([listed.media.length, listed.exports.length, listed.objects.length], [900, 10, 700]);
});

Deno.test("rows that go while the lists are read never make deletion skip a file that stays", async () => {
  const data = { media: media(2500), exports: [], objects: objects(2500) };
  const stays = data.media.map((row) => row.id as string);
  let requests = 0;
  const listed = await listAccountStorage(
    fakeListing(data, {
      onRequest: () => {
        // After the first media page: 40 media rows already listed are deleted.
        if (++requests === 2) {
          for (let i = 0; i < 40; i++) {
            data.media.splice(data.media.findIndex((r) => r.id === pad(i * 3)), 1);
          }
        }
      },
    }),
    "u",
  );
  const ids = listed.media.map((row) => row.id as string);
  assertEquals(new Set(ids).size, ids.length);
  for (const id of stays) assertEquals(ids.includes(id), true, id);
  assertEquals(listed.objects.length, 2500);
});

Deno.test("a failed listing stops the deletion with a code instead of skipping files", async () => {
  for (
    const [kind, code] of [
      ["media", "media_lookup_failed"],
      ["exports", "export_lookup_failed"],
      ["objects", "storage_listing_failed"],
    ] as const
  ) {
    const client = fakeListing({ media: media(1), exports: exportRows(1), objects: objects(1) }, {
      failOn: kind,
    });
    await assertRejects(() => listAccountStorage(client, "u"), Error, code);
  }
});

Deno.test("the unsafe-key report to Sentry carries no user id", () => {
  const sent: string[] = [];
  const realFetch = globalThis.fetch;
  Deno.env.set("SENTRY_DSN", "https://publickey@sentry.example.com/12345");
  globalThis.fetch = ((_url: unknown, init?: { body?: string }) => {
    sent.push(String(init?.body));
    return Promise.resolve(new Response("{}"));
  }) as typeof fetch;
  try {
    reportUnsafeKeys(2);
  } finally {
    globalThis.fetch = realFetch;
    Deno.env.delete("SENTRY_DSN");
  }
  assertEquals(sent.length, 1);
  const event = JSON.parse(sent[0]);
  assertEquals(event.exception.values[0].value, "unsafe_storage_key");
  assertEquals(event.extra.count, 2);
  assertEquals(event.user, undefined);
  assert(!sent[0].includes("userId"));
});
