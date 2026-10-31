import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { fetchAllByKey } from "../_shared/paging.ts";
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
type MediaRow = Readonly<{ id: string; purpose: string; object_key: string }>;
type ExportRow = Readonly<{ id: string; storage_path: string }>;
type StorageObject = Readonly<{ bucket_id: string; name: string }>;
type KeysetQuery<T> = {
  gt: (column: string, value: string) => KeysetQuery<T>;
  order: (column: string, options: { ascending: boolean }) => KeysetQuery<T>;
  limit: (count: number) => PromiseLike<Page<T>>;
};
export type StorageListingClient = {
  from: (table: string) => {
    select: (columns: string) => {
      eq: (column: string, value: string) => {
        neq: (column: string, value: string) => KeysetQuery<MediaRow>;
        not: (column: string, operator: string, value: null) => KeysetQuery<ExportRow>;
      };
    };
  };
  rpc: (name: string, args: { target_user_id: string }) => {
    eq: (column: string, value: string) => KeysetQuery<StorageObject>;
  };
};

export const accountBuckets = ["meal-images", "progress-photos", "account-exports"] as const;

// PostgREST returns 1000 rows at most per request, so each list is read in keyset pages (rows after
// the last key, in key order). A list cut at 1000 would leave every later file in Storage after the
// account is gone, and offset pages would skip files when rows move while the list is read.
export async function listAccountStorage(client: StorageListingClient, userId: string) {
  const media = await fetchAllByKey<MediaRow>(
    (after, size) => {
      let query = client.from("media_objects").select("id,purpose,object_key").eq("user_id", userId)
        .neq("lifecycle_status", "deleted");
      if (after !== null) query = query.gt("id", after);
      return query.order("id", { ascending: true }).limit(size);
    },
    (row) => row.id,
    "media_lookup_failed",
  );
  const exports = await fetchAllByKey<ExportRow>(
    (after, size) => {
      let query = client.from("data_exports").select("id,storage_path").eq("user_id", userId)
        .not("storage_path", "is", null);
      if (after !== null) query = query.gt("id", after);
      return query.order("id", { ascending: true }).limit(size);
    },
    (row) => row.id,
    "export_lookup_failed",
  );
  // Uploads that never got a database row are in the user's folders too. A name is unique within
  // its bucket, so each bucket is paged by name.
  const objects: StorageObject[] = [];
  for (const bucket of accountBuckets) {
    objects.push(
      ...await fetchAllByKey<StorageObject>(
        (after, size) => {
          let query = client.rpc("list_account_storage_objects", { target_user_id: userId })
            .eq("bucket_id", bucket);
          if (after !== null) query = query.gt("name", after);
          return query.order("name", { ascending: true }).limit(size);
        },
        (row) => row.name,
        "storage_listing_failed",
      ),
    );
  }
  return { media, exports, objects };
}

// Counts only: the event carries no user id, key or path.
export function reportUnsafeKeys(unsafe: number): void {
  captureException(new Error(`account_deletion_unsafe_keys_${unsafe}`), {
    functionName: "privacy-delete-account",
    failureCode: "unsafe_storage_key",
  });
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
      reportUnsafeKeys(unsafe);
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
