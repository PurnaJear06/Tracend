// 1.1 clients render the labeled data-summary reply; 1.0 clients keep the 503.
export const coachChatRequestSchemaVersions = ["1.0", "1.1"] as const;

export type CoachChatRequestV1 = Readonly<{
  schema_version: typeof coachChatRequestSchemaVersions[number];
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

// Hard ceilings. Formatting limits are generous on purpose: an answer that is
// accurate but a little long must not be thrown away. The prompt still asks for
// short items (coachChatPreferredLengths); accuracy rules stay strict.
export const coachChatAnswerLimits = Object.freeze({
  answerMaxLength: 12_000,
  evidenceMaxItems: 20,
  evidenceLabelMaxLength: 400,
  missingDataMaxItems: 12,
  missingDataItemMaxLength: 300,
  followUpsMaxItems: 6,
  followUpMaxLength: 300,
  reasoningMaxItems: 10,
  reasoningStepMaxLength: 200,
  reasoningValueMaxLength: 400,
});

export const coachChatPreferredLengths = Object.freeze({
  reasoningStep: 80,
  reasoningValue: 160,
  followUp: 120,
  missingDataItem: 120,
});

export const coachChatSafetyStates = ["allowed", "limited", "refused", "unavailable"] as const;
export const coachChatEvidenceSources = [
  "feature_snapshot",
  "policy_evaluation",
  "coach_context",
] as const;

export const coachChatValidationRules = [
  "json_syntax",
  "invalid_root",
  "unexpected_keys",
  "answer_invalid",
  "answer_too_long",
  "safety_state_invalid",
  "evidence_not_array",
  "evidence_too_many",
  "evidence_item_invalid",
  "evidence_unexpected_keys",
  "evidence_code_not_permitted",
  "evidence_label_invalid",
  "evidence_label_too_long",
  "evidence_source_invalid",
  "missing_data_not_array",
  "missing_data_too_many",
  "missing_data_item_invalid",
  "missing_data_item_too_long",
  "follow_ups_not_array",
  "follow_ups_too_many",
  "follow_up_invalid",
  "follow_up_too_long",
  "reasoning_not_array",
  "reasoning_too_many",
  "reasoning_item_invalid",
  "reasoning_unexpected_keys",
  "reasoning_step_invalid",
  "reasoning_step_too_long",
  "reasoning_value_invalid",
  "reasoning_value_too_long",
  "reasoning_evidence_invalid",
  "reasoning_evidence_not_permitted",
] as const;

export type CoachChatValidationRule = typeof coachChatValidationRules[number];

export class CoachChatAnswerValidationError extends Error {
  constructor(
    readonly rule: CoachChatValidationRule,
    readonly path: string,
    readonly limit?: number,
    readonly actual?: number,
  ) {
    super(`invalid_chat_answer:${rule}:${path}`);
    this.name = "CoachChatAnswerValidationError";
  }
}

function invalid(
  rule: CoachChatValidationRule,
  path: string,
  limit?: number,
  actual?: number,
): never {
  throw new CoachChatAnswerValidationError(rule, path, limit, actual);
}

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
    !coachChatRequestSchemaVersions.includes(
      input.schema_version as typeof coachChatRequestSchemaVersions[number],
    ) || typeof input.thread_id !== "string" ||
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
    invalid("invalid_root", "$");
  }
  const answer = value as Record<string, unknown>;
  const requiredKeys = "answer,evidence,missing_data,safety_state,suggested_follow_ups";
  const keys = Object.keys(answer).filter((k) => k !== "reasoning_chain").sort().join(",");
  if (keys !== requiredKeys) {
    invalid("unexpected_keys", "$");
  }
  if (typeof answer.answer !== "string" || answer.answer.trim().length < 1) {
    invalid("answer_invalid", "answer");
  }
  if (answer.answer.length > coachChatAnswerLimits.answerMaxLength) {
    invalid(
      "answer_too_long",
      "answer",
      coachChatAnswerLimits.answerMaxLength,
      answer.answer.length,
    );
  }
  if (
    !coachChatSafetyStates.includes(answer.safety_state as typeof coachChatSafetyStates[number])
  ) {
    invalid("safety_state_invalid", "safety_state");
  }
  if (!Array.isArray(answer.evidence)) invalid("evidence_not_array", "evidence");
  if (answer.evidence.length > coachChatAnswerLimits.evidenceMaxItems) {
    invalid(
      "evidence_too_many",
      "evidence",
      coachChatAnswerLimits.evidenceMaxItems,
      answer.evidence.length,
    );
  }
  if (!Array.isArray(answer.missing_data)) invalid("missing_data_not_array", "missing_data");
  if (answer.missing_data.length > coachChatAnswerLimits.missingDataMaxItems) {
    invalid(
      "missing_data_too_many",
      "missing_data",
      coachChatAnswerLimits.missingDataMaxItems,
      answer.missing_data.length,
    );
  }
  for (const [index, item] of answer.missing_data.entries()) {
    if (typeof item !== "string") invalid("missing_data_item_invalid", `missing_data[${index}]`);
    if (item.length > coachChatAnswerLimits.missingDataItemMaxLength) {
      invalid(
        "missing_data_item_too_long",
        `missing_data[${index}]`,
        coachChatAnswerLimits.missingDataItemMaxLength,
        item.length,
      );
    }
  }
  if (!Array.isArray(answer.suggested_follow_ups)) {
    invalid("follow_ups_not_array", "suggested_follow_ups");
  }
  if (answer.suggested_follow_ups.length > coachChatAnswerLimits.followUpsMaxItems) {
    invalid(
      "follow_ups_too_many",
      "suggested_follow_ups",
      coachChatAnswerLimits.followUpsMaxItems,
      answer.suggested_follow_ups.length,
    );
  }
  for (const [index, item] of answer.suggested_follow_ups.entries()) {
    if (typeof item !== "string") invalid("follow_up_invalid", `suggested_follow_ups[${index}]`);
    if (item.length > coachChatAnswerLimits.followUpMaxLength) {
      invalid(
        "follow_up_too_long",
        `suggested_follow_ups[${index}]`,
        coachChatAnswerLimits.followUpMaxLength,
        item.length,
      );
    }
  }
  for (const [index, item] of answer.evidence.entries()) {
    const path = `evidence[${index}]`;
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      invalid("evidence_item_invalid", path);
    }
    const evidence = item as Record<string, unknown>;
    if (Object.keys(evidence).sort().join(",") !== "code,label,source") {
      invalid("evidence_unexpected_keys", path);
    }
    if (typeof evidence.code !== "string" || !permittedEvidence.includes(evidence.code)) {
      invalid("evidence_code_not_permitted", `${path}.code`);
    }
    if (typeof evidence.label !== "string") invalid("evidence_label_invalid", `${path}.label`);
    if (evidence.label.length > coachChatAnswerLimits.evidenceLabelMaxLength) {
      invalid(
        "evidence_label_too_long",
        `${path}.label`,
        coachChatAnswerLimits.evidenceLabelMaxLength,
        evidence.label.length,
      );
    }
    if (
      !coachChatEvidenceSources.includes(evidence.source as typeof coachChatEvidenceSources[number])
    ) {
      invalid("evidence_source_invalid", `${path}.source`);
    }
  }
  if (answer.reasoning_chain !== undefined) {
    if (!Array.isArray(answer.reasoning_chain)) {
      invalid("reasoning_not_array", "reasoning_chain");
    }
    if (answer.reasoning_chain.length > coachChatAnswerLimits.reasoningMaxItems) {
      invalid(
        "reasoning_too_many",
        "reasoning_chain",
        coachChatAnswerLimits.reasoningMaxItems,
        answer.reasoning_chain.length,
      );
    }
    for (const [index, item] of answer.reasoning_chain.entries()) {
      const path = `reasoning_chain[${index}]`;
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        invalid("reasoning_item_invalid", path);
      }
      const step = item as Record<string, unknown>;
      if (Object.keys(step).sort().join(",") !== "evidence_id,step,value") {
        invalid("reasoning_unexpected_keys", path);
      }
      if (typeof step.step !== "string") invalid("reasoning_step_invalid", `${path}.step`);
      if (step.step.length > coachChatAnswerLimits.reasoningStepMaxLength) {
        invalid(
          "reasoning_step_too_long",
          `${path}.step`,
          coachChatAnswerLimits.reasoningStepMaxLength,
          step.step.length,
        );
      }
      if (typeof step.value !== "string") invalid("reasoning_value_invalid", `${path}.value`);
      if (step.value.length > coachChatAnswerLimits.reasoningValueMaxLength) {
        invalid(
          "reasoning_value_too_long",
          `${path}.value`,
          coachChatAnswerLimits.reasoningValueMaxLength,
          step.value.length,
        );
      }
      if (step.evidence_id !== null && typeof step.evidence_id !== "string") {
        invalid("reasoning_evidence_invalid", `${path}.evidence_id`);
      }
      if (typeof step.evidence_id === "string" && !permittedEvidence.includes(step.evidence_id)) {
        invalid("reasoning_evidence_not_permitted", `${path}.evidence_id`);
      }
    }
  }
  return answer as unknown as CoachChatAnswerV2;
}
