import { type Embedder, embeddingDimensions } from "./embedding.ts";

// Coach chat's embedder for the question: an HTTP call to the library-embed Edge Function, which
// is the only place gte-small is loaded. Loading the model inside coach-chat would put the whole
// Coach turn at the Edge CPU limit (a first load runs for seconds); here a slow or failing call
// only costs the turn its vector search, and the contributor falls back to the words.
//
// The call is gated like the cron job's: a bearer with the library worker secret, which the
// database keeps in Vault and hands only to the service role (library_worker_secret_v1). The body
// carries the question and nothing else; neither side logs it.

export const libraryEmbedPath = "/functions/v1/library-embed";

export type QueryEmbedderDeps = Readonly<{
  /** The project URL (SUPABASE_URL), read when the call is made. */
  baseUrl: () => string;
  /** The library worker secret; read once and kept. */
  secret: () => Promise<string>;
  /** Longest the call may take before it is abandoned. */
  timeoutMs: number;
  fetch?: typeof fetch;
}>;

export function createQueryEmbedder(deps: QueryEmbedderDeps): Embedder {
  const send = deps.fetch ?? fetch;
  let secret: string | undefined;
  return async (text) => {
    const bearer = secret ??= await deps.secret();
    const response = await send(`${deps.baseUrl().replace(/\/+$/, "")}${libraryEmbedPath}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${bearer}` },
      body: JSON.stringify({ query: text }),
      signal: AbortSignal.timeout(deps.timeoutMs),
    });
    if (response.status !== 200) {
      await response.body?.cancel();
      throw new Error(`library_embed_${response.status}`);
    }
    const body = await response.json().catch(() => null) as { embedding?: unknown } | null;
    const embedding = body?.embedding;
    if (
      !Array.isArray(embedding) || embedding.length !== embeddingDimensions ||
      !embedding.every((value) => typeof value === "number" && Number.isFinite(value))
    ) throw new Error("library_embed_shape_invalid");
    return embedding;
  };
}
