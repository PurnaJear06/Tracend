import { SupabaseClient } from "npm:@supabase/supabase-js@2.49.8";
import { strToU8, zipSync } from "npm:fflate@0.8.2";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { fetchAllByKey } from "../_shared/paging.ts";
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
  "training_pauses",
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
  "data_exports",
  "deletion_requests",
] as const;

// Tables that hold a user_id and are deliberately not exported. Each needs a reason, and the test in
// coverage_test.ts fails when a table with a user_id is in neither list.
export const exportExclusions: Readonly<Record<string, string>> = {
  "private.day_adjustment_metric_attempts":
    "Rate-limit counter for readiness metric lookups: timestamps only, no athlete content. The answers it limits are in day_adjustments.",
  "public.ai_budget_reservations":
    "Internal spend reservations for the AI budget. The settled cost of each call is in ai_usage_events, which is exported.",
};

// Columns left out of an exported table, each with the reason. The coverage test checks that every
// column named here exists in the migrations.
export const omittedColumns: Readonly<Record<string, Readonly<Record<string, string>>>> = {
  coach_context_snapshots: {
    context:
      "A derived copy of tables that are exported (up to about 40 KB for every Coach turn). The snapshot's id, thread, trigger, date, checksum and time stay.",
  },
  coach_messages: {
    search_vector: "A search index the database derives from content.",
    guard_faults:
      "Diagnostics of the Coach answer check, not something the athlete said or was told.",
    lookups: "Diagnostics: which data lookups the Coach turn ran.",
    lookup_rounds: "Diagnostics: how many lookup rounds the Coach turn took.",
    library_version: "Diagnostics: the version of the research library that turn read.",
  },
  data_exports: {
    storage_path:
      "Internal Storage path of the package; the athlete cannot read it (no column grant).",
    queue_message_id: "Internal queue number; the athlete cannot read it (no column grant).",
  },
  deletion_requests: {
    queue_message_id: "Internal queue number; the athlete cannot read it.",
  },
};

// Rows linked to the account by a column other than user_id, or by the account email, read through
// export_linked_account_rows_v1. The invite list's private note about the invitee is not the
// athlete's data and is left out, and so are the waitlist's token hashes and referral graph.
export const linkedExports = ["signup_invites", "waitlist_signups"] as const;

// Every uuid column that points at the account (references user_accounts or auth.users) or is named
// `*_by`, other than user_id, with how its rows reach the export. The coverage test fails on a
// column that is not listed here, and on a listed column that no longer exists.
export const linkedColumns: Readonly<Record<string, string>> = {
  "public.user_accounts.id": "The account row itself: exported as user_accounts.",
  "public.coach_narrative_entries.superseded_by":
    "Points at another entry of the same athlete; the table is exported by user_id.",
  "private.signup_invites.claimed_by":
    "The invite the account claimed: exported as signup_invites through export_linked_account_rows_v1.",
};

// For a table with omitted columns, the columns that are selected: its migration columns minus the
// omitted ones. The omitted columns are never downloaded (`select *` would fetch a snapshot's whole
// context body only to drop it). coverage_test.ts fails when a list drifts from the migrations.
export const selectedColumns: Readonly<Record<string, readonly string[]>> = {
  coach_context_snapshots: [
    "id",
    "user_id",
    "thread_id",
    "schema_version",
    "trigger_kind",
    "coaching_date",
    "context_checksum",
    "created_at",
  ],
  coach_messages: [
    "id",
    "user_id",
    "thread_id",
    "role",
    "content",
    "evidence",
    "missing_data",
    "safety_state",
    "idempotency_key",
    "created_at",
    "answer_source",
    "proposal_id",
  ],
  data_exports: [
    "id",
    "user_id",
    "status",
    "scope",
    "byte_size",
    "created_at",
    "started_at",
    "completed_at",
    "expires_at",
    "download_count",
    "sanitized_error_code",
  ],
  deletion_requests: [
    "id",
    "user_id",
    "status",
    "requested_at",
    "started_at",
    "completed_at",
    "sanitized_error_code",
  ],
};

// The column pages are ordered and continued by. It is unique among one owner's rows: the primary
// key, or the primary key without user_id. Most tables use `id`.
export const keyColumns: Readonly<Record<string, string>> = {
  health_history_months: "month",
  sleeping_heart_rate_nights: "local_date",
  exercise_set_heart_rate: "exercise_set_id",
  notification_preferences: "user_id",
  onboarding_drafts: "user_id",
  user_profiles: "user_id",
};

// A table whose rows are large is read in smaller pages.
const pageSizes: Readonly<Record<string, number>> = { coach_context_snapshots: 100 };

// What one export may hold in memory. The JSON copy, the CSV copies, the zip and the encrypted
// package are all in memory at once in a 256 MB function, so an account over these limits fails
// with a code instead of running the function out of memory.
export const maxRowBytes = 16 * 1024 * 1024;
export const maxMediaBytes = 32 * 1024 * 1024;

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

// A JSON value longer than this is not repeated in the CSV: the same text is in data/all-data.json.
export const csvInlineLimit = 2000;
export const csvPointer = "[see data/all-data.json]";

export function csv(rows: ReadonlyArray<Record<string, unknown>>): string {
  if (rows.length === 0) return "";
  const fields = Array.from(new Set(rows.flatMap((row) => Object.keys(row))));
  const cell = (value: unknown) => {
    let text = value == null
      ? ""
      : typeof value === "object"
      ? JSON.stringify(value)
      : String(value);
    if (typeof value === "object" && value != null && text.length > csvInlineLimit) {
      text = csvPointer;
    }
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
  gt: (column: string, value: string) => PagedQuery;
  order: (column: string, options: { ascending: boolean }) => PagedQuery;
  limit: (count: number) => PromiseLike<Page>;
};
export type RowsClient = {
  from: (table: string) => {
    select: (columns: string) => { eq: (column: string, value: string) => PagedQuery };
  };
  rpc: (
    name: string,
    args: { target_user_id: string; target_email: string | null },
  ) => PromiseLike<{ data: unknown; error: unknown }>;
};

export async function collectRows(
  client: RowsClient,
  userId: string,
  email: string | null = null,
  limit = maxRowBytes,
) {
  const output: Record<string, ReadonlyArray<Record<string, unknown>>> = {};
  let bytes = 0;
  // Counted as each page arrives, so an account over the limit stops mid-table instead of after
  // everything is already in memory.
  const spend = (rows: ReadonlyArray<unknown>) => {
    bytes += JSON.stringify(rows).length;
    if (bytes > limit) throw new Error("export_too_large");
  };
  for (const table of dataTables) {
    const ownerColumn = table === "user_accounts" ? "id" : "user_id";
    const key = keyColumns[table] ?? "id";
    const columns = selectedColumns[table]?.join(",") ?? "*";
    output[table] = await fetchAllByKey<Record<string, unknown>>(
      (after, size) => {
        let query = client.from(table).select(columns).eq(ownerColumn, userId);
        if (after !== null) query = query.gt(key, after);
        return query.order(key, { ascending: true }).limit(size);
      },
      (row) => row[key],
      `table_${table}`,
      pageSizes[table],
      spend,
    );
  }
  const linked = await client.rpc("export_linked_account_rows_v1", {
    target_user_id: userId,
    target_email: email,
  });
  const body = linked.data as Record<string, unknown> | null;
  if (linked.error || body == null || typeof body !== "object") throw new Error("table_linked");
  for (const name of linkedExports) {
    const rows = Array.isArray(body[name]) ? body[name] as Record<string, unknown>[] : [];
    spend(rows);
    output[name] = rows;
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

function isMissingObject(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  const { statusCode, status, message } = error as Record<string, unknown>;
  return String(statusCode ?? status) === "404" ||
    (typeof message === "string" && /not found/i.test(message));
}

// Returns the ids of media rows that are listed in the manifest instead of downloaded: a key that is
// not a safe key in the user's own folder, a photo the retention worker is deleting right now, and an
// object that is already gone from Storage. None of them fails the export. Any other download error
// does, and so does a package over the memory limit.
export async function addMedia(
  files: Record<string, Uint8Array>,
  client: MediaStorage,
  rows: Record<string, ReadonlyArray<Record<string, unknown>>>,
  userId: string,
  limit = maxMediaBytes,
): Promise<string[]> {
  const skipped: string[] = [];
  const media = rows.media_objects ?? [];
  let bytes = 0;
  for (const object of media) {
    if (object.lifecycle_status === "deleted" || typeof object.object_key !== "string") continue;
    if (
      object.lifecycle_status === "pending_deletion" || !isUserStorageKey(userId, object.object_key)
    ) {
      skipped.push(String(object.id));
      continue;
    }
    const purpose = String(object.purpose ?? "unknown");
    const bucket = purpose === "meal_analysis" ? "meal-images" : "progress-photos";
    const { data, error } = await client.storage.from(bucket).download(object.object_key);
    if (isMissingObject(error)) {
      skipped.push(String(object.id));
      continue;
    }
    if (error || !data) throw new Error("media_download_failed");
    bytes += data.size;
    if (bytes > limit) throw new Error("export_too_large");
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
  const rows = await collectRows(client as unknown as RowsClient, userId, email ?? null);
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

// An account over the size limit gets its own answer (retrying cannot help); anything else is the
// general failure.
export function exportFailureReply(code: string): Response {
  return code === "export_too_large"
    ? reply(413, { error: "export_too_large" })
    : reply(503, { error: "export_failed" });
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
    return exportFailureReply(code);
  }
}

if (import.meta.main) Deno.serve(handlePrivacyExport);
