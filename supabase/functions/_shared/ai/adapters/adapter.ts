import type { TokenCounts } from "../models.ts";
import type { AiContent, AiRequest } from "../types.ts";

/** One HTTP request to a provider. */
export type ProviderCall = Readonly<{
  url: string;
  headers: Record<string, string>;
  body: Record<string, unknown>;
}>;

/** A provider's 200 answer, mapped to the gateway's terms. */
export type ProviderAnswer = Readonly<{
  text: string;
  /** other = a stop the gateway never asks for (tool use, context overflow, ...). */
  finish: "end" | "max_tokens" | "refused" | "other";
  tokens: TokenCounts;
  /** The model the provider says answered, when it says. */
  model: string | null;
}>;

export type Adapter<Spec> = Readonly<{
  /** null when this provider cannot express the request; nothing is sent. */
  build(request: AiRequest, spec: Spec, apiKey: string): ProviderCall | null;
  /**
   * null when the payload is not an answer at all. A billed answer whose shape is wrong is
   * finish "other" with the usage it reported.
   */
  read(payload: unknown): ProviderAnswer | null;
}>;

export const tokenCount = (value: unknown): number =>
  typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : 0;

export const record = (value: unknown): Record<string, unknown> | null =>
  typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;

/**
 * Text parts as one string for providers that take a single string. Blank lines keep stable and
 * volatile blocks apart.
 */
export const textOf = (content: readonly AiContent[]): string =>
  content.flatMap((part) => part.type === "text" ? [part.text] : []).join("\n\n");
