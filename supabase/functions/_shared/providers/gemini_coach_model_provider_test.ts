import { parseCoachDecision } from "../contracts/coach_decision_v1.ts";
import { GeminiCoachModelProvider } from "./gemini_coach_model_provider.ts";

const fixtureDecision = {
  schema_version: "1.0",
  decision_kind: "daily",
  training: {
    action: "PROCEED_AS_PLANNED",
    summary: "Complete the approved session.",
    today_adjustments: [],
  },
  nutrition: {
    action: "MAINTAIN_TARGETS",
    summary: "Keep the approved nutrition targets.",
    today_adjustments: [],
  },
  head_coach: {
    final_decision: "Keep today's approved plan.",
    reason: "Current recovery evidence remains within baseline.",
  },
  evidence: [{
    code: "RECOVERY_WITHIN_BASELINE",
    label: "Recovery is within baseline",
    source: "feature_snapshot",
  }],
  confidence: "medium",
  missing_data: [],
  risk_flags: [],
  change_proposals: [],
};

Deno.test("Gemini provider requires the paid-data privacy gate", () => {
  let rejected = false;
  try {
    new GeminiCoachModelProvider({
      apiKey: "synthetic-key",
      model: "synthetic-model",
      paidDataTermsAccepted: false,
    });
  } catch (error) {
    rejected = error instanceof Error && error.message === "gemini_paid_data_terms_required";
  }
  if (!rejected) throw new Error("Unpaid Gemini must remain disabled for restricted data.");
});

Deno.test("Gemini provider sends a key header and structured-output schema", async () => {
  const fetcher: typeof fetch = (input, init) => {
    const url = String(input);
    if (url.includes("synthetic-key")) throw new Error("API key leaked into URL");
    const headers = new Headers(init?.headers);
    if (headers.get("x-goog-api-key") !== "synthetic-key") {
      throw new Error("Missing API key header");
    }
    const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
    const config = body.generationConfig as Record<string, unknown>;
    if (config.responseMimeType !== "application/json" || !config.responseJsonSchema) {
      throw new Error("Structured output was not requested");
    }
    const contents = body.contents as Array<Record<string, unknown>>;
    const parts = contents[0].parts as Array<Record<string, unknown>>;
    if (!String(parts[0].text).includes('"energy":4')) {
      throw new Error("Bounded feature context was not supplied");
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({
          candidates: [{ content: { parts: [{ text: JSON.stringify(fixtureDecision) }] } }],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
  };
  const provider = new GeminiCoachModelProvider({
    apiKey: "synthetic-key",
    model: "synthetic-model",
    paidDataTermsAccepted: true,
    fetcher,
  });
  const result = await provider.generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "synthetic-snapshot",
    policyEvaluationId: "synthetic-policy",
    policyOutcome: "maintain_only",
    permittedEvidence: ["RECOVERY_WITHIN_BASELINE"],
    featureContext: { energy: 4 },
    missingData: [],
  });
  parseCoachDecision(result.decision, ["RECOVERY_WITHIN_BASELINE"], "maintain_only");
});

Deno.test("Gemini provider returns only sanitized failure codes", async () => {
  const provider = new GeminiCoachModelProvider({
    apiKey: "synthetic-key",
    model: "synthetic-model",
    paidDataTermsAccepted: true,
    fetcher: () => Promise.resolve(new Response("private provider detail", { status: 429 })),
  });
  let message = "";
  try {
    await provider.generateDecision({
      decisionKind: "daily",
      featureSnapshotId: "synthetic-snapshot",
      policyEvaluationId: "synthetic-policy",
      policyOutcome: "request_data",
      permittedEvidence: [],
      featureContext: {},
      missingData: ["recovery_check_in"],
    });
  } catch (error) {
    message = error instanceof Error ? error.message : "";
  }
  if (message !== "gemini_request_failed") throw new Error("Provider detail escaped.");
});
