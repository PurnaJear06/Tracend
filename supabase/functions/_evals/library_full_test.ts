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

Deno.test("the full library is deterministic and under the 70,000-token line for a cached prefix", () => {
  assertEquals(renderFullLibrary(), renderFullLibrary());
  const size = fullLibrarySize();
  assertEquals(size.sources, librarySources.length);
  // The whole library as a cached prefix was the option E3's head-to-head compared against
  // retrieval, and retrieval was chosen. This line guards only that shelved whole-library
  // evaluation (library_full.ts, library_head_to_head.ts); nothing in production reads it. Sizes:
  // E3 measured 85,000 characters (21,000 to 24,000 tokens); on main before E4 the 106 sources
  // render to 201,482 characters (57,566 tokens at 3.5 characters a token); with E4's eight regional
  // sources, 114 sources and 220,432 characters (62,981 tokens). E4 raised the line from 60,000 to
  // 70,000; the next expansion either raises it again or retires the evaluation
  // (docs/handoff/research-library.md).
  assert(size.tokens.high < 70_000, `${size.tokens.high} tokens`);
});
