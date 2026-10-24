import type { PrefetchedQueryEmbedding } from "../coach_context/host.ts";
import { coachServiceRpc, type ServiceRpc } from "../coach_context/service_source.ts";
import { type Embedder, embeddingModel } from "./embedding.ts";
import { planFactsFromService } from "./plan_facts.ts";
import { isFollowUp, libraryRetrievalQuery } from "./query.ts";
import { createQueryEmbedder } from "./query_embedder.ts";
import {
  createLibraryContributor,
  libraryEmbedDeadlineMs,
  type LibraryRow,
  type LibrarySearch,
} from "./retrieval.ts";

// The library contributor Coach chat registers: the question is embedded with the same gte-small
// model that embedded the chunks, but by library-embed (query_embedder.ts), never inside
// coach-chat; then search_library_v3 runs for this athlete, so the athlete's region decides which
// regional sources can appear and only chunks embedded with that model are compared. No new
// provider.

const textOf = (value: unknown) => typeof value === "string" ? value : null;
const numberOf = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) ? value : null;

/** The well-formed rows of a search_library_v3 result. */
export const libraryRowsOf = (data: unknown): LibraryRow[] =>
  (Array.isArray(data) ? data : []).flatMap((item) => {
    const row = item as Record<string, unknown> | null;
    return row && typeof row.source_key === "string" && typeof row.header === "string" &&
        typeof row.body === "string" && typeof row.title === "string"
      ? [{
        sourceId: row.source_key,
        title: row.title,
        year: typeof row.year === "number" ? row.year : null,
        header: row.header,
        body: row.body,
        section: textOf(row.section),
        evidenceLevel: textOf(row.evidence_level),
        kind: textOf(row.kind),
        vectorDistance: numberOf(row.vector_distance),
        textRank: numberOf(row.text_rank),
        libraryVersion: textOf(row.library_version),
      }]
      : [];
  });

/** The search through a service-role RPC caller. */
export function librarySearchViaRpc(rpc: ServiceRpc): LibrarySearch {
  return async (request) => {
    const { data, error } = await rpc("search_library_v3", {
      query_text: request.text,
      query_embedding: request.embedding,
      query_embedding_model: request.embedding === null ? null : embeddingModel,
      match_count: request.matchCount,
      filters: null,
      target_user_id: request.userId,
    });
    if (error) throw new Error("library_search_unavailable");
    return libraryRowsOf(data);
  };
}

// The question is embedded by library-embed, over HTTP, with the same deadline the contributor
// enforces; the worker secret comes from the database and is kept until library-embed refuses it.
export const libraryQueryEmbedder = createQueryEmbedder({
  baseUrl: () => Deno.env.get("SUPABASE_URL") ?? "",
  secret: async () => {
    const { data, error } = await coachServiceRpc("library_worker_secret_v1", {});
    if (error || typeof data !== "string" || data === "") {
      throw new Error("library_worker_secret_unavailable");
    }
    return data;
  },
  timeoutMs: libraryEmbedDeadlineMs,
});

/**
 * Starts embedding the question at the start of a Coach chat request, so the embedding runs while
 * the context is prepared. Null for a follow-up: its query borrows an earlier question from the
 * prepared context, so the contributor embeds it then. A question about why the plan is the way it
 * is (E5) is prefetched like any other: its first search is the question as asked.
 */
export function prefetchLibraryEmbedding(
  question: string,
  embedder: Embedder = libraryQueryEmbedder,
): PrefetchedQueryEmbedding | null {
  if (isFollowUp(question)) return null;
  const text = libraryRetrievalQuery(question, []).text;
  const startedAt = performance.now();
  const embedding = Promise.resolve().then(() => embedder(text));
  // Abandoned when the turn ends early (a refusal, a replay); the contributor reports its failure.
  embedding.catch(() => {});
  return { text, startedAt, embedding };
}

export const libraryContributor = createLibraryContributor({
  embed: () => libraryQueryEmbedder,
  search: librarySearchViaRpc(coachServiceRpc),
  planFacts: planFactsFromService,
});
