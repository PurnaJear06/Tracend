import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { sha256, stableJson } from "./index.ts";

Deno.test("stableJson — preserves scalar values", () => {
  assertEquals(stableJson(42), "42");
  assertEquals(stableJson("hello"), '"hello"');
  assertEquals(stableJson(true), "true");
  assertEquals(stableJson(null), "null");
});

Deno.test("stableJson — sorts object keys", () => {
  const a = stableJson({ z: 1, a: 2 });
  const b = stableJson({ a: 2, z: 1 });
  assertEquals(a, b);
  assertEquals(a, '{"a":2,"z":1}');
});

Deno.test("stableJson — handles nested objects", () => {
  const result = stableJson({ outer: { b: 1, a: 2 } });
  assertStringIncludes(result, '"outer":');
  assertStringIncludes(result, '"a":2');
  assertStringIncludes(result, '"b":1');
});

Deno.test("stableJson — handles arrays", () => {
  assertEquals(stableJson([3, 1, 2]), "[3,1,2]");
});

Deno.test("stableJson — handles mixed nested structures", () => {
  const obj = { items: [{ name: "B", val: 1 }, { name: "A", val: 2 }] };
  const result = stableJson(obj);
  assertStringIncludes(result, '"name":"B"');
  assertStringIncludes(result, '"val":1');
});

Deno.test("sha256 — produces deterministic 64-char hex", async () => {
  const hash1 = await sha256({ a: 1, b: 2 });
  const hash2 = await sha256({ a: 1, b: 2 });
  assertEquals(hash1, hash2);
  assertEquals(hash1.length, 64);
  assert(/^[0-9a-f]{64}$/.test(hash1));
});

Deno.test("sha256 — different inputs produce different hashes", async () => {
  const hash1 = await sha256({ a: 1 });
  const hash2 = await sha256({ a: 2 });
  assert(hash1 !== hash2);
});

Deno.test("sha256 — key ordering does not affect hash", async () => {
  const hash1 = await sha256({ z: 1, a: 2 });
  const hash2 = await sha256({ a: 2, z: 1 });
  assertEquals(hash1, hash2);
});
