import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  embedTexts,
  EmbedTextsError,
  maxEmbedTextChars,
  maxEmbedTexts,
  parseEmbedTexts,
} from "./embed_texts.ts";

Deno.test("a body without texts asks for the normal worker run", () => {
  assertEquals(parseEmbedTexts({}), null);
  assertEquals(parseEmbedTexts(null), null);
  assertEquals(parseEmbedTexts("x"), null);
});

Deno.test("valid texts pass and invalid ones are refused", () => {
  assertEquals(parseEmbedTexts({ texts: ["a", "b"] }), ["a", "b"]);
  for (
    const bad of [
      { texts: [] },
      { texts: "a" },
      { texts: [1] },
      { texts: [" "] },
      { texts: ["x".repeat(maxEmbedTextChars + 1)] },
      { texts: new Array(maxEmbedTexts + 1).fill("a") },
    ]
  ) {
    assertThrows(() => parseEmbedTexts(bad), EmbedTextsError);
  }
});

Deno.test("texts are embedded in order", async () => {
  const result = await embedTexts((text) => Promise.resolve([text.length]), ["a", "bb"]);
  assertEquals(result, [[1], [2]]);
});
