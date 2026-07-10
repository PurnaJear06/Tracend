import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2.49.8";
import { strToU8, zipSync } from "npm:fflate@0.8.2";

const jsonHeaders = { "Content-Type": "application/json" };
const dataTables = [
  "user_accounts",
  "user_profiles",
  "consent_records",
  "onboarding_drafts",
  "user_goals",
  "training_plans",
  "training_plan_versions",
  "nutrition_target_sets",
  "planned_workouts",
  "planned_exercises",
  "workout_sessions",
  "exercise_performances",
  "exercise_sets",
  "workout_amendments",
  "daily_check_ins",
  "health_sync_runs",
  "daily_health_summaries",
  "user_foods",
  "media_objects",
  "meals",
  "meal_analysis_candidates",
  "meal_items",
  "body_measurements",
  "progress_photo_sets",
  "progress_photos",
  "progress_reviews",
  "weekly_review_jobs",
  "feature_snapshots",
  "policy_evaluations",
  "model_runs",
  "coach_decisions",
  "change_proposals",
  "change_responses",
  "audit_events",
  "notification_preferences",
] as const;

function response(status: number, body: Readonly<Record<string, unknown>>) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

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

async function collectRows(client: SupabaseClient, userId: string) {
  const output: Record<string, ReadonlyArray<Record<string, unknown>>> = {};
  for (const table of dataTables) {
    const ownerColumn = table === "user_accounts" ? "id" : "user_id";
    const { data, error } = await client.from(table).select("*").eq(ownerColumn, userId);
    if (error) throw new Error(`table_${table}`);
    output[table] = (data ?? []) as ReadonlyArray<Record<string, unknown>>;
  }
  return output;
}

async function addMedia(
  files: Record<string, Uint8Array>,
  client: SupabaseClient,
  rows: Record<string, ReadonlyArray<Record<string, unknown>>>,
) {
  const media = rows.media_objects ?? [];
  for (const object of media) {
    if (object.lifecycle_status === "deleted" || typeof object.object_key !== "string") continue;
    const purpose = String(object.purpose ?? "unknown");
    const bucket = purpose === "meal_analysis" ? "meal-images" : "progress-photos";
    const { data, error } = await client.storage.from(bucket).download(object.object_key);
    if (error || !data) throw new Error("media_download_failed");
    const name = object.object_key.split("/").at(-1) ?? `${object.id}.bin`;
    files[`media/${purpose}/${object.id}-${name}`] = new Uint8Array(await data.arrayBuffer());
  }
}

async function buildExport(
  client: SupabaseClient,
  userId: string,
  email: string | undefined,
) {
  const rows = await collectRows(client, userId);
  const files: Record<string, Uint8Array> = {};
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
    },
    null,
    2,
  ));
  files["data/all-data.json"] = strToU8(JSON.stringify(rows, null, 2));
  for (const [name, values] of Object.entries(rows)) {
    files[`data/csv/${name}.csv`] = strToU8(csv(values));
  }
  await addMedia(files, client, rows);
  return zipSync(files, { level: 6 });
}

export async function handlePrivacyExport(request: Request): Promise<Response> {
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
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return response(401, { error: "invalid_session" });
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return response(422, { error: "invalid_request" });
  }
  const action = body.action;
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  if (action === "download") {
    if (typeof body.export_id !== "string") return response(422, { error: "invalid_request" });
    const { data: path, error } = await userClient.rpc("record_data_export_download", {
      target_export_id: body.export_id,
    });
    if (error || typeof path !== "string") return response(409, { error: "export_unavailable" });
    const signed = await serviceClient.storage.from("account-exports").createSignedUrl(path, 60);
    if (signed.error || !signed.data) return response(503, { error: "download_unavailable" });
    return response(200, {
      schema_version: "1.0",
      download_url: signed.data.signedUrl,
      expires_in: 60,
    });
  }

  if (
    action !== "request" || typeof body.password !== "string" || body.password.length < 12 ||
    body.password.length > 128
  ) {
    return response(422, { error: "invalid_export_request" });
  }
  const requested = await userClient.rpc("request_my_data_export");
  if (requested.error || typeof requested.data !== "string") {
    const recent = requested.error?.message.toLowerCase().includes("recent authentication");
    return response(recent ? 401 : 409, {
      error: recent ? "recent_authentication_required" : "export_request_rejected",
    });
  }
  const exportId = requested.data;
  const claimed = await serviceClient.rpc("claim_data_export", { target_export_id: exportId });
  if (claimed.error) return response(503, { error: "export_queue_unavailable" });
  if (claimed.data == null) {
    const existing = await userClient.from("data_exports").select(
      "id,status,byte_size,created_at,completed_at,expires_at,download_count,sanitized_error_code",
    ).eq("id", exportId).single();
    return response(200, { schema_version: "1.0", export: existing.data });
  }
  try {
    const zip = await buildExport(serviceClient, userData.user.id, userData.user.email);
    const encrypted = await encrypt(zip, body.password);
    const path = `${userData.user.id}/${exportId}.tracendexport`;
    const upload = await serviceClient.storage.from("account-exports").upload(path, encrypted, {
      contentType: "application/octet-stream",
      upsert: false,
    });
    if (upload.error) throw new Error("export_upload_failed");
    const completed = await serviceClient.rpc("complete_data_export", {
      target_export_id: exportId,
      object_path: path,
      object_bytes: encrypted.length,
    });
    if (completed.error) throw new Error("export_finalize_failed");
    return response(200, {
      schema_version: "1.0",
      export: { id: exportId, status: "ready", byte_size: encrypted.length },
    });
  } catch (error) {
    const code = error instanceof Error && error.message.match(/^[a-z0-9_]+$/)
      ? error.message
      : "export_failed";
    await serviceClient.rpc("fail_data_export", { target_export_id: exportId, failure_code: code });
    return response(503, { error: "export_failed" });
  }
}

if (import.meta.main) Deno.serve(handlePrivacyExport);
