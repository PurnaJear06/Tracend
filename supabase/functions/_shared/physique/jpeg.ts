// Prepares a stored progress photo for the model: it must be a JPEG, and every
// metadata segment (EXIF with its location and camera details, XMP, ICC
// profiles, comments) is removed before the photo leaves Tracend. The app
// already re-encodes photos at capture without metadata; this is the server's
// own check, so an older or unexpected upload never sends more than pixels.

/** Base64 grows a file by a third; Groq accepts base64 images up to 4 MB. */
export const maxPhotoBytes = 3_000_000;

const startOfImage = 0xd8;
const startOfScan = 0xda;
const endOfImage = 0xd9;

/** APP1-APP15 (EXIF, XMP, ICC, maker data) and COM. APP0 (JFIF) is kept. */
const isMetadata = (marker: number) => (marker >= 0xe1 && marker <= 0xef) || marker === 0xfe;

/**
 * The photo without its metadata segments, or null when it is not a
 * well-formed JPEG. The image data from the start of scan on is copied as is.
 */
export function stripJpegMetadata(bytes: Uint8Array): Uint8Array | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== startOfImage) return null;
  const kept: Uint8Array[] = [bytes.subarray(0, 2)];
  let offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset] !== 0xff) return null;
    const marker = bytes[offset + 1];
    if (marker === undefined) return null;
    if (marker === 0xff) {
      // Fill bytes between segments.
      offset += 1;
      continue;
    }
    if (marker === endOfImage) return null;
    if (marker === startOfScan) {
      kept.push(bytes.subarray(offset));
      break;
    }
    if (marker >= 0xd0 && marker <= 0xd7) return null;
    if (offset + 4 > bytes.length) return null;
    const length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    const end = offset + 2 + length;
    if (length < 2 || end > bytes.length) return null;
    if (!isMetadata(marker)) kept.push(bytes.subarray(offset, end));
    offset = end;
  }
  if (offset >= bytes.length) return null;
  const size = kept.reduce((total, part) => total + part.length, 0);
  const clean = new Uint8Array(size);
  let at = 0;
  for (const part of kept) {
    clean.set(part, at);
    at += part.length;
  }
  return clean;
}

export function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, Math.min(index + 0x8000, bytes.length)));
  }
  return btoa(binary);
}
