import { type Embedder, embeddingModel } from "./embedder.ts";

export type PendingChunk = Readonly<{ chunkId: string; sourceId: string; text: string }>;
export type EmbeddedChunk = Readonly<{ chunkId: string; embedding: readonly number[] }>;

export type EmbedRunResult = Readonly<{
  embedded: number;
  failed: number;
  sources: number;
  stoppedEarly: boolean;
}>;

export type EmbedWorkerDeps = Readonly<{
  /** Chunks that still have no embedding, oldest first. */
  pending: (batchSize: number) => Promise<readonly PendingChunk[]>;
  embed: Embedder;
  /** Stores embeddings only on chunks that still have none; returns how many it stored. */
  store: (model: string, items: readonly EmbeddedChunk[]) => Promise<number>;
  now: () => number;
}>;

export type EmbedWorkerOptions = Readonly<{
  /** Chunks fetched, embedded and stored together. */
  batchSize: number;
  /**
   * Most milliseconds one run spends inside the embedder. An Edge Function request may use only
   * about two seconds of CPU (seen locally: a soft limit near 1.1 s, a hard one near 2.1 s), so
   * a run embeds what fits and leaves the rest to the next cron call.
   */
  embedBudgetMs: number;
}>;

export const defaultEmbedOptions: EmbedWorkerOptions = { batchSize: 5, embedBudgetMs: 800 };

/**
 * Fills missing chunk embeddings. Safe to run twice at once and to re-run: it only reads chunks
 * without an embedding and only writes where none exists. One chunk that fails to embed is
 * counted and skipped; a batch where nothing embeds ends the run.
 */
export async function embedPendingChunks(
  deps: EmbedWorkerDeps,
  options: EmbedWorkerOptions = defaultEmbedOptions,
): Promise<EmbedRunResult> {
  const touchedSources = new Set<string>();
  let spentMs = 0;
  let embedded = 0;
  let failed = 0;
  let stoppedEarly = false;

  while (!stoppedEarly) {
    const batch = await deps.pending(options.batchSize);
    if (batch.length === 0) break;

    const ready: EmbeddedChunk[] = [];
    for (const chunk of batch) {
      if (spentMs >= options.embedBudgetMs) {
        stoppedEarly = true;
        break;
      }
      const before = deps.now();
      try {
        ready.push({ chunkId: chunk.chunkId, embedding: await deps.embed(chunk.text) });
        touchedSources.add(chunk.sourceId);
      } catch {
        failed += 1;
      }
      spentMs += deps.now() - before;
    }
    if (ready.length > 0) embedded += await deps.store(embeddingModel, ready);
    else if (!stoppedEarly) break;
  }

  return { embedded, failed, sources: touchedSources.size, stoppedEarly };
}
