import { createClient } from "npm:@supabase/supabase-js@2.49.8";

const jsonHeaders = { "Content-Type": "application/json" };

function response(status: number, body: Readonly<Record<string, unknown>>) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

export function isExactDeletionConfirmation(value: unknown): boolean {
  return value === "DELETE";
}

async function removeObjects(
  client: {
    storage: {
      from: (bucket: string) => {
        remove: (paths: string[]) => Promise<{ error: unknown }>;
      };
    };
  },
  bucket: string,
  paths: string[],
) {
  for (let index = 0; index < paths.length; index += 100) {
    const result = await client.storage.from(bucket).remove(paths.slice(index, index + 100));
    if (result.error) throw new Error("storage_deletion_failed");
  }
}

export async function handleAccountDeletion(request: Request): Promise<Response> {
  if (request.method !== "POST") return response(405, { error: "method_not_allowed" });
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
  const user = await userClient.auth.getUser();
  if (user.error || !user.data.user) return response(401, { error: "invalid_session" });
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return response(422, { error: "invalid_request" });
  }
  if (!isExactDeletionConfirmation(body.confirmation)) {
    return response(422, { error: "invalid_confirmation" });
  }
  const requested = await userClient.rpc("request_my_account_deletion", { confirmation: "DELETE" });
  if (requested.error || typeof requested.data !== "string") {
    const recent = requested.error?.message.toLowerCase().includes("recent authentication");
    return response(recent ? 401 : 409, {
      error: recent ? "recent_authentication_required" : "deletion_request_rejected",
    });
  }
  const service = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
  const claimed = await service.rpc("claim_account_deletion", {
    target_request_id: requested.data,
  });
  if (claimed.error || claimed.data !== user.data.user.id) {
    return response(409, { error: "deletion_unavailable" });
  }
  try {
    const media = await service.from("media_objects").select("purpose,object_key")
      .eq("user_id", user.data.user.id).neq("lifecycle_status", "deleted");
    if (media.error) throw new Error("media_lookup_failed");
    const mealPaths: string[] = [];
    const progressPaths: string[] = [];
    for (const row of media.data ?? []) {
      if (typeof row.object_key !== "string") continue;
      if (row.purpose === "meal_analysis") mealPaths.push(row.object_key);
      else progressPaths.push(row.object_key);
    }
    const exports = await service.from("data_exports").select("storage_path")
      .eq("user_id", user.data.user.id).not("storage_path", "is", null);
    if (exports.error) throw new Error("export_lookup_failed");
    await removeObjects(service, "meal-images", mealPaths);
    await removeObjects(service, "progress-photos", progressPaths);
    await removeObjects(
      service,
      "account-exports",
      (exports.data ?? []).map((row) => row.storage_path).filter((path): path is string =>
        typeof path === "string"
      ),
    );
    const removed = await service.auth.admin.deleteUser(user.data.user.id);
    if (removed.error) throw new Error("auth_deletion_failed");
    await service.rpc("complete_account_deletion", {
      target_request_id: requested.data,
      succeeded: true,
    });
    return response(200, { schema_version: "1.0", status: "completed" });
  } catch {
    await service.rpc("complete_account_deletion", {
      target_request_id: requested.data,
      succeeded: false,
    });
    return response(503, { error: "deletion_failed" });
  }
}

if (import.meta.main) Deno.serve(handleAccountDeletion);
