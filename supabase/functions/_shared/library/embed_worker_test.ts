import { assertEquals } from "jsr:@std/assert@1";
import { embeddingModel } from "./embedder.ts";
import {
  type EmbeddedChunk,
  embedPendingChunks,
  type EmbedWorkerDeps,
  type PendingChunk,
} from "./embed_worker.ts";

function fakeDeps(chunks: PendingChunk[], options: {
  failOn?: string[];
  clock?: () => number;
} = {}) {
  const stored = new Map<string, readonly number[]>();
  const models: string[] = [];
  let pendingCalls = 0;
  const deps: EmbedWorkerDeps = {
    pending: (batchSize) => {
      pendingCalls += 1;
      return Promise.resolve(
        chunks.filter((chunk) => !stored.has(chunk.chunkId)).slice(0, batchSize),
      );
    },
    embed: (text) => {
      if (options.failOn?.includes(text)) return Promise.reject(new Error("boom"));
      return Promise.resolve([text.length]);
    },
    store: (model, items: readonly EmbeddedChunk[]) => {
      models.push(model);
      let count = 0;
      for (const item of items) {
        if (!stored.has(item.chunkId)) {
          stored.set(item.chunkId, item.embedding);
          count += 1;
        }
      }
      return Promise.resolve(count);
    },
    now: options.clock ?? (() => 0),
  };
  return { deps, stored, models, pendingCalls: () => pendingCalls };
}

const chunk = (id: string, sourceId: string, text: string): PendingChunk => ({
  chunkId: id,
  sourceId,
  text,
});

Deno.test("embeds every pending chunk in batches and records the model", async () => {
  const { deps, stored, models } = fakeDeps([
    chunk("c1", "s1", "one"),
    chunk("c2", "s1", "two"),
    chunk("c3", "s2", "three"),
  ]);
  const result = await embedPendingChunks(deps, { batchSize: 2, embedBudgetMs: 1000 });
  assertEquals(result, { embedded: 3, failed: 0, sources: 2, stoppedEarly: false });
  assertEquals([...stored.keys()], ["c1", "c2", "c3"]);
  assertEquals(models, [embeddingModel, embeddingModel]);
});

Deno.test("running again with nothing pending does nothing", async () => {
  const { deps, models } = fakeDeps([]);
  assertEquals(await embedPendingChunks(deps), {
    embedded: 0,
    failed: 0,
    sources: 0,
    stoppedEarly: false,
  });
  assertEquals(models, []);
});

Deno.test("one chunk that cannot be embedded is counted and the rest go on", async () => {
  const { deps, stored } = fakeDeps(
    [chunk("c1", "s1", "bad"), chunk("c2", "s1", "good"), chunk("c3", "s1", "fine")],
    { failOn: ["bad"] },
  );
  const result = await embedPendingChunks(deps, { batchSize: 10, embedBudgetMs: 1000 });
  assertEquals(result.embedded, 2);
  assertEquals(result.failed >= 1, true);
  assertEquals(stored.has("c1"), false);
  assertEquals(stored.has("c2") && stored.has("c3"), true);
});

Deno.test("a batch where nothing embeds ends the run instead of looping", async () => {
  const { deps, pendingCalls } = fakeDeps([chunk("c1", "s1", "bad")], { failOn: ["bad"] });
  const result = await embedPendingChunks(deps, { batchSize: 5, embedBudgetMs: 1000 });
  assertEquals(result, { embedded: 0, failed: 1, sources: 0, stoppedEarly: false });
  assertEquals(pendingCalls(), 1);
});

Deno.test("embedding stops once the embed time budget is spent and the rest waits for the next run", async () => {
  let now = 0;
  const { deps, stored } = fakeDeps(
    [
      chunk("c1", "s1", "a"),
      chunk("c2", "s1", "b"),
      chunk("c3", "s1", "c"),
      chunk("c4", "s1", "d"),
    ],
    { clock: () => now },
  );
  const timed: EmbedWorkerDeps = {
    ...deps,
    embed: (text) => {
      now += 300;
      return deps.embed(text);
    },
  };
  const result = await embedPendingChunks(timed, { batchSize: 2, embedBudgetMs: 700 });
  assertEquals(result, { embedded: 3, failed: 0, sources: 1, stoppedEarly: true });
  assertEquals([...stored.keys()], ["c1", "c2", "c3"]);
  const next = await embedPendingChunks(fakeDeps([chunk("c4", "s1", "d")]).deps);
  assertEquals(next.embedded, 1);
});
