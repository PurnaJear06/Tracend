// Shared by the router client and the Coach's request rewriting (live_model.ts): the modes a model
// may be asked in, and the JSON object inside a model's text.

/** How a model is asked: the router may reject response_format or the max_tokens name for a model. */
export type ChatMode = Readonly<{
  /** Send response_format json_object when the request asks for JSON. */
  responseFormat: boolean;
  maxTokensField: "max_tokens" | "max_completion_tokens";
  /**
   * Send the answer schema as `response_format: {type: "json_schema"}` (structured output, as
   * production asks Claude) instead of a bare JSON object. Only the Coach has a schema.
   */
  structured?: boolean;
  /**
   * Claude's Messages API directly (no router): the Coach through the production gateway's own
   * Claude request, the athlete and the judges with JSON asked in the prompt.
   */
  messages?: boolean;
}>;

export const defaultChatMode: ChatMode = Object.freeze({
  responseFormat: true,
  maxTokensField: "max_tokens",
});

/** The Coach's first choice: the answer schema enforced by the router, as production does. */
export const structuredMode: ChatMode = Object.freeze({
  responseFormat: true,
  maxTokensField: "max_tokens",
  structured: true,
});

/** The direct run's one mode: Claude's Messages API with Anthropic's key (anthropic_client.ts). */
export const messagesMode: ChatMode = Object.freeze({
  responseFormat: false,
  maxTokensField: "max_tokens",
  messages: true,
});

/** The modes tried in order when a call fails: the run's own mode first. */
export const chatModes: readonly ChatMode[] = [
  defaultChatMode,
  { responseFormat: false, maxTokensField: "max_tokens" },
  { responseFormat: true, maxTokensField: "max_completion_tokens" },
  { responseFormat: false, maxTokensField: "max_completion_tokens" },
];

export const describeMode = (mode: ChatMode) =>
  mode.messages
    ? "Claude Messages API (Anthropic directly)"
    : `${
      mode.structured
        ? "structured output (response_format json_schema)"
        : mode.responseFormat
        ? "JSON mode (response_format)"
        : "plain text, JSON asked in the prompt"
    }, ${mode.maxTokensField}`;

/**
 * The JSON object in a model's text: the whole text, or the first fenced block, or the outermost
 * braces. Null when none parses to an object.
 */
export function jsonObjectIn(text: string): Record<string, unknown> | null {
  const candidates = [
    text.trim(),
    text.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1]?.trim(),
    text.includes("{") ? text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1) : undefined,
  ];
  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed;
    } catch {
      // The next candidate.
    }
  }
  return null;
}
