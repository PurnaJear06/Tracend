import { unzipSync } from "npm:fflate@0.8.2";

const [inputPath, outputDirectory] = Deno.args;
const password = Deno.env.get("TRACEND_EXPORT_PASSWORD");
if (!inputPath || !outputDirectory || !password) {
  console.error(
    "Usage: TRACEND_EXPORT_PASSWORD=... ./scripts/deno.sh run --allow-env=TRACEND_EXPORT_PASSWORD --allow-read=<file> --allow-write=<dir> scripts/decrypt-export.ts <file> <dir>",
  );
  Deno.exit(2);
}

const bytes = await Deno.readFile(inputPath);
const newline = bytes.indexOf(10);
if (newline < 1) throw new Error("Invalid Tracend export header");
const header = JSON.parse(new TextDecoder().decode(bytes.slice(0, newline)));
if (header.format !== "tracend-export" || header.version !== 1) {
  throw new Error("Unsupported Tracend export format");
}
const decodeBase64 = (value: string) =>
  Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
const material = await crypto.subtle.importKey(
  "raw",
  new TextEncoder().encode(password),
  "PBKDF2",
  false,
  ["deriveKey"],
);
const key = await crypto.subtle.deriveKey(
  {
    name: "PBKDF2",
    hash: "SHA-256",
    salt: decodeBase64(header.salt),
    iterations: header.iterations,
  },
  material,
  { name: "AES-GCM", length: 256 },
  false,
  ["decrypt"],
);
const encrypted = bytes.slice(newline + 1);
const decrypted = new Uint8Array(
  await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: decodeBase64(header.iv) },
    key,
    encrypted.buffer.slice(encrypted.byteOffset, encrypted.byteOffset + encrypted.byteLength),
  ),
);
const files = unzipSync(decrypted);
for (const [relativePath, contents] of Object.entries(files)) {
  if (relativePath.includes("..") || relativePath.startsWith("/")) {
    throw new Error("Unsafe export path");
  }
  const destination = `${outputDirectory}/${relativePath}`;
  await Deno.mkdir(destination.slice(0, destination.lastIndexOf("/")), { recursive: true });
  await Deno.writeFile(destination, contents);
}
console.log(`Decrypted ${Object.keys(files).length} files into ${outputDirectory}`);
