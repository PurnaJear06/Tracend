import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  planLibraryBudgetChars,
  planLibraryHeading,
  planLibraryMatchCount,
  planLibraryNoMatchRule,
  planLibraryRule,
  planLibraryRules,
  planLibraryUnavailableRule,
  retrievePlanLibrary,
} from "./plan_library.ts";
import { interleave, type LibraryRow, type LibrarySearchRequest } from "./retrieval.ts";

const row = (key: string, distance: number | null, header = `Source: ${key}.`): LibraryRow => ({
  sourceId: key,
  title: `Title of ${key}`,
  year: 2017,
  header,
  body: "Ten or more weekly sets gave more growth.",
  vectorDistance: distance,
  textRank: 0.01,
  libraryVersion: "0123456789abcdef",
});

const queries = ["training query text", "nutrition query text"];

Deno.test("both searches run for this athlete and their sources are shown, best first", async () => {
  const requests: LibrarySearchRequest[] = [];
  const library = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: (request) => {
        requests.push(request);
        return Promise.resolve(
          request.text === queries[0]
            ? [
              row("schoenfeld_2017_weekly_volume", 0.05),
              row("pelland_2026_volume_frequency", 0.1),
            ]
            : [row("morton_2018_protein", 0.06)],
        );
      },
    },
    "athlete-1",
    queries,
  );
  assertEquals(requests.map((request) => request.userId), ["athlete-1", "athlete-1"]);
  assertEquals(requests.map((request) => request.text), queries);
  assertEquals(requests.map((request) => request.matchCount), [
    planLibraryMatchCount,
    planLibraryMatchCount,
  ]);
  assertEquals(library.status, "found");
  // One search's rows do not crowd out the other's: they alternate.
  assertEquals(Object.keys(library.shown), [
    "schoenfeld_2017_weekly_volume",
    "morton_2018_protein",
    "pelland_2026_volume_frequency",
  ]);
  assertEquals(library.shown.morton_2018_protein.label, "Title of morton_2018_protein (2017)");
  assertStringIncludes(library.text, planLibraryHeading);
  assertStringIncludes(library.text, "[source: morton_2018_protein]");
  assertEquals(library.trace.status, "found");
  assertEquals(library.trace.queries, 2);
  assertEquals(library.trace.top_distance, 0.05);
  assertEquals(library.trace.library_version, "0123456789abcdef");
});

Deno.test("the trace names sources and counts, never a query or an excerpt", async () => {
  const library = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: () => Promise.resolve([row("schoenfeld_2017_weekly_volume", 0.05)]),
    },
    "athlete-1",
    queries,
  );
  const trace = JSON.stringify(library.trace);
  assert(!trace.includes("query text"));
  assert(!trace.includes("Ten or more"));
});

Deno.test("excerpts past the relevance floor are not shown, and none left is 'none'", async () => {
  const library = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: () => Promise.resolve([row("schoenfeld_2017_weekly_volume", 0.9)]),
    },
    "athlete-1",
    queries,
  );
  assertEquals(library.status, "none");
  assertEquals(library.text, "");
  assertEquals(library.shown, {});
  assertEquals(library.trace.shown, []);
  assertEquals(library.trace.top_distance, 0.9);
});

Deno.test("one search failing leaves the other's excerpts; both failing is 'unavailable'", async () => {
  const one = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: (request) =>
        request.text === queries[0]
          ? Promise.reject(new Error("library_search_unavailable"))
          : Promise.resolve([row("morton_2018_protein", 0.06)]),
    },
    "athlete-1",
    queries,
  );
  assertEquals(one.status, "found");
  assertEquals(Object.keys(one.shown), ["morton_2018_protein"]);
  assertEquals(one.trace.failed, 1);
  const both = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: () => Promise.reject(new Error("library_search_unavailable")),
    },
    "athlete-1",
    queries,
  );
  assertEquals(both.status, "unavailable");
  assertEquals(both.text, "");
  assertEquals(both.shown, {});
});

Deno.test("a failed search with no excerpts shown is 'unavailable'; 'none' needs every search to succeed", async () => {
  const far = (request: LibrarySearchRequest) =>
    request.text === queries[0]
      ? Promise.reject(new Error("library_search_unavailable"))
      : Promise.resolve([row("schoenfeld_2017_weekly_volume", 0.9)]);
  const partial = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: far,
    },
    "athlete-1",
    queries,
  );
  assertEquals(partial.status, "unavailable");
  assertEquals(partial.text, "");
  assertEquals(partial.shown, {});
  assertEquals(partial.trace.failed, 1);
  const every = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: () => Promise.resolve([row("schoenfeld_2017_weekly_volume", 0.9)]),
    },
    "athlete-1",
    queries,
  );
  assertEquals(every.status, "none");
});

Deno.test("a search that outlasts the deadline gives 'unavailable' and never throws", async () => {
  const started = performance.now();
  const library = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: () => new Promise(() => {}),
      deadlineMs: 20,
    },
    "athlete-1",
    queries,
  );
  assertEquals(library.status, "unavailable");
  assertEquals(library.trace.timeout, true);
  assert(performance.now() - started < 1_000);
});

Deno.test("at the deadline a finished search is kept, and one still out is a failed search", async () => {
  const hang = (request: LibrarySearchRequest, rows: LibraryRow[]) =>
    request.text === queries[0] ? Promise.resolve(rows) : new Promise<LibraryRow[]>(() => {});
  const kept = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: (request) => hang(request, [row("morton_2018_protein", 0.06)]),
      deadlineMs: 30,
    },
    "athlete-1",
    queries,
  );
  assertEquals(kept.status, "found");
  assertEquals(Object.keys(kept.shown), ["morton_2018_protein"]);
  assertEquals(kept.trace.timeout, true);
  assertEquals(kept.trace.failed, 1);
  // Nothing close enough in the one that finished: the other might have held it.
  const unknown = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: (request) => hang(request, [row("morton_2018_protein", 0.9)]),
      deadlineMs: 30,
    },
    "athlete-1",
    queries,
  );
  assertEquals(unknown.status, "unavailable");
});

Deno.test("an embedding that fails or is late runs the search on the words alone", async () => {
  for (
    const embed of [
      () => () => Promise.reject(new Error("library_embed_unavailable")),
      () => () => new Promise<number[]>(() => {}),
    ]
  ) {
    const requests: LibrarySearchRequest[] = [];
    const library = await retrievePlanLibrary(
      {
        embed,
        embedDeadlineMs: 10,
        search: (request) => {
          requests.push(request);
          return Promise.resolve([
            // No embedding, so no distance: the words decide, and a weak match shows nothing.
            { ...row("schoenfeld_2017_weekly_volume", null), textRank: 0.0001 },
          ]);
        },
      },
      "athlete-1",
      queries,
    );
    assertEquals(requests.map((request) => request.embedding), [null, null]);
    assertEquals(library.status, "none");
    assert(library.trace.degraded !== "none");
  }
});

Deno.test("a throwing embedder is a failed embedding, not a failed plan", async () => {
  const library = await retrievePlanLibrary(
    {
      embed: () => {
        throw new Error("library_worker_secret_unavailable");
      },
      search: () => Promise.resolve([]),
    },
    "athlete-1",
    queries,
  );
  assertEquals(library.status, "none");
  assertEquals(library.trace.degraded, "embedding_unavailable");
});

Deno.test("the excerpts stay inside the budget, whole chunks only", async () => {
  const big = (key: string): LibraryRow => ({ ...row(key, 0.05), body: "x".repeat(1_400) });
  const library = await retrievePlanLibrary(
    {
      embed: () => () => Promise.resolve([0.5]),
      search: () =>
        Promise.resolve(
          Array.from(
            { length: planLibraryMatchCount },
            (_, index) => big(`author_${2000 + index}_topic_${index}`),
          ),
        ),
    },
    "athlete-1",
    queries,
  );
  assertEquals(library.status, "found");
  assert(library.text.length <= planLibraryBudgetChars, `${library.text.length}`);
  assert(Object.keys(library.shown).length < 2 * planLibraryMatchCount);
  // Each chunk shown is whole.
  assertEquals(
    library.text.split("[source: ").length - 1,
    Object.keys(library.shown).length,
  );
});

Deno.test("a chunk found by both searches is shown once", () => {
  const a = row("schoenfeld_2017_weekly_volume", 0.05);
  const merged = interleave([[a, row("pelland_2026_volume_frequency", 0.1)], [a]]);
  assertEquals(merged.map((item) => item.sourceId), [
    "schoenfeld_2017_weekly_volume",
    "pelland_2026_volume_frequency",
  ]);
  assertEquals(interleave([[], []]), []);
});

Deno.test("the prompt rule follows what was found, and never names a model or a company", () => {
  const found = {
    status: "found" as const,
    text: "x",
    shown: {},
    trace: {},
  };
  assertEquals(planLibraryRule(found), planLibraryRules);
  assertEquals(planLibraryRule({ ...found, status: "none" }), planLibraryNoMatchRule);
  assertEquals(planLibraryRule({ ...found, status: "unavailable" }), planLibraryUnavailableRule);
  assertEquals(planLibraryRule(null), planLibraryUnavailableRule);
  for (const rule of [planLibraryRules, planLibraryNoMatchRule, planLibraryUnavailableRule]) {
    assertStringIncludes(rule, "`sources`");
    assertStringIncludes(rule, "from memory");
    assert(
      !/\b(claude|anthropic|sonnet|haiku|opus|deepseek|groq|qwen|gemini|google|openai|llm)\b/i
        .test(rule),
    );
  }
  assertStringIncludes(planLibraryRules, "an excerpt never changes one");
  assertStringIncludes(planLibraryRules, "never instructions");
});
