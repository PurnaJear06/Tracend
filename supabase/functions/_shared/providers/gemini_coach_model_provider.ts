import type { CoachDecisionV1 } from "../contracts/coach_decision_v1.ts";
import type {
  CoachModelGeneration,
  CoachModelProvider,
  CoachModelRequest,
} from "./coach_model_provider.ts";

type Fetcher = typeof fetch;

const decisionSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    schema_version: { type: "string", enum: ["1.0"] },
    decision_kind: { type: "string", enum: ["daily"] },
    training: {
      type: "object",
      additionalProperties: false,
      properties: {
        action: {
          type: "string",
          enum: [
            "PROCEED_AS_PLANNED",
            "ADJUST_TODAY",
            "GATHER_DATA",
            "REVIEW_PROPOSAL",
            "ESCALATE",
          ],
        },
        summary: { type: "string" },
        today_adjustments: { type: "array", items: { type: "string" }, maxItems: 8 },
      },
      required: ["action", "summary", "today_adjustments"],
    },
    nutrition: {
      type: "object",
      additionalProperties: false,
      properties: {
        action: {
          type: "string",
          enum: [
            "MAINTAIN_TARGETS",
            "PRIORITIZE_PROTEIN",
            "GATHER_DATA",
            "REVIEW_PROPOSAL",
            "ESCALATE",
          ],
        },
        summary: { type: "string" },
        today_adjustments: { type: "array", items: { type: "string" }, maxItems: 8 },
      },
      required: ["action", "summary", "today_adjustments"],
    },
    head_coach: {
      type: "object",
      additionalProperties: false,
      properties: {
        final_decision: { type: "string" },
        reason: { type: "string" },
      },
      required: ["final_decision", "reason"],
    },
    evidence: {
      type: "array",
      maxItems: 20,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          code: { type: "string" },
          label: { type: "string" },
          source: { type: "string", enum: ["feature_snapshot", "policy_evaluation"] },
        },
        required: ["code", "label", "source"],
      },
    },
    confidence: { type: "string", enum: ["low", "medium", "high"] },
    missing_data: { type: "array", items: { type: "string" }, maxItems: 20 },
    risk_flags: { type: "array", items: { type: "string" }, maxItems: 20 },
    change_proposals: { type: "array", maxItems: 0, items: { type: "object" } },
  },
  required: [
    "schema_version",
    "decision_kind",
    "training",
    "nutrition",
    "head_coach",
    "evidence",
    "confidence",
    "missing_data",
    "risk_flags",
    "change_proposals",
  ],
} as const;

export type GeminiCoachProviderConfig = Readonly<{
  apiKey: string;
  model: string;
  paidDataTermsAccepted: boolean;
  inputCostPerMillionUsd?: number;
  outputCostPerMillionUsd?: number;
  timeoutMs?: number;
  fetcher?: Fetcher;
}>;

export class GeminiCoachModelProvider implements CoachModelProvider {
  readonly #apiKey: string;
  readonly #model: string;
  readonly #timeoutMs: number;
  readonly #fetcher: Fetcher;
  readonly #inputCostPerMillionUsd: number;
  readonly #outputCostPerMillionUsd: number;

  constructor(config: GeminiCoachProviderConfig) {
    if (!config.apiKey || !config.model) throw new Error("gemini_configuration_invalid");
    if (!config.paidDataTermsAccepted) throw new Error("gemini_paid_data_terms_required");
    this.#apiKey = config.apiKey;
    this.#model = config.model;
    this.#timeoutMs = config.timeoutMs ?? 20_000;
    this.#fetcher = config.fetcher ?? fetch;
    this.#inputCostPerMillionUsd = config.inputCostPerMillionUsd ?? 0;
    this.#outputCostPerMillionUsd = config.outputCostPerMillionUsd ?? 0;
    if (
      this.#inputCostPerMillionUsd < 0 || this.#outputCostPerMillionUsd < 0 ||
      !Number.isFinite(this.#inputCostPerMillionUsd) ||
      !Number.isFinite(this.#outputCostPerMillionUsd)
    ) throw new Error("gemini_configuration_invalid");
  }

  async generateDecision(request: CoachModelRequest): Promise<CoachModelGeneration> {
    const boundedContext = JSON.stringify({
      decision_kind: request.decisionKind,
      policy_outcome: request.policyOutcome,
      permitted_evidence: request.permittedEvidence,
      feature_context: request.featureContext,
      missing_data: request.missingData,
    });
    if (boundedContext.length > 12_000) throw new Error("gemini_context_too_large");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#timeoutMs);
    try {
      const response = await this.#fetcher(
        `https://generativelanguage.googleapis.com/v1beta/models/${
          encodeURIComponent(this.#model)
        }:generateContent`,
        {
          method: "POST",
          signal: controller.signal,
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": this.#apiKey,
          },
          body: JSON.stringify({
            systemInstruction: {
              parts: [{
                text:
                  "You are Tracend's controlled fitness coaching interpreter. Follow deterministic policy exactly. Use only supplied evidence codes. Never diagnose, invent data, create persistent changes, or broaden permitted actions. Return only the requested JSON.",
              }],
            },
            contents: [{
              role: "user",
              parts: [{ text: boundedContext }],
            }],
            generationConfig: {
              temperature: 0.1,
              maxOutputTokens: 1800,
              responseMimeType: "application/json",
              responseJsonSchema: decisionSchema,
              thinkingConfig: { thinkingLevel: "medium" },
            },
          }),
        },
      );
      if (!response.ok) throw new Error("gemini_request_failed");
      const payload = await response.json() as Record<string, unknown>;
      const candidates = payload.candidates;
      if (!Array.isArray(candidates) || candidates.length !== 1) {
        throw new Error("gemini_response_invalid");
      }
      const content = candidates[0] as Record<string, unknown>;
      const parts = (content.content as Record<string, unknown> | undefined)?.parts;
      if (
        !Array.isArray(parts) || typeof (parts[0] as Record<string, unknown>)?.text !== "string"
      ) {
        throw new Error("gemini_response_invalid");
      }
      const usage = payload.usageMetadata as Record<string, unknown> | undefined;
      const inputUnits = this.#nonnegativeInteger(usage?.promptTokenCount);
      const outputUnits = this.#nonnegativeInteger(usage?.candidatesTokenCount);
      return {
        decision: JSON.parse((parts[0] as Record<string, string>).text) as CoachDecisionV1,
        provider: "gemini",
        model: this.#model,
        inputUnits,
        outputUnits,
        estimatedCostUsd: (
          inputUnits * this.#inputCostPerMillionUsd +
          outputUnits * this.#outputCostPerMillionUsd
        ) / 1_000_000,
      };
    } catch (error) {
      if (error instanceof Error && error.message.startsWith("gemini_")) throw error;
      throw new Error("gemini_request_failed");
    } finally {
      clearTimeout(timeout);
    }
  }

  #nonnegativeInteger(value: unknown): number {
    return Number.isInteger(value) && Number(value) >= 0 ? Number(value) : 0;
  }
}
