import type { SupabaseClient } from "npm:@supabase/supabase-js@2.49.8";
import { aiCoachingConsent, type ConsentRpc } from "../_shared/ai_consent.ts";
import { AuthError, reply, requireAuth } from "../_shared/auth.ts";
import {
  type CatalogExercise,
  type EquipmentItem,
  type MovementPattern,
  type Muscle,
} from "../_shared/onboarding/catalog.ts";
import { createLogger, extractCorrelationId } from "../_shared/logger.ts";
import { resolveOnboardingModel } from "../_shared/providers/onboarding_plan_provider.ts";
import { captureException } from "../_shared/sentry.ts";
import {
  type GenerationClaim,
  generationLeaseSeconds,
  handleOnboardingPlan,
  type OnboardingStore,
  type StoredQuestions,
} from "./handler.ts";

type EdgeRuntimeGlobal = { EdgeRuntime?: { waitUntil(work: Promise<unknown>): void } };

function supabaseStore(client: SupabaseClient, userId: string): OnboardingStore {
  return {
    async loadDraft() {
      const { data, error } = await client.from("onboarding_drafts")
        .select("path,payload").eq("user_id", userId).maybeSingle();
      if (error) throw error;
      if (!data?.path || !data.payload || typeof data.payload !== "object") return null;
      return { path: data.path, payload: data.payload as Record<string, unknown> };
    },
    async claim(snapshotHash) {
      const { data, error } = await client.rpc("claim_onboarding_generation", {
        target_user_id: userId,
        target_snapshot_hash: snapshotHash,
        lease_seconds: generationLeaseSeconds,
      });
      if (error) throw error;
      return data as GenerationClaim;
    },
    async loadCatalog() {
      const { data, error } = await client.from("exercise_catalog")
        .select("slug,name,movement_pattern,primary_muscles,equipment_required,level,is_compound")
        .eq("status", "active").order("slug");
      if (error) throw error;
      return (data ?? []).map((row): CatalogExercise => ({
        slug: row.slug,
        name: row.name,
        pattern: row.movement_pattern as MovementPattern,
        muscles: row.primary_muscles as Muscle[],
        equipment: row.equipment_required as EquipmentItem[],
        level: row.level as "beginner" | "intermediate",
        compound: row.is_compound,
      }));
    },
    async timezone() {
      const { data, error } = await client.from("user_accounts")
        .select("timezone").eq("id", userId).maybeSingle();
      if (error) throw error;
      return typeof data?.timezone === "string" ? data.timezone : "UTC";
    },
    async loadHealth(from, through) {
      const [days, workouts] = await Promise.all([
        client.from("daily_health_summaries")
          .select("local_date,steps,active_energy_kcal,sleep_minutes,weight_kg")
          .eq("user_id", userId).eq("source_scope", "healthkit")
          .gte("local_date", from).lte("local_date", through),
        client.from("health_workout_references")
          .select("local_date,activity_type,duration_seconds")
          .eq("user_id", userId)
          .gte("local_date", from).lte("local_date", through),
      ]);
      if (days.error) throw days.error;
      if (workouts.error) throw workouts.error;
      const number = (value: unknown) =>
        value === null || value === undefined ? null : Number(value);
      return {
        days: (days.data ?? []).map((row) => ({
          local_date: String(row.local_date),
          steps: number(row.steps),
          active_energy_kcal: number(row.active_energy_kcal),
          sleep_minutes: number(row.sleep_minutes),
          weight_kg: number(row.weight_kg),
        })),
        workouts: (workouts.data ?? []).map((row) => ({
          local_date: String(row.local_date),
          activity_type: String(row.activity_type),
          duration_seconds: Number(row.duration_seconds),
        })),
      };
    },
    async loadHealthHistory(from, through) {
      const { data, error } = await client.from("health_history_months")
        .select(
          "month,workouts,strength_workouts,workout_minutes,sleep_nights,sleep_minutes_avg,weight_days,weight_kg_avg,data_days",
        )
        .eq("user_id", userId).gte("month", from).lte("month", through);
      if (error) throw error;
      const optional = (value: unknown) =>
        value === null || value === undefined ? null : Number(value);
      return (data ?? []).map((row) => ({
        month: String(row.month),
        workouts: Number(row.workouts),
        strength_workouts: Number(row.strength_workouts),
        workout_minutes: Number(row.workout_minutes),
        sleep_nights: Number(row.sleep_nights),
        sleep_minutes_avg: optional(row.sleep_minutes_avg),
        weight_days: Number(row.weight_days),
        weight_kg_avg: optional(row.weight_kg_avg),
        data_days: Number(row.data_days),
      }));
    },
    async loadQuestions(questionsHash) {
      const { data, error } = await client.from("onboarding_questions")
        .select("questions,skipped_reason,metadata")
        .eq("user_id", userId).eq("questions_hash", questionsHash).maybeSingle();
      if (error) throw error;
      return data ? data as StoredQuestions : null;
    },
    async saveQuestions(questionsHash, stored) {
      const { data, error } = await client.rpc("store_onboarding_questions", {
        target_user_id: userId,
        target_questions_hash: questionsHash,
        target_questions: stored.questions,
        target_skipped_reason: stored.skipped_reason,
        target_metadata: stored.metadata,
      });
      if (error) throw error;
      return data as StoredQuestions;
    },
    async recordQuestionUsage(usage) {
      const { error } = await client.rpc("record_ai_usage_event", {
        target_user_id: userId,
        run_purpose: "onboarding_questions",
        run_provider: usage.provider,
        run_model: usage.model,
        run_input_units: usage.inputUnits,
        run_output_units: usage.outputUnits,
        run_estimated_cost_usd: usage.estimatedCostUsd,
        run_latency_ms: usage.latencyMs,
      });
      if (error) throw error;
    },
    consent() {
      return aiCoachingConsent(
        ((name, params) => client.rpc(name, params)) as ConsentRpc,
        userId,
        "onboarding_plan",
      );
    },
    async budgetAvailable() {
      const { error } = await client.rpc("assert_owner_ai_budget", { target_user_id: userId });
      return !error;
    },
    async recordUsage(usage) {
      const { error } = await client.rpc("record_ai_usage_event", {
        target_user_id: userId,
        run_purpose: "onboarding_plan",
        run_provider: usage.provider,
        run_model: usage.model,
        run_input_units: usage.inputUnits,
        run_output_units: usage.outputUnits,
        run_estimated_cost_usd: usage.estimatedCostUsd,
        run_latency_ms: usage.latencyMs,
      });
      if (error) throw error;
    },
    async persist(generationId, snapshotHash, snapshot, proposal, metadata) {
      const { error } = await client.rpc("persist_onboarding_proposal_v3", {
        target_generation_id: generationId,
        target_user_id: userId,
        target_snapshot_hash: snapshotHash,
        snapshot_features: snapshot,
        training_payload: proposal.training,
        nutrition_payload: proposal.nutrition,
        evidence_payload: proposal.evidence,
        proposal_rationale: proposal.rationale,
        proposal_benefit: proposal.benefit,
        proposal_downside: proposal.downside,
        proposal_confidence: proposal.confidence,
        generation_metadata: metadata,
      });
      if (error) {
        // 55000: a newer generation replaced this one while it ran.
        if ((error as { code?: string }).code === "55000") return "superseded";
        throw error;
      }
      return "stored";
    },
    async fail(generationId, code) {
      const { error } = await client.rpc("fail_onboarding_generation", {
        target_generation_id: generationId,
        failure_code: code,
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
  const runtime = (globalThis as EdgeRuntimeGlobal).EdgeRuntime;
  // Older app builds send no body: they always ask for the plan.
  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const mode = body?.mode === "questions" ? "questions" : "plan";
  const sentry = (failureCode: string, fields: Record<string, unknown>) => ({
    functionName: "onboarding-plan",
    correlationId,
    failureCode,
    provider: typeof fields.provider === "string" ? fields.provider : undefined,
    model: typeof fields.model === "string" ? fields.model : undefined,
  });
  try {
    return await handleOnboardingPlan({
      mode,
      store: supabaseStore(auth.serviceClient, auth.userId),
      resolution: () => resolveOnboardingModel(),
      currentYear: new Date().getUTCFullYear(),
      now: () => new Date(),
      background: (work) => runtime ? runtime.waitUntil(work) : void work,
      observer: {
        info: (event, fields) => log.info(event, fields),
        warn: (event, fields) => {
          log.warn(event, fields);
          captureException(
            new Error(event),
            sentry(String(fields.fallbackReason ?? event), fields),
          );
        },
        error: (event, error, fields) => {
          log.error(event, { ...fields, error: error instanceof Error ? error.name : "unknown" });
          captureException(error, sentry(event, fields));
        },
      },
    });
  } catch (error) {
    log.error("onboarding_plan_request_failed", {
      error: error instanceof Error ? error.name : "unknown",
    });
    captureException(error, { functionName: "onboarding-plan", correlationId });
    return reply(503, { error: "onboarding_plan_unavailable" });
  }
});
