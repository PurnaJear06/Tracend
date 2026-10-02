import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { stripJpegMetadata } from "./jpeg.ts";

const segment = (marker: number, payload: number[]) => [
  0xff,
  marker,
  (payload.length + 2) >> 8,
  (payload.length + 2) & 0xff,
  ...payload,
];

const scan = [0xff, 0xda, 0x00, 0x04, 0x01, 0x02, 0x11, 0x22, 0x33, 0xff, 0xd9];

Deno.test("EXIF, XMP and comments are removed; the image data is kept", () => {
  const exif = segment(0xe1, [...new TextEncoder().encode("Exif\0\0GPS 12.97N 77.59E")]);
  const xmp = segment(0xe1, [...new TextEncoder().encode("http://ns.adobe.com/xap/")]);
  const comment = segment(0xfe, [...new TextEncoder().encode("iPhone 12")]);
  const jfif = segment(0xe0, [0x4a, 0x46, 0x49, 0x46, 0x00]);
  const quant = segment(0xdb, [0x00, 0x01, 0x02]);
  const photo = new Uint8Array([
    0xff,
    0xd8,
    ...jfif,
    ...exif,
    ...xmp,
    ...comment,
    ...quant,
    ...scan,
  ]);
  const clean = stripJpegMetadata(photo)!;
  assertEquals([...clean], [0xff, 0xd8, ...jfif, ...quant, ...scan]);
  const text = new TextDecoder().decode(clean);
  assert(!text.includes("GPS") && !text.includes("iPhone"));
});

Deno.test("anything that is not a well-formed JPEG is refused", () => {
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assertEquals(stripJpegMetadata(png), null);
  // A segment longer than the file.
  assertEquals(stripJpegMetadata(new Uint8Array([0xff, 0xd8, 0xff, 0xe1, 0x40, 0x00, 0x01])), null);
  // No image data at all.
  assertEquals(stripJpegMetadata(new Uint8Array([0xff, 0xd8, ...segment(0xdb, [1])])), null);
  assertEquals(stripJpegMetadata(new Uint8Array([0xff, 0xd8, 0xff, 0xd9])), null);
});

Deno.test("a progressive JPEG is walked to the end: metadata between scans goes too", () => {
  const huffman = segment(0xc4, [0x00, 0x01]);
  // Entropy data with a stuffed 0xFF00 and a restart marker, kept as is.
  const firstScan = [0xff, 0xda, 0x00, 0x03, 0x01, 0x10, 0xff, 0x00, 0x20, 0xff, 0xd0, 0x30];
  const lateExif = segment(0xe1, [...new TextEncoder().encode("Exif\0\0GPS 12.97N")]);
  const lateComment = segment(0xfe, [...new TextEncoder().encode("serial 1234")]);
  const secondScan = [0xff, 0xda, 0x00, 0x03, 0x02, 0x40, 0x50];
  const trailer = [...new TextEncoder().encode("GPS after end")];
  const photo = new Uint8Array([
    0xff,
    0xd8,
    ...huffman,
    ...firstScan,
    ...lateExif,
    ...huffman,
    ...lateComment,
    ...secondScan,
    0xff,
    0xd9,
    ...trailer,
  ]);
  const clean = stripJpegMetadata(photo)!;
  assertEquals([...clean], [
    0xff,
    0xd8,
    ...huffman,
    ...firstScan,
    ...huffman,
    ...secondScan,
    0xff,
    0xd9,
  ]);
  const text = new TextDecoder().decode(clean);
  assert(!text.includes("GPS") && !text.includes("serial"));
});

Deno.test("a scan that never ends is refused", () => {
  assertEquals(
    stripJpegMetadata(new Uint8Array([0xff, 0xd8, 0xff, 0xda, 0x00, 0x03, 0x01, 0x10, 0x20])),
    null,
  );
});
