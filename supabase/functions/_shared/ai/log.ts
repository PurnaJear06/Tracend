import { createLogger } from "../logger.ts";
import type { AiFailure, AiFeature, AiProvider, AiUsage, AiVendor } from "./types.ts";

// One `ai_call` line per gateway call. Every field is a fixed name, a number or an enum value
// the gateway produced; prompt text, image data, reply text and provider error bodies never
// reach this function.

export type AiCallRecord = Readonly<{
  feature: AiFeature;
  provider: AiProvider;
  vendor: AiVendor;
  model: string;
  outcome: "ok" | AiFailure;
  usage: AiUsage | null;
  latencyMs: number;
  /** The provider's HTTP status, when a response arrived. */
  httpStatus: number | null;
  stop: "end" | "max_tokens" | null;
}>;

/** Model ids are configuration, but they are clipped to an id's characters all the same. */
const modelId = (model: string) => model.replace(/[^A-Za-z0-9._:/-]/g, "").slice(0, 80);

export function aiCallFields(record: AiCallRecord): Record<string, unknown> {
  return {
    feature: record.feature,
    provider: record.provider,
    vendor: record.vendor,
    model: modelId(record.model),
    outcome: record.outcome,
    input_tokens: record.usage?.inputTokens ?? null,
    output_tokens: record.usage?.outputTokens ?? null,
    cache_read_tokens: record.usage?.cacheReadTokens ?? null,
    cache_write_tokens: record.usage?.cacheWriteTokens ?? null,
    cost_usd: record.usage?.costUsd ?? null,
    latency_ms: Math.max(0, Math.round(record.latencyMs)),
    http_status: record.httpStatus,
    stop: record.stop,
  };
}

export function logAiCall(record: AiCallRecord): void {
  const logger = createLogger();
  if (record.outcome === "ok") {
    logger.info("ai_call", aiCallFields(record));
  } else {
    logger.warn("ai_call", aiCallFields(record));
  }
}
