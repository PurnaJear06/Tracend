import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { fetchAllPages } from "../_shared/paging.ts";
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
  const safe = [...new Set(keys.filter((key): key is string => isUserStorageKey(userId, key)))];
  const unsafe = keys.filter((key) => typeof key === "string" && !isUserStorageKey(userId, key));
  return { keys: safe, unsafe: unsafe.length };
}

type Page<T> = Readonly<{ data: readonly T[] | null; error: unknown }>;
type MediaRow = Readonly<{ purpose: string; object_key: string }>;
type ExportRow = Readonly<{ storage_path: string }>;
type StorageObject = Readonly<{ bucket_id: string; name: string }>;
export type StorageListingClient = {
  from: (table: string) => {
    select: (columns: string) => {
      eq: (column: string, value: string) => {
        neq: (column: string, value: string) => PagedQuery<MediaRow>;
        not: (column: string, operator: string, value: null) => PagedQuery<ExportRow>;
      };
    };
  };
  rpc: (name: string, args: { target_user_id: string }) => PagedQuery<StorageObject>;
};
type PagedQuery<T> = {
  order: (column: string, options: { ascending: boolean }) => PagedQuery<T>;
  range: (from: number, to: number) => PromiseLike<Page<T>>;
};

// PostgREST returns 1000 rows at most per request, so each list is read page by page. A list cut
// at 1000 would leave every later file in Storage after the account is gone.
export async function listAccountStorage(client: StorageListingClient, userId: string) {
  const media = await fetchAllPages<MediaRow>(
    (from, to) =>
      client.from("media_objects").select("purpose,object_key").eq("user_id", userId)
        .neq("lifecycle_status", "deleted").order("id", { ascending: true }).range(from, to),
    "media_lookup_failed",
  );
  const exports = await fetchAllPages<ExportRow>(
    (from, to) =>
      client.from("data_exports").select("storage_path").eq("user_id", userId)
        .not("storage_path", "is", null).order("id", { ascending: true }).range(from, to),
    "export_lookup_failed",
  );
  // Uploads that never got a database row are in the user's folders too.
  const objects = await fetchAllPages<StorageObject>(
    (from, to) =>
      client.rpc("list_account_storage_objects", { target_user_id: userId })
        .order("bucket_id", { ascending: true }).order("name", { ascending: true }).range(from, to),
    "storage_listing_failed",
  );
  return { media, exports, objects };
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
    const { media: rows, exports, objects } = await listAccountStorage(
      auth.serviceClient as unknown as StorageListingClient,
      auth.userId,
    );
    const inBucket = (bucket: string) =>
      objects.filter((object) => object.bucket_id === bucket).map((object) => object.name);
    const meals = deletableKeys(auth.userId, [
      ...rows.filter((row) => row.purpose === "meal_analysis").map((row) => row.object_key),
      ...inBucket("meal-images"),
    ]);
    const progress = deletableKeys(auth.userId, [
      ...rows.filter((row) => row.purpose !== "meal_analysis").map((row) => row.object_key),
      ...inBucket("progress-photos"),
    ]);
    const exportKeys = deletableKeys(auth.userId, [
      ...exports.map((row) => row.storage_path),
      ...inBucket("account-exports"),
    ]);
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
