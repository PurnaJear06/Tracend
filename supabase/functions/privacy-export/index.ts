import { SupabaseClient } from "npm:@supabase/supabase-js@2.49.8";
import { strToU8, zipSync } from "npm:fflate@0.8.2";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { fetchAllPages } from "../_shared/paging.ts";
import { isUserStorageKey } from "../_shared/storage_keys.ts";
export const dataTables = [
  "user_accounts",
  "user_profiles",
  "consent_records",
  "onboarding_drafts",
  "onboarding_screenings",
  "user_goals",
  "training_plans",
  "training_plan_versions",
  "nutrition_target_sets",
  "planned_workouts",
  "planned_exercises",
  "workout_sessions",
  "exercise_performances",
  "exercise_sets",
  "exercise_set_heart_rate",
  "sleeping_heart_rate_nights",
  "workout_amendments",
  "daily_check_ins",
  "day_adjustments",
  "pain_reports",
  "health_sync_runs",
  "daily_health_summaries",
  "health_history_months",
  "user_foods",
  "media_objects",
  "meals",
  "meal_analysis_candidates",
  "meal_items",
  "body_measurements",
  "progress_photo_sets",
  "progress_photos",
  "progress_reviews",
  "physique_analyses",
  "weekly_review_jobs",
  "feature_snapshots",
  "policy_evaluations",
  "model_runs",
  "coach_decisions",
  "change_proposals",
  "coach_facts",
  "coach_notes",
  "change_responses",
  "onboarding_generations",
  "onboarding_questions",
  "ai_usage_events",
  "audit_events",
  "notification_preferences",
  "user_preferences",
  "user_baselines",
  "metric_baseline_history",
  "daily_computed_metrics",
  "nutrition_schedule_versions",
  "nutrition_schedule_items",
  "health_workout_references",
  "workout_reconciliations",
  "coach_threads",
  "coach_messages",
  "coach_narrative_entries",
  "coach_session_summaries",
  "coach_context_snapshots",
  "ai_budget_reservations",
  "data_exports",
  "deletion_requests",
] as const;

// Tables that hold a user_id and are deliberately not exported. Each needs a reason, and the test in
// coverage_test.ts fails when a table with a user_id is in neither list.
export const exportExclusions: Readonly<Record<string, string>> = {
  "private.day_adjustment_metric_attempts":
    "Rate-limit counter for readiness metric lookups: timestamps only, no athlete content. The answers it limits are in day_adjustments.",
};

// A stable order for paging. Most tables have an `id` primary key; these do not.
const orderColumns: Readonly<Record<string, readonly string[]>> = {
  health_history_months: ["user_id", "month"],
  sleeping_heart_rate_nights: ["user_id", "local_date"],
  exercise_set_heart_rate: ["exercise_set_id"],
  notification_preferences: ["user_id"],
  onboarding_drafts: ["user_id"],
  user_profiles: ["user_id"],
};

// Columns the database derives from other columns of the same row. They add nothing to a readable
// package (a search index over coach_messages.content).
const derivedColumns: Readonly<Record<string, readonly string[]>> = {
  coach_messages: ["search_vector"],
};

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function csv(rows: ReadonlyArray<Record<string, unknown>>): string {
  if (rows.length === 0) return "";
  const fields = Array.from(new Set(rows.flatMap((row) => Object.keys(row))));
  const cell = (value: unknown) => {
    const text = value == null
      ? ""
      : typeof value === "object"
      ? JSON.stringify(value)
      : String(value);
    return `"${text.replaceAll('"', '""')}"`;
  };
  return [
    fields.map(cell).join(","),
    ...rows.map((row) => fields.map((f) => cell(row[f])).join(",")),
  ]
    .join("\n");
}

export async function encrypt(zip: Uint8Array, password: string): Promise<Uint8Array> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveKey"],
  );
  const key = await crypto.subtle.deriveKey(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations: 310_000 },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt"],
  );
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      key,
      zip.buffer.slice(zip.byteOffset, zip.byteOffset + zip.byteLength) as ArrayBuffer,
    ),
  );
  const header = strToU8(
    JSON.stringify({
      format: "tracend-export",
      version: 1,
      encryption: "AES-256-GCM",
      key_derivation: "PBKDF2-HMAC-SHA256",
      iterations: 310_000,
      salt: encodeBase64(salt),
      iv: encodeBase64(iv),
    }) + "\n",
  );
  const output = new Uint8Array(header.length + ciphertext.length);
  output.set(header);
  output.set(ciphertext, header.length);
  return output;
}

type Page = Readonly<{ data: ReadonlyArray<Record<string, unknown>> | null; error: unknown }>;
type PagedQuery = {
  order: (column: string, options: { ascending: boolean }) => PagedQuery;
  range: (from: number, to: number) => PromiseLike<Page>;
};
export type RowsClient = {
  from: (table: string) => {
    select: (columns: string) => { eq: (column: string, value: string) => PagedQuery };
  };
};

export async function collectRows(client: RowsClient, userId: string) {
  const output: Record<string, ReadonlyArray<Record<string, unknown>>> = {};
  for (const table of dataTables) {
    const ownerColumn = table === "user_accounts" ? "id" : "user_id";
    const order = orderColumns[table] ?? ["id"];
    const rows = await fetchAllPages<Record<string, unknown>>((from, to) => {
      let query = client.from(table).select("*").eq(ownerColumn, userId);
      for (const column of order) query = query.order(column, { ascending: true });
      return query.range(from, to);
    }, `table_${table}`);
    const derived = derivedColumns[table] ?? [];
    output[table] = derived.length === 0 ? rows : rows.map((row) => {
      const kept = { ...row };
      for (const column of derived) delete kept[column];
      return kept;
    });
  }
  return output;
}

type MediaStorage = Readonly<{
  storage: {
    from: (bucket: string) => {
      download: (key: string) => Promise<{ data: Blob | null; error: unknown }>;
    };
  };
}>;

// Returns the ids of media rows whose key is not a safe key in the user's own
// folder. They are listed in the manifest instead of downloaded.
export async function addMedia(
  files: Record<string, Uint8Array>,
  client: MediaStorage,
  rows: Record<string, ReadonlyArray<Record<string, unknown>>>,
  userId: string,
): Promise<string[]> {
  const skipped: string[] = [];
  const media = rows.media_objects ?? [];
  for (const object of media) {
    if (object.lifecycle_status === "deleted" || typeof object.object_key !== "string") continue;
    if (!isUserStorageKey(userId, object.object_key)) {
      skipped.push(String(object.id));
      continue;
    }
    const purpose = String(object.purpose ?? "unknown");
    const bucket = purpose === "meal_analysis" ? "meal-images" : "progress-photos";
    const { data, error } = await client.storage.from(bucket).download(object.object_key);
    if (error || !data) throw new Error("media_download_failed");
    const name = object.object_key.split("/").at(-1) ?? `${object.id}.bin`;
    files[`media/${purpose}/${object.id}-${name}`] = new Uint8Array(await data.arrayBuffer());
  }
  return skipped;
}

async function buildExport(
  client: SupabaseClient,
  userId: string,
  email: string | undefined,
) {
  const rows = await collectRows(client as unknown as RowsClient, userId);
  const files: Record<string, Uint8Array> = {};
  const skippedMedia = await addMedia(files, client, rows, userId);
  const generatedAt = new Date().toISOString();
  files["manifest.json"] = strToU8(JSON.stringify(
    {
      schema_version: "1.0",
      generated_at: generatedAt,
      identity: { user_id: userId, email: email ?? null },
      units: { weight: "kg", body_measurements: "cm", energy: "kcal", macros: "g" },
      provenance:
        "Each record retains its source, timestamps, and canonical units where collected.",
      tables: Object.fromEntries(
        Object.entries(rows).map(([name, values]) => [name, values.length]),
      ),
      skipped_media: skippedMedia,
    },
    null,
    2,
  ));
  files["data/all-data.json"] = strToU8(JSON.stringify(rows, null, 2));
  for (const [name, values] of Object.entries(rows)) {
    files[`data/csv/${name}.csv`] = strToU8(csv(values));
  }
  return zipSync(files, { level: 6 });
}

export async function handlePrivacyExport(request: Request): Promise<Response> {
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
  const action = body.action;

  if (action === "download") {
    if (typeof body.export_id !== "string") return reply(422, { error: "invalid_request" });
    const { data: path, error } = await auth.userClient.rpc("record_data_export_download", {
      target_export_id: body.export_id,
    });
    if (error || typeof path !== "string") return reply(409, { error: "export_unavailable" });
    const signed = await auth.serviceClient.storage.from("account-exports").createSignedUrl(
      path,
      60,
    );
    if (signed.error || !signed.data) return reply(503, { error: "download_unavailable" });
    return reply(200, {
      schema_version: "1.0",
      download_url: signed.data.signedUrl,
      expires_in: 60,
    });
  }

  if (
    action !== "request" || typeof body.password !== "string" || body.password.length < 12 ||
    body.password.length > 128
  ) {
    return reply(422, { error: "invalid_export_request" });
  }
  const requested = await auth.userClient.rpc("request_my_data_export");
  if (requested.error || typeof requested.data !== "string") {
    const recent = requested.error?.message.toLowerCase().includes("recent authentication");
    return reply(recent ? 401 : 409, {
      error: recent ? "recent_authentication_required" : "export_request_rejected",
    });
  }
  const exportId = requested.data;
  const claimed = await auth.serviceClient.rpc("claim_data_export", { target_export_id: exportId });
  if (claimed.error) return reply(503, { error: "export_queue_unavailable" });
  if (claimed.data == null) {
    const existing = await auth.userClient.from("data_exports").select(
      "id,status,byte_size,created_at,completed_at,expires_at,download_count,sanitized_error_code",
    ).eq("id", exportId).single();
    return reply(200, { schema_version: "1.0", export: existing.data });
  }
  const path = `${auth.userId}/${exportId}.tracendexport`;
  let uploaded = false;
  try {
    const zip = await buildExport(auth.serviceClient, auth.userId, auth.userEmail);
    const encrypted = await encrypt(zip, body.password);
    const upload = await auth.serviceClient.storage.from("account-exports").upload(
      path,
      encrypted,
      {
        contentType: "application/octet-stream",
        // A retry of an export that stopped after its upload writes the same path again.
        upsert: true,
      },
    );
    if (upload.error) throw new Error("export_upload_failed");
    uploaded = true;
    const completed = await auth.serviceClient.rpc("complete_data_export", {
      target_export_id: exportId,
      object_path: path,
      object_bytes: encrypted.length,
    });
    if (completed.error) throw new Error("export_finalize_failed");
    return reply(200, {
      schema_version: "1.0",
      export: { id: exportId, status: "ready", byte_size: encrypted.length },
    });
  } catch (error) {
    const code = error instanceof Error && error.message.match(/^[a-z0-9_]+$/)
      ? error.message
      : "export_failed";
    // An export that never became ready must not stay in Storage.
    if (uploaded) await auth.serviceClient.storage.from("account-exports").remove([path]);
    await auth.serviceClient.rpc("fail_data_export", {
      target_export_id: exportId,
      failure_code: code,
    });
    return reply(503, { error: "export_failed" });
  }
}

if (import.meta.main) Deno.serve(handlePrivacyExport);
