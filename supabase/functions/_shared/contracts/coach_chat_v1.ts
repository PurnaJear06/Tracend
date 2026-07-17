export type CoachChatRequestV1 = Readonly<{
  schema_version: "1.0";
  thread_id: string;
  question: string;
  timezone: string;
  idempotency_key: string;
}>;

export type CoachChatAnswerV1 = Readonly<{
  answer: string;
  evidence: readonly Readonly<{ code: string; label: string; source: string }>[];
  missing_data: readonly string[];
  safety_state: "allowed" | "limited" | "refused" | "unavailable";
  suggested_follow_ups: readonly string[];
}>;

export type ReasoningChainItem = Readonly<{
  step: string;
  value: string;
  evidence_id: string | null;
}>;

export type CoachChatAnswerV2 =
  & CoachChatAnswerV1
  & Readonly<{
    reasoning_chain?: readonly ReasoningChainItem[];
  }>;

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseCoachChatRequest(value: unknown): CoachChatRequestV1 {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_chat_request");
  }
  const input = value as Record<string, unknown>;
  const keys = Object.keys(input).sort().join(",");
  if (keys !== "idempotency_key,question,schema_version,thread_id,timezone") {
    throw new Error("invalid_chat_request");
  }
  if (
    input.schema_version !== "1.0" || typeof input.thread_id !== "string" ||
    !uuid.test(input.thread_id) || typeof input.idempotency_key !== "string" ||
    !uuid.test(input.idempotency_key) || typeof input.question !== "string" ||
    input.question.trim().length < 1 || input.question.length > 2000 ||
    typeof input.timezone !== "string" || input.timezone.length < 1 ||
    input.timezone.length > 64
  ) throw new Error("invalid_chat_request");
  return input as unknown as CoachChatRequestV1;
}

export function parseCoachChatAnswer(
  value: unknown,
  permittedEvidence: readonly string[],
): CoachChatAnswerV2 {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_chat_answer");
  }
  const answer = value as Record<string, unknown>;
  const requiredKeys = "answer,evidence,missing_data,safety_state,suggested_follow_ups";
  const keys = Object.keys(answer).filter((k) => k !== "reasoning_chain").sort().join(",");
  if (keys !== requiredKeys) {
    throw new Error("invalid_chat_answer");
  }
  if (
    typeof answer.answer !== "string" || answer.answer.trim().length < 1 ||
    answer.answer.length > 12000 ||
    !["allowed", "limited", "refused", "unavailable"].includes(String(answer.safety_state)) ||
    !Array.isArray(answer.evidence) || answer.evidence.length > 12 ||
    !Array.isArray(answer.missing_data) || answer.missing_data.length > 12 ||
    !answer.missing_data.every((item) => typeof item === "string" && item.length <= 120) ||
    !Array.isArray(answer.suggested_follow_ups) || answer.suggested_follow_ups.length > 4 ||
    !answer.suggested_follow_ups.every((item) => typeof item === "string" && item.length <= 160)
  ) throw new Error("invalid_chat_answer");
  for (const item of answer.evidence) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("invalid_chat_answer");
    }
    const evidence = item as Record<string, unknown>;
    if (
      Object.keys(evidence).sort().join(",") !== "code,label,source" ||
      typeof evidence.code !== "string" || !permittedEvidence.includes(evidence.code) ||
      typeof evidence.label !== "string" || evidence.label.length > 240 ||
      !["feature_snapshot", "policy_evaluation", "coach_context"].includes(String(evidence.source))
    ) throw new Error("invalid_chat_answer");
  }
  if (answer.reasoning_chain !== undefined) {
    if (!Array.isArray(answer.reasoning_chain) || answer.reasoning_chain.length > 6) {
      throw new Error("invalid_chat_answer");
    }
    for (const item of answer.reasoning_chain) {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        throw new Error("invalid_chat_answer");
      }
      const step = item as Record<string, unknown>;
      if (
        typeof step.step !== "string" || step.step.length > 80 ||
        typeof step.value !== "string" || step.value.length > 160 ||
        (step.evidence_id !== null && step.evidence_id !== undefined &&
          (typeof step.evidence_id !== "string" || !permittedEvidence.includes(step.evidence_id)))
      ) throw new Error("invalid_chat_answer");
    }
  }
  return answer as unknown as CoachChatAnswerV2;
}
