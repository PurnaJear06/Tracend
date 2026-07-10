import { createClient } from "npm:@supabase/supabase-js@2.49.8";

const jsonHeaders = { "Content-Type": "application/json" };

function response(status: number, body: Readonly<Record<string, unknown>>) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function stableJson(value: unknown): string {
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

async function sha256(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(stableJson(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return response(405, { error: "method_not_allowed" });
  }

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
  if (userError || !userData.user) {
    return response(401, { error: "invalid_session" });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const userId = userData.user.id;
  const { data: draft, error: draftError } = await serviceClient
    .from("onboarding_drafts")
    .select("path,payload")
    .eq("user_id", userId)
    .single();

  if (draftError || !draft?.path || !draft.payload) {
    return response(422, { error: "onboarding_draft_incomplete" });
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

  const { data: proposalId, error: proposalError } = await serviceClient.rpc(
    "persist_mock_onboarding_proposal",
    {
      target_user_id: userId,
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
    return response(422, { error: "proposal_generation_failed" });
  }

  return response(200, { schema_version: "1.0", proposal_id: proposalId });
});
