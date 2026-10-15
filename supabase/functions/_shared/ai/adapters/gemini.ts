import type { GeminiModel } from "../models.ts";
import type { AiContent } from "../types.ts";
import { type Adapter, record, textOf, tokenCount } from "./adapter.ts";

// Gemini generateContent, the request shape of providers/gemini_*_provider.ts. JSON output uses
// responseJsonSchema; thinking maps to thinkingConfig.thinkingLevel. Cache flags are ignored
// (Gemini caches implicitly). No temperature is sent.

export const geminiApiBase = "https://generativelanguage.googleapis.com/v1beta/models";

const part = (item: AiContent): Record<string, unknown> =>
  item.type === "text"
    ? { text: item.text }
    : { inlineData: { mimeType: item.mediaType, data: item.base64 } };

export const geminiAdapter: Adapter<GeminiModel> = {
  build(request, spec, apiKey) {
    const { route } = request;
    const generationConfig: Record<string, unknown> = {
      maxOutputTokens: route.maxOutputTokens,
      thinkingConfig: {
        thinkingLevel: route.thinking === "adaptive"
          ? route.effort ?? "medium"
          : spec.thinkingOffLevel,
      },
    };
    if (request.output.kind === "json") {
      generationConfig.responseMimeType = "application/json";
      generationConfig.responseJsonSchema = request.output.schema;
    }
    const body: Record<string, unknown> = {
      contents: request.messages.map((message) => ({
        role: message.role === "assistant" ? "model" : "user",
        parts: message.content.map(part),
      })),
      generationConfig,
    };
    if (request.system.length > 0) {
      body.systemInstruction = { parts: [{ text: textOf(request.system) }] };
    }
    return {
      url: `${geminiApiBase}/${encodeURIComponent(route.model)}:generateContent`,
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body,
    };
  },

  read(payload) {
    const reply = record(payload);
    if (!reply) return null;
    const usage = record(reply.usageMetadata);
    const prompt = tokenCount(usage?.promptTokenCount);
    // Cached tokens are part of promptTokenCount; thinking tokens are billed as output.
    const cached = Math.min(prompt, tokenCount(usage?.cachedContentTokenCount));
    const tokens = {
      inputTokens: prompt - cached,
      outputTokens: tokenCount(usage?.candidatesTokenCount) +
        tokenCount(usage?.thoughtsTokenCount),
      cacheReadTokens: cached,
      cacheWriteTokens: 0,
    };
    const model = typeof reply.modelVersion === "string" ? reply.modelVersion : null;
    const candidate = Array.isArray(reply.candidates) ? record(reply.candidates[0]) : null;
    if (!candidate) {
      // A blocked prompt comes back with promptFeedback.blockReason and no candidate.
      return record(reply.promptFeedback)?.blockReason
        ? { text: "", finish: "refused", tokens, model }
        : null;
    }
    const parts = record(candidate.content)?.parts;
    const text = Array.isArray(parts)
      ? parts.map((item) => {
        const piece = record(item);
        return piece && piece.thought !== true && typeof piece.text === "string" ? piece.text : "";
      }).join("")
      : "";
    const finish = candidate.finishReason;
    return {
      text,
      finish: finish === "STOP"
        ? "end"
        : finish === "MAX_TOKENS"
        ? "max_tokens"
        : finish === "SAFETY" || finish === "PROHIBITED_CONTENT" || finish === "BLOCKLIST" ||
            finish === "SPII" || finish === "RECITATION"
        ? "refused"
        : "other",
      tokens,
      model,
    };
  },
};
