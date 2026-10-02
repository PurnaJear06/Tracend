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
 * well-formed JPEG. The whole file is walked: a progressive JPEG has several
 * scans, and metadata may sit between them. Each scan's entropy-coded data is
 * copied as is; anything after the end-of-image marker is dropped.
 */
export function stripJpegMetadata(bytes: Uint8Array): Uint8Array | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== startOfImage) return null;
  const kept: Uint8Array[] = [bytes.subarray(0, 2)];
  let offset = 2;
  let scans = 0;
  while (true) {
    if (offset + 1 >= bytes.length || bytes[offset] !== 0xff) return null;
    const marker = bytes[offset + 1];
    if (marker === 0xff) {
      // Fill bytes between segments.
      offset += 1;
      continue;
    }
    if (marker === endOfImage) {
      if (scans === 0) return null;
      kept.push(bytes.subarray(offset, offset + 2));
      break;
    }
    if ((marker >= 0xd0 && marker <= 0xd7) || marker === startOfImage || marker === 0x01) {
      return null;
    }
    if (offset + 4 > bytes.length) return null;
    const length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    let end = offset + 2 + length;
    if (length < 2 || end > bytes.length) return null;
    if (marker === startOfScan) {
      // The scan header, then its entropy-coded data up to the next marker
      // that is neither a stuffed 0xFF00 nor a restart marker.
      scans += 1;
      while (end < bytes.length) {
        if (bytes[end] !== 0xff) {
          end += 1;
          continue;
        }
        const next = bytes[end + 1];
        if (next === 0x00 || (next !== undefined && next >= 0xd0 && next <= 0xd7)) {
          end += 2;
          continue;
        }
        break;
      }
      if (end >= bytes.length) return null;
    }
    if (!isMetadata(marker)) kept.push(bytes.subarray(offset, end));
    offset = end;
  }
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
