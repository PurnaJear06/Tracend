import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { parseHealthSyncRequest } from "../_shared/contracts/health_sync_v1.ts";

const jsonHeaders = { "Content-Type": "application/json" };

function response(status: number, body: Readonly<Record<string, unknown>>) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return response(405, { error: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  if (!supabaseUrl || !publishableKey || !serviceRoleKey || !authorization) {
    return response(401, { error: "authentication_required" });
  }

  const userClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return response(401, { error: "invalid_session" });
  }

  let payload;
  try {
    payload = parseHealthSyncRequest(await request.json());
  } catch {
    return response(422, { error: "invalid_health_sync" });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data, error } = await serviceClient.rpc("persist_health_sync", {
    target_user_id: userData.user.id,
    sync_idempotency_key: payload.idempotency_key,
    request_start: payload.requested_start,
    request_end: payload.requested_end,
    request_types: payload.requested_types,
    response_types: payload.returned_types,
    summary_payload: payload.summaries,
  });
  if (error || !data) {
    return response(422, { error: "health_sync_rejected" });
  }

  return response(200, {
    schema_version: "1.0",
    ...data as Record<string, unknown>,
  });
});
