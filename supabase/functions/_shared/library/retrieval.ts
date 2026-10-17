import type { CoachContextContributor } from "../coach_context/host.ts";
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

/** One chunk the search returned. */
export type LibraryRow = Readonly<{
  sourceId: string;
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

/** The marker that starts a chunk in the block; the citation guard reads the ids back from it. */
const chunkMarker = (key: string) => `[source: ${key}]`;

const intro =
  "Research library excerpts found for this question, each starting with its source id in square brackets. Cite a source only by an id listed here. A figure in an excerpt is guidance from that source, never the athlete's own number.";

/**
 * The block's text: the introduction, then as many chunks as fit the budget, best first. Whole
 * chunks only, so the host never has to cut one. Null when there is nothing to show.
 */
export function renderLibraryChunks(
  rows: readonly LibraryRow[],
  budgetChars: number = libraryBudgetChars,
): string | null {
  const blocks: string[] = [];
  let used = intro.length;
  for (const row of rows) {
    if (!sourceIdPattern.test(row.sourceId)) continue;
    const block = `${chunkMarker(row.sourceId)} ${row.header}\n${row.body}`;
    if (used + block.length + 2 > budgetChars) break;
    blocks.push(block);
    used += block.length + 2;
  }
  return blocks.length === 0 ? null : `${intro}\n\n${blocks.join("\n\n")}`;
}

/** Contributor wiring: how the question becomes an embedding and how the search runs. */
export type LibraryContributorDeps = Readonly<{
  embed: () => Embedder;
  search: LibrarySearch;
  /** Told (by code, never by content) when retrieval ran without its embedding. */
  degraded?: (code: "embedding_unavailable") => void;
}>;

export function createLibraryContributor(deps: LibraryContributorDeps): CoachContextContributor {
  return Object.freeze({
    id: libraryContributorId,
    slot: "volatile",
    budgetChars: libraryBudgetChars,
    async render(input) {
      const query = libraryRetrievalQuery(input.question, input.previousQuestions ?? []);
      let embedding: number[] | null = null;
      try {
        embedding = await deps.embed()(query.text);
      } catch {
        deps.degraded?.("embedding_unavailable");
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

const libraryBlock = /<reference_data source="library">([\s\S]*?)<\/reference_data>/;
const chunkStart = /^\[source: ([a-z0-9][a-z0-9_.-]{0,119})\]/gm;

/** The source ids in the library block of a text, read back from the markers `renderLibraryChunks` writes. */
export function shownLibraryKeys(text: string | undefined): ReadonlySet<string> {
  const block = libraryBlock.exec(text ?? "");
  if (!block) return new Set();
  return new Set([...block[1].matchAll(chunkStart)].map((match) => match[1]));
}

/**
 * The source ids Coach was shown this turn. The library renders in the volatile part of the
 * prompt; the stable part is read too, so the head-to-head evaluation can put the whole library
 * in the cached prefix and be graded by the same guard.
 */
export function shownLibraryKeysIn(
  contributions: Readonly<{ stable: string; volatile: string }> | null | undefined,
): ReadonlySet<string> {
  return shownLibraryKeys(`${contributions?.stable ?? ""}\n${contributions?.volatile ?? ""}`);
}

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
