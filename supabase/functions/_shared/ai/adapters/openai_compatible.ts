import type { OpenAiCompatibleModel } from "../models.ts";
import type { AiContent } from "../types.ts";
import { type Adapter, record, textOf, tokenCount } from "./adapter.ts";

// OpenAI-compatible chat completions (DeepSeek, Groq), the request shape of
// providers/onboarding_plan_provider.ts and groq_meal_vision_provider.ts. JSON output uses
// JSON mode (`response_format: {type: "json_object"}`), the mode both providers serve; the
// schema belongs in the prompt and the gateway checks the answer against it. Cache flags are
// ignored: DeepSeek caches prefixes on its own. No temperature is sent.

function content(parts: readonly AiContent[]): string | Record<string, unknown>[] {
  if (parts.every((part) => part.type === "text")) return textOf(parts);
  return parts.map((part) =>
    part.type === "text"
      ? { type: "text", text: part.text }
      : { type: "image_url", image_url: { url: `data:${part.mediaType};base64,${part.base64}` } }
  );
}

export const openAiCompatibleAdapter: Adapter<OpenAiCompatibleModel> = {
  build(request, spec, apiKey) {
    const { route } = request;
    const thinking = spec.thinking[route.thinking];
    if (!route.baseUrl || thinking === null) return null;
    const messages: Record<string, unknown>[] = [];
    if (request.system.length > 0) {
      messages.push({ role: "system", content: textOf(request.system) });
    }
    for (const message of request.messages) {
      messages.push({ role: message.role, content: content(message.content) });
    }
    const body: Record<string, unknown> = {
      model: route.model,
      [spec.maxTokensField]: route.maxOutputTokens,
      ...thinking,
      messages,
    };
    if (request.output.kind === "json") body.response_format = { type: "json_object" };
    return {
      url: `${route.baseUrl}/chat/completions`,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
      body,
    };
  },

  read(payload) {
    const reply = record(payload);
    const choice = Array.isArray(reply?.choices) ? record(reply.choices[0]) : null;
    const message = record(choice?.message);
    if (!reply || !choice || !message) return null;
    const usage = record(reply.usage);
    const prompt = tokenCount(usage?.prompt_tokens);
    // DeepSeek reports prompt_cache_hit_tokens; OpenAI-style APIs report
    // prompt_tokens_details.cached_tokens. Both are part of prompt_tokens.
    const cached = Math.min(
      prompt,
      tokenCount(usage?.prompt_cache_hit_tokens) ||
        tokenCount(record(usage?.prompt_tokens_details)?.cached_tokens),
    );
    const finish = choice.finish_reason;
    return {
      text: typeof message.content === "string" ? message.content : "",
      finish: finish === "stop"
        ? "end"
        : finish === "length"
        ? "max_tokens"
        : finish === "content_filter"
        ? "refused"
        : "other",
      tokens: {
        inputTokens: prompt - cached,
        // Reasoning tokens are part of completion_tokens and billed as output.
        outputTokens: tokenCount(usage?.completion_tokens),
        cacheReadTokens: cached,
        cacheWriteTokens: 0,
      },
      model: typeof reply.model === "string" ? reply.model : null,
    };
  },
};
