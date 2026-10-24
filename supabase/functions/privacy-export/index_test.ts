import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { FakeQuery, type Row } from "../_shared/fake_postgrest.ts";
import {
  addMedia,
  collectRows,
  csv,
  csvPointer,
  dataTables,
  encrypt,
  exportExclusions,
  omittedColumns,
  type RowsClient,
} from "./index.ts";

Deno.test("CSV preserves user-readable fields and quotes", () => {
  assertEquals(csv([{ value: "a,b", count: 2 }]), '"value","count"\n"a,b","2"');
});

Deno.test("the export includes each set's heart-rate summary", () => {
  assert(dataTables.includes("exercise_set_heart_rate"));
});

Deno.test("the export includes the sleeping heart rate kept in shadow mode", () => {
  assert(dataTables.includes("sleeping_heart_rate_nights"));
});

Deno.test("the export includes the pre-exercise screening answers", () => {
  assert(dataTables.includes("onboarding_screenings"));
});

Deno.test("the export includes the same-day adjustments the athlete answered", () => {
  assert(dataTables.includes("day_adjustments"));
});

Deno.test("the export includes the pain checks the athlete made", () => {
  assert(dataTables.includes("pain_reports"));
});

Deno.test("the export includes the facts the athlete confirmed and the Coach's notes", () => {
  assert(dataTables.includes("coach_facts"));
  assert(dataTables.includes("coach_notes"));
});

Deno.test("export bytes are encrypted and contain no plaintext payload", async () => {
  const plaintext = new TextEncoder().encode("private-health-export-marker");
  const encrypted = await encrypt(plaintext, "correct horse battery staple");
  const output = new TextDecoder().decode(encrypted);
  assert(output.startsWith('{"format":"tracend-export"'));
  assert(!output.includes("private-health-export-marker"));
  assert(output.includes('"encryption":"AES-256-GCM"'));
});

Deno.test("export downloads only safe keys in the user's own folder", async () => {
  const user = "11111111-1111-4111-8111-111111111111";
  const requested: string[] = [];
  const client = {
    storage: {
      from: (_bucket: string) => ({
        download: (key: string) => {
          requested.push(key);
          return Promise.resolve({ data: new Blob([new Uint8Array([1])]), error: null });
        },
      }),
    },
  };
  const files: Record<string, Uint8Array> = {};
  const skipped = await addMedia(files, client, {
    media_objects: [
      { id: "a", purpose: "meal_analysis", object_key: `${user}/meal/a.jpg` },
      { id: "b", purpose: "meal_analysis", object_key: `${user}/meal/../../other/x` },
      {
        id: "c",
        purpose: "progress_front",
        object_key: "22222222-2222-4222-8222-222222222222/x.jpg",
      },
    ],
  }, user);
  assertEquals(requested, [`${user}/meal/a.jpg`]);
  assertEquals(skipped, ["b", "c"]);
  assertEquals(Object.keys(files), ["media/meal_analysis/a-a.jpg"]);
});

Deno.test("the export includes the Coach conversation and the athlete's other stored records", () => {
  for (
    const table of [
      "coach_threads",
      "coach_messages",
      "coach_narrative_entries",
      "coach_session_summaries",
      "coach_context_snapshots",
      "user_preferences",
      "nutrition_schedule_versions",
      "nutrition_schedule_items",
      "health_workout_references",
      "workout_reconciliations",
      "daily_computed_metrics",
      "metric_baseline_history",
      "user_baselines",
      "data_exports",
      "deletion_requests",
    ]
  ) assert(dataTables.includes(table as (typeof dataTables)[number]), table);
});

// A fake database: `tables` hold rows per table; PostgREST caps a response at `maxRows`.
function fakeDatabase(
  tables: Record<string, Row[]>,
  options: {
    maxRows?: number;
    onRequest?: (table: string, request: number) => void;
    linked?: unknown;
    failTable?: string;
  } = {},
) {
  const requests: Array<{ table: string; owner: string; after: string | null; order: string[] }> =
    [];
  let count = 0;
  const client: RowsClient = {
    from: (table) => ({
      select: () => ({
        eq: (owner, value) => {
          const entry = {
            table,
            owner: `${owner}=${value}`,
            after: null as string | null,
            order: [] as string[],
          };
          requests.push(entry);
          const query = new FakeQuery(
            () => (tables[table] ?? []).filter((row) => row[owner] === value),
            options.maxRows ?? 1000,
            () => options.onRequest?.(table, count++),
            options.failTable === table,
          );
          const wrapped = {
            gt: (column: string, after: string) => {
              entry.after = after;
              query.gt(column, after);
              return wrapped;
            },
            order: (column: string) => {
              entry.order.push(column);
              query.order(column);
              return wrapped;
            },
            limit: (size: number) => query.limit(size),
          };
          return wrapped;
        },
      }),
    }),
    rpc: () =>
      Promise.resolve({
        data: options.linked ?? { schema_version: "1.0", signup_invites: [], waitlist_signups: [] },
        error: null,
      }),
  };
  return { client, requests };
}

const ids = (count: number, extra: Row = {}): Row[] =>
  Array.from({ length: count }, (_, i) => ({
    id: String(i).padStart(6, "0"),
    user_id: "user-1",
    ...extra,
  }));

Deno.test("the export reads every row of a table with more than 1000 rows", async () => {
  const { client, requests } = fakeDatabase({ meals: ids(2300), coach_messages: ids(1000) });
  const rows = await collectRows(client, "user-1");
  assertEquals(rows.meals.length, 2300);
  assertEquals(rows.meals.at(-1)?.id, "002299");
  assertEquals(requests.filter((r) => r.table === "meals").map((r) => r.after), [
    null,
    "000999",
    "001999",
    "002299",
  ]);
  assertEquals(rows.coach_messages.length, 1000);
  assertEquals(rows.user_profiles, []);
});

Deno.test("a server that caps responses below the page size still gives the whole table", async () => {
  const { client } = fakeDatabase({ meals: ids(1500) }, { maxRows: 300 });
  assertEquals((await collectRows(client, "user-1")).meals.length, 1500);
});

Deno.test("rows that appear or go while the export reads never repeat or skip a row that stays", async () => {
  const meals = ids(2500);
  const initial = meals.map((row) => row.id as string);
  let mealRequests = 0;
  const { client } = fakeDatabase({ meals }, {
    onRequest: (table) => {
      if (table !== "meals" || ++mealRequests !== 2) return;
      // After the first page: 30 rows already read go, and one arrives before them.
      for (let i = 0; i < 30; i++) {
        meals.splice(meals.findIndex((row) => row.id === String(i * 2 + 10).padStart(6, "0")), 1);
      }
      meals.push({ id: "0000009", user_id: "user-1" });
    },
  });
  const read = (await collectRows(client, "user-1")).meals.map((row) => row.id as string);
  assertEquals(mealRequests >= 3, true);
  assertEquals(new Set(read).size, read.length);
  for (const id of initial) {
    if (meals.some((row) => row.id === id) || id <= "000999") {
      assertEquals(read.includes(id), true, id);
    }
  }
});

Deno.test("the export pages in key order and filters on the owner", async () => {
  const { client, requests } = fakeDatabase({});
  await collectRows(client, "user-1");
  const first = (table: string) => requests.find((r) => r.table === table)!;
  assertEquals(first("meals").order, ["id"]);
  assertEquals(first("meals").owner, "user_id=user-1");
  assertEquals(first("user_accounts").owner, "id=user-1");
  assertEquals(first("health_history_months").order, ["month"]);
  assertEquals(first("sleeping_heart_rate_nights").order, ["local_date"]);
  assertEquals(first("exercise_set_heart_rate").order, ["exercise_set_id"]);
  assertEquals(first("user_profiles").order, ["user_id"]);
});

Deno.test("the export leaves out the columns it lists as omitted", async () => {
  const { client } = fakeDatabase({
    coach_messages: ids(1, {
      content: "hello",
      search_vector: "'x':1",
      guard_faults: ["a"],
      lookups: ["b"],
      lookup_rounds: [1],
      library_version: "abc",
    }),
    coach_context_snapshots: ids(1, { context: { big: "x".repeat(50_000) }, trigger_kind: "chat" }),
    data_exports: ids(1, { status: "ready", storage_path: "p", queue_message_id: 4 }),
    deletion_requests: ids(1, { status: "queued", queue_message_id: 5 }),
  });
  const rows = await collectRows(client, "user-1");
  assertEquals(rows.coach_messages, [{ id: "000000", user_id: "user-1", content: "hello" }]);
  assertEquals(rows.coach_context_snapshots, [
    { id: "000000", user_id: "user-1", trigger_kind: "chat" },
  ]);
  assertEquals(rows.data_exports, [{ id: "000000", user_id: "user-1", status: "ready" }]);
  assertEquals(rows.deletion_requests, [{ id: "000000", user_id: "user-1", status: "queued" }]);
  for (const [table, columns] of Object.entries(omittedColumns)) {
    for (const [column, reason] of Object.entries(columns)) {
      assert(reason.length >= 20, `${table}.${column} needs a reason`);
    }
  }
});

Deno.test("the AI budget ledger is excluded with a reason, not exported", () => {
  assert(!dataTables.includes("ai_budget_reservations" as (typeof dataTables)[number]));
  assert(exportExclusions["public.ai_budget_reservations"].includes("ai_usage_events"));
});

Deno.test("the invite and waitlist rows tied to the account join the export", async () => {
  const linked = {
    schema_version: "1.0",
    signup_invites: [{ email: "a@example.com", claimed_at: "2026-10-01T00:00:00Z" }],
    waitlist_signups: [{ email: "a@example.com", status: "confirmed" }],
  };
  const { client } = fakeDatabase({}, { linked });
  const rows = await collectRows(client, "user-1", "a@example.com");
  assertEquals(rows.signup_invites, linked.signup_invites);
  assertEquals(rows.waitlist_signups, linked.waitlist_signups);
});

Deno.test("a failed page or a failed linked read fails the export with a code", async () => {
  await assertRejects(
    () => collectRows(fakeDatabase({}, { failTable: "meals" }).client, "user-1"),
    Error,
    "table_meals",
  );
  const broken = fakeDatabase({}).client;
  broken.rpc = () => Promise.resolve({ data: null, error: { message: "detail" } });
  await assertRejects(() => collectRows(broken, "user-1"), Error, "table_linked");
});

Deno.test("an account whose rows pass the memory limit fails with a code, before the zip is built", async () => {
  const { client } = fakeDatabase({ meals: ids(2000, { note: "x".repeat(500) }) });
  const error = await assertRejects(() => collectRows(client, "user-1", null, 100_000), Error);
  assertEquals(error.message, "export_too_large");
  assert(/^[a-z0-9_]+$/.test(error.message), "the code passes fail_data_export's check");
});

Deno.test("a long JSON value is not repeated in the CSV", () => {
  const long = { text: "y".repeat(3000) };
  const short = { a: 1 };
  const text = csv([{ id: "1", long, short, plain: "z".repeat(3000) }]);
  assert(text.includes(csvPointer));
  assert(!text.includes("y".repeat(100)));
  assert(text.includes('"{""a"":1}"'));
  assert(text.includes("z".repeat(3000)), "plain text is never replaced");
});

Deno.test("media that retention is deleting or that is already gone does not fail the export", async () => {
  const user = "11111111-1111-4111-8111-111111111111";
  const client = {
    storage: {
      from: () => ({
        download: (key: string) =>
          Promise.resolve(
            key.endsWith("gone.jpg")
              ? { data: null, error: { statusCode: "404", message: "Object not found" } }
              : { data: new Blob([new Uint8Array([1])]), error: null },
          ),
      }),
    },
  };
  const files: Record<string, Uint8Array> = {};
  const skipped = await addMedia(files, client, {
    media_objects: [
      {
        id: "a",
        purpose: "meal_analysis",
        object_key: `${user}/meal/a.jpg`,
        lifecycle_status: "active",
      },
      {
        id: "b",
        purpose: "meal_analysis",
        object_key: `${user}/meal/b.jpg`,
        lifecycle_status: "pending_deletion",
      },
      {
        id: "c",
        purpose: "meal_analysis",
        object_key: `${user}/meal/gone.jpg`,
        lifecycle_status: "active",
      },
    ],
  }, user);
  assertEquals(skipped, ["b", "c"]);
  assertEquals(Object.keys(files), ["media/meal_analysis/a-a.jpg"]);
});

Deno.test("another download error still fails the export, and so does too much media", async () => {
  const user = "11111111-1111-4111-8111-111111111111";
  const media = {
    media_objects: [
      {
        id: "a",
        purpose: "meal_analysis",
        object_key: `${user}/meal/a.jpg`,
        lifecycle_status: "active",
      },
    ],
  };
  const failing = {
    storage: {
      from: () => ({
        download: () =>
          Promise.resolve({ data: null, error: { statusCode: "500", message: "boom" } }),
      }),
    },
  };
  await assertRejects(() => addMedia({}, failing, media, user), Error, "media_download_failed");
  const big = {
    storage: {
      from: () => ({
        download: () => Promise.resolve({ data: new Blob([new Uint8Array(100)]), error: null }),
      }),
    },
  };
  await assertRejects(() => addMedia({}, big, media, user, 50), Error, "export_too_large");
});
