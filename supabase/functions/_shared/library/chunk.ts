import type { LibraryChunk, LibrarySource } from "./types.ts";

// gte-small reads at most 512 tokens, header included. About four characters make a token
// in English, so a 1400-character body plus a header stays comfortably inside the window.
export const maxBodyChars = 1400;
const maxHeaderChars = 1000;

export function chunkHeader(source: LibrarySource, sectionTitle: string): string {
  const header = `Source: ${source.label}, ${source.title}. Section: ${sectionTitle}.`;
  if (header.length > maxHeaderChars) {
    throw new Error(`header too long for ${source.slug}: ${sectionTitle}`);
  }
  return header;
}

/** The text the embedder and full-text search both see for a chunk. */
export function chunkText(header: string, body: string): string {
  return header === "" ? body : `${header}\n${body}`;
}

export function estimateTokens(text: string): number {
  return Math.min(2000, Math.max(1, Math.ceil(text.length / 4)));
}

function splitParagraphs(body: string): string[] {
  return body.split(/\n\s*\n/).map((paragraph) => paragraph.trim()).filter((p) => p !== "");
}

/**
 * Splits each section on blank lines into chunks of at most maxBodyChars. A single paragraph
 * longer than that is an authoring error, not something to cut mid-sentence.
 */
export function chunkSource(source: LibrarySource): LibraryChunk[] {
  const chunks: LibraryChunk[] = [];
  for (const section of source.sections) {
    const header = chunkHeader(source, section.title);
    let current: string[] = [];
    const flush = () => {
      if (current.length === 0) return;
      const body = current.join("\n\n");
      chunks.push({
        ordinal: chunks.length,
        section: section.title,
        header,
        body,
        tokenCount: estimateTokens(chunkText(header, body)),
      });
      current = [];
    };
    for (const paragraph of splitParagraphs(section.body)) {
      if (paragraph.length > maxBodyChars) {
        throw new Error(
          `paragraph over ${maxBodyChars} characters in ${source.slug}: ${section.title}`,
        );
      }
      const joined = [...current, paragraph].join("\n\n");
      if (current.length > 0 && joined.length > maxBodyChars) flush();
      current.push(paragraph);
    }
    flush();
  }
  return chunks;
}
