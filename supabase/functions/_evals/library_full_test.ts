import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { librarySources } from "../../library/index.ts";
import { fullLibraryShown, fullLibrarySize, renderFullLibrary } from "./library_full.ts";

Deno.test("the full library names every source once, with the id the citation guard reads", () => {
  const text = renderFullLibrary();
  for (const source of librarySources) {
    assertEquals(text.split(`[source: ${source.slug}]`).length - 1, 1, source.slug);
  }
  const shown = fullLibraryShown();
  assertEquals(Object.keys(shown).sort(), librarySources.map((source) => source.slug).sort());
  for (const source of librarySources) {
    assertStringIncludes(shown[source.slug].text, `[source: ${source.slug}]`);
    assertStringIncludes(shown[source.slug].label, source.title);
  }
  assertStringIncludes(text, "Cite a source only by an id listed here.");
});

Deno.test("the full library is deterministic and under the 60,000-token line for a cached prefix", () => {
  assertEquals(renderFullLibrary(), renderFullLibrary());
  const size = fullLibrarySize();
  assertEquals(size.sources, librarySources.length);
  // E3 measured 85,000 characters, about 21,000 to 24,000 tokens, on 2026-10-18. Past 60,000
  // tokens the head-to-head option is off the table (docs/handoff/research-library.md).
  assert(size.tokens.high < 60_000, `${size.tokens.high} tokens`);
});
