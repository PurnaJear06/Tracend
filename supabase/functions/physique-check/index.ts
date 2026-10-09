import type { SupabaseClient } from "npm:@supabase/supabase-js@2.49.8";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { createLogger, extractCorrelationId } from "../_shared/logger.ts";
import {
  physiqueAllowedUsers,
  resolvePhysiqueVision,
} from "../_shared/providers/physique_vision_provider.ts";
import { captureException } from "../_shared/sentry.ts";
import { isUserStorageKey } from "../_shared/storage_keys.ts";
import { handlePhysiqueCheck, type PhysiqueStore } from "./handler.ts";

function supabaseStore(
  userClient: SupabaseClient,
  serviceClient: SupabaseClient,
  userId: string,
): PhysiqueStore {
  const number = (value: unknown) => value === null || value === undefined ? null : Number(value);
  return {
    async grantedNotice() {
      const { data, error } = await userClient.rpc("get_my_photo_ai_notice");
      if (error) throw error;
      const notice = data as { version?: unknown; granted?: unknown } | null;
      return notice?.granted === true && typeof notice.version === "string" ? notice.version : null;
    },
    async budgetAvailable() {
      const { error } = await serviceClient.rpc("assert_owner_ai_budget", {
        target_user_id: userId,
      });
      return !error;
    },
    async profileNotes() {
      const { data, error } = await serviceClient.from("user_profiles")
        .select("limitations_note,nutrition_note").eq("user_id", userId).maybeSingle();
      if (error) throw error;
      return [data?.limitations_note, data?.nutrition_note]
        .filter((note): note is string => typeof note === "string" && note.length > 0);
    },
    async loadSet(setId) {
      const { data, error } = await serviceClient.from("progress_photo_sets")
        .select("status,progress_photos(pose,media_objects(object_key))")
        .eq("id", setId).eq("user_id", userId).maybeSingle();
      if (error) throw error;
      if (!data) return null;
      const photos = (data.progress_photos as unknown as {
        pose: string;
        media_objects: { object_key: string } | null;
      }[]) ?? [];
      return {
        status: String(data.status),
        photos: photos
          .filter((photo) => typeof photo.media_objects?.object_key === "string")
          .map((photo) => ({ pose: photo.pose, objectKey: photo.media_objects!.object_key })),
      };
    },
    async download(objectKey) {
      if (!isUserStorageKey(userId, objectKey)) return null;
      const { data, error } = await serviceClient.storage.from("progress-photos")
        .download(objectKey);
      if (error || !data) return null;
      return new Uint8Array(await data.arrayBuffer());
    },
    async athlete() {
      const [profile, measurement, goal] = await Promise.all([
        serviceClient.from("user_profiles").select("sex,height_cm")
          .eq("user_id", userId).maybeSingle(),
        serviceClient.from("body_measurements")
          .select("weight_kg,waist_cm,chest_cm,hip_cm,arm_cm,thigh_cm")
          .eq("user_id", userId).is("superseded_at", null)
          .order("measured_on", { ascending: false }).order("created_at", { ascending: false })
          .limit(1).maybeSingle(),
        serviceClient.from("user_goals").select("goal_type")
          .eq("user_id", userId).eq("status", "active").order("priority").limit(1).maybeSingle(),
      ]);
      for (const result of [profile, measurement, goal]) if (result.error) throw result.error;
      return {
        sex: typeof profile.data?.sex === "string" ? profile.data.sex : null,
        height_cm: number(profile.data?.height_cm),
        weight_kg: number(measurement.data?.weight_kg),
        waist_cm: number(measurement.data?.waist_cm),
        chest_cm: number(measurement.data?.chest_cm),
        hip_cm: number(measurement.data?.hip_cm),
        arm_cm: number(measurement.data?.arm_cm),
        thigh_cm: number(measurement.data?.thigh_cm),
        goal: typeof goal.data?.goal_type === "string" ? goal.data.goal_type : null,
      };
    },
    async persist(setId, result, model, noticeVersion, metadata) {
      const { data, error } = await serviceClient.rpc("persist_physique_analysis", {
        target_user_id: userId,
        target_set_id: setId,
        analysis_result: result,
        run_provider: "groq",
        run_model: model,
        run_notice_version: noticeVersion,
        run_metadata: metadata,
      });
      if (error) throw error;
      return data as string;
    },
    async recordUsage(usage) {
      const { error } = await serviceClient.rpc("record_ai_usage_event", {
        target_user_id: userId,
        run_purpose: "progress_vision",
        run_provider: "groq",
        run_model: usage.model,
        run_input_units: usage.inputUnits,
        run_output_units: usage.outputUnits,
        run_estimated_cost_usd: usage.estimatedCostUsd,
        run_latency_ms: usage.latencyMs,
      });
      if (error) throw error;
    },
  };
}

Deno.serve(async (request) => {
  const correlationId = extractCorrelationId(request);
  const log = createLogger(correlationId);
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  let auth;
  try {
    auth = await requireAuth(request);
  } catch (e) {
    if (e instanceof AuthError) return reply(e.status, { error: e.message });
    throw e;
  }
  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  if (!body || typeof body !== "object") return reply(422, { error: "invalid_physique_request" });
  try {
    return await handlePhysiqueCheck({
      userId: auth.userId,
      store: supabaseStore(auth.userClient, auth.serviceClient, auth.userId),
      resolution: resolvePhysiqueVision(),
      allowedUsers: physiqueAllowedUsers(),
      observer: {
        info: (event, fields) => log.info(event, fields),
        warn: (event, fields) => {
          log.warn(event, fields);
          captureException(new Error(event), {
            functionName: "physique-check",
            correlationId,
            failureCode: String(fields.rule ?? event),
          });
        },
      },
    }, body);
  } catch (error) {
    // Codes and names only: never photos, prompts or the model's text.
    log.error("physique_check_failed", {
      error: error instanceof Error ? error.message.slice(0, 80) : "unknown",
    });
    captureException(error, { functionName: "physique-check", correlationId });
    return reply(503, { error: "physique_check_failed" });
  }
});
