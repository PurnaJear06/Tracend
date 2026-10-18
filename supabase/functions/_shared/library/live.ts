import { coachServiceRpc, type ServiceRpc } from "../coach_context/service_source.ts";
import { createLogger } from "../logger.ts";
import { createQueryEmbedder } from "./query_embedder.ts";
import {
  createLibraryContributor,
  libraryEmbedDeadlineMs,
  type LibraryRow,
  type LibrarySearch,
} from "./retrieval.ts";

// The library contributor Coach chat registers: the question is embedded with the same gte-small
// model that embedded the chunks, but by library-embed (query_embedder.ts), never inside
// coach-chat; then search_library_v2 runs for this athlete, so the athlete's region decides which
// regional sources can appear. No new provider.

const asRows = (data: unknown): LibraryRow[] =>
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
      }]
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

// The question is embedded by library-embed, over HTTP, with the same deadline the contributor
// enforces; the worker secret comes from the database once and is kept.
const embed = createQueryEmbedder({
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

export const libraryContributor = createLibraryContributor({
  embed: () => embed,
  search: librarySearchViaRpc(coachServiceRpc),
  degraded: (code) => createLogger().warn("library_retrieval_degraded", { reason: code }),
});
