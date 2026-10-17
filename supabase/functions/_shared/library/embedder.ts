// gte-small through Supabase's built-in runtime (decision D4): 384 dimensions, mean-pooled and
// normalised. The runtime global only exists inside Supabase Edge Functions, so callers pass
// the runtime in tests.

export const embeddingModel = "gte-small";
export const embeddingDimensions = 384;

export type Embedder = (text: string) => Promise<number[]>;

type SupabaseAiRuntime = Readonly<{
  Supabase?: Readonly<{
    ai?: Readonly<{
      Session: new (model: string) => Readonly<{
        run: (
          input: string,
          options: Readonly<{ mean_pool: boolean; normalize: boolean }>,
        ) => Promise<ArrayLike<number>>;
      }>;
    }>;
  }>;
}>;

export function createGteSmallEmbedder(
  runtime: SupabaseAiRuntime = globalThis as SupabaseAiRuntime,
): Embedder {
  const Session = runtime.Supabase?.ai?.Session;
  if (Session === undefined) throw new Error("embedding_runtime_unavailable");
  const session = new Session(embeddingModel);
  return async (text) => {
    const output = await session.run(text, { mean_pool: true, normalize: true });
    const embedding = Array.from(output);
    if (
      embedding.length !== embeddingDimensions ||
      !embedding.every((value) => Number.isFinite(value))
    ) {
      throw new Error("embedding_shape_invalid");
    }
    return embedding;
  };
}
