import type { AnthropicModel } from "../models.ts";
import type { AiContent } from "../types.ts";
import { type Adapter, record, tokenCount } from "./adapter.ts";

// Claude Messages API (https://platform.claude.com/docs/en/api/messages).
// Claude 5 models reject non-default sampling parameters and forced tool_choice, so the request
// never carries temperature, top_p, top_k, tools or tool_choice; JSON comes from
// output_config.format.

export const anthropicMessagesUrl = "https://api.anthropic.com/v1/messages";
export const anthropicVersion = "2023-06-01";

/** The API allows at most four cache_control breakpoints per request. */
const maxCacheBreakpoints = 4;

// Structured outputs return 400 for these keywords; the gateway still checks them on the answer.
const droppedSchemaKeywords = new Set([
  "minLength",
  "maxLength",
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "maxItems",
]);

// Values that are data, not subschemas.
const passedSchemaKeywords = new Set(["enum", "const", "required", "default", "examples"]);

/**
 * The schema as Claude accepts it: unsupported limits removed, every object closed
 * (additionalProperties other than false is rejected) and minItems kept only at 0 or 1.
 */
export function anthropicSchema(schema: unknown): unknown {
  if (Array.isArray(schema)) return schema.map(anthropicSchema);
  const node = record(schema);
  if (!node) return schema;
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(node)) {
    if (droppedSchemaKeywords.has(key)) continue;
    if (key === "minItems" && value !== 0 && value !== 1) continue;
    if (passedSchemaKeywords.has(key)) {
      result[key] = value;
    } else if (key === "properties") {
      const properties = record(value) ?? {};
      result[key] = Object.fromEntries(
        Object.entries(properties).map(([name, item]) => [name, anthropicSchema(item)]),
      );
    } else {
      result[key] = anthropicSchema(value);
    }
  }
  const types = Array.isArray(node.type) ? node.type : [node.type];
  if (types.includes("object")) result.additionalProperties = false;
  return result;
}

function block(part: AiContent): Record<string, unknown> {
  if (part.type === "image") {
    return {
      type: "image",
      source: { type: "base64", media_type: part.mediaType, data: part.base64 },
    };
  }
  return part.cache
    ? { type: "text", text: part.text, cache_control: { type: "ephemeral" } }
    : { type: "text", text: part.text };
}

export const anthropicAdapter: Adapter<AnthropicModel> = {
  build(request, spec, apiKey) {
    const { route } = request;
    const breakpoints = [...request.system, ...request.messages.flatMap((m) => m.content)]
      .filter((part) => part.type === "text" && part.cache).length;
    if (breakpoints > maxCacheBreakpoints) return null;

    const body: Record<string, unknown> = {
      model: route.model,
      max_tokens: route.maxOutputTokens,
      messages: request.messages.map((message) => ({
        role: message.role,
        content: message.content.map(block),
      })),
    };
    if (request.system.length > 0) body.system = request.system.map(block);
    if (route.thinking === "adaptive") {
      body.thinking = { type: "adaptive" };
    } else if (spec.thinkingOff !== "always_on") {
      body.thinking = { type: spec.thinkingOff };
    }
    const outputConfig: Record<string, unknown> = {};
    if (route.effort) outputConfig.effort = route.effort;
    if (request.output.kind === "json") {
      outputConfig.format = { type: "json_schema", schema: anthropicSchema(request.output.schema) };
    }
    if (Object.keys(outputConfig).length > 0) body.output_config = outputConfig;

    return {
      url: anthropicMessagesUrl,
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": anthropicVersion,
      },
      body,
    };
  },

  read(payload) {
    const message = record(payload);
    if (!message || !Array.isArray(message.content)) return null;
    const usage = record(message.usage);
    // Thinking blocks are skipped: the answer is the text blocks only.
    const text = message.content
      .map((item) => {
        const part = record(item);
        return part?.type === "text" && typeof part.text === "string" ? part.text : "";
      })
      .join("");
    const stop = message.stop_reason;
    return {
      text,
      finish: stop === "end_turn" || stop === "stop_sequence"
        ? "end"
        : stop === "max_tokens"
        ? "max_tokens"
        : stop === "refusal"
        ? "refused"
        : "other",
      tokens: {
        inputTokens: tokenCount(usage?.input_tokens),
        outputTokens: tokenCount(usage?.output_tokens),
        cacheReadTokens: tokenCount(usage?.cache_read_input_tokens),
        cacheWriteTokens: tokenCount(usage?.cache_creation_input_tokens),
      },
      model: typeof message.model === "string" ? message.model : null,
    };
  },
};
