import { coachServiceRpc, type ServiceRpc } from "../coach_context/service_source.ts";
import { createLogger } from "../logger.ts";
import { createGteSmallEmbedder, type Embedder } from "./embedder.ts";
import { createLibraryContributor, type LibraryRow, type LibrarySearch } from "./retrieval.ts";

// The library contributor Coach chat registers: the question is embedded with the same gte-small
// model that embedded the chunks (the Supabase Edge runtime provides it), then
// search_library_v2 runs for this athlete, so the athlete's region decides which regional sources
// can appear. No new provider and no network call beyond the database.

const asRows = (data: unknown): LibraryRow[] =>
  (Array.isArray(data) ? data : []).flatMap((item) => {
    const row = item as Record<string, unknown> | null;
    return row && typeof row.source_key === "string" && typeof row.header === "string" &&
        typeof row.body === "string"
      ? [{ sourceId: row.source_key, header: row.header, body: row.body }]
      : [];
  });

/** The search through a service-role RPC caller. */
export function librarySearchViaRpc(rpc: ServiceRpc): LibrarySearch {
  return async (request) => {
    const { data, error } = await rpc("search_library_v2", {
      query_text: request.text,
      query_embedding: request.embedding,
      match_count: request.matchCount,
      filters: null,
      target_user_id: request.userId,
    });
    if (error) throw new Error("library_search_unavailable");
    return asRows(data);
  };
}

// Loaded on first use and kept for the life of the Edge isolate: the model loads once.
let embedder: Embedder | undefined;

export const libraryContributor = createLibraryContributor({
  embed: () => (embedder ??= createGteSmallEmbedder()),
  search: librarySearchViaRpc(coachServiceRpc),
  degraded: (code) => createLogger().warn("library_retrieval_degraded", { reason: code }),
});
