import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { chunkHeader, chunkSource, chunkText, estimateTokens, maxBodyChars } from "./chunk.ts";
import type { LibrarySource } from "./types.ts";

const source: LibrarySource = {
  slug: "test_source",
  label: "Test et al. 2020",
  title: "A test source",
  authors: ["Test T"],
  year: 2020,
  doi: null,
  url: "https://example.org/test",
  licence: "CC-BY-4.0",
  verbatimAllowed: true,
  lastReviewed: "2026-10-18",
  region: ["global"],
  topics: ["training"],
  evidenceLevel: "test",
  kind: "paper",
  chosenBecause: "test",
  sections: [
    { title: "One", body: "First paragraph.\n\nSecond paragraph." },
    { title: "Two", body: `${"a".repeat(900)}\n\n${"b".repeat(900)}\n\nshort` },
  ],
};

Deno.test("a short section is one chunk and the header names the source and section", () => {
  const chunks = chunkSource(source);
  assertEquals(chunks[0].section, "One");
  assertEquals(chunks[0].body, "First paragraph.\n\nSecond paragraph.");
  assertEquals(chunks[0].header, chunkHeader(source, "One"));
  assert(chunks[0].header.startsWith("Source: Test et al. 2020, A test source."));
  assert(chunks[0].header.endsWith("Section: One."));
});

Deno.test("long sections split on paragraph breaks and ordinals run from zero without gaps", () => {
  const chunks = chunkSource(source);
  assertEquals(chunks.map((chunk) => chunk.ordinal), [0, 1, 2]);
  assertEquals(chunks.map((chunk) => chunk.section), ["One", "Two", "Two"]);
  for (const chunk of chunks) assert(chunk.body.length <= maxBodyChars);
  assertEquals(chunks[2].body, `${"b".repeat(900)}\n\nshort`);
});

Deno.test("a paragraph too long to keep whole is an error, not a cut", () => {
  assertThrows(
    () =>
      chunkSource({ ...source, sections: [{ title: "Big", body: "x".repeat(maxBodyChars + 1) }] }),
    Error,
    "paragraph over",
  );
});

Deno.test("chunk text is the header then the body, and tokens are about four characters each", () => {
  assertEquals(chunkText("H", "B"), "H\nB");
  assertEquals(chunkText("", "B"), "B");
  assertEquals(estimateTokens("abcd"), 1);
  assertEquals(estimateTokens("abcde"), 2);
  assertEquals(estimateTokens(""), 1);
});
