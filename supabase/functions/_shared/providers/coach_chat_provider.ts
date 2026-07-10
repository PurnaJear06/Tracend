import { type CoachChatAnswerV1, parseCoachChatAnswer } from "../contracts/coach_chat_v1.ts";

export type CoachChatGeneration = Readonly<{
  answer: CoachChatAnswerV1;
  provider: "mock" | "gemini";
  model: string;
  inputUnits: number;
  outputUnits: number;
  estimatedCostUsd: number;
}>;

const answerSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    answer: { type: "string" },
    evidence: {
      type: "array",
      maxItems: 12,
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
    missing_data: { type: "array", maxItems: 12, items: { type: "string" } },
    safety_state: { type: "string", enum: ["allowed", "limited", "refused", "unavailable"] },
    suggested_follow_ups: { type: "array", maxItems: 4, items: { type: "string" } },
  },
  required: ["answer", "evidence", "missing_data", "safety_state", "suggested_follow_ups"],
} as const;

function deterministicBoundary(question: string): CoachChatAnswerV1 | null {
  const normalized = question.toLowerCase();
  const emergency = [
    "chest pain",
    "fainting",
    "can't breathe",
    "cannot breathe",
    "severe shortness of breath",
  ];
  if (emergency.some((term) => normalized.includes(term))) {
    return {
      answer:
        "Stop the activity. Tracend cannot safely assess these symptoms. Contact local emergency services or seek urgent medical care now.",
      evidence: [],
      missing_data: [],
      safety_state: "refused",
      suggested_follow_ups: [],
    };
  }
  const clinical = [
    "diagnose",
    "medication",
    "medical report",
    "rehab",
    "pregnant",
    "eating disorder",
  ];
  if (clinical.some((term) => normalized.includes(term))) {
    return {
      answer:
        "Tracend cannot provide diagnosis, treatment, rehabilitation, medication, pregnancy, or eating-disorder guidance. Use a qualified clinician for this request.",
      evidence: [],
      missing_data: [],
      safety_state: "refused",
      suggested_follow_ups: [
        "Ask about the approved training plan",
        "Review current fitness evidence",
      ],
    };
  }
  return null;
}

function fallbackAnswer(context: Record<string, unknown>): CoachChatAnswerV1 {
  const permitted = Array.isArray(context.permitted_evidence)
    ? context.permitted_evidence.filter((item): item is string => typeof item === "string")
    : [];
  const code = permitted.includes("APPROVED_PLAN_ACTIVE") ? "APPROVED_PLAN_ACTIVE" : permitted[0];
  return {
    answer:
      "Your approved plan remains the source of truth. Use the scheduled workout or meal shown in Tracend, and add a check-in if you want a more specific evidence-based answer.",
    evidence: code
      ? [{ code, label: "Your approved plan is active", source: "feature_snapshot" }]
      : [],
    missing_data: Array.isArray(context.missing_data)
      ? context.missing_data.filter((item): item is string => typeof item === "string").slice(0, 12)
      : [],
    safety_state: "limited",
    suggested_follow_ups: ["What is my next scheduled action?", "What evidence is missing today?"],
  };
}

export async function generateCoachChat(
  question: string,
  context: Record<string, unknown>,
  fetcher: typeof fetch = fetch,
): Promise<CoachChatGeneration> {
  const boundary = deterministicBoundary(question);
  if (boundary) {
    return {
      answer: boundary,
      provider: "mock",
      model: "deterministic-safety-v1",
      inputUnits: 0,
      outputUnits: 0,
      estimatedCostUsd: 0,
    };
  }

  const enabled = Deno.env.get("COACH_AI_ENABLED") === "true";
  const paid = Deno.env.get("GEMINI_PAID_DATA_TERMS_ACCEPTED") === "true";
  const key = Deno.env.get("GEMINI_API_KEY") ?? "";
  const model = Deno.env.get("GEMINI_MODEL") ?? "";
  const permitted = Array.isArray(context.permitted_evidence)
    ? context.permitted_evidence.filter((item): item is string => typeof item === "string")
    : [];
  if (!enabled || !paid || !key || model !== "gemini-3.5-flash") {
    return {
      answer: fallbackAnswer(context),
      provider: "mock",
      model: "deterministic-chat-fallback-v1",
      inputUnits: 0,
      outputUnits: 0,
      estimatedCostUsd: 0,
    };
  }
  const bounded = JSON.stringify({ question, context });
  if (bounded.length > 18000) throw new Error("chat_context_too_large");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    const response = await fetcher(
      `https://generativelanguage.googleapis.com/v1beta/models/${
        encodeURIComponent(model)
      }:generateContent`,
      {
        method: "POST",
        signal: controller.signal,
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{
              text:
                "You are Tracend's evidence-driven fitness coach for healthy adults. Answer only training, nutrition, recovery, progress, evidence, and app-usage questions. Use only supplied facts and evidence codes. State missing data. Never diagnose, give medical treatment, or claim to change a plan, target, meal, or durable fact. Persistent suggestions require explicit approval. Return only the requested JSON.",
            }],
          },
          contents: [{ role: "user", parts: [{ text: bounded }] }],
          generationConfig: {
            temperature: 0.15,
            maxOutputTokens: 2200,
            responseMimeType: "application/json",
            responseJsonSchema: answerSchema,
            thinkingConfig: { thinkingLevel: "medium" },
          },
        }),
      },
    );
    if (!response.ok) throw new Error("gemini_chat_failed");
    const payload = await response.json() as Record<string, unknown>;
    const candidates = payload.candidates;
    const parts = Array.isArray(candidates)
      ? ((candidates[0] as Record<string, unknown>)?.content as Record<string, unknown> | undefined)
        ?.parts
      : undefined;
    if (!Array.isArray(parts) || typeof (parts[0] as Record<string, unknown>)?.text !== "string") {
      throw new Error("gemini_chat_invalid");
    }
    const parsed = parseCoachChatAnswer(
      JSON.parse((parts[0] as Record<string, string>).text),
      permitted,
    );
    const usage = payload.usageMetadata as Record<string, unknown> | undefined;
    const inputUnits = Number.isInteger(usage?.promptTokenCount)
      ? Number(usage?.promptTokenCount)
      : 0;
    const outputUnits = Number.isInteger(usage?.candidatesTokenCount)
      ? Number(usage?.candidatesTokenCount)
      : 0;
    const inputRate = Number(Deno.env.get("GEMINI_INPUT_COST_PER_MILLION_USD") ?? "1.5");
    const outputRate = Number(Deno.env.get("GEMINI_OUTPUT_COST_PER_MILLION_USD") ?? "9");
    return {
      answer: parsed,
      provider: "gemini",
      model,
      inputUnits,
      outputUnits,
      estimatedCostUsd: (inputUnits * inputRate + outputUnits * outputRate) / 1_000_000,
    };
  } catch {
    return {
      answer: fallbackAnswer(context),
      provider: "mock",
      model: "deterministic-chat-fallback-v1",
      inputUnits: 0,
      outputUnits: 0,
      estimatedCostUsd: 0,
    };
  } finally {
    clearTimeout(timeout);
  }
}
