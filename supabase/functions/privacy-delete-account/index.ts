import { AuthError, reply, requireAuth } from "../_shared/auth.ts";

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
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  let auth;
  try {
    auth = await requireAuth(request);
  } catch (e) {
    if (e instanceof AuthError) return reply(e.status, { error: e.message });
    throw e;
  }
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return reply(422, { error: "invalid_request" });
  }
  if (!isExactDeletionConfirmation(body.confirmation)) {
    return reply(422, { error: "invalid_confirmation" });
  }
  const requested = await auth.userClient.rpc("request_my_account_deletion", {
    confirmation: "DELETE",
  });
  if (requested.error || typeof requested.data !== "string") {
    const recent = requested.error?.message.toLowerCase().includes("recent authentication");
    return reply(recent ? 401 : 409, {
      error: recent ? "recent_authentication_required" : "deletion_request_rejected",
    });
  }
  const claimed = await auth.serviceClient.rpc("claim_account_deletion", {
    target_request_id: requested.data,
  });
  if (claimed.error || claimed.data !== auth.userId) {
    return reply(409, { error: "deletion_unavailable" });
  }
  try {
    const media = await auth.serviceClient.from("media_objects").select("purpose,object_key")
      .eq("user_id", auth.userId).neq("lifecycle_status", "deleted");
    if (media.error) throw new Error("media_lookup_failed");
    const mealPaths: string[] = [];
    const progressPaths: string[] = [];
    for (const row of media.data ?? []) {
      if (typeof row.object_key !== "string") continue;
      if (row.purpose === "meal_analysis") mealPaths.push(row.object_key);
      else progressPaths.push(row.object_key);
    }
    const exports = await auth.serviceClient.from("data_exports").select("storage_path")
      .eq("user_id", auth.userId).not("storage_path", "is", null);
    if (exports.error) throw new Error("export_lookup_failed");
    await removeObjects(auth.serviceClient, "meal-images", mealPaths);
    await removeObjects(auth.serviceClient, "progress-photos", progressPaths);
    await removeObjects(
      auth.serviceClient,
      "account-exports",
      (exports.data ?? []).map((row) => row.storage_path).filter((path): path is string =>
        typeof path === "string"
      ),
    );
    const removed = await auth.serviceClient.auth.admin.deleteUser(auth.userId);
    if (removed.error) throw new Error("auth_deletion_failed");
    await auth.serviceClient.rpc("complete_account_deletion", {
      target_request_id: requested.data,
      succeeded: true,
    });
    return reply(200, { schema_version: "1.0", status: "completed" });
  } catch {
    await auth.serviceClient.rpc("complete_account_deletion", {
      target_request_id: requested.data,
      succeeded: false,
    });
    return reply(503, { error: "deletion_failed" });
  }
}

if (import.meta.main) Deno.serve(handleAccountDeletion);
