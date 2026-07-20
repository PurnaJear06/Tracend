import { AuthError, reply, requireAuth } from "../_shared/auth.ts";

export function stableJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right));
    return `{${
      entries.map(([key, child]) => `${JSON.stringify(key)}:${stableJson(child)}`).join(",")
    }}`;
  }
  return JSON.stringify(value);
}

export async function sha256(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(stableJson(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return reply(405, { error: "method_not_allowed" });
  }

  let auth;
  try {
    auth = await requireAuth(request);
  } catch (e) {
    if (e instanceof AuthError) return reply(e.status, { error: e.message });
    throw e;
  }

  const { data: draft, error: draftError } = await auth.serviceClient
    .from("onboarding_drafts")
    .select("path,payload")
    .eq("user_id", auth.userId)
    .single();

  if (draftError || !draft?.path || !draft.payload) {
    return reply(422, { error: "onboarding_draft_incomplete" });
  }

  const payload = draft.payload as Record<string, unknown>;
  const experienced = draft.path === "experienced";
  const sessions = Number(payload.training_days ?? (experienced ? 4 : 3));
  const sessionsPerWeek = Math.min(7, Math.max(1, sessions));
  const weeklyStructure = experienced
    ? ["Upper A", "Lower A", "Upper B", "Lower B"].slice(0, sessionsPerWeek)
    : ["Full body A", "Full body B", "Full body C"].slice(0, sessionsPerWeek);
  const weightKg = Number(payload.weight_kg ?? 75);
  const calories = Math.round(Math.min(6000, Math.max(1500, weightKg * 30)) / 50) * 50;
  const protein = Math.round(Math.min(400, Math.max(90, weightKg * 2)));
  const snapshot = {
    schema_version: "1.0",
    path: draft.path,
    answers: payload,
    deterministic_inputs: { sessions_per_week: sessionsPerWeek, weight_kg: weightKg },
  };

  const { data: proposalId, error: proposalError } = await auth.serviceClient.rpc(
    "persist_mock_onboarding_proposal",
    {
      target_user_id: auth.userId,
      snapshot_hash: await sha256(snapshot),
      snapshot_features: snapshot,
      training_payload: {
        title: experienced ? "Preserve and Progress" : "Foundation Block",
        block_weeks: experienced ? 8 : 6,
        sessions_per_week: sessionsPerWeek,
        weekly_structure: weeklyStructure,
        prescription: experienced
          ? { strategy: "preserve_confirmed_work", review_after_weeks: 2 }
          : { strategy: "repeatable_full_body_foundation", review_after_weeks: 2 },
      },
      nutrition_payload: {
        calories,
        protein_g: protein,
        carbohydrate_g: Math.round((calories - protein * 4 - 70 * 9) / 4),
        fat_g: 70,
      },
      evidence_payload: [{
        code: "ONBOARDING_ANSWERS_CONFIRMED",
        label: "Your reviewed onboarding answers",
        source: "feature_snapshot",
      }],
      proposal_rationale: experienced
        ? "Preserve confirmed training practices while making the weekly structure repeatable."
        : "Start with a repeatable baseline before evidence-based progression.",
      proposal_benefit: "A clear starting plan that can be measured before it changes.",
      proposal_downside: "Targets are initial estimates and require execution data for refinement.",
    },
  );

  if (proposalError || typeof proposalId !== "string") {
    return reply(422, { error: "proposal_generation_failed" });
  }

  return reply(200, { schema_version: "1.0", proposal_id: proposalId });
});
