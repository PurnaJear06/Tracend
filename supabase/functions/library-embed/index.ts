import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { createGteSmallEmbedder } from "../_shared/library/embedder.ts";
import { type EmbeddedChunk, embedPendingChunks } from "../_shared/library/embed_worker.ts";
import { embedTexts, EmbedTextsError, parseEmbedTexts } from "../_shared/library/embed_texts.ts";
import { captureException } from "../_shared/sentry.ts";

// Fills missing library embeddings with the built-in gte-small model. A database cron job
// (private.library_embed_kick) calls it every minute while any chunk lacks an embedding; each call
// embeds what fits in the CPU limit of one request. A body of {"texts": [...]} embeds those few
// texts instead (the retrieval evaluation).
// It never accepts a user session: the caller must present the worker secret that the
// database generated in Vault, checked through library_worker_authorized_v1.

const jsonHeaders = { "Content-Type": "application/json" };

function response(status: number, body: Readonly<Record<string, unknown>>) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return response(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization") ?? "";
  const bearer = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!supabaseUrl || !serviceRoleKey || bearer === "") {
    return response(401, { error: "authentication_required" });
  }

  const client = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  try {
    const { data: authorized, error: authError } = await client.rpc(
      "library_worker_authorized_v1",
      { candidate: bearer },
    );
    if (authError) throw new Error("authorization_check_failed");
    if (authorized !== true) return response(401, { error: "authentication_required" });

    // A few short texts to embed (the retrieval evaluation), instead of the worker run.
    const body = await request.json().catch(() => null);
    const texts = parseEmbedTexts(body);
    if (texts !== null) {
      return response(200, {
        schema_version: "1.0",
        embeddings: await embedTexts(createGteSmallEmbedder(), texts),
      });
    }

    const startedAt = new Date().toISOString();
    const result = await embedPendingChunks({
      pending: async (batchSize, excludeIds) => {
        const { data, error } = await client.rpc("library_pending_chunks_v1", {
          batch_size: batchSize,
          exclude_ids: excludeIds.length === 0 ? null : excludeIds,
        });
        if (error) throw new Error("pending_failed");
        return (data ?? []).map((
          row: { chunk_id: string; source_id: string; input_text: string },
        ) => ({ chunkId: row.chunk_id, sourceId: row.source_id, text: row.input_text }));
      },
      embed: createGteSmallEmbedder(),
      store: async (model, items: readonly EmbeddedChunk[]) => {
        const { data, error } = await client.rpc("library_store_embeddings_v1", {
          model,
          items: items.map((item) => ({ chunk_id: item.chunkId, embedding: item.embedding })),
        });
        if (error) throw new Error("store_failed");
        return typeof data === "number" ? data : 0;
      },
      recordFailures: async (chunkIds) => {
        const { data, error } = await client.rpc("library_record_embed_failures_v1", {
          chunk_ids: chunkIds,
        });
        if (error) throw new Error("failure_record_failed");
        return typeof data === "number" ? data : 0;
      },
      now: () => Date.now(),
    });

    if (result.embedded > 0 || result.failed > 0) {
      const { error } = await client.rpc("library_record_run_v1", {
        started_at: startedAt,
        succeeded: result.failed === 0,
        source_count: result.sources,
        chunk_count: result.embedded,
        error: result.failed === 0 ? null : `${result.failed} chunks failed to embed`,
      });
      if (error) throw new Error("run_record_failed");
    }
    // Once per chunk, not every minute: only when a chunk has just been given up on.
    if (result.abandoned > 0) {
      console.error(`library-embed: gave up on ${result.abandoned} chunks after repeated failures`);
      captureException(new Error(`library_embed_abandoned_${result.abandoned}`), {
        functionName: "library-embed",
        failureCode: "embedding_abandoned",
      });
    }
    return response(200, {
      schema_version: "1.0",
      embedded: result.embedded,
      failed: result.failed,
      abandoned: result.abandoned,
      stopped_early: result.stoppedEarly,
    });
  } catch (error) {
    if (error instanceof EmbedTextsError) return response(400, { error: "invalid_texts" });
    captureException(error, { functionName: "library-embed", failureCode: "library_embed_failed" });
    return response(500, { error: "library_embed_failed" });
  }
});
