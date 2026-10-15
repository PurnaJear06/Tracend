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

// Structured outputs return 400 for these limits; the gateway still checks them on the answer.
// `format` is removed too (Claude accepts only some formats), as are annotations it has no use
// for.
const droppedSchemaKeywords = new Set([
  "minLength",
  "maxLength",
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "maxItems",
  "format",
  "default",
  "examples",
  "$schema",
]);

const isPrimitive = (value: unknown) => value === null || typeof value !== "object";

/**
 * The schema as Claude's structured outputs accept it, or null when Claude cannot take it.
 * Unsupported limits are removed (minItems is kept only at 0 or 1) and every object schema is
 * closed with additionalProperties false. Refused: an open map (`additionalProperties` true or
 * a schema) and an enum or const with an object or array value. The input has passed
 * isSupportedSchema.
 */
export function anthropicSchema(schema: Record<string, unknown>): Record<string, unknown> | null {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(schema)) {
    if (droppedSchemaKeywords.has(key)) continue;
    switch (key) {
      case "minItems":
        if (value === 0 || value === 1) result[key] = value;
        break;
      case "enum":
        if (!Array.isArray(value) || !value.every(isPrimitive)) return null;
        result[key] = value;
        break;
      case "const":
        if (!isPrimitive(value)) return null;
        result[key] = value;
        break;
      case "additionalProperties":
        if (value !== false) return null;
        break;
      case "properties": {
        const properties: Record<string, unknown> = {};
        for (const [name, item] of Object.entries(record(value) ?? {})) {
          const converted = anthropicSchema(record(item) ?? {});
          if (!converted) return null;
          properties[name] = converted;
        }
        result[key] = properties;
        break;
      }
      case "items": {
        const converted = anthropicSchema(record(value) ?? {});
        if (!converted) return null;
        result[key] = converted;
        break;
      }
      case "anyOf": {
        const options = (Array.isArray(value) ? value : []).map((item) =>
          anthropicSchema(record(item) ?? {})
        );
        if (options.some((option) => option === null)) return null;
        result[key] = options;
        break;
      }
      default:
        result[key] = value;
    }
  }
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  if (types.includes("object") || Object.hasOwn(schema, "properties")) {
    result.additionalProperties = false;
  }
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
    } else if (spec.thinkingOff !== null) {
      body.thinking = { type: spec.thinkingOff };
    } else {
      // route() refuses thinking "off" on a model that cannot turn it off.
      return null;
    }
    const outputConfig: Record<string, unknown> = {};
    if (route.effort) outputConfig.effort = route.effort;
    if (request.output.kind === "json") {
      const schema = anthropicSchema(request.output.schema);
      if (!schema) return null;
      outputConfig.format = { type: "json_schema", schema };
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
    const usage = record(message?.usage);
    const content = Array.isArray(message?.content) ? message?.content as unknown[] : null;
    if (!message || (!content && !usage)) return null;
    // Thinking blocks are skipped: the answer is the text blocks only.
    const text = (content ?? [])
      .map((item) => {
        const part = record(item);
        return part?.type === "text" && typeof part.text === "string" ? part.text : "";
      })
      .join("");
    const stop = message.stop_reason;
    return {
      text,
      // A billed answer without a content list keeps its usage as "other".
      finish: content === null
        ? "other"
        : stop === "end_turn" || stop === "stop_sequence"
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
