import { DeepseekCoachModelProvider } from "./deepseek_coach_model_provider.ts";

Deno.test("Deepseek V4 Flash coach adapter sends bounded JSON-only requests", async () => {
  let request: Request | undefined;
  const provider = new DeepseekCoachModelProvider({
    apiKey: "synthetic-key",
    model: "deepseek-v4-flash",
    inputCostPerMillionUsd: 0.14,
    outputCostPerMillionUsd: 0.28,
    fetcher: (input, init) => {
      request = new Request(input, init);
      return Promise.resolve(
        new Response(
          JSON.stringify({
            choices: [{
              message: {
                content: JSON.stringify({
                  schema_version: "1.0",
                  decision_kind: "daily",
                  training: {
                    action: "GATHER_DATA",
                    summary: "Add a check-in.",
                    today_adjustments: [],
                  },
                  nutrition: {
                    action: "MAINTAIN_TARGETS",
                    summary: "Keep targets.",
                    today_adjustments: [],
                  },
                  head_coach: {
                    final_decision: "Keep the approved plan.",
                    reason: "Evidence is incomplete.",
                  },
                  evidence: [],
                  confidence: "low",
                  missing_data: ["check_in"],
                  risk_flags: [],
                  change_proposals: [],
                }),
              },
            }],
            usage: { prompt_tokens: 100, completion_tokens: 50 },
          }),
          { status: 200 },
        ),
      );
    },
  });
  const result = await provider.generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "a",
    policyEvaluationId: "b",
    policyOutcome: "request_data",
    permittedEvidence: [],
    featureContext: {},
    missingData: ["check_in"],
  });
  if (
    result.provider !== "deepseek" || result.inputUnits !== 100 ||
    result.outputUnits !== 50
  ) {
    throw new Error("Deepseek usage was not parsed.");
  }
  if (
    !request || request.url !== "https://api.deepseek.com/v1/chat/completions" ||
    request.headers.get("Authorization") !== "Bearer synthetic-key"
  ) throw new Error("Deepseek request contract changed.");
  const sent = JSON.parse(await request.text()) as Record<string, unknown>;
  const thinking = sent.thinking as { type?: string } | undefined;
  if (thinking?.type !== "disabled") {
    throw new Error("Deepseek thinking mode must be disabled for decisions.");
  }
});

Deno.test("Deepseek V4 Flash coach adapter reports the HTTP status on failure", async () => {
  const provider = new DeepseekCoachModelProvider({
    apiKey: "synthetic-key",
    model: "deepseek-v4-flash",
    fetcher: () =>
      Promise.resolve(
        new Response(JSON.stringify({ error: { message: "boom" } }), { status: 500 }),
      ),
  });
  try {
    await provider.generateDecision({
      decisionKind: "daily",
      featureSnapshotId: "a",
      policyEvaluationId: "b",
      policyOutcome: "request_data",
      permittedEvidence: [],
      featureContext: {},
      missingData: [],
    });
    throw new Error("Expected the request failure to surface.");
  } catch (error) {
    if (!(error instanceof Error) || error.message !== "deepseek_request_failed_status_500") {
      throw new Error("Failure token did not carry the HTTP status.");
    }
  }
});
