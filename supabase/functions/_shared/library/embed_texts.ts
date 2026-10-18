import type { Embedder } from "./embedder.ts";

// library-embed can also embed a few short texts for the retrieval evaluation (the Supabase
// runtime is the only place gte-small runs). The caller still needs the worker secret.

export const maxEmbedTexts = 8;
export const maxEmbedTextChars = 1_000;

export class EmbedTextsError extends Error {}

/** The texts of an embed-texts request, or null when the body asks for the normal worker run. */
export function parseEmbedTexts(body: unknown): string[] | null {
  if (typeof body !== "object" || body === null || !("texts" in body)) return null;
  const texts = (body as { texts: unknown }).texts;
  if (!Array.isArray(texts) || texts.length === 0 || texts.length > maxEmbedTexts) {
    throw new EmbedTextsError(`texts must hold 1 to ${maxEmbedTexts} strings`);
  }
  for (const text of texts) {
    if (typeof text !== "string" || text.trim() === "" || text.length > maxEmbedTextChars) {
      throw new EmbedTextsError(`each text must be 1 to ${maxEmbedTextChars} characters`);
    }
  }
  return texts;
}

/**
 * The question of a query-embedding request (`{"query": "..."}`), or null when the body is not one.
 * One short text; the caller is Coach chat, which sends the athlete's question and nothing else.
 */
export function parseEmbedQuery(body: unknown): string | null {
  if (typeof body !== "object" || body === null || !("query" in body)) return null;
  const query = (body as { query: unknown }).query;
  if (typeof query !== "string" || query.trim() === "" || query.length > maxEmbedTextChars) {
    throw new EmbedTextsError(`query must be 1 to ${maxEmbedTextChars} characters`);
  }
  return query;
}

export async function embedTexts(embed: Embedder, texts: readonly string[]): Promise<number[][]> {
  const embeddings: number[][] = [];
  for (const text of texts) embeddings.push(await embed(text));
  return embeddings;
}
