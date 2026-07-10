import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { csv, encrypt } from "./index.ts";

Deno.test("CSV preserves user-readable fields and quotes", () => {
  assertEquals(csv([{ value: "a,b", count: 2 }]), '"value","count"\n"a,b","2"');
});

Deno.test("export bytes are encrypted and contain no plaintext payload", async () => {
  const plaintext = new TextEncoder().encode("private-health-export-marker");
  const encrypted = await encrypt(plaintext, "correct horse battery staple");
  const output = new TextDecoder().decode(encrypted);
  assert(output.startsWith('{"format":"tracend-export"'));
  assert(!output.includes("private-health-export-marker"));
  assert(output.includes('"encryption":"AES-256-GCM"'));
});
