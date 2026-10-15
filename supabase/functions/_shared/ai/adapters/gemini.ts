import type { GeminiModel } from "../models.ts";
import type { AiContent } from "../types.ts";
import { type Adapter, record, tokenCount } from "./adapter.ts";

// Gemini generateContent, with the request fields of providers/gemini_*_provider.ts: the
// model's sampling defaults (temperature 0.1) in generationConfig, JSON output through
// responseJsonSchema, thinking as thinkingConfig.thinkingLevel. Each system block is its own
// part. Cache flags are ignored (Gemini caches implicitly).

export const geminiApiBase = "https://generativelanguage.googleapis.com/v1beta/models";

const refusedFinishReasons = new Set([
  "SAFETY",
  "PROHIBITED_CONTENT",
  "BLOCKLIST",
  "SPII",
  "RECITATION",
  "IMAGE_SAFETY",
  "IMAGE_PROHIBITED_CONTENT",
]);

const part = (item: AiContent): Record<string, unknown> =>
  item.type === "text"
    ? { text: item.text }
    : { inlineData: { mimeType: item.mediaType, data: item.base64 } };

export const geminiAdapter: Adapter<GeminiModel> = {
  build(request, spec, apiKey) {
    const { route } = request;
    const generationConfig: Record<string, unknown> = {
      ...spec.generationDefaults,
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
    if (request.system.length > 0) body.systemInstruction = { parts: request.system.map(part) };
    return {
      url: `${geminiApiBase}/${encodeURIComponent(route.model)}:generateContent`,
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body,
    };
  },

  read(payload) {
    const reply = record(payload);
    const usage = record(reply?.usageMetadata);
    const candidate = Array.isArray(reply?.candidates) ? record(reply.candidates[0]) : null;
    if (!reply || (!candidate && !usage)) return null;
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
    if (!candidate) {
      // A blocked prompt comes back with promptFeedback.blockReason and no candidate; any other
      // billed answer without a candidate keeps its usage as "other".
      const blocked = Boolean(record(reply.promptFeedback)?.blockReason);
      return { text: "", finish: blocked ? "refused" : "other", tokens, model };
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
        : typeof finish === "string" && refusedFinishReasons.has(finish)
        ? "refused"
        : "other",
      tokens,
      model,
    };
  },
};
