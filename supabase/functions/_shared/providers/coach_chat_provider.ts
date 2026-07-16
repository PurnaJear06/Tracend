import { type CoachChatAnswerV1, parseCoachChatAnswer } from "../contracts/coach_chat_v1.ts";

export type CoachChatGeneration = Readonly<{
  answer: CoachChatAnswerV1;
  provider: "mock" | "gemini" | "groq";
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
          source: {
            type: "string",
            enum: ["feature_snapshot", "policy_evaluation", "coach_context"],
          },
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

export class CoachChatUnavailableError extends Error {
  constructor(
    readonly provider: "mock" | "gemini" | "groq",
    readonly model: string,
  ) {
    super("coach_chat_unavailable");
  }
}

function collectEvidenceIds(value: unknown, target = new Set<string>()): Set<string> {
  if (Array.isArray(value)) {
    for (const item of value) collectEvidenceIds(item, target);
  } else if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      if (key === "evidence_id" && typeof item === "string") target.add(item);
      else collectEvidenceIds(item, target);
    }
  }
  return target;
}

const keyAbbreviations: Record<string, string> = {
  session_id: "sid",
  prescribed_workout: "w",
  duration_seconds: "dur",
  logging_completeness: "lc",
  session_effort: "eff",
  session_energy: "en",
  correction_status: "cs",
  local_date: "d",
  prescribed_name: "n",
  performed_name: "pn",
  kind: "k",
  status: "s",
  pain_flag: "p",
  exercise_order: "o",
  sets: "ss",
  set_number: "s",
  repetitions: "r",
  load_kg: "kg",
  rpe: "rpe",
  completed: "c",
  weight_kg: "w",
  body_fat_pct: "bf",
  steps_count: "st",
  resting_heart_rate_bpm: "rhr",
  hrv_sdnn_ms: "hrv",
  sleep_duration_hours: "sl",
  food_name: "f",
  serving_label: "s",
  calories: "cal",
  protein_g: "p",
  carbohydrate_g: "c",
  fat_g: "f",
  nutrition_adherence: "na",
  nutrition_compliance_7day: "nc7",
  days_with_confirmed_meals_7d: "dwm",
  confirmed_meal_count_7d: "cm7",
  schedule_slot_compliance: "ssc",
  scheduled_slots: "ss",
  matched_slots_today: "mst",
  last_photo_set: "lps",
  photo_sets_completed: "psc",
  has_physique_analysis: "hpa",
  avg_daily_carbohydrate_g: "adc",
  avg_daily_fat_g: "adf",
  days_with_meals: "dwm",
};

function compactValue(value: unknown): unknown {
  if (value === null) return undefined;
  if (Array.isArray(value)) {
    const compacted = value.map(compactValue).filter((v) => v !== undefined);
    return compacted.length === 0 ? undefined : compacted;
  }
  if (typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [key, val] of Object.entries(value as Record<string, unknown>)) {
      const compressed = compactValue(val);
      if (compressed !== undefined) {
        const abbr = keyAbbreviations[key] ?? key;
        if (abbr === "rationale" && typeof compressed === "string" && compressed.length > 120) {
          result[abbr] = compressed.slice(0, 120);
        } else {
          result[abbr] = compressed;
        }
      }
    }
    return Object.keys(result).length === 0 ? undefined : result;
  }
  return value;
}

export function compactContext(context: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(context)) {
    const compressed = compactValue(value);
    if (compressed !== undefined) {
      const abbr = keyAbbreviations[key] ?? key;
      result[abbr] = compressed;
    }
  }
  return result;
}

export function classifyQuestion(question: string): string {
  const q = question.toLowerCase();
  if (
    /weekly|new plan|change.{1,20}plan|plateau|progression|next block|program|routine|split|deload|periodiz/
      .test(q)
  ) return "plan_change";
  if (
    /recovery|rest|sleep|sore|fatigue|injur|hurt|pain|sick|fever|cold|ill|stress|energy/.test(q)
  ) return "recovery";
  if (
    /evidence|data|missing|gap|what's|explain|why|health|summary|trend|progress|tracking|logged|physique|visual progress|photo comparison|body composition/
      .test(q)
  ) return "explain_evidence";
  if (
    /nutrition|food|eat|diet|calories|protein|macro|meal|carb|fat|fiber|sodium|sugar|adherence|compliance|sticking to|diet plan/
      .test(q)
  ) return "nutrition_focus";
  if (/next|today|train|workout|schedule/.test(q)) {
    return "daily_action";
  }
  return "general";
}

export function isCoachChatLiveProviderConfigured(
  environment: Pick<typeof Deno.env, "get">,
): boolean {
  const enabled = environment.get("COACH_AI_ENABLED") === "true";
  const provider = environment.get("COACH_MODEL_PROVIDER") ?? "mock";
  if (provider === "groq") {
    return enabled && Boolean(environment.get("GROQ_API_KEY")) &&
      environment.get("GROQ_MODEL") === "qwen/qwen3.6-27b";
  }
  return provider === "gemini" && enabled &&
    environment.get("GEMINI_PAID_DATA_TERMS_ACCEPTED") === "true" &&
    Boolean(environment.get("GEMINI_API_KEY")) &&
    environment.get("GEMINI_MODEL") === "gemini-3.5-flash";
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
  const provider = Deno.env.get("COACH_MODEL_PROVIDER") ?? "mock";
  const paid = Deno.env.get("GEMINI_PAID_DATA_TERMS_ACCEPTED") === "true";
  const key = Deno.env.get("GEMINI_API_KEY") ?? "";
  const model = Deno.env.get("GEMINI_MODEL") ?? "";
  const policyEvidence = Array.isArray(context.permitted_evidence)
    ? context.permitted_evidence.filter((item): item is string => typeof item === "string")
    : [];
  const permitted = [...new Set([...policyEvidence, ...collectEvidenceIds(context)])];
  const groqKey = Deno.env.get("GROQ_API_KEY") ?? "";
  const groqModel = Deno.env.get("GROQ_MODEL") ?? "";
  const groqEnabled = provider === "groq" && enabled && groqKey && groqModel === "qwen/qwen3.6-27b";
  const geminiEnabled = provider === "gemini" && enabled && paid && key &&
    model === "gemini-3.5-flash";
  if (!isCoachChatLiveProviderConfigured(Deno.env) || (!groqEnabled && !geminiEnabled)) {
    throw new CoachChatUnavailableError("mock", "provider_not_configured");
  }
  const ctx = groqEnabled ? compactContext(context as Record<string, unknown>) : context;
  let bounded = JSON.stringify({ question, context: ctx });
  if (bounded.length > 22000) throw new Error("chat_context_too_large");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    if (groqEnabled) {
      let reasoningInputUnits = 0;
      let reasoningOutputUnits = 0;
      const planningQuestion = /weekly|new plan|change (my )?plan|plateau|progression|next block/i
        .test(question);
      if (planningQuestion) {
        const reasoningResponse = await fetcher(
          "https://api.groq.com/openai/v1/chat/completions",
          {
            method: "POST",
            signal: controller.signal,
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${groqKey}`,
            },
            body: JSON.stringify({
              model: groqModel,
              temperature: 0.1,
              max_completion_tokens: 2400,
              reasoning_effort: "high",
              reasoning_format: "hidden",
              response_format: { type: "json_object" },
              messages: [{
                role: "user",
                content:
                  "Analyze this personal training question using only the supplied context. Separate adherence, incomplete logging, recovery constraints, and ineffective programming. Return JSON with exactly analysis (string), evidence_ids (array using supplied evidence_id values), and recommendation (maintain, gather_data, or propose_change). Do not claim a persistent change.\n\n" +
                  bounded,
              }],
            }),
          },
        );
        if (!reasoningResponse.ok) throw new Error("groq_chat_reasoning_failed");
        const reasoningPayload = await reasoningResponse.json() as Record<string, unknown>;
        const reasoningMessage = Array.isArray(reasoningPayload.choices)
          ? (reasoningPayload.choices[0] as Record<string, unknown>)?.message as
            | Record<string, unknown>
            | undefined
          : undefined;
        if (typeof reasoningMessage?.content !== "string") {
          throw new Error("groq_chat_reasoning_invalid");
        }
        const analysis = JSON.parse(reasoningMessage.content) as Record<string, unknown>;
        if (
          Object.keys(analysis).sort().join(",") !== "analysis,evidence_ids,recommendation" ||
          typeof analysis.analysis !== "string" || analysis.analysis.length > 6000 ||
          !Array.isArray(analysis.evidence_ids) ||
          !analysis.evidence_ids.every((id) => typeof id === "string" && permitted.includes(id)) ||
          !["maintain", "gather_data", "propose_change"].includes(String(analysis.recommendation))
        ) throw new Error("groq_chat_reasoning_invalid");
        const usage = reasoningPayload.usage as Record<string, unknown> | undefined;
        reasoningInputUnits = Number.isInteger(usage?.prompt_tokens)
          ? Number(usage?.prompt_tokens)
          : 0;
        reasoningOutputUnits = Number.isInteger(usage?.completion_tokens)
          ? Number(usage?.completion_tokens)
          : 0;
        bounded = JSON.stringify({ question, context: ctx, validated_analysis: analysis });
      }
      const request = async (repair: boolean) => {
        const response = await fetcher("https://api.groq.com/openai/v1/chat/completions", {
          method: "POST",
          signal: controller.signal,
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${groqKey}` },
          body: JSON.stringify({
            model: groqModel,
            temperature: 0.15,
            max_completion_tokens: 2200,
            reasoning_effort: "none",
            reasoning_format: "hidden",
            response_format: { type: "json_object" },
            messages: [{
              role: "user",
              content:
                "You are Tracend's evidence-driven personal fitness coach for healthy adults. Respond like the user's continuing coach, not a generic chatbot. Lead with one clear recommendation, then give specific training, nutrition, recovery, and tracking actions supported by the prepared context. When relevant context exists, naturally reference at least two concrete personal facts such as the goal, approved targets, recent confirmed nutrition, check-in, HealthKit trend, measurement trend, or actual workout execution. Never claim a source is missing when context_coverage marks it available. Do not invent generic foods as if they are in the approved plan; name foods only when present in nutrition_schedule. Do not repeat generic disclaimers or merely redirect the user to the app. Distinguish a temporary daily adjustment from a persistent plan change. You may recommend conservative same-day execution changes, including rest or reduced training, but persistent plan or target changes require explicit user approval. For ordinary illness reports such as fever, cold, or cough: do not diagnose or prescribe treatment; do not tell the user to complete the scheduled workout; recommend pausing strenuous training while feverish, basic rest/hydration and an updated recovery check-in, and brief escalation guidance if symptoms are severe, worsening, or persistent. Answer only supplied training, nutrition, recovery, progress, evidence, and app-usage facts. State only important data that is genuinely absent. Never invent HealthKit values, meals, symptoms, or history, give medical treatment, or claim that a plan, target, meal, or durable fact was changed. Return only JSON matching: " +
                JSON.stringify(answerSchema) +
                "\nEvidence codes must exactly match either context.permitted_evidence or an evidence_id supplied in context. Use source coach_context for those stable IDs. Use an empty evidence list when none applies. Do not add markdown or any keys outside the schema." +
                (repair
                  ? "\nYour preceding response did not pass validation. Correct it using only the schema and prepared context."
                  : "") +
                "\n\nPrepared context:\n" + bounded,
            }],
          }),
        });
        if (!response.ok) throw new Error("groq_chat_failed");
        const payload = await response.json() as Record<string, unknown>;
        const message = Array.isArray(payload.choices)
          ? (payload.choices[0] as Record<string, unknown>)?.message as
            | Record<string, unknown>
            | undefined
          : undefined;
        if (typeof message?.content !== "string") throw new Error("groq_chat_invalid");
        const usage = payload.usage as Record<string, unknown> | undefined;
        return {
          content: message.content,
          inputUnits: Number.isInteger(usage?.prompt_tokens) ? Number(usage?.prompt_tokens) : 0,
          outputUnits: Number.isInteger(usage?.completion_tokens)
            ? Number(usage?.completion_tokens)
            : 0,
        };
      };
      const first = await request(false);
      let answer: CoachChatAnswerV1;
      let inputUnits = reasoningInputUnits + first.inputUnits;
      let outputUnits = reasoningOutputUnits + first.outputUnits;
      try {
        answer = parseCoachChatAnswer(JSON.parse(first.content), permitted);
      } catch {
        const repaired = await request(true);
        inputUnits += repaired.inputUnits;
        outputUnits += repaired.outputUnits;
        answer = parseCoachChatAnswer(JSON.parse(repaired.content), permitted);
      }
      const inputRate = Number(Deno.env.get("GROQ_INPUT_COST_PER_MILLION_USD") ?? "0.6");
      const outputRate = Number(Deno.env.get("GROQ_OUTPUT_COST_PER_MILLION_USD") ?? "3");
      return {
        answer,
        provider: "groq",
        model: groqModel,
        inputUnits,
        outputUnits,
        estimatedCostUsd: (inputUnits * inputRate + outputUnits * outputRate) / 1_000_000,
      };
    }
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
                "You are Tracend's evidence-driven personal fitness coach for healthy adults. Lead with one clear, practical recommendation grounded in the supplied history, then give specific training, nutrition, recovery, and tracking actions. Never merely redirect the user to the app or repeat generic disclaimers. You may recommend conservative same-day execution adjustments, including rest or reduced training; persistent plan or target changes require explicit approval. For fever, cold, or cough, do not diagnose or prescribe treatment and do not tell the user to complete the scheduled workout. Recommend pausing strenuous training while feverish, basic rest/hydration, an updated recovery check-in, and concise escalation guidance for severe, worsening, or persistent symptoms. Use only supplied facts and evidence codes. State important missing data. Never invent data or claim a durable change. Return only the requested JSON.",
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
    throw new CoachChatUnavailableError(
      provider === "groq" ? "groq" : provider === "gemini" ? "gemini" : "mock",
      provider === "groq" ? groqModel || "unconfigured" : model || "unconfigured",
    );
  } finally {
    clearTimeout(timeout);
  }
}
