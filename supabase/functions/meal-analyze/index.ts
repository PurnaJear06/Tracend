import { AiBudget } from "../_shared/ai_budget.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import { createLogger, extractCorrelationId } from "../_shared/logger.ts";
import { captureException } from "../_shared/sentry.ts";
import { handleMealAnalyze } from "./handler.ts";
import { mealVisionPath, readMealConsent, reserveMealBudget } from "./vision.ts";

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
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    log.warn("invalid_meal_request");
    return reply(422, { error: "invalid_meal_request" });
  }
  const { serviceClient, userClient, userId } = auth;
  // The gateway route when AI_MEAL_VISION_* is complete, else today's provider.
  const path = mealVisionPath();
  const provider = path.provider;
  const budget = new AiBudget((fn, args) => serviceClient.rpc(fn, args), userId);
  try {
    return await handleMealAnalyze(body, {
      userId,
      provider,
      analyze: path.analyze,
      log,
      report: (error, mealId) =>
        captureException(error, { userId, functionName: "meal-analyze", correlationId, mealId }),
      store: {
        consent: () => readMealConsent((fn, args) => serviceClient.rpc(fn, args), userId, path),
        reserveBudget: () => reserveMealBudget(budget, path),
        keepBudget: () => budget.keep(),
        async loadDraft(mealId) {
          const { data: meal, error } = await serviceClient.from("meals")
            .select("id,status,source,media_objects!inner(object_key,content_type)")
            .eq("id", mealId).eq("user_id", userId).single();
          if (error || !meal || meal.status !== "draft" || meal.source !== "photo_analysis") {
            return null;
          }
          const media = meal.media_objects as unknown as Record<string, unknown>;
          return { objectKey: media.object_key, contentType: String(media.content_type) };
        },
        async download(objectKey) {
          const { data, error } = await serviceClient.storage.from("meal-images")
            .download(objectKey);
          if (error || !data) return null;
          return new Uint8Array(await data.arrayBuffer());
        },
        async recordUsage(usage, latencyMs) {
          const { error } = await serviceClient.rpc("record_ai_usage_event", {
            target_user_id: userId,
            run_purpose: "meal_vision",
            run_provider: provider,
            run_model: usage.model,
            run_input_units: usage.inputUnits,
            run_output_units: usage.outputUnits,
            run_estimated_cost_usd: usage.estimatedCostUsd,
            run_latency_ms: Math.min(latencyMs, 120_000),
          });
          if (error) {
            // The call stays counted by its open reservation.
            budget.keep();
            captureException(new Error("meal_usage_not_recorded"), {
              userId,
              functionName: "meal-analyze",
              correlationId,
              failureCode: error.code ?? "unknown",
            });
          }
        },
        async persistCandidates(mealId, candidates, model) {
          const { error } = await serviceClient.rpc("persist_meal_photo_candidates", {
            target_user_id: userId,
            target_meal_id: mealId,
            candidates,
            run_provider: provider,
            run_model: model,
          });
          return !error;
        },
        async discardDraft(mealId) {
          const { error } = await userClient.rpc("delete_my_meal", { target_meal_id: mealId });
          return !error;
        },
      },
    });
  } finally {
    await budget.release();
  }
});
