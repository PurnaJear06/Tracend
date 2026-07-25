import type { CoachDecisionV1 } from "../contracts/coach_decision_v1.ts";
import { decisionSchema } from "./gemini_coach_model_provider.ts";
import type {
  CoachModelGeneration,
  CoachModelProvider,
  CoachModelRequest,
} from "./coach_model_provider.ts";

export type DeepseekCoachProviderConfig = Readonly<{
  apiKey: string;
  model: string;
  inputCostPerMillionUsd?: number;
  outputCostPerMillionUsd?: number;
  timeoutMs?: number;
  fetcher?: typeof fetch;
}>;

export class DeepseekCoachModelProvider implements CoachModelProvider {
  readonly #apiKey: string;
  readonly #model: string;
  readonly #inputRate: number;
  readonly #outputRate: number;
  readonly #timeoutMs: number;
  readonly #fetcher: typeof fetch;

  constructor(config: DeepseekCoachProviderConfig) {
    if (!config.apiKey || config.model !== "deepseek-v4-flash") {
      throw new Error("deepseek_configuration_invalid");
    }
    this.#apiKey = config.apiKey;
    this.#model = config.model;
    this.#inputRate = config.inputCostPerMillionUsd ?? 0;
    this.#outputRate = config.outputCostPerMillionUsd ?? 0;
    this.#timeoutMs = config.timeoutMs ?? 25_000;
    this.#fetcher = config.fetcher ?? fetch;
    if (
      !Number.isFinite(this.#inputRate) || !Number.isFinite(this.#outputRate) ||
      this.#inputRate < 0 || this.#outputRate < 0
    ) {
      throw new Error("deepseek_configuration_invalid");
    }
  }

  async generateDecision(request: CoachModelRequest): Promise<CoachModelGeneration> {
    const context = JSON.stringify({
      decision_kind: request.decisionKind,
      policy_outcome: request.policyOutcome,
      permitted_evidence: request.permittedEvidence,
      feature_context: request.featureContext,
      missing_data: request.missingData,
    });
    if (context.length > 12_000) throw new Error("deepseek_context_too_large");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#timeoutMs);
    try {
      const response = await this.#fetcher(
        "https://api.deepseek.com/v1/chat/completions",
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
            max_tokens: 1800,
            response_format: { type: "json_object" },
            messages: [{
              role: "user",
              content:
                "You are Tracend's controlled fitness coaching interpreter. Follow deterministic policy exactly. Use only supplied evidence codes. Never diagnose, invent data, create persistent changes, or broaden permitted actions. Return only valid JSON matching this schema: " +
                JSON.stringify(decisionSchema) +
                "\n\nPrepared evidence context:\n" + context,
            }],
          }),
        },
      );
      if (!response.ok) throw new Error("deepseek_request_failed");
      const payload = await response.json() as Record<string, unknown>;
      const message = Array.isArray(payload.choices)
        ? (payload.choices[0] as Record<string, unknown>)?.message as
          | Record<string, unknown>
          | undefined
        : undefined;
      if (typeof message?.content !== "string") throw new Error("deepseek_response_invalid");
      const usage = payload.usage as Record<string, unknown> | undefined;
      const inputUnits = Number.isInteger(usage?.prompt_tokens) ? Number(usage?.prompt_tokens) : 0;
      const outputUnits = Number.isInteger(usage?.completion_tokens)
        ? Number(usage?.completion_tokens)
        : 0;
      return {
        decision: JSON.parse(message.content) as CoachDecisionV1,
        provider: "deepseek",
        model: this.#model,
        inputUnits,
        outputUnits,
        estimatedCostUsd: (inputUnits * this.#inputRate + outputUnits * this.#outputRate) /
          1_000_000,
      };
    } catch (error) {
      if (error instanceof Error && error.message.startsWith("deepseek_")) throw error;
      throw new Error("deepseek_request_failed");
    } finally {
      clearTimeout(timeout);
    }
  }
}
