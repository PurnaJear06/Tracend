import {
  type HealthSyncRequestV1,
  parseHealthSyncRequest,
} from "../_shared/contracts/health_sync_v1.ts";
import { reply } from "../_shared/auth.ts";
import type { Logger } from "../_shared/logger.ts";

/** What `persist_health_sync_v2` answered: its result, or the database error. */
export type HealthSyncWrite = {
  data: unknown;
  error: { code?: string } | null;
};

export type HealthSyncDeps = {
  persist: (payload: HealthSyncRequestV1) => PromiseLike<HealthSyncWrite>;
  log: Logger;
  /** Sends a codes-only Sentry event (`_shared/sentry.ts`). */
  report: (failureCode: string, errorCode: string) => void;
};

const sqlState = /^[0-9A-Z]{5}$/;

/**
 * How a refused write is answered. A batch the database refuses as invalid (a data exception,
 * a broken constraint, or an account that is gone) is the app's to fix: 422 with the SQLSTATE,
 * and sending it again changes nothing. The hourly limit (54000) is 429. Anything else (a lost
 * connection, a timeout, a missing grant) is the server's: 503, and the app's retry may get
 * through. Both of those are logged and reported by code, never with the payload.
 */
export function healthSyncFailure(error: { code?: string } | null): {
  status: 422 | 429 | 503;
  error: string;
  code: string;
} {
  const code = typeof error?.code === "string" && sqlState.test(error.code)
    ? error.code
    : "unknown";
  if (code.startsWith("22") || code.startsWith("23") || code === "P0002") {
    return { status: 422, error: "health_sync_rejected", code };
  }
  if (code === "54000") return { status: 429, error: "health_sync_limit", code };
  return { status: 503, error: "health_sync_unavailable", code };
}

export async function handleHealthSync(body: unknown, deps: HealthSyncDeps): Promise<Response> {
  let payload: HealthSyncRequestV1;
  try {
    payload = parseHealthSyncRequest(body);
  } catch {
    deps.log.warn("health_sync_invalid");
    return reply(422, { error: "invalid_health_sync" });
  }

  let write: HealthSyncWrite;
  try {
    write = await deps.persist(payload);
  } catch {
    write = { data: null, error: null };
  }
  if (write.error || !write.data) {
    const failure = healthSyncFailure(write.error);
    if (failure.status === 422) {
      deps.log.warn("health_sync_rejected", { error_code: failure.code });
    } else {
      deps.log.error(failure.error, { error_code: failure.code });
      deps.report(failure.error, failure.code);
    }
    return reply(failure.status, { error: failure.error, code: failure.code });
  }

  return reply(200, {
    schema_version: "1.0",
    ...write.data as Record<string, unknown>,
  });
}
