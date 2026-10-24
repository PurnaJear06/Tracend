// Compares a presented secret with the expected one without leaking, through timing, how much of
// it matched or how long it is: both are hashed to 32 bytes first, then every byte is compared.
export async function secretsMatch(presented: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(presented)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const left = new Uint8Array(a);
  const right = new Uint8Array(b);
  let difference = 0;
  for (let i = 0; i < left.length; i++) difference |= left[i] ^ right[i];
  return difference === 0;
}

// True when the header is exactly `Bearer <expected>`.
export async function bearerMatches(
  authorization: string | null,
  expected: string,
): Promise<boolean> {
  return await secretsMatch(authorization ?? "", `Bearer ${expected}`);
}
