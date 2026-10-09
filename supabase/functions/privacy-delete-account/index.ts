import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { captureException } from "../_shared/sentry.ts";
import { isUserStorageKey } from "../_shared/storage_keys.ts";

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

// Splits stored keys into the ones safe to pass to Storage and a count of the
// rest, which are never sent: a service-role remove ignores Storage RLS.
export function deletableKeys(
  userId: string,
  keys: readonly unknown[],
): { keys: string[]; unsafe: number } {
  const safe = keys.filter((key): key is string => isUserStorageKey(userId, key));
  return { keys: safe, unsafe: keys.filter((key) => typeof key === "string").length - safe.length };
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
    const rows = media.data ?? [];
    const meals = deletableKeys(
      auth.userId,
      rows.filter((row) => row.purpose === "meal_analysis").map((row) => row.object_key),
    );
    const progress = deletableKeys(
      auth.userId,
      rows.filter((row) => row.purpose !== "meal_analysis").map((row) => row.object_key),
    );
    const exports = await auth.serviceClient.from("data_exports").select("storage_path")
      .eq("user_id", auth.userId).not("storage_path", "is", null);
    if (exports.error) throw new Error("export_lookup_failed");
    const exportKeys = deletableKeys(
      auth.userId,
      (exports.data ?? []).map((row) => row.storage_path),
    );
    // An object whose key cannot be passed to Storage safely would outlive the
    // account, so nothing is deleted: the request fails and the owner removes
    // that object by hand before the athlete retries.
    const unsafe = meals.unsafe + progress.unsafe + exportKeys.unsafe;
    if (unsafe > 0) {
      captureException(new Error(`account_deletion_unsafe_keys_${unsafe}`), {
        userId: auth.userId,
        functionName: "privacy-delete-account",
        failureCode: "unsafe_storage_key",
      });
      throw new Error("unsafe_storage_key");
    }
    await removeObjects(auth.serviceClient, "meal-images", meals.keys);
    await removeObjects(auth.serviceClient, "progress-photos", progress.keys);
    await removeObjects(auth.serviceClient, "account-exports", exportKeys.keys);
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
