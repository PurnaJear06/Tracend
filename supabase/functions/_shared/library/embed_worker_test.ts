import { assertEquals } from "jsr:@std/assert@1";
import { embeddingModel } from "./embedder.ts";
import {
  type EmbeddedChunk,
  embedPendingChunks,
  type EmbedWorkerDeps,
  type PendingChunk,
} from "./embed_worker.ts";

/** The database stops offering a chunk after this many failed attempts. */
const attemptLimit = 5;

function fakeDeps(chunks: PendingChunk[], options: {
  failOn?: string[];
  clock?: () => number;
} = {}) {
  const stored = new Map<string, readonly number[]>();
  const models: string[] = [];
  const attempts = new Map<string, number>();
  let pendingCalls = 0;
  const deps: EmbedWorkerDeps = {
    pending: (batchSize, excludeIds) => {
      pendingCalls += 1;
      return Promise.resolve(
        chunks.filter((chunk) =>
          !stored.has(chunk.chunkId) && !excludeIds.includes(chunk.chunkId) &&
          (attempts.get(chunk.chunkId) ?? 0) < attemptLimit
        ).slice(0, batchSize),
      );
    },
    recordFailures: (chunkIds) => {
      let reached = 0;
      for (const id of chunkIds) {
        const next = (attempts.get(id) ?? 0) + 1;
        attempts.set(id, next);
        if (next === attemptLimit) reached += 1;
      }
      return Promise.resolve(reached);
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
  return { deps, stored, models, attempts, pendingCalls: () => pendingCalls };
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
  assertEquals(result, { embedded: 3, failed: 0, abandoned: 0, sources: 2, stoppedEarly: false });
  assertEquals([...stored.keys()], ["c1", "c2", "c3"]);
  assertEquals(models, [embeddingModel, embeddingModel]);
});

Deno.test("running again with nothing pending does nothing", async () => {
  const { deps, models } = fakeDeps([]);
  assertEquals(await embedPendingChunks(deps), {
    embedded: 0,
    failed: 0,
    abandoned: 0,
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
  assertEquals(result.failed, 1, "a failed chunk is not tried again in the same run");
  assertEquals(stored.has("c1"), false);
  assertEquals(stored.has("c2") && stored.has("c3"), true);
});

Deno.test("a batch where nothing embeds ends the run instead of looping", async () => {
  const { deps, pendingCalls } = fakeDeps([chunk("c1", "s1", "bad")], { failOn: ["bad"] });
  const result = await embedPendingChunks(deps, { batchSize: 5, embedBudgetMs: 1000 });
  assertEquals(result, { embedded: 0, failed: 1, abandoned: 0, sources: 0, stoppedEarly: false });
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
  assertEquals(result, { embedded: 3, failed: 0, abandoned: 0, sources: 1, stoppedEarly: true });
  assertEquals([...stored.keys()], ["c1", "c2", "c3"]);
  const next = await embedPendingChunks(fakeDeps([chunk("c4", "s1", "d")]).deps);
  assertEquals(next.embedded, 1);
});

Deno.test("a chunk that keeps failing does not block the chunks behind it", async () => {
  const { deps, stored, attempts, pendingCalls } = fakeDeps(
    [chunk("c1", "s1", "bad"), chunk("c2", "s1", "good"), chunk("c3", "s1", "fine")],
    { failOn: ["bad"] },
  );
  // A batch of one: the failing chunk comes first and is left out of the batches after it.
  const result = await embedPendingChunks(deps, { batchSize: 1, embedBudgetMs: 1000 });
  assertEquals(result.embedded, 0, "a whole batch failing ends the run");
  assertEquals(attempts.get("c1"), 1);
  const wide = await embedPendingChunks(deps, { batchSize: 2, embedBudgetMs: 1000 });
  assertEquals(wide.embedded, 2);
  assertEquals(stored.has("c2") && stored.has("c3"), true);
  assertEquals(attempts.get("c1"), 2);
  assertEquals(pendingCalls() >= 3, true);
});

Deno.test("after the attempt limit the failing chunk is no longer offered and is reported once", async () => {
  const { deps, attempts } = fakeDeps([chunk("c1", "s1", "bad")], { failOn: ["bad"] });
  const options = { batchSize: 5, embedBudgetMs: 1000 };
  const reported: number[] = [];
  for (let run = 0; run < attemptLimit + 3; run++) {
    reported.push((await embedPendingChunks(deps, options)).abandoned);
  }
  assertEquals(reported, [0, 0, 0, 0, 1, 0, 0, 0]);
  assertEquals(attempts.get("c1"), attemptLimit, "no attempt is recorded once it is given up");
});

Deno.test("chunks that failed in a run are passed to the next batch request", async () => {
  const seen: (readonly string[])[] = [];
  const { deps } = fakeDeps(
    [chunk("c1", "s1", "bad"), chunk("c2", "s1", "ok"), chunk("c3", "s1", "fine")],
    { failOn: ["bad"] },
  );
  const spy: EmbedWorkerDeps = {
    ...deps,
    pending: (batchSize, excludeIds) => {
      seen.push([...excludeIds]);
      return deps.pending(batchSize, excludeIds);
    },
  };
  await embedPendingChunks(spy, { batchSize: 2, embedBudgetMs: 1000 });
  assertEquals(seen[0], []);
  assertEquals(seen[1], ["c1"]);
});
