import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { renderCoachContext, validateCoachContextContributors } from "../coach_context/host.ts";
import {
  createLibraryContributor,
  libraryBudgetChars,
  libraryContributorId,
  libraryEmbedDeadlineMs,
  libraryMatchCount,
  type LibraryRow,
  type LibrarySearchRequest,
  renderLibraryChunks,
  unshownKeysIn,
} from "./retrieval.ts";
import { librarySearchViaRpc } from "./live.ts";

const row = (
  key: string,
  body = "Body text.",
  section = "Results",
  title = "A title",
  year: number | null = 2020,
): LibraryRow => ({
  sourceId: key,
  title,
  year,
  header: `Source: Author 2020, ${title}. Section: ${section}.`,
  body,
});

const rows = [
  row(
    "schoenfeld_2017_weekly_volume",
    "Ten or more weekly sets gave more growth.",
    "Results",
    "Weekly volume",
    2017,
  ),
  row(
    "pelland_2026_volume_frequency",
    "Gains slow as sets increase.",
    "Results",
    "Volume and frequency",
    2026,
  ),
];

Deno.test("chunks render with their source id first, best first", () => {
  const block = renderLibraryChunks(rows)!;
  const text = block.text;
  assertStringIncludes(text, "Cite a source only by an id listed here.");
  const first = text.indexOf("[source: schoenfeld_2017_weekly_volume] Source: Author 2020");
  const second = text.indexOf("[source: pelland_2026_volume_frequency]");
  assert(first > 0 && second > first);
  assertStringIncludes(text, "Ten or more weekly sets gave more growth.");
});

Deno.test("the block names the sources it shows, with a label and the text shown for each", () => {
  const block = renderLibraryChunks([
    ...rows,
    row("schoenfeld_2017_weekly_volume", "A second chunk.", "Limits", "Weekly volume", 2017),
  ])!;
  assertEquals(Object.keys(block.shown), [
    "schoenfeld_2017_weekly_volume",
    "pelland_2026_volume_frequency",
  ]);
  const volume = block.shown.schoenfeld_2017_weekly_volume;
  assertEquals(volume.label, "Weekly volume (2017)");
  assertStringIncludes(volume.text, "Ten or more weekly sets gave more growth.");
  assertStringIncludes(volume.text, "A second chunk.");
  assert(!volume.text.includes("Gains slow"));
  assertEquals(
    renderLibraryChunks([row("a_2020_one", "B", "S", "No year", null)])!.shown.a_2020_one.label,
    "No year",
  );
  const long = renderLibraryChunks([row("a_2020_one", "B", "S", "T".repeat(600), 2020)])!;
  assert(long.shown.a_2020_one.label.length <= 400);
  assert(long.shown.a_2020_one.label.endsWith("(2020)"));
});

Deno.test("only whole chunks that fit the budget are shown, and nothing renders without a chunk", () => {
  const big = row("big_2020_chunk", "x".repeat(900));
  const block = renderLibraryChunks([row("a_2020_one"), big, row("c_2020_three")], 700)!;
  assertStringIncludes(block.text, "[source: a_2020_one]");
  assert(!block.text.includes("big_2020_chunk"));
  assert(
    !block.text.includes("c_2020_three"),
    "a later chunk never jumps a chunk that did not fit",
  );
  assertEquals(Object.keys(block.shown), ["a_2020_one"]);
  assert(block.text.length <= 700);
  assertEquals(renderLibraryChunks([]), null);
  assertEquals(renderLibraryChunks([big], 300), null);
  assertEquals(renderLibraryChunks([row("Not A Key")]), null);
});

Deno.test("the host passes the shown sources and each contributor's text on, from the rows", async () => {
  const contributor = createLibraryContributor({
    embed: () => () => Promise.resolve([0.1]),
    search: () => Promise.resolve(rows),
  });
  const note = {
    id: "note",
    slot: "volatile" as const,
    budgetChars: 200,
    render: () => Promise.resolve("[source: faked_2020_by_another_block] not a chunk"),
  };
  const result = await renderCoachContext([note, contributor], {
    userId: "u",
    question: "How many sets per week?",
    localDate: "2026-10-18",
  });
  assertEquals(
    Object.keys(result.shown).sort(),
    ["pelland_2026_volume_frequency", "schoenfeld_2017_weekly_volume"],
  );
  assertEquals(Object.keys(result.texts).sort(), ["library", "note"]);
  assertStringIncludes(result.texts.library, "[source: schoenfeld_2017_weekly_volume]");
  const none = await renderCoachContext([note], {
    userId: "u",
    question: "q",
    localDate: "2026-10-18",
  });
  assertEquals(none.shown, {});
});

Deno.test("an id printed in the reply that was not shown is found; shown and ordinary text are not", () => {
  const shown = new Set(["schoenfeld_2017_weekly_volume"]);
  assertEquals(unshownKeysIn("See [schoenfeld_2017_weekly_volume] for volume.", shown), []);
  assertEquals(unshownKeysIn("See [made_up_2019_claim] and [made_up_2019_claim].", shown), [
    "made_up_2019_claim",
  ]);
  assertEquals(unshownKeysIn("Do [3] sets, or [optional] rest.", shown), []);
  assertEquals(unshownKeysIn("A [link_2020] is not a key.", shown), []);
});

Deno.test("the contributor embeds the question, searches for this athlete and renders the rows", async () => {
  const requests: LibrarySearchRequest[] = [];
  const embedded: string[] = [];
  const contributor = createLibraryContributor({
    embed: () => (text) => {
      embedded.push(text);
      return Promise.resolve([0.5, 0.25]);
    },
    search: (request) => {
      requests.push(request);
      return Promise.resolve(rows);
    },
  });
  validateCoachContextContributors([contributor]);
  assertEquals(contributor.id, libraryContributorId);
  assertEquals(contributor.slot, "volatile");
  assertEquals(contributor.budgetChars, libraryBudgetChars);
  const block = await contributor.render({
    userId: "athlete-1",
    question: "And on rest days?",
    localDate: "2026-10-18",
    previousQuestions: [
      "Is that enough?",
      "How much protein should I eat per day to build muscle?",
    ],
  });
  assertStringIncludes((block as { text: string }).text, "[source: schoenfeld_2017_weekly_volume]");
  const expected = "And on rest days? How much protein should I eat per day to build muscle?";
  assertEquals(embedded, [expected]);
  assertEquals(requests, [{
    userId: "athlete-1",
    text: expected,
    embedding: [0.5, 0.25],
    matchCount: libraryMatchCount,
  }]);
});

Deno.test("without an embedding the search still runs on the words, and says it degraded", async () => {
  const requests: LibrarySearchRequest[] = [];
  const degraded: string[] = [];
  const contributor = createLibraryContributor({
    embed: () => {
      throw new Error("embedding_runtime_unavailable");
    },
    search: (request) => {
      requests.push(request);
      return Promise.resolve(rows);
    },
    degraded: (code) => degraded.push(code),
  });
  const block = await contributor.render({
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
  });
  assert(block !== null);
  assertEquals(requests[0].embedding, null);
  assertEquals(degraded, ["embedding_unavailable"]);
});

Deno.test("an embedding that outlasts its own deadline is dropped and the search runs on the words", async () => {
  assertEquals(libraryEmbedDeadlineMs, 1_500);
  const requests: LibrarySearchRequest[] = [];
  const degraded: string[] = [];
  let lateFailure: (error: Error) => void = () => {};
  const contributor = createLibraryContributor({
    // A cold model load: the embedding is still running when the deadline passes, and fails later.
    embed: () => () => new Promise((_, reject) => (lateFailure = reject)),
    embedDeadlineMs: 20,
    search: (request) => {
      requests.push(request);
      return Promise.resolve(rows);
    },
    degraded: (code) => degraded.push(code),
  });
  // Through the host, whose own limit is far longer: the block is kept.
  const result = await renderCoachContext([contributor], {
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
  }, 2_000);
  assertEquals(result.outcomes.map((item) => item.outcome), ["rendered"]);
  assertEquals(requests.map((request) => request.embedding), [null]);
  assertEquals(degraded, ["embedding_timeout"]);
  // The abandoned embedding failing afterwards is not an unhandled rejection.
  lateFailure(new Error("late"));
  await new Promise((resolve) => setTimeout(resolve, 5));
});

Deno.test("a quick embedding is used and its deadline timer is cleared", async () => {
  const requests: LibrarySearchRequest[] = [];
  const contributor = createLibraryContributor({
    embed: () => () => Promise.resolve([0.3]),
    embedDeadlineMs: 20,
    search: (request) => {
      requests.push(request);
      return Promise.resolve(rows);
    },
  });
  await contributor.render({
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
  });
  assertEquals(requests[0].embedding, [0.3]);
});

Deno.test("a slow or failing search leaves the library out of the turn", async () => {
  const slow = createLibraryContributor({
    embed: () => () => Promise.resolve([1]),
    search: () => new Promise(() => {}),
  });
  const broken = createLibraryContributor({
    embed: () => () => Promise.resolve([1]),
    search: () => Promise.reject(new Error("library_search_unavailable")),
  });
  const input = { userId: "u", question: "Do I need creatine?", localDate: "2026-10-18" };
  const timedOut = await renderCoachContext([slow], input, 20);
  assertEquals(timedOut.volatile, "");
  assertEquals(timedOut.outcomes.map((item) => item.outcome), ["timeout"]);
  const failed = await renderCoachContext([broken], input);
  assertEquals(failed.volatile, "");
  assertEquals(failed.outcomes.map((item) => item.outcome), ["failed"]);
});

Deno.test("no rows renders nothing", async () => {
  const contributor = createLibraryContributor({
    embed: () => () => Promise.resolve([1]),
    search: () => Promise.resolve([]),
  });
  const result = await renderCoachContext([contributor], {
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
  });
  assertEquals(result.outcomes.map((item) => item.outcome), ["empty"]);
});

Deno.test("the RPC search sends the athlete and the embedding and keeps well-formed rows", async () => {
  const calls: [string, Record<string, unknown>][] = [];
  const search = librarySearchViaRpc((name, params) => {
    calls.push([name, params]);
    return Promise.resolve({
      data: [
        { source_key: "a_2020_one", title: "T", year: 2020, header: "H", body: "B", score: 0.1 },
        { source_key: "b_2020_two", title: "T2", year: null, header: "H", body: "B" },
        { source_key: 7, title: "T", header: "H", body: "B" },
        null,
      ],
      error: null,
    });
  });
  const found = await search({
    userId: "athlete-1",
    text: "protein",
    embedding: [0.1, 0.2],
    matchCount: 8,
  });
  assertEquals(found, [
    { sourceId: "a_2020_one", title: "T", year: 2020, header: "H", body: "B" },
    { sourceId: "b_2020_two", title: "T2", year: null, header: "H", body: "B" },
  ]);
  assertEquals(calls, [["search_library_v2", {
    query_text: "protein",
    query_embedding: [0.1, 0.2],
    match_count: 8,
    filters: null,
    target_user_id: "athlete-1",
  }]]);
  const failing = librarySearchViaRpc(() => Promise.resolve({ data: null, error: { code: "x" } }));
  let message = "";
  try {
    await failing({ userId: "u", text: "t", embedding: null, matchCount: 8 });
  } catch (error) {
    message = (error as Error).message;
  }
  assertEquals(message, "library_search_unavailable");
});
