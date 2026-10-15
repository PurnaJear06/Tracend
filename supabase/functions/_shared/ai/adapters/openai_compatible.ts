import type { OpenAiCompatibleModel } from "../models.ts";
import type { AiContent } from "../types.ts";
import { type Adapter, record, textOf, tokenCount } from "./adapter.ts";

// OpenAI-compatible chat completions (DeepSeek, Groq, eval routers), with the request fields of
// today's providers (deepseek_coach_model_provider.ts, onboarding_plan_provider.ts,
// groq_meal_vision_provider.ts, physique_vision_provider.ts): the model's sampling defaults and
// thinking fields from models.ts, and JSON mode (`response_format: {type: "json_object"}`) with
// the schema restated in the system prompt, as those providers do. The gateway checks the answer
// against the schema. Cache flags are ignored: DeepSeek caches prefixes on its own.

/** The system line JSON mode adds; DeepSeek's JSON mode needs the word "JSON" in the prompt. */
export const jsonSchemaInstruction = (schema: Record<string, unknown>) =>
  `Return only valid JSON matching this schema: ${JSON.stringify(schema)}`;

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
    const { route, output } = request;
    const thinking = spec.thinking[route.thinking];
    if (!route.baseUrl || thinking === null) return null;
    const system = [textOf(request.system)].filter((text) => text !== "");
    if (output.kind === "json") system.push(jsonSchemaInstruction(output.schema));
    const messages: Record<string, unknown>[] = [];
    if (system.length > 0) messages.push({ role: "system", content: system.join("\n\n") });
    for (const message of request.messages) {
      messages.push({ role: message.role, content: content(message.content) });
    }
    const body: Record<string, unknown> = {
      model: route.model,
      [spec.maxTokensField]: route.maxOutputTokens,
      ...thinking,
    };
    if (route.thinking === "adaptive" && spec.reasoningEffort) {
      body[spec.reasoningEffort.field] = route.effort ?? spec.reasoningEffort.default;
    }
    if (output.kind === "json") body.response_format = { type: "json_object" };
    body.messages = messages;
    return {
      url: `${route.baseUrl}/chat/completions`,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
      body,
    };
  },

  read(payload) {
    const reply = record(payload);
    const usage = record(reply?.usage);
    const choice = Array.isArray(reply?.choices) ? record(reply.choices[0]) : null;
    const message = record(choice?.message);
    if (!reply || (!message && !usage)) return null;
    const prompt = tokenCount(usage?.prompt_tokens);
    // DeepSeek reports prompt_cache_hit_tokens; OpenAI-style APIs report
    // prompt_tokens_details.cached_tokens. Both are part of prompt_tokens.
    const cached = Math.min(
      prompt,
      tokenCount(usage?.prompt_cache_hit_tokens) ||
        tokenCount(record(usage?.prompt_tokens_details)?.cached_tokens),
    );
    const finish = choice?.finish_reason;
    return {
      text: typeof message?.content === "string" ? message.content : "",
      // A billed answer without a message keeps its usage as "other".
      finish: !message
        ? "other"
        : finish === "stop"
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
