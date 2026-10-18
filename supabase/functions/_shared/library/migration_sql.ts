import { chunkSource } from "./chunk.ts";
import type { LibrarySource } from "./types.ts";

// Builds the SQL a migration uses to load library content. Each source becomes one call to
// private.library_replace_source (defined by the E2 migration), which upserts the source by
// manifest_key and replaces its chunks only when their text changed, so re-running a block
// never discards embeddings that are still valid. A later content update is a new migration
// holding the blocks for the sources that changed:
//
//   ./scripts/deno.sh run --allow-read supabase/functions/_shared/library/build_migration.ts \
//     --only creatine_ussn_2017,caffeine_issn_2021
//
// Every block starts with a comment holding the source key and a digest of what it loads.
// library_content_test.ts compares the newest migration that loads a source with the content
// files, so editing a file without a migration fails the test.
//
// A source removed from supabase/library/index.ts is retired the same way: the migration holds a
// retire block for it (build_migration.ts --retire key), which calls
// private.library_retire_source and deletes the source with its chunks. The same test fails while
// a migration still loads a source that index.ts no longer lists and no later block retires it.

const quoteTag = "$lib$";

export function sourcePayload(source: LibrarySource): Record<string, unknown> {
  return {
    slug: source.slug,
    title: source.title,
    authors: source.authors,
    year: source.year,
    doi: source.doi,
    url: source.url,
    licence: source.licence,
    region: source.region,
    topics: source.topics,
    evidence_level: source.evidenceLevel,
    kind: source.kind,
  };
}

export function chunkPayload(source: LibrarySource): Record<string, unknown>[] {
  return chunkSource(source).map((chunk) => ({
    ordinal: chunk.ordinal,
    section: chunk.section,
    header: chunk.header,
    body: chunk.body,
    token_count: chunk.tokenCount,
  }));
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function literal(value: unknown): string {
  const json = JSON.stringify(value);
  if (json.includes(quoteTag)) throw new Error("content contains the SQL quote tag");
  return `${quoteTag}${json}${quoteTag}::jsonb`;
}

export async function sourceBlock(source: LibrarySource): Promise<string> {
  const sourceJson = literal(sourcePayload(source));
  const chunksJson = literal(chunkPayload(source));
  const digest = await sha256Hex(`${sourceJson}\n${chunksJson}`);
  return [
    `-- library-source: ${source.slug} sha256:${digest}`,
    "select private.library_replace_source(",
    `${sourceJson},`,
    `${chunksJson}`,
    ");",
    "",
  ].join("\n");
}

export async function sourceBlocks(sources: readonly LibrarySource[]): Promise<string> {
  const blocks: string[] = [];
  for (const source of sources) blocks.push(await sourceBlock(source));
  return blocks.join("\n");
}

/** The marker a retire block starts with. */
export const retireMarker = (key: string) => `-- library-retire: ${key}`;

export function retireBlock(key: string): string {
  if (!/^[a-z0-9][a-z0-9_.-]{0,119}$/.test(key)) throw new Error(`not a manifest key: ${key}`);
  return [retireMarker(key), `select private.library_retire_source('${key}');`, ""].join("\n");
}
