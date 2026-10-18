// The simulator's stand-in for search_library_v2: a word search over the real library chunks, for
// the athlete's region (global sources and their own country's). It ranks chunks by the rarity of
// the question's topic words they contain and returns only chunks that share one and score near
// the best, like the production search's word-only fallback; the vector half needs the database
// and the embedding model, and library_eval.ts measures it there. The text it searches is the one
// coach-chat builds (libraryRetrievalQuery), so a follow-up borrows the earlier question's topic.
import { chunkSource } from "../../_shared/library/chunk.ts";
import { topicTerms } from "../../_shared/library/query.ts";
import {
  libraryMatchCount,
  type LibraryRow,
  type LibrarySearch,
} from "../../_shared/library/retrieval.ts";
import { librarySources } from "../../../library/index.ts";

type IndexedChunk = Readonly<
  { row: LibraryRow; terms: ReadonlySet<string>; region: readonly string[] }
>;

const stem = (word: string) => word.replace(/(?:ing|es|s)$/, "");

/** A chunk is returned only when it scores at least this share of the best chunk's score. */
export const relativeFloor = 0.4;

function indexChunks(): IndexedChunk[] {
  return librarySources.flatMap((source) =>
    chunkSource(source).map((chunk) => ({
      row: {
        sourceId: source.slug,
        title: source.title,
        year: source.year,
        header: chunk.header,
        body: chunk.body,
      },
      terms: new Set(topicTerms(`${chunk.header} ${chunk.body}`).map(stem)),
      region: source.region,
    }))
  );
}

/** A search over the library for an athlete in `region` (an ISO country code). */
export function wordSearch(region: string): LibrarySearch {
  const chunks = indexChunks().filter((chunk) =>
    chunk.region.includes("global") || chunk.region.includes(region)
  );
  const documentFrequency = new Map<string, number>();
  for (const chunk of chunks) {
    for (const term of chunk.terms) {
      documentFrequency.set(term, (documentFrequency.get(term) ?? 0) + 1);
    }
  }
  const weight = (term: string) =>
    Math.log((chunks.length + 1) / ((documentFrequency.get(term) ?? 0) + 0.5));
  return (request) => {
    const terms = [...new Set(topicTerms(request.text).map(stem))];
    const ranked = chunks.map((chunk) => ({
      chunk,
      score: terms.filter((term) => chunk.terms.has(term)).reduce((sum, t) => sum + weight(t), 0),
    })).filter((item) => item.score > 0).sort((a, b) => b.score - a.score);
    // A chunk that shares only a common word with the question ("week", "plan") is noise next to
    // one that shares its topic: keep those within reach of the best match.
    const floor = (ranked[0]?.score ?? 0) * relativeFloor;
    return Promise.resolve(
      ranked.filter((item) => item.score >= floor).slice(
        0,
        Math.min(request.matchCount, libraryMatchCount),
      )
        .map((item) => item.chunk.row),
    );
  };
}
