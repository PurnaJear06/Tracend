// Service-role Storage calls bypass Storage RLS, so a key read from the
// database must pass these checks before it reaches Storage. A segment starts
// with a letter, digit or underscore and holds only letters, digits, `_`, `.`
// and `-`: no empty, `.` or `..` segment, and no `%`, `\` or control character
// that a client or server could decode into another path.
const segment = /^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$/;

export function isSafeStorageKey(key: unknown): key is string {
  if (typeof key !== "string" || key.length === 0 || key.length > 512) return false;
  return key.split("/").every((part) => segment.test(part));
}

// A safe key inside the user's own folder.
export function isUserStorageKey(userId: string, key: unknown): key is string {
  return isSafeStorageKey(key) && key.startsWith(`${userId}/`) &&
    key.length > userId.length + 1;
}
