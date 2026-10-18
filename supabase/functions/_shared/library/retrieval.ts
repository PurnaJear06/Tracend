import type { CoachContextContributor, RenderedBlock, ShownSource } from "../coach_context/host.ts";
import { type Embedder } from "./embedder.ts";
import { libraryRetrievalQuery } from "./query.ts";

// Library retrieval as a Contract 7 contributor (chunk E3): every Coach chat turn searches the
// library for the athlete's question and shows Coach the chunks it found, each tagged with its
// source id. Coach cites a source by that id, and a citation of an id that was not shown is a
// reply-guard failure (citationsOf, below). Retrieval is context, never authority: Tracend's
// calculations, the athlete's confirmed facts and the athlete's own words come first, and rules
// still decide every number.

export const libraryContributorId = "library";
/** Chunks asked for per turn. The search returns at most ten; eight is what the evaluation scores. */
export const libraryMatchCount = 8;
/** About 2,300 tokens. The average chunk is 600 characters, so eight rarely come near it. */
export const libraryBudgetChars = 9_000;
/**
 * The most the question's embedding may take. A cold gte-small load can run far past it, and the
 * host drops the whole block at 4 seconds; past this the search runs on the words alone.
 */
export const libraryEmbedDeadlineMs = 1_500;

/** One chunk the search returned. */
export type LibraryRow = Readonly<{
  sourceId: string;
  /** The source's title and year, which label a citation of it. */
  title: string;
  year: number | null;
  header: string;
  body: string;
}>;

export type LibrarySearchRequest = Readonly<{
  userId: string;
  text: string;
  /** Null when the question could not be embedded: the search then uses its words alone. */
  embedding: readonly number[] | null;
  matchCount: number;
}>;

/** Runs the search for one athlete (search_library_v2 with the athlete's region). */
export type LibrarySearch = (request: LibrarySearchRequest) => Promise<readonly LibraryRow[]>;

const sourceIdPattern = /^[a-z0-9][a-z0-9_.-]{0,119}$/;

/** The marker that starts a chunk in the block, so Coach can name the source it relies on. */
const chunkMarker = (key: string) => `[source: ${key}]`;

const intro =
  "Research library excerpts found for this question, each starting with its source id in square brackets. Cite a source only by an id listed here. A figure in an excerpt is guidance from that source, never the athlete's own number.";

/**
 * The block: the introduction, then as many chunks as fit the budget, best first, with the sources
 * they came from. Whole chunks only, so the host never has to cut one. Null when there is nothing
 * to show.
 */
export function renderLibraryChunks(
  rows: readonly LibraryRow[],
  budgetChars: number = libraryBudgetChars,
): RenderedBlock | null {
  const blocks: string[] = [];
  const shown: Record<string, ShownSource> = {};
  let used = intro.length;
  for (const row of rows) {
    if (!sourceIdPattern.test(row.sourceId)) continue;
    const block = `${chunkMarker(row.sourceId)} ${row.header}\n${row.body}`;
    if (used + block.length + 2 > budgetChars) break;
    blocks.push(block);
    used += block.length + 2;
    const earlier = shown[row.sourceId];
    shown[row.sourceId] = {
      label: earlier?.label ?? citationLabel(row),
      text: earlier ? `${earlier.text}\n${block}` : block,
    };
  }
  return blocks.length === 0 ? null : { text: `${intro}\n\n${blocks.join("\n\n")}`, shown };
}

/** "Title (year)", cut to the evidence label limit. */
function citationLabel(row: LibraryRow): string {
  const year = row.year === null ? "" : ` (${row.year})`;
  return `${row.title.slice(0, 380 - year.length)}${year}`;
}

/** Contributor wiring: how the question becomes an embedding and how the search runs. */
export type LibraryContributorDeps = Readonly<{
  embed: () => Embedder;
  search: LibrarySearch;
  /** Told (by code, never by content) when retrieval ran without its embedding. */
  degraded?: (code: "embedding_unavailable" | "embedding_timeout") => void;
  /** How long the embedding may take; defaults to `libraryEmbedDeadlineMs`. */
  embedDeadlineMs?: number;
}>;

export function createLibraryContributor(deps: LibraryContributorDeps): CoachContextContributor {
  return Object.freeze({
    id: libraryContributorId,
    slot: "volatile",
    budgetChars: libraryBudgetChars,
    async render(input) {
      const query = libraryRetrievalQuery(input.question, input.previousQuestions ?? []);
      let embedding: number[] | null = null;
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const pending = Promise.resolve().then(() => deps.embed()(query.text));
        // A late failure of an abandoned embedding must not surface as an unhandled rejection.
        pending.catch(() => {});
        const timedOut = new Promise<"timeout">((resolve) => {
          timer = setTimeout(
            () => resolve("timeout"),
            deps.embedDeadlineMs ?? libraryEmbedDeadlineMs,
          );
        });
        const result = await Promise.race([pending, timedOut]);
        if (result === "timeout") deps.degraded?.("embedding_timeout");
        else embedding = result;
      } catch {
        deps.degraded?.("embedding_unavailable");
      } finally {
        clearTimeout(timer);
      }
      const rows = await deps.search({
        userId: input.userId,
        text: query.text,
        embedding,
        matchCount: libraryMatchCount,
      });
      return renderLibraryChunks(rows);
    },
  });
}

// ---- citations ----------------------------------------------------------------------------

// A manifest key reads author_year_topic (for example schoenfeld_2017_weekly_volume): lower-case
// words joined by underscores around a four-digit year, in square brackets.
const bracketedKey = /\[([a-z0-9][a-z0-9_.-]*_(?:19|20)\d{2}_[a-z0-9_.-]+)\]/g;

/**
 * Source ids written inline in the reply text that were not shown. The persona tells Coach not to
 * print ids, so one is rare; but a printed id that was never retrieved is a citation of nothing.
 */
export function unshownKeysIn(text: string, shown: ReadonlySet<string>): string[] {
  return [...new Set([...text.matchAll(bracketedKey)].map((match) => match[1]))].filter((key) =>
    !shown.has(key)
  );
}
