import { parseHealthSyncRequest } from "../_shared/contracts/health_sync_v1.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";

Deno.serve(async (request) => {
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

  let payload;
  try {
    payload = parseHealthSyncRequest(await request.json());
  } catch {
    return reply(422, { error: "invalid_health_sync" });
  }

  const { data, error } = await auth.serviceClient.rpc("persist_health_sync_v2", {
    target_user_id: auth.userId,
    sync_idempotency_key: payload.idempotency_key,
    request_start: payload.requested_start,
    request_end: payload.requested_end,
    request_types: payload.requested_types,
    response_types: payload.returned_types,
    summary_payload: payload.summaries,
    workout_payload: payload.workouts,
  });
  if (error || !data) {
    return reply(422, { error: "health_sync_rejected" });
  }

  return reply(200, {
    schema_version: "1.0",
    ...data as Record<string, unknown>,
  });
});
