import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { createGteSmallEmbedder, embeddingDimensions, embeddingModel } from "./embedder.ts";

function runtime(output: ArrayLike<number>, seen: unknown[] = []) {
  return {
    Supabase: {
      ai: {
        Session: class {
          constructor(model: string) {
            seen.push(model);
          }
          run(input: string, options: { mean_pool: boolean; normalize: boolean }) {
            seen.push(input, options);
            return Promise.resolve(output);
          }
        },
      },
    },
  };
}

Deno.test("embeds with gte-small, mean-pooled and normalised", async () => {
  const seen: unknown[] = [];
  const embed = createGteSmallEmbedder(runtime(new Float32Array(embeddingDimensions), seen));
  const result = await embed("hello");
  assertEquals(result.length, 384);
  assertEquals(seen, [embeddingModel, "hello", { mean_pool: true, normalize: true }]);
});

Deno.test("a wrong-size or non-finite vector is refused", async () => {
  await assertRejects(
    () => createGteSmallEmbedder(runtime([1, 2, 3]))("x"),
    Error,
    "embedding_shape_invalid",
  );
  const bad = new Array(embeddingDimensions).fill(0);
  bad[5] = Number.NaN;
  await assertRejects(
    () => createGteSmallEmbedder(runtime(bad))("x"),
    Error,
    "embedding_shape_invalid",
  );
});

Deno.test("outside the Supabase runtime the embedder cannot be created", () => {
  assertThrows(() => createGteSmallEmbedder({}), Error, "embedding_runtime_unavailable");
});
