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
  const messages = sent.messages as Array<Record<string, unknown>>;
  const prompt = String(messages[0].content);
  if (!prompt.includes("NOT MEASURED")) {
    throw new Error("Decision prompt must carry the null contract (null = NOT MEASURED).");
  }
  if (!prompt.includes("never treat it as zero")) {
    throw new Error("Decision prompt must forbid reading null as zero.");
  }
  const sentContext = JSON.parse(
    prompt.slice(
      prompt.indexOf("Prepared evidence context:\n") + "Prepared evidence context:\n".length,
    ),
  ) as Record<string, unknown>;
  if (sentContext.missing_data === undefined) {
    throw new Error("missing_data must be part of the decision context.");
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

Deno.test("Deepseek decision context serializes null metrics as null, never zero (Pass 4)", async () => {
  let sentBody: string | undefined;
  const provider = new DeepseekCoachModelProvider({
    apiKey: "synthetic-key",
    model: "deepseek-v4-flash",
    fetcher: (_input, init) => {
      sentBody = String(init?.body);
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
  await provider.generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "a",
    policyEvaluationId: "b",
    policyOutcome: "request_data",
    permittedEvidence: [],
    featureContext: {
      local_date: "2026-09-08",
      check_in: null,
      health: { sleep_minutes: null, resting_heart_rate_bpm: 58 },
    },
    missingData: ["check_in"],
  });
  if (!sentBody) throw new Error("no request captured");
  // The prompt embeds the context JSON as an escaped string, so unescape
  // the message before asserting — the null tokens must survive as real
  // JSON nulls, not be stripped or coerced to zero.
  const sentJson = JSON.parse(sentBody) as {
    messages: Array<{ content: string }>;
  };
  const prompt = sentJson.messages[0].content;
  const contextStart = prompt.indexOf("Prepared evidence context:\n");
  const contextText = contextStart >= 0
    ? prompt.slice(contextStart + "Prepared evidence context:\n".length)
    : prompt;
  let contextJson: Record<string, unknown> | undefined;
  try {
    contextJson = JSON.parse(contextText) as Record<string, unknown>;
  } catch {
    throw new Error("prepared context did not parse as JSON");
  }
  if (contextJson === undefined) throw new Error("prepared context missing");
  const feature = contextJson.feature_context as Record<string, unknown>;
  if (feature.check_in !== null) {
    throw new Error("null check_in must serialize as null in the decision context");
  }
  const health = feature.health as Record<string, unknown>;
  if (health.sleep_minutes !== null) {
    throw new Error("null sleep_minutes must serialize as null in the decision context");
  }
  if (health.resting_heart_rate_bpm !== 58) {
    throw new Error("measured RHR must still serialize with its value");
  }
});
