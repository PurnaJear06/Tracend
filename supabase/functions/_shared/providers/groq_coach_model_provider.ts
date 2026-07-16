import type { CoachDecisionV1 } from "../contracts/coach_decision_v1.ts";
import { decisionSchema } from "./gemini_coach_model_provider.ts";
import type {
  CoachModelGeneration,
  CoachModelProvider,
  CoachModelRequest,
} from "./coach_model_provider.ts";

export type GroqCoachProviderConfig = Readonly<{
  apiKey: string;
  model: string;
  inputCostPerMillionUsd?: number;
  outputCostPerMillionUsd?: number;
  timeoutMs?: number;
  fetcher?: typeof fetch;
}>;

export class GroqCoachModelProvider implements CoachModelProvider {
  readonly #apiKey: string;
  readonly #model: string;
  readonly #inputRate: number;
  readonly #outputRate: number;
  readonly #timeoutMs: number;
  readonly #fetcher: typeof fetch;

  constructor(config: GroqCoachProviderConfig) {
    if (!config.apiKey || config.model !== "qwen/qwen3.6-27b") {
      throw new Error("groq_configuration_invalid");
    }
    this.#apiKey = config.apiKey;
    this.#model = config.model;
    this.#inputRate = config.inputCostPerMillionUsd ?? 0;
    this.#outputRate = config.outputCostPerMillionUsd ?? 0;
    this.#timeoutMs = config.timeoutMs ?? 20_000;
    this.#fetcher = config.fetcher ?? fetch;
    if (
      !Number.isFinite(this.#inputRate) || !Number.isFinite(this.#outputRate) ||
      this.#inputRate < 0 || this.#outputRate < 0
    ) {
      throw new Error("groq_configuration_invalid");
    }
  }

  async generateDecision(request: CoachModelRequest): Promise<CoachModelGeneration> {
    let context = JSON.stringify({
      decision_kind: request.decisionKind,
      policy_outcome: request.policyOutcome,
      permitted_evidence: request.permittedEvidence,
      feature_context: request.featureContext,
      missing_data: request.missingData,
    });
    if (context.length > 12_000) throw new Error("groq_context_too_large");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#timeoutMs);
    try {
      let reasoningInputUnits = 0;
      let reasoningOutputUnits = 0;
      if (request.decisionKind === "weekly") {
        const reasoningResponse = await this.#fetcher(
          "https://api.groq.com/openai/v1/chat/completions",
          {
            method: "POST",
            signal: controller.signal,
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${this.#apiKey}`,
            },
            body: JSON.stringify({
              model: this.#model,
              temperature: 0.1,
              max_completion_tokens: 2400,
              reasoning_effort: "high",
              reasoning_format: "hidden",
              response_format: { type: "json_object" },
              messages: [{
                role: "user",
                content:
                  "Analyze this weekly fitness context. Separate adherence, incomplete evidence, recovery constraints, and ineffective programming. Use only the permitted evidence codes. Return JSON with exactly analysis (string), evidence_ids (array of permitted strings), recommended_action (maintain, gather_data, or propose_change). Do not format the user response and do not claim a persistent change.\n\n" +
                  context,
              }],
            }),
          },
        );
        if (!reasoningResponse.ok) throw new Error("groq_reasoning_failed");
        const reasoningPayload = await reasoningResponse.json() as Record<string, unknown>;
        const reasoningMessage = Array.isArray(reasoningPayload.choices)
          ? (reasoningPayload.choices[0] as Record<string, unknown>)?.message as
            | Record<string, unknown>
            | undefined
          : undefined;
        if (typeof reasoningMessage?.content !== "string") {
          throw new Error("groq_reasoning_invalid");
        }
        const analysis = JSON.parse(reasoningMessage.content) as Record<string, unknown>;
        const keys = Object.keys(analysis).sort().join(",");
        if (
          keys !== "analysis,evidence_ids,recommended_action" ||
          typeof analysis.analysis !== "string" || analysis.analysis.length > 6000 ||
          !Array.isArray(analysis.evidence_ids) ||
          !analysis.evidence_ids.every((id) =>
            typeof id === "string" && request.permittedEvidence.includes(id)
          ) ||
          !["maintain", "gather_data", "propose_change"].includes(
            String(analysis.recommended_action),
          )
        ) throw new Error("groq_reasoning_invalid");
        const reasoningUsage = reasoningPayload.usage as Record<string, unknown> | undefined;
        reasoningInputUnits = Number.isInteger(reasoningUsage?.prompt_tokens)
          ? Number(reasoningUsage?.prompt_tokens)
          : 0;
        reasoningOutputUnits = Number.isInteger(reasoningUsage?.completion_tokens)
          ? Number(reasoningUsage?.completion_tokens)
          : 0;
        context = JSON.stringify({
          prepared_context: JSON.parse(context),
          validated_weekly_analysis: analysis,
        });
      }
      const response = await this.#fetcher("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST",
        signal: controller.signal,
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${this.#apiKey}` },
        body: JSON.stringify({
          model: this.#model,
          temperature: 0.1,
          max_completion_tokens: 1800,
          reasoning_effort: "none",
          reasoning_format: "hidden",
          response_format: { type: "json_object" },
          messages: [{
            role: "user",
            content:
              "You are Tracend's controlled fitness coaching interpreter. Follow deterministic policy exactly. Use only supplied evidence codes. Never diagnose, invent data, create persistent changes, or broaden permitted actions. Return only valid JSON matching this schema: " +
              JSON.stringify(decisionSchema) +
              "\n\nPrepared evidence context:\n" + context,
          }],
        }),
      });
      if (!response.ok) throw new Error("groq_request_failed");
      const payload = await response.json() as Record<string, unknown>;
      const message = Array.isArray(payload.choices)
        ? (payload.choices[0] as Record<string, unknown>)?.message as
          | Record<string, unknown>
          | undefined
        : undefined;
      if (typeof message?.content !== "string") throw new Error("groq_response_invalid");
      const usage = payload.usage as Record<string, unknown> | undefined;
      const inputUnits = reasoningInputUnits +
        (Number.isInteger(usage?.prompt_tokens) ? Number(usage?.prompt_tokens) : 0);
      const outputUnits = Number.isInteger(usage?.completion_tokens)
        ? reasoningOutputUnits + Number(usage?.completion_tokens)
        : reasoningOutputUnits;
      return {
        decision: JSON.parse(message.content) as CoachDecisionV1,
        provider: "groq",
        model: this.#model,
        inputUnits,
        outputUnits,
        estimatedCostUsd: (inputUnits * this.#inputRate + outputUnits * this.#outputRate) /
          1_000_000,
      };
    } catch (error) {
      if (error instanceof Error && error.message.startsWith("groq_")) throw error;
      throw new Error("groq_request_failed");
    } finally {
      clearTimeout(timeout);
    }
  }
}
