import type {
  CoachContextContributor,
  ContributorTrace,
  RenderedBlock,
  ShownSource,
} from "../coach_context/host.ts";
import type { Embedder } from "./embedding.ts";
import { libraryRetrievalQuery, topicTerms } from "./query.ts";

// Library retrieval as a Contract 7 contributor (chunk E3): every Coach chat turn searches the
// library for the athlete's question and shows Coach the chunks that are close enough to it, each
// tagged with its source id. Coach cites a source by that id, and a citation of an id that was not
// shown is a reply-guard failure (citationsOf, below). Retrieval is context, never authority:
// Tracend's calculations, the athlete's confirmed facts and the athlete's own words come first,
// and rules still decide every number.

export const libraryContributorId = "library";
/** Chunks asked for per turn. The search returns at most ten; eight is what the evaluation scores. */
export const libraryMatchCount = 8;
/** About 2,300 tokens. The average chunk is 600 characters, so eight rarely come near it. */
export const libraryBudgetChars = 9_000;
/**
 * The most the question's embedding may take, counted from when it started (at the start of the
 * request when Coach chat prefetched it). A cold gte-small load inside library-embed can run far
 * past it, and the host drops the whole block at 4 seconds; past this the search runs on the words
 * alone.
 */
export const libraryEmbedDeadlineMs = 1_500;

/**
 * When the library has something for the question, and which chunks to show (calibrated with the
 * real gte-small model on the retrieval questions; docs/handoff/research-library.md, "Relevance
 * floor"). Two limits on the cosine distance to the question, because the right chunks of a
 * question the library covers sit close to it, while every chunk of a question it does not cover
 * sits farther away, and the second or third source of a multi-topic question sits farther than
 * the first:
 *
 * - `maxTopDistance`: the turn shows excerpts only when its nearest chunk is at most this far.
 *   Past it the library has nothing for the question, and Coach is told so.
 * - `maxVectorDistance`: then every chunk at most this far is shown.
 *
 * A full-text rank is no part of this floor: on the 106-source library a strong word match let
 * through as many out-of-library questions as it rescued answerable ones (see the sweep in the
 * handoff), so the distance alone decides.
 */
export type RelevanceFloor = Readonly<{
  maxTopDistance: number;
  maxVectorDistance: number;
}>;
// Calibrated 2026-10-18 on the calibration set (189 answerable and 30 no-answer questions, 351
// chunks of 106 sources): the nearest chunk of an expected source sits at 0.074 to 0.187 (median
// 0.106); the nearest chunk of a no-answer question at 0.147 to 0.245 (median 0.177). The values
// below are the highest-recall floor that still leaves at least 80% of the no-answer questions
// with nothing shown (the gate is 70%).
export const libraryRelevanceFloor: RelevanceFloor = Object.freeze({
  maxTopDistance: 0.155,
  maxVectorDistance: 0.19,
});

/**
 * The floor for the word-search fallback, used when the question could not be embedded (a
 * timeout or library-embed down). There is no distance then, and a word match is a much weaker
 * sign than a near embedding: a strong rank alone cannot tell a covered question from one outside
 * the library (the answerable questions' strongest word match overlaps the others'). The fallback
 * therefore also needs the strongest chunk to hold a good share of the question's topic words:
 *
 * - `minTopRank`: the best chunk's `ts_rank` must be at least this, or nothing is shown.
 * - `minTopCoverage`: and that chunk must hold at least this share of the question's distinct
 *   topic words (`termCoverage`).
 * - `minRowRank`: then every chunk ranked at least this is shown.
 */
export type KeywordFloor = Readonly<{
  minTopRank: number;
  minTopCoverage: number;
  minRowRank: number;
}>;
export const libraryKeywordFloor: KeywordFloor = Object.freeze({
  minTopRank: 0.0055,
  minTopCoverage: 0.35,
  minRowRank: 0.002,
});

/** One chunk the search returned. */
export type LibraryRow = Readonly<{
  sourceId: string;
  /** The source's title and year, which label a citation of it. */
  title: string;
  year: number | null;
  header: string;
  body: string;
  /** The chunk's section title; "Practical reading" sections are Tracend's interpretation. */
  section?: string | null;
  /** The source's evidence level, for example "systematic review and meta-analysis". */
  evidenceLevel?: string | null;
  /** paper, guideline, position_stand or summary. */
  kind?: string | null;
  /**
   * Cosine distance between the chunk and the question; null when the search ran without an
   * embedding. Absent, with `textRank`, only for rows no query scored (fixed rows in the answer
   * bank), which are shown as given.
   */
  vectorDistance?: number | null;
  /** Full-text rank for the question's terms (0 when the chunk holds none); null without terms. */
  textRank?: number | null;
  /** The library version the search ran against (private.library_version()). */
  libraryVersion?: string | null;
}>;

export type LibrarySearchRequest = Readonly<{
  userId: string;
  text: string;
  /** Null when the question could not be embedded: the search then uses its words alone. */
  embedding: readonly number[] | null;
  matchCount: number;
}>;

/** Runs the search for one athlete (search_library_v3 with the athlete's region). */
export type LibrarySearch = (request: LibrarySearchRequest) => Promise<readonly LibraryRow[]>;

type Scored = Pick<LibraryRow, "vectorDistance" | "textRank">;

const unscored = (rows: readonly Scored[]) =>
  rows.every((row) => row.vectorDistance === undefined && row.textRank === undefined);

/**
 * The rows relevant enough to show, best first (see `RelevanceFloor`). Rows that no query scored
 * (fixed rows in the answer bank carry neither score) are shown as given.
 */
export function relevantRows<Row extends Scored>(
  rows: readonly Row[],
  floor: RelevanceFloor = libraryRelevanceFloor,
): Row[] {
  if (unscored(rows)) return [...rows];
  const within = (row: Scored, limit: number) =>
    typeof row.vectorDistance === "number" && row.vectorDistance <= limit;
  if (!rows.some((row) => within(row, floor.maxTopDistance))) return [];
  return rows.filter((row) => within(row, floor.maxVectorDistance));
}

// Word stems are approximated by the first five letters, which is enough to match "sleeping" to
// "sleep" and "proteins" to "protein" without a stemmer.
const stemOf = (word: string) => word.slice(0, 5);

/**
 * The share (0 to 1) of the question's distinct topic words (query.ts `topicTerms`) that the text
 * holds, matching on word stems. 0 for a question with no topic word.
 */
export function termCoverage(queryText: string, text: string): number {
  const terms = [...new Set(topicTerms(queryText).map(stemOf))];
  if (terms.length === 0) return 0;
  const words = new Set((text.toLowerCase().match(/[a-z0-9]+/g) ?? []).map(stemOf));
  return terms.filter((term) => words.has(term)).length / terms.length;
}

/**
 * The rows to show when the search ran on the words alone (see `KeywordFloor`), best first.
 * `textOf` gives a row's header and body, which the coverage is measured on.
 */
export function keywordRelevantRows<Row extends Scored>(
  rows: readonly Row[],
  queryText: string,
  textOf: (row: Row) => string,
  floor: KeywordFloor = libraryKeywordFloor,
): Row[] {
  if (unscored(rows)) return [...rows];
  const rank = (row: Scored) => typeof row.textRank === "number" ? row.textRank : 0;
  const top = rows[0];
  if (
    top === undefined || rank(top) < floor.minTopRank ||
    termCoverage(queryText, textOf(top)) < floor.minTopCoverage
  ) return [];
  return rows.filter((row) => rank(row) >= floor.minRowRank);
}

const sourceIdPattern = /^[a-z0-9][a-z0-9_.-]{0,119}$/;

/** The marker that starts a chunk in the block, so Coach can name the source it relies on. */
const chunkMarker = (key: string) => `[source: ${key}]`;

const kindNames: Readonly<Record<string, string>> = {
  paper: "Paper",
  guideline: "Guideline",
  position_stand: "Position stand",
  summary: "Summary",
};

// A section that holds Tracend's own reading of a source ("Practical reading and limits"), and a
// remark that points to another library entry, are Tracend's words about the source, not what it
// found. They are marked when shown, so nothing has to be re-embedded.
const readingSection = /^practical reading\b/i;
const crossReference = /\bsee the [^.]{1,80}? entry\b|\bin this library\b/i;

export const tracendReadingNote =
  "Tracend's reading of this source (our interpretation and its limits), not a finding the source reports.";
export const crossReferenceNote =
  "A remark here that points to another library entry is Tracend's, not the source's.";

/** What the marker line says about the excerpt: kind, year, evidence level and whose words. */
function describe(row: LibraryRow): string {
  const kind = row.kind ? kindNames[row.kind] ?? row.kind : null;
  const what = [kind, row.year === null ? null : String(row.year)].filter(Boolean).join(", ");
  return [
    what === "" ? null : `${what}.`,
    row.evidenceLevel ? `Evidence: ${row.evidenceLevel}.` : null,
    readingSection.test(row.section ?? "")
      ? tracendReadingNote
      : crossReference.test(row.body)
      ? crossReferenceNote
      : null,
  ].filter(Boolean).join(" ");
}

const intro =
  "Research library excerpts found for this question. Each starts with its source id in square brackets, then the kind of source, its year and its evidence level. Cite a source only by an id listed here. A figure in an excerpt is guidance from that source, never the athlete's own number. An excerpt marked as Tracend's reading is Tracend's interpretation of the source: present it as our reading, never as what the study found.";

/** The block when no excerpt is close enough to the question. */
export const libraryNoMatchText =
  "No research library excerpt matched this question closely enough to show. Cite no library source this turn. If the answer rests on research evidence, say that Tracend's library does not cover it rather than answering from memory.";

/**
 * The block when the search ran on the words alone (the embedding failed) and found no strong
 * match: the library may still cover the question, so Coach must not say it does not.
 */
export const libraryWordsOnlyText =
  "The research library could only be searched by keyword this turn and no excerpt matched closely. Cite no library source this turn, do not say the library lacks the topic, and make no research claims from memory.";

/**
 * The block: the introduction, then as many chunks as fit the budget, best first, with the sources
 * they came from. Whole chunks only, so the host never has to cut one. With nothing to show it is
 * an explicit line saying so, so Coach knows the library was searched and found nothing:
 * `wordsOnly` when the search had no embedding.
 */
export function renderLibraryChunks(
  rows: readonly LibraryRow[],
  budgetChars: number = libraryBudgetChars,
  wordsOnly = false,
): RenderedBlock {
  const blocks: string[] = [];
  const shown: Record<string, ShownSource> = {};
  let used = intro.length;
  for (const row of rows) {
    if (!sourceIdPattern.test(row.sourceId)) continue;
    const about = describe(row);
    const block = `${chunkMarker(row.sourceId)} ${
      about === "" ? "" : `${about} `
    }${row.header}\n${row.body}`;
    if (used + block.length + 2 > budgetChars) break;
    blocks.push(block);
    used += block.length + 2;
    const earlier = shown[row.sourceId];
    shown[row.sourceId] = {
      label: earlier?.label ?? citationLabel(row),
      text: earlier ? `${earlier.text}\n${block}` : block,
    };
  }
  if (blocks.length > 0) return { text: `${intro}\n\n${blocks.join("\n\n")}`, shown };
  return { text: wordsOnly ? libraryWordsOnlyText : libraryNoMatchText, shown };
}

/** "Title (year)", cut to the evidence label limit. */
function citationLabel(row: LibraryRow): string {
  const year = row.year === null ? "" : ` (${row.year})`;
  return `${row.title.slice(0, 380 - year.length)}${year}`;
}

/** Why the search ran without its embedding, or "none". */
export type LibraryDegradedReason = "none" | "embedding_unavailable" | "embedding_timeout";

/** Contributor wiring: how the question becomes an embedding and how the search runs. */
export type LibraryContributorDeps = Readonly<{
  embed: () => Embedder;
  search: LibrarySearch;
  /** How long the embedding may take; defaults to `libraryEmbedDeadlineMs`. */
  embedDeadlineMs?: number;
  /** The clock prefetched embeddings are timed on; defaults to performance.now. */
  now?: () => number;
}>;

const rowText = (row: LibraryRow) => `${row.header}\n${row.body}`;
const roundTo = (value: number, places: number) => Number(value.toFixed(places));

export function createLibraryContributor(deps: LibraryContributorDeps): CoachContextContributor {
  const now = deps.now ?? (() => performance.now());
  const deadline = deps.embedDeadlineMs ?? libraryEmbedDeadlineMs;
  return Object.freeze({
    id: libraryContributorId,
    slot: "volatile",
    budgetChars: libraryBudgetChars,
    async render(input) {
      const query = libraryRetrievalQuery(input.question, input.previousQuestions ?? []);
      const early = input.queryEmbedding?.text === query.text ? input.queryEmbedding : undefined;
      const startedAt = early?.startedAt ?? now();
      let embedding: number[] | null = null;
      let degraded: LibraryDegradedReason = "none";
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const pending = early?.embedding ??
          Promise.resolve().then(() => deps.embed()(query.text));
        // A late failure of an abandoned embedding must not surface as an unhandled rejection.
        pending.catch(() => {});
        const timedOut = new Promise<"timeout">((resolve) => {
          timer = setTimeout(
            () => resolve("timeout"),
            Math.max(0, deadline - (now() - startedAt)),
          );
        });
        const result = await Promise.race([pending, timedOut]);
        if (result === "timeout") degraded = "embedding_timeout";
        else embedding = result;
      } catch {
        degraded = "embedding_unavailable";
      } finally {
        clearTimeout(timer);
      }
      const embedMs = Math.round(now() - startedAt);
      const rows = await deps.search({
        userId: input.userId,
        text: query.text,
        embedding,
        matchCount: libraryMatchCount,
      });
      const shown = embedding === null
        ? keywordRelevantRows(rows, query.text, rowText)
        : relevantRows(rows);
      const block = renderLibraryChunks(shown, libraryBudgetChars, embedding === null);
      const distances = rows.flatMap((row) =>
        typeof row.vectorDistance === "number" ? [row.vectorDistance] : []
      );
      const trace: ContributorTrace = {
        embed_ms: embedMs,
        degraded,
        prefetched: early !== undefined,
        follow_up: query.rewritten,
        candidates: rows.length,
        shown: Object.keys(block.shown),
        top_distance: distances.length === 0 ? null : roundTo(Math.min(...distances), 4),
        library_version: rows.find((row) => row.libraryVersion)?.libraryVersion ?? null,
      };
      return { ...block, trace };
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
