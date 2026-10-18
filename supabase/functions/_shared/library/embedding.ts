// What the library's embeddings are, without the model: the name, the size and the shape of an
// embedder. Coach chat imports this and the HTTP client (query_embedder.ts), never embedder.ts,
// which holds the code that loads gte-small: that model runs only inside library-embed.

export const embeddingModel = "gte-small";
export const embeddingDimensions = 384;

export type Embedder = (text: string) => Promise<number[]>;
