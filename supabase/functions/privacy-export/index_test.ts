import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { addMedia, csv, encrypt } from "./index.ts";

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

Deno.test("export downloads only safe keys in the user's own folder", async () => {
  const user = "11111111-1111-4111-8111-111111111111";
  const requested: string[] = [];
  const client = {
    storage: {
      from: (_bucket: string) => ({
        download: (key: string) => {
          requested.push(key);
          return Promise.resolve({ data: new Blob([new Uint8Array([1])]), error: null });
        },
      }),
    },
  };
  const files: Record<string, Uint8Array> = {};
  const skipped = await addMedia(files, client, {
    media_objects: [
      { id: "a", purpose: "meal_analysis", object_key: `${user}/meal/a.jpg` },
      { id: "b", purpose: "meal_analysis", object_key: `${user}/meal/../../other/x` },
      {
        id: "c",
        purpose: "progress_front",
        object_key: "22222222-2222-4222-8222-222222222222/x.jpg",
      },
    ],
  }, user);
  assertEquals(requested, [`${user}/meal/a.jpg`]);
  assertEquals(skipped, ["b", "c"]);
  assertEquals(Object.keys(files), ["media/meal_analysis/a-a.jpg"]);
});
