// What library-embed keeps for the life of its isolate: the worker-secret check it last passed and
// when it last reported a failure to Sentry. Both only save work; neither widens access.

/**
 * How long an accepted worker secret is trusted without asking the database again. The secret
 * changes only when Vault loses it (a restore creates a new one), and a refused secret is never
 * remembered, so the worst case is that a replaced secret keeps working in a warm isolate for this
 * long.
 */
export const workerAuthCacheMs = 5 * 60_000;

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export type WorkerAuthorizerDeps = Readonly<{
  /** The database's check of a candidate secret (library_worker_authorized_v1). */
  check: (candidate: string) => Promise<boolean>;
  now?: () => number;
  ttlMs?: number;
}>;

/**
 * Checks a bearer against the worker secret, remembering the last accepted one (by its SHA-256
 * digest, never the secret itself) for `workerAuthCacheMs`. A refused bearer always goes to the
 * database and never replaces the remembered one.
 */
export function createWorkerAuthorizer(
  deps: WorkerAuthorizerDeps,
): (candidate: string) => Promise<boolean> {
  const now = deps.now ?? Date.now;
  const ttlMs = deps.ttlMs ?? workerAuthCacheMs;
  let accepted: { digest: string; until: number } | undefined;
  return async (candidate) => {
    const digest = await sha256Hex(candidate);
    if (accepted && accepted.digest === digest && now() < accepted.until) return true;
    const ok = await deps.check(candidate);
    if (ok) accepted = { digest, until: now() + ttlMs };
    return ok;
  };
}

/**
 * The shortest time between two Sentry events for library-embed's catch-all failure. Cron calls
 * the function every minute, so a lasting failure would otherwise send one event a minute; every
 * failure is still logged.
 */
export const failureReportIntervalMs = 30 * 60_000;

/** True when a failure should go to Sentry now: the first one, then one per interval. */
export function createReportGate(
  intervalMs: number = failureReportIntervalMs,
  now: () => number = Date.now,
): () => boolean {
  let last: number | undefined;
  return () => {
    const time = now();
    if (last !== undefined && time - last < intervalMs) return false;
    last = time;
    return true;
  };
}
