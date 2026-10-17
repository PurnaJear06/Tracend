import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { renderCoachContext, validateCoachContextContributors } from "../coach_context/host.ts";
import {
  createLibraryContributor,
  libraryBudgetChars,
  libraryContributorId,
  libraryMatchCount,
  type LibraryRow,
  type LibrarySearchRequest,
  renderLibraryChunks,
  shownLibraryKeys,
  unshownKeysIn,
} from "./retrieval.ts";
import { librarySearchViaRpc } from "./live.ts";

const row = (key: string, body = "Body text.", section = "Results"): LibraryRow => ({
  sourceId: key,
  header: `Source: Author 2020, A title. Section: ${section}.`,
  body,
});

const rows = [
  row("schoenfeld_2017_weekly_volume", "Ten or more weekly sets gave more growth."),
  row("pelland_2026_volume_frequency", "Gains slow as sets increase."),
];

Deno.test("chunks render with their source id first, best first", () => {
  const text = renderLibraryChunks(rows)!;
  assertStringIncludes(text, "Cite a source only by an id listed here.");
  const first = text.indexOf("[source: schoenfeld_2017_weekly_volume] Source: Author 2020");
  const second = text.indexOf("[source: pelland_2026_volume_frequency]");
  assert(first > 0 && second > first);
  assertStringIncludes(text, "Ten or more weekly sets gave more growth.");
});

Deno.test("only whole chunks that fit the budget are shown, and nothing renders without a chunk", () => {
  const big = row("big_2020_chunk", "x".repeat(900));
  const text = renderLibraryChunks([row("a_2020_one"), big, row("c_2020_three")], 700)!;
  assertStringIncludes(text, "[source: a_2020_one]");
  assert(!text.includes("big_2020_chunk"));
  assert(!text.includes("c_2020_three"), "a later chunk never jumps a chunk that did not fit");
  assert(text.length <= 700);
  assertEquals(renderLibraryChunks([]), null);
  assertEquals(renderLibraryChunks([big], 300), null);
  assertEquals(renderLibraryChunks([row("Not A Key")]), null);
});

Deno.test("the shown ids are read back from the library block only", async () => {
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
    [...shownLibraryKeys(result.volatile)].sort(),
    ["pelland_2026_volume_frequency", "schoenfeld_2017_weekly_volume"],
  );
  assertEquals(shownLibraryKeys(""), new Set());
  assertEquals(shownLibraryKeys(undefined), new Set());
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
  const text = await contributor.render({
    userId: "athlete-1",
    question: "And on rest days?",
    localDate: "2026-10-18",
    previousQuestions: [
      "Is that enough?",
      "How much protein should I eat per day to build muscle?",
    ],
  });
  assertStringIncludes(text!, "[source: schoenfeld_2017_weekly_volume]");
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
  const text = await contributor.render({
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
  });
  assert(text !== null);
  assertEquals(requests[0].embedding, null);
  assertEquals(degraded, ["embedding_unavailable"]);
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
        { source_key: "a_2020_one", header: "H", body: "B", score: 0.1 },
        { source_key: 7, header: "H", body: "B" },
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
  assertEquals(found, [{ sourceId: "a_2020_one", header: "H", body: "B" }]);
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
