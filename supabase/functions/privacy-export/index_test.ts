import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { addMedia, collectRows, csv, dataTables, encrypt, type RowsClient } from "./index.ts";

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

// A fake that serves `total` rows per table like PostgREST: at most `limit` rows from the range.
function fakeRows(totals: Record<string, number>, limit = 1000) {
  const requests: Array<
    { table: string; owner: string; order: string[]; range: [number, number] }
  > = [];
  const client: RowsClient = {
    from: (table) => ({
      select: () => ({
        eq: (owner, value) => {
          const order: string[] = [];
          const query = {
            order: (column: string) => {
              order.push(column);
              return query;
            },
            range: (from: number, to: number) => {
              requests.push({
                table,
                owner: `${owner}=${value}`,
                order: [...order],
                range: [from, to],
              });
              const total = totals[table] ?? 0;
              const end = Math.min(to + 1, from + limit, total);
              const data = Array.from({ length: Math.max(0, end - from) }, (_, i) => ({
                id: from + i,
                search_vector: "'x':1",
              }));
              return Promise.resolve({ data, error: null });
            },
          };
          return query;
        },
      }),
    }),
  };
  return { client, requests };
}

Deno.test("the export reads every page of a table with more than 1000 rows", async () => {
  const { client, requests } = fakeRows({ meals: 2300, coach_messages: 1000 });
  const rows = await collectRows(client, "user-1");
  assertEquals(rows.meals.length, 2300);
  assertEquals(rows.meals.at(-1)?.id, 2299);
  assertEquals(requests.filter((r) => r.table === "meals").map((r) => r.range), [
    [0, 999],
    [1000, 1999],
    [2000, 2999],
  ]);
  // A full last page needs one more request to learn that nothing follows.
  assertEquals(rows.coach_messages.length, 1000);
  assertEquals(requests.filter((r) => r.table === "coach_messages").length, 2);
  assertEquals(rows.user_profiles, []);
});

Deno.test("the export pages in a stable order and filters on the owner", async () => {
  const { client, requests } = fakeRows({});
  await collectRows(client, "user-1");
  const first = (table: string) => requests.find((r) => r.table === table)!;
  assertEquals(first("meals").order, ["id"]);
  assertEquals(first("meals").owner, "user_id=user-1");
  assertEquals(first("user_accounts").owner, "id=user-1");
  assertEquals(first("health_history_months").order, ["user_id", "month"]);
  assertEquals(first("exercise_set_heart_rate").order, ["exercise_set_id"]);
});

Deno.test("the export leaves out the derived search index of Coach messages", async () => {
  const { client } = fakeRows({ coach_messages: 2 });
  const rows = await collectRows(client, "user-1");
  assertEquals(rows.coach_messages, [{ id: 0 }, { id: 1 }]);
});

Deno.test("a failed page fails the export with the table's code", async () => {
  const { client } = fakeRows({});
  const failing: RowsClient = {
    from: (table) =>
      table === "meals"
        ? ({
          select: () => ({
            eq: () => {
              const query = {
                order: () => query,
                range: () => Promise.resolve({ data: null, error: { message: "detail" } }),
              };
              return query;
            },
          }),
        })
        : client.from(table),
  };
  await assertRejects(() => collectRows(failing, "user-1"), Error, "table_meals");
});
