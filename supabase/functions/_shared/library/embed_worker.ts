import { type Embedder, embeddingModel } from "./embedder.ts";

export type PendingChunk = Readonly<{ chunkId: string; sourceId: string; text: string }>;
export type EmbeddedChunk = Readonly<{ chunkId: string; embedding: readonly number[] }>;

export type EmbedRunResult = Readonly<{
  embedded: number;
  failed: number;
  /** Chunks that reached the attempt limit in this run and will not be tried again. */
  abandoned: number;
  sources: number;
  stoppedEarly: boolean;
}>;

export type EmbedWorkerDeps = Readonly<{
  /**
   * Chunks that still have no embedding and have attempts left, oldest first, leaving out
   * `excludeIds` (chunks that already failed in this run).
   */
  pending: (batchSize: number, excludeIds: readonly string[]) => Promise<readonly PendingChunk[]>;
  embed: Embedder;
  /** Stores embeddings only on chunks that still have none; returns how many it stored. */
  store: (model: string, items: readonly EmbeddedChunk[]) => Promise<number>;
  /**
   * Counts one failed attempt on each chunk; returns how many of them reached the attempt limit
   * with this one (the database stops offering a chunk after that).
   */
  recordFailures: (chunkIds: readonly string[]) => Promise<number>;
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
 * without an embedding and only writes where none exists. A chunk that fails to embed is counted,
 * recorded as a failed attempt and left out of the rest of the run, so it cannot block the chunks
 * behind it; after enough attempts the database stops offering it. A batch where nothing embeds
 * ends the run (the model is probably unavailable, so the other chunks are not marked failed).
 */
export async function embedPendingChunks(
  deps: EmbedWorkerDeps,
  options: EmbedWorkerOptions = defaultEmbedOptions,
): Promise<EmbedRunResult> {
  const touchedSources = new Set<string>();
  let spentMs = 0;
  let embedded = 0;
  let failed = 0;
  let abandoned = 0;
  const failedIds = new Set<string>();
  let stoppedEarly = false;

  while (!stoppedEarly) {
    const batch = await deps.pending(options.batchSize, [...failedIds]);
    if (batch.length === 0) break;

    const ready: EmbeddedChunk[] = [];
    const failedHere: string[] = [];
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
        failedIds.add(chunk.chunkId);
        failedHere.push(chunk.chunkId);
      }
      spentMs += deps.now() - before;
    }
    if (failedHere.length > 0) abandoned += await deps.recordFailures(failedHere);
    if (ready.length > 0) embedded += await deps.store(embeddingModel, ready);
    else if (!stoppedEarly) break;
  }

  return { embedded, failed, abandoned, sources: touchedSources.size, stoppedEarly };
}
