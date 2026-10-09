import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { cleanExpiredMealMedia, sweepOrphanObjects } from "../_shared/meal_media_retention.ts";
import { cleanExpiredExports } from "../_shared/export_retention.ts";
import { captureException } from "../_shared/sentry.ts";

const jsonHeaders = { "Content-Type": "application/json" };

function response(status: number, body: Readonly<Record<string, unknown>>) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return response(405, { error: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const workerSecret = Deno.env.get("RETENTION_WORKER_SECRET");
  const authorization = request.headers.get("Authorization");
  if (
    !supabaseUrl || !serviceRoleKey || !workerSecret ||
    authorization !== `Bearer ${workerSecret}`
  ) {
    return response(401, { error: "authentication_required" });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  try {
    const result = await cleanExpiredMealMedia({
      claim: async (batchSize) => {
        const { data, error } = await serviceClient.rpc("claim_expired_meal_media", {
          batch_size: batchSize,
        });
        if (error) throw new Error("claim_failed");
        return data ?? [];
      },
      remove: async (objectKey) => {
        const { error } = await serviceClient.storage.from("meal-images").remove([objectKey]);
        return error === null;
      },
      complete: async (mediaObjectId, succeeded) => {
        const { error } = await serviceClient.rpc("complete_meal_media_retention", {
          target_media_object_id: mediaObjectId,
          deletion_succeeded: succeeded,
        });
        if (error) throw new Error("completion_failed");
      },
    });
    if (result.unsafe > 0) {
      captureException(new Error(`meal_media_unsafe_keys_${result.unsafe}`), {
        functionName: "meal-media-retention",
        failureCode: "unsafe_storage_key",
      });
    }
    const exports = await cleanExpiredExports({
      claim: async () => {
        const { data, error } = await serviceClient.rpc("expire_data_exports");
        if (error) throw new Error("export_claim_failed");
        return data ?? [];
      },
      remove: async (storagePath) => {
        const { error } = await serviceClient.storage.from("account-exports").remove([storagePath]);
        return error === null;
      },
      complete: async (storagePath, succeeded) => {
        const { error } = await serviceClient.rpc("complete_data_export_retention", {
          object_path: storagePath,
          deletion_succeeded: succeeded,
        });
        if (error) throw new Error("export_completion_failed");
      },
    });
    const orphans = await sweepOrphanObjects({
      list: async (batchSize) => {
        const { data, error } = await serviceClient.rpc("list_orphan_storage_objects", {
          batch_size: batchSize,
        });
        if (error) throw new Error("orphan_listing_failed");
        return data ?? [];
      },
      remove: async (bucket, name) => {
        const { error } = await serviceClient.storage.from(bucket).remove([name]);
        return error === null;
      },
    });
    if (orphans.unsafe > 0) {
      captureException(new Error(`orphan_unsafe_keys_${orphans.unsafe}`), {
        functionName: "meal-media-retention",
        failureCode: "unsafe_storage_key",
      });
    }
    await serviceClient.rpc("cleanup_deletion_receipts");
    return response(200, {
      schema_version: "1.0",
      ...result,
      export_retention: exports,
      orphan_sweep: orphans,
    });
  } catch {
    return response(500, { error: "retention_failed" });
  }
});
