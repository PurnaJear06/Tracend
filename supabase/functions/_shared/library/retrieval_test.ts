import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { renderCoachContext, validateCoachContextContributors } from "../coach_context/host.ts";
import {
  createLibraryContributor,
  crossReferenceNote,
  keywordRelevantRows,
  libraryBudgetChars,
  libraryContributorId,
  libraryEmbedDeadlineMs,
  libraryKeywordFloor,
  libraryMatchCount,
  libraryNoMatchText,
  libraryRelevanceFloor,
  type LibraryRow,
  type LibrarySearchRequest,
  libraryWordsOnlyText,
  relevantRows,
  renderLibraryChunks,
  termCoverage,
  tracendReadingNote,
  unshownKeysIn,
} from "./retrieval.ts";
import { librarySearchViaRpc, prefetchLibraryEmbedding } from "./live.ts";

const traceOf = (block: unknown) => (block as { trace: Record<string, unknown> }).trace;

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
  const block = renderLibraryChunks(rows);
  const text = block.text;
  assertStringIncludes(text, "Cite a source only by an id listed here.");
  const first = text.indexOf("[source: schoenfeld_2017_weekly_volume] 2017. Source: Author 2020");
  const second = text.indexOf("[source: pelland_2026_volume_frequency]");
  assert(first > 0 && second > first);
  assertStringIncludes(text, "Ten or more weekly sets gave more growth.");
});

Deno.test("the marker line gives the kind of source, its year and its evidence level", () => {
  const text = renderLibraryChunks([{
    ...rows[0],
    kind: "position_stand",
    evidenceLevel: "position stand; overview of 137 systematic reviews",
  }]).text;
  assertStringIncludes(
    text,
    "[source: schoenfeld_2017_weekly_volume] Position stand, 2017. Evidence: position stand; overview of 137 systematic reviews. Source: Author 2020",
  );
  assertStringIncludes(
    renderLibraryChunks([{ ...rows[0], kind: "paper", year: null, evidenceLevel: null }]).text,
    "[source: schoenfeld_2017_weekly_volume] Paper. Source: Author 2020",
  );
});

Deno.test("Tracend's own reading of a source is marked as ours, not as the paper's finding", () => {
  const reading = renderLibraryChunks([{
    ...row(
      "schoenfeld_2017_weekly_volume",
      "Present volume as a lever.",
      "Practical reading and limits",
    ),
    section: "Practical reading and limits",
  }]).text;
  assertStringIncludes(reading, `2020. ${tracendReadingNote} Source: Author 2020`);
  const crossReferenced = renderLibraryChunks([{
    ...row("acsm_2026_x", "Analyses elsewhere in this library find small effects.", "Variables"),
    section: "Variables",
  }]).text;
  assertStringIncludes(crossReferenced, crossReferenceNote);
  assert(!crossReferenced.includes(tracendReadingNote));
  const seeEntry = renderLibraryChunks([{
    ...row("a_2020_one", "Newer work (see the Pelland 2026 entry) disagrees.", "Findings"),
    section: "Findings",
  }]).text;
  assertStringIncludes(seeEntry, crossReferenceNote);
  const finding = renderLibraryChunks([{ ...rows[0], section: "Results" }]).text;
  assert(!finding.includes(tracendReadingNote) && !finding.includes(crossReferenceNote));
});

Deno.test("the block names the sources it shows, with a label and the text shown for each", () => {
  const block = renderLibraryChunks([
    ...rows,
    row("schoenfeld_2017_weekly_volume", "A second chunk.", "Limits", "Weekly volume", 2017),
  ]);
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
    renderLibraryChunks([row("a_2020_one", "B", "S", "No year", null)]).shown.a_2020_one.label,
    "No year",
  );
  const long = renderLibraryChunks([row("a_2020_one", "B", "S", "T".repeat(600), 2020)]);
  assert(long.shown.a_2020_one.label.length <= 400);
  assert(long.shown.a_2020_one.label.endsWith("(2020)"));
});

Deno.test("only whole chunks that fit the budget are shown, and no chunk renders the no-match line", () => {
  const big = row("big_2020_chunk", "x".repeat(900));
  const block = renderLibraryChunks([row("a_2020_one"), big, row("c_2020_three")], 700);
  assertStringIncludes(block.text, "[source: a_2020_one]");
  assert(!block.text.includes("big_2020_chunk"));
  assert(
    !block.text.includes("c_2020_three"),
    "a later chunk never jumps a chunk that did not fit",
  );
  assertEquals(Object.keys(block.shown), ["a_2020_one"]);
  assert(block.text.length <= 700);
  for (const empty of [[], [row("Not A Key")]]) {
    assertEquals(renderLibraryChunks(empty), { text: libraryNoMatchText, shown: {} });
  }
  assertEquals(renderLibraryChunks([big], 300), { text: libraryNoMatchText, shown: {} });
  assertStringIncludes(libraryNoMatchText, "Cite no library source this turn.");
});

Deno.test("excerpts show only when the nearest chunk is close; then every chunk within the row limit", () => {
  const { maxTopDistance, maxVectorDistance } = libraryRelevanceFloor;
  assert(maxTopDistance <= maxVectorDistance);
  const at = (key: string, vectorDistance: number | null, textRank: number | null = 0) => ({
    key,
    vectorDistance,
    textRank,
  });
  const keys = (found: { key: string }[]) => found.map((item) => item.key);
  const between = (maxTopDistance + maxVectorDistance) / 2;
  // A covered question: the nearest is within the top limit, so the farther second source shows.
  assertEquals(
    keys(
      relevantRows([at("a", maxTopDistance), at("b", between), at("c", maxVectorDistance + 0.01)]),
    ),
    ["a", "b"],
  );
  // A question the library does not cover: nothing near enough, so nothing at all, even within
  // the row limit.
  assertEquals(relevantRows([at("b", between), at("c", maxTopDistance + 0.001)]), []);
  // A strong word match does not open the gate or rescue a far chunk: the distance alone decides.
  assertEquals(relevantRows([at("t", 0.9, 0.5), at("u", maxTopDistance + 0.01, 0.5)]), []);
  assertEquals(keys(relevantRows([at("a", maxTopDistance), at("t", 0.9, 0.5)])), ["a"]);
  // Rows no query scored (fixed rows in the answer bank) are shown as given.
  const unscored: { key: string; vectorDistance?: number; textRank?: number }[] = [
    { key: "f" },
    { key: "g" },
  ];
  assertEquals(keys(relevantRows(unscored)), ["f", "g"]);
  assertEquals(relevantRows([]), []);
});

Deno.test("term coverage is the share of the question's topic words a text holds, by word stem", () => {
  assertEquals(termCoverage("Protein, muscle, growth and strength?", "Protein and muscle."), 0.5);
  assertEquals(termCoverage("Sleeping hours", "Sleep for hours."), 1);
  assertEquals(termCoverage("creatine", "Nothing here."), 0);
  assertEquals(termCoverage("what is that?", "Anything."), 0, "no topic word");
  assertEquals(
    termCoverage("Protein protein PROTEIN", "protein"),
    1,
    "a repeated word counts once",
  );
});

Deno.test("the word-search fallback needs a strong, well-covered best chunk, then shows the ranked rows", () => {
  const floor = libraryKeywordFloor;
  const found = (key: string, textRank: number, text: string) => ({
    key,
    vectorDistance: null,
    textRank,
    text,
  });
  const keys = (items: { key: string }[]) => items.map((item) => item.key);
  const keywordRows = (query: string, items: ReturnType<typeof found>[]) =>
    keys(keywordRelevantRows(items, query, (item) => item.text));
  const query = "creatine safe kidneys?";
  const covered = "Creatine and the kidneys: safe.";
  // The best chunk is strong and holds the question's words: it and the chunks ranked above the
  // row limit show; a weaker chunk does not.
  assertEquals(
    keywordRows(query, [
      found("a", floor.minTopRank, covered),
      found("b", floor.minRowRank, "Other."),
      found("c", floor.minRowRank / 2, "More."),
    ]),
    ["a", "b"],
  );
  // A strong rank with too few of the question's words is a coincidence: nothing.
  assertEquals(keywordRows(query, [found("a", floor.minTopRank * 2, "Safe harbour.")]), []);
  // Words held but a rank under the top limit: nothing.
  assertEquals(keywordRows(query, [found("a", floor.minTopRank / 2, covered)]), []);
  assertEquals(keywordRows(query, []), []);
  // Rows no query scored are shown as given.
  const unscored: { key: string; vectorDistance?: number; textRank?: number }[] = [
    { key: "f" },
    { key: "g" },
  ];
  assertEquals(keys(keywordRelevantRows(unscored, query, () => "")), ["f", "g"]);
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
  assertEquals(traceOf(block).follow_up, true);
  assertEquals(traceOf(block).prefetched, false);
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
  const contributor = createLibraryContributor({
    embed: () => {
      throw new Error("embedding_runtime_unavailable");
    },
    search: (request) => {
      requests.push(request);
      return Promise.resolve(rows);
    },
  });
  const block = await contributor.render({
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
  });
  assert(block !== null);
  assertEquals(requests[0].embedding, null);
  assertEquals(traceOf(block).degraded, "embedding_unavailable");
});

Deno.test("an embedding that outlasts its own deadline is dropped and the search runs on the words", async () => {
  assertEquals(libraryEmbedDeadlineMs, 1_500);
  const requests: LibrarySearchRequest[] = [];
  let lateFailure: (error: Error) => void = () => {};
  const contributor = createLibraryContributor({
    // A cold model load: the embedding is still running when the deadline passes, and fails later.
    embed: () => () => new Promise((_, reject) => (lateFailure = reject)),
    embedDeadlineMs: 20,
    search: (request) => {
      requests.push(request);
      return Promise.resolve(rows);
    },
  });
  // Through the host, whose own limit is far longer: the block is kept.
  const result = await renderCoachContext([contributor], {
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
  }, 2_000);
  assertEquals(result.outcomes.map((item) => item.outcome), ["rendered"]);
  assertEquals(requests.map((request) => request.embedding), [null]);
  assertEquals(result.traces?.library.degraded, "embedding_timeout");
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

Deno.test("rows past the relevance floor are dropped, and none left renders the no-match line", async () => {
  const far = { ...rows[0], vectorDistance: 0.9, textRank: 0, libraryVersion: "0123456789abcdef" };
  const near = {
    ...rows[1],
    vectorDistance: 0.05,
    textRank: 0,
    libraryVersion: "0123456789abcdef",
  };
  const input = { userId: "u", question: "Do I need creatine?", localDate: "2026-10-18" };
  const mixed = await renderCoachContext([
    createLibraryContributor({
      embed: () => () => Promise.resolve([1]),
      search: () => Promise.resolve([far, near]),
      now: () => 0,
    }),
  ], input);
  assertEquals(Object.keys(mixed.shown), ["pelland_2026_volume_frequency"]);
  assertEquals(mixed.traces?.library, {
    embed_ms: 0,
    degraded: "none",
    prefetched: false,
    follow_up: false,
    candidates: 2,
    shown: ["pelland_2026_volume_frequency"],
    top_distance: 0.05,
    library_version: "0123456789abcdef",
  });
  for (const found of [[far], []]) {
    const none = await renderCoachContext([
      createLibraryContributor({
        embed: () => () => Promise.resolve([1]),
        search: () => Promise.resolve(found),
      }),
    ], input);
    assertEquals(none.outcomes.map((item) => item.outcome), ["rendered"]);
    assertEquals(none.texts.library, libraryNoMatchText);
    assertEquals(none.shown, {});
    assertEquals(none.traces?.library.shown, []);
  }
  // Without an embedding the line does not claim the library lacks the topic.
  const wordsOnly = await renderCoachContext([
    createLibraryContributor({
      embed: () => () => Promise.reject(new Error("down")),
      search: () => Promise.resolve([{ ...far, vectorDistance: null }]),
    }),
  ], input);
  assertEquals(wordsOnly.texts.library, libraryWordsOnlyText);
  assertEquals(renderLibraryChunks([], 9_000, true).text, libraryWordsOnlyText);
  // A strong word match that holds the question's words still shows on the words alone.
  const creatine = {
    ...row("kreider_2017_creatine", "Creatine is safe for healthy adults.", "Safety"),
    vectorDistance: null,
    textRank: libraryKeywordFloor.minTopRank,
  };
  const shownByWords = await renderCoachContext([
    createLibraryContributor({
      embed: () => () => Promise.reject(new Error("down")),
      search: () => Promise.resolve([creatine]),
    }),
  ], input);
  assertEquals(Object.keys(shownByWords.shown), ["kreider_2017_creatine"]);
});

Deno.test("an embedding prefetched at the start of the request is reused, within the same deadline", async () => {
  let clock = 1_000;
  const embedded: string[] = [];
  const requests: LibrarySearchRequest[] = [];
  const contributor = createLibraryContributor({
    embed: () => (text) => {
      embedded.push(text);
      return Promise.resolve([0.9]);
    },
    search: (request) => {
      requests.push(request);
      return Promise.resolve(rows);
    },
    now: () => clock,
  });
  const queryEmbedding = {
    text: "Do I need creatine?",
    startedAt: 400,
    embedding: Promise.resolve([0.2]),
  };
  const block = await contributor.render({
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
    queryEmbedding,
  });
  assertEquals(embedded, [], "nothing is embedded twice");
  assertEquals(requests[0].embedding, [0.2]);
  assertEquals(traceOf(block).prefetched, true);
  assertEquals(traceOf(block).embed_ms, 600, "the time is counted from the prefetch");
  // Another query text (a follow-up borrowing an earlier question) embeds its own.
  await contributor.render({
    userId: "u",
    question: "And on rest days?",
    localDate: "2026-10-18",
    previousQuestions: ["Do I need creatine?"],
    queryEmbedding,
  });
  assertEquals(embedded, ["And on rest days? Do I need creatine?"]);
  // A prefetch that already used up the deadline is not waited for.
  clock = 10_000;
  const late = await contributor.render({
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
    queryEmbedding: { ...queryEmbedding, embedding: new Promise<number[]>(() => {}) },
  });
  assertEquals(traceOf(late).degraded, "embedding_timeout");
  assertEquals(requests.at(-1)?.embedding, null);
});

Deno.test("the request prefetches only a question whose query does not depend on the context", async () => {
  const embedded: string[] = [];
  const embedder = (text: string) => {
    embedded.push(text);
    return Promise.resolve([0.4]);
  };
  const prefetched = prefetchLibraryEmbedding("  How much protein do I need?  ", embedder)!;
  assertEquals(prefetched.text, "How much protein do I need?");
  assertEquals(await prefetched.embedding, [0.4]);
  assertEquals(embedded, ["How much protein do I need?"]);
  assertEquals(prefetchLibraryEmbedding("And on rest days?", embedder), null);
  const failing = prefetchLibraryEmbedding(
    "Do I need creatine?",
    () => Promise.reject(new Error("x")),
  )!;
  let failed = false;
  await failing.embedding.catch(() => (failed = true));
  assert(failed, "a failed prefetch rejects for the contributor to report");
});

Deno.test("the RPC search sends the athlete and the embedding and keeps well-formed rows", async () => {
  const calls: [string, Record<string, unknown>][] = [];
  const search = librarySearchViaRpc((name, params) => {
    calls.push([name, params]);
    return Promise.resolve({
      data: [
        {
          source_key: "a_2020_one",
          title: "T",
          year: 2020,
          header: "H",
          body: "B",
          score: 0.1,
          section: "Results",
          evidence_level: "meta-analysis",
          kind: "paper",
          vector_distance: 0.12,
          text_rank: 0.05,
          library_version: "0123456789abcdef",
        },
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
  const unscored = {
    section: null,
    evidenceLevel: null,
    kind: null,
    vectorDistance: null,
    textRank: null,
    libraryVersion: null,
  };
  assertEquals(found, [
    {
      sourceId: "a_2020_one",
      title: "T",
      year: 2020,
      header: "H",
      body: "B",
      section: "Results",
      evidenceLevel: "meta-analysis",
      kind: "paper",
      vectorDistance: 0.12,
      textRank: 0.05,
      libraryVersion: "0123456789abcdef",
    },
    { sourceId: "b_2020_two", title: "T2", year: null, header: "H", body: "B", ...unscored },
  ]);
  assertEquals(calls, [["search_library_v3", {
    query_text: "protein",
    query_embedding: [0.1, 0.2],
    query_embedding_model: "gte-small",
    match_count: 8,
    filters: null,
    target_user_id: "athlete-1",
  }]]);
  await search({ userId: "athlete-1", text: "protein", embedding: null, matchCount: 8 });
  assertEquals(calls[1][1].query_embedding_model, null, "words alone name no model");
  const failing = librarySearchViaRpc(() => Promise.resolve({ data: null, error: { code: "x" } }));
  let message = "";
  try {
    await failing({ userId: "u", text: "t", embedding: null, matchCount: 8 });
  } catch (error) {
    message = (error as Error).message;
  }
  assertEquals(message, "library_search_unavailable");
});
