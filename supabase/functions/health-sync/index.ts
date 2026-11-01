import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { createLogger, extractCorrelationId } from "../_shared/logger.ts";
import { captureException } from "../_shared/sentry.ts";
import { handleHealthSync } from "./handler.ts";

Deno.serve(async (request) => {
  const correlationId = extractCorrelationId(request);
  const log = createLogger(correlationId);
  if (request.method !== "POST") {
    return reply(405, { error: "method_not_allowed" });
  }

  let auth;
  try {
    auth = await requireAuth(request);
  } catch (e) {
    if (e instanceof AuthError) return reply(e.status, { error: e.message });
    throw e;
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    log.warn("health_sync_invalid");
    return reply(422, { error: "invalid_health_sync" });
  }

  const { serviceClient, userId } = auth;
  return await handleHealthSync(body, {
    log,
    persist: (payload) =>
      serviceClient.rpc("persist_health_sync_v2", {
        target_user_id: userId,
        sync_idempotency_key: payload.idempotency_key,
        request_start: payload.requested_start,
        request_end: payload.requested_end,
        request_types: payload.requested_types,
        response_types: payload.returned_types,
        summary_payload: payload.summaries,
        workout_payload: payload.workouts,
      }),
    report: (failureCode, errorCode) =>
      captureException(new Error(failureCode), {
        userId,
        functionName: "health-sync",
        correlationId,
        failureCode,
        errorCode,
      }),
  });
});
